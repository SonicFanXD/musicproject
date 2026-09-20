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
        let lines = LRCParser.parse(text)
        self.lyricsLines = lines
        self.engine = LyricsEngine(lines: lines)
        self.hasLyrics = !lines.isEmpty

        // ✅ Reset estado y primera línea calculada al instante (sin esperar tick)
        activeStartMs = 0
        activeEndMs = 0
        anchorClock(at: audioEngine?.currentTime ?? clockTime)
        refreshActiveLine()
    }

    // MARK: - Sin lyrics
    /// ✅ Sin letras: limpia líneas/estado y cancela el despertar de boundary
    /// (una canción sin lyrics no debe dejar datos ni despertadores colgando).
    @MainActor
    func clearLyrics() {
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
        anchorClock(at: audioEngine?.currentTime ?? clockTime)
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

    /// Progreso (0...1, sin easing) del relleno de la línea indicada.
    /// ✅ O(1) con la ventana cacheada: se llama en cada frame SOLO para la línea
    /// activa, así el resto de la lista no se recalcula.
    func fillProgress(forLineID id: Int) -> Double {
        guard id == activeID, activeEndMs > activeStartMs else { return 0 }

        let timeMs = interpolatedTime() * 1000
        let clampedMs = min(max(timeMs, Double(activeStartMs)), Double(activeEndMs))
        return (clampedMs - Double(activeStartMs)) / Double(activeEndMs - activeStartMs)
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
