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
    // ✅ FIX PERFIL BT DECLARADO: "A2DP" / "HFP" / "LE" / "" según el portType
    // REAL de la salida. HFP = SCO (manos libres, mono, calidad de llamada): la
    // música suena degradada y hasta ahora no había ni log ni UI que lo dijeran.
    @Published var bluetoothProfile: String = ""
    // Último perfil ya registrado en el log (privado, NO publicado): existe solo
    // para loguear la TRANSICIÓN, no en cada refresco de telemetría.
    private var lastLoggedBluetoothProfile: String?
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
        case systemMonoAudio
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
    /// ✅ TAREA DRIFT (solo medición): cada anclaje (play, seek, pausa, resume,
    /// gapless…) invalida la referencia nodo↔host del medidor de desfase: los
    /// puntos de anclaje pasan por AQUÍ, así el medidor nunca compara con una
    /// referencia de un tramo de reproducción distinto.
    private func anchorPlaybackPosition(_ pos: TimeInterval) {
        // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): cada re-anclaje
        // reposiciona la extrapolación de la barra; comparar la nueva posición
        // con el ancla PREVIO delata qué camino la mueve y cuánto salta.
        AppLog.info(.playback, String(format: "[CLOCK] anchor: pos=%.2f (antes=%.2f) wallClock=%.3f", pos, posAnchor, CACurrentMediaTime()))
        posAnchor = duration > 0 ? min(max(pos, 0), duration) : max(pos, 0)
        wallAnchor = CACurrentMediaTime()
        clockDriftReference = nil
    }

    /// ✅ TAREA DRIFT (solo medición): referencia relativa nodo↔host. `pos` es la
    /// posición del reloj HOST (extrapolada) pareja del sample de nodo
    /// `nodeSample` en el instante de siembra — sin descuento de latencia de
    /// salida: el drift se calcula con deltas RELATIVOS a partir de esa pareja,
    /// así que un ajuste constante en el seed (la latencia) no se cancelaría y
    /// quedaría sesgando TODAS las medidas. Con deltas no hace falta conocer el
    /// mapeo exacto del scheduleSegment: nodeSample avanza al ritmo del reloj del
    /// hardware de audio y pos al ritmo de CACurrentMediaTime, así que su
    /// divergencia ES el drift buscado.
    private var clockDriftReference: (pos: TimeInterval, nodeSample: AVAudioFramePosition, sampleRate: Double)?
    /// Contador para el log periódico de evidencia (cada 75 ticks ≈ 30s en
    /// primer plano, ≈ 225s en segundo plano).
    private var clockDriftLogCounter = 0
    /// Estado "desfase alto" para loguear SOLO las transiciones del umbral
    /// (sin un log por tick cuando el desfase se mantiene alto).
    private var clockDriftHighActive = false
    // ✅ FIX spam drift: cooldown de 30 s para el log de transición del umbral.
    private var clockDriftLastLogTime: TimeInterval = 0
    // ✅ FIX drift persistente: anti-rebote de la auto-corrección (mínimo 5 s).
    private var clockDriftLastCorrectionTime: TimeInterval = 0

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
            // ✅ REMUESTREO HI-RES: abrir a float32 estándar con render a la
            // tasa NATIVA (ver makePlaybackFile) para que el encadenado use el
            // mismo camino de reproducción que playCurrentSong.
            guard let opened = try? makePlaybackFile(url) else { return }
            file = opened
        }

        let fmt = file.processingFormat
        // ✅ FIX GAPLESS ENTRE TASAS NATIVAS DISTINTAS: el guard comparaba la tasa
        // del archivo siguiente contra la de la canción EN CURSO (`sampleRate`),
        // y esa no es la referencia: el nodo rinde SIEMPRE al formato de conexión
        // y el SRC del mixer convierte lo que llegue (así suena hoy un 96 kHz
        // sobre un grafo de 48 kHz). Dos archivos de tasa distinta acaban en ese
        // mismo SRC, así que se encadenan igual. Lo que sí impide encadenar es un
        // formato que el mixer no pueda resolver: tasa irreal o de otro orden, o
        // canales fuera de rango. El bit-perfect no se toca: donde se conserva
        // (cable, sin EQ/mono/limiter, tasa del archivo = tasa del DAC) el grafo
        // va en paso directo y el encadenado es idéntico al de antes.
        let chainable = fmt.sampleRate > 1 && fmt.sampleRate <= 384_000 &&
            fmt.channelCount >= 1 && fmt.channelCount <= 8
        guard connectedFormatKey != nil && chainable else {
            // ✅ DIAGNÓSTICO GAPLESS (evidencia en dispositivo): este warning ya NO
            // aparece por tasas distintas — solo cuando el formato del archivo
            // siguiente no es encadenable, y ahí el hueco es inevitable.
            AppLog.warning(.playback, "Gapless: '\(song.displayName)' NO se encadena (formato no encadenable: \(fmt.sampleRate) Hz/\(fmt.channelCount)ch · graph \(connectedFormatKey ?? "—"))")
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
        // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): cada invocación
        // (callback real o watchdog) con el veredicto del guard; el rechazo
        // silencioso es hoy invisible y puede esconder callbacks perdidos
        // o duplicados.
        AppLog.info(.playback, String(format: "[CLOCK] segmentDidFinish: token=%d active=%d gen=%d expected=%d isPlaying=%@ isStopping=%@", token, activeSegmentToken, scheduleGeneration, expectedGeneration, isPlaying ? "true" : "false", isStopping ? "true" : "false"))
        guard scheduleGeneration == expectedGeneration,
              token != 0, activeSegmentToken == token,
              isPlaying, !isStopping else { return }
        // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): segmento aceptado
        // → arranca la transición (promoción gapless o reinicio atómico).
        AppLog.info(.playback, "[CLOCK] segmentDidFinish ACEPTADO: commitChainedSong →")
        activeSegmentToken = 0
        AppLog.info(.playback, "Canción terminada: '\(currentSong?.displayName ?? "—")' (\(String(format: "%.1f", duration))s, repeat: \(repeatMode.rawValue))")
        commitChainedSong()
    }

    /// Si ya hay una canción pre-programada y sonando (encadenada por
    /// adelantado), refleja el cambio en la UI/estado y deja programada la
    /// que sigue. Si no había nada encadenado (formato distinto o fin de
    /// playlist), recurre al reinicio atómico como respaldo.
    private func commitChainedSong() {
        // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): estado al entrar;
        // chained* vacíos = camino del reinicio atómico (hueco audible).
        AppLog.info(.playback, String(format: "[CLOCK] commitChainedSong: chainedIndex=%@ chainedToken=%d chainedAheadSong='%@' wallClock=%.2f duration=%.2f", chainedAheadIndex.map(String.init) ?? "nil", chainedAheadToken, String(describing: chainedAheadSong?.displayName), wallClockTimeUnclamped, duration))
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
        // ✅ REMUESTREO HI-RES: duración y relojes con la tasa de RENDER del
        // archivo (la nativa del material, no la del hardware): frames/nativos
        // ÷ nativos/s = segundos exactos con converter activo o sin él.
        duration = Double(file.length) / fmt.sampleRate
        sampleRate = fmt.sampleRate
        // ✅ FIX SINCRONIZACIÓN BARRA: el callback .dataPlayedBack llega cuando
        // la canción nueva YA lleva sonando `joinLatenessMs` (5-30 ms en cable,
        // 200-500 ms en Bluetooth). Anclar en 0 dejaba la barra por detrás del
        // audio durante toda la pista y re-sembraba el error en cada transición.
        // Se ancla en la posición real ya reproducida, clampeada a la duración
        // nueva (por si el callback llega después del fin real).
        let chainedStart = min(max(joinLatenessMs / 1000, 0), duration)
        currentTime = chainedStart
        clock.time = chainedStart
        anchorPlaybackPosition(chainedStart)
        // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): posición de salida
        // del gapless; un chainedStart grande = callback tardío (BT/AirPlay).
        AppLog.info(.playback, String(format: "[CLOCK] commitChainedSong OK: nuevaPos=%.2f joinLatenessMs=%.0f", chainedStart, joinLatenessMs))
        updateNowPlayingInfo()
        // ✅ FIX TIMER CC (CAMBIO D): red de seguridad del gapless. La unión
        // puede caer justo en una transición de estado del sistema; una
        // republicación 0.3 s después garantiza que CC/bloqueo quede anclado
        // al tema nuevo (solo si sigue siendo la canción promovida).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.currentSong?.id == song.id else { return }
            self.publishNowPlayingInfoImmediately()
        }
        updateAudioQuality()
        addToHistory(song)
        updateNextUpQueue()
        saveState()
        preloadNextSong()

        AppLog.info(.playback, String(format: "Gapless: encadenado '%@' (unión %+.0f ms respecto al fin de la anterior)", song.displayName, joinLatenessMs))
        logQualityAuditLine(context: "gapless")

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
        // ✅ FIX -50 en cold start: setCategory falla durante el launch
        // (audio server aún no listo). Se difiere hasta didBecomeActive,
        // que dispara justo después con el sistema ya estabilizado.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configureSessionOnActivation),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        setupEngine()
        setupEqualizer()
        observeRouteChanges()
        observeInterruptions()
        // ✅ FIX CRASH PAUSA PROLONGADA: sin este observer, un reinicio de
        // mediaserverd con la app suspendida dejaba un grafo muerto que
        // resume() reutilizaba tal cual.
        observeMediaServicesReset()
        observeSystemMonoAudio()
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

    // ✅ FIX CRASH SUSPENSION: instante de entrada en segundo plano (reloj
    // monótono) y bandera de reconstrucción total del grafo. El timestamp se
    // registra SIEMPRE — también en pausa, que es justo el escenario del crash
    // — y se limpia al volver a primer plano.
    private var backgroundedAt: TimeInterval?
    private var needsFullEngineReset = false
    // ✅ FIX CRASH INTERRUPCION: "el grafo quedó muerto por un evento EXTERNO"
    // (interrupción, media services reset, cambio de ruta/configuración, vuelta
    // de background). Es DISTINTO de un engine.pause() nuestro: pause() deja
    // isRunning == false con el grafo intacto y el nodo conservando su cola, y
    // eso NO debe pagar una reconstrucción completa en cada pausa/reanudación.
    private var engineDiedExternally = false

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
        // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): snapshot del reloj
        // al entrar en segundo plano (iOS puede matar el engine aquí).
        AppLog.info(.playback, String(format: "[CLOCK] background: currentTime=%.2f posAnchor=%.2f wallAnchor=%.3f isPlaying=%@", currentTime, posAnchor, wallAnchor, isPlaying ? "true" : "false"))
        // ✅ Persistencia del audio: si estamos reproduciendo, mantener la
        // sesión de audio activa y pedir tiempo en segundo plano para que
        // el engine no se suspenda. Esto mejora la reproducción continua
        // sin saltos ni cortes al cambiar de app o bloquear la pantalla.
        // ✅ FIX CRASH SUSPENSION: anotar el instante de entrada en segundo
        // plano ANTES del guard de reproducción — el escenario del crash es
        // background EN PAUSA (isPlaying == false), que sale por ese guard sin
        // registrar nada.
        backgroundedAt = CACurrentMediaTime()
        // ✅ OPT BG: sin UI de letras no hay línea activa que recalcular ni
        // despertador de boundary que rearmar en cada tick del reloj.
        Task { @MainActor in lyricsViewModel.setSceneActive(false) }
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
        if !engine.isRunning, isPlaying, audioFile != nil {
            // ✅ FIX CRASH INTERRUPCION: este bloque SOLO entra con el engine ya
            // detenido (guard de arriba) — reconectar el grafo con
            // startEngineSafely()/reconnectPlayerNode sobre un grafo muerto es
            // el crash real (AVAE_RaiseException, no capturable con do/catch).
            // Mismo gate que resume(): reconstruir entero y reprogramar la
            // pista desde la posición actual. Sin `return`: saltarse
            // startDisplayTimer() de abajo congelaría barra y letras.
            if let song = currentSong {
                performFullEngineReset()
                playCurrentSong(resumingAt: min(max(currentTime, 0), max(song.duration - 0.05, 0)))
            } else {
                AppLog.info(.playback, "engine muerto sin canción: ignorado")
            }
        }

        // ✅ REDUCIR la frecuencia de actualización del display timer en
        // segundo plano para ahorrar batería (el UI no necesita updates
        // tan frecuentes cuando no se ve la pantalla), pero NO detenerlo
        // completamente porque el sistema de lyrics depende de clock.time
        // que se actualiza vía este timer. Si se detiene, las lyrics dejan
        // de sincronizarse al volver a primer plano.
        startDisplayTimer()
    }

    @objc private func handleAppWillEnterForeground() {
        // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): snapshot al volver;
        // si posAnchor + (wall − wallAnchor) ≠ currentTime, el reloj avanzó en
        // segundo plano cuando no debía.
        AppLog.info(.playback, String(format: "[CLOCK] foreground: currentTime=%.2f posAnchor=%.2f wallAnchor=%.3f isPlaying=%@", currentTime, posAnchor, wallAnchor, isPlaying ? "true" : "false"))
        // ✅ FIX CRASH SUSPENSION: en segundo plano y en pausa, iOS desactiva
        // la sesión de audio y suspende el proceso; tras unos minutos (umbral
        // conservador: 30 s) el grafo, el archivo
        // programado y la sesión ya no son de fiar. Se marca reconstrucción
        // completa para que el próximo play no reutilice ese estado.
        if let backgroundedAt = backgroundedAt {
            let backgroundDuration = CACurrentMediaTime() - backgroundedAt
            if backgroundDuration > 30 {
                needsFullEngineReset = true
                AppLog.info(.playback, String(format: "[BT CRASH] vuelta tras %.1f s en segundo plano: reset completo programado", backgroundDuration))
            }
            self.backgroundedAt = nil
        }
        // ✅ OPT BG: al volver, las letras se re-anclan al tiempo real del motor
        // (en segundo plano el tick solo mantenía el ancla de interpolación).
        Task { @MainActor in lyricsViewModel.setSceneActive(true) }
        // ✅ Volver a frecuencia normal del timer al regresar a primer plano
        if isPlaying {
            // ✅ FIX: sincronizar el reloj ANTES de reiniciar el timer para evitar
            // que la barra se adelante al volver de segundo plano.
            syncCurrentTimeFromRenderThread()
            startDisplayTimer()
            updateNowPlayingInfo()
        }

        // ✅ Si se pausó en segundo plano, asegurar que el engine siga listo
        if !engine.isRunning, isPlaying, audioFile != nil {
            // ✅ FIX CRASH INTERRUPCION: mismo caso que en background — el guard
            // de arriba ya garantiza engine detenido, así que reconectar el
            // grafo aquí era el crash (AVAE_RaiseException, no capturable).
            // Mismo gate que resume(): reconstruir entero y reprogramar la
            // pista desde la posición actual.
            if let song = currentSong {
                performFullEngineReset()
                playCurrentSong(resumingAt: min(max(currentTime, 0), max(song.duration - 0.05, 0)))
            } else {
                AppLog.info(.playback, "engine muerto sin canción: ignorado")
            }
        }
    }

    /// Sincroniza currentTime y clock.time con el reloj de pared.
    /// Llamado al volver de segundo plano para evitar que la barra se adelante.
    private func syncCurrentTimeFromRenderThread() {
        let current = wallClockTime
        currentTime = current
        clock.time = current
        // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): qué publicó el
        // reloj de pared al resincronizar (foreground, cambios de timer).
        AppLog.info(.playback, String(format: "[CLOCK] syncCurrentTimeFromRenderThread: wallClock=%.2f", current))
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

        // ✅ FIX CRASH SUSPENSION: tras minutos suspendido la sesión puede seguir
        // inactiva o con la ruta a medio negociar (0 Hz) — el paso 1 ya intentó
        // setActive, así que sin tasa real el sistema no la ha concedido. Se
        // comprueba AQUÍ, antes de reenganchar el nodo: si hace falta se espera
        // hasta 50 ms (pasos de 10, 0 en el caso normal) a que haya tasa válida,
        // y si sigue a 0 se aborta con log claro en vez de arrancar a ciegas
        // sobre una sesión muerta (reconnectPlayerNode + engine.start() sobre
        // ese estado era el camino del crash al volver de una suspensión larga).
        for _ in 0..<5 {
            if session.isActive, session.sampleRate > 1 { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard session.isActive, session.sampleRate > 1 else {
            AppLog.error(.playback, String(format: "[BT CRASH] startEngineSafely: sesión sin ruta válida tras 50 ms (isActive=%@, %.0f Hz): abortado antes de reenganchar el nodo", session.isActive ? "true" : "false", session.sampleRate))
            throw NSError(domain: "AuroraAudioEngine", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Sesión de audio sin ruta válida (posible suspensión larga)"])
        }

        // ✅ FIX CRASH AL REANUDAR TRAS CAMBIO DE RUTA: consultar el formato
        // del hardware DESPUÉS de reactivar la sesión (paso 1): con la ruta
        // activa, el outputNode ya reporta la tasa/canales reales de la ruta
        // vigente; hacerlo antes (con el engine detenido y la ruta en
        // transición) podía devolver 0 Hz / 0 canales y alimentar la conexión
        // con un formato inválido (IsFormatSampleRateAndChannelCountValid).
        // reconnectPlayerNode conserva además su red de saneamiento para el
        // caso en que iOS aún no haya estabilizado la ruta.

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
        // ✅ REMUESTREO HI-RES: al reactivar el engine (segundo plano,
        // interrupción, cambio de ruta) el grafo se reengancha SIEMPRE al
        // formato del HARDWARE de salida (la tasa pudo haber cambiado). Los
        // archivos se abren a su tasa nativa (makePlaybackFile) y el SRC
        // interno del mixer del engine hace la conversión si las tasas
        // difieren (calidad por defecto de iOS: no configurable desde la app).
        reconnectPlayerNode(format: makeHardwareFormat())

        // 2. Arrancar el engine con un reintento tras reconectar el grafo
        do {
            try engine.start()
        } catch {
            AppLog.error(.playback, error, context: "startEngineSafely: primer intento, reintentando")
            // ✅ FIX CRASH REINTENTO: recargar el formato ANTES del segundo
            // start(): la ruta pudo estabilizarse entre intentos, y arrancar
            // con la conexión vieja era la receta del silencio tras cambio
            // de ruta.
            reconnectPlayerNode(format: makeHardwareFormat())
            try engine.start()
        }

        // 3. Verificación final: si el engine sigue sin correr, es un error real
        guard engine.isRunning else {
            throw NSError(domain: "AuroraAudioEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "El motor de audio no pudo iniciarse"])
        }
    }

    /// ✅ FIX CRASH SUSPENSION: tira TODO el grafo (nodo + engine + encadenado
    /// por adelantado) y olvida el archivo y el formato conectado. No reactiva
    /// la sesión (eso lo hace startEngineSafely con la ruta ya estabilizada) ni
    /// programa nada: la reconstrucción completa la hace
    /// playCurrentSong(resumingAt:), que reabre el archivo, reengancha el nodo
    /// al hardware vigente y arranca en la posición pedida.
    private func performFullEngineReset() {
        // ⚠️ Los completion handlers encolados mueren con el nodo: subir la
        // generación evita que un callback rezagado (token/generación antiguos)
        // ejecute la transición de fin de segmento sobre un grafo ya tirado.
        // Es el mismo patrón que usan playCurrentSong() y suspendForRouteLoss().
        scheduleGeneration += 1
        playerNode.stop()
        engine.stop()
        clearChainedAhead()
        audioFile = nil
        connectedFormatKey = nil
        // ✅ FIX CRASH SUSPENSION: tirar también la precarga. Su AVAudioFile se
        // abrió ANTES de la suspensión; si playCurrentSong usa ese handle
        // cacheado, el archivo NO se reabre. Limpiándola, la rama audioFile ==
        // nil abre de disco con makePlaybackFile (handle fresco).
        clearPreloadedNext()
        // ✅ FIX CRASH INTERRUPCION: con el grafo ya tirado no queda nada "muerto"
        // pendiente de reconstruir (resume() también limpia las banderas ANTES de
        // llamar aquí; esto cubre a los demás llamadores).
        engineDiedExternally = false
        AppLog.info(.playback, "[BT CRASH] full engine reset ejecutado")
    }

    // ✅ iOS detiene/reconfigura el engine ante cambios de ruta o del sistema.
    // Sin este observador, el engine quedaba muerto y la siguiente reproducción
    // fallaba (o crasheaba). Lo reiniciamos proactivamente.
    // ✅ FIX CRASH PAUSA PROLONGADA: si mediaserverd se reinicia con la app
    // suspendida (pausa nocturna, presión de memoria), la sesión se invalida
    // y el grafo queda muerto: reutilizar sus nodos puede tirar de
    // excepciones de CoreAudio. Apple exige reactivar la sesión y
    // reconstruir el render aquí.
    private func observeMediaServicesReset() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.currentSong != nil else { return }
            AppLog.warning(.playback, "Media services reiniciado: reconstruyendo el grafo")
            // ✅ FIX CRASH INTERRUPCION: todos los nodos/programaciones anteriores
            // murieron con el servicio → muerte EXTERNA marcada.
            self.engineDiedExternally = true
            // ✅ FIX CRASH INTERRUPCION: el reset mata el grafo SIEMPRE — aquí
            // engine.isRunning puede mentir (true sobre un grafo muerto), por
            // eso el gate es isPlaying y no isRunning (a diferencia de
            // background/foreground, donde el guard ya garantiza motor
            // detenido). Reconectar los nodos viejos (startEngineSafely →
            // reconnectPlayerNode → engine.connect) era el crash
            // AVAE_RaiseException, no capturable. Se reconstruye entero y se
            // reprograma la pista desde la posición actual; antes NO se
            // reprogramaba nada y la app se quedaba en silencio con
            // isPlaying=true. En pausa (o con AVPlayer/Dolby activo) no se
            // arranca nada: flags para que resume() reconstruya al reanudar.
            if self.isPlaying, !self.isAVPlayerActive, let song = self.currentSong {
                self.performFullEngineReset()
                self.playCurrentSong(resumingAt: min(max(self.currentTime, 0), max(song.duration - 0.05, 0)))
            } else if !self.isAVPlayerActive {
                // ✅ FIX CRASH INTERRUPCION: en pausa el grafo también está
                // muerto, pero no hay que arrancar nada ahora; needsFullEngineReset
                // garantiza que resume() reconstruya aunque isRunning mienta
                // con true (el gate de resume() exige !isRunning).
                self.needsFullEngineReset = true
            }
        }
    }

    private func observeEngineConfigurationChanges() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // ✅ 3.0.1 DIAGNÓSTICO: formato de E/S ANTES de reconfigurar. Es la
            // prueba de qué tasa/canales había negociado el hardware.
            // ✅ FIX CRASH INTERRUPCION: un cambio de configuración del engine
            // invalida la cola del nodo y puede dejar el grafo a medio morir →
            // muerte EXTERNA marcada (el próximo arranque reconstruye entero).
            self.engineDiedExternally = true
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
                    // ✅ FIX FLAG MUERTO RESIDUAL: la reconexión ligera terminó
                    // sin error → no queda nada muerto pendiente. Sin esto, el
                    // siguiente pause→resume disparaba un reset completo
                    // (~150 ms + reapertura) sin motivo. Si startEngineSafely
                    // lanza, el catch deja el flag true y resume() reconstruye.
                    self.engineDiedExternally = false
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

    // ✅ FIX -50 en cold start: solo la primera activación de cada ciclo de
    // vida; los cambios de ruta ya reconfiguran por su cuenta.
    private var hasConfiguredSessionOnActivation = false

    @objc private func configureSessionOnActivation() {
        guard !hasConfiguredSessionOnActivation else { return }
        hasConfiguredSessionOnActivation = true
        setupSession()
    }

    // ✅ FIX -50 en cold start: se invoca desde didBecomeActive
    // (configureSessionOnActivation), no desde init().
    private func setupSession() {
        configureSession(level: .primary)
    }
    
    // ✅ AUDIÓFILO: método público para cambiar el modo de audio dinámicamente
    func setAudioSessionMode(_ modeIndex: Int) {
        UserDefaults.standard.set(modeIndex, forKey: "com.aurora.audioSessionMode")
        UserDefaults.standard.synchronize()
        // Reconfigurar la sesión con el nuevo modo
        configureSession(level: .primary)
    }

    // ✅ FIX -50: niveles de degradado de la sesión. `.primary` = opciones
    // vacías; `.renegotiate` = soltar la sesión (setActive(false) +
    // .notifyOthersOnDeactivation) y volver a intentar .primary: resuelve los
    // -50 transitorios por sesión retenida por otra app SIN renunciar a la
    // exclusividad (antes .mixWithOthers, que mezclaba con Spotify/Apple
    // Music — inaceptable en una app audiófila); `.activeOnly` = sin
    // setCategory, solo activar la sesión con la categoría vigente del proceso.
    private enum SessionFallbackLevel {
        case primary, renegotiate, activeOnly
    }

    /// Configura la sesión de audio. Las opciones .allowBluetoothA2DP y
    /// .allowAirPlay (rawValue 32/96) son paramErr (-50) con la categoría
    /// .playback en iOS 16.7.16: solo existen para .playAndRecord/.record.
    /// La escalera `SessionFallbackLevel` reintenta con backoff
    /// (0.15/0.3/0.6 s): [] ×3 → re-negociación (setActive(false) + [] ×3)
    /// → activar sin setCategory.
    private func configureSession(level: SessionFallbackLevel = .primary, attempt: Int = 0) {
        let session = AVAudioSession.sharedInstance()
        
        // ✅ AUDIÓFILO: obtener el modo preferido de configuración
        let modeIndex = UserDefaults.standard.integer(forKey: "com.aurora.audioSessionMode")
        // ✅ .measurement desactiva el procesamiento del sistema (ideal por cable),
        // pero en Bluetooth y altavoz interno puede forzar tasas bajas y rutas
        // inestables. Se aplica SOLO en salidas cableadas (jack / USB DAC).
        let sessionMode: AVAudioSession.Mode = (modeIndex == 1 && isWiredRoute) ? .measurement : .default
        
        do {
            // ✅ FIX -50: .allowBluetoothA2DP y .allowAirPlay solo son válidas
            // para .playAndRecord/.record; con .playback las rutas de música
            // (A2DP/AirPlay) van por defecto y especificarlas es paramErr
            // (rawValue 96/32 del log del 2026-09-28). Evidencia: la opción 32
            // falla TAMBIÉN con la sesión inactiva, y los AirPods Pro 3 se
            // enrutan por A2DP sin ninguna opción aplicada.
            // ✅ En todos los niveles con setCategory las opciones son []: el
            // nivel 2 ya no usa .mixWithOthers (mezclar con otra música es
            // inaceptable aquí) sino re-negociación; en .activeOnly no se
            // intenta setCategory en absoluto (más abajo).
            var options: AVAudioSession.CategoryOptions = []
            if level != .activeOnly {
                // ✅ FIX -50: desactivar la sesión antes de cambiar la categoría.
                // iOS rechaza setCategory con -50 si la sesión ya está activa en
                // ciertos estados (p. ej., activada implícitamente por
                // MPRemoteCommandCenter.shared() en init).
                // ✅ LÍMITE: solo con reproducción parada. En reconfiguraciones en
                // activo (modo de audio en Settings, reintentos) desactivar cortaría
                // el audio y avisaría a otras apps (.notifyOthersOnDeactivation).
                // ✅ EXCEPCIÓN (.renegotiate): se fuerza setActive(false) aunque
                // isPlaying — es la única forma de soltar la sesión que otra app
                // pudo dejar retenida; el corte instantáneo es preferible a
                // seguir sin sesión configurada (decisión documentada).
                if !isPlaying || level == .renegotiate {
                    do {
                        try session.setActive(false, options: .notifyOthersOnDeactivation)
                    } catch {
                        // No es un error: la sesión ya estaba inactiva.
                        AppLog.debug(.playback, "configureSession: setActive(false) previo no aplicable (\(error.localizedDescription))")
                    }
                }
                do {
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
                } catch {
                    AppLog.error(.playback, error, context: "configureSession: setCategory")
                    throw error
                }
            }

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
            // ✅ FIX soloAmbient: si .primary y .renegotiate han fallado, la
            // sesión conserva su categoría previa (.soloAmbient en cold start)
            // y activarla así deja la app silenciable por el mute switch y sin
            // audio en background — peor que no reproducir. Intento best-effort
            // ANTES de activar: el `try?` es deliberado, red de seguridad y no
            // reintento de la escalera (no reinicia el backoff).
            if level == .activeOnly {
                // ✅ EVIDENCIA: si el best-effort falla queremos ver el PORQUÉ
                // (-50, interrupción de otra app…), no solo que falló. Sigue
                // sin ser reintento: no toca la escalera ni el backoff.
                do {
                    try session.setCategory(.playback, mode: .default, options: [])
                } catch {
                    AppLog.error(.playback, error, context: "activeOnly: best-effort setCategory")
                }
            }
            do {
                try session.setActive(true)
                // ✅ EVIDENCIA setActive: confirmar que la activación no falla
                // en silencio (el fallo ya se loguea con context "setActive").
                // La categoría se INTERPOLA (no hardcodeada): en .activeOnly el
                // best-effort puede no haber recuperado .playback.
                AppLog.info(.playback, "setupSession: setActive OK · categoría \(session.category.rawValue) · opciones \(options)")
                if level == .activeOnly {
                    // ✅ El best-effort de arriba puede haber recuperado .playback:
                    // `session.category` refleja el setCategory aunque no se haya
                    // activado aún, así que este check post-activación es fiable.
                    if session.category != .playback {
                        AppLog.error(.playback, "setupSession: sesión activada con categoría \(session.category.rawValue) — mute switch puede silenciar")
                    } else {
                        AppLog.warning(.playback, "setupSession: nivel activeOnly; setCategory best-effort recuperó .playback")
                    }
                }
            } catch {
                AppLog.error(.playback, error, context: "configureSession: setActive")
                throw error
            }
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
            // ✅ FIX -50 en cold start: un único reintento NO bastaba — el server
            // tarda más que ese segundo intento y ambos fallaban seguidos.
            // Backoff exponencial 0.15/0.3/0.6 s y solo al agotar los 3 se
            // degrada de nivel (ese nivel vuelve con attempt 0, así que
            // reintenta por su cuenta).
            // ✅ FIX -50: escalera de degradado con niveles explícitos:
            // .primary ([] ×3 con backoff) → .renegotiate (setActive(false) +
            // [] ×3) → .activeOnly (activar sin setCategory, ×3).
            if attempt < 3 {
                let delay = 0.15 * pow(2.0, Double(attempt))
                AppLog.warning(.playback, String(format: "setupSession falló; reintento %d/3 en %.0f ms", attempt + 1, delay * 1000))
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.configureSession(level: level, attempt: attempt + 1)
                }
            } else {
                switch level {
                case .primary:
                    AppLog.warning(.playback, "setupSession: nivel .primary agotado; re-negociando sesión (setActive(false) + reintento)")
                    configureSession(level: .renegotiate, attempt: 0)
                case .renegotiate:
                    // ✅ Última línea: la sesión conserva su categoría vigente (el
                    // sistema asigna la del proceso) y solo se intenta activar.
                    AppLog.warning(.playback, "setupSession: nivel .renegotiate agotado; degradando a .activeOnly (activación sin setCategory)")
                    configureSession(level: .activeOnly, attempt: 0)
                case .activeOnly:
                    AppLog.warning(.playback, "setupSession: nivel .activeOnly agotado; la sesión queda sin configurar")
                }
            }
        }
    }

    private func setupEngine() {
        engine.attach(playerNode)
        // ✅ Mono: el mezclador de downmix vive permanentemente en el grafo
        engine.attach(monoMixerNode)
        // ✅ SRC Hi-Res (aclaración): cuando el grafo conecta a la tasa del
        // hardware y el archivo está en otra, la conversión la ejecuta el SRC
        // interno de los AVAudioMixerNode del engine. Su calidad NO es
        // configurable desde la app: AVAudioMixerNode no expone
        // sampleRateConverterQuality (esa propiedad solo existe en
        // AVAudioConverter) y la que iOS aplica por defecto no está documentada.
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
        // ✅ REMUESTREO HI-RES: reconexión con el formato de conexión real
        // (hardware); ver reconnectPlayerNode / makeHardwareFormat.
        reconnectPlayerNode(format: makeHardwareFormat())
    }

    private func reconnectPlayerNode(format: AVAudioFormat) {
        // ✅ FIX CRASH AL REANUDAR TRAS CAMBIO DE RUTA: un formato con tasa o
        // canales inválidos (0 Hz / 0 ch, posible en el instante en que el
        // hardware está en transición tras desconectar audífonos/BT) hace que
        // AVAudioEngine.connect dispare la aserción interna
        // "required condition is false: IsFormatSampleRateAndChannelCountValid(format)"
        // — una NSException NO capturable con do/catch (el catch de resume()
        // no la detiene). La política de makeHardwareFormat ya cae a la tasa
        // de la sesión cuando la del hardware es irreal; aquí se aplica el
        // mismo saneamiento para canales/tasa como ÚLTIMA red: si el formato
        // que llega es irreal se sustituye por el formato estándar de la
        // sesión (tasa concedida, 2 canales), que es válido tras
        // setActive(true). Sin remuestreo falso: solo evita conectar el grafo
        // con basura y degrada a la tasa de sesión en el caso extremo.
        var format = format
        if format.sampleRate <= 1 || format.channelCount <= 0 || format.channelCount > 64 {
            let sessionRate = AVAudioSession.sharedInstance().sampleRate
            // ✅ FIX CRASH FORMATO: el `?? format` anterior reintroducía el
            // formato inválido cuando ni el hardware ni la sesión dan tasa
            // válida (ruta en transición): engine.connect dispara entonces la
            // NSException IsFormatSampleRateAndChannelCountValid, no capturable
            // con do/catch. 44100/2 es válido siempre; el grafo se reconecta
            // al formato real en el siguiente arranque.
            let safeRate = sessionRate > 1 ? sessionRate : 44_100.0
            AppLog.warning(.playback, String(format: "Formato de conexión inválido (%.0f Hz · %d canales): usando fallback seguro a %.0f Hz · 2 canales", format.sampleRate, format.channelCount, safeRate))
            format = AVAudioFormat(standardFormatWithSampleRate: safeRate, channels: 2)
                ?? AVAudioFormat(standardFormatWithSampleRate: 44_100.0, channels: 2)!
        }
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
        // ✅ REMUESTREO HI-RES: la CONEXIÓN se hace al formato de hardware que
        // llega (makeHardwareFormat), nunca al del archivo. Si difieren, la
        // conversión la ejecuta el SRC interno del mixer de conexión del
        // engine (AVAudioMixerNode no expone sampleRateConverterQuality: esa
        // propiedad solo existe en AVAudioConverter, y TN3136 documenta su uso
        // MANUAL, no el SRC interno del engine). La calidad aplicada es la
        // por defecto de iOS, no configurable desde la app. Con tasas iguales
        // queda en paso directo: sin coste y sin alterar la ruta bit-perfect.
        // EQ/mono/mainMixer procesan a la tasa del hardware, que es para la
        // que está diseñado el EQ de 10 bandas.
        updateSrcConversionState()
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
    /// ✅ REMUESTREO HI-RES: la tasa de SALIDA del downmix debe ser la del
    /// HARDWARE (la conexión al mainMixer es a makeHardwareFormat), no la del
    /// archivo: con converter activo, emitir a tasa nativa reinsertaría un SRC
    /// de calidad media en el mixer al cruzar a la tasa del hardware.
    private func monoMixerOutputFormat() -> AVAudioFormat {
        let rate = hardwareOutputFormat().sampleRate
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
        if isBluetoothRoute && !UserDefaults.standard.bool(forKey: "com.aurora.btHeadroomDisabled") {
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
        case .systemMonoAudio:
            return "Mono Audio activo en Accesibilidad del sistema"
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
        // ✅ FIX BIT-PERFECT HONESTO CON MONO DEL SISTEMA: iOS puede forzar el
        // downmix mono de TODO el audio (incluida la salida cableada) desde
        // Accesibilidad y la app no puede desactivarlo — pero SÍ leerlo. Sin este
        // término el indicador decía "Bit-Perfect: sí" mientras iOS procesaba la
        // señal: mentira activa en la UI. No es el mono de la app, es el del
        // sistema, y va aparte para poder decir la causa exacta.
        let systemMono = UIAccessibility.isMonoAudioEnabled
        // ✅ FIX A9+C3: en modo de respaldo (AVPlayer) el grafo propio —EQ, mono y
        // headroom— NO está en uso, así que el indicador no puede afirmar
        // "bit-perfect": describiría un motor que no es el que suena. Sin este
        // término, con `audioFile == nil` (que es el caso en respaldo) la tasa caía
        // a la del índice y la fila podía decir "Sí (sin remuestreo)" justo debajo
        // del chip que avisa de que no hay bit-perfect.
        let unityGain = !isLimiterEnabled && isWiredRoute && !isAVPlayerActive
        let value = sourceRate > 0 && abs(outputRate - sourceRate) < 1 && !processing && unityGain && !systemMono
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
        } else if systemMono {
            // ✅ Causa más específica que `processing`: este downmix lo aplica iOS
            // fuera del grafo, no el EQ/mono de la app.
            reason = .systemMonoAudio
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
        // ✅ FIX headroom BT (restaura 32a1e37): -1 dB de margen para el
        // encoder AAC/SBC de iOS, que puede producir overs con
        // inter-sample peaks en material a 0 dBFS. Independiente del
        // limiter: en BT el margen no debe variar con ese ajuste, porque
        // el encoder de iOS ya hace su propio control de picos.
        // ✅ AJUSTE AVANZADO (Ajustes › Audio): el margen de BT se puede
        // desactivar (clave com.aurora.btHeadroomDisabled) para recuperar ese
        // decibelio; entonces la ruta Bluetooth usa la misma base que la
        // cableada (limiter ? 0.99 : 1.0) en lugar del 0.89 fijo.
        let isBTHeadroomDisabled = UserDefaults.standard.bool(forKey: "com.aurora.btHeadroomDisabled")
        let base: Float
        if isBluetoothRoute && !isBTHeadroomDisabled {
            base = 0.89
        } else {
            base = isLimiterEnabled ? 0.99 : 1.0
        }
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

    /// ✅ Reaplica la ganancia base cuando cambia un ajuste que la modifica
    /// pero que no pasa por EQ ni limiter (p. ej. el headroom de Bluetooth).
    /// Mismo camino que los toggles existentes; sin efectos si nada cambió.
    func refreshOutputGain() {
        applyOutputGain()
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
        // ✅ REMUESTREO HI-RES: el archivo sonará a su tasa nativa (render) y
        // la CONEXIÓN se hace al formato del hardware: el converter activo o
        // el paso directo deciden, nunca la tasa del archivo en el grafo.
        reconnectPlayerNode(format: makeHardwareFormat())   // ya detiene el engine si hace falta
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
                // ✅ REMUESTREO HI-RES: apertura única (float32 estándar, render
                // a la tasa NATIVA del material; ver makePlaybackFile).
                file = try makePlaybackFile(song.url)
            }
            audioFile = file
            // ✅ REMUESTREO HI-RES: sampleRate = tasa de RENDER del archivo
            // (siempre la nativa del material). El reloj de pared y el seek
            // escalan con ella; el grafo va aparte, al formato del hardware.
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
                // ✅ REMUESTREO HI-RES: sin cambios de semántica. Si el DAC
                // acepta la tasa nativa, sesión y grafo van a esa tasa y no hay
                // conversión (bit-perfect intacto). Si NO la acepta, el
                // hardware se queda en su tasa y el SRC interno del grafo hace
                // la conversión (en vez del mixer de salida).
                if !isBluetoothRoute, abs(session.sampleRate - sampleRate) > 1 {
                    try session.setPreferredSampleRate(sampleRate)
                }
            } catch {
                AppLog.debug(.playback, "setPreferredSampleRate no soportado: \(error.localizedDescription)")
            }

            // ✅ Reconectar el graph y relanzar el engine desde estado limpio.
            // ✅ REMUESTREO HI-RES: la conexión usa el formato REAL del
            // hardware; el SRC interno del mixer del engine hace la conversión
            // solo cuando la tasa del archivo difiere.
            reconnectPlayerNode(format: makeHardwareFormat())
            try startEngineSafely()

            currentSong = song
            isPlaying = true
            playbackErrorCount = 0
            currentFileURL = song.url
            let playBits = Int(file.fileFormat.streamDescription.pointee.mBitsPerChannel)
            let playChannels = Int(file.processingFormat.channelCount)
            let renderSampleRate = file.processingFormat.sampleRate
            AppLog.info(.playback, String(format: "▶ Reproduciendo '%@' (%@ · %.0f Hz · %d bits · %d canales · %.1fs)", song.displayName, song.formatDescription, renderSampleRate, playBits > 0 ? playBits : 0, playChannels, duration))
            logQualityAuditLine(context: "play")

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
                // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): este
                // re-anclaje define el origen del reloj de pared de TODA la
                // canción; un startTime equivocado desplaza la barra entera.
                AppLog.info(.playback, String(format: "[CLOCK] playCurrentSong: startTime=%.2f, anchor antes de play()", startTime))
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
            // ✅ FIX TIMER CC (CAMBIO D): red de seguridad. Si iOS descartó la
            // publicación por llegar durante una transición de estado del
            // sistema (típico con la pantalla bloqueada), esta segunda la coge
            // ya con el audio sonando y el cronómetro anclado de verdad.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self,
                      self.scheduleGeneration == currentGeneration,
                      !self.isStopping else { return }
                self.publishNowPlayingInfoImmediately()
            }
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
        // ✅ REMUESTREO HI-RES: el seek se escala con la tasa de RENDER del
        // archivo (nativa), que es la unidad de file.length/scheduleSegment.
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

    // MARK: - Remuestreo Hi-Res (SRC interno del engine)

    /// ✅ REMUESTREO HI-RES (infraestructura): formato de CONEXIÓN del grafo =
    /// el del hardware de salida (outputNode, tasa real del DAC/ruta), no el
    /// del archivo. Los AVAudioFile se abren a su tasa NATIVA (makePlaybackFile)
    /// y la conversión la ejecuta el SRC interno del mixer del engine (su
    /// calidad es la por defecto de iOS: AVAudioMixerNode no permite
    /// configurarla; TN3136 documenta solo el AVAudioConverter manual). Con
    /// tasas iguales no hay conversión (ruta bit-perfect intacta); con 96 kHz
    /// sobre hardware 44.1/48 el SRC interno la hace a la calidad que iOS
    /// aplique. La señal que procesan EQ/mono/headroom pasa a la tasa del
    /// hardware (el EQ de 10 bandas está diseñado para 44.1/48 kHz).
    private func hardwareOutputFormat() -> AVAudioFormat {
        engine.outputNode.outputFormat(forBus: 0)
    }

    /// Formato de conexión/render del grafo: tasa REAL del hardware (fallback:
    /// la negociada por la sesión) a 2 canales float32 no interleaved.
    /// ✅ FIX CRASH AL REANUDAR TRAS CAMBIO DE RUTA: la tasa del outputNode
    /// puede ser irreal (0 Hz) y el channelCount 0 mientras la ruta está en
    /// transición (audífonos recién desconectados). Con tasas/canales no
    /// válidos se cae al formato estándar de la sesión, que es válido tras
    /// setActive(true); reconnectPlayerNode mantiene una última red igual.
    private func makeHardwareFormat() -> AVAudioFormat {
        let session = AVAudioSession.sharedInstance()
        let rate = hardwareOutputFormat().sampleRate
        let channels = hardwareOutputFormat().channelCount
        if rate > 1 && channels > 0 {
            return AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)
                ?? hardwareOutputFormat()
        }
        // ✅ FIX CRASH FORMATO: si la sesión tampoco da tasa válida, el
        // `?? hardwareOutputFormat()` devolvía el formato inválido en crudo
        // (0 Hz / 0 ch) y alimentaba engine.connect con basura. 44100/2
        // garantizado nunca es basura.
        return AVAudioFormat(standardFormatWithSampleRate: session.sampleRate, channels: 2)
            ?? AVAudioFormat(standardFormatWithSampleRate: 44_100.0, channels: 2)!
    }

    /// ✅ ACTIVACIÓN CONDICIONAL: solo hay conversión cuando la tasa del
    /// archivo difiere de la del hardware. Con 44.1↔44.1 (o 48↔48) el grafo
    /// es idéntico al anterior: cero coste de CPU y ruta bit-perfect intacta.
    private var srcConversionActive = false

    /// ✅ DIAGNÓSTICO SRC: estado y tasa de origen de la ÚLTIMA línea logueada.
    /// Se escribe cuando cambia cualquiera de los dos (transición de
    /// activo/inactivo o tasa de archivo distinta); las reconexiones repetidas
    /// del grafo y las canciones con la misma tasa no generan spam.
    private var srcLoggedActive: Bool?
    private var srcLoggedSourceRate: Double?

    private func updateSrcConversionState() {
        let hwRate = hardwareOutputFormat().sampleRate
        let source = sampleRate > 0 ? sampleRate : (currentSong?.sampleRate ?? 0)
        let active = source > 0 && hwRate > 1 && abs(hwRate - source) > 1
        srcConversionActive = active
        // ✅ REMUESTREO HI-RES (DIAGNÓSTICO, una línea por CAMBIO): tasa del
        // ARCHIVO (render nativo), tasa del HARDWARE, si el converter está
        // activo y la quality usada. Se loguea al cambiar el estado Y al cambiar
        // la tasa de origen aunque el estado no cambie (p. ej. 96 kHz → 44.1 kHz
        // sobre HW 48: el converter sigue ACTIVO, pero es otra conversión).
        // THROTTLE: si la tasa es la misma que la última logueada no se repite
        // ni por canción ni por reconexión del grafo.
        // Verificación esperada:
        //   · 96 kHz sobre HW 44.1/48 → "SRC Hi-Res ACTIVADO …".
        //   · 44.1 sobre HW 44.1      → "SRC Hi-Res INACTIVO" (sin remuestreo).
        // La conversión la hace el SRC interno del mixer del engine con la
        // calidad POR DEFECTO de iOS: AVAudioMixerNode no expone
        // sampleRateConverterQuality (solo AVAudioConverter la tiene) y no
        // existe API para fijarla desde una app.
        let rateChanged = srcLoggedSourceRate.map { abs($0 - source) > 1 } ?? true
        guard source > 0, srcLoggedActive != active || rateChanged else { return }
        srcLoggedActive = active
        srcLoggedSourceRate = source
        if active {
            AppLog.info(.playback, String(format: "SRC Hi-Res ACTIVADO: archivo %.0f Hz → hardware %.0f Hz (SRC interno del mixer del engine, calidad por defecto de iOS: no configurable desde la app)", source, hwRate))
        } else {
            AppLog.info(.playback, String(format: "SRC Hi-Res INACTIVO: archivo %.0f Hz, hardware %.0f Hz (sin remuestreo en el grafo; bit-perfect posible en ruta cableada sin EQ/mono/limiter)", source, hwRate))
        }
    }

    /// ✅ HI-RES: abre el archivo DECODIFICANDO a float32 estándar A LA MISMA
    /// TASA NATIVA del material (AVAudioFile(forReading:commonFormat:) no
    /// remuestrea: solo fija el formato de render; la tasa y los canales salen
    /// del archivo). El cambio de tasa lo hace el SRC interno del mixer del
    /// engine (calidad por defecto de iOS, no configurable), nunca el
    /// decodificador. Normaliza codecs cuyo processingFormat nativo no es
    /// float32 no interleaved.
    private func makePlaybackFile(_ url: URL) throws -> AVAudioFile {
        let container = try AVAudioFile(forReading: url)
        let source = container.processingFormat
        if source.commonFormat == .pcmFormatFloat32 && !source.isInterleaved {
            return container
        }
        return try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
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
            // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): pausa por
            // AVPlayer; el reloj de pared queda congelado en la posición previa.
            AppLog.info(.playback, String(format: "[CLOCK] pause AVPlayer: pos=%.2f posAnchor_before=%.2f", current, posAnchor))
            currentTime = current
            posAnchor = current
        } else {
            let current = wallClockTime
            // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): congelar la
            // extrapolación como nueva ancla en la pausa (ruta del motor).
            AppLog.info(.playback, String(format: "[CLOCK] pause: pos=%.2f posAnchor_before=%.2f", current, posAnchor))
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
        // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): último ancla antes
        // de suspender por pérdida de ruta; su pos y la del resume() deben coincidir.
        AppLog.info(.playback, String(format: "[CLOCK] suspendForRouteLoss: pos=%.2f posAnchor_before=%.2f", current, posAnchor))
        currentTime = current
        posAnchor = current
        wallAnchor = CACurrentMediaTime()
        clock.time = current
        isPlaying = false
        // ✅ FIX CRASH AL REANUDAR TRAS CAMBIO DE RUTA: loguear el estado SRC
        // de salida (solo lectura) para que la auditoría en LogsView muestre
        // contra qué tasa quedaba el converter al suspender por pérdida de
        // ruta, sin alterar comportamiento.
        // ✅ FIX log mentiroso: refrescar el estado ANTES de loguearlo — si no,
        // el log puede decir "converter activo" con rates ya iguales.
        updateSrcConversionState()
        let srcHwRate = hardwareOutputFormat().sampleRate
        let srcFileRate = sampleRate > 0 ? sampleRate : (currentSong?.sampleRate ?? 0)
        AppLog.info(.playback, String(format: "SRC suspendido por pérdida de ruta: archivo %.0f Hz · hardware %.0f Hz · converter %@", srcFileRate, srcHwRate, srcConversionActive ? "activo" : "inactivo"))
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
        // ✅ FIX CRASH SUSPENSION: si la app estuvo en segundo plano en pausa
        // más de 30 s, iOS ya desactivó la sesión y el grafo quedó
        // inconsistente; reutilizarlo (playerNode.play() /
        // engine.start() sobre él) era el crash. Con canción cargada se tira
        // TODO y se rehace por la ruta completa de playCurrentSong — sesión,
        // reconexión, apertura del archivo y reseek —, la misma que usa el
        // usuario al elegir una canción: no depende de ningún estado previo.
        // ⚠️ Solo aplica a la ruta del AVAudioEngine: en el respaldo (Dolby),
        // AVPlayer gestiona sus propios recursos y reanudar con avPlayer.play()
        // es exacto — reconstruir ahí reiniciaría el reproductor y re-seekearía
        // sin motivo (con un hueco audible) para tirar un grafo que no se usa.
        if needsFullEngineReset, !isAVPlayerActive, let song = currentSong {
            needsFullEngineReset = false
            performFullEngineReset()
            let position = min(max(currentTime, 0), max(song.duration - 0.05, 0))
            playCurrentSong(resumingAt: position)
            return
        }
        // ✅ FIX CRASH INTERRUPCION: si el engine NO corre, el grafo está muerto
        // SIN IMPORTAR CUÁNDO se mató (suspensión en background, interrupción que
        // termina con la app aún en background, media services reset). El flag
        // needsFullEngineReset solo cubre la vuelta a primer plano, así que con la
        // interrupción terminando en background quedaba en false y resume()
        // tomaba el camino rápido sobre un grafo muerto. Aquí se tira TODO y se
        // reconstruye por la ruta completa de playCurrentSong (sesión,
        // reconexión, apertura y reseek), que no depende de ningún estado previo.
        // ⚠️ engine.isRunning == false NO basta como señal: pause() llama a
        // engine.pause() y deja isRunning == false con el grafo INTACTO (docs de
        // AVAudioEngine). Por eso el reset exige además una bandera de muerte
        // EXTERNA; sin ella el motor estaba solo pausado por nosotros y se
        // reanuda sin reconectar (abajo), que es lo que evita el delay de
        // ~150 ms y la reapertura de archivo en cada pausa/play normal.
        if !engine.isRunning, !isAVPlayerActive, let song = currentSong,
           (needsFullEngineReset || engineDiedExternally) {
            needsFullEngineReset = false
            engineDiedExternally = false
            AppLog.info(.playback, "[BT CRASH] engine muerto al reanudar: reset completo")
            performFullEngineReset()
            let position = min(max(currentTime, 0), max(song.duration - 0.05, 0))
            playCurrentSong(resumingAt: position)
            return
        }

        if isAVPlayerActive {
            avPlayer?.play()
        } else {
            // ✅ FIX CRASH INTERRUPCION: con el engine parado por una muerte
            // EXTERNA ya se salió por el reset completo de arriba. Lo que queda
            // aquí es el motor pausado POR NOSOTROS (pause() → engine.pause()) o
            // un grafo muerto sin bandera: el primero se reanuda con start() SIN
            // reconectar nada (el grafo sigue intacto y playerNode.pause() conserva
            // su cola); el segundo se detecta porque start() falla.
            // Reconectar en este punto ERA el crash: startEngineSafely →
            // reconnectPlayerNode → engine.connect lanza AVAE_RaiseException
            // (NSException NO capturable con do/catch) → SIGABRT.
            var engineReady = engine.isRunning
            if !engineReady {
                do {
                    try engine.start()
                    engineReady = true
                    AppLog.info(.playback, "Resume: start() del engine pausado (sin reconectar el grafo)")
                } catch {
                    AppLog.error(.playback, error, context: "resume: start() del engine pausado")
                }
            }
            if engineReady {
                // ✅ RELOJ DE PARED: re-anclar la extrapolación en la posición
                // pausada; la UI y el lock screen arrancan exactos desde aquí.
                // playerNode.pause() (a diferencia de .stop()) NO descarta la
                // cola: si ya había una canción encadenada por adelantado,
                // sigue intacta y no hace falta re-programarla.
                // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): ancla y
                // reloj en el instante exacto del play() en la ruta rápida.
                AppLog.info(.playback, String(format: "[CLOCK] resume: currentTime=%.2f posAnchor=%.2f wallAnchor=%.3f", currentTime, posAnchor, wallAnchor))
                anchorPlaybackPosition(currentTime)
                clock.time = currentTime
                playerNode.play()
            } else {
                // ✅ FIX CRASH INTERRUPCION: start() falló = el grafo NO estaba
                // sano aunque no tuviéramos bandera (muerte externa sin aviso, p.
                // ej. una suspensión corta). Se reconstruye COMPLETO por la misma
                // ruta del reset de arriba: aquí NUNCA se llama a la reconexión
                // suelta, que es la que lanza la excepción no capturable.
                if let song = currentSong {
                    performFullEngineReset()
                    let position = min(max(currentTime, 0), max(song.duration - 0.05, 0))
                    playCurrentSong(resumingAt: position)
                } else {
                    // Sin canción que reanudar (stop() deja un AVAudioFile
                    // residual): se sale EN PAUSA sin tocar el grafo. Devolver el
                    // estado real es preferible a dejar isPlaying=true sin audio.
                    AppLog.info(.playback, "resume() con engine detenido y sin canción: ignorado")
                }
                return
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
                // ✅ REMUESTREO HI-RES: misma política de apertura (float32,
                // render nativo) que la reproducción activa.
                let file = try makePlaybackFile(url)
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
        
        // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): posición pedida vs.
        // la que el reloj de pared reportaba justo antes del seek.
        AppLog.info(.playback, String(format: "[CLOCK] seek: target=%.2f currentTime_before=%.2f", time, wallClockTime))
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
        // ✅ FIX POST-G (micro-corte al activar shuffle/repeat): aquí vivía
        // rechainAheadAfterOrderChange(), que hacía playerNode.stop() + resiembra
        // de la canción actual para re-encadenar contra el orden nuevo — y ese
        // stop corta el buffer vivo: el micro-corte audible. El segmento ya
        // encolado no se puede desprogramar sin parar el nodo, así que se
        // conserva: sonará la canción elegida con el orden viejo (igual que en
        // Apple Music) y el orden nuevo entra en el SIGUIENTE commit natural.
        // Solo se re-ancla su índice por IDENTIDAD: el índice heredado apuntaba
        // al orden viejo y commitChainedSong() promovería una canción equivocada
        // (saltos o repetidos) al terminar la actual.
        if let chained = chainedAheadSong {
            chainedAheadIndex = playbackOrder.firstIndex(where: { $0.id == chained.id })
        }
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
        // ✅ FIX POST-G (micro-corte al activar shuffle/repeat): aquí vivía
        // rechainAheadAfterOrderChange() (playerNode.stop() + resiembra), y ese
        // stop cortaba el buffer vivo. El modo nuevo entra en el siguiente commit
        // natural: la transición ya encolada suena como se programó (trade-off
        // estilo Apple Music) y a partir de ahí manda el modo nuevo. Aquí no hace
        // falta re-anclar índice: esta función no altera playbackOrder.
        // ✅ FASE B4: la repetición también es estado de reproducción: se publica
        // el diccionario completo para que las superficies del sistema (CC,
        // bloqueo, CarPlay) queden sincronizadas con la app.
        updateNowPlayingInfo(force: true)
        AppLog.info(.playback, "Repetición: \(name)")
    }

    // ✅ MEJORA QUEUE (FASE E1): "Reproducir siguiente". A diferencia de
    // addToQueue (que añade al FINAL: suena después de todo lo que ya estaba
    // en cola), aquí la canción se inserta al PRINCIPIO de `manualQueue`, y
    // computeNextIndex() consume `removeFirst()` justo después de la actual:
    // suena inmediatamente después, por delante del resto de la cola manual.
    // Es la operación que el menú contextual anunciaba como "Reproducir
    // siguiente" y que en realidad reemplazaba la lista entera (play(song:
    // from:) con una lista recortada).
    //
    // ✅ E1.5 — desalojo del encolado: como el motor ya dejó programada la
    // siguiente en el nodo (encadenado gapless, ver scheduleAheadIfPossible),
    // esa transición ganaría a la recién insertada: el audio está ya en el
    // `playerNode` y no se puede desprogramar un segmento suelto. Se desaloja
    // con invalidateChainedAhead() (token a 0, sin apilar otra transición
    // encima): al terminar la canción actual el motor cae al respaldo atómico
    // y recalcula con la cola YA modificada, así que suena X y no B.
    // Coste declarado: esa transición concreta deja de ser gapless (~0,15 s del
    // respaldo atómico) y el audio huérfano de B lo descarta playCurrentSong.
    func playNext(_ song: Song) {
        // ✅ E1.5: se comprueba ANTES de desalojar, solo para el log.
        let hadChainedAhead = chainedAheadIndex != nil
        invalidateChainedAhead()
        // ✅ E1.5 — guard anti-deriva: si el encolado salió de la COLA MANUAL,
        // computeNextIndex() ya adelantó `currentIndex` a ESA canción
        // (`currentIndex = insertionIndex`) mientras sonaba la anterior, y el
        // respaldo atómico que dispara el desalojo reproduce
        // `currentIndex + 1`: la canción encolada, que vive EN `currentIndex`,
        // se quedaría sin sonar. Se retrocede el puntero a la canción que suena.
        // El guard es por IDENTIDAD, no por heurística: en repeat-one el
        // encolado ES la canción actual (playbackOrder[currentIndex].id ==
        // currentSong.id) y ahí no hay deriva que corregir.
        if let chained = chainedAheadIndex, chained == currentIndex,
           playbackOrder.indices.contains(currentIndex),
           playbackOrder[currentIndex].id != currentSong?.id {
            currentIndex -= 1
        }
        // ✅ E3.5: si la canción ya está en el ORDEN por delante de la actual, se
        // QUITA de ahí antes de encolarla. Si no, sonaría dos veces: ahora desde
        // la cola manual (que `computeNextIndex()` consume con prioridad) y otra
        // vez al llegar el orden a su posición original, que seguía intacta.
        if let removedIndex = removeQueuedCopyFromOrder(song) {
            AppLog.info(.playback, "Reproducir siguiente: quitada de la posición \(removedIndex) del orden")
        }
        manualQueue.insert(song, at: 0)
        updateNextUpQueue()
        // ✅ FASE B4: mismo criterio que add/remove/reorder — la cola es estado
        // que se publica a iOS (la "siguiente" que anuncian CC/bloqueo/CarPlay
        // sale de ella).
        updateNowPlayingInfo(force: true)
        AppLog.info(.playback, hadChainedAhead
            ? "Reproducir siguiente (desalojando encolado): \(song.title)"
            : "Reproducir siguiente: \(song.title)")
    }

    /// ✅ E3.5 — De-duplicación al ENCOLAR (estilo Spotify): MUEVE la canción, no
    /// la duplica.
    ///
    /// Si la canción que el usuario manda a la cola manual está TAMBIÉN en el
    /// orden (`playbackOrder`) por delante de la posición actual, se quita de ahí.
    /// Sin esto sonaba dos veces: la primera desde la cola manual (que
    /// `computeNextIndex()` consume con prioridad) y la segunda cuando el orden
    /// llegaba a su posición original, porque `addToQueue`/`playNext` solo tocaban
    /// `manualQueue` y nadie quitaba la copia del orden.
    ///
    /// Mira SOLO desde `currentIndex + 1`: la canción que suena (y, en repeat-one,
    /// la que se va a repetir, que en el orden vive EN `currentIndex`) no se toca
    /// nunca. Devuelve el índice quitado para el log del llamador, o nil si no
    /// había copia en el orden.
    private func removeQueuedCopyFromOrder(_ song: Song) -> Int? {
        // El clamp evita el crash de un rango `[n...]` cuando currentIndex ya está
        // al final del orden (n > count aborta el proceso).
        let from = max(currentIndex + 1, 0)
        guard from < playbackOrder.count,
              let index = (from..<playbackOrder.count).first(where: { playbackOrder[$0].id == song.id })
        else { return nil }
        // La transición de gapless apunta por ÍNDICE. Si la copia que se quita es
        // justo la que ya está programada en el nodo, ese índice pasa a señalar a
        // OTRA canción (todo lo posterior se desplaza) y `commitChainedSong()` la
        // promovería con el estado equivocado: se invalida el token (0) para que al
        // terminar la actual el motor recalcule con el orden YA corregido. El audio
        // huérfano de esa transición lo descarta `playCurrentSong`
        // (`playerNode.stop()`), igual que en el desalojo de E1.5.
        if chainedAheadIndex == index { invalidateChainedAhead() }
        playbackOrder.remove(at: index)
        // Si la transición encolada estaba DESPUÉS de la copia quitada, su índice
        // se desplaza con el array: sin corregirlo, al promover se saltaría una
        // canción (prioridad nº1: nada de saltos).
        if let chained = chainedAheadIndex, chained > index { chainedAheadIndex = chained - 1 }
        // `playbackQueue` es el espejo publicado del orden y lo consume la UI (es el
        // contexto que usa "Reproducir ahora" en la cola): si no se refresca, ese
        // camino reconstruiría el orden con la canción ya quitada y la duplicaría
        // otra vez.
        updatePlaybackQueue()
        return index
    }

    // ✅ MEJORA QUEUE: añadir canción a la cola manual
    func addToQueue(_ song: Song) {
        // ✅ E3.5: misma de-duplicación que en playNext. Sin esto, encolar desde
        // "A continuación" dejaba la canción en las dos listas (y sonaba dos veces).
        if let removedIndex = removeQueuedCopyFromOrder(song) {
            AppLog.info(.playback, "Añadido a cola: quitada de la posición \(removedIndex) del orden")
        }
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
        // ✅ FIX POST-G (restore pierde la playlist): recuperar el ORDEN REAL de
        // la sesión guardada re-mapeando los UUID de saveState() contra la
        // biblioteca actual. Antes SIEMPRE se reconstruía con la biblioteca
        // completa: la canción sonaba bien (songID) pero la "siguiente" pasaba a
        // ser otra canción cualquiera, no la del álbum/playlist en curso.
        var restoredSessionOrder: (playback: [Song], original: [Song])?
        if let playbackIDStrings = state["playbackOrderIDs"] as? [String],
           let originalIDStrings = state["originalOrderIDs"] as? [String] {
            // Mismo patrón y misma garantía de IDs únicos que songsInPlaylist().
            let byID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
            let restoredPlaybackOrder = playbackIDStrings.compactMap { idString in
                UUID(uuidString: idString).flatMap { byID[$0] }
            }
            let restoredOriginalOrder = originalIDStrings.compactMap { idString in
                UUID(uuidString: idString).flatMap { byID[$0] }
            }
            // Válido solo si AMBOS órdenes sobreviven al mapeo (biblioteca
            // cambiada/borrada = IDs perdidos) y contienen la canción actual.
            if !restoredPlaybackOrder.isEmpty,
               !restoredOriginalOrder.isEmpty,
               restoredPlaybackOrder.contains(where: { $0.id == song.id }) {
                restoredSessionOrder = (restoredPlaybackOrder, restoredOriginalOrder)
            } else {
                AppLog.warning(.playback, "restoreState: playbackOrder no recuperable, usando biblioteca")
            }
        }
        // Retrocompatibilidad: un state sin playbackOrderIDs (versión anterior
        // de la app) cae al fallback de siempre, sin warning.
        if let sessionOrder = restoredSessionOrder {
            playbackOrder = sessionOrder.playback
            originalOrder = sessionOrder.original
        } else {
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

    // ✅ G: AQUÍ VIVÍAN las 4 funciones legacy del trío "Siguiente"
    // (`removeFromNextUpQueue`, `reorderNextUpQueue`, `clearNextUpQueue` y su
    // `rebuildPlaylistFromQueue`). Se borran tras verificar 0 call sites: E3
    // dejó de usarlas al pasar QueueView a las operaciones DIRECTAS sobre la
    // cola (removeFromQueue / moveInQueue / clearQueue) y nadie más las
    // llamaba. Su problema de diseño era el de `rebuildPlaylistFromQueue`:
    // rehacía el orden COMPLETO a partir de la cola, así que editar la cola
    // reescribía el álbum en curso.

    private func startDisplayTimer() {
        stopDisplayTimer()
        var tickCount = 0
        // ✅ OPT BG: la cadencia se decide por el ESTADO REAL de la app, no por lo
        // que recuerde el llamador. `playCurrentSong()`, `resume()` y el respaldo
        // (Dolby) rearman este timer en cada cambio de pista SIN contexto: en
        // segundo plano rearmaban la cadencia de PRIMER PLANO (0.4s, con
        // publicación de Now Playing cada 0.8s, medida de drift y watchdog en
        // cada tick) y la mantenían el resto de la sesión — el calor con la
        // pantalla bloqueada o usando otra app salía de ahí.
        // ✅ OPTIMIZACIÓN DE BATERÍA: en primer plano 0.4s es suficiente para
        // una UI fluida (la barra de progreso responde rápido al seek/pause),
        // y en segundo plano 6.0s: la UI no se ve e iOS extrapola el progreso
        // del lock screen/CC con el rate, así que el timer solo existe para
        // los watchdogs, la persistencia de posición y una publicación de
        // seguridad al minuto.
        let isBackground = UIApplication.shared.applicationState == .background
        // ✅ OPT BG: throttling térmico (ligero): con el teléfono caliente
        // (.serious/.critical) el timer de segundo plano se estira a 15s. En
        // primer plano NO se toca: este mismo timer alimenta la barra de
        // progreso de la app y saltaría a tirones de 15s.
        let thermal = ProcessInfo.processInfo.thermalState
        let thermallyThrottled = (thermal == .serious || thermal == .critical)
        let interval: TimeInterval = isBackground ? (thermallyThrottled ? 15.0 : 6.0) : 0.4
        // ✅ OPT BG: en segundo plano se publica una vez por minuto (10 ticks)
        // en vez de en cada tick. iOS extrapola con playbackRate y los cambios
        // reales (canción/estado/seek/cola) publican con force:true al instante;
        // esta cadencia queda solo como red de seguridad por si el sistema
        // descartó una publicación durante una transición de bloqueo.
        let nowPlayingRefreshTicks = isBackground ? 10 : 2
        // ✅ OPT BG: evidencia en dispositivo (barata: solo al REARMAR el timer,
        // no por tick). Con el bug, en segundo plano se veía 0.4s tras cada
        // cambio de pista; ahora debe verse 6.0s (o 15.0s con el teléfono
        // caliente) durante toda la sesión en background.
        AppLog.info(.playback, String(format: "[OPT BG] timer: %.1f s (%@%@)", interval, isBackground ? "background" : "foreground", thermallyThrottled ? ", térmico" : ""))
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
                // ✅ TAREA DRIFT: MEDIR y loguear el desfase entre el reloj de
                // pared (host) y el reloj del nodo de audio. SIN corrección
                // automática: primero datos, después decisión.
                self.measureClockDrift()
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
            // suena (37 ticks × 0.4s fg / 3 × 6.0s bg = 18s). Así un cierre
            // forzado (kill sin willResignActive) restaura la posición más
            // reciente, no la del último cambio de canción.
            // ✅ OPT BG: en segundo plano se persiste SOLO la posición (ver
            // saveState(positionOnly:)): ni el orden de reproducción ni la cola
            // cambian por estar sonando, y re-serializarlos cada 18s era CPU e
            // I/O gratis (900+ UUID × 3 arrays por escritura).
            self.persistTickCounter += 1
            if self.persistTickCounter >= (isBackground ? 3 : 37) {
                self.persistTickCounter = 0
                self.saveState(positionOnly: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // MARK: - Medición de drift host ↔ hardware de audio (SOLO MEDICIÓN)
    /// ✅ TAREA DRIFT: corre en cada tick del displayTimer (solo modo engine).
    /// Compara la posición extrapolada por el reloj de pared (posAnchor +
    /// CACurrentMediaTime, monótono pero del HOST) con la posición derivada del
    /// reloj del nodo (playerTime.sampleTime avanza al ritmo del reloj del
    /// hardware de audio) usando una REFERENCIA RELATIVA sembrada tras cada
    /// anclaje (anchorPlaybackPosition la invalida).
    ///
    /// · SIN corrección automática: el intento anterior re-anclaba el reloj y
    ///   producía saltos visibles en la animación de la línea activa. Aquí solo
    ///   se mide y se loguea; la decisión se tomará con los datos recogidos.
    /// · Evidencia: muestra cada 75 ticks (~30s en primer plano) y las
    ///   TRANSICIONES del umbral de 100ms (no cada tick: sin spam).
    /// · La siembra NO descuenta la latencia de salida: el drift sale de los
    ///   DELTAS de ambos relojes desde el mismo instante, así que restarla solo
    ///   en el seed la dejaba como sesgo constante +latencia en cada medida (en
    ///   BT ≈ 150 ms, indistinguible de un drift real).
    private func measureClockDrift() {
        guard isPlaying, !isAVPlayerActive, playerNode.isPlaying,
              let lastRender = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: lastRender),
              playerTime.sampleRate > 0 else {
            clockDriftReference = nil
            clockDriftHighActive = false
            return
        }

        let nodeSample = playerTime.sampleTime
        let nodeRate = playerTime.sampleRate

        // ✅ El timeline del nodo se reinicia si el engine se paró sin pasar por
        // un anclaje (defensivo): una referencia de un timeline viejo daría un
        // Δnode negativo y una medición falsa. Se descarta y se re-siembra.
        if let reference = clockDriftReference,
           (reference.sampleRate != nodeRate || nodeSample < reference.nodeSample) {
            clockDriftReference = nil
        }

        let extrapolated = max(0, posAnchor + (CACurrentMediaTime() - wallAnchor))

        guard let reference = clockDriftReference else {
            // ✅ SIEMBRA: pareja (posición host, sample del nodo) del MISMO
            // instante, sin ajuste de latencia: el drift son deltas relativos a
            // partir de aquí, y cualquier constante en el seed sesga todas las
            // medidas (ver cabecera).
            clockDriftReference = (pos: extrapolated,
                                   nodeSample: nodeSample,
                                   sampleRate: nodeRate)
            clockDriftLogCounter = 0
            clockDriftHighActive = false
            return
        }

        let audible = max(0, reference.pos + Double(nodeSample - reference.nodeSample) / nodeRate)
        let drift = extrapolated - audible

        clockDriftLogCounter += 1
        if clockDriftLogCounter >= 75 {
            clockDriftLogCounter = 0
            AppLog.info(.playback, String(format: "Drift de reloj (host − audio): %.1f ms", drift * 1000))
        }

        // ✅ Umbral de decisión (100ms): loguear SOLO las transiciones para tener
        // los episodios documentados sin inundar el log. La corrección queda
        // a decisión con estos datos.
        let isHigh = abs(drift) > 0.1
        // ✅ FIX spam: cooldown de 30 s. El valor oscila alrededor del umbral
        // y sin cooldown el log se llena con cientos de líneas por minuto.
        if isHigh != clockDriftHighActive,
           CACurrentMediaTime() - clockDriftLastLogTime > 30 {
            clockDriftHighActive = isHigh
            clockDriftLastLogTime = CACurrentMediaTime()
            if isHigh {
                AppLog.info(.playback, String(format: "Drift de reloj supera 100 ms: %.0f ms — solo medición, sin corrección", drift * 1000))
            }
        }

        // ✅ FIX drift persistente: si el desfase supera 150 ms y no se ha
        // corregido en los últimos 5 s, re-anclar el reloj de pared a la
        // posición audible del nodo. Corrige el drift que sobrevive a cambios
        // de ruta sin re-anclaje, sin esperar al siguiente anclaje natural.
        if abs(drift) > 0.15,
           CACurrentMediaTime() - clockDriftLastCorrectionTime > 5 {
            clockDriftLastCorrectionTime = CACurrentMediaTime()
            // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): la corrección
            // sustituye la extrapolación del HOST por la posición audible del
            // NODO: aquí se ve el salto exacto que percibe la UI.
            AppLog.info(.playback, String(format: "[CLOCK] drift corregido: drift=%.0fms posAnchor_before=%.2f posAnchor_after=%.2f audible=%.2f", drift * 1000, posAnchor, audible, audible))
            posAnchor = audible
            wallAnchor = CACurrentMediaTime()
            clockDriftReference = nil
            AppLog.info(.playback, String(format: "Drift corregido: %.0f ms", drift * 1000))
        }
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
            // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): si dispara con
            // audio aún sonando (BT), aquí está el "salto al final".
            AppLog.info(.playback, String(format: "[CLOCK] WATCHDOG dispara: elapsed=%.2f duration=%.2f margin=%.2f", elapsed, duration, watchdogMargin))
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
        // ⏳ INSTRUMENTACIÓN CLOCK (retirar tras diagnóstico): ancla del respaldo
        // AVPlayer (Dolby/fallo del motor); mientras esté activo, currentTime
        // viene del observer de AVPlayer, no del reloj de pared.
        AppLog.info(.playback, String(format: "[CLOCK] startFallbackPlayback: pos=%.2f posAnchor_before=%.2f", start, posAnchor))
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

            // ✅ FIX PERFIL BT DECLARADO: iOS NO permite forzar la vuelta de HFP a
            // A2DP desde la app (el SCO lo libera el sistema), pero sí detectar el
            // estado y declararlo. Mismo switch que el codec, sobre el portType.
            let newProfile: String
            if portType == AVAudioSession.Port.bluetoothA2DP.rawValue {
                newProfile = "A2DP"
            } else if portType == AVAudioSession.Port.bluetoothHFP.rawValue {
                newProfile = "HFP"
            } else if portType == AVAudioSession.Port.bluetoothLE.rawValue {
                newProfile = "LE"
            } else {
                newProfile = ""
            }
            self.bluetoothProfile = newProfile
            // Log SOLO en la transición (no en cada refresco de la telemetría).
            if newProfile != self.lastLoggedBluetoothProfile {
                if newProfile == "HFP" && self.lastLoggedBluetoothProfile == "A2DP" {
                    AppLog.warning(.playback, "BT degradado a HFP (manos libres, mono)")
                } else if newProfile == "A2DP" && self.lastLoggedBluetoothProfile == "HFP" {
                    AppLog.info(.playback, "BT restaurado a A2DP (estéreo)")
                }
                self.lastLoggedBluetoothProfile = newProfile
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

    /// ✅ FIX 6: una sola línea con TODO lo que importa para diagnosticar un
    /// problema de calidad (ruta, tasas, SRC, mono, EQ, ganancia, perfil BT).
    /// Se llama en tres puntos de cambio real: play manual, gapless y cambio
    /// de ruta. No se llama en cada tick ni en cada refresh de telemetría.
    private func logQualityAuditLine(context: String) {
        let session = AVAudioSession.sharedInstance()
        let graphRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let src = srcConversionActive ? "SRC activo" : "sin SRC"
        let mono = isMonoAudioEnabled ? "mono" : "estéreo"
        let eq = (isEQEnabled && eqPreset != .flat) ? "EQ \(eqPreset.rawValue)" : "sin EQ"
        let systemMono = UIAccessibility.isMonoAudioEnabled ? " · mono-sistema" : ""
        let bt = bluetoothProfile.isEmpty ? "sin BT" : "BT \(bluetoothProfile)"
        AppLog.info(.playback, String(format: "Auditoría [%@]: ruta %@ · sesión %.0f Hz · grafo %.0f Hz · archivo %.0f Hz · %@ · %@ · %@ · ganancia %.3f · %@%@",
                                      context,
                                      routeDisplay,
                                      session.sampleRate,
                                      graphRate,
                                      sampleRate,
                                      src,
                                      mono,
                                      eq,
                                      outputGain,
                                      bt,
                                      systemMono))
    }

    // ✅ Auto-reanudación al conectar audífonos
    private var wasPlayingBeforeRouteChange = false
    // ✅ FIX resume() fantasma tras desconectar BT: cada notificación de ruta
    // invalida los bloques diferidos de las notificaciones anteriores. iOS emite
    // .newDeviceAvailable (aparece el altavoz interno) y .oldDeviceUnavailable
    // (se va el Bluetooth) casi a la vez; el bloque diferido de la primera no
    // sabía que la ruta ya había cambiado y reanudaba en el altavoz interno.
    private var routeChangeGeneration = 0

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

            // ✅ FIX resume() fantasma: la generación sube ANTES de cualquier rama
            // (incluida la suspensión por pérdida de ruta), así el bloque diferido
            // de un .newDeviceAvailable anterior queda invalidado.
            self.routeChangeGeneration &+= 1
            let gen = self.routeChangeGeneration
            // ✅ FIX CRASH INTERRUPCION: un cambio de ruta reconstruye/reconecta el
            // grafo (o lo suspende por pérdida de ruta, que descarta la cola) →
            // muerte EXTERNA marcada.
            self.engineDiedExternally = true

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
                    // ✅ FIX resume() fantasma tras desconectar BT: DOS barreras, la
                    // generación (¿sigue vigente esta decisión?) y el portType real
                    // (¿es el altavoz interno?). El resultado de esta comprobación YA
                    // se calculaba aquí y se DESCARTABA (`_ =`): ahora gobierna la
                    // reanudación. `usbAudio` se suma a la lista de isHeadphonePort
                    // porque el helper no incluye los DAC USB/Lightning.
                    let canAutoResume = gen == self.routeChangeGeneration
                        && (route.map { output in
                            Self.isHeadphonePort(output.portType) || output.portType == .usbAudio
                        } ?? false)

                    // ✅ FIX desconexión BT: reanudar en CUALQUIER ruta (no solo audífonos)
                    // Si estaba reproduciendo y se cambió de ruta, reanudar si está pausado
                    if wasPlaying && !self.isPlaying, canAutoResume {
                        self.resume()
                        AppLog.info(.playback, "Ruta cambiada a \(route?.portName ?? "?"): reproducción reanudada")
                    } else if wasPlaying && !self.isPlaying {
                        // ✅ Evidencia en dispositivo: aquí vivía la reanudación fantasma
                        // en el altavoz interno (descartada por generación o por ruta).
                        AppLog.info(.playback, "Ruta cambiada a \(route?.portName ?? "?"): reanudación automática descartada")
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
                            // ✅ FIX FLAG MUERTO RESIDUAL: reconexión ligera sin
                            // error → grafo vivo y reprogramado; el flag solo
                            // queda true si el start lanza (lo deja el catch) y
                            // entonces resume() reconstruye entero.
                            self.engineDiedExternally = false
                            // ✅ 3.0.1 BIT-PERFECT: el dispositivo nuevo puede haber
                            // negociado otra tasa; se recupera la nativa del archivo
                            // antes de reprogramar (solo en ruta cableada, y solo si
                            // realmente difiere).
                            self.reassertNativeSampleRateIfNeeded()
                            self.scheduleFile(file, from: position, generation: self.scheduleGeneration)
                            // ✅ FIX drift tras reconexión: el ancla va DESPUÉS de
                            // reprogramar, justo antes de que arranque el nuevo
                            // render. Antes se anclaba al iniciar el engine y el
                            // host se adelantaba durante la reprogramación/arranque
                            // de la ruta nueva → drift de cientos de ms persistente.
                            self.anchorPlaybackPosition(position)
                            self.clock.time = position
                            self.currentTime = position
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
                self?.logQualityAuditLine(context: "ruta")
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
            // ✅ FIX CRASH INTERRUPCION: una interrupción tumba el grafo de Core
            // Audio aunque no estemos reproduciendo (iOS libera el motor). Queda
            // marcado como muerte EXTERNA para que el próximo arranque reconstruya
            // en vez de reconectar sobre un grafo inconsistente.
            self.engineDiedExternally = true
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

    /// ✅ FIX BIT-PERFECT HONESTO (mono del sistema): Mono Audio se activa en
    /// Ajustes › Accesibilidad, fuera de la app. Sin este observer el indicador
    /// solo se corregía en el siguiente cambio de pista/ruta/ganancia, así que
    /// podía decir "Bit-Perfect: sí" con el sistema en mono.
    private func observeSystemMonoAudio() {
        NotificationCenter.default.addObserver(
            forName: UIAccessibility.monoAudioStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.refreshBitPerfect(outputRate: self.outputSampleRate)
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
        // ✅ FIX TIMER CC (CAMBIO A): sin duración válida NO se publica
        // cronómetro. Con `duration` 0 (metadatos sin duración, o el respaldo
        // Dolby cuando el archivo no la trae) CUALQUIER elapsed da un restante
        // NEGATIVO en CC/bloqueo ("-0:00", la firma del bug) porque iOS lo
        // extrapola con el rate. Se publican solo metadatos + rate 0 (el
        // sistema deja de extrapolar y no dibuja barra) y NO se tocan
        // elapsed, duración ni playbackState.
        guard duration > 0 else {
            info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
            info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            lastNowPlayingPublishTime = CACurrentMediaTime()
            lastPublishedSongID = currentSong?.id
            lastPublishedIsPlaying = isPlaying
            lastPublishedDuration = duration
            return
        }
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
        // ✅ FIX TIMER CC (CAMBIO A): clamp defensivo. Si iOS recibe
        // elapsed >= duration cae a "-0:00" y se queda AHÍ hasta la siguiente
        // publicación completa: es exactamente lo que ocurría al anclar como
        // posición nueva el final (clampado) de la canción anterior. Se deja
        // 0.1 s de margen para que el restante nunca sea negativo.
        let rawElapsed: TimeInterval = (isPlaying && !isAVPlayerActive) ? wallClockTime : currentTime
        let elapsedForPublish: TimeInterval = min(max(rawElapsed, 0), max(0, duration - 0.1))
        // ✅ Evidencia en dispositivo: solo se registra cuando la corrección es
        // perceptible (> 250 ms), que es exactamente el desfase que el usuario
        // veía entre la barra in-app y la del Centro de Control.
        if abs(elapsedForPublish - currentTime) > 0.25 {
            AppLog.info(.playback, String(format: "NowPlaying: elapsed %.2fs publicado (el tick tenía %.2fs)", elapsedForPublish, currentTime))
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedForPublish

        // ✅ FIX TIMER CC (CAMBIO B): cambio de CANCIÓN en DOS FASES. iOS usa
        // `playbackRate = 0` como señal de "deja de extrapolar": si recibe
        // rate 1 + elapsed 0 de golpe, sigue avanzando desde el elapsed
        // ANTERIOR (el final de la canción vieja, ya clavado en su duración) y
        // la barra del Centro de Control / pantalla de bloqueo aparece con el
        // restante a "-0:00" y no se reinicia. Fase 1 = rate 0 + elapsed 0
        // (re-ancla el cronómetro del sistema en el nuevo tema); fase 2, un
        // turno de run loop después, = la publicación normal con rate real.
        // El libro de contabilidad de abajo se actualiza en la fase 1 para que
        // `publishIfNeeded` no vuelva a entrar por identidad y la fase 2 no
        // re-dispara el ciclo.
        if lastPublishedSongID != currentSong?.id {
            info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
            info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            MPNowPlayingInfoCenter.default().playbackState = .paused
            lastNowPlayingPublishTime = CACurrentMediaTime()
            lastPublishedSongID = currentSong?.id
            lastPublishedIsPlaying = isPlaying
            lastPublishedDuration = duration
            AppLog.info(.playback, "NowPlaying: fase 1 (rate 0, elapsed 0) para '\(currentSong?.displayName ?? "-")'")
            // ✅ Dos TURNOS distintos del run loop: la fase 1 se asigna en este
            // turno y la fase 2 en el siguiente (0.01 s). Dos asignaciones en el
            // MISMO turno pueden quedar coalescidas y iOS se quedaría con la de
            // rate 0 (canción nueva clavada en pausa).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                self?.publishNowPlayingInfo()
            }
            return
        }

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

    private func saveState(positionOnly: Bool = false) {
        // ✅ OPT BG: la persistencia periódica del timer solo refresca la
        // POSICIÓN. Se PARTE del diccionario ya guardado (UserDefaults lo tiene
        // en memoria) para no borrar el resto del estado: re-serializar en cada
        // tick el orden completo de reproducción (900+ UUID) y la cola manual
        // era puro gasto, porque esos campos solo cambian con acciones del
        // usuario, que ya llaman a saveState() completo.
        var state = positionOnly
            ? (UserDefaults.standard.dictionary(forKey: stateDefaultsKey) ?? [:])
            : [String: Any]()
        state["isPlaying"] = isPlaying
        state["currentTime"] = currentTime
        state["currentIndex"] = currentIndex
        // ✅ FIX: guardar la IDENTIDAD de la canción (UUID). restoreState()
        // la usa para rescatar la canción EXACTA aunque la biblioteca cambie
        // de orden entre sesiones (antes solo currentIndex → canción errónea).
        if let song = currentSong {
            state["songID"] = song.id.uuidString
            state["songDuration"] = song.duration
        }
        if !positionOnly {
            // ✅ MEJORA QUEUE: guardar cola manual para persistencia
            state["manualQueue"] = manualQueue.map { $0.id.uuidString }
            // ✅ FIX POST-G (restore pierde la playlist): guardar el ORDEN de sesión
            // real (álbum, playlist, búsqueda...) y el orden original de referencia.
            // Sin esto, restoreState() reconstruía con la biblioteca completa y la
            // "siguiente" era cualquier canción cercana en orden alfabético.
            state["playbackOrderIDs"] = playbackOrder.map { $0.id.uuidString }
            state["originalOrderIDs"] = originalOrder.map { $0.id.uuidString }
        }
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