import Foundation
import AVFoundation
import MediaPlayer
import UIKit

class AudioEngine: NSObject, ObservableObject {
    // MARK: - Publicado para la UI
    @Published var isPlaying: Bool = false {
        didSet {
            // Notificar cambios de estado para sincronizar con el centro de control
            if oldValue != isPlaying {
                NotificationCenter.default.post(name: NSNotification.Name("PlaybackStateChanged"), object: nil)
            }
        }
    }
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentSong: Song?
    @Published var currentRouteName: String = "Altavoz"

    // MARK: - Propiedades para la vista de calidad de audio
    @Published var sourceSampleRate: Double = 0
    @Published var outputSampleRate: Double = 0
    @Published var outputChannelCount: Int = 0
    @Published var audioQualityInfo: String = ""

    // MARK: - Propiedades para la cola y controles
    @Published var isShuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var playbackQueue: [Song] = []
    @Published var nextUpQueue: [Song] = []
    @Published var playHistory: [Song] = []

    // MARK: - Cola de reproducción interna
    private var playlist: [Song] = []
    private var originalPlaylist: [Song] = [] // Para restaurar orden original
    private(set) var currentIndex: Int = 0

    // MARK: - Motor de audio mejorado
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var displayTimer: Timer?
    private var nowPlayingInfoTimer: Timer?
    private var sampleRate: Double = 44100
    private var seekOffset: TimeInterval = 0

    // MARK: - Crossfade y Gapless Playback
    private var crossfadeTimer: Timer?
    private var crossfadeDuration: TimeInterval = 0.3 // segundos (reducido para mejor rendimiento)
    private var isCrossfading = false
    private var nextPlayerNode: AVAudioPlayerNode?
    private var nextAudioFile: AVAudioFile?
    @Published var isCrossfadeEnabled: Bool = false // Desactivado por defecto para estabilidad

    // MARK: - Equalizador
    private var equalizerNode: AVAudioUnitEQ?
    @Published var isEQEnabled: Bool = false
    @Published var eqPreset: EQPreset = .flat

    // MARK: - Flags para evitar ejecuciones simultáneas
    private var isChangingTrack = false
    private var isSeeking = false
    private var isStopping = false
    private var playbackErrorCount = 0

    // Generación de programación: invalida completion handlers huérfanos
    // que provocaban que las canciones se saltaran al cambiar de pista.
    private var scheduleGeneration = 0

    // MARK: - Reproductor de respaldo (AVPlayer)
    // Se usa cuando AVAudioFile/AVAudioEngine no puede abrir o reproducir un
    // archivo (códecs no soportados por AVAudioFile, errores -10868/-10875,
    // motor en estado inválido...). AVPlayer soporta más códecs y contenedores.
    private var avPlayer: AVPlayer?
    private var avTimeObserver: Any?
    private var avEndObserver: NSObjectProtocol?
    private var isUsingFallback = false

    // MARK: - Persistencia de estado
    private let stateDefaultsKey = "com.aurora.playbackState"
    private var hasRestored: Bool = false

    // MARK: - Init
    override init() {
        super.init()
        setupSession()
        setupEngine()
        setupEqualizer()
        observeRouteChanges()
        observeInterruptions()
        setupRemoteCommandCenter()
        setupBackgroundNotification()
        setupPlaybackStateObserver()
        loadPlaybackState()
    }

    // MARK: - Configuración inicial

