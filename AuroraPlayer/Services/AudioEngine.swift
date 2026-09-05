import Foundation
import AVFoundation
import MediaPlayer
import UIKit

class AudioEngine: NSObject, ObservableObject {
    // MARK: - Publicado para la UI
    @Published var isPlaying: Bool = false {
        didSet {
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
    private var originalPlaylist: [Song] = []
    private(set) var currentIndex: Int = 0

    // MARK: - Motor de audio mejorado
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var displayTimer: Timer?
    private var nowPlayingInfoTimer: Timer?
    private var sampleRate: Double = 44100
    private var seekOffset: TimeInterval = 0

    // MARK: - Crossfade y Gapless Playback (Corregido y optimizado)
    private var crossfadeTimer: Timer?
    private var crossfadeDuration: TimeInterval = 3.0 // 3 segundos estándar para notar el crossfade con fluidez
    private var isCrossfading = false
    private var nextPlayerNode: AVAudioPlayerNode?
    private var nextAudioFile: AVAudioFile?
    @Published var isCrossfadeEnabled: Bool = true // Activado por defecto para que funcione de inmediato

    // MARK: - Equalizador
    private var equalizerNode: AVAudioUnitEQ?
    @Published var isEQEnabled: Bool = false
    @Published var eqPreset: EQPreset = .flat

    // MARK: - Flags y control
    private var isChangingTrack = false
    private var isSeeking = false
    private var isStopping = false
    private var playbackErrorCount = 0
    private var scheduleGeneration = 0

    // MARK: - Reproductor de respaldo (AVPlayer)
    private var avPlayer: AVPlayer?
    private var avTimeObserver: Any?
    private var avEndObserver: NSObjectProtocol?
    private var isUsingFallback = false

    private let stateDefaultsKey = "com.aurora.playbackState"
    private var hasRestored: Bool = false

    override init() {
        super.init()
        // Cargar duración de crossfade persistida
        crossfadeDuration = UserDefaults.standard.object(forKey: "com.aurora.crossfadeDuration") as? TimeInterval ?? 3.0
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

    private func setupSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay]
            )

            // ✅ Mejor calidad con latencia mínima: probamos buffers cortos en
            // orden descendente con fallback robusto. iOS 16 en A11 (iPhone 8)
            // devuelve error -50 (paramErr) con 0.02, así que vamos bajando
            // hasta encontrar el menor soportado por el hardware/DAC actual.
            let bufferDurations: [TimeInterval] = [0.02, 0.03, 0.04, 0.05]
            for duration in bufferDurations {
                do {
                    try session.setPreferredIOBufferDuration(duration)
                    AppLog.debug(.playback, "Buffer I/O óptimo: \(duration * 1000)ms")
                    break
                } catch {
                    AppLog.debug(.playback, "Buffer \(Int(duration * 1000))ms no soportado, probando siguiente")
                }
            }

            // Mantener el sample rate nativo del motor: el remuestreo final lo
            // hace iOS en la salida física (DAC/BT/altavoz). NO forzamos
            // preferredSampleRate para preservar bit-perfect hasta el último paso.
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            updateRouteName()
            updateAudioQuality()
        } catch {
            AppLog.error(.playback, error, context: "setupSession")
        }
    }

    private func setupEngine() {
        engine.attach(playerNode)
    }

    private func setupEqualizer() {
        if let existingEQ = equalizerNode {
            engine.detach(existingEQ)
        }

        equalizerNode = AVAudioUnitEQ(numberOfBands: 10)
        guard let eq = equalizerNode else { return }

        let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        for (index, freq) in frequencies.enumerated() {
            let band = eq.bands[index]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }

        eq.bypass = !isEQEnabled
        engine.attach(eq)
        reconnectPlayerNode(format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) ?? engine.outputNode.outputFormat(forBus: 0))
    }

    private func reconnectPlayerNode(format: AVAudioFormat) {
        if engine.isRunning {
            engine.stop()
        }

        let mixer = engine.mainMixerNode
        if let eq = equalizerNode {
            // Desconectar nodos previos de forma segura
            if !engine.outputConnectionPoints(for: playerNode, outputBus: 0).isEmpty {
                engine.disconnectNodeOutput(playerNode)
            }
            if !engine.outputConnectionPoints(for: eq, outputBus: 0).isEmpty {
                engine.disconnectNodeOutput(eq)
            }

            engine.connect(playerNode, to: eq, format: format)
            engine.connect(eq, to: mixer, format: format)
        } else {
            if !engine.outputConnectionPoints(for: playerNode, outputBus: 0).isEmpty {
                engine.disconnectNodeOutput(playerNode)
            }
            engine.connect(playerNode, to: mixer, format: format)
        }
    }

    func toggleCrossfade() {
        isCrossfadeEnabled.toggle()

        // Si se activa durante la reproducción actual, programar crossfade si es posible
        if isCrossfadeEnabled, isPlaying, let file = audioFile {
            let timeRemaining = duration - currentTime
            if timeRemaining > crossfadeDuration && currentIndex + 1 < playlist.count {
                scheduleCrossfade(for: file, startFrame: AVAudioFramePosition(currentTime * sampleRate), framesToPlay: AVAudioFrameCount(file.length))
            }
        } else if !isCrossfadeEnabled {
            // Al desactivar, cancelar cualquier crossfade pendiente
            crossfadeTimer?.invalidate()
            crossfadeTimer = nil
            isCrossfading = false
        }

        AppLog.info(.playback, "Crossfade: \(isCrossfadeEnabled ? "activado" : "desactivado")")
    }

    func toggleEQ() {
        isEQEnabled.toggle()
        equalizerNode?.bypass = !isEQEnabled

        // Asegurar que el cambio se aplique al playback activo sin perder posición
        if isPlaying, playerNode.isPlaying, let file = audioFile {
            // Reiniciar reproducción desde la posición actual para que el EQ se aplique de inmediato
            // ⚠️ CRÍTICO: incrementar scheduleGeneration ANTES de stop() para que el completion
            // handler del segmento anterior quede obsoleto y NO dispare playNext()
            scheduleGeneration += 1
            let currentPosition = currentTime
            playerNode.stop()
            // ✅ Mantener consistencia del reloj de display tras re-programar desde currentPosition
            seekOffset = currentPosition
            crossfadeTimer?.invalidate()
            crossfadeTimer = nil
            isCrossfading = false

            // Reprogramar en el siguiente runloop para evitar glitches de audio
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                guard let self = self, self.isPlaying else { return }
                self.scheduleFile(file, from: currentPosition)
                self.playerNode.play()
            }
        }

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
        guard let eq = equalizerNode, band >= 0 && band < eq.bands.count else { return }
        eq.bands[band].gain = gain
    }

    /// Sample rate del motor de audio para UI (publicado para que las vistas se actualicen)
    var sampleRateDisplay: Double {
        sampleRate
    }

    /// Configura la duración del crossfade (1–12 segundos) y la persiste
    func setCrossfadeDuration(_ seconds: TimeInterval) {
        crossfadeDuration = max(1.0, min(12.0, seconds))
        UserDefaults.standard.set(crossfadeDuration, forKey: "com.aurora.crossfadeDuration")
    }

    var currentCrossfadeDuration: TimeInterval {
        crossfadeDuration
    }

    func getEQGain(for band: Int) -> Float {
        guard let eq = equalizerNode, band >= 0 && band < eq.bands.count else { return 0 }
        return eq.bands[band].gain
    }

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
        AppLog.info(.playback, "Reproduciendo: \(song.displayName)")

        scheduleGeneration += 1
        stopFallbackPlayback()
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        isCrossfading = false

        if let nextNode = nextPlayerNode {
            nextNode.stop()
            engine.detach(nextNode)
            nextPlayerNode = nil
        }

        isUsingFallback = false
        if playerNode.isPlaying {
            playerNode.stop()
        }
        audioFile = nil
        isPlaying = false
        currentTime = 0
        seekOffset = 0
        stopDisplayTimer()

        guard FileManager.default.fileExists(atPath: song.url.path) else {
            handlePlaybackFailure(song: song)
            return
        }

        do {
            let file = try AVAudioFile(forReading: song.url)
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            sourceSampleRate = sampleRate
            duration = Double(file.length) / sampleRate

            guard duration > 0, file.length > 0 else {
                handlePlaybackFailure(song: song)
                return
            }

            if engine.isRunning {
                engine.stop()
            }
            playerNode.stop()
            reconnectPlayerNode(format: file.processingFormat)

            try engine.start()

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
            startFallbackPlayback(song: song)
        }
    }

    private func scheduleFile(_ file: AVAudioFile, from startSeconds: TimeInterval) {
        let generation = scheduleGeneration
        let safeStartFrame = AVAudioFramePosition(startSeconds * sampleRate)
        guard safeStartFrame < file.length else {
            playNext()
            return
        }

        let framesToPlay = AVAudioFrameCount(file.length - safeStartFrame)
        guard framesToPlay > 0 else {
            playNext()
            return
        }

        // Programar Crossfade si está activo y hay siguiente canción
        let timeRemaining = Double(file.length - safeStartFrame) / sampleRate
        if isCrossfadeEnabled && timeRemaining > crossfadeDuration && currentIndex + 1 < playlist.count {
            scheduleCrossfade(for: file, startFrame: safeStartFrame, framesToPlay: framesToPlay)
        }

        playerNode.scheduleSegment(
            file,
            startingFrame: safeStartFrame,
            frameCount: framesToPlay,
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self,
                      self.scheduleGeneration == generation,
                      self.isPlaying,
                      !self.isStopping,
                      !self.isCrossfading else { return }
                self.handlePlaybackFinished()
            }
        }

        playerNode.play()
    }

    // MARK: - Crossfade implementado con precisión
    private func scheduleCrossfade(for file: AVAudioFile, startFrame: AVAudioFramePosition, framesToPlay: AVAudioFrameCount) {
        let crossfadeStartFrame = AVAudioFramePosition(Double(file.length) - (crossfadeDuration * sampleRate))

        crossfadeTimer?.invalidate()
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self,
                  let nodeTime = self.playerNode.lastRenderTime,
                  let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else {
                return
            }

            let currentFrame = playerTime.sampleTime + AVAudioFramePosition(startFrame)
            if currentFrame >= crossfadeStartFrame && !self.isCrossfading {
                self.crossfadeTimer?.invalidate()
                self.startCrossfadeToNext()
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
        nextPlayer.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                self?.completeCrossfade()
            }
        }

        nextPlayer.volume = 0
        nextPlayer.play()

        // Transición de Crossfade fluida
        let startTime = Date()
        let duration = crossfadeDuration

        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(1.0, elapsed / duration)

            self.playerNode.volume = Float(1.0 - progress)
            nextPlayer.volume = Float(progress)

            if progress >= 1.0 {
                timer.invalidate()
                self.playerNode.stop()
                self.playerNode.volume = 1.0
                self.completeCrossfade()
            }
        }
    }

    private func completeCrossfade() {
        guard let nextPlayer = nextPlayerNode else { return }
        guard let nextFile = nextAudioFile else {
            isCrossfading = false
            return
        }
        guard currentIndex + 1 < playlist.count else {
            // Detener nextPlayer sin dañar el graph
            nextPlayer.stop()
            engine.detach(nextPlayer)
            nextPlayerNode = nil
            isCrossfading = false
            return
        }

        // Actualizar estado del reproductor antes de migrar
        currentIndex += 1
        currentSong = playlist[currentIndex]
        audioFile = nextFile
        sampleRate = nextFile.processingFormat.sampleRate
        duration = Double(nextFile.length) / sampleRate
        seekOffset = 0
        playbackErrorCount = 0

        // Detener y desmontar el nodo temporal del crossfade (NUNCA tocar playerNode)
        nextPlayer.stop()
        engine.detach(nextPlayer)
        nextPlayerNode = nil
        nextAudioFile = nil
        isCrossfading = false

        // Reutilizar el playerNode principal con el nuevo archivo
        // ⚠️ Incrementar generación antes de stop() para que el handler obsoleto no dispare playNext()
        scheduleGeneration += 1
        if playerNode.isPlaying {
            playerNode.stop()
        }
        playerNode.volume = 1.0

        // Reprogramar el nuevo archivo desde el inicio en el playerNode principal
        scheduleFile(nextFile, from: 0)

        isPlaying = true
        startDisplayTimer()
        updateNowPlayingInfo()
        updateAudioQuality()
        addToHistory(currentSong!)
        updateNextUpQueue()
        saveState()
    }

    // MARK: - Controles básicos y otros métodos requeridos
    func pause() {
        crossfadeTimer?.invalidate()
        if playerNode.isPlaying {
            playerNode.pause()
        }
        if let nextNode = nextPlayerNode, nextNode.isPlaying {
            nextNode.pause()
        }
        avPlayer?.pause()
        isPlaying = false
        stopDisplayTimer()
        saveState()
    }

    func resume() {
        if isUsingFallback {
            avPlayer?.play()
        } else {
            playerNode.play()
            if let nextNode = nextPlayerNode, isCrossfading {
                nextNode.play()
            }
        }
        isPlaying = true
        startDisplayTimer()
        saveState()
    }

    func stop() {
        isStopping = true
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        stopFallbackPlayback()
        if playerNode.isPlaying {
            playerNode.stop()
        }
        if let nextNode = nextPlayerNode {
            nextNode.stop()
            engine.detach(nextNode)
            nextPlayerNode = nil
        }
        isPlaying = false
        currentTime = 0
        duration = 0
        currentSong = nil
        stopDisplayTimer()
        isStopping = false
        saveState()
    }

    func playNext() {
        guard !playlist.isEmpty else { return }
        if isShuffleEnabled {
            currentIndex = Int.random(in: 0..<playlist.count)
        } else {
            currentIndex += 1
            if currentIndex >= playlist.count {
                if repeatMode == .all {
                    currentIndex = 0
                } else {
                    currentIndex = playlist.count - 1
                    stop()
                    return
                }
            }
        }
        playCurrentSong()
    }

    func playPrevious() {
        guard !playlist.isEmpty else { return }
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        currentIndex -= 1
        if currentIndex < 0 {
            currentIndex = repeatMode == .all ? playlist.count - 1 : 0
        }
        playCurrentSong()
    }

    func seek(to time: TimeInterval) {
        guard let file = audioFile else {
            if isUsingFallback {
                let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
                avPlayer?.seek(to: cmTime)
            }
            return
        }

        // ⚠️ CRÍTICO: incrementar scheduleGeneration ANTES de stop().
        // playerNode.stop() invoca los completion handlers de los segmentos programados;
        // sin esto, el handler obsoleto llamaba a handlePlaybackFinished() → playNext()
        // y SALTABA DE CANCIÓN al tocar/arrastrar la barra de progreso o las letras.
        scheduleGeneration += 1
        playerNode.stop()
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        isCrossfading = false

        let clampedTime = max(0, min(time, duration))
        currentTime = clampedTime
        // ✅ FIX CRÍTICO (letras reiniciaban al hacer tap): playerTime.sampleTime se reinicia
        // a 0 tras stop()/play(), y el display timer calcula seekOffset + sampleTime/sampleRate.
        // Sin actualizar seekOffset, currentTime volvía a ~0 y la letra saltaba al inicio.
        seekOffset = clampedTime
        scheduleFile(file, from: clampedTime)
        if isPlaying {
            playerNode.play()
        }
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
        if isShuffleEnabled {
            originalPlaylist = playlist
            let current = playlist[currentIndex]
            playlist.shuffle()
            if let newIndex = playlist.firstIndex(where: { $0.id == current.id }) {
                playlist.remove(at: newIndex)
                playlist.insert(current, at: 0)
                currentIndex = 0
            }
        } else {
            if !originalPlaylist.isEmpty {
                let current = playlist[currentIndex]
                playlist = originalPlaylist
                if let newIndex = playlist.firstIndex(where: { $0.id == current.id }) {
                    currentIndex = newIndex
                }
                originalPlaylist = []
            }
        }
        updatePlaybackQueue()
        updateNextUpQueue()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func restoreState(with songs: [Song]) {
        guard !songs.isEmpty else { return }

        // Solo marcar como restaurado si realmente hay canciones para restaurar.
        // Si ya se restauró previamente, lo omitimos.
        guard !hasRestored else { return }

        if let state = UserDefaults.standard.dictionary(forKey: stateDefaultsKey),
           let savedIndex = state["currentIndex"] as? Int,
           savedIndex >= 0, savedIndex < songs.count {
            hasRestored = true
            let song = songs[savedIndex]
            self.playlist = songs
            self.currentIndex = savedIndex
            self.currentSong = song
            self.duration = song.duration
            if let savedTime = state["currentTime"] as? TimeInterval {
                self.currentTime = max(0, savedTime)
            }

            if state["isPlaying"] as? Bool == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.playCurrentSong()
                }
            }
            updatePlaybackQueue()
            updateNextUpQueue()
            saveState()
        }
    }

    func playFromHistory(_ song: Song) {
        play(song: song, from: playHistory)
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        // 0.3s interval reduces UI churn on iPhone 8 Plus (A11) while remaining accurate
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            if self.isUsingFallback {
                if let current = self.avPlayer?.currentTime().seconds, !current.isNaN {
                    self.currentTime = current
                }
            } else if let nodeTime = self.playerNode.lastRenderTime,
                      let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) {
                let current = self.seekOffset + Double(playerTime.sampleTime) / self.sampleRate
                if current >= 0 && current <= self.duration {
                    self.currentTime = current
                }
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func handlePlaybackFinished() {
        if repeatMode == .one {
            seek(to: 0)
            resume()
            return
        }
        playNext()
    }

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
            self.currentTime = time.seconds
        }

        avEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isUsingFallback else { return }
            self.handlePlaybackFinished()
        }

        player.play()
        isPlaying = true
        startDisplayTimer()
        updateNowPlayingInfo()
        updateAudioQuality()
        addToHistory(song)
        updateNextUpQueue() // ✅ CORREGIDO: era updateNextUpQuery() (no compilaba)
        saveState()
    }

    private func handlePlaybackFailure(song: Song) {
        playbackErrorCount += 1
        if playbackErrorCount >= 5 {
            stop()
            playbackErrorCount = 0
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.playNext()
        }
    }

    private func updatePlaybackQueue() {
        playbackQueue = playlist
    }

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
        let upcoming = Array(playlist.suffix(from: nextIndex))
        nextUpQueue = Array(upcoming.prefix(3))
    }

    private func addToHistory(_ song: Song) {
        if let last = playHistory.first, last.id == song.id { return }
        playHistory.insert(song, at: 0)
        if playHistory.count > 50 { playHistory = Array(playHistory.prefix(50)) }
    }

    private func updateRouteName() {
        let session = AVAudioSession.sharedInstance()
        guard let output = session.currentRoute.outputs.first else { return }
        DispatchQueue.main.async {
            self.currentRouteName = output.portName
        }
    }

    private func updateAudioQuality() {
        let session = AVAudioSession.sharedInstance()
        DispatchQueue.main.async {
            self.outputSampleRate = session.sampleRate
            self.outputChannelCount = Int(session.outputNumberOfChannels)
            let rateInfo = session.sampleRate >= 48000 ? "Hi-Res" : "Estándar"
            let channelInfo = session.outputNumberOfChannels >= 2 ? "Estéreo" : "Mono"
            self.audioQualityInfo = "\(rateInfo) • \(Int(session.sampleRate))Hz • \(channelInfo)"
        }
    }

    // ✅ Auto-reanudación al conectar audífonos
    private var wasPlayingBeforeRouteChange = false

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw)

            // ✅ FIX: cuando se conectan audífonos/BT (nuevo dispositivo disponible),
            // reanudar la reproducción automáticamente si estaba sonando antes.
            // Antes, al conectar audífonos el audio quedaba pausado/silencioso y
            // el usuario tenía que dar play manualmente.
            if reason == .newDeviceAvailable {
                let wasPlaying = self.isPlaying || self.wasPlayingBeforeRouteChange
                self.wasPlayingBeforeRouteChange = self.isPlaying

                // Pequeño delay para que el sistema termine de estabilizar la ruta
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self = self else { return }
                    let route = AVAudioSession.sharedInstance().currentRoute.outputs.first
                    let isHeadphoneRoute = route.map { output in
                        [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .airPlay, .carAudio]
                            .contains(output.portType)
                    } ?? false

                    if wasPlaying && isHeadphoneRoute && !self.isPlaying {
                        self.resume()
                        AppLog.info(.playback, "Ruta cambiada a \(route?.portName ?? "?"): reproducción reanudada")
                    }
                }
            } else if reason == .oldDeviceUnavailable {
                // Al desconectar audífonos, recordar estado (el sistema pausa solo)
                self.wasPlayingBeforeRouteChange = self.isPlaying
            } else {
                self.wasPlayingBeforeRouteChange = self.isPlaying
            }

            self.updateRouteName()
            self.updateAudioQuality()
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let info = notification.userInfo,
                  let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }
            if type == .began && self.isPlaying {
                self.pause()
            } else if type == .ended {
                if let optVal = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                   AVAudioSession.InterruptionOptions(rawValue: optVal).contains(.shouldResume) {
                    self.resume()
                }
            }
        }
    }

    private func setupBackgroundNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.updateNowPlayingInfo()
        }
    }

    private func setupPlaybackStateObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
    }

    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        if let song = currentSong {
            info[MPMediaItemPropertyTitle] = song.title
            info[MPMediaItemPropertyArtist] = song.artist
            info[MPMediaItemPropertyAlbumTitle] = song.album
            if let art = song.artwork {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
            }
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isPlaying { self.pause() } else { self.resume() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPrevious()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: posEvent.positionTime)
            return .success
        }
    }

    private func saveState() {
        let state: [String: Any] = [
            "isPlaying": isPlaying,
            "currentTime": currentTime,
            "currentIndex": currentIndex
        ]
        UserDefaults.standard.set(state, forKey: stateDefaultsKey)
    }

    private func loadPlaybackState() {
        guard let state = UserDefaults.standard.dictionary(forKey: stateDefaultsKey) else { return }
        if let time = state["currentTime"] as? TimeInterval {
            currentTime = time
        }
    }
}
