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
                mode: .musicPlayback,
                options: [.allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay]
            )

            // Configurar para alta calidad de audio con buffer optimizado
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.02) // 20ms buffer (balance entre latencia y CPU)

            try session.setActive(true)
            updateRouteName()
            updateAudioQuality()

            // Activar el control remoto y la recepción de eventos de control
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Error configurando AVAudioSession: \(error.localizedDescription)")
        }
    }

    private func setupEngine() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
    }

    private func setupEqualizer() {
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

    private func setupBackgroundNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
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
        stop()

        do {
            let file = try AVAudioFile(forReading: song.url)
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            sourceSampleRate = sampleRate
            duration = Double(file.length) / sampleRate

            guard duration > 0 else {
                playNext()
                return
            }

            // Reconectar nodos con el formato correcto
            engine.disconnectNodeInput(playerNode)
            if let eq = equalizerNode {
                engine.connect(playerNode, to: eq, format: file.processingFormat)
            } else {
                engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)
            }

            if !engine.isRunning {
                try engine.start()
            }

            scheduleFile(file, from: 0)

            currentSong = song
            seekOffset = 0
            isPlaying = true
            startDisplayTimer()
            updateNowPlayingInfo()
            updateAudioQuality()
            addToHistory(song)
            updateNextUpQueue()
            saveState()
        } catch {
            handleAudioError(error, context: "playCurrentSong")
            playNext()
        }
    }

    private func scheduleFile(_ file: AVAudioFile, from startFrame: AVAudioFramePosition) {
        playerNode.stop()

        let framesToPlay = AVAudioFrameCount(file.length - startFrame)
        guard framesToPlay > 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.playNext()
            }
            return
        }

        // Configurar crossfade si no es la primera canción
        let timeRemaining = Double(file.length - startFrame) / sampleRate
        if timeRemaining > crossfadeDuration && currentIndex > 0 {
            scheduleCrossfade(for: file, startFrame: startFrame, framesToPlay: framesToPlay)
        }

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: framesToPlay,
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.handlePlaybackFinished()
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

        // Limpiar player anterior
        engine.detach(playerNode)

        // Reemplazar con el nuevo
        playerNode.stop()
        engine.detach(playerNode)

        let currentFile = nextAudioFile
        audioFile = currentFile
        sampleRate = currentFile?.processingFormat.sampleRate ?? 44100
        duration = Double(currentFile?.length ?? 0) / sampleRate

        currentIndex += 1
        currentSong = playlist[currentIndex]
        seekOffset = 0

        // Configurar el nuevo player como principal
        engine.attach(playerNode)
        if let eq = equalizerNode {
            engine.connect(playerNode, to: eq, format: currentFile?.processingFormat)
        } else {
            engine.connect(playerNode, to: engine.mainMixerNode, format: currentFile?.processingFormat)
        }

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

        let upcomingSongs = Array(playlist.suffix(from: currentIndex + 1))
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
        guard audioFile != nil else { return }
        if !engine.isRunning {
            try? engine.start()
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
    }

    func seek(to time: TimeInterval) {
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
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
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
        nowPlayingInfoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
    }

    private func stopNowPlayingInfoTimer() {
        nowPlayingInfoTimer?.invalidate()
        nowPlayingInfoTimer = nil
    }

    private func updateCurrentTime() {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }

        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        currentTime = seekOffset + elapsed
    }

    private func handlePlaybackFinished() {
        if isPlaying && !isChangingTrack {
            if repeatMode == .one {
                seek(to: 0)
                if isPlaying { resume() }
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
        guard let state = UserDefaults.standard.dictionary(forKey: stateDefaultsKey) else { return }
        guard let songIDString = state["songID"] as? String,
              let songID = UUID(uuidString: songIDString),
              let song = allSongs.first(where: { $0.id == songID }) else {
            UserDefaults.standard.removeObject(forKey: stateDefaultsKey)
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

            engine.disconnectNodeInput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)

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
            hasRestored = true
        } catch {
            print("Error al restaurar estado: \(error.localizedDescription)")
            UserDefaults.standard.removeObject(forKey: stateDefaultsKey)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        AppLog.error(.playback, "Error en \(context): \(error.localizedDescription)")

        // Intentar recuperar de errores comunes
        if (error as NSError).code == -51 { // Invalid parameter
            // Reiniciar el motor de audio
            cleanupAudioResources()
            setupEngine()
            setupEqualizer()
        }
    }
}