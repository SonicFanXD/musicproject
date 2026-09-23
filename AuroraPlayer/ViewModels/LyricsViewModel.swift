import Foundation
import Combine
import QuartzCore

// MARK: - ViewModel para lyrics línea por línea
// ✅ SIN Timer: la sincronización se alimenta del reloj de reproducción
//    (`audioEngine.clock.$time`, publica cada 0.4s) y el wipe interpola entre
//    ticks con un ancla CACurrentMediaTime → 60 fps reales en la vista.
// ✅ Sin publicar en cada tick: `clockTime`/`clockUpdateDate` son propiedades
//    normales que el TimelineView lee en cada frame (cero re-renders por tick).
// ✅ El cambio de línea se despierta EXACTAMENTE en el boundary (Task.sleep),
//    no en el siguiente tick: no se pierde hasta 0.4s de sincronía visual.
// ✅ Conecta con AudioEngine existente sin modificar la ruta de audio.
final class LyricsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var activeID: Int? = nil
    @Published var lyricsLines: [LyricsLine] = []
    @Published var hasLyrics: Bool = false
    /// ✅ Espejo de `audioEngine.isPlaying`: permite pausar el TimelineView de la
    /// vista cuando no suena nada (batería) y congelar la interpolación.
    @Published private(set) var isPlaying: Bool = false
    /// ✅ Sube cuando un parseo EN BACKGROUND termina: la vista lo usa para
    /// repetir el centrado inicial (cuando termina, el `onAppear` ya pasó).
    @Published private(set) var lyricsRevision: Int = 0

    // MARK: - Dependencies
    weak var audioEngine: AudioEngine?
    private var engine: LyricsEngine?

    // MARK: - Observación del reloj (sin Timer)
    private var clockCancellable: AnyCancellable?
    private var playbackStateObserver: NSObjectProtocol?
    private var lineBoundaryTask: Task<Void, Never>?

    // MARK: - Ancla de interpolación (se lee en cada frame desde la vista)
    /// Último tiempo publicado por el reloj y el instante (CACurrentMediaTime)
    /// en que se recibió: el wipe dibuja `clockTime + transcurrido`.
    private var clockTime: TimeInterval = 0
    private var clockUpdateDate: CFTimeInterval = 0

    // MARK: - Ventana de la línea activa (cache O(1) para el wipe)
    private var activeStartMs: Int = 0
    private var activeEndMs: Int = 0

    // MARK: - Parseo (token de vigencia)
    /// ✅ Cada llamada a `parseLyrics` invalida el parseo pendiente anterior: si el
    /// usuario cambia de canción mientras uno está en vuelo, el resultado viejo
    /// se descarta en vez de publicarse sobre la canción nueva.
    private var parseToken: Int = 0
    /// ✅ Por debajo de este tamaño el parseo es sub-milisegundo (LRC clásico) y se
    /// aplica en el MISMO turno: así la vista nace ya centrada, sin parpadeo del
    /// estado vacío ni segundo centrado. Solo los payloads grandes (TTML con
    /// timings por palabra, donde el XMLParser + las regex + el troceo de filas
    /// sí pesan) se van a background.
    private static let synchronousParseByteLimit = 16_000

    // MARK: - Initialization
    init() {
        // ✅ AudioEngine se conecta después para evitar ciclo de referencia
    }

    deinit {
        clockCancellable?.cancel()
        lineBoundaryTask?.cancel()
        if let observer = playbackStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Conectar audioEngine (llamado por AudioEngine después de init)
    func connectAudioEngine(_ audioEngine: AudioEngine) {
        self.audioEngine = audioEngine

        // ✅ Se observa `clock.$time` (PlaybackClock) y NO una propiedad publicada
        // del propio AudioEngine: el publisher de `audioEngine.$x` retiene al
        // engine y crearía el ciclo AudioEngine → ViewModel → publisher → AudioEngine.
        clockCancellable?.cancel()
        clockCancellable = audioEngine.clock.$time
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.receiveClockTime(time)
            }

        // ✅ Estado de reproducción: AudioEngine.isPlaying lo publica desde su
        // didSet como "PlaybackStateChanged" (tampoco retiene al engine).
        if playbackStateObserver == nil {
            playbackStateObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("PlaybackStateChanged"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.syncPlaybackState()
            }
        }

        syncPlaybackState()
    }

    // MARK: - Parse lyrics
    /// Parsea el texto de letras y prepara el motor de lyrics
    /// - Parameter text: Texto crudo (TTML de Apple Music, LRC clásico o híbrido)
    @MainActor
    func parseLyrics(_ text: String) {
        parseToken &+= 1
        let token = parseToken

        // ✅ Camino común (LRC): mismo turno, cero cambios de comportamiento.
        guard text.utf8.count > Self.synchronousParseByteLimit else {
            applyParsedLines(LRCParser.parse(text), token: token)
            return
        }

        // ✅ Payload grande: `hasLyrics` se publica de inmediato (el llamador ya
        //    comprobó que hay texto) para no mostrar un falso "no hay letras" y
        //    para que el contenedor de scroll ya exista cuando lleguen las líneas
        //    (si naciera después, el centrado de abajo se perdería).
        hasLyrics = true

        // ✅ `Task.detached` y no `Task {}`: heredar el MainActor ejecutaría el
        //    parseo en el hilo principal, que es justo lo que se evita.
        Task.detached(priority: .userInitiated) { [weak self] in
            let lines = LRCParser.parse(text)
            await self?.applyParsedLines(lines, token: token, notifyView: true)
        }
    }

    /// ✅ Aplica líneas YA parseadas en el hilo principal: publica el estado, deja
    /// la ventana del wipe lista y recalcula la línea activa con el tiempo real.
    /// - Parameter notifyView: `true` solo cuando las líneas llegan de un parseo en
    ///   background (la vista tiene que repetir su centrado inicial).
    @MainActor
    private func applyParsedLines(_ lines: [LyricsLine], token: Int, notifyView: Bool = false) {
        guard token == parseToken else { return }

        self.lyricsLines = lines
        self.engine = LyricsEngine(lines: lines)
        self.hasLyrics = !lines.isEmpty

        // ✅ Reset estado y primera línea calculada al instante (sin esperar tick)
        activeStartMs = 0
        activeEndMs = 0
        anchorClock(at: audioEngine?.currentTime ?? clockTime)
        refreshActiveLine()

        if notifyView {
            lyricsRevision &+= 1
        }
    }

    // MARK: - Sin lyrics
    /// ✅ Sin letras: limpia líneas/estado y cancela el despertar de boundary
    /// (una canción sin lyrics no debe dejar datos ni despertadores colgando).
    @MainActor
    func clearLyrics() {
        // ✅ Invalida cualquier parseo en background pendiente: sin esto el
        //    resultado de la canción anterior podría publicarse sobre la nueva
        //    (que no tiene letras).
        parseToken &+= 1
        lyricsLines = []
        engine = nil
        hasLyrics = false
        activeID = nil
        activeStartMs = 0
        activeEndMs = 0
        lineBoundaryTask?.cancel()
        lineBoundaryTask = nil
    }

    // MARK: - Control de reproducción
    /// ✅ Compatibilidad con AudioEngine: ya no hay Timer que arrancar ni parar
    /// (la observación del reloj es independiente del ciclo de vida).
    @MainActor
    func startMonitoring() {}

    /// ✅ Compatibilidad con AudioEngine (ver startMonitoring).
    @MainActor
    func stopMonitoring() {}

    /// Recalcula la línea activa inmediatamente después de un seek
    @MainActor
    func handleSeek() {
        syncToCurrentTime()
    }

    /// ✅ Sincroniza el estado con el tiempo REAL de reproducción. Se llama al
    /// ENTRAR en la vista de letras y al cambiar de canción, para que la línea
    /// activa esté calculada antes del primer frame (si el usuario entra en el
    /// minuto 2:30, la vista nace ya centrada en esa línea y no se ve ningún
    /// scroll de arranque).
    @MainActor
    func syncToCurrentTime() {
        guard let audioEngine else { return }
        anchorClock(at: audioEngine.currentTime)
        refreshActiveLine()
    }

    // MARK: - Interpolación entre ticks (la lee la vista en cada frame)
    /// Tiempo de reproducción interpolado.
    /// ✅ El reloj de AudioEngine publica cada 0.4s; aquí extrapolamos el tramo
    /// transcurrido desde el tick (`clockTime` + `clockUpdateDate`) para que el
    /// wipe se dibuje a 60 fps reales. La extrapolación se limita a 1s por si un
    /// tick se retrasa (hilo principal ocupado o app en segundo plano).
    /// ✅ En pausa/seek devuelve la posición congelada, sin extrapolar.
    func interpolatedTime() -> TimeInterval {
        guard isPlaying else { return clockTime }

        let elapsed = CACurrentMediaTime() - clockUpdateDate
        return max(0, clockTime + min(max(elapsed, 0), 1.0))
    }

    /// Progreso (0...1, sin easing) del relleno de UNA FILA de la línea activa.
    /// ✅ O(1): se llama en cada frame SOLO para la línea activa (y solo para las
    /// filas que cambian de progreso), así el resto de la lista no se recalcula.
    /// ✅ Cada fila usa SU ventana temporal, de modo que el wipe avanza fila a
    /// fila (nunca en paralelo) y respeta los silencios entre filas: la fila de
    /// arriba queda completa mientras no llegue el timestamp de la de abajo.
    /// ✅ La ÚLTIMA fila toma el fin EFECTIVO del motor (incluido el buffer
    /// adaptativo), así una línea de una sola fila se rellena exactamente igual
    /// que antes de existir las filas visuales.
    func fillProgress(forLineID id: Int, row: LyricVisualRow, isLastRow: Bool) -> Double {
        guard id == activeID, activeEndMs > activeStartMs else { return 0 }

        let startMs = Double(row.startMs)
        let endMs = Double(isLastRow ? max(activeEndMs, row.endMs) : row.endMs)
        guard endMs > startMs else { return 1 }

        let timeMs = interpolatedTime() * 1000
        let clampedMs = min(max(timeMs, startMs), endMs)
        return (clampedMs - startMs) / (endMs - startMs)
    }

    /// Progreso (0...1) de una fila guiado por TIMINGS DE PALABRA (karaoke).
    /// ✅ Apple Music no adelanta las palabras que aún no han sonado: cada palabra
    /// se revela dentro de SU propia ventana y las siguientes quedan apagadas
    /// hasta que les toca. Dentro de la palabra el barrido es continuo, así que el
    /// borde avanza a 60 fps pero gobernado por la voz real (un reparto lineal por
    /// caracteres se desincroniza en cuanto una palabra es más larga que otra).
    /// ✅ O(nº de palabras de la fila) y sin allocations: se llama una vez por
    /// frame y solo para la fila que está cambiando de progreso.
    /// - Parameters:
    ///   - fractions: fracción de ancho acumulada al final de cada palabra (la
    ///     última vale 1), calculada y cacheada en la vista con la fuente real.
    /// - Returns: nil si la fila no tiene timings utilizables → el llamador debe
    ///   usar el relleno lineal por fila (`fillProgress`).
    func wordFillProgress(
        forLineID id: Int,
        row: LyricVisualRow,
        fractions: [Double],
        isLastRow: Bool
    ) -> Double? {
        guard id == activeID, activeEndMs > activeStartMs else { return nil }

        let words = row.words
        guard !words.isEmpty,
              fractions.count == words.count,
              let lastFraction = fractions.last,
              lastFraction > 0 else { return nil }

        let endMs = Double(isLastRow ? max(activeEndMs, row.endMs) : row.endMs)
        let timeMs = min(max(interpolatedTime() * 1000, Double(row.startMs)), endMs)

        var revealed = 0.0
        for index in words.indices {
            let upper = fractions[index]
            let startMs = Double(words[index].startMs)
            var finishMs = Double(max(words[index].endMs, words[index].startMs))
            // ✅ La última palabra de la última fila se cierra con el fin EFECTIVO
            // de la línea (el buffer adaptativo del motor), igual que el relleno
            // lineal: la línea no se queda a medias mientras sigue sonando.
            if isLastRow, index == words.count - 1 {
                finishMs = max(finishMs, endMs)
            }

            // Todavía no ha empezado: lo que queda por delante permanece apagado.
            if timeMs < startMs { return revealed }

            let duration = finishMs - startMs
            let local = duration > 0 ? min((timeMs - startMs) / duration, 1) : 1
            if local < 1 { return revealed + (upper - revealed) * local }
            revealed = upper
        }

        return revealed
    }

    // MARK: - Reloj interno
    /// ✅ Nuevo tick del reloj: fija el ancla de interpolación y recalcula línea.
    private func receiveClockTime(_ time: TimeInterval) {
        clockTime = time
        clockUpdateDate = CACurrentMediaTime()
        refreshActiveLine()
    }

    /// Re-ancla la interpolación en un instante conocido (parseo/seek).
    private func anchorClock(at time: TimeInterval) {
        clockTime = max(0, time)
        clockUpdateDate = CACurrentMediaTime()
    }

    /// ✅ Espejo del estado de reproducción (llega por "PlaybackStateChanged").
    private func syncPlaybackState() {
        let playing = audioEngine?.isPlaying ?? false
        guard playing != isPlaying else { return }

        isPlaying = playing
        refreshActiveLine()
    }

    // MARK: - Línea activa
    /// Recalcula la línea resaltada y rearma el despertar del próximo boundary.
    /// ✅ Solo publica `activeID` si cambió → cero re-renders por tick.
    /// ✅ Durante los huecos mantiene la última línea empezada (no atenúa todo).
    private func refreshActiveLine() {
        guard let engine = engine else { return }

        let timeMs = interpolatedMs()
        let index = engine.activeIndex(at: timeMs) ?? engine.lastStartedIndex(at: timeMs)

        updateActiveWindow(index: index, engine: engine)
        if index != activeID {
            activeID = index
        }

        scheduleLineBoundaryWake()
    }

    /// ✅ Cachea inicio + fin efectivo de la línea activa: el wipe los lee en
    /// cada frame sin volver a buscar en el motor.
    private func updateActiveWindow(index: Int?, engine: LyricsEngine) {
        guard let index = index, let window = engine.window(for: index) else {
            activeStartMs = 0
            activeEndMs = 0
            return
        }

        activeStartMs = window.startMs
        activeEndMs = window.endMs
    }

    private func interpolatedMs() -> Int {
        return Int((interpolatedTime() * 1000).rounded())
    }

    // MARK: - Cambio de línea exacto (sin Timer)
    /// ✅ El reloj publica cada 0.4s: aquí dormimos hasta el próximo inicio de
    /// línea y actualizamos entonces (error de ~ms en vez de hasta 400ms).
    /// Si el boundary queda lejos no se duerme: el siguiente tick del reloj
    /// (0.4s) vuelve a evaluar con un delay ya corto.
    private func scheduleLineBoundaryWake() {
        lineBoundaryTask?.cancel()
        lineBoundaryTask = nil

        guard isPlaying, let engine = engine else { return }

        let timeMs = interpolatedMs()
        guard let boundaryMs = engine.nextStartMs(afterMs: timeMs) else { return }

        let delayMs = boundaryMs - timeMs
        guard delayMs > 0, delayMs <= 1200 else { return }

        lineBoundaryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.handleLineBoundary()
        }
    }

    /// ✅ Despertó el boundary: recalcula la línea activa (y rearma el siguiente).
    private func handleLineBoundary() {
        guard isPlaying else { return }
        refreshActiveLine()
    }

    // MARK: - Public helpers
    /// Línea en un índice específico
    func line(at index: Int) -> LyricsLine? {
        return engine?.line(at: index)
    }

    /// Número total de líneas
    var lineCount: Int {
        return lyricsLines.count
    }
}
