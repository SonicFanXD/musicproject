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
    @Published var currentRouteName: String = ""

    /// ✅ Nombre de ruta para mostrar SIEMPRE localizado según el idioma de la
    /// app (antes el default era "Altavoz" hardcodeado → se veía en español
    /// con el idioma en inglés). Para salidas con nombre propio (Bluetooth,
    /// AirPlay) muestra el nombre del dispositivo; para internas, la etiqueta
    /// localizada del tipo.
    var routeDisplay: String {
        switch outputPortType {
        case AVAudioSession.Port.builtInSpeaker.rawValue: return Localization.localized("quality.internalSpeaker")
        case AVAudioSession.Port.builtInReceiver.rawValue: return Localization.localized("quality.internalReceiver")
        case AVAudioSession.Port.headphones.rawValue: return Localization.localized("quality.wiredHeadphones")
        case AVAudioSession.Port.usbAudio.rawValue: return Localization.localized("quality.wiredUsb")
        case AVAudioSession.Port.carAudio.rawValue: return Localization.localized("quality.wirelessCar")
        case AVAudioSession.Port.bluetoothA2DP.rawValue,
             AVAudioSession.Port.bluetoothLE.rawValue,
             AVAudioSession.Port.bluetoothHFP.rawValue:
            return currentRouteName.isEmpty ? Localization.localized("quality.wirelessBt") : currentRouteName
        case AVAudioSession.Port.airPlay.rawValue:
            return currentRouteName.isEmpty ? Localization.localized("quality.wirelessAirPlay") : currentRouteName
        default:
            return currentRouteName.isEmpty ? Localization.localized("quality.internal") : currentRouteName
        }
    }
    // ✅ Tipo de salida (idioma-independiente): la detección por nombre
    // localizado ("Altavoz") fallaba fuera de español. Ahora usamos portType.
    @Published var outputPortType: String = ""
    // ✅ Modelo real del dispositivo (ej. "iPhone 13 Pro") en vez de "iPhone".
    @Published var deviceModelName: String = AudioEngine.resolveDeviceModel()

    // MARK: - Propiedades para la vista de calidad de audio
    // ✅ 3.0.1: aquí vivía `sourceSampleRate`, que solo se escribía en
    // playCurrentSong (nunca en la transición gapless, así que quedaba obsoleto)
    // y que NINGUNA vista leía (grep en todo el proyecto: 0 consumidores).
    // Eliminada: la tasa de referencia real es `sampleRate` del motor.
    @Published var outputSampleRate: Double = 0
    @Published var outputChannelCount: Int = 0
    // ✅ 3.0.1 TELEMETRÍA REAL DE LA SALIDA: son los ÚNICOS datos que iOS expone
    // del dispositivo conectado (no existe API de "tasas que soporta el DAC").
    // Solo lectura, para que la vista de calidad pueda mostrarlos.
    @Published var maximumOutputChannels: Int = 0
    @Published var outputLatencyMs: Double = 0
    @Published var ioBufferDurationMs: Double = 0
    // ✅ FASE C5: búfer I/O que la app PIDIÓ (setPreferredIOBufferDuration). iOS
    // puede conceder otro (redondea en silencio), así que "pedido" y "concedido"
    // se muestran por separado. 0 en Bluetooth: allí no se pide (lo decide iOS).
    @Published var requestedIOBufferDurationMs: Double = 0
    // ✅ FASE C5: tasa REAL del hardware (formato de salida del grafo) frente a la
    // tasa negociada de la sesión. Suelen coincidir; cuando no, es que iOS tuvo
    // que remuestrear en el nodo de salida.
    @Published var hardwareSampleRate: Double = 0
    @Published var audioQualityInfo: String = ""
    // ✅ AUDIÓFILO: indicador de salida bit-perfect (sin remuestreo)
    @Published var isBitPerfect: Bool = false
    /// ✅ FASE C4: motivo EXACTO por el que la salida no es bit-perfect, en forma
    /// estructurada para que la UI lo muestre localizado (el log conserva su
    /// texto en español). `nil` = bit-perfect o sin datos suficientes.
    enum BitPerfectBlockReason: Equatable {
        case dolbyAVPlayer
        case fallbackPlayer
        case unknownSourceRate
        case resampling(source: Double, output: Double)
        case eqOrMono
        case limiter
        case nonWiredRoute
    }
    /// Última causa calculada por `refreshBitPerfect()` (se refresca SIEMPRE, no
    /// solo en la transición, porque la vista de calidad la muestra literal).
    private(set) var bitPerfectBlockReason: BitPerfectBlockReason?
    /// ✅ FASE C4: headroom que el EQ está aplicando de verdad (dB negativos o 0).
    /// Lo escribe `applyOutputGain()`: es el valor REAL, no una estimación.
    private(set) var appliedEQHeadroomDB: Double = 0
    /// ✅ FASE C4: ganancia efectiva de salida (base × headroom del EQ).
    var effectiveOutputGain: Float { outputGain }
    // ✅ AUDIÓFILO: información del codec Bluetooth (si aplica)
    @Published var bluetoothCodec: String = ""
    // ✅ AUDIÓFILO: información del DAC USB conectado
    @Published var usbDACInfo: String = ""
    // ✅ AUDIÓFILO: modo actual de AVAudioSession
    @Published var audioSessionMode: String = ""

    // MARK: - Propiedades para la cola y controles
    @Published var isShuffleEnabled: Bool = UserDefaults.standard.bool(forKey: "com.aurora.shuffleEnabled") {
        didSet {
            if isShuffleEnabled != oldValue {
                UserDefaults.standard.set(isShuffleEnabled, forKey: "com.aurora.shuffleEnabled")
                UserDefaults.standard.synchronize()
            }
        }
    }
    // ✅ FASE A: eliminadas `shuffledPlaylist`/`shuffleIndex`. Eran una SEGUNDA
    // estructura de orden (una cola paralela con su propio puntero) que se
    // actualizaba por caminos distintos de la lista real y podía quedar
    // desincronizada (síntomas: la "siguiente" impredecible al mezclar, o el
    // motor mudo al saltar entre playlists). El orden mezclado vive AHORA en
    // `playbackOrder`: una sola fuente de verdad (ver la sección de cola).
    // ✅ MEJORA QUEUE: cola manual de canciones para reproducir después
    @Published var manualQueue: [Song] = []
    // ✅ FIX cola larga: lista COMPLETA de lo que viene después (cola manual +
    // resto de la playlist, SIN topar). `nextUpQueue` es solo la ventana de 10
    // que pinta la vista de cola; reconstruir la playlist desde esa ventana
    // truncaba la reproducción a 10 canciones en cuanto el usuario tocaba la
    // cola (eliminar/reordenar una fila borraba el resto de la lista).
    private var upcomingQueue: [Song] = []
    @Published var repeatMode: RepeatMode = {
        if let raw = UserDefaults.standard.string(forKey: "com.aurora.repeatMode"),
           let mode = RepeatMode(rawValue: raw) { return mode }
        return .off
    }() {
        didSet {
            if repeatMode != oldValue {
                UserDefaults.standard.set(repeatMode.rawValue, forKey: "com.aurora.repeatMode")
                UserDefaults.standard.synchronize()
            }
        }
    }
    @Published var playbackQueue: [Song] = []
    @Published var nextUpQueue: [Song] = []
    @Published var playHistory: [Song] = []

    // MARK: - Cola de reproducción interna (máquina de estados canónica)
    // ✅ FASE A: dos listas, una sola verdad de ORDEN:
    //   · `originalOrder` = la playlist SIN mezclar, tal como la eligió el
    //     usuario. Es la fuente desde la que se reconstruye el orden al apagar
    //     el aleatorio (nunca al revés).
    //   · `playbackOrder` = el orden REAL de reproducción. Con shuffle OFF es
    //     `originalOrder`; con shuffle ON es `originalOrder` mezclado con la
    //     canción actual fija en el índice 0.
    // `currentIndex` apunta SIEMPRE a la canción actual dentro de `playbackOrder`
    // (sin excepciones): "siguiente"/"anterior" dejan de depender de dos
    // punteros paralelos que podían desincronizarse.
    private var playbackOrder: [Song] = []
    private var originalOrder: [Song] = []
    private(set) var currentIndex: Int = 0

    // ✅ Reloj de reproducción publicado para las vistas de UI
    let clock = PlaybackClock()
    
    // ✅ ViewModel de lyrics line-by-line (optimizado para iPhone 8 Plus)
    // Inicializado diferidamente para evitar ciclo de referencia
    private var _lyricsViewModel: LyricsViewModel?
    var lyricsViewModel: LyricsViewModel {
        if let viewModel = _lyricsViewModel {
            return viewModel
        }
        let viewModel = LyricsViewModel()
        viewModel.connectAudioEngine(self)
        _lyricsViewModel = viewModel
        return viewModel
    }

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
    // Contador para persistir la posición en vivo cada ~15s mientras suena.
    private var persistTickCounter = 0
    private var sampleRate: Double = 44100
    // ✅ RELOJ DE PARED: la posición de reproducción se extrapola con
    // CACurrentMediaTime (monótono) desde un ancla (posición + instante).
    // Es INMUNE a los reinicios del timeline del AVAudioPlayerNode
    // (stop/pausa/reprogramación y gapless encadenado, donde sampleTime
    // se ACUMULA entre canciones) — causa raíz de los saltos de la barra
    // de progreso y de la desincronización en las canciones siguientes.
    private var posAnchor: TimeInterval = 0
    private var wallAnchor: TimeInterval = 0

    /// Fija el ancla: la posición actual es `pos` desde este instante.
    private func anchorPlaybackPosition(_ pos: TimeInterval) {
        posAnchor = duration > 0 ? min(max(pos, 0), duration) : max(pos, 0)
        wallAnchor = CACurrentMediaTime()
    }

    /// Posición de reproducción extrapolada (solo mientras isPlaying).
    // ✅ TRACKING de archivo programado: permite a `resume()` detectar si el
    // nodo quedó sin archivo programado (por pausa durante una reprogramación
    // asíncrona) y re-programarlo en vez de quedarse en silencio.
    /// Calcula el momento exacto en que el segmento actual terminará de sonar.
    /// Retorna nil si no se puede calcular (nodo no reproduciendo o engine detenido).
    private func calculateSegmentEndTime() -> AVAudioTime? {
        guard playerNode.isPlaying else { return nil }
        guard let lastRender = playerNode.lastRenderTime else { return nil }
        guard let playerTime = playerNode.playerTime(forNodeTime: lastRender) else { return nil }
        return AVAudioTime(sampleTime: playerTime.sampleTime, atRate: playerTime.sampleRate)
    }

    /// ✅ REDISEÑO (elimina el silencio entre canciones): en vez de programar
    /// la siguiente canción reactivamente cuando la actual YA terminó de sonar
    /// (lo que con completionCallbackType .dataPlayedBack significa programarla
    /// DESPUÉS de que ya hubo silencio), ahora se programa por ADELANTADO,
    /// en el mismo nodo con at: nil, mientras la actual todavía está sonando.
    /// Cuando la actual termina de verdad, la siguiente YA está sonando sin
    /// hueco — solo queda reflejar el cambio en la UI (commitChainedSong) y
    /// dejar programada la que sigue. Ver scheduleAheadIfPossible() /
    /// commitChainedSong() más abajo.
    private var chainedAheadIndex: Int?
    private var chainedAheadSong: Song?
    private var chainedAheadFile: AVAudioFile?
    private var chainedAheadFormat: AVAudioFormat?
    private var chainedAheadToken: Int = 0
    // Token del segmento actualmente sonando cuya finalización estamos
    // esperando. Evita que el watchdog y el completion handler real disparen
    // la MISMA transición dos veces (el segundo en llegar se ignora).
    private var activeSegmentToken: Int = 0
    private var nextScheduleToken: Int = 1

    /// Qué índice habría que encadenar a continuación, teniendo en cuenta
    /// repeat-one (repetir la MISMA canción) como caso particular.
    /// ✅ MEJORA REPEAT: mejor manejo de repeat-one con gapless más suave
    private func indexToChainAhead() -> Int? {
        guard !playbackOrder.isEmpty else { return nil }
        if repeatMode == .one {
            // ✅ MEJORA: en repeat-one, verificar que la canción tenga duración válida
            guard let current = currentSong, current.duration > 0 else { return nil }
            return currentIndex
        }
        return computeNextIndex()
    }

    private func clearChainedAhead() {
        chainedAheadIndex = nil
        chainedAheadSong = nil
        chainedAheadFile = nil
        chainedAheadFormat = nil
        chainedAheadToken = 0
    }

    /// ✅ B5: anula la transición YA ENCOLADA sin parar el nodo.
    /// `AVAudioPlayerNode` no permite desprogramar un segmento suelto (`stop()`
    /// descarta toda la cola, incluido el que está sonando), así que el audio
    /// huérfano no se puede borrar: se conserva el índice A PROPÓSITO — con él
    /// puesto, `scheduleAheadIfPossible()` no apila OTRA transición encima de
    /// ese audio huérfano (su guardia es `chainedAheadIndex == nil`) — y se deja
    /// el token en 0. Al terminar la canción actual, `commitChainedSong()` ve
    /// el token inválido, cae al reinicio atómico (`playCurrentSong` →
    /// `playerNode.stop()` descarta el huérfano) y programa la siguiente con el
    /// modo/orden ya actualizados. Coste: esa transición deja de ser gapless.
    private func invalidateChainedAhead() {
        guard chainedAheadIndex != nil else { return }
        chainedAheadToken = 0
    }

    /// ✅ FIX GAPLESS (hallazgo A-1 de la auditoría): un cambio de orden
    /// (aleatorio/repetición) a mitad de canción invalidaba la transición YA
    /// encolada y esa invalidación se pagaba con un HUECO audible en la
    /// SIGUIENTE transición: `commitChainedSong()` ve el token inválido, cae al
    /// respaldo atómico `chainGaplessPlayNext()` → `playCurrentSong()`, que hace
    /// `engine.stop()` + reconexión del grafo + 0.1 s de arranque diferido.
    ///
    /// En vez de dejar el huérfano, se re-siembra el MISMO nodo con la canción
    /// actual en la posición viva —sin tocar la sesión ni reconectar el grafo—
    /// y se vuelve a encadenar contra el orden YA actualizado, así la siguiente
    /// transición sigue siendo gapless (que era el objetivo de 6569d34).
    private func rechainAheadAfterOrderChange() {
        guard isPlaying, !isStopping, !isAVPlayerActive,
              engine.isRunning, let file = audioFile, duration > 0 else {
            // Sin reproducción activa no hay nada encolado que salvar: la
            // próxima canción se programará (ya encadenada) al arrancar.
            invalidateChainedAhead()
            return
        }
        let position = wallClockTime
        AppLog.info(.playback, String(format: "Orden cambiado en %.1fs: re-encadenando sin hueco", position))
        scheduleGeneration += 1
        let generation = scheduleGeneration
        // playerNode.stop() descarta el segmento huérfano ya encolado…
        playerNode.stop()
        clearChainedAhead()
        anchorPlaybackPosition(position)
        currentTime = position
        clock.time = position
        // …y se reprograma la canción ACTUAL desde la posición viva. No se
        // detiene el engine ni se reconecta el grafo: ese era el hueco.
        scheduleFile(file, from: position, generation: generation)
        scheduleAheadIfPossible()
    }

    /// Programa por adelantado, en el mismo nodo (at: nil), la canción que
    /// sigue a la que está sonando AHORA MISMO — sin esperar a que termine.
    /// Así el nodo siempre tiene el siguiente buffer listo y la transición
    /// de audio es continua, sin silencio, para canciones que se conectan.
    /// Solo es posible si el formato coincide con el ya conectado al graph;
    /// si difiere, se deja sin encadenar y la transición se resuelve de
    /// forma reactiva (reinicio atómico con reconexión, con un pequeño gap
    /// inevitable) cuando la canción actual termine.
    private func scheduleAheadIfPossible() {
        guard chainedAheadIndex == nil, isPlaying, !isStopping,
              engine.isRunning, playerNode.isPlaying else { return }
        guard let index = indexToChainAhead(), playbackOrder.indices.contains(index) else { return }
        let song = playbackOrder[index]
        let url = song.url

        let file: AVAudioFile
        if repeatMode == .one, let current = audioFile, currentFileURL == url {
            file = current
        } else if preloadedNextIndex == index, preloadedNextURL == url, let cached = preloadedNextFile {
            clearPreloadedNext()
            file = cached
        } else {
            guard let opened = try? AVAudioFile(forReading: url) else { return }
            file = opened
        }

        let fmt = file.processingFormat
        guard connectedFormatKey == nil || formatKey(fmt) == connectedFormatKey else {
            // ✅ DIAGNÓSTICO GAPLESS (evidencia en dispositivo): si esta línea
            // aparece en los logs justo antes de un punto de unión, el hueco
            // audible es un cambio de formato REAL entre pistas, no un fallo
            // del encadenado. Sin log, ese caso era indistinguible de un bug.
            AppLog.warning(.playback, "Gapless: '\(song.displayName)' NO se encadena (formato \(Int(fmt.sampleRate)) Hz/\(fmt.channelCount)ch ≠ graph \(connectedFormatKey ?? "—"))")
            return
        }

        let framesToPlay = AVAudioFrameCount(file.length)
        guard framesToPlay > 0 else { return }

        let token = nextScheduleToken
        nextScheduleToken += 1
        chainedAheadIndex = index
        chainedAheadSong = song
        chainedAheadFile = file
        chainedAheadFormat = fmt
        chainedAheadToken = token

        let generation = scheduleGeneration
        playerNode.scheduleSegment(
            file,
            startingFrame: 0,
            frameCount: framesToPlay,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.segmentDidFinish(token: token, expectedGeneration: generation)
            }
        }
        if connectedFormatKey == nil {
            connectedFormatKey = formatKey(fmt)
        }
    }

    /// Se llama cuando el segmento ACTIVO (el que se supone está sonando)
    /// terminó de verdad. Puede venir del completion handler real o del
    /// watchdog (red de seguridad) — el chequeo de token asegura que solo
    /// uno de los dos surta efecto.
    private func segmentDidFinish(token: Int, expectedGeneration: Int) {
        guard scheduleGeneration == expectedGeneration,
              token != 0, activeSegmentToken == token,
              isPlaying, !isStopping else { return }
        activeSegmentToken = 0
        AppLog.info(.playback, "Canción terminada: '\(currentSong?.displayName ?? "—")' (\(String(format: "%.1f", duration))s, repeat: \(repeatMode.rawValue))")
        commitChainedSong()
    }

    /// Si ya hay una canción pre-programada y sonando (encadenada por
    /// adelantado), refleja el cambio en la UI/estado y deja programada la
    /// que sigue. Si no había nada encadenado (formato distinto o fin de
    /// playlist), recurre al reinicio atómico como respaldo.
    private func commitChainedSong() {
        guard let index = chainedAheadIndex,
              let song = chainedAheadSong,
              let file = chainedAheadFile,
              let fmt = chainedAheadFormat,
              chainedAheadToken != 0 else {
            stopDisplayTimer()
            chainGaplessPlayNext()
            return
        }
        // ✅ DIAGNÓSTICO GAPLESS (evidencia en dispositivo, no impresiones):
        // cuánto después del fin REAL de la canción anterior (según su reloj de
        // pared y su duración) llegó este callback de fin de segmento. Es el
        // error del punto de unión: ~0-30 ms = encadenado exacto; cientos de ms
        // = el callback llega tarde (típico en Bluetooth/AirPlay) y el ancla de
        // la canción nueva arranca por detrás del audio. Se mide ANTES de
        // promover, porque `duration` aquí es todavía la de la canción anterior.
        let joinLatenessMs = (wallClockTimeUnclamped - duration) * 1000
        let promotedToken = chainedAheadToken
        clearChainedAhead()
        activeSegmentToken = promotedToken

        currentIndex = index
        currentSong = song
        currentFileURL = song.url
        audioFile = file
        duration = Double(file.length) / fmt.sampleRate
        sampleRate = fmt.sampleRate
        currentTime = 0
        clock.time = 0
        anchorPlaybackPosition(0)
        updateNowPlayingInfo()
        updateAudioQuality()
        addToHistory(song)
        updateNextUpQueue()
        saveState()
        preloadNextSong()

        AppLog.info(.playback, String(format: "Gapless: encadenado '%@' (unión %+.0f ms respecto al fin de la anterior)", song.displayName, joinLatenessMs))

        // Dejar programada la que sigue, ahora que esta es la actual.
        scheduleAheadIfPossible()
    }

    /// Reinicio atómico de respaldo: se usa SOLO cuando no había nada
    /// pre-encadenado (cambio de formato, fin de lista, o el nodo no estaba
    /// en condiciones de encolar por adelantado). Aquí sí puede haber un
    /// pequeño gap (~0.15s), inevitable si hace falta reconectar el graph.
    @discardableResult
    private func chainGaplessPlayNext() -> Bool {
        guard let index = indexToChainAhead() else {
            stop()
            return true
        }
        // ✅ DIAGNÓSTICO GAPLESS: la transición de respaldo NO es gapless
        // (reinicio atómico con reconexión y 0.1 s de arranque diferido). Si el
        // usuario oye un hueco, este log dice exactamente por qué: aquí no había
        // nada pre-encadenado.
        AppLog.warning(.playback, "Gapless: transición de respaldo (puede haber hueco) hacia '\(playbackOrder[index].displayName)'")
        currentIndex = index
        playCurrentSong()
        return true
    }
    
   
    /// Posición EXACTA sin clamp — usada por el watchdog para detectar cuándo
    // el audio realmente terminó. El clamp a duration impedía que el watchdog
    // se disparara (wallClockTime NUNCA podía >= duration + margen).
    private var wallClockTimeUnclamped: TimeInterval {
        guard isPlaying, !isAVPlayerActive else { return posAnchor }
        let t = posAnchor + (CACurrentMediaTime() - wallAnchor)
        return max(t, 0)
    }

    private var wallClockTime: TimeInterval {
        guard isPlaying, !isAVPlayerActive else { return posAnchor }
        let t = posAnchor + (CACurrentMediaTime() - wallAnchor)
        // ✅ Clampear para la UI (barra de progreso no debe pasar 100%).
        return duration > 0 ? min(max(t, 0), duration) : max(t, 0)
    }

    // ✅ FIX "corte feo" entre canciones: recordar el formato ya conectado al
    // graph. Si la siguiente canción tiene el mismo formato, NO se detiene ni
    // reinicia el engine (solo se reprograma el nodo) → transición sin hueco.
    private var connectedFormatKey: String?
    // ✅ FIX reinicio desde punto aleatorio: recordar el archivo cargado para
    // detectar cuándo se reinicia la MISMA canción (repeat-one / álbum de una
    // sola canción) y aplicar el re-programado con delay.
    private var currentFileURL: URL?
    // ✅ PRECARGA de la siguiente canción: mientras suena la actual, abrimos
    // el AVAudioFile de la siguiente en background para que la transición sea
    // casi instantánea. Se limpia si cambia la playlist o al parar.
    // Es DISTINTA del encadenado gapless (que causaba saltos aleatorios):
    // aquí solo se deja el archivo "caliente"; la reproducción sigue pasando
    // por el reinicio atómico de playCurrentSong(), que arranca siempre en 0.
    private var preloadedNextIndex: Int?
    private var preloadedNextURL: URL?
    private var preloadedNextFile: AVAudioFile?
    // ✅ CROSSFADE: eliminado por completo (era la fuente principal de bugs
    // ✅ CROSSFADE: eliminado por completo (era la fuente principal de bugs
    // de sincronización y el gapless de chainNextSong lo hace innecesario).
    // Las referencias en vistas también fueron removidas.

    // ✅ "Mantener pantalla encendida" gestionado aquí (centralizado):
    // antes solo vivía en NowPlayingView y se perdía al cerrarla.
    var isKeepScreenOnEnabled: Bool = false {
        didSet { updateIdleTimer() }
    }

    // ✅ Ruta de salida actual SIN consultar AVAudioSession en cada llamada:
    // outputPortType ya se actualiza en cada cambio de ruta (coste ~0 y no
    // despierta el servidor de audio, importante para la batería en A11).
    private var currentPortType: String {
        outputPortType.isEmpty
            ? (AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "")
            : outputPortType
    }

    private var isBluetoothRoute: Bool {
        let t = currentPortType
        return t == AVAudioSession.Port.bluetoothA2DP.rawValue ||
               t == AVAudioSession.Port.bluetoothLE.rawValue ||
               t == AVAudioSession.Port.bluetoothHFP.rawValue
    }

    /// ✅ 3.0.1: `lineOut` (dock / salida digital del conector Lightning) es una
    /// salida CABLEADA real y antes se clasificaba como inalámbrica: el indicador
    /// bit-perfect se apagaba y no se pedía la tasa nativa del archivo. Esta misma
    /// propiedad es la que usa `configureSession` para decidir el modo
    /// `.measurement`, así que un dock cableado también recibe ese modo.
    private var isWiredRoute: Bool {
        let t = currentPortType
        return t == AVAudioSession.Port.headphones.rawValue ||
               t == AVAudioSession.Port.usbAudio.rawValue ||
               t == AVAudioSession.Port.lineOut.rawValue
    }

    // MARK: - Equalizador
    private var equalizerNode: AVAudioUnitEQ?
    // ✅ PERSISTENCIA (Fase 6): el EQ (activado + preset) sobrevivía solo a la
    // sesión — se apagaba y volvía a "Flat" en cada arranque. El preset se guarda
    // por rawValue (String) y se valida al leer.
    @Published var isEQEnabled: Bool = UserDefaults.standard.bool(forKey: "com.aurora.eqEnabled") {
        didSet {
            if isEQEnabled != oldValue {
                UserDefaults.standard.set(isEQEnabled, forKey: "com.aurora.eqEnabled")
            }
        }
    }
    @Published var eqPreset: EQPreset = {
        if let raw = UserDefaults.standard.string(forKey: "com.aurora.eqPreset"),
           let preset = EQPreset(rawValue: raw) { return preset }
        return .flat
    }() {
        didSet {
            if eqPreset != oldValue {
                UserDefaults.standard.set(eqPreset.rawValue, forKey: "com.aurora.eqPreset")
            }
        }
    }
    // ✅ PROTECCIÓN ANTI-CLIPPING: atenuación fija anti-distorsión (SIN Audio
    // Unit en la cadena, para que la señal no pase por ningún procesador
    // dinámico). Aplica 0.99 (≈ -0.09 dB) sobre la salida.
    // ✅ BIT-PERFECT: desactivada por defecto. Con la protección activa TODOS
    // los samples salen escalados (x0.99), así que la ruta no puede ser
    // bit-perfect aunque el resto de condiciones se cumplan: el usuario tenía
    // que apagarla a mano para que el indicador se encendiera. La música a
    // 0 dBFS no satura si nada añade ganancia, y el headroom del EQ sigue
    // calculándose por separado, así que el valor por defecto es 1.0.
    // ✅ PERSISTENCIA (Fase 6): el usuario configura su sonido una vez y no
    // debería rehacerlo en cada arranque. Mismo patrón que isMonoAudioEnabled:
    // se lee al crear el motor y se guarda con cada cambio. Este ajuste mueve la
    // ganancia base de salida (0.99 con protección anti-clipping, 1.0 sin ella) y
    // el indicador bit-perfect, así que recordarlo es lo coherente.
    @Published var isLimiterEnabled: Bool = UserDefaults.standard.bool(forKey: "com.aurora.limiterEnabled") {
        didSet {
            if isLimiterEnabled != oldValue {
                UserDefaults.standard.set(isLimiterEnabled, forKey: "com.aurora.limiterEnabled")
            }
        }
    }
    // ✅ BLUETOOTH OPTIMIZATION: ajustes para mejorar calidad en BT
    @Published var isBluetoothOptimizationEnabled: Bool = false
    // ✅ Audio Mono: mezcla ambos canales en uno para usuarios con audífono único
    @Published var isMonoAudioEnabled: Bool = UserDefaults.standard.bool(forKey: "com.aurora.monoAudio") {
        didSet {
            if isMonoAudioEnabled != oldValue {
                UserDefaults.standard.set(isMonoAudioEnabled, forKey: "com.aurora.monoAudio")
                // ✅ FIX mono: además del downmix en el grafo, forzar mono a
                // nivel de AVAudioSession — es lo ÚNICO que iOS respeta en el
                // hardware de salida (el mixer del grafo no llega a algunos
                // dispositivos/rutas de audio).
                applySystemMonoOutput()
            }
        }
    }

    /// Downmix mono a nivel de sesión de audio (afecta TODA la salida).
    private func applySystemMonoOutput() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setPreferredOutputNumberOfChannels(isMonoAudioEnabled ? 1 : 2)
        } catch {
            AppLog.warning(.playback, "No se pudo fijar canales de salida: \(error.localizedDescription)")
        }
    }

    // MARK: - Flags y control
    private var isStopping = false
    private var playbackErrorCount = 0
    private var scheduleGeneration = 0

    // MARK: - Reproductor de respaldo (AVPlayer)
    private var avPlayer: AVPlayer?
    private var avTimeObserver: Any?
    private var avEndObserver: NSObjectProtocol?
    /// ✅ A9+C3: era `private var` → la vista de calidad NO podía saber que el
    /// motor propio estaba fuera de juego, así que la caída al reproductor de
    /// respaldo (AVPlayer), que pierde EQ, mono, headroom y bit-perfect, ocurría
    /// EN SILENCIO. Publicado para que el chip de AudioQualityDetailView aparezca
    /// y desaparezca solo. No cambia ninguno de los usos internos del flag y
    /// ninguna otra vista lo lee. El threading no cambia: se asigna junto a
    /// `currentSong`/`currentTime`/`duration`, que ya eran @Published.
    @Published private(set) var isUsingFallback = false
    /// ✅ AVPlayer es el BACKEND que está sonando: respaldo por fallo del motor
    /// propio O modo Dolby intencional. Todo lo que pregunta "¿quién reproduce?"
    /// (anclaje de posición, pausa, seek, watchdog, observadores del AVPlayer,
    /// reconexión de ruta, bit-perfect) lee ESTE flag. `isUsingFallback` queda
    /// solo para lo que es un problema de verdad (el chip de calidad).
    private(set) var isAVPlayerActive = false
    /// ✅ MODO DOLBY: AVPlayer porque el codec del archivo (E-AC-3/AC-3) no lo
    /// decodifica AVAudioEngine. Es intencional: no marca el chip de respaldo
    /// ni se registra como error.
    @Published private(set) var isDolbyPlayback = false

    /// ✅ Motivo por el que AVPlayer pasa a ser el reproductor activo.
    enum FallbackReason: Equatable {
        /// El motor propio no pudo cargar/arrancar el archivo (fallo real).
        case engineFailure
        /// El codec no es decodificable por AVAudioEngine (Dolby E-AC-3/AC-3):
        /// modo intencional.
        case codecUnsupported
    }

    private let stateDefaultsKey = "com.aurora.playbackState"
    private var hasRestored: Bool = false

    override init() {
        super.init()
        // ✅ Mono: restaurar el ajuste persistido a nivel de sesión al arrancar
        applySystemMonoOutput()
        // ✅ Crossfade eliminado: limpiar preferencias obsoletas
        UserDefaults.standard.removeObject(forKey: "com.aurora.crossfadeEnabled")
        UserDefaults.standard.removeObject(forKey: "com.aurora.crossfadeDuration")
        setupSession()
        setupEngine()
        setupEqualizer()
        observeRouteChanges()
        observeInterruptions()
        // ✅ FIX detección inicial: forzar actualización de ruta al iniciar
        // para detectar dispositivos conectados al arrancar la app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateRouteName()
            self?.updateAudioQuality()
        }
        setupRemoteCommandCenter()
        setupBackgroundNotification()
        setupPlaybackStateObserver()
        observeEngineConfigurationChanges()
        setupBackgroundLifecycleObservers()
        setupPersistOnBackgroundObserver()
        setupMemoryWarningObserver()
        loadPlaybackState()
    }

    // ✅ RESISTENCIA RAM: ante un aviso de memoria del sistema (bibliotecas
    // grandes en iPhone 8 / 2GB), liberar las cachés de colores de carátulas
    // y el artwork del lock screen — se regeneran solos bajo demanda, así
    // que iOS no termina el proceso ni corta el audio en segundo plano.
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            AppLog.warning(.performance, "Aviso de memoria: liberando cachés (colores + miniaturas de carátula + lock screen)")
            AppTheme.artworkColorCache.removeAllObjects()
            AppTheme.thumbnailCache.removeAllObjects()
            self?.cachedNowPlayingArtwork = nil
            self?.cachedArtworkSongID = nil
        }
    }

    // ✅ Persistencia forzada: cuando la app se cierra o va a segundo plano,
    // sincroniza UserDefaults inmediatamente para evitar perder shuffle/repeat
    // si iOS termina el proceso antes del sync automático.
    private func setupPersistOnBackgroundObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.saveState()
            UserDefaults.standard.synchronize()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.saveState()
            UserDefaults.standard.synchronize()
        }
    }

    // ✅ Caché del artwork para Now Playing: se genera UNA vez por canción,
    // no en cada refresh (cada 0.8s fg / 1.5s bg) como antes. Antes renderizaba
    // una imagen 1200×1200 en cada tick → gasto enorme de CPU/batería.
    private var cachedArtworkSongID: UUID?
    private var cachedNowPlayingArtwork: MPMediaItemArtwork?
    // ✅ FASE B2: conteo de pistas/discos del álbum para MPNowPlayingInfo. El
    // motor NO conoce la biblioteca (`FileAccessService`): la app le inyecta
    // este closure al arrancar (ContentView) y así
    // MPMediaItemPropertyAlbumTrackCount/DiscCount salen del MISMO agrupado de
    // álbumes que ve el usuario. Sin proveedor no se publican (son campos
    // opcionales para iOS).
    var albumCountsProvider: ((Song) -> (tracks: Int, discs: Int)?)?
    // ✅ FASE B3: marca del último envío REAL a MPNowPlayingInfoCenter. El
    // display timer (0.4 s fg / 3 s bg) ya NO refresca now-playing en cada tick:
    // iOS extrapola el elapsed con `playbackRate`. La red de seguridad se
    // conserva, pero ahora es de 2 s y además CEDE SIEMPRE ante un cambio
    // publicable (canción/estado/duración, ver publishIfNeeded): era el hueco
    // por el que CC/bloqueo podían quedarse con la canción anterior al retroceder.
    private var lastNowPlayingPublishTime: TimeInterval = 0
    // ✅ FIX (sincronización de la barra): 30 s era demasiado para una ventana
    // que ahora solo se salta si NADA cambió. 2 s acota cualquier deriva
    // residual de la extrapolación de iOS y sigue siendo 2,5× más barato que el
    // refresco de 0.8 s que existía antes de la FASE B.
    private let nowPlayingRefreshInterval: TimeInterval = 2
    // ✅ FIX (restauración al retroceder): qué se publicó la última vez. La red
    // de seguridad temporal solo puede saltarse un tick si NADA de esto cambió;
    // un cambio de identidad/estado se publica SIEMPRE (no puede quedar tapado
    // por la ventana de refresco).
    private var lastPublishedSongID: UUID?
    private var lastPublishedIsPlaying: Bool = false
    private var lastPublishedDuration: TimeInterval = 0

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
            stopDisplayTimer()  // 🛡 Red de seguridad: sin timer, cero CPU en background.
            if engine.isRunning {
                engine.pause()
            }
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            // ✅ Reactivar la sesión (necesario para audio en background continuo).
            // La opción .notifyOthersOnDeactivation solo aplica al desactivar
            // la sesión (stop()), no al activarla.
            try session.setActive(true)
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
                // ✅ FIX GAPLESS: el engine se detuvo (iOS lo mató en segundo
                // plano) → cualquier segmento pre-encadenado murió con él. Sin
                // limpiar el rastreo y volver a encadenar, la PRIMERA transición
                // tras volver sonaba por el respaldo atómico (hueco).
                clearChainedAhead()
                anchorPlaybackPosition(position)
                scheduleFile(file, from: position)
                scheduleAheadIfPossible()
            } catch {
                AppLog.error(.playback, error, context: "background: reiniciar engine")
            }
        }

        // ✅ REDUCIR la frecuencia de actualización del display timer en
        // segundo plano para ahorrar batería (el UI no necesita updates
        // tan frecuentes cuando no se ve la pantalla), pero NO detenerlo
        // completamente porque el sistema de lyrics depende de clock.time
        // que se actualiza vía este timer. Si se detiene, las lyrics dejan
        // de sincronizarse al volver a primer plano.
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
                // ✅ FIX GAPLESS: mismo caso que en segundo plano — al rearrancar
                // el engine muere cualquier segmento pre-encadenado; hay que
                // limpiar el rastreo y volver a encadenar la siguiente pista o
                // la próxima transición paga el respaldo atómico (hueco).
                clearChainedAhead()
                anchorPlaybackPosition(position)
                scheduleFile(file, from: position)
                scheduleAheadIfPossible()
            } catch {
                AppLog.error(.playback, error, context: "foreground: reiniciar engine")
            }
        }
    }

    /// Sincroniza currentTime y clock.time con el reloj de pared.
    /// Llamado al volver de segundo plano para evitar que la barra se adelante.
    private func syncCurrentTimeFromRenderThread() {
        let current = wallClockTime
        currentTime = current
        clock.time = current
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

        // ⚠️ FIX silencio tras desconectar audífonos: antes solo se
        // reconectaba el playerNode con el formato correcto DENTRO del
        // catch (si engine.start() lanzaba error). Pero tras un cambio de
        // ruta (audífonos → altavoz), engine.start() casi siempre funciona
        // SIN lanzar error, aunque el playerNode siga conectado con el
        // formato de la ruta VIEJA — resultado: primer intento de reanudar
        // suena en silencio; recién en un reinicio posterior (por casualidad,
        // cuando el sistema ya terminó de estabilizar la ruta) se oía. Ahora
        // se reconecta SIEMPRE con el formato actual antes de arrancar, sin
        // depender de que el primer intento falle para corregirlo.
        if let file = audioFile {
            reconnectPlayerNode(format: file.processingFormat)
        } else {
            reconnectPlayerNode(format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) ?? engine.outputNode.outputFormat(forBus: 0))
        }

        // 2. Arrancar el engine con un reintento tras reconectar el grafo
        do {
            try engine.start()
        } catch {
            AppLog.error(.playback, error, context: "startEngineSafely: primer intento, reintentando")
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
            // ✅ 3.0.1 DIAGNÓSTICO: formato de E/S ANTES de reconfigurar. Es la
            // prueba de qué tasa/canales había negociado el hardware.
            let ioBefore = self.engine.outputNode.outputFormat(forBus: 0)
            AppLog.info(.playback, String(format: "Configuración del engine cambió; reconfigurando (E/S antes: %.0f Hz · %d canales)", ioBefore.sampleRate, ioBefore.channelCount))
            // ⚠️ Cualquier cambio de configuración (no solo cuando el engine
            // llega a detenerse del todo) puede invalidar lo que había en la
            // cola del playerNode — incluida una canción pre-encadenada por
            // adelantado (scheduleAheadIfPossible). Si no limpiamos este
            // rastreo aquí, cuando la canción "activa" termine, commitChainedSong()
            // podía dar por sonando una canción que en realidad el grafo ya
            // había descartado silenciosamente durante la reconfiguración —
            // el síntoma: la UI/portada cambia a la siguiente pero el audio
            // que se sigue escuchando (residual, en el driver) es el de la
            // canción anterior, desde un punto random.
            // ⛔️ FIX salto de canción al reanudar: invalidar TODOS los
            // completions pendientes ANTES de tocar el nodo (patrón del seek).
            // Si un completion obsoleto llegara a ejecutarse en pleno cambio
            // de ruta (audífonos desconectados), segmentDidFinish() pasaría el
            // guard (misma generación + isPlaying) y avanzaría a la SIGUIENTE
            // canción mientras el usuario espera reanudar la que estaba en pausa.
            // Solo se interviene con reproducción ACTIVA: en pausa no se toca la
            // cola (resume() la retoma intacta o la reprograma si el engine se
            // detuvo), y el generación bump solo aplica a segmentos en vivo.
            if self.isPlaying, let file = self.audioFile {
                self.scheduleGeneration += 1
                self.clearChainedAhead()
                self.playerNode.stop()
                do {
                    try self.startEngineSafely()
                    // ✅ 3.0.1 DIAGNÓSTICO: y el formato DESPUÉS, para ver si la
                    // reconfiguración cambió la tasa de salida.
                    let ioAfter = self.engine.outputNode.outputFormat(forBus: 0)
                    AppLog.info(.playback, String(format: "Engine reconfigurado (E/S ahora: %.0f Hz · %d canales)", ioAfter.sampleRate, ioAfter.channelCount))
                    let position = min(max(self.currentTime, 0), self.duration)
                    self.anchorPlaybackPosition(position)
                    // ✅ 3.0.1 BIT-PERFECT: reafirmar la tasa NATIVA antes de
                    // reprogramar (la función solo actúa en ruta cableada). Sin
                    // esto, una reconfiguración que deje la salida a 48 kHz con un
                    // archivo de 44.1 sonaba REMUESTREADA hasta el siguiente
                    // pause/play. Es idempotente: si la tasa ya coincide, sale sin
                    // tocar la sesión (y sin re-disparar este observer).
                    self.reassertNativeSampleRateIfNeeded()
                    self.scheduleFile(file, from: position, generation: self.scheduleGeneration)
                    self.scheduleAheadIfPossible()
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
        configureSession(allowAirPlay: true, didRetryDegraded: false)
    }
    
    // ✅ AUDIÓFILO: método público para cambiar el modo de audio dinámicamente
    func setAudioSessionMode(_ modeIndex: Int) {
        UserDefaults.standard.set(modeIndex, forKey: "com.aurora.audioSessionMode")
        UserDefaults.standard.synchronize()
        // Reconfigurar la sesión con el nuevo modo
        configureSession(allowAirPlay: true, didRetryDegraded: false)
    }

    /// Configura la sesión de audio. Si el arranque ocurre antes de que el
    /// audio server esté listo (cold start en A11), setCategory/setActive
    /// puede devolver -50 (paramErr) — error TRANSITORIO que el catch anterior
    /// tragaba sin más, dejando la sesión sin configurar hasta la siguiente
    /// canción. Ahora se reintenta UNA vez degradado (sin AirPlay).
    private func configureSession(allowAirPlay: Bool, didRetryDegraded: Bool) {
        let session = AVAudioSession.sharedInstance()
        
        // ✅ AUDIÓFILO: obtener el modo preferido de configuración
        let modeIndex = UserDefaults.standard.integer(forKey: "com.aurora.audioSessionMode")
        // ✅ .measurement desactiva el procesamiento del sistema (ideal por cable),
        // pero en Bluetooth y altavoz interno puede forzar tasas bajas y rutas
        // inestables. Se aplica SOLO en salidas cableadas (jack / USB DAC).
        let sessionMode: AVAudioSession.Mode = (modeIndex == 1 && isWiredRoute) ? .measurement : .default
        
        do {
            var options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]
            if allowAirPlay { options.insert(.allowAirPlay) }
            try session.setCategory(
                .playback,
                mode: sessionMode,
                // ✅ MÁXIMA CALIDAD BT: SOLO perfiles de música (A2DP/AirPlay).
                // Quitado .allowBluetoothHFP: HFP es el perfil de llamadas (SCO,
                // mono 8/16kHz, mSBC/CVSD) — si lo permitimos y el A2DP falla o
                // tarda, iOS puede enrutar la música por HFP y suena comprimido.
                // Los controles del auricular (play/pausa/siguiente) siguen
                // funcionando por AVRCP sobre A2DP sin necesidad de HFP.
                options: options
            )

            // ✅ AUDIÓFILO (BT): en A2DP la latencia la impone el ENLACE
            // (100-300 ms), así que un buffer de render de 8 ms NO reduce la
            // latencia percibida: solo multiplica las interrupciones de render
            // por segundo en el A11 y arriesga underrun (microcortes/clicks que
            // se oyen como pérdida de calidad). En Bluetooth no se pide buffer:
            // se deja el que iOS tenga por defecto. Los buffers cortos solo se
            // piden en ruta cableada (jack / DAC USB), donde sí bajan latencia.
            // ✅ Mejor calidad con latencia mínima: probamos buffers cortos en
            // orden descendente con fallback robusto. iOS 16 en A11 (iPhone 8)
            // devuelve error -50 (paramErr) con 0.02, así que vamos bajando
            // hasta encontrar el menor soportado por el hardware/DAC actual.
            // ✅ OPTIMIZACIÓN: buffers de 8-10ms para menor latencia sin glitches
            let bufferDurations: [TimeInterval] = isBluetoothRoute ? [] : [0.008, 0.01, 0.015, 0.02]
            // ✅ DIAGNÓSTICO: se guarda el último valor PEDIDO para poder compararlo
            // con el CONCEDIDO (setPreferredIOBufferDuration no falla cuando el
            // hardware no lo soporta: redondea en silencio al más cercano).
            var requestedBufferDuration: TimeInterval = session.ioBufferDuration
            for duration in bufferDurations {
                do {
                    try session.setPreferredIOBufferDuration(duration)
                    requestedBufferDuration = duration
                    break
                } catch {
                    // ✅ Esperado en A11 (iPhone 8): no es un error real,
                    // solo probamos el siguiente buffer más corto soportado.
                    AppLog.debug(.playback, "Buffer \(Int(duration * 1000))ms no soportado, probando siguiente")
                }
            }
            // ✅ 3.0.1: aquí NO se puede leer el concedido — en el instante de la
            // petición el audio server todavía no lo ha aplicado (y
            // setPreferredIOBufferDuration no falla cuando el hardware no lo
            // soporta: redondea en silencio). El valor REAL se registra 0.3 s
            // después de activar la sesión.
            if isBluetoothRoute {
                AppLog.info(.playback, "Buffer I/O: sin petición en ruta Bluetooth (lo decide iOS)")
            } else {
                AppLog.info(.playback, String(format: "Buffer I/O pedido: %.1f ms (el concedido se comprueba tras activar)", requestedBufferDuration * 1000))
            }
            // ✅ FASE C5: publicar lo PEDIDO (0 en Bluetooth: allí no se pide) para
            // que la vista de calidad lo muestre junto al concedido real. Va al
            // hilo principal porque configureSession también se alcanza desde
            // rutas de reactivación del engine.
            let requestedMs = isBluetoothRoute ? 0 : requestedBufferDuration * 1000
            DispatchQueue.main.async { [weak self] in
                self?.requestedIOBufferDurationMs = requestedMs
            }

            // ✅ Línea base de sample rate SIN forzar 44.1 kHz: pedir siempre
            // 44100 al reconfigurar la sesión reclocaba el hardware si el archivo
            // cargado (o el DAC) estaba en otra tasa. Ahora se usa la tasa del
            // archivo actual y, si no hay ninguno cargado, la que ya tiene el
            // sistema: nunca se cambia el reloj a ciegas.
            // setPreferredSampleRate NO remuestrea la señal (solo selecciona el
            // reloj del DAC/hardware más cercano soportado); el ajuste por
            // canción (playCurrentSong) pide el rate NATIVO del archivo.
            // ✅ AUDIÓFILO (BT): en Bluetooth la tasa la decide el ENLACE (A2DP
            // negocia su propio reloj de 44.1 kHz — o 48 kHz en algunos
            // receptores). Pedir aquí la tasa del archivo contradecía la regla
            // de `playCurrentSong` (donde Bluetooth SÍ está excluido) y podía
            // forzar una reconfiguración de ruta al abrir la app con unos
            // auriculares BT ya conectados → click/microcorte audible. La tasa
            // nativa solo se pide por cable (jack / DAC USB).
            let baselineRate = sampleRate > 0 ? sampleRate : session.sampleRate
            if !isBluetoothRoute, baselineRate > 0, abs(session.sampleRate - baselineRate) > 1 {
                do {
                    try session.setPreferredSampleRate(baselineRate)
                } catch {
                    AppLog.debug(.playback, "SetPreferredSampleRate base no aplicado: \(error.localizedDescription)")
                }
            }

            // Mantener el sample rate del archivo cuando el DAC lo soporta: el
            // remuestreo final lo hace el mainMixer en la salida física
            // (DAC/BT/altavoz) solo cuando el hardware no acepta el rate nativo.
            // ✅ La opción .notifyOthersOnDeactivation solo tiene efecto al
            // DESACTIVAR la sesión (abajo, en stop()); al activarla es inerte.
            try session.setActive(true)
            // ✅ 3.0.1: buffer REAL concedido, leído cuando el audio server ya
            // aplicó (o redondeó) la petición. Comparado con "pedido" dice si el
            // hardware aceptó los 8 ms o si sirvió su valor por defecto.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let granted = AVAudioSession.sharedInstance().ioBufferDuration
                AppLog.info(.playback, String(format: "Buffer I/O concedido: %.2f ms (pedido: %.1f ms)", granted * 1000, requestedBufferDuration * 1000))
            }
            updateRouteName()
            updateAudioQuality()
        } catch {
            AppLog.error(.playback, error, context: "setupSession")
            // ✅ FIX -50 al arranque: reintento degradado UNA vez (sin AirPlay),
            // también cubre combinaciones de opciones rechazadas por el HW.
            if !didRetryDegraded {
                AppLog.warning(.playback, "setupSession falló; reintentando degradado (sin AirPlay)")
                configureSession(allowAirPlay: false, didRetryDegraded: true)
            }
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
            // ✅ CALIDAD: extremos como SHELVES (estándar en EQ gráfico de 10
            // bandas). Un paramétrico de ancho 1.0 en 32 Hz/16 kHz solo levanta
            // una colina estrecha: el realce de "Bajos" no cubría 20–40 Hz de
            // verdad y el de "Agudos" dejaba el aire (>16 kHz) intacto. Con
            // lowShelf/highShelf la curva se extiende plana hasta el extremo.
            band.filterType = index == 0 ? .lowShelf
                : (index == frequencies.count - 1 ? .highShelf : .parametric)
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }

        // ✅ PERSISTENCIA: las bandas nacen a 0 (bucle de arriba), así que un EQ
        // restaurado desde UserDefaults habría dicho "Bajos" en Ajustes y sonado
        // plano. Reaplicar aquí el preset guardado deja el estado auditivo igual
        // al que el usuario dejó.
        for (index, gain) in eqPreset.gains.enumerated() where index < eq.bands.count {
            eq.bands[index].gain = gain
        }
        // Procesa solo si está activado Y el preset no es plano (misma regla que
        // updateEQBypassState(): "flat" = bypass total, cero biquads de más).
        eq.bypass = !(isEQEnabled && eqPreset != .flat)
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

        // Desconectar cualquier cadena previa de forma segura.
        if !engine.outputConnectionPoints(for: playerNode, outputBus: 0).isEmpty {
            engine.disconnectNodeOutput(playerNode)
        }
        if let eq = equalizerNode, !engine.outputConnectionPoints(for: eq, outputBus: 0).isEmpty {
            engine.disconnectNodeOutput(eq)
        }
        if !engine.outputConnectionPoints(for: monoMixerNode, outputBus: 0).isEmpty {
            engine.disconnectNodeOutput(monoMixerNode)
        }

        // ✅ CALIDAD + BATERÍA: cada nodo del grafo es una etapa de conversión
        // y CPU por buffer. El mezclador mono SOLO se inserta si el mono está
        // activo (antes estaba SIEMPRE, incluso en estéreo, sin aportar nada).
        var last: AVAudioNode = playerNode
        if let eq = equalizerNode {
            engine.connect(last, to: eq, format: format)
            last = eq
        }
        if isMonoAudioEnabled {
            engine.connect(last, to: monoMixerNode, format: format)
            engine.connect(monoMixerNode, to: mixer, format: monoMixerOutputFormat())
        } else {
            engine.connect(last, to: mixer, format: format)
        }
    }

    /// ✅ Mono: salida de 1 canal del mezclador de downmix. Esta función ya
    /// solo se usa cuando el mono está activo (en estéreo el nodo ni siquiera
    /// entra en el grafo).
    private func monoMixerOutputFormat() -> AVAudioFormat {
        let rate = sampleRate > 0 ? sampleRate : 44100
        return AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)
            ?? engine.mainMixerNode.outputFormat(forBus: 0)
    }

    func toggleEQ() {
        let wasProcessing = isEQEnabled && eqPreset != .flat
        isEQEnabled.toggle()
        updateEQBypassState()
        let willProcess = isEQEnabled && eqPreset != .flat

        // ✅ MÁXIMA CALIDAD: solo se reinicia la reproducción si el estado de
        // procesamiento REAL cambió (flat → sin procesamiento). Encender o
        // apagar el interruptor con preset plano no altera la señal → se evita
        // el mini-corte de ~20ms que antes ocurría siempre.
        // Asegurar que el cambio se aplique al playback activo sin perder posición
        if wasProcessing != willProcess, isPlaying, playerNode.isPlaying, let file = audioFile {
            // Reiniciar reproducción desde la posición actual para que el EQ se aplique de inmediato
            // ⚠️ CRÍTICO: incrementar scheduleGeneration ANTES de stop() para que el completion
            // handler del segmento anterior quede obsoleto y NO dispare playNext()
            scheduleGeneration += 1
            let currentPosition = currentTime
            playerNode.stop()
            // playerNode.stop() descarta cualquier canción pre-encadenada.
            clearChainedAhead()
            // ✅ Mantener consistencia del reloj de display tras re-programar desde currentPosition
            anchorPlaybackPosition(currentPosition)

            // Reprogramar en el siguiente runloop para evitar glitches de audio
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                guard let self = self, self.isPlaying else { return }
                self.scheduleFile(file, from: currentPosition)
                self.playerNode.play()
                self.scheduleAheadIfPossible()
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
        updateEQBypassState()
        AppLog.info(.playback, "EQ preset: \(preset.displayName)")
    }

    /// ✅ MÁXIMA CALIDAD: el nodo EQ solo procesa cuando hace falta. "Flat"
    /// (ganancias a 0) → bypass total del AVAudioUnitEQ → la señal pasa por la
    /// ruta limpia sin 10 biquads en cascada (cero redondeo acumulado y cero
    /// CPU extra por buffer).
    private func updateEQBypassState() {
        equalizerNode?.bypass = !(isEQEnabled && eqPreset != .flat)
        applyOutputGain()
    }

    /// ✅ LIMITER: activar/desactivar limiter para prevenir distorsión
    func toggleLimiter() {
        isLimiterEnabled.toggle()
        updateEQBypassState()
        // ✅ FIX telemetría honesta: en Bluetooth la ganancia NO la fija este
        // ajuste — la ruta impone su propio margen (0.89 ≈ -1 dB) para que el
        // codificador AAC/SBC no sature con picos entre muestras, esté el
        // limiter activado o no. El log anterior afirmaba "base 0.99" / "base
        // 1.0" también en BT, así que el usuario leía un valor que no era el
        // que sonaba. Ahora se declara la base REAL de la ruta activa.
        let gainNote: String
        if isBluetoothRoute {
            gainNote = "margen de ruta Bluetooth (base 0.89 ≈ -1 dB) · este ajuste no cambia la ganancia en BT"
        } else {
            gainNote = isLimiterEnabled ? "base 0.99" : "base 1.0 (bit-perfect posible)"
        }
        AppLog.info(.playback, "Protección anti-clipping: \(isLimiterEnabled ? "activada" : "desactivada") · \(gainNote)")
    }

    /// ✅ BLUETOOTH OPTIMIZATION: activar optimizaciones para BT
    func toggleBluetoothOptimization() {
        isBluetoothOptimizationEnabled.toggle()
        // Al activar, forzar reconfiguración de sesión con optimizaciones BT
        if isBluetoothOptimizationEnabled {
            configureSessionWithBluetoothOptimization()
        }
        AppLog.info(.playback, "Optimización Bluetooth: \(isBluetoothOptimizationEnabled ? "activada" : "desactivada")")
    }

    /// ✅ BLUETOOTH: el enlace A2DP recodifica a AAC/SBC y el encoder de iOS
    /// trabaja a 44.1 kHz. Pedir 48 kHz (como hacía antes) provocaba un doble
    /// remuestreo 44.1→48→44.1: solo CPU y pérdida, nunca calidad.
    private func configureSessionWithBluetoothOptimization() {
        // ✅ OPTIMIZACIÓN (BT): en A2DP la latencia la impone el enlace
        // (100-300 ms), así que un buffer de render de 8 ms en la app NO la
        // mejora: solo añade presión de render y CPU por buffer (batería y
        // riesgo de underrun). La tasa también la decide iOS (ver
        // playCurrentSong), así que aquí ya no se fuerza nada.
        let session = AVAudioSession.sharedInstance()
        AppLog.info(.playback, String(format: "Sesión BT: sin forzar buffer ni tasa (concedido: %.2f ms, %.0f Hz)",
                                      session.ioBufferDuration * 1000, session.sampleRate))
    }

    /// ✅ FASE C4: describe la causa para el LOG (texto en español, como el
    /// resto del registro). La UI usa el enum y localiza por su cuenta.
    private func logDescription(for reason: BitPerfectBlockReason) -> String {
        switch reason {
        case .dolbyAVPlayer:
            return "codec Dolby decodificado por AVPlayer (fuera del grafo propio)"
        case .fallbackPlayer:
            return "motor de respaldo AVPlayer activo (fuera del grafo propio)"
        case .unknownSourceRate:
            return "tasa de la fuente desconocida"
        case .resampling(let source, let output):
            return String(format: "remuestreo %.0f → %.0f Hz", source, output)
        case .eqOrMono:
            return "EQ o mono procesando"
        case .limiter:
            return "protección anti-clipping (limiter) activa"
        case .nonWiredRoute:
            return "ganancia != 1.0 (limiter activo o ruta no cableada)"
        }
    }

    /// "Sin remuestreo / bit-clean": solo es cierto si (1) la tasa de salida
    /// coincide con la del archivo, (2) la salida es cableada (jack/USB DAC; ni
    /// BT con codec con perdida ni el altavoz con su DSP de proteccion),
    /// (3) no hay EQ ni mono procesando y (4) la ganancia es 1.0 (limiter OFF).
    /// iOS no ofrece modo exclusivo, asi que es la mejor garantia posible.
    private func refreshBitPerfect(outputRate: Double) {
        // ✅ 3.0.1: la tasa fiable es la del ARCHIVO CARGADO (`sampleRate`, fijada
        // en playCurrentSong desde file.processingFormat); `currentSong?.sampleRate`
        // la escribió el indexador al leer los tags y con un header engañoso miente
        // (el indicador decía "remuestreado" con la salida perfecta, o al revés).
        // Se cae a la del índice solo si el motor todavía no tiene archivo cargado.
        let sourceRate = (audioFile != nil && sampleRate > 0) ? sampleRate : (currentSong?.sampleRate ?? 0)
        let processing = (isEQEnabled && eqPreset != .flat) || isMonoAudioEnabled
        // ✅ FIX A9+C3: en modo de respaldo (AVPlayer) el grafo propio —EQ, mono y
        // headroom— NO está en uso, así que el indicador no puede afirmar
        // "bit-perfect": describiría un motor que no es el que suena. Sin este
        // término, con `audioFile == nil` (que es el caso en respaldo) la tasa caía
        // a la del índice y la fila podía decir "Sí (sin remuestreo)" justo debajo
        // del chip que avisa de que no hay bit-perfect.
        let unityGain = !isLimiterEnabled && isWiredRoute && !isAVPlayerActive
        let value = sourceRate > 0 && abs(outputRate - sourceRate) < 1 && !processing && unityGain
        // ✅ FASE C4: la causa EXACTA se calcula SIEMPRE (no solo en la
        // transición), porque la vista de calidad la muestra literalmente; el log
        // se sigue escribiendo solo cuando el valor CAMBIA (no en cada refresco).
        let reason: BitPerfectBlockReason?
        if value {
            reason = nil
        } else if isDolbyPlayback {
            // ✅ Dolby (E-AC-3/AC-3) va por AVPlayer: el grafo propio no participa,
            // así que el bit-perfect no aplica. Se dice el motivo real en vez de
            // culpar a la ganancia.
            reason = .dolbyAVPlayer
        } else if isAVPlayerActive {
            reason = .fallbackPlayer
        } else if sourceRate <= 0 {
            reason = .unknownSourceRate
        } else if abs(outputRate - sourceRate) >= 1 {
            reason = .resampling(source: sourceRate, output: outputRate)
        } else if processing {
            reason = .eqOrMono
        } else if isLimiterEnabled {
            reason = .limiter
        } else {
            reason = .nonWiredRoute
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.bitPerfectBlockReason = reason
            guard self.isBitPerfect != value else { return }
            self.isBitPerfect = value
            // ✅ 3.0.1 DIAGNÓSTICO: se registra la TRANSICIÓN (no cada refresco)
            // con la causa exacta: cuándo se gana y cuándo se pierde la salida
            // bit-perfect.
            if value {
                AppLog.info(.playback, String(format: "Bit-perfect ACTIVADO (salida cableada a %.0f Hz, sin EQ/mono, ganancia unidad)", outputRate))
            } else if let reason = reason {
                AppLog.info(.playback, "Bit-perfect DESACTIVADO (\(self.logDescription(for: reason)))")
            }
        }
    }

    /// ✅ GANANCIA DE SALIDA (anti-clipping). Maximiza calidad bit-perfect
    /// dentro de las limitaciones del hardware iPhone 8 Plus.
    /// ✅ CRÍTICO - CALIDAD BIT-PERFECT MÁXIMA:
    /// - 1.0 cuando limiter está desactivado (sin atenuación)
    /// - 0.99 cuando limiter está activo (mínima protección -0.09 dB)
    /// - Headroom del EQ solo cuando es necesario (EQ no flat)
    /// - Headroom reducido al mínimo necesario (3 dB) para máxima dinámica
    private func applyOutputGain() {
        let processing = isEQEnabled && eqPreset != .flat
        var maxGain: Float = 0
        if processing, let eq = equalizerNode {
            // Las bandas contiguas se SUMAN: dos de +6 dB juntas dan más de
            // +6 dB reales, así que se mide el par más alto, no una banda sola.
            let gains = eq.bands.map(\.gain)
            let single = gains.max() ?? 0
            var pair: Float = 0
            for i in 0..<max(gains.count - 1, 0) {
                pair = max(pair, (gains[i] + gains[i + 1]) * 0.6)
            }
            maxGain = max(single, pair)
        }
        // ✅ NIVEL BASE: 1.0 cuando la protección anti-clipping está
        // desactivada (por defecto → bit-perfect posible), 0.99 cuando está
        // activa (mínima protección anti-clipping).
        // ✅ Sin atenuación fija en Bluetooth: el encoder AAC/SBC de iOS
        // tiene su propio control de picos, y la base 0.89 (-1 dB)
        // introducida en 32a1e37 rebajaba el nivel universalmente en BT
        // frente a versiones anteriores. Se conserva el margen sólo si el
        // usuario activa manualmente la protección anti-clipping (limiter).
        let base: Float = isLimiterEnabled ? 0.99 : 1.0
        // ✅ 3.0.1 HEADROOM DEL EQ: antes se topaba en 3 dB (`min(maxGain, 3)`)
        // mientras el máximo real calculado arriba es bastante mayor (Bass/Treble:
        // single 8 dB, par contiguo 9 dB; Rock: 6.6 dB). Con material a 0 dBFS en
        // graves —electrónica, hip-hop— el boost superaba el margen y RECORTABA en
        // el conversor de salida del hardware (el mixer suma en float; el clip
        // aparece al pasar a entero en el DAC).
        // Ahora se aplica el máximo REAL: es el precio de no recortar — con EQ
        // activo la salida queda más baja (Bass/Treble ~6 dB menos de nivel
        // percibido) pero la curva del preset llega intacta a la salida.
        // Solo se aplica cuando el EQ está procesando (no flat).
        let eqAttenuation: Float = maxGain > 0 ? pow(10, -maxGain / 20) : 1
        outputGain = base * eqAttenuation
        // ✅ FASE C4: headroom REAL aplicado (dB). La vista de calidad lo muestra
        // tal cual, así que se guarda el mismo número que acaba de sonar.
        appliedEQHeadroomDB = Double(-maxGain)
        engine.mainMixerNode.outputVolume = outputGain * fadeFactor
        refreshBitPerfect(outputRate: outputSampleRate)
    }

    func setEQGain(for band: Int, gain: Float) {
        guard let eq = equalizerNode, band >= 0 && band < eq.bands.count else { return }
        eq.bands[band].gain = gain
        // ✅ Edición manual → des-bypass + recalcular headroom (una ganancia
        // subida a mano también puede provocar clipping).
        updateEQBypassState()
    }

    // MARK: - Audio Mono
    /// Activa/desactiva audio mono (mezcla ambos canales en uno).
    /// Útil para usuarios con audífono único o pérdida auditiva en un oído.
    func toggleMonoAudio() {
        isMonoAudioEnabled.toggle()
        applyMonoAudio()
        refreshBitPerfect(outputRate: outputSampleRate)
        AppLog.info(.playback, "Audio mono: \(isMonoAudioEnabled ? "activado" : "desactivado")")
    }

    private func applyMonoAudio() {
        // ✅ Mono REAL (downmix de salida): el mezclador intermedio emite con
        // formato de 1 canal y AVAudioMixerNode hace el downmix estéreo→mono
        // por DSP; iOS lo reproduce por ambos auriculares/altavoces.
        // ✅ Ahora el mezclador mono ENTRA y SALE del grafo según el ajuste,
        // así que hay que reconstruir la cadena completa en vez de reconectar
        // solo su salida.
        let wasRunning = engine.isRunning
        let graphFormat = audioFile?.processingFormat
            ?? AVAudioFormat(standardFormatWithSampleRate: sampleRate > 0 ? sampleRate : 44100, channels: 2)
            ?? engine.mainMixerNode.outputFormat(forBus: 0)
        reconnectPlayerNode(format: graphFormat)   // ya detiene el engine si hace falta
        if wasRunning {
            do { try startEngineSafely() } catch {
                AppLog.error(.playback, error, context: "applyMonoAudio: relanzar engine")
            }
        }

        // ✅ FIX mono fluido: reprogramar el segmento. CRÍTICO: scheduleFile usa
        // scheduleSegment(at: nil) que ENCOLA el segmento detrás del que ya está
        // programado. Sin flushear el playerNode, el RESTO del segmento viejo
        // (formato anterior) seguía sonando primero y el nuevo arrancaba desde
        // `position` después → el audio "saltaba hacia atrás" y parecía atascado.
        // Mismo patrón que el toggle del EQ: stop (descarta la cola) +
        // reprogramar en el siguiente runloop desde la posición exacta.
        if let file = audioFile {
            scheduleGeneration += 1
            let generation = scheduleGeneration
            let position = isPlaying ? wallClockTime : min(max(currentTime, 0), duration)
            playerNode.stop()          // descarta el resto del segmento viejo
            // playerNode.stop() también descarta cualquier canción
            // pre-encadenada por adelantado.
            clearChainedAhead()
            anchorPlaybackPosition(position)
            // Reprogramar en el siguiente runloop (el engine ya está corriendo
            // si había audio; el formato mono/estéreo ya tomó efecto).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                guard let self = self,
                      self.scheduleGeneration == generation,
                      !self.isStopping else { return }
                self.scheduleFile(file, from: position, autostart: self.isPlaying)
                if self.isPlaying {
                    self.scheduleAheadIfPossible()
                }
            }
        }
        AppLog.info(.playback, "Audio mono (downmix de salida): \(isMonoAudioEnabled ? "activado" : "desactivado")")
    }

    /// Sample rate del motor de audio para UI (publicado para que las vistas se actualicen)
    var sampleRateDisplay: Double {
        sampleRate
    }

    func getEQGain(for band: Int) -> Float {
        guard let eq = equalizerNode, band >= 0 && band < eq.bands.count else { return 0 }
        return eq.bands[band].gain
    }

    func play(song: Song, from songPlaylist: [Song]? = nil) {
        // ✅ FIX shuffle + cola pre-encadenada: play() reemplaza la playlist
        // por completo, así que cualquier canción pre-programada por
        // adelantado (scheduleAheadIfPossible: chainedAhead*) y la precarga
        // en background (preloadedNext*) quedan obsoletas. Sin limpiarlas,
        // su callback .dataPlayedBack podía disparar una transición fantasma
        // a mitad de la canción nueva (patrón usado en seek/resume).
        scheduleGeneration += 1
        clearChainedAhead()
        clearPreloadedNext()
        // ✅ FASE A: `play(song:from:)` es el ÚNICO punto que reemplaza la
        // lista de reproducción, así que aquí se fijan los tres estados
        // canónicos: `originalOrder` (la lista sin mezclar), `playbackOrder`
        // (el orden real que va a sonar) y `currentIndex` (posición de la
        // canción elegida DENTRO de `playbackOrder`).
        let source = songPlaylist ?? [song]
        originalOrder = source
        if isShuffleEnabled {
            // La canción elegida suena YA y queda fija en el índice 0; el resto
            // se mezcla EXCLUYÉNDOLA (así el motor nunca se re-encadena a sí
            // mismo cuando el orden agota la vuelta).
            playbackOrder = [song] + source.filter { $0.id != song.id }.shuffled()
            currentIndex = 0
        } else {
            playbackOrder = source
            if let index = playbackOrder.firstIndex(where: { $0.id == song.id }) {
                currentIndex = index
            } else {
                // Canción fuera de la lista recibida (p. ej. "Reproducir ahora"
                // desde otra sección): se inserta al principio para que
                // `currentIndex` apunte SIEMPRE a ella dentro de `playbackOrder`.
                playbackOrder.insert(song, at: 0)
                originalOrder = playbackOrder
                currentIndex = 0
            }
        }

        updatePlaybackQueue()
        // ✅ FIX: reproducción INMEDIATA (sin retraso de 0.1s) para que el reloj
        // de UI, la barra de progreso y el audio se reinicien de forma atómica.
        // El retraso anterior creaba una ventana donde el UI seguía mostrando
        // la canción anterior mientras el audio ya había cambiado → "punto random".
        playCurrentSong()
        // ✅ Iniciar monitoreo de lyrics line-by-line
        let lyrics = song.lyrics
        if !lyrics.isEmpty {
            Task { @MainActor in
                lyricsViewModel.parseLyrics(lyrics)
                lyricsViewModel.startMonitoring()
            }
        }
        saveState()
    }

    private func playCurrentSong(resumingAt position: TimeInterval? = nil) {
        guard currentIndex >= 0 && currentIndex < playbackOrder.count else {
            stop()
            return
        }

        let song = playbackOrder[currentIndex]
        // ✅ FIX anti-pop: el fade de PAUSA deja el mixer en volumen 0; si el
        // usuario elige otra canción estando en pausa, el mixer seguiría mudo.
        monoMixerNode.volume = 1
        volumeFadeGeneration += 1
        fadeFactor = 1
        engine.mainMixerNode.outputVolume = outputGain * fadeFactor
        AppLog.info(.playback, "Reproduciendo: \(song.displayName)")

        // ✅ FIX: Incrementar scheduleGeneration UNA SOLA VEZ al inicio
        // para invalidar todos los completion handlers pendientes
        scheduleGeneration += 1
        let currentGeneration = scheduleGeneration
        
        stopFallbackPlayback()

        // ✅ FIX REINICIO ATÓMICO: detener TODO antes de reprogramar.
        // playerNode.stop() no resetea el timeline inmediatamente; si se
        // programa justo después, el nodo puede arrancar desde un punto
        // residual (el bug de "reiniciar en cualquier punto random").
        // Solución: detener engine completo, programar, y relanzar.
        isUsingFallback = false
        isStopping = true
        stopDisplayTimer()
        playerNode.stop()
        engine.stop()
        isPlaying = false
        audioFile = nil
        // ✅ playerNode.stop() descarta cualquier segmento pre-encadenado por
        // adelantado (scheduleAheadIfPossible) — limpiar el rastreo para que
        // no quede desincronizado con lo que realmente hay en la cola del nodo.
        clearChainedAhead()
        // ✅ FIX: Mantener isStopping=true hasta que la nueva canción esté programada
        // para evitar que completion handlers ejecuten segmentDidFinish

        guard FileManager.default.fileExists(atPath: song.url.path) else {
            isStopping = false
            handlePlaybackFailure(song: song)
            return
        }

        // ✅ DOLBY DIGITAL PLUS / DOLBY DIGITAL (E-AC-3 / AC-3): el motor propio
        // NO decodifica estos codecs — iOS no expone decodificador Dolby a apps
        // de terceros, así que AVAudioFile falla siempre. AVPlayer sí los
        // decodifica de forma nativa (desde iOS 9.3), así que estas pistas van
        // DIRECTAS a esa ruta, sin pasar por el fallo: es un modo intencional
        // (log de info, sin chip de respaldo) y la pista suena igual.
        if song.requiresAVPlayerPlayback {
            isStopping = false
            AppLog.info(.playback, "Dolby \(song.codecDisplayName ?? song.codecName ?? "?") en '\(song.displayName)' (\(song.formatName)): reproducción por AVPlayer (AVAudioEngine no decodifica E-AC-3/AC-3)")
            startFallbackPlayback(song: song, reason: .codecUnsupported, startAt: position ?? 0)
            return
        }

        do {
            // PRECARGA: si la siguiente cancion ya se precargo en background,
            // se usa directamente en vez de leerla de disco (elimina el hueco).
            // La reproduccion sigue pasando por el reinicio atomico — solo se
            // evita la parte lenta (lectura del archivo del disco).
            let file: AVAudioFile
            if let cached = preloadedNextFile, preloadedNextIndex == currentIndex, preloadedNextURL == song.url {
                clearPreloadedNext()
                file = cached
            } else {
                file = try AVAudioFile(forReading: song.url)
            }
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            duration = Double(file.length) / sampleRate

            guard duration > 0, file.length > 0 else {
                isStopping = false
                handlePlaybackFailure(song: song)
                return
            }

            do {
                let session = AVAudioSession.sharedInstance()
                // Bluetooth: NO pedir tasa. iOS/el enlace A2DP deciden el reloj
                // (forzar 48 kHz no mejora nada y, si el enlace va a 44.1 kHz, solo
                // anade un remuestreo). Ademas evita reconfigurar la ruta por
                // cancion (click / microcorte).
                // Cable / DAC USB / altavoz: tasa NATIVA del archivo; si el
                // hardware no la soporta iOS elige la mas cercana.
                if !isBluetoothRoute, abs(session.sampleRate - sampleRate) > 1 {
                    try session.setPreferredSampleRate(sampleRate)
                }
            } catch {
                AppLog.debug(.playback, "setPreferredSampleRate no soportado: \(error.localizedDescription)")
            }

            // ✅ Reconectar el graph y relanzar el engine desde estado limpio.
            reconnectPlayerNode(format: file.processingFormat)
            try startEngineSafely()

            currentSong = song
            isPlaying = true
            playbackErrorCount = 0
            currentFileURL = song.url
            let playBits = Int(file.fileFormat.streamDescription.pointee.mBitsPerChannel)
            let playChannels = Int(file.processingFormat.channelCount)
            AppLog.info(.playback, String(format: "▶ Reproduciendo '%@' (%@ · %.0f Hz · %d bits · %d canales · %.1fs)", song.displayName, song.formatDescription, sampleRate, playBits > 0 ? playBits : 0, playChannels, duration))

            // ✅ 3.0.1 DIAGNÓSTICO: formato REAL de E/S del hardware (lo que
            // negoció el sistema) + latencia y buffer concedidos al arrancar la
            // pista. Solo lectura: no altera nada del arranque.
            let ioFormat = engine.outputNode.outputFormat(forBus: 0)
            let sessionInfo = AVAudioSession.sharedInstance()
            AppLog.info(.playback, String(format: "Salida: HW %.0f Hz · %d canales · latencia %.2f ms · buffer %.2f ms (fuente %.0f Hz)",
                                          ioFormat.sampleRate, ioFormat.channelCount,
                                          sessionInfo.outputLatency * 1000, sessionInfo.ioBufferDuration * 1000, sampleRate))

            // ✅ Programar el segmento PRIMERO, luego anclar reloj y reproducir.
            // Esto elimina la ventana de carrera donde el timer marcaba 0
            // pero el audio arrancaba tarde o desde otra posición.
            // ✅ FIX reanudación: si llega una posición guardada (restaurar la
            // última canción al abrir la app), se arranca DESDE AHÍ, no de 0.
            let startTime: TimeInterval
            if let position {
                // ✅ FIX GAPLESS: clamp más robusto para evitar problemas con canciones cortas
                // o posiciones guardadas cercanas al final. El margen de 0.05s evita
                // iniciar exactamente al final (podría causar skip inmediato).
                let safeEnd = max(song.duration - 0.05, 0.1) // Mínimo 0.1s para canciones muy cortas
                startTime = min(max(position, 0), safeEnd)
            } else {
                startTime = 0
            }
            scheduleFile(file, from: startTime, autostart: false, generation: currentGeneration)
            anchorPlaybackPosition(startTime)
            currentTime = startTime
            clock.time = startTime
            // ✅ FIX punto aleatorio: tras engine.stop(), el reloj interno del nodo
            // (sampleTime) no se resetea hasta el proximo render. Programar + play
            // inmediato arranca desde un punto residual al azar por milisegundos.
            // ✅ RESTAURADO: 0.1s. Ese margen da tiempo al render thread a
            // resetear el timeline del nodo antes de programar + play; con 0.02s
            // se podía arrancar desde un punto residual (glitch al iniciar).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self,
                      self.scheduleGeneration == currentGeneration,
                      !self.isStopping else { return }
                // ✅ FIX: pausa DURANTE la ventana de arranque (0.15s). Sin este
                // guard, el play() diferido arrancaba el nodo aunque el usuario
                // ya hubiera pausado (la pausa no cambia scheduleGeneration) →
                // el audio seguía corriendo en silencio (mixer a 0) con
                // isPlaying=false, consumiendo CPU/batería con la pantalla
                // bloqueada y sin que el timer de display corrija nada.
                guard self.isPlaying else { return }
                // Re-anclar el reloj a la posición JUSTO antes de play(): el
                // audio arranca aqui (tras el delay), no cuando se lanzo el
                // schedule. Sin esto el reloj de pared iria 0.15s adelantado
                // durante toda la cancion (o desincronizado al reanudar).
                self.anchorPlaybackPosition(startTime)
                self.playerNode.play()
                // ✅ FIX (restauración al retroceder): publicar JUSTO cuando el
                // audio arranca de verdad. El publish del cambio de canción (más
                // arriba) sale ~0.1 s antes de que el nodo suene; esto re-ancla
                // CC/bloqueo al mismo instante que el reloj de la app (rate 1 con
                // elapsed = posición real), que es lo que espera el usuario al
                // volver a una canción anterior.
                self.publishNowPlayingInfoImmediately()
                // Ya está sonando de verdad: dejar programada la siguiente por
                // adelantado para que la transición sea sin hueco.
                self.scheduleAheadIfPossible()
            }
            isStopping = false  // FIX: Ahora podemos permitir completion handlers

            startDisplayTimer()
            // ✅ FIX (restauración al retroceder): publicación inmediata, no
            // diferida — el estado de la canción nueva ya está final aquí.
            publishNowPlayingInfoImmediately()
            updateAudioQuality()
            addToHistory(song)
            updateNextUpQueue()
            saveState()
            // ✅ PRECARGA de la siguiente canción mientras suena la actual,
            // para que la transición al final sea casi instantánea cuando el
            // formato difiere (donde no se puede usar encadenado gapless).

            preloadNextSong()
        } catch {
            // 🔍 LOG: registrar la causa exacta por la que el AVAudioEngine falló
            // (formato no soportado, archivo corrupto, engine no arrancable, etc.)
            isStopping = false  // ✅ FIX: Permitir completion handlers antes del fallback
            AppLog.error(.playback, error, context: "playCurrentSong: cargar/programar \(song.displayName)")
            AppLog.warning(.playback, "Fallback a AVPlayer para '\(song.displayName)' (AVAudioEngine falló)")
            startFallbackPlayback(song: song)
        }
    }

    private func scheduleFile(_ file: AVAudioFile, from startSeconds: TimeInterval, autostart: Bool = true, generation: Int? = nil) {
        // ✅ FIX: Usar la generación proporcionada o la actual
        let generation = generation ?? scheduleGeneration
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

        // ✅ FIX corte prematuro: ver nota en scheduleAheadIfPossible(). Sin
        // .dataPlayedBack, el handler llegaba antes de que el audio saliera
        // realmente por el parlante/auriculares. Este scheduleFile programa
        // siempre el segmento "activo" (el que se supone está sonando ahora):
        // se le asigna un token nuevo, y su propio final dispara
        // segmentDidFinish(), que confirma/encadena la siguiente canción ya
        // pre-programada (ver scheduleAheadIfPossible / commitChainedSong).
        let token = nextScheduleToken
        nextScheduleToken += 1
        activeSegmentToken = token
        playerNode.scheduleSegment(
            file,
            startingFrame: safeStartFrame,
            frameCount: framesToPlay,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.segmentDidFinish(token: token, expectedGeneration: generation)
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

    // MARK: - Controles básicos y otros métodos requeridos
    // MARK: - Fade anti-pop (pausa/reanudación sin "clic")
    // ⛔️ Cortar playerNode/engine a mitad de buffer produce una discontinuidad
    // digital audible ("pop"/"clic"). Antes de pausar bajamos el volumen del
    // mixer a 0 en ~40 ms y al reanudar lo subimos de vuelta. Solo 4 pasos de
    // volume (no por-frame) → sin coste en CPU ni en la UI.
    private var volumeFadeGeneration = 0
    // Factor de fade (0...1) y ganancia base de salida: el volumen real del
    // mainMixer es SIEMPRE outputGain * fadeFactor. El fade actua sobre el
    // mainMixer (siempre en el grafo), no sobre monoMixerNode (que en estereo
    // ya no esta conectado y por eso el fade anti-pop no hacia nada).
    private var fadeFactor: Float = 1
    private var outputGain: Float = 1
    // ✅ ANTI-DOBLE-RESUME: al cambiar la ruta (BT/audífonos) el sistema puede
    // entregar 2 notificaciones seguidas (categoría + dispositivo) y cada una
    // disparar resume() → doble reprogramación y doble log (visto en logs).
    // Este guard ignora un segundo resume dentro de 150 ms si ya está sonando.
    private var lastResumeCallTime: TimeInterval = 0

    /// Rampa lineal del volumen del mezclador intermedio. Una rampa nueva
    /// cancela la anterior (generación), así pausa/resume rápidos no chocan.
    private func rampMixerVolume(to target: Float, duration: TimeInterval = 0.04) {
        volumeFadeGeneration += 1
        let generation = volumeFadeGeneration
        let steps = 4
        let stepDuration = duration / Double(steps)
        let from = fadeFactor
        func scheduleStep(_ step: Int) {
            guard self.volumeFadeGeneration == generation else { return }
            let progress = Float(step) / Float(steps)
            self.fadeFactor = from + (target - from) * progress
            self.engine.mainMixerNode.outputVolume = self.outputGain * self.fadeFactor
            if step < steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration) {
                    scheduleStep(step + 1)
                }
            }
        }
        scheduleStep(0)
    }

    /// ✅ BIT-PERFECT: tras una INTERRUPCIÓN (llamada, Siri, otra app) o un
    /// cambio de ruta, iOS puede dejar la salida en otra tasa de muestreo: la
    /// canción seguiría sonando REMUESTREADA en silencio hasta la siguiente
    /// pista (el indicador lo delataba, pero no se corregía solo).
    /// Se reafirma la tasa NATIVA del archivo actual solo en ruta cableada
    /// (jack/DAC USB): en Bluetooth/AirPlay/altavoz la tasa la decide iOS.
    /// Se llama ANTES de subir el volumen con el fade anti-pop para que el
    /// reclock del DAC quede tapado por la rampa.
    private func reassertNativeSampleRateIfNeeded() {
        guard !isAVPlayerActive, isWiredRoute, sampleRate > 0 else { return }
        let session = AVAudioSession.sharedInstance()
        let previousRate = session.sampleRate
        guard abs(previousRate - sampleRate) > 1 else { return }
        do {
            try session.setPreferredSampleRate(sampleRate)
            AppLog.info(.playback, String(format: "Tasa de salida reafirmada: %.0f Hz → %.0f Hz", previousRate, sampleRate))
        } catch {
            AppLog.debug(.playback, "No se pudo reafirmar la tasa nativa: \(error.localizedDescription)")
        }
    }

    func pause() {
        // ✅ FIX: detener el display timer PRIMERO para evitar que siga
        // actualizando currentTime mientras capturamos la posición exacta.
        stopDisplayTimer()
        // ✅ RELOJ DE PARED: congelar la posición extrapolada como nueva ancla.
        // Independiente del timeline del nodo (que queda congelado a medias
        // tras engine.pause() y era la fuente del doble conteo al reanudar).
        if isAVPlayerActive, let current = avPlayer?.currentTime().seconds, current.isFinite, current >= 0 {
            currentTime = current
            posAnchor = current
        } else {
            let current = wallClockTime
            currentTime = current
            posAnchor = current
            wallAnchor = CACurrentMediaTime()
        }
        clock.time = currentTime
        // ✅ RESTAURADO: fade anti-pop de 30ms (versión previa). Con 10ms el
        // fade podía caer dentro de un mismo buffer y volver el "pop" al pausar.
        rampMixerVolume(to: 0, duration: 0.03)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, !self.isPlaying else { return }
            if self.playerNode.isPlaying {
                self.playerNode.pause()
            }
            self.avPlayer?.pause()
            if !self.isAVPlayerActive, self.engine.isRunning {
                self.engine.pause()
            }
        }
        // ✅ CALIDAD FIX: si la pausa llega DURANTE la ventana de arranque
        // (playCurrentSong re-ancla y llama playerNode.play() 0.15s después,
        // con guard solo de scheduleGeneration), el play diferido saldría
        // DESPUÉS de esta pausa → nodo reproduciendo con mixer a 0: "suena"
        // en silencio, avanza la pista, y al reanudar ya va a mitad de
        // canción sin que el usuario la escuchara. El guard de isPlaying en
        // el bloque diferido de playCurrentSong cancela ese arranque.
        // (No incrementar volumeFadeGeneration aqui: cancelaba la rampa de
        // bajada recien lanzada y el fade-out nunca se ejecutaba.)
        isPlaying = false
        AppLog.info(.playback, String(format: "Pausa en %.1fs — '%@'", currentTime, currentSong?.displayName ?? "—"))
        updateNowPlayingInfo()
        saveState()
    }

    /// ⛔️ Suspensión TOTAL al perder la ruta de audio (audífonos/BT desconectados).
    /// Secuencia crítica contra el salto de canción y el estado "reproduciendo"
    /// congelado del lock screen / Centro de Control:
    ///  1) scheduleGeneration += 1 ANTES de tocar el nodo → cualquier completion
    ///     obsoleto (.dataPlayedBack del segmento actual o del encadenado, que el
    ///     sistema puede disparar justo al caerse la ruta) se IGNORA porque su
    ///     expectedGeneration ya no coincide y NO puede llamar a segmentDidFinish()
    ///     → playNext() → saltar a la canción SIGUIENTE en vez de reanudar la pausada.
    ///  2) Se descarta la canción pre-encadenada y se detiene el nodo + el engine
    ///     (reinicio limpio): al reanudar, resume() reprograma la MISMA canción
    ///     desde la posición anclada — nunca el audioFile de otra canción.
    ///  3) isPlaying = false + updateNowPlayingInfo() ANTES de terminar: el sistema
    ///     recibe rate 0 → lock screen/CC pasan a pausa en la posición exacta
    ///     (se acabó el "reproduciendo" con la barra congelada).
    private func suspendForRouteLoss() {
        AppLog.warning(.playback, "⚠️ Ruta de audio perdida: suspendiendo reproducción en \(String(format: "%.1fs", currentTime)) — '\(currentSong?.displayName ?? "—")'")
        if isAVPlayerActive {
            avPlayer?.pause()
            isPlaying = false
            updateNowPlayingInfo()
            saveState()
            return
        }
        scheduleGeneration += 1
        clearChainedAhead()
        playerNode.stop()
        if engine.isRunning { engine.stop() }
        stopDisplayTimer()
        // Anclar la posición EXACTA antes de marcar pausa (wallClockTime
        // extrapola solo mientras isPlaying sea true).
        let current = wallClockTime
        currentTime = current
        posAnchor = current
        wallAnchor = CACurrentMediaTime()
        clock.time = current
        isPlaying = false
        // ✅ Detener monitoreo de lyrics line-by-line
        Task { @MainActor in
            lyricsViewModel.stopMonitoring()
        }
        updateNowPlayingInfo()
        saveState()
    }

    func resume() {
        // ✅ A2: sin canción NI archivo no hay absolutamente nada que reanudar.
        // Tras stop() (p. ej. fin de playlist sin repeat) el engine sigue
        // corriendo pero currentSong/audioFile son nil: reanudar a ciegas ponía
        // isPlaying = true y publicaba rate 1.0 con duration 0, así que la barra
        // del Centro de Control avanzaba sin que sonara nada. Salir aquí sin
        // tocar el estado deja al sistema en .paused, que es la verdad.
        if currentSong == nil && audioFile == nil {
            AppLog.info(.playback, "resume() sin canción ni archivo: ignorado (nada que reanudar)")
            return
        }
        // ✅ ANTI-DOBLE-RESUME: ya reproduciendo + llamada duplicada en 100ms.
        let now = CACurrentMediaTime()
        if isPlaying, now - lastResumeCallTime < 0.1 {
            return
        }
        lastResumeCallTime = now
        if isAVPlayerActive {
            avPlayer?.play()
        } else {
            // ✅ FIX: si la app estuvo en segundo plano sin reproducir, iOS puede
            // haber detenido el engine. Reanudar a ciegas fallaba en silencio (o
            // crasheaba). Reactivar sesión + engine antes de hacer play.
            if !engine.isRunning {
                do {
                    scheduleGeneration += 1
                    // ⚠️ Ver nota en observeEngineConfigurationChanges(): sin
                    // vaciar la cola explícitamente, scheduleFile (at: nil)
                    // podía encolar detrás de restos de audio viejo.
                    playerNode.stop()
                    // El engine se detuvo por completo: cualquier canción
                    // pre-encadenada por adelantado se perdió con él.
                    clearChainedAhead()
                    if let song = currentSong, audioFile == nil {
                        // ✅ FIX "Reproducir al iniciar" / CC play tras abrir la
                        // app: tras el restore SOLO hay metadatos, el archivo de
                        // audio aún NO está cargado (audioFile == nil) — la rama
                        // antigua nunca programaba nada y quedaba "reproduciendo"
                        // en silencio. playCurrentSong(resumingAt:) hace la carga
                        // COMPLETA (sesión, mono, reconexión, fallback) y arranca
                        // desde la posición guardada.
                        playCurrentSong(resumingAt: min(max(currentTime, 0), max(song.duration - 0.05, 0)))
                    } else if let file = audioFile {
                        // ✅ CRÍTICO - ESTABILIDAD: verificar que el archivo existe antes
                        // de intentar reactivar el engine. Si el archivo fue borrado o
                        // movido mientras la app estaba en segundo plano, esto previene
                        // un crash al intentar reconectar el grafo con un archivo inválido.
                        guard FileManager.default.fileExists(atPath: file.url.path) else {
                            AppLog.warning(.playback, "resume(): archivo ya no existe en disco: \(file.url.lastPathComponent)")
                            self.stop()
                            return
                        }
                        try startEngineSafely()
                        let position = min(max(currentTime, 0), duration)
                        anchorPlaybackPosition(position)
                        scheduleFile(file, from: position, generation: scheduleGeneration)
                    } else {
                        // Sin canción restaurada (app recién instalada o el
                        // usuario nunca reprodujo): nada que reanudar — salir
                        // sin dejar el estado "reproduciendo" fantasma.
                        AppLog.info(.playback, "resume() sin canción cargada: ignorado")
                        return
                    }
                } catch {
                    AppLog.error(.playback, error, context: "resume: reactivar engine")
                }
            } else {
                // ✅ RELOJ DE PARED: re-anclar la extrapolación en la posición
                // pausada; la UI y el lock screen arrancan exactos desde aquí.
                // playerNode.pause() (a diferencia de .stop()) NO descarta la
                // cola: si ya había una canción encadenada por adelantado,
                // sigue intacta y no hace falta re-programarla.
                anchorPlaybackPosition(currentTime)
                clock.time = currentTime
                playerNode.play()
            }
        }
        AppLog.info(.playback, String(format: "Resume desde %.1fs — '%@' (engine running: %@, fallback: %@)", currentTime, currentSong?.displayName ?? "—", engine.isRunning ? "sí" : "no", isUsingFallback ? "sí" : "no"))
        isPlaying = true
        // ✅ BIT-PERFECT: si el sistema cambió la tasa durante la interrupción o
        // el cambio de ruta, se recupera la nativa del archivo antes de subir
        // el volumen (el reclock queda tapado por la rampa del fade).
        reassertNativeSampleRateIfNeeded()
        // ✅ FADE anti-pop: subir el volumen suavemente tras el play (el mixer
        // quedó en 0 por el fade de pausa). 4 pasos × 10 ms, sin clic.
        rampMixerVolume(to: 1, duration: 0.04)
        // ✅ FIX Centro de Control: publicar rate 1.0 + elapsed al reanudar
        updateNowPlayingInfo()
        startDisplayTimer()
        // ✅ Iniciar monitoreo de lyrics line-by-line
        Task { @MainActor in
            lyricsViewModel.startMonitoring()
        }
        if !isAVPlayerActive {
            scheduleAheadIfPossible()
        }
        saveState()
    }

    func stop() {
        isStopping = true
        stopFallbackPlayback()
        // ✅ FIX: detener TERMINA el modo de respaldo, así que el flag vuelve a
        // false aquí. Antes solo lo hacía playCurrentSong(), de modo que tras
        // detener con el motor caído el chip de AudioQualityDetailView seguía
        // visible hasta la siguiente canción. Es seguro porque avPlayer ya quedó
        // liberado arriba: las ramas que leen el flag (pause, resume,
        // suspendForRouteLoss, anclaje de posición) son no-ops sin reproductor.
        isUsingFallback = false
        if playerNode.isPlaying {
            playerNode.stop()
        }
        isPlaying = false
        currentTime = 0
        duration = 0
        currentSong = nil
        currentFileURL = nil
        // Limpiar el archivo precargado (evita dejar handlers de archivo
        // abiertos al parar la reproduccion).
        clearPreloadedNext()
        clearChainedAhead()
        activeSegmentToken = 0
        stopDisplayTimer()
        isStopping = false
        // ✅ BATERÍA: al detener la reproducción, liberar la sesión de audio.
        // Sin esto, la sesión queda "active" de forma indefinida con la app en
        // segundo plano (rate 0 pero hardware de audio reservado) — drena batería
        // y bloquea que otras apps (podcasts, Spotify) usen el audio. El play
        // posterior reactiva la sesión vía startEngineSafely()/configureSession.
        // Es ASÍNCRONO y best-effort: si iOS lo rechaza (interrupción en curso,
        // etc.) no afecta al estado local del motor.
        DispatchQueue.main.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        saveState()
    }

    /// Calcula el índice de la siguiente canción según shuffle/repeat.
    /// Retorna nil si se alcanzó el final de `playbackOrder` sin repeat.
    /// NOTA: el avance AUTOMÁTICO con repeat-one se maneja aparte, en
    /// indexToChainAhead() (repite la MISMA canción). Aquí se resuelve el
    /// avance MANUAL (botón siguiente de la app, del lock screen y del Centro
    /// de Control), que con repeat-one sí debe cambiar de pista y, al llegar al
    /// final de la lista, volver al principio: antes devolvía nil y pulsar
    /// "siguiente" en la última canción no hacía absolutamente nada.
    /// ✅ FASE A: el aleatorio ya NO tiene cola paralela. `playbackOrder` ES el
    /// orden mezclado cuando `isShuffleEnabled` (lo fijan play() y
    /// toggleShuffle()), así que "siguiente" es la posición contigua: nunca
    /// repite hasta agotar la vuelta y nunca puede apuntar a una lista obsoleta.
    /// ✅ MEJORA QUEUE: prioriza la cola manual sobre el resto del orden.
    private func computeNextIndex() -> Int? {
        // ✅ MEJORA QUEUE: primero revisar cola manual
        if !manualQueue.isEmpty {
            // Añadir la primera canción de la cola manual al orden y reproducirla
            let nextSong = manualQueue.removeFirst()
            // ✅ FIX crash (Array index out of range): `insert(_:at:)` exige
            // 0...playbackOrder.count. Si el orden está VACÍO (nada
            // reproduciéndose) o currentIndex quedó fuera de rango, insertar en
            // currentIndex + 1 abortaba el proceso. El clamp no cambia nada
            // cuando el índice es válido (caso normal) y sanea el caso borde.
            let insertionIndex = min(max(currentIndex + 1, 0), playbackOrder.count)
            playbackOrder.insert(nextSong, at: insertionIndex)
            currentIndex = insertionIndex
            updateNextUpQueue()
            return currentIndex
        }

        guard !playbackOrder.isEmpty else { return nil }
        if playbackOrder.count == 1 {
            return repeatMode == .all || repeatMode == .one ? 0 : nil
        }
        if isShuffleEnabled {
            return shuffledAdvanceIndex()
        }
        let next = currentIndex + 1
        if next >= playbackOrder.count {
            // ✅ FIX repeat-one: el avance manual con "repetir una" debe saltar
            // a la siguiente pista y, en el final de la lista, volver al
            // principio. Antes solo repeat-all envolvía, así que en la última
            // canción con repeat-one el botón siguiente era un no-op.
            return (repeatMode == .all || repeatMode == .one) ? 0 : nil
        }
        return next
    }

    /// ✅ FASE A3 — Siguiente posición en ALEATORIO, con anti-repetición de
    /// artista (soft) y SIN mutar el orden.
    ///
    /// Devuelve la primera canción de `playbackOrder` a partir de
    /// `currentIndex + 1` cuyo artista sea DISTINTO al de la canción actual
    /// (queja real: dos temas seguidos de Post Malone). Si TODAS las restantes
    /// son del mismo artista, cae a la siguiente normal: el salto es una
    /// preferencia, nunca un bloqueo de la reproducción. El orden de
    /// `playbackOrder` NO cambia — solo se salta esa posición cuando hace falta.
    ///
    /// Se aplica únicamente si la lista tiene al menos 3 artistas distintos: en
    /// un álbum (uno o dos artistas) no aporta nada y solo alteraría la
    /// secuencia mezclada.
    private func shuffledAdvanceIndex() -> Int? {
        let next = currentIndex + 1
        if next >= playbackOrder.count {
            // Fin de vuelta: con repeat se envuelve al principio (el salto por
            // artista no aplica al reinicio de vuelta); sin repeat, stop() limpio
            // — igual que el modo secuencial.
            return (repeatMode == .all || repeatMode == .one) ? 0 : nil
        }
        if distinctArtistCount(in: playbackOrder) >= 3,
           let currentKey = artistKey(at: currentIndex) {
            var candidate = next
            while candidate < playbackOrder.count {
                if artistKey(at: candidate) != currentKey { return candidate }
                candidate += 1
            }
            // Todas las restantes son del mismo artista → siguiente normal.
        }
        return next
    }

    /// Clave normalizada de artista para la anti-repetición: `albumArtist`
    /// (estable en recopilatorios y compilaciones) y, si falta, `artist`.
    /// Devuelve nil si la canción no trae artista, para que un dato vacío nunca
    /// provoque un salto.
    private func artistKey(at index: Int) -> String? {
        guard playbackOrder.indices.contains(index) else { return nil }
        let song = playbackOrder[index]
        let raw = song.albumArtist.isEmpty ? song.artist : song.albumArtist
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.isEmpty ? nil : key
    }

    /// Número de artistas DISTINTOS de una lista (ignora canciones sin artista).
    /// Sirve para decidir si el anti-repetición aporta algo.
    private func distinctArtistCount(in songs: [Song]) -> Int {
        var keys = Set<String>()
        for song in songs {
            let raw = song.albumArtist.isEmpty ? song.artist : song.albumArtist
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty { keys.insert(key) }
        }
        return keys.count
    }

    /// ¿Hay una canción siguiente que el motor pueda reproducir ahora mismo?
    /// Réplica de `computeNextIndex()` **sin efectos secundarios**: NO consume
    /// la cola manual, NO inserta en el orden y NO avanza ningún puntero del
    /// aleatorio (el orden mezclado es `playbackOrder` y no se muta).
    /// Lo usan los comandos remotos (lock screen / Centro de Control) para
    /// responder `.noSuchContent` en lugar de `.success` cuando un "siguiente"
    /// no haría absolutamente nada.
    ///
    /// Nota sobre el aleatorio: `playbackOrder` YA viene mezclado cuando
    /// `isShuffleEnabled`, y `shuffledAdvanceIndex()` es PURA (no consume la
    /// vuelta), así que este espejo es exacto sin regenerar nada: con 2+
    /// canciones hay siguiente mientras repeat esté activo o quede vuelta por
    /// delante — igual que hace Apple Music al saltar en modo aleatorio.
    var hasNextTrack: Bool {
        // Una canción ya programada por adelantado (gapless) sonará sí o sí al
        // terminar la actual, incluso si el orden de reproducción cambia después.
        if chainedAheadSong != nil { return true }
        // La cola manual siempre tiene contenido pendiente.
        if !manualQueue.isEmpty { return true }
        guard !playbackOrder.isEmpty else { return false }
        // Con una sola canción, solo repeat (.all/.one) permite avanzar.
        if playbackOrder.count == 1 { return repeatMode == .all || repeatMode == .one }
        if isShuffleEnabled { return shuffledAdvanceIndex() != nil }
        // Secuencial: queda algo por delante, o repeat vuelve al principio
        // (espejo exacto de computeNextIndex(): si aquí dijera que no hay
        // siguiente, el lock screen respondería .noSuchContent a un botón que
        // sí funciona).
        if currentIndex + 1 < playbackOrder.count { return true }
        return repeatMode == .all || repeatMode == .one
    }

    /// Índice de la siguiente canción SIN comprometerla.
    /// Pura, sin side effects. Usar para consultar "qué sigue" sin comprometer
    /// la cola (la precarga, por ejemplo). Para avanzar de verdad —consumiendo
    /// la cola manual y avanzando el puntero del aleatorio— usar
    /// `computeNextIndex()`.
    func peekNextIndex() -> Int? { peekNextTrack()?.index }

    /// Núcleo puro del peek: devuelve el índice que tendrá la siguiente canción
    /// y la URL que realmente va a sonar.
    ///
    /// Es un espejo de `computeNextIndex()` **sin mutar nada**: ni
    /// `manualQueue.removeFirst()` ni `playbackOrder.insert(_:at:)`. Los índices
    /// devueltos coinciden con los que devolverá `computeNextIndex()` cuando
    /// llegue el momento real (mientras el orden y el índice actual no cambien
    /// entre medias), para que la caché de precarga siga acertando.
    /// ✅ FASE A: con el aleatorio ya no hay "lista mezclada que regenerar":
    /// `shuffledAdvanceIndex()` es determinista y pura, así que la precarga
    /// acierta SIEMPRE (antes devolvía nil al agotarse la cola paralela y la
    /// transición pagaba la apertura de disco del archivo).
    private func peekNextTrack() -> (index: Int, url: URL)? {
        // Rama 1 — cola manual: se insertará justo después de la actual. Ese es
        // el índice que devolverá computeNextIndex() (`min(max(currentIndex+1,0),
        // playbackOrder.count)`), y la URL hay que leerla de la cola, porque la
        // canción TODAVÍA no está en el orden actual en este momento.
        if let queued = manualQueue.first {
            let insertionIndex = min(max(currentIndex + 1, 0), playbackOrder.count)
            return (insertionIndex, queued.url)
        }

        guard !playbackOrder.isEmpty else { return nil }
        // Con una sola canción, solo repeat (.all/.one) permite avanzar.
        if playbackOrder.count == 1 {
            return (repeatMode == .all || repeatMode == .one) ? (0, playbackOrder[0].url) : nil
        }
        if isShuffleEnabled {
            // ✅ FASE A: espejo EXACTO y puro del camino real (misma función que
            // usa computeNextIndex), incluido el salto por anti-repetición de
            // artista de A3: la canción precargada es la que va a sonar.
            guard let idx = shuffledAdvanceIndex(), playbackOrder.indices.contains(idx) else { return nil }
            return (idx, playbackOrder[idx].url)
        }
        // Secuencial
        let next = currentIndex + 1
        if next >= playbackOrder.count {
            // ✅ Espejo de computeNextIndex(): repeat-one también vuelve al
            // principio en el avance manual.
            return (repeatMode == .all || repeatMode == .one) ? (0, playbackOrder[0].url) : nil
        }
        return (next, playbackOrder[next].url)
    }

    /// ✅ PRECARGA de la siguiente canción en background: mientras suena la
    /// actual, abrimos el AVAudioFile de la siguiente para que, al terminar,
    /// el reinicio atómico de playCurrentSong() use el archivo ya "caliente"
    /// en vez de leerlo de disco — eliminando el grueso del hueco entre pistas.

    private func preloadNextSong() {
        // ✅ FIX: consultar con la versión PURA del cálculo. Antes se usaba
        // computeNextIndex(), que CONSUME la cola manual (removeFirst) e inserta
        // en el orden — es decir, la simple PRECARGA alteraba la cola (una
        // canción de la cola manual desaparecía de nextUpQueue sin sonar).
        guard let next = peekNextTrack() else {
            clearPreloadedNext()
            return
        }
        let index = next.index
        let url = next.url
        // ✅ DOLBY: el motor propio no decodifica E-AC-3/AC-3, así que precargar
        // su AVAudioFile solo gastaría una apertura de disco para fallar. La
        // siguiente canción Dolby se resolverá por AVPlayer en playCurrentSong().
        if playbackOrder.indices.contains(index), playbackOrder[index].requiresAVPlayerPlayback {
            clearPreloadedNext()
            return
        }
        // Ya está precargada la misma siguiente → no volver a abrirla.
        guard url != preloadedNextURL else { return }
        preloadedNextIndex = index
        preloadedNextURL = url
        preloadedNextFile = nil

        DispatchQueue.global(qos: .utility).async { [weak self] in

            guard let self else { return }
            guard FileManager.default.fileExists(atPath: url.path) else {
                DispatchQueue.main.async { self.clearPreloadedNext() }
                return
            }
            do {
                let file = try AVAudioFile(forReading: url)
                DispatchQueue.main.async {
                    // Solo guardar si SIGUE siendo la misma siguiente (el
                    // usuario pudo saltar/esperar mientras se precargaba).
                    guard self.preloadedNextIndex == index, self.preloadedNextURL == url else { return }
                    self.preloadedNextFile = file
                }
            } catch {
                AppLog.debug(.playback, "Precarga fallida para " + url.lastPathComponent + ": " + error.localizedDescription)
                DispatchQueue.main.async { self.clearPreloadedNext() }
            }
        }
    }

    /// ✅ Limpia el archivo precargado (cambio de playlist, parada, o precarga
    /// que ya no aplica). Evita dejar handlers de archivo abiertos en el sistema.

    private func clearPreloadedNext() {
        preloadedNextFile = nil
        preloadedNextIndex = nil
        preloadedNextURL = nil
    }

    func playNext() {
        guard let index = computeNextIndex() else {
            AppLog.info(.playback, "Fin de la playlist (repeat: \(repeatMode.rawValue)). No hay siguiente.")
            return
        }
        currentIndex = index
        playCurrentSong()
    }

    // MARK: - Transición de canción
    // ✅ Encadenado por adelantado (sin silencio): scheduleAheadIfPossible()
    // programa la siguiente canción en el mismo nodo (at: nil) MIENTRAS la
    // actual sigue sonando. commitChainedSong() confirma la transición cuando
    // el segmento activo realmente termina (.dataPlayedBack) y refleja el
    // cambio en la UI — el audio para entonces ya viene sonando sin hueco.
    // chainGaplessPlayNext()/playCurrentSong() solo se usan como respaldo
    // (con un pequeño gap) cuando no fue posible encadenar por adelantado:
    // cambio de formato entre canciones, o fin de la playlist.
    func playPrevious() {
        guard !playbackOrder.isEmpty else { return }
        if currentTime > 3.0 {
            // Regla de 3 s (iPod/Apple Music): reiniciar la canción actual, no
            // retroceder. Queda registrado para poder DISTINGUIR en el
            // dispositivo este caso de un retroceso que no llegó a ejecutarse.
            AppLog.info(.playback, String(format: "Anterior: reinicio de la actual (%.1fs > 3s) — '%@'", currentTime, currentSong?.displayName ?? "—"))
            seek(to: 0)
            return
        }
        currentIndex -= 1
        if currentIndex < 0 {
            currentIndex = repeatMode == .all ? playbackOrder.count - 1 : 0
        }
        AppLog.info(.playback, "Anterior: retroceso a '\(playbackOrder[currentIndex].displayName)' (índice \(currentIndex)/\(playbackOrder.count - 1))")
        playCurrentSong()
    }

    func seek(to time: TimeInterval) {
        guard let file = audioFile else {
            if isAVPlayerActive {
                let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
                avPlayer?.seek(to: cmTime)
            }
            return
        }

        // ⚠️ CRÍTICO: incrementar scheduleGeneration ANTES de stop().
        // playerNode.stop() invoca los completion handlers de los segmentos programados;
        // sin esto, el handler obsoleto llamaba a segmentDidFinish() → playNext()
        // y SALTABA DE CANCIÓN al tocar/arrastrar la barra de progreso o las letras.
        scheduleGeneration += 1
        let generation = scheduleGeneration
        
        AppLog.info(.playback, String(format: "Seek a %.1fs en '%@' (isPlaying: %@)", time, currentSong?.displayName ?? "—", isPlaying ? "sí" : "no"))
        playerNode.stop()
        // playerNode.stop() descarta cualquier canción pre-encadenada por
        // adelantado; hay que volver a programarla tras el seek.
        clearChainedAhead()

        let clampedTime = max(0, min(time, duration))
        currentTime = clampedTime
        // ✅ RELOJ DE PARED: anclar la extrapolación en la posición buscada.
        anchorPlaybackPosition(clampedTime)
        // ✅ FIX sincronización UI: publicar la posición YA en el reloj de las
        // vistas. Sin esto, la barra de la app (PlayerBar/NowPlaying) seguía
        // mostrando la posición previa al seek hasta el siguiente tick del
        // timer de display (hasta 0,4 s; 3 s en segundo plano), mientras el
        // lock screen/CC ya mostraban la nueva. Mismo patrón que ya usan
        // suspendForRouteLoss() y commitChainedSong().
        clock.time = clampedTime
        // ✅ Handle seek en lyrics line-by-line
        Task { @MainActor in
            lyricsViewModel.handleSeek()
        }
        // ✅ FIX sincronización: en pausa el seek NO debe iniciar la reproducción.
        scheduleFile(file, from: clampedTime, autostart: isPlaying, generation: generation)
        if isPlaying {
            scheduleAheadIfPossible()
        }
        // ✅ FIX Centro de Control: publicar elapsed exacto inmediatamente
        // tras el seek para que la barra del sistema salte al mismo punto.
        updateNowPlayingInfo()
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
        // ✅ Guarda anti-crash: orden vacío (cola terminada) no debe indexar
        // sobre []; el estado visual ON/OFF igual se actualiza.
        guard playbackOrder.indices.contains(currentIndex) else { return }
        // ✅ FASE A: la canción actual se lee UNA vez y sobrevive al cambio de
        // orden. Solo hay dos listas: `originalOrder` (sin mezclar) es la fuente
        // y `playbackOrder` el orden real; se reconstruye SIEMPRE desde la
        // primera, nunca al revés.
        let current = playbackOrder[currentIndex]
        if isShuffleEnabled {
            // OFF → ON: lo que estaba sonando es, por definición, el orden
            // secuencial elegido por el usuario → pasa a ser `originalOrder`. El
            // orden real se reconstruye mezclado con la canción actual fija en
            // el índice 0, así que la "siguiente" es siempre la primera de la
            // cola nueva y NUNCA una posición heredada de la lista anterior.
            originalOrder = playbackOrder
            playbackOrder = [current] + originalOrder.filter { $0.id != current.id }.shuffled()
            currentIndex = 0
        } else {
            // ON → OFF: se vuelve al orden original SIN mezclar y se recoloca el
            // índice sobre la MISMA canción (nunca se pierde el punto de escucha).
            playbackOrder = originalOrder.isEmpty ? playbackOrder : originalOrder
            if let newIndex = playbackOrder.firstIndex(where: { $0.id == current.id }) {
                currentIndex = newIndex
            } else {
                playbackOrder.insert(current, at: 0)
                originalOrder = playbackOrder
                currentIndex = 0
            }
        }
        updatePlaybackQueue()
        updateNextUpQueue()
        // ✅ FIX GAPLESS: el audio ya encolado era el de la canción "siguiente"
        // del orden VIEJO. En vez de invalidarlo (y pagar el respaldo atómico
        // con hueco en la siguiente transición), se re-siembra el nodo con la
        // canción actual en su posición viva y se vuelve a encadenar contra el
        // orden nuevo: la siguiente transición sigue siendo gapless.
        rechainAheadAfterOrderChange()
        // ✅ FASE B4: el aleatorio es un estado de reproducción: el Centro de
        // Control, la pantalla de bloqueo y CarPlay lo reflejan en cuanto se
        // publica el diccionario completo (antes este toggle no avisaba a iOS).
        updateNowPlayingInfo(force: true)

        AppLog.info(.playback, "Aleatorio: \(isShuffleEnabled ? "activado" : "desactivado") (\(playbackOrder.count) canciones)")
    }

    /// Cicla el modo de repetición: .off → .all → .one → .off.
    ///
    /// ✅ FASE A4 — LOS TRES MODOS, documentados tal y como los implementa el
    /// motor (avance AUTOMÁTICO = cuando el audio termina; avance MANUAL = botón
    /// "siguiente" de la app, del lock screen y del Centro de Control):
    ///
    ///   · `.off` — Al llegar al final de `playbackOrder` no hay siguiente: el
    ///     avance automático acaba en stop() (motor parado, UI sin canción) y el
    ///     manual tampoco hace nada en la última pista (computeNextIndex() nil).
    ///   · `.all` — Al llegar al final (automático) o al pulsar "siguiente" en
    ///     la última pista (manual), vuelve al índice 0 y sigue sonando.
    ///   · `.one` — El avance AUTOMÁTICO repite la MISMA canción (lo resuelve
    ///     indexToChainAhead(), que no pasa por computeNextIndex()). El avance
    ///     MANUAL, en cambio, SÍ cambia de pista: es el comportamiento ya
    ///     verificado y el que espera el usuario (pulsar "siguiente" debe
    ///     saltar, no reiniciar la que suena); en la última pista envuelve al
    ///     índice 0, igual que `.all` (rama manual de computeNextIndex()).
    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        let name: String
        switch repeatMode {
        case .off: name = "sin repetición"
        case .all: name = "repetir todo"
        case .one: name = "repetir uno"
        }
        // ✅ FIX GAPLESS: cambiar el modo a mitad de canción dejaba desfasada la
        // canción YA ENCOLADA (terminaría sonando la del modo anterior) y la
        // invalidación costaba un hueco en la siguiente transición. Se re-siembra
        // el nodo y se vuelve a encadenar contra el modo nuevo, sin hueco.
        rechainAheadAfterOrderChange()
        // ✅ FASE B4: la repetición también es estado de reproducción: se publica
        // el diccionario completo para que las superficies del sistema (CC,
        // bloqueo, CarPlay) queden sincronizadas con la app.
        updateNowPlayingInfo(force: true)
        AppLog.info(.playback, "Repetición: \(name)")
    }

    // ✅ MEJORA QUEUE: añadir canción a la cola manual
    func addToQueue(_ song: Song) {
        manualQueue.append(song)
        updateNextUpQueue()
        // ✅ FASE B4: la cola forma parte del estado que se publica a iOS (la
        // siguiente pista que anuncian CC/bloqueo/CarPlay sale de ella).
        updateNowPlayingInfo(force: true)
        AppLog.info(.playback, "Añadido a cola: \(song.title)")
    }

    // ✅ MEJORA QUEUE: añadir canciones a la cola manual
    func addToQueue(_ songs: [Song]) {
        manualQueue.append(contentsOf: songs)
        updateNextUpQueue()
        updateNowPlayingInfo(force: true)
        AppLog.info(.playback, "Añadidas \(songs.count) canciones a cola")
    }

    // ✅ MEJORA QUEUE: quitar canción de la cola manual
    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < manualQueue.count else { return }
        let removed = manualQueue.remove(at: index)
        updateNextUpQueue()
        updateNowPlayingInfo(force: true)
        AppLog.info(.playback, "Quitado de cola: \(removed.title)")
    }

    // ✅ MEJORA QUEUE: mover canción en la cola manual
    func moveInQueue(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < manualQueue.count,
              destinationIndex >= 0 && destinationIndex < manualQueue.count,
              sourceIndex != destinationIndex else { return }
        let song = manualQueue.remove(at: sourceIndex)
        manualQueue.insert(song, at: destinationIndex)
        updateNextUpQueue()
        // ✅ FASE B4: mismo criterio que add/remove — un cambio de cola publica
        // el diccionario completo para que el sistema vea el mismo estado.
        updateNowPlayingInfo(force: true)
        AppLog.info(.playback, "Reordenado en cola: \(song.title)")
    }

    // ✅ MEJORA QUEUE: limpiar cola manual
    func clearQueue() {
        manualQueue.removeAll()
        updateNextUpQueue()
        // ✅ FASE B4: vaciar la cola cambia lo que viene después: se publica.
        updateNowPlayingInfo(force: true)
        AppLog.info(.playback, "Cola manual limpiada")
    }

    func restoreState(with songs: [Song]) {
        guard !songs.isEmpty else { return }

        // Solo marcar como restaurado si realmente hay canciones para restaurar.
        // Si ya se restauró previamente, lo omitimos.
        guard !hasRestored else { return }

        guard let state = UserDefaults.standard.dictionary(forKey: stateDefaultsKey) else {
            hasRestored = true
            return
        }
        hasRestored = true

        // ✅ MEJORA QUEUE: restaurar cola manual
        if let queueIDs = state["manualQueue"] as? [String] {
            var restoredQueue: [Song] = []
            for idString in queueIDs {
                if let savedID = UUID(uuidString: idString),
                   let song = songs.first(where: { $0.id == savedID }) {
                    restoredQueue.append(song)
                }
            }
            manualQueue = restoredQueue
        }

        // ✅ FIX canción errónea al reabrir: la canción se busca por SU ID
        // (UUID). Antes se restauraba por `currentIndex` aplicado a la lista
        // global de canciones, pero ese índice pertenecía a la cola que se
        // estaba reproduciendo (álbum, playlist, búsqueda...) → al reabrir
        // caía en OTRA canción (frecuentemente la primera de la sección) con
        // una posición y duración que no correspondían.
        var restoredIndex: Int?
        if let idString = state["songID"] as? String, let savedID = UUID(uuidString: idString) {
            restoredIndex = songs.firstIndex(where: { $0.id == savedID })
        }
        // Fallback: estados guardados por versiones anteriores (sin songID).
        if restoredIndex == nil,
           let savedIndex = state["currentIndex"] as? Int,
           savedIndex >= 0, savedIndex < songs.count {
            restoredIndex = savedIndex
        }

        guard let index = restoredIndex else {
            // No hay canción restaurable (o ya no existe en la biblioteca).
            AppLog.info(.playback, "restoreState: sin canción restaurable")
            return
        }

        let song = songs[index]
        // ✅ FASE A: la biblioteca completa es el orden SIN mezclar de la sesión
        // restaurada. Si el aleatorio estaba activo, el orden real se reconstruye
        // mezclado con la canción restaurada fija en el índice 0 — la misma
        // invariante que play()/toggleShuffle(): `currentIndex` apunta SIEMPRE a
        // la canción actual dentro de `playbackOrder`.
        originalOrder = songs
        if isShuffleEnabled, songs.count > 1 {
            playbackOrder = [song] + songs.filter { $0.id != song.id }.shuffled()
        } else {
            playbackOrder = songs
        }
        self.currentIndex = playbackOrder.firstIndex(where: { $0.id == song.id }) ?? 0
        self.currentSong = song
        self.duration = song.duration
        let savedTime = (state["currentTime"] as? TimeInterval) ?? 0
        // ✅ FIX: NUNCA restaurar pegado al final (duration-0.05) — si no,
        // al reanudar el final de canción disparaba playNext() inmediato.
        self.currentTime = min(max(0, savedTime), max(0, song.duration - 0.05))
        // ✅ FIX UI sincronizada: el reloj de display arranca en la posición
        // guardada (antes mostraba 0:00 hasta reanudar).
        self.clock.time = self.currentTime

        updatePlaybackQueue()
        updateNextUpQueue()

        if state["isPlaying"] as? Bool == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self, self.currentSong?.id == song.id else { return }
                // ✅ FIX posición: playCurrentSong(resumingAt:) reanuda desde la
                // posición guardada (playCurrentSong() a secas siempre arranca
                // de 0 — antes la canción se reiniciaba al abrir la app).
                self.playCurrentSong(resumingAt: self.currentTime)
            }
        }
        AppLog.info(.playback, String(format: "Estado restaurado: '%@' @ %.1fs · reproduciendo: %@", song.displayName, currentTime, state["isPlaying"] as? Bool == true ? "sí" : "no"))
        saveState()
    }

    func playFromHistory(_ song: Song) {
        play(song: song, from: playHistory)
    }

    // ✅ Gestión de la cola "Siguiente" (reordenar, eliminar, limpiar)
    func removeFromNextUpQueue(_ song: Song) {
        // ✅ FIX: se elimina de las DOS fuentes (cola manual y lista completa),
        // no solo de la ventana que pinta la UI. Si se quitaba solo de la
        // ventana, la canción seguía estando en `upcomingQueue` y volvía a
        // aparecer al rehacer la playlist.
        manualQueue.removeAll { $0.id == song.id }
        upcomingQueue.removeAll { $0.id == song.id }
        // Reconstruir playlist interna para reflejar el cambio
        rebuildPlaylistFromQueue()
    }

    /// El usuario reordena la ventana visible (las PRIMERAS canciones de
    /// `upcomingQueue`). Se reemplaza ese prefijo por el orden nuevo y se
    /// conserva intacto el resto, así reordenar 10 filas nunca borra las demás.
    func reorderNextUpQueue(_ songs: [Song]) {
        let editedIDs = Set(songs.map { $0.id })
        let untouched = upcomingQueue.filter { !editedIDs.contains($0.id) }
        upcomingQueue = songs + untouched
        // ✅ Las canciones de la cola manual ya están dentro de `upcomingQueue`
        // en el orden elegido: se vacía la cola manual para que
        // computeNextIndex() no vuelva a insertarlas (el mismo tema se
        // reproducía dos veces: una por la playlist rehecha y otra al consumir
        // la cola manual).
        manualQueue.removeAll()
        rebuildPlaylistFromQueue()
    }

    func clearNextUpQueue() {
        // Vaciar la cola es vaciarla ENTERA (también lo que no se ve en la
        // ventana): la reproducción termina en la canción actual.
        manualQueue.removeAll()
        upcomingQueue.removeAll()
        rebuildPlaylistFromQueue()
    }

    private func rebuildPlaylistFromQueue() {
        // La playlist actual = [canción actual] + cola siguiente COMPLETA.
        // ✅ FIX truncamiento: antes se usaba `nextUpQueue` (la ventana de 10
        // de la UI), así que cualquier edición de la cola recortaba la
        // reproducción a esas 10 canciones + la actual.
        guard currentIndex >= 0, currentIndex < playbackOrder.count else { return }
        let current = playbackOrder[currentIndex]
        playbackOrder = [current] + upcomingQueue
        currentIndex = 0
        // ✅ FASE A: la cola editada pasa a ser el nuevo orden SIN mezclar
        // (`originalOrder`), que es la fuente desde la que se reconstruye al
        // apagar el aleatorio. Con el aleatorio activo el orden real se re-mezcla
        // conservando la canción actual fija en el índice 0 — misma invariante
        // que play()/toggleShuffle().
        originalOrder = playbackOrder
        if isShuffleEnabled, playbackOrder.count > 1 {
            playbackOrder = [current] + originalOrder.filter { $0.id != current.id }.shuffled()
        }
        updatePlaybackQueue()
        // Mantener la ventana de la UI coherente con la playlist recién rehecha
        // (y con la cola manual ya volcada dentro de ella).
        updateNextUpQueue()
    }

    private func startDisplayTimer(isBackground: Bool = false) {
        stopDisplayTimer()
        var tickCount = 0
        // ✅ OPTIMIZACIÓN DE BATERÍA: en primer plano 0.4s es suficiente para
        // una UI fluida (la barra de progreso responde rápido al seek/pause),
        // y en segundo plano subimos a 3.0s para reducir drásticamente el
        // consumo de CPU cuando la pantalla está bloqueada o en otra app.
        // iOS interpola el progreso del lock screen/CC con el rate, así que
        // un update cada 3s es imperceptible visualmente pero ahorra CPU/RAM.
        let interval: TimeInterval = isBackground ? 3.0 : 0.4
        let nowPlayingRefreshTicks = isBackground ? 1 : 2
        // ✅ SINCRONIZACIÓN: el timer se añade al run loop en modo .common. Con el
        // modo por defecto (.default) NO dispara mientras el usuario hace scroll o
        // arrastra un control (el run loop está en .tracking), así que la barra de
        // progreso de la app y del lock screen se congelaba durante el gesto y los
        // watchdogs de fin de pista se retrasaban.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            // 🛡 WATCHDOG DE RUTA/ENGINE: si isPlaying=true pero el engine ya no
            // corre (ruta perdida sin notificación — p. ej. Bluetooth caído en
            // segundo plano, desconexión que iOS no reporta), el lock screen /
            // CC se quedarían "reproduciendo" con la barra congelada y un play
            // posterior arrancaría raro. Suspender aquí publica rate 0 (pausa
            // real en el sistema) y deja la posición anclada para reanudar bien.
            // Seguro: el engine siempre corre mientras isPlaying=true en modo
            // engine (los cambios de ruta se detectan y re-programan aparte),
            // y el modo respaldo (AVPlayer) queda excluido por isUsingFallback.
            if !self.isAVPlayerActive, !self.engine.isRunning {
                AppLog.warning(.playback, "Watchdog: engine detenido con isPlaying=true — suspendiendo por pérdida de ruta")
                self.suspendForRouteLoss()
                return
            }
            if self.isAVPlayerActive {
                if let current = self.avPlayer?.currentTime().seconds, !current.isNaN {
                    self.currentTime = current
                }
            } else {
                // ✅ RELOJ DE PARED: extrapolación monótona, inmune a los
                // reinicios del timeline del nodo (pausa, seek, gapless).
                // ✅ FIX: SIEMPRE actualizar currentTime y clock.time, incluso si
                // current > duration (evita que el reloj de UI se quede atrasado
                // cuando el reloj de pared se extrapola más allá del final).
                let current = self.wallClockTime
                self.currentTime = current
                self.clock.time = current
            }
            // ✅ WATCHDOG: si llegamos al final sin transición, forzarla.
            // Corrige el bug de "barra congelada al final, no pasa la canción".
            self.checkPlaybackEndWatchdog()
            // ✅ FASE B3/B5: el elapsed ya NO se envía en cada tick. Apple
            // recomienda enviarlo solo en CAMBIOS de estado y dejar que iOS
            // extrapole con `playbackRate`; aquí se llama con `force: false`, que
            // salta el tick solo si pasó menos de la ventana Y nada cambió
            // (canción/estado/duración: ver publishIfNeeded). Antes: un update
            // cada ~0.8 s en primer plano y cada 3 s en segundo plano — CPU y
            // batería para un dato que el sistema ya sabe calcular.
            tickCount += 1
            if tickCount >= nowPlayingRefreshTicks {
                tickCount = 0
                self.updateNowPlayingInfo(force: false)
            }
            // ✅ PERSISTENCIA DE POSICIÓN EN VIVO: guardar cada ~15s mientras
            // suena (37 ticks × 0.4s fg / 5 × 3.0s bg). Así un cierre forzado
            // (kill sin willResignActive) restaura la posición más reciente,
            // no la del último cambio de canción.
            self.persistTickCounter += 1
            if self.persistTickCounter >= (isBackground ? 5 : 37) {
                self.persistTickCounter = 0
                self.saveState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // ✅ WATCHDOG: red de seguridad contra completions perdidos. Usa el reloj SIN
    // clamp para detectar cuándo el audio realmente terminó (el reloj clampeado
    // NUNCA puede exceder duration, lo que hacía imposible disparar el watchdog).
    private func checkPlaybackEndWatchdog() {
        guard isPlaying, !isStopping, duration > 0, activeSegmentToken != 0 else { return }
        let elapsed = wallClockTimeUnclamped
        // ✅ FIX carrera watchdog vs. callback real (.dataPlayedBack): el
        // callback real ahora espera a que el audio SALGA de verdad por el
        // hardware, lo que en Bluetooth/AirPlay puede tardar varios cientos
        // de ms más de lo que AVAudioSession.outputLatency reporta. Con un
        // margen fijo de 0.5s el watchdog podía ganarle la carrera y forzar
        // la transición (título/portada/reloj a 0 de la siguiente canción)
        // MIENTRAS la canción anterior seguía sonando de verdad — el bug de
        // "portada nueva pero sigue sonando la anterior desde un punto raro".
        // El watchdog es solo una red de seguridad para cuando el callback
        // real nunca llega; un margen generoso no afecta el uso normal.
        let session = AVAudioSession.sharedInstance()
        let watchdogMargin = max(2.5, session.outputLatency + session.ioBufferDuration + 2.0)
        // ✅ FIX bug persistente en repeat-one: antes se excluía repeat-one del
        // watchdog (`repeatMode != .one`). Repeat-one depende ÚNICAMENTE del
        // completion handler de su propio scheduleSegment(at: nil) para volver
        // a programarse — si ese callback .dataPlayedBack no llega (hay reportes
        // conocidos de que a veces no se dispara en ciertos dispositivos/rutas
        // de audio), la canción se quedaba en silencio para siempre al terminar,
        // porque no había ninguna red de seguridad para este modo. El watchdog
        // ahora cubre también repeat-one; el margen amplio evita que compita
        // con el callback real en el caso normal.
        if elapsed >= duration + watchdogMargin {
            AppLog.warning(.playback, String(format: "Watchdog: '%@' en %.1f/%.1fs sin transición, forzando", currentSong?.displayName ?? "—", elapsed, duration))
            segmentDidFinish(token: activeSegmentToken, expectedGeneration: scheduleGeneration)
        }
    }

    // ✅ rescheduleFileAfterStop() fue eliminada: su único uso era el camino
    // de respaldo de repeat-one cuando el nodo no estaba en condiciones de
    // encadenar por adelantado. Ese caso ahora lo cubre uniformemente
    // commitChainedSong() → chainGaplessPlayNext() → playCurrentSong(), que
    // hace un reinicio atómico completo (más robusto que reprogramar a mano).

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
        // ✅ Sin reproductor AVPlayer, el backend activo vuelve a ser el motor
        // propio: las ramas que preguntan "¿quién reproduce?" (pausa, seek,
        // watchdog, anclaje de posición) no deben quedarse esperando un
        // reproductor que ya no existe.
        isAVPlayerActive = false
        isDolbyPlayback = false
    }

    /// ✅ `reason` decide cómo se registra y si el chip de calidad avisa:
    /// Dolby es un modo intencional; el fallo del motor sí es un problema.
    private func startFallbackPlayback(song: Song, reason: FallbackReason = .engineFailure, startAt position: TimeInterval = 0) {
        scheduleGeneration += 1
        stopFallbackPlayback()
        if playerNode.isPlaying {
            playerNode.stop()
        }
        audioFile = nil
        stopDisplayTimer()

        isAVPlayerActive = true
        isDolbyPlayback = (reason == .codecUnsupported)
        isUsingFallback = (reason == .engineFailure)
        currentSong = song
        // ✅ Posición inicial: la restauración al relanzar la app y la
        // reanudación tras un cambio de ruta pasan por aquí; antes el respaldo
        // empezaba siempre en 0 y una canción Dolby reanudaba desde el principio.
        let start = max(0, position)
        currentTime = start
        duration = song.duration > 0 ? song.duration : 0
        posAnchor = start
        playbackErrorCount = 0

        let player = AVPlayer(url: song.url)
        avPlayer = player
        // ✅ El seek se aplica antes de play(): AVPlayer arranca en esa posición
        // sin pasar por el 0 (y sin depender del seek asíncrono).
        if start > 0 {
            player.seek(to: CMTime(seconds: start, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), toleranceBefore: .zero, toleranceAfter: .zero)
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        avTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, self.isAVPlayerActive else { return }
            self.currentTime = time.seconds
        }

        avEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isAVPlayerActive else { return }
            // El modo de respaldo (AVPlayer) nunca pre-encadena por adelantado,
            // así que commitChainedSong() siempre tomará la rama de reinicio
            // atómico (chainGaplessPlayNext → playCurrentSong), que es lo que
            // corresponde aquí.
            self.commitChainedSong()
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
        AppLog.error(.playback, "Fallo de reproducción #\(playbackErrorCount)/5: '\(song.displayName)' — \(song.url.lastPathComponent). ¿Existe: \(FileManager.default.fileExists(atPath: song.url.path))")
        if playbackErrorCount >= 5 {
            AppLog.warning(.playback, "Demasiados fallos consecutivos (5). Deteniendo reproducción.")
            stop()
            playbackErrorCount = 0
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.playNext()
        }
    }

    private func updatePlaybackQueue() {
        // ✅ FASE A: el orden real (`playbackOrder`) es lo que ve la UI.
        playbackQueue = playbackOrder
    }

    private func updateNextUpQueue() {
        // ✅ MEJORA QUEUE: cola manual primero, luego el resto del orden real
        var upcoming: [Song] = []
        
        // Añadir cola manual primero
        upcoming.append(contentsOf: manualQueue)
        
        // Luego añadir las canciones que siguen en `playbackOrder` (con el
        // aleatorio activo ya viene mezclado: la cola que se ve es la que sonará).
        guard currentIndex < playbackOrder.count else {
            upcomingQueue = upcoming
            nextUpQueue = Array(upcoming.prefix(10))
            return
        }
        let nextIndex = currentIndex + 1
        guard nextIndex < playbackOrder.count else {
            upcomingQueue = upcoming
            nextUpQueue = Array(upcoming.prefix(10))
            return
        }
        let orderUpcoming = Array(playbackOrder.suffix(from: nextIndex))
        upcoming.append(contentsOf: orderUpcoming)
        
        // ✅ FIX cola larga: la lista completa (sin topar) es la que usa el
        // motor para rehacer el orden; la ventana de 10 es solo para la UI.
        upcomingQueue = upcoming
        // ✅ MEJORA: mostrar 10 canciones en lugar de 3 para mejor visualización
        nextUpQueue = Array(upcoming.prefix(10))
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
        // ✅ FIX detección al inicio: siempre publicar si la ruta está vacía
        // (cuando la app arranca con audífonos conectados, currentRouteName está vacío)
        let isFirstDetection = currentRouteName.isEmpty || outputPortType.isEmpty
        guard newName != currentRouteName || newType != outputPortType || isFirstDetection else { return }
        DispatchQueue.main.async {
            self.currentRouteName = newName
            self.outputPortType = newType
            // La ganancia depende de la ruta (margen extra en Bluetooth).
            self.applyOutputGain()
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
        // ✅ 3.0.1: valores REALES negociados con el dispositivo (canales máximos,
        // latencia y buffer concedido). No se inventan capacidades del DAC.
        let newMaxChannels = session.maximumOutputNumberOfChannels
        let newLatencyMs = session.outputLatency * 1000
        let newBufferMs = session.ioBufferDuration * 1000
        // ✅ FASE C5: tasa REAL del hardware = formato del nodo de salida del
        // grafo (frente a la tasa NEGOCIADA de la sesión, `session.sampleRate`).
        // Cuando difieren es que iOS remuestrea en el nodo de salida.
        let newHardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        // ✅ OPTIMIZACIÓN BATERÍA: no recrear el string de calidad ni publicar
        // si no hubo cambios reales en la salida (evita re-render UI + dispatch).
        // Recalcular SIEMPRE (cambia con la cancion aunque la tasa de salida no).
        refreshBitPerfect(outputRate: newRate)
        // ✅ 3.0.1: la latencia y el buffer también entran en la comparación (con
        // umbral, para no publicar por ruido de coma flotante) — antes un cambio
        // solo de latencia no refrescaba la telemetría.
        guard outputSampleRate != newRate || outputChannelCount != newChannels
            || maximumOutputChannels != newMaxChannels
            || abs(outputLatencyMs - newLatencyMs) > 0.01
            || abs(ioBufferDurationMs - newBufferMs) > 0.01
            || abs(hardwareSampleRate - newHardwareRate) > 1 else { return }
        DispatchQueue.main.async {
            self.outputSampleRate = newRate
            self.outputChannelCount = newChannels
            self.maximumOutputChannels = newMaxChannels
            self.outputLatencyMs = newLatencyMs
            self.ioBufferDurationMs = newBufferMs
            self.hardwareSampleRate = newHardwareRate
            
            // ✅ AUDIÓFILO: determinar si la salida es bit-perfect
            // Bit-perfect = sample rate de salida coincide con el del archivo

            // ✅ La ganancia de salida se recalcula al cambiar de salida porque
            // el headroom anti-clipping se combina con el ajuste de limiter.
            // Va aquí porque la función tiene un guard que la corta si no hubo
            // cambios reales, así que no se ejecuta en bucle ni gasta batería.
            self.applyOutputGain()
            
            // ✅ AUDIÓFILO: detectar codec Bluetooth (iOS no expone el codec directamente,
            // pero podemos inferir información por el tipo de puerto y nombre del dispositivo)
            let portType = self.outputPortType
            if portType == AVAudioSession.Port.bluetoothA2DP.rawValue ||
               portType == AVAudioSession.Port.bluetoothLE.rawValue ||
               portType == AVAudioSession.Port.bluetoothHFP.rawValue {
                // iOS no expone el codec (AAC/aptX/LDAC) directamente a las apps
                // es una limitación del sistema. Documentamos esto en la UI.
                if portType == AVAudioSession.Port.bluetoothLE.rawValue {
                    self.bluetoothCodec = "BLE (iOS maneja codec)"
                } else if portType == AVAudioSession.Port.bluetoothHFP.rawValue {
                    self.bluetoothCodec = "HFP (llamadas, baja calidad)"
                } else {
                    self.bluetoothCodec = "A2DP (iOS maneja codec)"
                }
            } else {
                self.bluetoothCodec = ""
            }
            
            // ✅ AUDIÓFILO: información del DAC USB conectado
            if portType == AVAudioSession.Port.usbAudio.rawValue {
                let route = session.currentRoute
                if let output = route.outputs.first {
                    let deviceName = output.portName
                    // Intentar obtener información adicional del dispositivo USB
                    self.usbDACInfo = deviceName.isEmpty ? "USB DAC" : deviceName
                } else {
                    self.usbDACInfo = "USB DAC"
                }
            } else {
                self.usbDACInfo = ""
            }
            
            // ✅ AUDIÓFILO: modo actual de AVAudioSession
            switch session.mode {
            case .default:
                self.audioSessionMode = "Default"
            case .measurement:
                self.audioSessionMode = "Measurement (bit-perfect)"
            default:
                self.audioSessionMode = session.mode.rawValue
            }
            
            // ✅ Localizado: antes "Estándar"/"Estéreo" quedaban fijos en español
            // aunque la app estuviera en inglés.
            let rateInfo = newRate > 48000 ? "Hi-Res" : Localization.localized("quality.standard")
            let channelInfo = newChannels >= 2 ? Localization.localized("audio.quality.stereo") : Localization.localized("audio.quality.mono")
            self.audioQualityInfo = "\(rateInfo) • \(Int(newRate))Hz • \(channelInfo)"
        }
    }

    // ✅ Auto-reanudación al conectar audífonos
    private var wasPlayingBeforeRouteChange = false

    /// ¿La salida de audio dada es de tipo "audífonos/BT/dispositivo externo"?
    private static func isHeadphonePort(_ port: AVAudioSession.Port) -> Bool {
        [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .airPlay, .carAudio]
            .contains(port)
    }

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

                // ✅ OPTIMIZACIÓN: delay reducido para reanudación más rápida (0.15s en vez de 0.25s)
                // Suficiente para estabilización de ruta en iOS 16 en iPhone 8
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self = self else { return }
                    let route = AVAudioSession.sharedInstance().currentRoute.outputs.first
                    _ = route.map { output in
                        Self.isHeadphonePort(output.portType)
                    } ?? false

                    // ✅ FIX desconexión BT: reanudar en CUALQUIER ruta (no solo audífonos)
                    // Si estaba reproduciendo y se cambió de ruta, reanudar si está pausado
                    if wasPlaying && !self.isPlaying {
                        self.resume()
                        AppLog.info(.playback, "Ruta cambiada a \(route?.portName ?? "?"): reproducción reanudada")
                    } else if wasPlaying && self.isPlaying, !self.isAVPlayerActive, let file = self.audioFile {
                        // ✅ FIX simétrico: si la reproducción NUNCA se pausó
                        // (el motor siguió "corriendo" durante el cambio de
                        // ruta), su conexión puede haber quedado con el
                        // formato de la ruta VIEJA — el mismo problema que
                        // causaba silencio al desconectar, pero aquí sin
                        // pasar por pause()/resume(). Forzar reconexión +
                        // reprogramación en la posición actual para que el
                        // nuevo dispositivo (cualquiera: Bluetooth, Lightning
                        // con DAC, USB-C, AirPlay) reciba el formato correcto.
                        let position = self.currentTime
                        self.scheduleGeneration += 1
                        self.playerNode.stop()
                        self.clearChainedAhead()
                        do {
                            try self.startEngineSafely()
                            self.anchorPlaybackPosition(position)
                            // ✅ 3.0.1 BIT-PERFECT: el dispositivo nuevo puede haber
                            // negociado otra tasa; se recupera la nativa del archivo
                            // antes de reprogramar (solo en ruta cableada, y solo si
                            // realmente difiere).
                            self.reassertNativeSampleRateIfNeeded()
                            self.scheduleFile(file, from: position, generation: self.scheduleGeneration)
                            self.scheduleAheadIfPossible()
                            AppLog.info(.playback, "Ruta cambiada a \(route?.portName ?? "?") en reproducción activa: grafo reconectado")
                        } catch {
                            AppLog.error(.playback, error, context: "newDeviceAvailable: reconectar en reproducción activa")
                        }
                    }
                }
            } else if reason == .oldDeviceUnavailable {
                // ⚠️ BUG CONFIRMADO: este comentario decía "el sistema pausa
                // solo" — eso es cierto para AVPlayer/AVAudioPlayer, pero NO
                // para AVAudioEngine + AVAudioPlayerNode (lo que usa esta app
                // cuando no está en modo de respaldo). El engine sigue
                // corriendo y el playerNode sigue "reproduciendo" tras
                // desconectar audífonos/Bluetooth — el reloj de pared, la
                // barra de progreso y el Centro de Control seguían avanzando
                // con normalidad, pero el audio salía en silencio (o corrupto)
                // porque el grafo no se reconfiguró de verdad. Y como
                // isPlaying/playerNode nunca se pausaban, al tocar play
                // después `resume()` solo hacía playerNode.play() sobre un
                // nodo que ya "estaba reproduciendo" (no-op) — silencio
                // seguía. Apple recomienda pausar explícitamente en este caso.
                // ⚠️ NO dejar el flag en true: si quedara activo, la siguiente
                // conexión de ruta (rama .newDeviceAvailable, más abajo o en la
                // rama genérica) reanudaría una reproducción que el usuario ya
                // no tiene activa. El único "estaba sonando" que debe contar es
                // el de una ruta que se conecta CON reproducción en curso.
                self.wasPlayingBeforeRouteChange = false
                if self.isPlaying {
                    // ⛔️ No pause() a secas: suspendForRouteLoss() invalida la
                    // generación ANTES de detener el nodo → un completion
                    // de audio en el playerNode.
                    self.suspendForRouteLoss()
                    // ✅ PAUSA COMO APPLE MUSIC (decisión de producto): al perder
                    // la ruta NO se reanuda en la nueva salida. Aquí vivía un
                    // DispatchQueue.main.asyncAfter(0.2) que reprogramaba el
                    // archivo en la posición actual y llamaba a resume(), así que
                    // desenchufar los auriculares hacía que la música siguiera
                    // sonando por el ALTAVOZ del iPhone. Nació para "rescatar" el
                    // Lightning DAC, pero quien desenchufa espera silencio: ahora
                    // se suspende, la posición queda intacta y el play lo da el
                    // usuario (que sí funciona, en la ruta activa en ese momento).
                    // La reanudación automática al CONECTAR una ruta sigue
                    // intacta en la rama .newDeviceAvailable.
                    // ✅ Una sola suspensión por evento: la de arriba, que
                    // invalida la generación ANTES de detener el nodo (el orden
                    // obligatorio).
                    AppLog.info(.playback, "Audífonos/Bluetooth desconectados: pausado sin salto de canción (no se reanuda en altavoz)")
                }
            } else {
                self.wasPlayingBeforeRouteChange = self.isPlaying
                // ✅ FIX: algunos dispositivos (Bluetooth sobre todo) reportan
                // la desconexión con razones distintas a .oldDeviceUnavailable
                // (.categoryChange, .routeConfigurationChange, .unknown…).
                // Si la salida ANTERIOR era audífonos/BT y la actual ya no
                // tiene ninguna, tratar como pérdida de ruta: sin esto la app
                // seguía "reproduciendo" en silencio con isPlaying=true y el
                // lock screen/CC congelados, hasta que un play manual "resolvía".
                let previousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
                let hadHeadphoneOutput = previousRoute?.outputs.contains { output in
                    Self.isHeadphonePort(output.portType)
                } ?? false
                let hasHeadphoneNow = AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
                    Self.isHeadphonePort(output.portType)
                }
                if self.isPlaying && hadHeadphoneOutput && !hasHeadphoneNow {
                    self.suspendForRouteLoss()
                    AppLog.info(.playback, "Ruta de audio perdida (razón \(reason?.rawValue ?? reasonRaw)): suspendido sin salto de canción")
                }
            }

            self.updateRouteName()
            self.updateAudioQuality()
            // ✅ OPTIMIZACIÓN: delay reducido para verificación de ruta (0.2s en vez de 0.4s)
            // Suficiente para estabilización en iOS 16, más rápido para el usuario
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.updateRouteName()
                self?.updateAudioQuality()
            }
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
            if type == .began {
                AppLog.info(.playback, "Interrupción: BEGIN (\(self.isPlaying ? "reproduciendo → pausa" : "no estaba reproduciendo"))")
            }
            if type == .began && self.isPlaying {
                // ✅ GUARDAR estado antes de pausar para reanudación automática
                self.wasPlayingBeforeRouteChange = true
                self.pause()
            } else if type == .ended {
                let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .flatMap { AVAudioSession.InterruptionOptions(rawValue: $0) }
                    .map { $0.contains(.shouldResume) } ?? false
                // ✅ FIX: Solo reanudar si iOS explícitamente lo indica (shouldResume)
                // No reanudar automáticamente basado solo en wasPlayingBeforeRouteChange
                // para evitar reanudaciones no deseadas al navegar por la app
                // ✅ 3.0.1 DIAGNÓSTICO: sin este log, el caso "se paró tras una
                // llamada" era completamente invisible.
                AppLog.info(.playback, "Interrupción: END (shouldResume: \(shouldResume ? "sí" : "no"))")
                if shouldResume {
                    // ✅ Pequeño delay para asegurar que el sistema esté listo
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        self?.resume()
                        self?.wasPlayingBeforeRouteChange = false
                    }
                } else {
                    // ✅ Limpiar el flag si no hay shouldResume para evitar reanudaciones futuras
                    self.wasPlayingBeforeRouteChange = false
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
        // ✅ OPTIMIZACIÓN: delay reducido para actualización más rápida al volver a la app
        // 0.1s es suficiente para que iOS estabilice la sesión de audio tras segundo plano
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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

    /// Publica el estado de reproducción en MPNowPlayingInfoCenter (Centro de
    /// Control, pantalla de bloqueo y CarPlay; el llavero AVRCP consume los
    /// mismos metadatos vía MPRemoteCommandCenter).
    ///
    /// - Parameter force: `true` (por defecto) en CADA cambio de estado:
    ///   play/pausa, seek, cambio de pista (incluido el gapless), toggle de
    ///   aleatorio/repetición y edición de la cola. Envía el diccionario
    ///   COMPLETO (elapsed + rate + playbackState). `false` en los ticks del
    ///   display timer: salta el tick SOLO si pasaron menos de
    ///   `nowPlayingRefreshInterval` Y no cambió nada publicable (identidad de
    ///   canción, estado de reproducción o duración) — mientras suena, iOS
    ///   extrapola el elapsed con `playbackRate` (regla de Apple) y reenviarlo
    ///   en cada tick era puro gasto de CPU.
    private func updateNowPlayingInfo(force: Bool = true) {
        // ✅ FIX: MPNowPlayingInfoCenter debe actualizarse SIEMPRE en el
        // hilo principal; desde un hilo secundario iOS puede ignorar el
        // update (síntoma: el widget solo se refrescaba al reiniciar).
        // El diferido al siguiente turno del run loop es deliberado: coalesce
        // los cambios intermedios de una misma operación (p. ej. el
        // `isPlaying = false` transitorio de un cambio de pista) para no
        // parpadear en CC/bloqueo. Los cambios de pista manuales usan
        // `publishNowPlayingInfoImmediately()` (ver playCurrentSong).
        DispatchQueue.main.async { [weak self] in
            self?.publishIfNeeded(force: force)
        }
    }

    /// ✅ FIX (restauración al retroceder): publicación INMEDIATA para cambios de
    /// pista manuales (play/anterior/siguiente/tap en la biblioteca). El estado
    /// ya está final (canción, duración y rate nuevos), pero el publish normal
    /// queda en la cola del run loop por detrás del resto del trabajo síncrono
    /// de `playCurrentSong()`: esa era la ventana en la que CC/bloqueo seguían
    /// mostrando la canción anterior al retroceder. Sin diferir, la superficie
    /// externa cambia en el mismo turno en que el motor arranca la pista nueva.
    private func publishNowPlayingInfoImmediately() {
        if Thread.isMainThread {
            publishNowPlayingInfo()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.publishNowPlayingInfo()
            }
        }
    }

    /// ✅ FIX (restauración al retroceder): la red de seguridad ya no es solo
    /// temporal. El tick del display timer llama con `force:false` y antes solo
    /// reenviaba cada `nowPlayingRefreshInterval`; ahora se salta el tick
    /// ÚNICAMENTE si nada cambió. Un cambio de canción, de estado de
    /// reproducción o de duración se publica en el acto, así que un cambio de
    /// pista no puede quedar tapado por la ventana de refresco (era el hueco por
    /// el que CC/bloqueo podían quedarse con la canción anterior al retroceder).
    private func publishIfNeeded(force: Bool) {
        let identityChanged = lastPublishedSongID != currentSong?.id
            || lastPublishedIsPlaying != isPlaying
            || abs(lastPublishedDuration - duration) > 0.01
        if !force,
           !identityChanged,
           CACurrentMediaTime() - lastNowPlayingPublishTime < nowPlayingRefreshInterval {
            return
        }
        publishNowPlayingInfo()
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
            // ✅ FASE B2: identidad y posición dentro del álbum. iOS los usa
            // para "pista N de M", para CarPlay y para vincular el contenido
            // externo (identifier estable por canción).
            info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
            info[MPNowPlayingInfoPropertyIsLiveStream] = false
            info[MPNowPlayingInfoPropertyExternalContentIdentifier] = song.id.uuidString
            if let discNumber = song.discNumber {
                info[MPMediaItemPropertyDiscNumber] = discNumber
            }
            if song.trackNumber > 0 {
                info[MPMediaItemPropertyAlbumTrackNumber] = song.trackNumber
            }
            // ✅ FASE B2: conteo de pistas/discos del álbum, con
            // `FileAccessService.albums` como fuente (inyectado por la app en
            // `albumCountsProvider`). Sin proveedor o sin álbum indexado no se
            // publican: son campos opcionales y no se inventan valores.
            if let counts = albumCountsProvider?(song) {
                info[MPMediaItemPropertyAlbumTrackCount] = counts.tracks
                info[MPMediaItemPropertyDiscCount] = counts.discs
            }
        } else {
            cachedArtworkSongID = nil
            cachedNowPlayingArtwork = nil
        }
        // ✅ Sincronización correcta con Centro de Control / Bloquear pantalla:
        // - PlaybackRate  1.0 → reproduciendo; 0.0 → pausa
        // - ElapsedPlaybackTime se envía SIEMPRE (ver nota de abajo): en pausa
        //   fija la posición; en reproducción iOS la avanza con el rate. El bug
        //   de "se queda al final" / "no sincroniza la pausa" venía de enviar un
        //   elapsed OBSOLETO, no de enviarlo en cada publicación.
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPMediaItemPropertyPlaybackDuration] = duration
        // ✅ FIX Centro de Control: enviar SIEMPRE el elapsed. Al (re)iniciar
        // playback (repeat-one, seek, cambio de pista), si no se envía, iOS
        // sigue avanzando el elapsed desde el valor anterior (fin de canción)
        // y la barra de progreso queda desincronizada. Enviarlo en cada
        // actualización es lo estándar: el sistema lo avanza con el rate.
        // ✅ FIX (barra desfasada respecto a CC/bloqueo): se calcula EN EL
        // MOMENTO de publicar en lugar de copiar el último tick del display
        // timer. `currentTime` solo se refresca cada 0.4 s (primer plano) / 3 s
        // (segundo plano); al enviarlo tal cual, la barra del sistema quedaba
        // anclada por detrás de la de la app y, con la FASE B, ese desfase se
        // mantenía hasta 30 s. Con el reloj de pared vivo, cada publicación
        // reancla iOS en la posición real (clamp a duration incluido).
        let elapsedForPublish: TimeInterval = (isPlaying && !isAVPlayerActive) ? wallClockTime : currentTime
        // ✅ Evidencia en dispositivo: solo se registra cuando la corrección es
        // perceptible (> 250 ms), que es exactamente el desfase que el usuario
        // veía entre la barra in-app y la del Centro de Control.
        if abs(elapsedForPublish - currentTime) > 0.25 {
            AppLog.info(.playback, String(format: "NowPlaying: elapsed %.2fs publicado (el tick tenía %.2fs)", elapsedForPublish, currentTime))
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedForPublish

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        // ✅ SINCRONIZACIÓN (iOS 13+): fijar también el estado explícito de
        // reproducción. Con solo el rate (1.0/0.0), tras una interrupción o una
        // pausa desde el Centro de Control el sistema podía mostrar el botón del
        // lock screen en el estado contrario al real.
        // `publishNowPlayingInfo()` ya se ejecuta en el hilo principal.
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        // ✅ FASE B3: marcar el envío real. Los ticks del display timer
        // (`force: false`) lo consultan junto con lastPublished* para decidir si
        // pueden saltarse el tick (ventana de 2 s; ver publishIfNeeded).
        lastNowPlayingPublishTime = CACurrentMediaTime()
        // ✅ FIX (restauración al retroceder): recordar QUÉ se publicó para que
        // la red de seguridad sepa si un tick puede saltarse (ver publishIfNeeded).
        lastPublishedSongID = currentSong?.id
        lastPublishedIsPlaying = isPlaying
        lastPublishedDuration = duration
    }

    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            // ✅ A2: honestidad con el sistema — sin canción ni archivo no hay
            // nada que reanudar. Antes respondía .success y la barra del
            // Centro de Control arrancaba en silencio.
            guard let self = self, self.currentSong != nil || self.audioFile != nil else {
                return .commandFailed
            }
            self.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isPlaying {
                self.pause()
            } else {
                // ✅ A2: misma guarda que playCommand — con isPlaying == false y
                // sin canción ni archivo, resume() no tendría nada que hacer.
                guard self.currentSong != nil || self.audioFile != nil else { return .commandFailed }
                self.resume()
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            // ✅ Honestidad con el sistema: si no hay siguiente (fin de la
            // playlist sin repeat), responder `.noSuchContent` en lugar de
            // `.success` para que iOS no dé por hecho un salto que no ocurrió.
            // `hasNextTrack` es una comprobación SIN efectos secundarios, así que
            // puede consultarse en cada pulsación sin tocar el estado.
            guard let self = self, self.hasNextTrack else { return .noSuchContent }
            self.playNext()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            // ✅ Evidencia para verificación en dispositivo: si este log no
            // aparece al pulsar "anterior" en CC/bloqueo, el comando no llegó a
            // la app — no es un fallo del retroceso ni de la publicación.
            AppLog.info(.playback, "Comando remoto: anterior")
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
        var state: [String: Any] = [
            "isPlaying": isPlaying,
            "currentTime": currentTime,
            "currentIndex": currentIndex
        ]
        // ✅ FIX: guardar la IDENTIDAD de la canción (UUID). restoreState()
        // la usa para rescatar la canción EXACTA aunque la biblioteca cambie
        // de orden entre sesiones (antes solo currentIndex → canción errónea).
        if let song = currentSong {
            state["songID"] = song.id.uuidString
            state["songDuration"] = song.duration
        }
        // ✅ MEJORA QUEUE: guardar cola manual para persistencia
        state["manualQueue"] = manualQueue.map { $0.id.uuidString }
        UserDefaults.standard.set(state, forKey: stateDefaultsKey)
    }

    private func loadPlaybackState() {
        guard let state = UserDefaults.standard.dictionary(forKey: stateDefaultsKey) else { return }
        if let time = state["currentTime"] as? TimeInterval {
            currentTime = time
        }
        // ✅ FIX: NO restaurar isShuffleEnabled ni repeatMode desde el diccionario.
        // Estas propiedades se inicializan directamente desde sus claves dedicadas
        // (com.aurora.shuffleEnabled y com.aurora.repeatMode) que se guardan
        // INMEDIATAMENTE con cada cambio (didSet). El diccionario solo se guarda
        // en background/terminate y puede tener valores viejos que sobrescriban
        // los valores correctos.
    }
}