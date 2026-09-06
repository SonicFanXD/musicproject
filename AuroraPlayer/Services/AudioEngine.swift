import Foundation
import AVFoundation
import MediaPlayer
import UIKit

// ✅ Reloj de reproducción aislado: publica el tiempo SOLO a las vistas que
// lo necesitan (PlayerBar, NowPlaying, Lyrics). Antes `currentTime` era
// @Published en AudioEngine → cada tick (0.4s) re-renderizaba TODO el árbol
// de ContentView (lista completa de canciones = drops a 40-50fps al reproducir).
final class PlaybackClock: ObservableObject {
    @Published var time: TimeInterval = 0
}

class AudioEngine: NSObject, ObservableObject {
    // MARK: - Publicado para la UI
    @Published var isPlaying: Bool = false {
        didSet {
            if oldValue != isPlaying {
                NotificationCenter.default.post(name: NSNotification.Name("PlaybackStateChanged"), object: nil)
            }
            updateIdleTimer()
        }
    }
    // ✅ Ya no es @Published: el reloj de UI vive en `clock` (PlaybackClock)
    // para no re-renderizar la biblioteca completa en cada tick.
    var currentTime: TimeInterval = 0 {
        didSet {
            if oldValue != currentTime {
                clock.time = currentTime
            }
        }
    }
    @Published var duration: TimeInterval = 0
    @Published var currentSong: Song? {
        didSet {
            // ✅ Acento dinámico desde carátula: al cambiar de canción se extrae
            // el color dominante y ThemeManager lo publica para toda la app.
            if oldValue?.id != currentSong?.id {
                ThemeManager.shared.updateArtworkAccent(from: currentSong)
            }
        }
    }
    @Published var currentRouteName: String = "Altavoz"
    // ✅ Tipo de salida (idioma-independiente): la detección por nombre
    // localizado ("Altavoz") fallaba fuera de español. Ahora usamos portType.
    @Published var outputPortType: String = ""
    // ✅ Modelo real del dispositivo (ej. "iPhone 13 Pro") en vez de "iPhone".
    @Published var deviceModelName: String = AudioEngine.resolveDeviceModel()

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

    // ✅ Reloj de reproducción publicado para las vistas de UI
    let clock = PlaybackClock()

    // MARK: - Motor de audio mejorado
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    // ✅ Audio Mono REAL: mezclador intermedio siempre presente en el grafo.
    // El downmix se hace reconectando su SALIDA con formato de 1 canal
    // (AVAudioMixerNode adapta canales por DSP). El método anterior usaba
    // setPreferredInputNumberOfChannels (ENTRADA/micrófono) → no afectaba
    // en absoluto a la reproducción.
    private let monoMixerNode = AVAudioMixerNode()
    private var audioFile: AVAudioFile?
    private var displayTimer: Timer?
    private var sampleRate: Double = 44100
    private var seekOffset: TimeInterval = 0
    // ✅ FIX "corte feo" entre canciones: recordar el formato ya conectado al
    // graph. Si la siguiente canción tiene el mismo formato, NO se detiene ni
    // reinicia el engine (solo se reprograma el nodo) → transición sin hueco.
    private var connectedFormatKey: String?
    // ✅ FIX reinicio desde punto aleatorio: recordar el archivo cargado para
    // detectar cuándo se reinicia la MISMA canción (repeat-one / álbum de una
    // sola canción) y aplicar el re-programado con delay.
    private var currentFileURL: URL?

    // MARK: - Crossfade (✅ ELIMINADO)
    // El crossfade era la fuente principal de bugs de sincronización
    // (saltos "al azar" al terminar canciones y drift del reloj).
    // Las propiedades se mantienen (en false) por compatibilidad con las
    // vistas que las referencian, pero NUNCA se activa.
    private var crossfadeTimer: Timer?
    private var crossfadeDuration: TimeInterval = 3.0
    private var isCrossfading = false
    private var nextPlayerNode: AVAudioPlayerNode?
    private var nextAudioFile: AVAudioFile?
    @Published var isCrossfadeEnabled: Bool = false

    // ✅ "Mantener pantalla encendida" gestionado aquí (centralizado):
    // antes solo vivía en NowPlayingView y se perdía al cerrarla.
    var isKeepScreenOnEnabled: Bool = false {
        didSet { updateIdleTimer() }
    }

