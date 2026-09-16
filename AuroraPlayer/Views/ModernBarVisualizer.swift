import SwiftUI

/// Visualizador de barras modernas con efectos premium
/// Barras individuales con gradientes y sombras que mantienen la identidad visual
struct ModernBarVisualizer: View {
    @ObservedObject var audioEngine: AudioEngine
    var tintColor: Color
    @ObservedObject private var frameRate = VisualizerFrameRate.shared
    
    // ✅ OPTIMIZACIÓN A11: número de barras adaptativo según hardware
    private var barCount: Int { HardwareCapabilities.shared.optimalVisualizerBars }
    
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.08, count: 24)
    @State private var displayLink: CADisplayLink?
    @State private var isVisible = false
    @State private var smoothedAmplitudes: [CGFloat] = Array(repeating: 0.08, count: 24)
    @State private var phase: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { index in
                    let normalizedIndex = Double(index) / Double(barCount - 1)
                    let centerBoost = 1.0 + 0.5 * (1.0 - pow(normalizedIndex - 0.5, 2) * 4)
                    let adjustedAmplitude = max(0.08, min(1.0, smoothedAmplitudes[index] * centerBoost))
                    
                    // ✅ Barra con gradiente y sombra elegante
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tintColor.opacity(0.95),
                                    tintColor.opacity(0.7),
                                    tintColor.opacity(0.4)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: max(3, geometry.size.width / CGFloat(barCount) - 5))
                        .frame(height: max(4, adjustedAmplitude * geometry.size.height))
                        .shadow(color: tintColor.opacity(0.3), radius: 4, y: 2)
                        .overlay(
                            // ✅ Reflejo sutil en la parte superior
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.4),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: adjustedAmplitude * geometry.size.height * 0.3)
                        )
                }
            }
            .frame(height: geometry.size.height, alignment: .bottom)
        }
        .drawingGroup()
        .opacity(audioEngine.isPlaying ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.3), value: audioEngine.isPlaying)
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
    
    private func startVisualization() {
        guard displayLink == nil else { return }
        
        displayLink = CADisplayLink(target: SimpleDisplayLinkTarget { [self] in
            updateAmplitudes()
        }, selector: #selector(SimpleDisplayLinkTarget.fire(displayLink:)))
        displayLink?.add(to: .main, forMode: .common)
        displayLink?.preferredFramesPerSecond = frameRate.fps
    }
    
    private func stopVisualization() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    private func updateAmplitudes() {
        guard isVisible, audioEngine.isPlaying else { return }
        
        phase += 0.25
        
        // ✅ OPTIMIZACIÓN: solo redimensionar si realmente es necesario (no en cada frame)
        if amplitudes.count != barCount {
            amplitudes = Array(repeating: 0.08, count: barCount)
        }
        if smoothedAmplitudes.count != barCount {
            smoothedAmplitudes = Array(repeating: 0.08, count: barCount)
        }
        
        let baseAmplitude: CGFloat = 0.35
        for i in 0..<smoothedAmplitudes.count {
            let travel = sin(phase * 1.1 + Double(i) * 0.7) * 0.22
            let variation = CGFloat.random(in: 0.08...0.28)
            let target = min(1.0, max(0.05, baseAmplitude + CGFloat(travel) + variation * 0.4))
            
            smoothedAmplitudes[i] += (target - smoothedAmplitudes[i]) * 0.65
        }
        amplitudes = smoothedAmplitudes
    }
}