    private func setupSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Configurar la sesión de audio con opciones de alta calidad
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay]
            )

            // Configurar para la mayor calidad de audio posible
            // Sample rate de 96kHz para soportar archivos Hi-Res sin downsampling
            try session.setPreferredSampleRate(96000)
            // Buffer de 10ms para mínima latencia y máxima fidelidad
            try session.setPreferredIOBufferDuration(0.01)

            try session.setActive(true, options: .notifyOthersOnDeactivation)
            updateRouteName()
            updateAudioQuality()

            AppLog.info(.playback, "Sesión de audio configurada: \(Int(session.sampleRate))Hz · buffer \(String(format: "%.0f", session.ioBufferDuration * 1000))ms")
        } catch {
            AppLog.error(.playback, error, context: "setupSession")
            // Fallback a configuración estándar si falla la alta calidad
            do {
                try session.setPreferredSampleRate(48000)
                try session.setPreferredIOBufferDuration(0.02)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                AppLog.error(.playback, error, context: "setupSession fallback")
            }
        }
    }

    private func setupEngine() {
        // Solo adjuntar el nodo; la conexión se configura en setupEqualizer()
        // para evitar dobles conexiones playerNode -> mainMixer y playerNode -> EQ.
        engine.attach(playerNode)
    }

    private func setupEqualizer() {
        // Si hay un EQ previo (recuperación de errores), desconectarlo primero
        if let existingEQ = equalizerNode {
            engine.detach(existingEQ)
        }

        equalizerNode = AVAudioUnitEQ(numberOfBands: 10)
        guard let eq = equalizerNode else { return }

        // Configurar bandas del equalizador
        let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        for (index, frequency) in frequencies.enumerated() {
            eq.bands[index].frequency = frequency
            eq.bands[index].bandwidth = 1.0
            eq.bands[index].filterType = .parametric
            eq.bands[index].gain = 0
            eq.bands[index].bypass = false
        }

        engine.attach(eq)
        engine.connect(playerNode, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
    }

    /// Reconecta el playerNode con el formato indicado, evitando dobles conexiones.
    /// Usa disconnectNodeOutput (no disconnectNodeInput) para liberar bien la conexión.
    private func reconnectPlayerNode(format: AVAudioFormat?) {
        if !engine.outputConnectionPoints(for: playerNode, outputBus: 0).isEmpty {
            engine.disconnectNodeOutput(playerNode)
        }
        if let eq = equalizerNode {
            engine.connect(playerNode, to: eq, format: format)
        } else {
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        }
    }

    private func setupBackgroundNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        // Recuperación ante cambios de configuración de audio (desconectar
        // auriculares, Bluetooth, llamadas): el motor puede detenerse y
        // quedarse "reproduciendo" en silencio si no se reinicia.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    @objc private func handleEngineConfigurationChange() {
        AppLog.warning(.playback, "Cambio de configuración de audio; reiniciando motor (isPlaying: \(isPlaying))")
        guard isPlaying, !isUsingFallback else { return } // AVPlayer gestiona rutas por sí solo

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                if !self.engine.isRunning {
                    try self.engine.start()
                }
                // Reanudar desde la posición actual (el motor reiniciado
                // pierde la programación del playerNode)
                let position = self.currentTime
                if let file = self.audioFile {
                    self.seekOffset = position
                    self.scheduleFile(file, from: AVAudioFramePosition(position * self.sampleRate))
                    AppLog.info(.playback, "Motor reiniciado y reproducción reanudada en \(String(format: "%.1f", position))s")
                } else {
                    self.playerNode.play()
                }
            } catch {
                AppLog.error(.playback, error, context: "handleEngineConfigurationChange")
            }
        }
    }

    @objc private func applicationWillResignActive() {
        saveState()
    }
    
    // MARK: - Observer para estado de reproducción
    private func setupPlaybackStateObserver() {
        // Observar cambios en el estado de reproducción para sincronizar con el centro de control
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateChanged),
            name: NSNotification.Name("PlaybackStateChanged"),
            object: nil
        )
        
        // También observar cuando la app entra en primer plano para sincronizar estado
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func playbackStateChanged() {
        // Actualizar el estado en el centro de control cuando cambie el estado de reproducción
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateNowPlayingInfo()
        }
    }
    
    @objc private func appDidBecomeActive() {
        // Sincronizar estado cuando la app vuelve a primer plano
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.updateNowPlayingInfo()
        }
    }

    // MARK: - Reproducción

    func play(song: Song, from songPlaylist: [Song]? = nil) {
        if let songPlaylist = songPlaylist {
            self.playlist = songPlaylist
            if let index = songPlaylist.firstIndex(where: { $0.id == song.id }) {
                currentIndex = index
            } else {
                self.playlist.insert(song, at: 0)
                currentIndex = 0
            }
        } else {
            self.playlist = [song]
            currentIndex = 0
        }

        updatePlaybackQueue()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.playCurrentSong()
        }
        saveState()
    }

    private func playCurrentSong() {
        guard currentIndex >= 0 && currentIndex < playlist.count else {
            stop()
            return
        }

        let song = playlist[currentIndex]
        AppLog.info(.playback, "Reproduciendo: \(song.displayName) [\(song.formatDescription)]")

        // Limpieza manual sin activar isStopping (evita interferencia con scheduleFile)
        // CRÍTICO: invalidar de inmediato cualquier completion pendiente del track
        // anterior. Si el nuevo track se reproduce por la vía AVPlayer (respaldo),
        // scheduleFile nunca se llama y el completion anterior seguiría vigente:
        // al dispararse vería isPlaying==true y pondría la app en "pausa"
        // mientras la música suena (bug de skip → estado en pausa).
        scheduleGeneration += 1
        stopFallbackPlayback()
        isUsingFallback = false
        if playerNode.isPlaying {
            playerNode.stop()
        }
        audioFile = nil
        isPlaying = false
        currentTime = 0
        seekOffset = 0
        stopDisplayTimer()

        // Verificar que el archivo exista antes de intentar abrirlo (evita crashes)
        guard FileManager.default.fileExists(atPath: song.url.path) else {
            AppLog.error(.playback, "Archivo no encontrado en: \(song.url.path)")
            handlePlaybackFailure(song: song)
            return
        }

        do {
            let file: AVAudioFile
            do {
                file = try AVAudioFile(forReading: song.url)
            } catch {
                let ns = error as NSError
                let hint: String
                switch ns.code {
                case -10868: hint = "formato de datos no soportado por AVAudioFile (códec o DRM)"
                case -10875: hint = "tipo de archivo no soportado"
                case -10864: hint = "archivo no encontrado o inaccesible"
                default: hint = "apertura fallida"
                }
                AppLog.error(.playback, error, context: "AVAudioFile [\(hint)]: \(song.displayName)")
                throw error
            }

            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            sourceSampleRate = sampleRate
            duration = Double(file.length) / sampleRate

            guard duration > 0, file.length > 0 else {
                // Canción inválida: saltar a la siguiente pero con límite de errores
                handlePlaybackFailure(song: song)
                return
            }

            // CRÍTICO: detener el motor ANTES de cambiar conexiones. Reconectar
            // con el motor corriendo provoca kAudioUnitErr_CannotDoInCurrentContext (-10868).
            if engine.isRunning {
                engine.stop()
            }
            playerNode.stop()

            // Reconectar nodos con el formato correcto (protegido contra desconexión doble)
            reconnectPlayerNode(format: file.processingFormat)

            do {
                try engine.start()
            } catch {
                AppLog.error(.playback, error, context: "engine.start() — reactivando sesión y reintentando")
                let session = AVAudioSession.sharedInstance()
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                try? session.setActive(true, options: .notifyOthersOnDeactivation)
                try engine.start()
            }

            AppLog.debug(.playback, "Formato: \(Int(file.processingFormat.sampleRate))Hz · \(file.processingFormat.channelCount) canales · \(file.length) frames")

            // Establecer estado ANTES de programar el archivo para que el completion handler funcione
            currentSong = song
            seekOffset = 0
            isPlaying = true
            playbackErrorCount = 0

            scheduleFile(file, from: 0)

            startDisplayTimer()
            updateNowPlayingInfo()
            updateAudioQuality()
            addToHistory(song)
            updateNextUpQueue()
            saveState()
        } catch {
            // Cualquier fallo del motor AVAudioEngine → reproductor de respaldo AVPlayer
            AppLog.error(.playback, error, context: "Motor AVAudioEngine con \(song.displayName); usando reproductor de respaldo")
            startFallbackPlayback(song: song)
        }
    }

    private func handlePlaybackFailure(song: Song) {
        playbackErrorCount += 1
        AppLog.error(.playback, "Fallo de reproducción #\(playbackErrorCount): \(song.displayName) — saltando a la siguiente")

        // Evitar bucle infinito si muchas canciones fallan seguidas
        if playbackErrorCount >= 5 {
            AppLog.error(.playback, "Demasiados errores consecutivos, deteniendo reproducción")
            stop()
            playbackErrorCount = 0
            return
        }

        // Resetear isChangingTrack para permitir que playNext() avance
        isChangingTrack = false
        isPlaying = false

        // Avanzar a la siguiente canción después de un breve delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            self.isChangingTrack = false
            self.playNext()
        }
    }

    // MARK: - Reproductor de respaldo (AVPlayer)

    private func stopFallbackPlayback() {
        if let observer = avTimeObserver {
            avPlayer?.removeTimeObserver(observer)
            avTimeObserver = nil
        }
        if let observer = avEndObserver {
            NotificationCenter.default.removeObserver(observer)
            avEndObserver = nil
        }
        avPlayer?.pause()
        avPlayer = nil
    }

    private func startFallbackPlayback(song: Song) {
        // Invalidar completions pendientes del motor: el track anterior se
        // reproducía por AVAudioEngine y su completion sigue en cola.
        scheduleGeneration += 1
        stopFallbackPlayback()
        if playerNode.isPlaying {
            playerNode.stop()
        }
        audioFile = nil
        stopDisplayTimer()

        isUsingFallback = true
        currentSong = song
        currentTime = 0
        duration = song.duration > 0 ? song.duration : 0
        seekOffset = 0
        playbackErrorCount = 0

        let player = AVPlayer(url: song.url)
        avPlayer = player

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        avTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, self.isUsingFallback else { return }
            let seconds = time.seconds
            if seconds.isFinite { self.currentTime = max(0, seconds) }
            if self.duration <= 0, let item = self.avPlayer?.currentItem, item.duration.isNumeric {
                self.duration = max(0, item.duration.seconds)
            }
        }
        avEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isUsingFallback else { return }
            self.handlePlaybackFinished()
        }

        avPlayer?.play()
        isPlaying = true

        startDisplayTimer()
        updateNowPlayingInfo()
        updateAudioQuality()
        addToHistory(song)
        updateNextUpQueue()
        saveState()

        AppLog.info(.playback, "Reproduciendo con AVPlayer (respaldo): \(song.displayName)")
    }

    private func scheduleFile(_ file: AVAudioFile, from startFrame: AVAudioFramePosition) {
        if playerNode.isPlaying {
            playerNode.stop()
        }

        // Nueva generación: cualquier completion handler anterior queda invalidado
        scheduleGeneration += 1
        let generation = scheduleGeneration

        // Proteger contra startFrame negativo o mayor que la duración del archivo
        let safeStartFrame = max(0, min(startFrame, file.length))
        let framesToPlay = AVAudioFrameCount(file.length - safeStartFrame)
        guard framesToPlay > 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.playNext()
            }
            return
        }

        // Configurar crossfade si no es la primera canción
        let timeRemaining = Double(file.length - safeStartFrame) / sampleRate
        if timeRemaining > crossfadeDuration && currentIndex > 0 {
            scheduleCrossfade(for: file, startFrame: safeStartFrame, framesToPlay: framesToPlay)
        }

        playerNode.scheduleSegment(
            file,
            startingFrame: safeStartFrame,
            frameCount: framesToPlay,
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                // Solo avanzar si esta programación sigue vigente y estábamos reproduciendo.
                // Evita que el completion del track anterior salte el track nuevo.
                guard let self = self,
                      self.scheduleGeneration == generation,
                      self.isPlaying,
                      !self.isStopping else { return }
                self.handlePlaybackFinished()
            }
        }

        playerNode.play()
    }

    // MARK: - Crossfade y Gapless Playback

    private func scheduleCrossfade(for file: AVAudioFile, startFrame: AVAudioFramePosition, framesToPlay: AVAudioFrameCount) {
        guard crossfadeDuration > 0, isCrossfadeEnabled else { return }

        let crossfadeStartFrame = AVAudioFramePosition(Double(file.length) - (crossfadeDuration * sampleRate))

        crossfadeTimer?.invalidate()
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self,
                  let nodeTime = self.playerNode.lastRenderTime,
                  let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else {
                self?.crossfadeTimer?.invalidate()
                return
            }

            let currentFrame = playerTime.sampleTime + AVAudioFramePosition(startFrame)
            if currentFrame >= crossfadeStartFrame && !self.isCrossfading {
                self.startCrossfadeToNext()
                self.crossfadeTimer?.invalidate()
            }
        }
    }

    private func startCrossfadeToNext() {
        guard !isCrossfading, currentIndex + 1 < playlist.count else { return }
        isCrossfading = true

        let nextIndex = currentIndex + 1
        let nextSong = playlist[nextIndex]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let nextFile = try AVAudioFile(forReading: nextSong.url)
                self.nextAudioFile = nextFile

                DispatchQueue.main.async {
                    self.setupNextPlayer(with: nextFile)
                }
            } catch {
                print("Error preparando crossfade: \(error.localizedDescription)")
                self.isCrossfading = false
            }
        }
    }

    private func setupNextPlayer(with file: AVAudioFile) {
        let nextPlayer = AVAudioPlayerNode()
        engine.attach(nextPlayer)

        if let eq = equalizerNode {
            engine.connect(nextPlayer, to: eq, format: file.processingFormat)
        } else {
            engine.connect(nextPlayer, to: engine.mainMixerNode, format: file.processingFormat)
        }

        nextPlayerNode = nextPlayer

        let framesToPlay = AVAudioFrameCount(file.length)
        nextPlayer.scheduleSegment(
            file,
            startingFrame: 0,
            frameCount: framesToPlay,
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.completeCrossfade()
            }
        }

        // Iniciar con volumen 0 y fade in
        nextPlayer.volume = 0
        nextPlayer.play()

        // Crossfade: fade out actual, fade in siguiente
        UIView.animate(withDuration: crossfadeDuration) {
            self.playerNode.volume = 0
            nextPlayer.volume = 1.0
        } completion: { _ in
            self.playerNode.stop()
            self.playerNode.volume = 1.0
        }
    }

    private func completeCrossfade() {
        guard let nextPlayer = nextPlayerNode else { return }
        guard currentIndex + 1 < playlist.count else {
            isCrossfading = false
            return
        }

        // Detener y desconectar el player anterior (una sola vez, sin dobles detach)
        playerNode.stop()
        if !engine.outputConnectionPoints(for: playerNode, outputBus: 0).isEmpty {
            engine.disconnectNodeOutput(playerNode)
        }
        engine.detach(playerNode)

        let currentFile = nextAudioFile
        audioFile = currentFile
        sampleRate = currentFile?.processingFormat.sampleRate ?? 44100
        duration = Double(currentFile?.length ?? 0) / sampleRate

        currentIndex += 1
        currentSong = playlist[currentIndex]
        seekOffset = 0
        scheduleGeneration += 1

        // Configurar el nuevo player como principal
        engine.attach(playerNode)
        reconnectPlayerNode(format: currentFile?.processingFormat)

        // Limpiar recursos
        engine.detach(nextPlayer)
        nextPlayerNode = nil
        nextAudioFile = nil
        isCrossfading = false

        updatePlaybackQueue()
        updateNextUpQueue()
        updateNowPlayingInfo()
        saveState()
    }

    // MARK: - Controles de cola

    func playNext() {
        guard !isChangingTrack else { return }
        isChangingTrack = true

        guard !playlist.isEmpty else {
            isChangingTrack = false
            return
        }

        let nextIndex = currentIndex + 1
        guard nextIndex < playlist.count else {
            if repeatMode == .all {
                currentIndex = 0
                playCurrentSong()
                isChangingTrack = false
                return
            }
            stop()
            isChangingTrack = false
            return
        }

        currentIndex = nextIndex
        playCurrentSong()
        updatePlaybackQueue()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isChangingTrack = false
        }
    }

    func playPrevious() {
        guard !isChangingTrack else { return }
        isChangingTrack = true

        guard !playlist.isEmpty else {
            isChangingTrack = false
            return
        }

        if currentTime > 3.0 {
            seek(to: 0)
            isChangingTrack = false
            return
        }

        let prevIndex = currentIndex - 1
        guard prevIndex >= 0 else {
            if repeatMode == .all {
                currentIndex = playlist.count - 1
                playCurrentSong()
                isChangingTrack = false
                return
            }
            isChangingTrack = false
            return
        }

        currentIndex = prevIndex
        playCurrentSong()
        updatePlaybackQueue()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isChangingTrack = false
        }
    }

    // MARK: - Shuffle mejorado
    func toggleShuffle() {
        isShuffleEnabled.toggle()
        if isShuffleEnabled {
            // Guardar el orden original antes de shuffle
            if originalPlaylist.isEmpty {
                originalPlaylist = playlist
            }

            // Algoritmo de shuffle mejorado que evita repeticiones cercanas
            let currentSong = playlist[currentIndex]
            var remainingSongs = playlist.filter { $0.id != currentSong.id }
            remainingSongs.shuffle()

            // Colocar la canción actual al inicio
            playlist = [currentSong] + remainingSongs
            currentIndex = 0

            AppLog.info(.playback, "Shuffle activado con algoritmo mejorado")
        } else {
            // Restaurar orden original
            if !originalPlaylist.isEmpty {
                let currentSong = playlist[currentIndex]
                playlist = originalPlaylist
                if let newIndex = playlist.firstIndex(where: { $0.id == currentSong.id }) {
                    currentIndex = newIndex
                }
                originalPlaylist = []
            }
            AppLog.info(.playback, "Shuffle desactivado, orden original restaurado")
        }
        updatePlaybackQueue()
        updateNextUpQueue()
    }

    // MARK: - Control de Crossfade
    func toggleCrossfade() {
        isCrossfadeEnabled.toggle()
        AppLog.info(.playback, "Crossfade: \(isCrossfadeEnabled ? "activado" : "desactivado")")
    }

    // MARK: - Next Up Queue
    private func updateNextUpQueue() {
        guard currentIndex < playlist.count else {
            nextUpQueue = []
            return
        }

        let nextIndex = currentIndex + 1
        guard nextIndex < playlist.count else {
            nextUpQueue = []
            return
        }

        let upcomingSongs = Array(playlist.suffix(from: nextIndex))
        nextUpQueue = Array(upcomingSongs.prefix(3)) // Reducido a 3 para mejor rendimiento
    }

    // MARK: - Historial de reproducción
    private func addToHistory(_ song: Song) {
        // Evitar duplicados consecutivos
        if let lastSong = playHistory.first, lastSong.id == song.id {
            return
        }

        playHistory.insert(song, at: 0)

        // Limitar historial a 50 canciones
        if playHistory.count > 50 {
            playHistory = Array(playHistory.prefix(50))
        }
    }

    func playFromHistory(_ song: Song) {
        // Encontrar la canción en la biblioteca actual
        if let index = playlist.firstIndex(where: { $0.id == song.id }) {
            currentIndex = index
            playCurrentSong()
        } else {
            // Si no está en la playlist actual, reproducirla sola
            play(song: song, from: [song])
        }
    }

    // MARK: - Repeat
    func cycleRepeatMode() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
        AppLog.info(.playback, "Repeat: \(repeatMode.rawValue)")
    }

    // MARK: - Equalizador
    func toggleEQ() {
        isEQEnabled.toggle()
        equalizerNode?.bypass = !isEQEnabled
        AppLog.info(.playback, "Equalizador: \(isEQEnabled ? "activado" : "desactivado")")
    }

    func setEQPreset(_ preset: EQPreset) {
        guard let eq = equalizerNode else { return }

        eqPreset = preset
        let gains = preset.gains

        for (index, gain) in gains.enumerated() {
            eq.bands[index].gain = gain
        }

        AppLog.info(.playback, "Preset EQ: \(preset.displayName)")
    }

    func setEQGain(for band: Int, gain: Float) {
        guard let eq = equalizerNode,
              band >= 0 && band < eq.bands.count else { return }

        eq.bands[band].gain = gain
    }

    func getEQGain(for band: Int) -> Float {
        guard let eq = equalizerNode,
              band >= 0 && band < eq.bands.count else { return 0 }

        return eq.bands[band].gain
    }

    // MARK: - Repeat handling mejorado
    private func shouldRepeatNext() -> Bool {
        switch repeatMode {
        case .all:
            return true
        case .one:
            return false
        case .off:
            return false
        }
    }

    private func updatePlaybackQueue() {
        playbackQueue = playlist
    }

    // MARK: - Pausa / Reanudar / Detener

    func pause() {
        if isUsingFallback {
            avPlayer?.pause()
            isPlaying = false
            stopDisplayTimer()
            DispatchQueue.main.async {
                self.updateNowPlayingInfo()
                var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
                MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
            }
            saveState()
            return
        }

        playerNode.pause()
        isPlaying = false
        stopDisplayTimer()
        
        // Actualizar inmediatamente el estado en el centro de control y pantalla de bloqueo
        DispatchQueue.main.async {
            self.updateNowPlayingInfo()
            // Forzar actualización del estado de reproducción
            var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
        }
        
        saveState()
    }

    func resume() {
        if isUsingFallback {
            guard avPlayer != nil else { return }
            avPlayer?.play()
            isPlaying = true
            startDisplayTimer()
            DispatchQueue.main.async {
                self.updateNowPlayingInfo()
                var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
                MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
            }
            saveState()
            return
        }

        guard let file = audioFile else {
            AppLog.warning(.playback, "resume() sin archivo cargado; ignorado")
            return
        }

        // Si el motor no está corriendo, reiniciarlo; si falla, reprogramar
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            AppLog.error(.playback, error, context: "resume(): motor no arrancó")
        }

        // Caso crítico: la programación terminó (playerTime == nil) pero la
        // UI seguía en pausa. Re-programar desde la posición actual, si no
        // play() no produce sonido y el usuario ve "reproduciendo" en silencio.
        let nodeTime = playerNode.lastRenderTime
        let playerTime = nodeTime.flatMap { playerNode.playerTime(forNodeTime: $0) }
        if playerTime == nil {
            let position = min(max(currentTime, 0), duration)
            AppLog.info(.playback, "resume(): reprogramando desde \(String(format: "%.1f", position))s (programación previa agotada)")
            seekOffset = position
            scheduleFile(file, from: AVAudioFramePosition(position * sampleRate))
            isPlaying = true
            startDisplayTimer()
            saveState()
            return
        }

        playerNode.play()
        isPlaying = true
        startDisplayTimer()
        
        // Actualizar inmediatamente el estado en el centro de control y pantalla de bloqueo
        DispatchQueue.main.async {
            self.updateNowPlayingInfo()
            // Forzar actualización del estado de reproducción
            var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
        }
        
        saveState()
    }

    func stop() {
        isStopping = true
        scheduleGeneration += 1 // Invalida completion handlers pendientes
        stopFallbackPlayback()
        isUsingFallback = false
        playerNode.stop()
        audioFile = nil
        isPlaying = false
        currentTime = 0
        seekOffset = 0
        stopDisplayTimer()
        
        // Limpiar información de now playing al detener completamente
        DispatchQueue.main.async {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        
        // Resetear flag después de un ciclo de runloop
        DispatchQueue.main.async { [weak self] in
            self?.isStopping = false
        }
    }

    func seek(to time: TimeInterval) {
        if isUsingFallback {
            guard let player = avPlayer else { return }
            let clamped = max(0, min(time, duration > 0 ? duration : time))
            let target = CMTime(seconds: clamped, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = clamped
            if isPlaying { avPlayer?.play() } // necesario para repeat-one tras llegar al final
            DispatchQueue.main.async {
                self.updateNowPlayingInfo()
            }
            saveState()
            return
        }

        guard let file = audioFile else { return }
        let clampedTime = max(0, min(time, duration))
        let startFrame = AVAudioFramePosition(clampedTime * sampleRate)

        seekOffset = clampedTime
        scheduleFile(file, from: startFrame)
        currentTime = clampedTime

        if !isPlaying {
            playerNode.pause()
        }

        // Actualizar inmediatamente el estado en el centro de control
        DispatchQueue.main.async {
            self.updateNowPlayingInfo()
            var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            currentInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = clampedTime
            currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? 1.0 : 0.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
        }
        
        saveState()
    }

    // MARK: - Progreso

    private func startDisplayTimer() {
        stopDisplayTimer()
        // Optimized: 0.5s is smooth enough for UI updates while halving CPU load
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
        }
        startNowPlayingInfoTimer()
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
        stopNowPlayingInfoTimer()
    }

    private func startNowPlayingInfoTimer() {
        stopNowPlayingInfoTimer()
        // Optimized: 2.0s is enough for lock screen updates, reduces CPU usage
        nowPlayingInfoTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
    }

    private func stopNowPlayingInfoTimer() {
        nowPlayingInfoTimer?.invalidate()
        nowPlayingInfoTimer = nil
    }

    private func updateCurrentTime() {
        if isUsingFallback {
            guard let player = avPlayer else { return }
            let seconds = player.currentTime().seconds
            if seconds.isFinite { currentTime = max(0, seconds) }
            return
        }

        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }

        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        currentTime = seekOffset + elapsed
    }

    private func handlePlaybackFinished() {
        guard !isStopping else { return }
        if isPlaying && !isChangingTrack {
            if repeatMode == .one {
                // seek(to:) ya reprograma y reanuda la reproducción desde 0;
                // llamar resume() aquí causaba doble programación del archivo.
                seek(to: 0)
                return
            }
            playNext()
        } else {
            isPlaying = false
            currentTime = 0
            stopDisplayTimer()
            updateNowPlayingInfo()
            saveState()
        }
    }

    // MARK: - Ruta de audio (Bluetooth, Jack, etc.)

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        updateRouteName()
        updateAudioQuality()
    }

    private func updateRouteName() {
        let session = AVAudioSession.sharedInstance()
        guard let output = session.currentRoute.outputs.first else { return }

        DispatchQueue.main.async {
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                self.currentRouteName = "Bluetooth: \(output.portName)"
            case .headphones:
                self.currentRouteName = "Audífonos (Jack 3.5mm): \(output.portName)"
            case .builtInSpeaker:
                self.currentRouteName = "Altavoz"
            default:
                self.currentRouteName = output.portName
            }
        }
    }

    private func updateAudioQuality() {
        let session = AVAudioSession.sharedInstance()
        DispatchQueue.main.async {
            self.outputSampleRate = session.sampleRate
            self.outputChannelCount = Int(session.outputNumberOfChannels)

            // Crear descripción de calidad de audio
            let rateInfo = session.sampleRate >= 48000 ? "Hi-Res" : "Estándar"
            let channelInfo = session.outputNumberOfChannels >= 2 ? "Estéreo" : "Mono"
            let qualityInfo = session.currentRoute.outputs.first?.portType == .bluetoothA2DP ? "Bluetooth" : "Interno"

            self.audioQualityInfo = "\(rateInfo) • \(Int(session.sampleRate))Hz • \(channelInfo) • \(qualityInfo)"
        }
    }

    // MARK: - Interrupciones (llamadas, Siri)

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            if isPlaying { pause() }
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Pantalla de bloqueo y Centro de Control

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Configurar comando de play
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, self.currentSong != nil else { return .noActionableNowPlayingItem }
            DispatchQueue.main.async {
                self.resume()
            }
            return .success
        }
        commandCenter.playCommand.isEnabled = true

        // Configurar comando de pause
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self, self.currentSong != nil else { return .noActionableNowPlayingItem }
            DispatchQueue.main.async {
                self.pause()
            }
            return .success
        }
        commandCenter.pauseCommand.isEnabled = true

        // Configurar comando de toggle play/pause
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self, self.currentSong != nil else { return .noActionableNowPlayingItem }
            DispatchQueue.main.async {
                if self.isPlaying {
                    self.pause()
                } else {
                    self.resume()
                }
            }
            return .success
        }
        commandCenter.togglePlayPauseCommand.isEnabled = true

        // Configurar comando de siguiente pista
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.playNext()
            }
            return .success
        }
        commandCenter.nextTrackCommand.isEnabled = true

        // Configurar comando de pista anterior
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.playPrevious()
            }
            return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true

        // Configurar comando de cambio de posición
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            DispatchQueue.main.async {
                self.seek(to: positionEvent.positionTime)
            }
            return .success
        }
        commandCenter.changePlaybackPositionCommand.isEnabled = true
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let artist = song.artist.isEmpty ? "Artista desconocido" : song.artist
        let album = song.album.isEmpty ? "" : song.album

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]

        if let artworkData = song.artworkData,
           let image = UIImage(data: artworkData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        // Asegurar que la actualización se realice en el hilo principal
        DispatchQueue.main.async {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            
            // Forzar actualización inmediata del estado de reproducción
            // Esto asegura que el centro de control y pantalla de bloqueo se actualicen correctamente
            DispatchQueue.main.async {
                if self.isPlaying {
                    var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    updatedInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                } else {
                    var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    updatedInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                }
            }
        }
    }

    // MARK: - Persistencia de estado

    func saveState() {
        guard let song = currentSong else {
            UserDefaults.standard.removeObject(forKey: stateDefaultsKey)
            return
        }

        let state: [String: Any] = [
            "songID": song.id.uuidString,
            "currentTime": currentTime,
            "isPlaying": isPlaying,
            "duration": duration
        ]
        UserDefaults.standard.set(state, forKey: stateDefaultsKey)
    }

    private func loadPlaybackState() {
        // La restauración se hace desde ContentView con restoreState
    }

    func restoreState(with allSongs: [Song]) {
        guard !hasRestored else { return }
        hasRestored = true // Marcar como restaurado para evitar reintentos

        guard let state = UserDefaults.standard.dictionary(forKey: stateDefaultsKey) else { return }
        guard let songIDString = state["songID"] as? String,
              let songID = UUID(uuidString: songIDString),
              let song = allSongs.first(where: { $0.id == songID }) else {
            // Si la biblioteca aún está cargando (vacía), NO borrar el estado:
            // ContentView reintentará cuando termine de cargar la caché.
            if !allSongs.isEmpty {
                UserDefaults.standard.removeObject(forKey: stateDefaultsKey)
            }
            hasRestored = false
            return
        }

        let savedTime = state["currentTime"] as? TimeInterval ?? 0
        let wasPlaying = state["isPlaying"] as? Bool ?? false

        self.playlist = allSongs
        if let index = allSongs.firstIndex(where: { $0.id == songID }) {
            self.currentIndex = index
        } else {
            self.playlist.insert(song, at: 0)
            self.currentIndex = 0
        }
        updatePlaybackQueue()

        // Reproducir desde el punto guardado
        do {
            let file = try AVAudioFile(forReading: song.url)
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            duration = Double(file.length) / sampleRate

            // Proteger contra desconexión doble (pasa por el EQ si está activo)
            reconnectPlayerNode(format: file.processingFormat)

            if !engine.isRunning {
                try engine.start()
            }

            let startFrame = AVAudioFramePosition(savedTime * sampleRate)
            scheduleFile(file, from: startFrame)

            currentSong = song
            seekOffset = savedTime
            currentTime = savedTime

            if wasPlaying {
                playerNode.play()
                isPlaying = true
                startDisplayTimer()
            } else {
                playerNode.pause()
                isPlaying = false
            }

            updateNowPlayingInfo()
            updateAudioQuality()
        } catch {
            // Al restaurar NO saltamos de canción: solo registramos y limpiamos el estado
            AppLog.error(.playback, error, context: "restoreState: \(song.displayName)")
            handleAudioError(error, context: "restoreState")
            audioFile = nil
            isPlaying = false
            UserDefaults.standard.removeObject(forKey: stateDefaultsKey)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // Ensure timers are invalidated before cleanup
        displayTimer?.invalidate()
        displayTimer = nil
        nowPlayingInfoTimer?.invalidate()
        nowPlayingInfoTimer = nil
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        cleanupAudioResources()
        saveState()
    }

    // MARK: - Limpieza de recursos
    private func cleanupAudioResources() {
        // Detener el motor y limpiar recursos
        if engine.isRunning {
            engine.stop()
        }

        // Detener timers
        displayTimer?.invalidate()
        displayTimer = nil
        nowPlayingInfoTimer?.invalidate()
        nowPlayingInfoTimer = nil
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil

        // Limpiar nodos
        stopFallbackPlayback()
        isUsingFallback = false
        playerNode.stop()
        nextPlayerNode?.stop()

        // Limpiar archivos de audio
        audioFile = nil
        nextAudioFile = nil

        // Detach nodos para liberar memoria
        if let nextPlayer = nextPlayerNode {
            engine.detach(nextPlayer)
        }

        // Limpiar información de Now Playing
        DispatchQueue.main.async {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    // MARK: - Manejo de errores mejorado
    private func handleAudioError(_ error: Error, context: String) {
        let nsError = error as NSError
        AppLog.error(.playback, error, context: context)

        // Recuperación para errores comunes del motor (-51 invalid param,
        // -10877 formato, 561015905 'kAudioUnitErr_InvalidParameter'...)
        let recoverableCodes: Set<Int> = [-51, -10877, 561015905, 2003334207]
        guard recoverableCodes.contains(nsError.code) else { return }

        AppLog.warning(.playback, "Recuperando motor de audio tras error \(nsError.code)")

        engine.stop()
        playerNode.stop()

        // Desmontar y volver a montar el grafo completo de forma segura
        if !engine.outputConnectionPoints(for: playerNode, outputBus: 0).isEmpty {
            engine.disconnectNodeOutput(playerNode)
        }
        if let eq = equalizerNode {
            engine.detach(eq)
        }
        engine.detach(playerNode)
        equalizerNode = nil

        setupEngine()
        setupEqualizer()

        do {
            try engine.start()
            AppLog.info(.playback, "Motor de audio reiniciado correctamente")
        } catch {
            AppLog.error(.playback, error, context: "handleAudioError: reinicio del motor")
        }
    }
}