    // MARK: - Equalizador
    private var equalizerNode: AVAudioUnitEQ?
    @Published var isEQEnabled: Bool = false
    @Published var eqPreset: EQPreset = .flat
    // ✅ Audio Mono: mezcla ambos canales en uno para usuarios con audífono único
    @Published var isMonoAudioEnabled: Bool = UserDefaults.standard.bool(forKey: "com.aurora.monoAudio") {
        didSet {
            if isMonoAudioEnabled != oldValue {
                UserDefaults.standard.set(isMonoAudioEnabled, forKey: "com.aurora.monoAudio")
            }
        }
    }

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
        // ✅ Crossfade eliminado: limpiar preferencias obsoletas
        UserDefaults.standard.removeObject(forKey: "com.aurora.crossfadeEnabled")
        UserDefaults.standard.removeObject(forKey: "com.aurora.crossfadeDuration")
        setupSession()
        setupEngine()
        setupEqualizer()
        observeRouteChanges()
        observeInterruptions()
        setupRemoteCommandCenter()
        setupBackgroundNotification()
        setupPlaybackStateObserver()
        observeEngineConfigurationChanges()
        setupBackgroundLifecycleObservers()
        loadPlaybackState()
    }

    // ✅ Caché del artwork para Now Playing: se genera UNA vez por canción,
    // no en cada refresh (cada 0.8s fg / 1.5s bg) como antes. Antes renderizaba
    // una imagen 1200×1200 en cada tick → gasto enorme de CPU/batería.
    private var cachedArtworkSongID: UUID?
    private var cachedNowPlayingArtwork: MPMediaItemArtwork?

    // MARK: - Persistencia del motor en segundo plano
    // ✅ Mejora de batería + estabilidad: cuando la app pasa a segundo plano,
    // iOS puede suspender timers/render y en algunos casos detener el engine.
    // Este observador asegura que la sesión de audio permanezca activa y el
    // engine siga corriendo sin que la app sea suspendida por el sistema.
    // La persistencia de audio en background funciona gracias a la capacidad
    // UIBackgroundModes = audio (ya configurada en Info.plist) y a que la
    // sesión de audio se mantiene activa mientras hay reproducción activa.

    private func setupBackgroundLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func handleAppDidEnterBackground() {
        // ✅ Persistencia del audio: si estamos reproduciendo, mantener la
        // sesión de audio activa y pedir tiempo en segundo plano para que
        // el engine no se suspenda. Esto mejora la reproducción continua
        // sin saltos ni cortes al cambiar de app o bloquear la pantalla.
        guard isPlaying else {
            // ✅ Si no se reproduce, liberar el engine para ahorrar batería:
            // detener el engine (no la sesión) reduce consumo de CPU/RAM.
            if engine.isRunning {
                engine.pause()
            }
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            // ✅ Reactivar la sesión con notifyOthersOnDeactivation para que
            // otras apps (if any) se enteren y no se pisen. Mantener activa
            // la sesión es imprescindible para audio en background continuo.
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            AppLog.error(.playback, error, context: "background: reactivar sesión")
        }

        // ✅ Mantener el engine corriendo (no pausar) para que la reproducción
        // continúe de forma fluida al volver a primer plano. iOS permite audio
        // en background gracias a UIBackgroundModes = audio.
        if !engine.isRunning, isPlaying, let file = audioFile {
            do {
                try startEngineSafely()
                let position = min(max(currentTime, 0), duration)
                scheduleGeneration += 1
                seekOffset = position
                scheduleFile(file, from: position)
            } catch {
                AppLog.error(.playback, error, context: "background: reiniciar engine")
            }
        }

        // ✅ Reducir la frecuencia de actualización del display timer en
        // segundo plano para ahorrar batería (el UI no necesita updates
        // tan frecuentes cuando no se ve la pantalla).
        startDisplayTimer(isBackground: true)
    }

    @objc private func handleAppWillEnterForeground() {
        // ✅ Volver a frecuencia normal del timer al regresar a primer plano
        if isPlaying {
            // ✅ FIX: sincronizar el reloj ANTES de reiniciar el timer para evitar
            // que la barra se adelante al volver de segundo plano.
            syncCurrentTimeFromRenderThread()
            startDisplayTimer(isBackground: false)
            updateNowPlayingInfo()
        }

        // ✅ Si se pausó en segundo plano, asegurar que el engine siga listo
        if !engine.isRunning, isPlaying, let file = audioFile {
            do {
                try startEngineSafely()
                let position = min(max(currentTime, 0), duration)
                scheduleGeneration += 1
                seekOffset = position
                scheduleFile(file, from: position)
            } catch {
                AppLog.error(.playback, error, context: "foreground: reiniciar engine")
            }
        }
    }

    /// Sincroniza currentTime y clock.time con la posición real del render thread.
    /// Llamado al volver de segundo plano para evitar que la barra se adelante.
    private func syncCurrentTimeFromRenderThread() {
        guard !isUsingFallback,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        let current = seekOffset + Double(playerTime.sampleTime) / sampleRate
        if current >= 0 && current <= duration {
            currentTime = current
            clock.time = current
        }
    }

    // MARK: - Recuperación robusta del engine (fix de crashes en segundo plano)
    // ✅ Cuando la app pasa a segundo plano sin reproducir, iOS puede desactivar
    // la sesión de audio y detener el AVAudioEngine. Intentar reproducir en ese
    // estado crasheaba la app. Este helper reactiva la sesión y reintenta el
    // arranque del engine de forma segura.
    private func startEngineSafely() throws {
        let session = AVAudioSession.sharedInstance()

        // 1. Reactivar la sesión si está inactiva
        if !session.isOtherAudioPlaying {
            do {
                try session.setActive(true, options: [])
            } catch {
                AppLog.error(.playback, error, context: "startEngineSafely: reactivar sesión")
            }
        }

        // 2. Arrancar el engine con un reintento tras reconectar el grafo
        do {
            try engine.start()
        } catch {
            AppLog.error(.playback, error, context: "startEngineSafely: primer intento, reconectando")
            // Reintentar: reconectar el playerNode al mixer y arrancar de nuevo
            if let file = audioFile {
                reconnectPlayerNode(format: file.processingFormat)
            } else {
                reconnectPlayerNode(format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) ?? engine.outputNode.outputFormat(forBus: 0))
            }
            try engine.start()
        }

        // 3. Verificación final: si el engine sigue sin correr, es un error real
        guard engine.isRunning else {
            throw NSError(domain: "AuroraAudioEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "El motor de audio no pudo iniciarse"])
        }
    }

    // ✅ iOS detiene/reconfigura el engine ante cambios de ruta o del sistema.
    // Sin este observador, el engine quedaba muerto y la siguiente reproducción
    // fallaba (o crasheaba). Lo reiniciamos proactivamente.
    private func observeEngineConfigurationChanges() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            AppLog.info(.playback, "Configuración del engine cambió; reconfigurando")
            if !self.engine.isRunning {
                do {
                    try self.startEngineSafely()
                    // Si había reproducción activa, retomarla desde la posición actual
                    if self.isPlaying, let file = self.audioFile {
                        let position = self.currentTime
                        self.scheduleGeneration += 1
                        self.seekOffset = position
                        self.scheduleFile(file, from: position)
                    }
                } catch {
                    AppLog.error(.playback, error, context: "observeEngineConfigurationChanges")
                }
            }
        }
    }

    private func updateIdleTimer() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = self.isKeepScreenOnEnabled && self.isPlaying
        }
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
            // ✅ OPTIMIZACIÓN DE BATERÍA: un buffer levemente más largo (0.04s
            // en vez de 0.02s) reduce el número de interrupciones del render
            // thread sin degradar la calidad audible (el sample rate y la
            // precisión se mantienen idénticos; solo cambia la latencia).
            let bufferDurations: [TimeInterval] = [0.04, 0.03, 0.02, 0.05]
            for duration in bufferDurations {
                do {
                    try session.setPreferredIOBufferDuration(duration)
                    AppLog.debug(.playback, "Buffer I/O óptimo: \(duration * 1000)ms")
                    break
                } catch {
                    // ✅ Esperado en A11 (iPhone 8): no es un error real,
                    // solo probamos el siguiente buffer más corto soportado.
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
        // ✅ Mono: el mezclador de downmix vive permanentemente en el grafo
        engine.attach(monoMixerNode)
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
        // ✅ Recordar el formato conectado para evitar reinicios innecesarios
        // del engine al cambiar de canción (transición sin hueco).
        connectedFormatKey = formatKey(format)

        let mixer = engine.mainMixerNode
        // ✅ Mono: desconectar también la salida previa del mezclador downmix
        if !engine.outputConnectionPoints(for: monoMixerNode, outputBus: 0).isEmpty {
            engine.disconnectNodeOutput(monoMixerNode)
        }
        if let eq = equalizerNode {
            // Desconectar nodos previos de forma segura
            if !engine.outputConnectionPoints(for: playerNode, outputBus: 0).isEmpty {
                engine.disconnectNodeOutput(playerNode)
            }
            if !engine.outputConnectionPoints(for: eq, outputBus: 0).isEmpty {
                engine.disconnectNodeOutput(eq)
            }

            engine.connect(playerNode, to: eq, format: format)
            engine.connect(eq, to: monoMixerNode, format: format)
            engine.connect(monoMixerNode, to: mixer, format: monoMixerOutputFormat())
        } else {
            if !engine.outputConnectionPoints(for: playerNode, outputBus: 0).isEmpty {
                engine.disconnectNodeOutput(playerNode)
            }
            engine.connect(playerNode, to: monoMixerNode, format: format)
            engine.connect(monoMixerNode, to: mixer, format: monoMixerOutputFormat())
        }
    }

    /// ✅ Mono: formato de salida del mezclador downmix — 1 canal si el mono
    /// está activo (downmix real), 2 canales (estéreo transparente) si no.
    private func monoMixerOutputFormat() -> AVAudioFormat {
        let channels: AVAudioChannelCount = isMonoAudioEnabled ? 1 : 2
        let rate = sampleRate > 0 ? sampleRate : 44100
        return AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)
            ?? engine.mainMixerNode.outputFormat(forBus: 0)
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
            guard index < eq.bands.count else { break }
            eq.bands[index].gain = gain
        }
        AppLog.info(.playback, "EQ preset: \(preset.displayName)")
    }

    // MARK: - Audio Mono
    /// Activa/desactiva audio mono (mezcla ambos canales en uno).
    /// Útil para usuarios con audífono único o pérdida auditiva en un oído.
    func toggleMonoAudio() {
        isMonoAudioEnabled.toggle()
        applyMonoAudio()
        AppLog.info(.playback, "Audio mono: \(isMonoAudioEnabled ? "activado" : "desactivado")")
    }

    private func applyMonoAudio() {
        // ✅ Mono REAL (downmix de salida): reconectar la salida del mezclador
        // intermedio con formato de 1 canal. AVAudioMixerNode hace el downmix
        // estéreo→mono por DSP, y iOS reproduce la señal monofónica por ambos
        // altavoces/auriculares. (El método anterior tocaba los canales de
        // ENTRADA del micrófono → no tenía ningún efecto audible.)
        if !engine.outputConnectionPoints(for: monoMixerNode, outputBus: 0).isEmpty {
            engine.disconnectNodeOutput(monoMixerNode)
        }
        engine.connect(monoMixerNode, to: engine.mainMixerNode, format: monoMixerOutputFormat())

        // Si hay reproducción activa, re-programar el segmento para que el
        // cambio se aplique al instante (mismo patrón que toggleEQ).
        if isPlaying, !isCrossfading, playerNode.isPlaying, let file = audioFile {
            scheduleGeneration += 1
            let position = currentTime
            playerNode.stop()
            seekOffset = position
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                guard let self = self, self.isPlaying else { return }
                self.scheduleFile(file, from: position)
                self.playerNode.play()
            }
        }
        AppLog.info(.playback, "Audio mono (downmix de salida): \(isMonoAudioEnabled ? "activado" : "desactivado")")
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

            // ✅ FIX "corte feo" entre canciones: solo detener/reiniciar el engine
            // si cambió el formato (sample rate, canales o EQ). Si es el mismo,
            // se mantiene el engine corriendo y solo se reprograma el nodo →
            // la transición entre canciones queda sin hueco de silencio.
            let needsReconnect = !engine.isRunning || connectedFormatKey != formatKey(file.processingFormat)
            playerNode.stop()
            if needsReconnect {
                engine.stop()
                reconnectPlayerNode(format: file.processingFormat)
                // ✅ FIX crash en segundo plano: arranque robusto con reactivación
                // de sesión y reintento (antes: try engine.start() directo)
                try startEngineSafely()
            }

            currentSong = song
            seekOffset = 0
            isPlaying = true
            playbackErrorCount = 0

            // ✅ FIX reinicio desde punto aleatorio (repeat-one / álbum de una
            // sola canción): si se carga el MISMO archivo que ya estaba en el
            // nodo y no hubo que reconectar el graph, reprogramar con un breve
            // delay. Detener el nodo y re-programar de inmediato deja sampleTime
            // residual → la canción arranca desde un punto aleatorio. Con el
            // delay el reloj del nodo se resetea y arranca limpio desde 0.
            let isSameFileRestart = (song.url == currentFileURL) && !needsReconnect
            currentFileURL = song.url
            if isSameFileRestart {
                rescheduleFileAfterStop(file, from: 0)
            } else {
                scheduleFile(file, from: 0)
            }

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

    private func scheduleFile(_ file: AVAudioFile, from startSeconds: TimeInterval, autostart: Bool = true) {
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

        // ✅ Crossfade eliminado: nunca se programa (era la fuente de los
        // saltos "al azar" al terminar canciones y el drift de sincronización)

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

        // ✅ FIX sincronización: `autostart=false` permite reprogramar el nodo
        // SIN iniciar la reproducción (ej. seek en pausa). Antes scheduleFile
        // reproducía siempre: al buscar con la app en pausa el audio sonaba con
        // isPlaying=false y todas las barras quedaban desincronizadas.
        if autostart {
            playerNode.play()
        }
    }

    /// Identidad del formato conectado al graph (sample rate + canales + EQ)
    private func formatKey(_ format: AVAudioFormat) -> String {
        "\(format.sampleRate)-\(format.channelCount)-\(equalizerNode != nil)"
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
            // ✅ Mono: pasar por el mezclador downmix, no directo al mainMixer
            engine.connect(nextPlayer, to: monoMixerNode, format: file.processingFormat)
        }

        nextPlayerNode = nextPlayer
        nextPlayer.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                self?.completeCrossfade()
            }
        }

        nextPlayer.volume = 0
        nextPlayer.play()

        // ✅ CROSSFADE SUAVE con curvas EQUAL-POWER (cos/sin): la potencia sumada
        // de ambas canciones se mantiene constante durante todo el cruce (sin el
        // "hoyo" de -3dB del fundido lineal). Pasos a ~60Hz → inaudible, sin
        // zipper noise (el escalón es <0.02% de amplitud por frame).
        let duration = crossfadeDuration
        let stepInterval = 1.0 / 60.0
        let totalSteps = max(10, Int(duration / stepInterval))
        var step = 0

        crossfadeTimer?.invalidate()
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: duration / Double(totalSteps), repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            step += 1
            let progress = Double(step) / Double(totalSteps)
            if progress >= 1.0 {
                timer.invalidate()
                self.playerNode.volume = 0
                nextPlayer.volume = 1.0
                // ✅ Migración al terminar el fundido (single-shot: pause/stop/seek
                // ya invalidan este mismo timer y cancelan la migración también)
                self.completeCrossfade()
                return
            }
            // Curvas equal-power: cos sale / sin entra
            let angle = progress * Double.pi / 2
            self.playerNode.volume = Float(cos(angle))
            nextPlayer.volume = Float(sin(angle))
        }
    }

    private func completeCrossfade() {
        // ✅ FIX: Crash + audio feo del crossfade
        // El problema raíz era detach(nextPlayer) mientras el engine estaba
        // corriendo, lo que causaba crashes y glitches de audio.
        // SOLUCIÓN: NO hacemos detach. Simplemente detenemos el nodo temporal
        // y lo dejamos conectado pero silencioso, sin quitarlo del graph.
        // El siguiente program se encargará de desconectarlo de forma segura.
        guard isCrossfading, let nextPlayer = nextPlayerNode else { return }
        guard let nextFile = nextAudioFile else {
            isCrossfading = false
            return
        }
        guard currentIndex + 1 < playlist.count else {
            nextPlayer.stop()
            nextPlayer.volume = 0
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

        // ⚠️ FIX CRÍTICO: NO detach aquí. Solo paramos y silenciamos.
        // El playerNode principal se reprogramará en scheduleFile() y
        // el nodo temporal se reutilizará/destruirá de forma segura.
        nextPlayer.stop()
        nextPlayer.volume = 0
        nextPlayerNode = nil
        nextAudioFile = nil

        // ⚠️ FIX CRÍTICO (crash + doble "Reproduciendo"): incrementar la generación
        // ANTES de poner isCrossfading=false. Si lo hacemos después, el completion
        // del segmento VIEJO del playerNode pasa el guard (!isCrossfading) y sus
        // scheduleGeneration aún coincide → dispara playNext() duplicado que
        // colisiona con la reprogramación del crossfade (crash).
        scheduleGeneration += 1
        isCrossfading = false
        if playerNode.isPlaying {
            playerNode.stop()
        }
        playerNode.volume = 1.0

        // ✅ FIX CRÍTICO del crossfade: medir la posición REAL del nextPlayer
        // (reloj del render thread) en vez de asumir crossfadeDuration teórico.
        // Antes, cualquier drift del fundido causaba un salto audible al migrar.
        var framesPlayed = AVAudioFramePosition(crossfadeDuration * sampleRate)
        if let nodeTime = nextPlayer.lastRenderTime,
           let playerTime = nextPlayer.playerTime(forNodeTime: nodeTime) {
            framesPlayed = playerTime.sampleTime
        }
        framesPlayed = min(max(framesPlayed, 0), AVAudioFramePosition(nextFile.length) - 1)
        let alreadyPlayed = Double(framesPlayed) / sampleRate
        seekOffset = alreadyPlayed
        scheduleFile(nextFile, from: alreadyPlayed)

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
        // ✅ FIX: detener el display timer PRIMERO para evitar que siga
        // actualizando currentTime mientras capturamos la posición exacta.
        stopDisplayTimer()
        // ✅ FIX: capturar la posición EXACTA del render thread ANTES de pausar
        // y actualizar seekOffset para que al reanudar el display timer calcule
        // correctamente (seekOffset + sampleTime/sampleRate).
        if !isUsingFallback,
           let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
            let current = seekOffset + Double(playerTime.sampleTime) / sampleRate
            if current >= 0 && current <= duration {
                currentTime = current
                seekOffset = current
            }
        } else if isUsingFallback, let current = avPlayer?.currentTime().seconds, current.isFinite, current >= 0 {
            currentTime = current
        }
        if playerNode.isPlaying {
            playerNode.pause()
        }
        if let nextNode = nextPlayerNode, nextNode.isPlaying {
            nextNode.pause()
        }
        avPlayer?.pause()
        if !isUsingFallback, !isCrossfading, engine.isRunning {
            engine.pause()
        }
        isPlaying = false
        updateNowPlayingInfo()
        saveState()
    }

    func resume() {
        if isUsingFallback {
            avPlayer?.play()
        } else {
            // ✅ FIX: si la app estuvo en segundo plano sin reproducir, iOS puede
            // haber detenido el engine. Reanudar a ciegas fallaba en silencio (o
            // crasheaba). Reactivar sesión + engine antes de hacer play.
            if !engine.isRunning {
                do {
                    try startEngineSafely()
                    if let file = audioFile {
                        let position = min(max(currentTime, 0), duration)
                        scheduleGeneration += 1
                        seekOffset = position
                        scheduleFile(file, from: position)
                    }
                } catch {
                    AppLog.error(.playback, error, context: "resume: reactivar engine")
                }
            } else {
                playerNode.play()
                // ✅ FIX CRÍTICO (desincronización pausa/play): playerNode.pause()
                // NO resetea playerTime.sampleTime (persiste al reanudar), pero
                // pause() recolocó seekOffset a la posición absoluta. El display
                // timer calcula seekOffset + sampleTime/sampleRate → DOBLE conteo
                // y la barra (y las letras) saltaban a cualquier lado. Re-anclar:
                // seekOffset = posición absoluta - muestras ya renderizadas.
                if let nodeTime = playerNode.lastRenderTime,
                   let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
                    seekOffset = max(0, currentTime - Double(playerTime.sampleTime) / sampleRate)
                }
                if let nextNode = nextPlayerNode, isCrossfading {
                    nextNode.play()
                    // ✅ FIX: si se pausó a mitad del crossfade, el timer de
                    // migración fue invalidado. Reprogramarlo para que el
                    // fundido termine de migrar a la canción siguiente.
                    crossfadeTimer?.invalidate()
                    let remaining = max(0.1, crossfadeDuration * 0.25 + 0.05)
                    crossfadeTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                        self?.completeCrossfade()
                    }
                }
            }
        }
        isPlaying = true
        // ✅ FIX Centro de Control: publicar rate 1.0 + elapsed al reanudar
        updateNowPlayingInfo()
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
        currentFileURL = nil
        stopDisplayTimer()
        isStopping = false
        saveState()
    }

    /// Calcula el índice de la siguiente canción según shuffle/repeat-all.
    /// Retorna nil si se alcanzó el final de la playlist sin repeat.
    /// NOTA: repeat-one se maneja en handlePlaybackFinished, no aquí.
    private func computeNextIndex() -> Int? {
        guard !playlist.isEmpty else { return nil }
        if isShuffleEnabled {
            return Int.random(in: 0..<playlist.count)
        }
        let next = currentIndex + 1
        if next >= playlist.count {
            return repeatMode == .all ? 0 : nil
        }
        return next
    }

    func playNext() {
        // ✅ FIX CRÍTICO: Evitar crash si estamos en medio de un crossfade
        guard !isCrossfading else { return }
        guard let index = computeNextIndex() else { return }
        currentIndex = index
        playCurrentSong()
    }

    /// Encadena la siguiente canción directamente en el nodo sin detenerlo,
    /// logrando transición sin silencio (gapless). Si la siguiente canción
    /// requiere reconectar el graph (formato distinto), cae al proceso normal.
    private func chainNextSong() {
        guard let index = computeNextIndex() else {
            stop()
            return
        }
        let nextSong = playlist[index]

        guard let file = try? AVAudioFile(forReading: nextSong.url) else {
            currentIndex = index
            playCurrentSong()
            return
        }

        let fileFormat = file.processingFormat
        let needsReconnect = connectedFormatKey != nil && formatKey(fileFormat) != connectedFormatKey

        if needsReconnect {
            currentIndex = index
            playCurrentSong()
            return
        }

        // ✅ Gapless: actualizar estado y programar el segmento directamente.
        currentSong = nextSong
        currentIndex = index
        currentFileURL = nextSong.url
        seekOffset = 0
        isPlaying = true
        playbackErrorCount = 0
        audioFile = file
        sampleRate = fileFormat.sampleRate
        if connectedFormatKey == nil {
            connectedFormatKey = formatKey(fileFormat)
        }
        scheduleChainedFile(file, from: 0)
        startDisplayTimer()
        updateNowPlayingInfo()
        updateAudioQuality()
        addToHistory(nextSong)
        updateNextUpQueue()
        saveState()
    }

    /// Programa un segmento encadenado al anterior (at: nil) para gapless.
    /// Si el nodo no está reproduciendo (se detuvo entre segmentos), lo reinicia.
    private func scheduleChainedFile(_ file: AVAudioFile, from startSeconds: TimeInterval) {
        let generation = scheduleGeneration
        let safeStartFrame = AVAudioFramePosition(startSeconds * sampleRate)
        guard safeStartFrame < file.length else {
            handlePlaybackFinished()
            return
        }
        let framesToPlay = AVAudioFrameCount(file.length - safeStartFrame)
        guard framesToPlay > 0 else {
            handlePlaybackFinished()
            return
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
        // ✅ Reiniciar el nodo si se detuvo entre segmentos (evita silencio total)
        if !playerNode.isPlaying {
            if !engine.isRunning {
                try? startEngineSafely()
            }
            if engine.isRunning {
                playerNode.play()
            }
        }
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
        // ✅ FIX sincronización: en pausa el seek NO debe iniciar la reproducción.
        scheduleFile(file, from: clampedTime, autostart: isPlaying)
        // ✅ FIX Centro de Control: publicar elapsed exacto inmediatamente
        // tras el seek para que la barra del sistema salte al mismo punto.
        updateNowPlayingInfo()
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

    // ✅ Gestión de la cola "Siguiente" (reordenar, eliminar, limpiar)
    func removeFromNextUpQueue(_ song: Song) {
        nextUpQueue.removeAll { $0.id == song.id }
        // Reconstruir playlist interna para reflejar el cambio
        rebuildPlaylistFromQueue()
    }

    func reorderNextUpQueue(_ songs: [Song]) {
        nextUpQueue = songs
        rebuildPlaylistFromQueue()
    }

    func clearNextUpQueue() {
        nextUpQueue.removeAll()
        rebuildPlaylistFromQueue()
    }

    private func rebuildPlaylistFromQueue() {
        // La playlist actual = [canción actual] + cola siguiente
        guard currentIndex >= 0, currentIndex < playlist.count else { return }
        let current = playlist[currentIndex]
        playlist = [current] + nextUpQueue
        currentIndex = 0
        originalPlaylist = []
    }

    private func startDisplayTimer(isBackground: Bool = false) {
        stopDisplayTimer()
        var tickCount = 0
        // ✅ OPTIMIZACIÓN DE BATERÍA: en primer plano 0.4s es suficiente para
        // una UI fluida (la barra de progreso responde rápido al seek/pause),
        // y en segundo plano subimos a 1.5s para reducir drásticamente el
        // consumo de CPU cuando la pantalla está bloqueada o en otra app.
        let interval: TimeInterval = isBackground ? 1.5 : 0.4
        let nowPlayingRefreshTicks = isBackground ? 1 : 2
        displayTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
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
            // ✅ FIX Centro de Control / pantalla de bloqueo: refrescar
            // nowPlayingInfo cada ~0.8s en fg / ~1.5s en bg con el elapsed
            // EXACTO del reloj de render. En segundo plano iOS ya interpola
            // el progreso con el rate, así que no necesitamos tantos updates.
            tickCount += 1
            if tickCount >= nowPlayingRefreshTicks {
                tickCount = 0
                self.updateNowPlayingInfo()
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // ✅ Repeat one mejorado: en vez de seek(0)+resume (que puede fallar si
    // el engine se detuvo), reprograma el segmento completo desde 0 con una
    // nueva generación para garantizar que suene sin cortes ni silencios.
    private func handlePlaybackFinished() {
        guard isPlaying, !isStopping, !isCrossfading else { return }

        if repeatMode == .one {
            guard let file = audioFile else { return }
            scheduleGeneration += 1
            seekOffset = 0
            currentTime = 0
            rescheduleFileAfterStop(file, from: 0)
            return
        }
        // ✅ Gapless: marcar que la canción actual llegó al 100% antes de encadenar
        // para evitar cortes prematuros. El completion handler se dispara cuando el
        // segmento termina de programarse, no cuando el audio deja de sonar.
        if currentTime < duration {
            currentTime = duration
            clock.time = duration
        }
        stopDisplayTimer()
        chainNextSong()
    }

    /// Re-programa el mismo archivo tras detener el nodo, con un breve delay.
    /// Necesario cuando se reinicia la MISMA canción: el reloj interno del nodo
    /// (sampleTime) no se resetea hasta el siguiente render tras stop(), y
    /// programar+reproducir de inmediato arranca desde un punto residual al azar.
    private func rescheduleFileAfterStop(_ file: AVAudioFile, from seconds: TimeInterval) {
        scheduleGeneration += 1
        let generation = scheduleGeneration
        playerNode.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self,
                  self.scheduleGeneration == generation,
                  self.isPlaying,
                  !self.isStopping,
                  !self.isCrossfading else { return }
            self.scheduleFile(file, from: seconds)
            self.updateNowPlayingInfo()
        }
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
        let newName = output.portName
        let newType = output.portType.rawValue
        // ✅ OPTIMIZACIÓN BATERÍA: solo publicar si la ruta CAMBIÓ de verdad.
        // Evita dispatch al main + re-render de la UI en cada cambio de ruta
        // innecesario (antes publicaba siempre, incluso con mismos valores).
        guard newName != currentRouteName || newType != outputPortType else { return }
        DispatchQueue.main.async {
            self.currentRouteName = newName
            self.outputPortType = newType
            // ✅ FIX: Forzar actualización de la info de calidad al cambiar ruta
            self.updateAudioQuality()
        }
    }
    
    /// ✅ Verificación adicional de la ruta de salida para detectar cambios
    func refreshOutputRoute() {
        updateRouteName()
    }

    // ✅ Resuelve el nombre comercial del dispositivo desde el identificador
    // de máquina (utsname.machine). Fallback genérico si no está en la tabla.
    private static func resolveDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }

        let knownModels: [String: String] = [
            "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
            "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone12,8": "iPhone SE (2.ª gen.)", "iPhone14,6": "iPhone SE (3.ª gen.)",
            "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
            "iPhone11,8": "iPhone XR", "iPhone11,2": "iPhone XS", "iPhone11,6": "iPhone XS Max",
            "iPhone11,4": "iPhone XS Max", "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8",
            "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
            "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
            "iPad13,16": "iPad (9.ª gen.)", "iPad13,18": "iPad (10.ª gen.)",
            "iPad14,3": "iPad Pro 11\" (4.ª gen.)", "iPad14,4": "iPad Pro 12.9\" (6.ª gen.)",
        ]
        if let name = knownModels[machine] { return name }
        // Fallback legible: "iPhone16,1" → "iPhone"
        if machine.hasPrefix("iPhone") { return "iPhone" }
        if machine.hasPrefix("iPad") { return "iPad" }
        if machine.hasPrefix("iPod") { return "iPod touch" }
        return machine
    }

    private func updateAudioQuality() {
        let session = AVAudioSession.sharedInstance()
        let newRate = session.sampleRate
        let newChannels = Int(session.outputNumberOfChannels)
        // ✅ OPTIMIZACIÓN BATERÍA: no recrear el string de calidad ni publicar
        // si no hubo cambios reales en la salida (evita re-render UI + dispatch).
        guard outputSampleRate != newRate || outputChannelCount != newChannels else { return }
        DispatchQueue.main.async {
            self.outputSampleRate = newRate
            self.outputChannelCount = newChannels
            let rateInfo = newRate >= 48000 ? "Hi-Res" : "Estándar"
            let channelInfo = newChannels >= 2 ? "Estéreo" : "Mono"
            self.audioQualityInfo = "\(rateInfo) • \(Int(newRate))Hz • \(channelInfo)"
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
                let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .flatMap { AVAudioSession.InterruptionOptions(rawValue: $0) }
                    .map { $0.contains(.shouldResume) } ?? false
                // ✅ Resistente a pausas no otorgadas: si la interrupción terminó
                // (ej. llamada finalizada, video pausado por el usuario) y NO
                // venía con shouldResume pero la app estaba reproduciendo antes,
                // reanudamos manualmente para no quedar colgados en pausa.
                if shouldResume {
                    self.resume()
                } else if self.wasPlayingBeforeRouteChange {
                    // La interrupción fue por el sistema (llamada/video):
                    // reanudar solo si fue un interruptor temporal que terminó.
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
        // ✅ FIX: MPNowPlayingInfoCenter debe actualizarse SIEMPRE en el
        // hilo principal; desde un hilo secundario iOS puede ignorar el
        // update (síntoma: el widget solo se refrescaba al reiniciar).
        DispatchQueue.main.async {
            self.publishNowPlayingInfo()
        }
    }

    private func publishNowPlayingInfo() {
        var info = [String: Any]()
        if let song = currentSong {
            info[MPMediaItemPropertyTitle] = song.title
            info[MPMediaItemPropertyArtist] = song.artist
            info[MPMediaItemPropertyAlbumTitle] = song.album
            if let art = song.artwork {
                // ✅ OPTIMIZACIÓN BATERÍA: el artwork se renderiza UNA sola vez
                // por canción y se cachea. Antes se generaba una imagen 1200×1200
                // en cada refresh (0.8s fg / 1.5s bg) → consumo CPU enorme
                // mientras la pantalla estaba bloqueada o en otra app.
                if cachedArtworkSongID != song.id || cachedNowPlayingArtwork == nil {
                    let artworkSize = CGSize(width: 1200, height: 1200)
                    let newArtwork = MPMediaItemArtwork(boundsSize: artworkSize) { size in
                        // ✅ Redimensionar manteniendo calidad (image renderer GPU)
                        let renderer = UIGraphicsImageRenderer(size: size)
                        return renderer.image { _ in
                            art.draw(in: CGRect(origin: .zero, size: size))
                        }
                    }
                    cachedArtworkSongID = song.id
                    cachedNowPlayingArtwork = newArtwork
                }
                info[MPMediaItemPropertyArtwork] = cachedNowPlayingArtwork
            } else {
                cachedArtworkSongID = nil
                cachedNowPlayingArtwork = nil
            }
        } else {
            cachedArtworkSongID = nil
            cachedNowPlayingArtwork = nil
        }
        // ✅ Sincronización correcta con Centro de Control / Bloquear pantalla:
        // - PlaybackRate  1.0 → reproduciendo; 0.0 → pausa
        // - ElapsedPlaybackTime SOLO se incluye cuando está pausado o en seek,
        //   para que el sistema calcute el progreso automáticamente durante
        //   la reproducción y la barra se mueva sola sin actualizaciones
        //   constantes (el bug de "se queda al final" y "no se sincroniza
        //   la pausa" ocurría porque enviábamos currentTime obsoleto).
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPMediaItemPropertyPlaybackDuration] = duration
        // ✅ FIX Centro de Control: enviar SIEMPRE el elapsed. Al (re)iniciar
        // playback (repeat-one, seek, cambio de pista), si no se envía, iOS
        // sigue avanzando el elapsed desde el valor anterior (fin de canción)
        // y la barra de progreso queda desincronizada. Enviarlo en cada
        // actualización es lo estándar: el sistema lo avanza con el rate.
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime

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
            "currentIndex": currentIndex,
            // ✅ Persistir repeat/shuffle para que al cerrar la app por
            // voluntad o ahorro de rendimiento no se pierdan estos ajustes.
            "isShuffleEnabled": isShuffleEnabled,
            "repeatMode": repeatMode.rawValue
        ]
        UserDefaults.standard.set(state, forKey: stateDefaultsKey)
    }

    private func loadPlaybackState() {
        guard let state = UserDefaults.standard.dictionary(forKey: stateDefaultsKey) else { return }
        if let time = state["currentTime"] as? TimeInterval {
            currentTime = time
        }
        // ✅ Restaurar repeat/shuffle persistidos
        if let shuffle = state["isShuffleEnabled"] as? Bool {
            isShuffleEnabled = shuffle
        }
        if let repeatRaw = state["repeatMode"] as? String,
           let mode = RepeatMode(rawValue: repeatRaw) {
            repeatMode = mode
        }
    }
}
