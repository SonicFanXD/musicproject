import Foundation
import Combine
import AVFoundation

// MARK: - ViewModel para lyrics línea por línea
// ✅ Diseñado para iPhone 8 Plus: Timer 10 Hz (cada 100ms) para mínima batería
// ✅ Conecta con AudioEngine existente sin modificar la ruta de audio
// ✅ Detecta cambio de línea eficientemente sin recalcular cada frame
final class LyricsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var activeID: Int? = nil
    @Published var lyricsLines: [LyricsLine] = []
    @Published var hasLyrics: Bool = false
    
    // MARK: - Dependencies
    weak var audioEngine: AudioEngine?
    private var engine: LyricsEngine?
    private var timer: Timer?
    
    // MARK: - Estado interno
    private var lastActiveID: Int? = nil
    private var lastTimeMs: Int = 0
    
    // MARK: - Initialization
    init() {
        // ✅ AudioEngine se conecta después para evitar ciclo de referencia
    }
    
    // MARK: - Conectar audioEngine (llamado por AudioEngine después de init)
    func connectAudioEngine(_ engine: AudioEngine) {
        self.audioEngine = engine
    }
    
    deinit {
        stopTimer()
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
        activeID = nil
        lastActiveID = nil
        lastTimeMs = 0
    }
    
    // MARK: - Control de reproducción
    /// Inicia el timer cuando la reproducción comienza
    @MainActor
    func startMonitoring() {
        stopTimer()
        
        // ✅ Timer 10 Hz (cada 100ms) - suficiente para detectar cambio de línea
        // Para line-by-line, 10 Hz es más que suficiente y ahorra batería
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateActiveLine()
        }
        
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    /// Detiene el timer cuando la reproducción se pausa
    @MainActor
    func stopMonitoring() {
        stopTimer()
    }
    
    /// Recalcula línea activa inmediatamente después de un seek
    @MainActor
    func handleSeek() {
        guard let engine = engine else { return }
        
        let currentTimeMs = Int((audioEngine?.currentTime ?? 0) * 1000)
        let newIndex = engine.seekIndex(at: currentTimeMs)
        
        // ✅ Actualizar inmediatamente sin esperar al timer
        activeID = newIndex
        lastActiveID = newIndex
        lastTimeMs = currentTimeMs
    }
    
    // MARK: - Timer management
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Update logic
    /// Actualiza la línea activa basándose en el tiempo actual
    /// ✅ Solo actualiza el estado cuando cambia la línea activa (no en cada tick)
    private func updateActiveLine() {
        guard let engine = engine,
              let audioEngine = audioEngine else { return }
        
        let currentTimeMs = Int(audioEngine.currentTime * 1000)
        
        // ✅ Optimización: solo procesar si el tiempo cambió significativamente
        guard currentTimeMs != lastTimeMs else { return }
        lastTimeMs = currentTimeMs
        
        let newIndex = engine.activeIndex(at: currentTimeMs)
        
        // ✅ Solo actualizar @Published si cambió el índice (evita re-renders innecesarios)
        if newIndex != lastActiveID {
            activeID = newIndex
            lastActiveID = newIndex
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
