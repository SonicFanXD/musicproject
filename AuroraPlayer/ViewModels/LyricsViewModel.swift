import Foundation
import Combine
import AVFoundation
import QuartzCore

// ✅ Importar AppLog para logs de diagnóstico
// La app usa AppLog en lugar de print() para logging persistente

// MARK: - ViewModel para lyrics línea por línea (SpotiFLAC-style animation)
// ✅ Diseñado para iPhone 8 Plus: CADisplayLink a 60 Hz para animación fluida
// ✅ Interpolación de tiempo para relleno progresivo de izquierda a derecha
// ✅ Conecta con AudioEngine existente sin modificar la ruta de audio
final class LyricsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var activeLineID: Int? = nil
    @Published var progress: Double = 0.0  // 0.0 a 1.0 para la línea activa
    @Published var clockUpdateDate: TimeInterval = CACurrentMediaTime()  // ✅ Ancla de tiempo para interpolación
    @Published var clockTime: TimeInterval = 0.0  // ✅ Tiempo actual del reloj de audio
    @Published var lyricsLines: [LyricsLine] = []
    @Published var hasLyrics: Bool = false
    
    // MARK: - Dependencies
    weak var audioEngine: AudioEngine?
    private var engine: LyricsEngine?
    private var lyricsTimer: Timer?  // ✅ Timer 0.1s para updates (reemplaza CADisplayLink)
    private var clockCancellable: AnyCancellable?  // ✅ Para observar clock.time de AudioEngine
    
    // MARK: - Estado interno para interpolación
    private var lastUpdateTime: CFTimeInterval = 0
    private var lastAudioTime: TimeInterval = 0
    private var currentInterpolatedTime: TimeInterval = 0
    private var lastProcessedTimeMs: Int = -1  // ✅ Guarda para evitar procesamiento duplicado
    
    // MARK: - Initialization
    init() {
        // ✅ AudioEngine se conecta después para evitar ciclo de referencia
    }
    
    // MARK: - Conectar audioEngine (llamado por AudioEngine después de init)
    func connectAudioEngine(_ engine: AudioEngine) {
        self.audioEngine = engine
        
        // ✅ Observar clock.time de AudioEngine para interpolación fluida
        clockCancellable = engine.clock.$time.sink { [weak self] newTime in
            Task { @MainActor in
                self?.clockTime = newTime
            }
        }
        
        // ✅ Inicializar clockTime con el valor actual
        clockTime = engine.clock.time
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Parse lyrics
    /// Parsea texto LRC y prepara el motor de lyrics
    /// - Parameter text: Texto LRC crudo (formato clásico o híbrido)
    @MainActor
    func parseLyrics(_ text: String) {
        let lines = LRCParser.parse(text)
        self.lyricsLines = lines
        self.engine = LyricsEngine(lines: lines)
        self.hasLyrics = !lines.isEmpty
        
        // ✅ Reset estado
        activeLineID = nil
        progress = 0.0
        lastUpdateTime = 0
        lastAudioTime = 0
        currentInterpolatedTime = 0
    }
    
    // MARK: - Control de reproducción
    /// Inicia Timer 0.1s para updates de lyrics
    @MainActor
    func startMonitoring() {
        stopMonitoring()
        
        // ✅ Timer 0.1s para updates (CADisplayLink a 60 Hz era desperdicio)
        lyricsTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let audioEngine = self.audioEngine else { return }
            let currentTimeMs = Int(audioEngine.currentTime * 1000)
            guard currentTimeMs != self.lastProcessedTimeMs else { return }
            self.lastProcessedTimeMs = currentTimeMs
            Task { @MainActor in
                self.updateState(at: currentTimeMs)
            }
        }
    }
    
    /// Detiene Timer cuando la reproducción se pausa
    @MainActor
    func stopMonitoring() {
        lyricsTimer?.invalidate()
        lyricsTimer = nil
        lastProcessedTimeMs = -1
    }
    
    /// Recalcula línea activa inmediatamente después de un seek
    @MainActor
    func handleSeek() {
        guard let engine = engine else { return }
        
        let currentTimeMs = Int((audioEngine?.currentTime ?? 0) * 1000)
        _ = engine.seekIndex(at: currentTimeMs)
        
        // ✅ Actualizar inmediatamente sin esperar al siguiente frame
        updateState(at: currentTimeMs)
    }
    
    // MARK: - Update logic con interpolación
    /// Actualiza el estado en cada frame (60 Hz) para animación fluida
    @MainActor
    private func updateState(at timeMs: Int) {
        guard let engine = engine else { return }
        
        let currentTime = TimeInterval(timeMs) / 1000.0
        
        // ✅ Calcular línea activa y progress
        let newIndex = engine.activeIndex(at: timeMs)
        
        // ✅ DEBUG: Log de diagnóstico
        AppLog.debug(.lyrics, "timeMs=\(timeMs) — newIndex=\(String(describing: newIndex)) — lineIDs=\(engine.allLineIDs())")
        
        if let newIndex = newIndex, let line = engine.line(at: newIndex) {
            // ✅ Calcular progress para la línea activa
            let lineStart = TimeInterval(line.startMs) / 1000.0
            let lineEnd = TimeInterval(line.endMs) / 1000.0
            let lineDuration = lineEnd - lineStart
            
            let progress: Double
            if lineDuration > 0 {
                let lineProgress = (currentTime - lineStart) / lineDuration
                progress = max(0.0, min(1.0, lineProgress))
            } else {
                progress = 1.0
            }
            
            // ✅ DEBUG: Log de asignación
            AppLog.debug(.lyrics, "Asignando activeLineID=\(newIndex) — progress=\(progress)")
            
            activeLineID = newIndex
            self.progress = progress
            // ✅ Actualizar ancla de tiempo para interpolación en vista
            clockUpdateDate = CACurrentMediaTime()
        } else {
            // ✅ Gap o silencio: no línea activa, progress = 0
            // ✅ DEBUG: Log de gap
            AppLog.debug(.lyrics, "Gap/silencio: activeLineID=nil")
            activeLineID = nil
            progress = 0.0
        }
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
