import Foundation
import Combine
import AVFoundation
import QuartzCore

// MARK: - ViewModel para lyrics línea por línea (SpotiFLAC-style animation)
// ✅ Diseñado para iPhone 8 Plus: CADisplayLink a 60 Hz para animación fluida
// ✅ Interpolación de tiempo para relleno progresivo de izquierda a derecha
// ✅ Conecta con AudioEngine existente sin modificar la ruta de audio
final class LyricsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var activeLineID: Int? = nil
    @Published var progress: Double = 0.0  // 0.0 a 1.0 para la línea activa
    @Published var lyricsLines: [LyricsLine] = []
    @Published var hasLyrics: Bool = false
    
    // MARK: - Dependencies
    weak var audioEngine: AudioEngine?
    private var engine: LyricsEngine?
    private var displayLink: CADisplayLink?
    
    // MARK: - Estado interno para interpolación
    private var lastUpdateTime: CFTimeInterval = 0
    private var lastAudioTime: TimeInterval = 0
    private var currentInterpolatedTime: TimeInterval = 0
    
    // MARK: - Initialization
    init() {
        // ✅ AudioEngine se conecta después para evitar ciclo de referencia
    }
    
    // MARK: - Conectar audioEngine (llamado por AudioEngine después de init)
    func connectAudioEngine(_ engine: AudioEngine) {
        self.audioEngine = engine
    }
    
    deinit {
        stopDisplayLink()
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
    /// Inicia CADisplayLink a 60 Hz para animación fluida
    @MainActor
    func startMonitoring() {
        stopDisplayLink()
        
        // ✅ CADisplayLink a 60 Hz para animación fluida (SpotiFLAC-style)
        displayLink = CADisplayLink(target: self, selector: #selector(updateFromDisplayLink))
        displayLink?.add(to: .main, forMode: .common)
        displayLink?.isPaused = false
    }
    
    /// Detiene CADisplayLink cuando la reproducción se pausa
    @MainActor
    func stopMonitoring() {
        stopDisplayLink()
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
    
    // MARK: - CADisplayLink callback
    @objc private func updateFromDisplayLink() {
        guard let audioEngine = audioEngine else { return }
        
        let currentTimeMs = Int(audioEngine.currentTime * 1000)
        // ✅ CADisplayLink corre en el run loop principal pero no está marcado como @MainActor
        // Usamos MainActor.assumeIsolated para asegurar thread-safety con Swift 6 concurrency
        MainActor.assumeIsolated {
            updateState(at: currentTimeMs)
        }
    }
    
    // MARK: - Stop display link
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    // MARK: - Update logic con interpolación
    /// Actualiza el estado en cada frame (60 Hz) para animación fluida
    @MainActor
    private func updateState(at timeMs: Int) {
        guard let engine = engine else { return }
        
        let currentTime = TimeInterval(timeMs) / 1000.0
        
        // ✅ Calcular línea activa y progress
        let newIndex = engine.activeIndex(at: timeMs)
        
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
            
            activeLineID = newIndex
            self.progress = progress
        } else {
            // ✅ Gap o silencio: no línea activa, progress = 0
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
