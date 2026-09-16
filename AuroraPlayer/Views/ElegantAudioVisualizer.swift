import SwiftUI

/// Visualizador de audio elegante y fluido para NowPlayingView
/// Usa curvas de Bézier suaves con gradientes que siguen la identidad de la app
struct ElegantAudioVisualizer: View {
    @ObservedObject var audioEngine: AudioEngine
    var tintColor: Color
    @ObservedObject private var frameRate = VisualizerFrameRate.shared
    
    // ✅ OPTIMIZACIÓN A11: número de ondas adaptativo según hardware
    private var waveCount: Int { HardwareCapabilities.shared.optimalVisualizerBars }
    
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.5, count: 48)
    @State private var phases: [Double] = Array(repeating: 0, count: 48)
    @State private var displayLink: CADisplayLink?
    @State private var isVisible = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // ✅ Onda principal con gradiente elegante
                waveLayer(
                    geometry: geometry,
                    color: tintColor,
                    opacity: 0.8,
                    amplitude: 1.0,
                    speed: 1.0
                )
                
                // ✅ Onda secundaria con desplazamiento para profundidad
                waveLayer(
                    geometry: geometry,
                    color: tintColor,
                    opacity: 0.4,
                    amplitude: 0.6,
                    speed: 0.7
                )
                
                // ✅ Onda sutil de fondo para volumen
                waveLayer(
                    geometry: geometry,
                    color: tintColor,
                    opacity: 0.2,
                    amplitude: 0.3,
                    speed: 0.4
                )
            }
        }
        .onAppear {
            isVisible = true
            startVisualization()
        }
        .onDisappear {
            isVisible = false
            stopVisualization()
        }
        .onChange(of: audioEngine.isPlaying) { isPlaying in
            if isPlaying {
                isVisible = true
                startVisualization()
            } else {
                isVisible = false
                stopVisualization()
            }
        }
        .onReceive(frameRate.$fps) { fps in
            displayLink?.preferredFramesPerSecond = fps
        }
    }
    
    @ViewBuilder
    private func waveLayer(
        geometry: GeometryProxy,
        color: Color,
        opacity: Double,
        amplitude: CGFloat,
        speed: Double
    ) -> some View {
        Path { path in
            let width = geometry.size.width
            let height = geometry.size.height
            let centerY = height / 2
            
            path.move(to: CGPoint(x: 0, y: centerY))
            
            // ✅ Curva de Bézier suave con múltiples puntos de control
            let step = width / CGFloat(waveCount)
            for i in 0...waveCount {
                let x = CGFloat(i) * step
                let normalizedIndex = CGFloat(i) / CGFloat(waveCount)
                
                // ✅ Amplitud combinada de seno + ruido suave para movimiento orgánico
                let sineComponent = sin(phases[i] * speed + Double(i) * 0.3) * 0.5
                let noiseComponent = amplitudes[i % amplitudes.count] * 0.3
                let envelope = sin(normalizedIndex * .pi) // Envelope suave en los bordes
                
                let y = centerY + (sineComponent + noiseComponent) * envelope * amplitude * (height * 0.35)
                
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    // ✅ Curva cuadrática suave
                    let prevX = CGFloat(i - 1) * step
                    let prevY = centerY + (sin(phases[i - 1] * speed + Double(i - 1) * 0.3) * 0.5 + amplitudes[(i - 1) % amplitudes.count] * 0.3) * envelope * amplitude * (height * 0.35)
                    let controlX = (prevX + x) / 2
                    path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: controlX, y: prevY))
                }
            }
            
            path.addLine(to: CGPoint(x: width, y: centerY))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [
                    color.opacity(opacity),
                    color.opacity(opacity * 0.6),
                    color.opacity(opacity * 0.3),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(audioEngine.isPlaying ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.3), value: audioEngine.isPlaying)
    }
    
    private func startVisualization() {
        guard displayLink == nil else { return }
        
        displayLink = CADisplayLink(target: VisualizerLinkTarget { [self] _ in
            updateWaves()
        }, selector: #selector(VisualizerLinkTarget.fire(displayLink:)))
        displayLink?.add(to: .main, forMode: .common)
        displayLink?.preferredFramesPerSecond = frameRate.fps
    }
    
    private func stopVisualization() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    private func updateWaves() {
        guard isVisible, audioEngine.isPlaying else { return }
        
        // ✅ OPTIMIZACIÓN A11: asegurar tamaño correcto de arrays
        if amplitudes.count != waveCount * 2 {
            amplitudes = Array(repeating: 0.5, count: waveCount * 2)
        }
        if phases.count != waveCount * 2 {
            phases = Array(repeating: 0, count: waveCount * 2)
        }
        
        // ✅ Actualizar fases y amplitudes con movimiento orgánico
        for i in 0..<phases.count {
            phases[i] += 0.015 * (1.0 + Double(i) * 0.02)
            
            // ✅ Amplitud con variación suave basada en tiempo
            let time = Date().timeIntervalSince1970
            let baseAmp = audioEngine.isPlaying ? 0.6 : 0.2
            let variation = sin(time * 2 + Double(i) * 0.5) * 0.2
            amplitudes[i] = baseAmp + variation
        }
    }
}

/// Wrapper para CADisplayLink en SwiftUI
class VisualizerLinkTarget: NSObject {
    private let handler: () -> Void
    
    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
    }
    
    @objc func fire(displayLink: CADisplayLink) {
        handler()
    }
}