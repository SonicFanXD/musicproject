import SwiftUI
import AVFoundation

struct AudioVisualizer: View {
    @ObservedObject var audioEngine: AudioEngine
    var tintColor: Color = Color.accentColor
    // ✅ 30 barras: mejor definición de onda sin sobrecargar A11
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.05, count: 30)
    // ✅ CADisplayLink a 60fps reales (antes Timer de 12.5Hz = 8x menos fluido)
    @State private var displayLink: CADisplayLink?
    @State private var phase: Double = 0
    @State private var isVisible = false
    // ✅ Suavizado por barra (recuerda su valor anterior)
    @State private var smoothedAmplitudes: [CGFloat] = Array(repeating: 0.05, count: 30)
    // ✅ Timestamp acumulado para transiciones de pausa sin saltos
    @State private var lastFireTime: CFTimeInterval = 0

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(0..<amplitudes.count, id: \.self) { index in
                    // ✅ Onda senoidal + centro elevado (movimiento de agua)
                    let sineWave = sin(phase + Double(index) * 0.5) * 0.22
                    let centerBoost = 0.18 * (1 - abs(Double(index - amplitudes.count/2) / Double(amplitudes.count/2)))
                    let adjustedAmplitude = max(0.04, min(1.0, smoothedAmplitudes[index] + CGFloat(sineWave) + CGFloat(centerBoost)))

                    // ✅ Gradiente vertical con color extraído + base brillante
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    tintColor.opacity(0.95),
                                    tintColor.opacity(0.55),
                                    tintColor.opacity(0.25)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: max(3, geometry.size.width / CGFloat(amplitudes.count) - 2.5))
                        .frame(height: max(4, adjustedAmplitude * geometry.size.height))
                        // ✅ Sin .animation individual (CADisplayLink ya interpola 60fps)
                }
            }
            .frame(height: geometry.size.height)
            // ✅ Sombra sutil del conjunto (GPU barata, rasterizada por drawingGroup)
            .shadow(color: tintColor.opacity(0.12), radius: 6, x: 0, y: 2)
        }
        .drawingGroup()
        .opacity(audioEngine.isPlaying ? 1.0 : 0.55)
        .animation(.easeInOut(duration: 0.35), value: audioEngine.isPlaying)
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
                // ✅ Pausa: congelar suavemente sin saltos (las barras quedan
                // en su posición actual, atenuadas)
                stopVisualization()
                isVisible = false
            }
        }
    }

    private func startVisualization() {
        stopVisualization()
        displayLink = CADisplayLink(target: VisualizerLinkTarget { [weak self] in
            self?.updateAmplitudes()
        }, selector: #selector(VisualizerLinkTarget.fire))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopVisualization() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateAmplitudes() {
        guard isVisible, audioEngine.isPlaying else { return }

        // ✅ Onda senoidal con variación orgánica: viaja de izq a derecha
        phase += 0.35

        let baseAmplitude: CGFloat = 0.38
        for i in 0..<smoothedAmplitudes.count {
            // Componente de onda principal (movimiento sincronizado)
            let travel = sin(phase * 1.15 + Double(i) * 0.75) * 0.25
            // Variación aleatoria suave por barra (no es ruido puro)
            let variation = CGFloat.random(in: 0.10...0.35)
            let target = min(1.0, max(0.06, baseAmplitude + CGFloat(travel) + variation * 0.45))

            // ✅ Interpolación suave hacia el objetivo (60fps = imperceptible)
            smoothedAmplitudes[i] += (target - smoothedAmplitudes[i]) * 0.75
        }
        amplitudes = smoothedAmplitudes
    }
}

/// Wrapper para CADisplayLink con closure (evita retain cycle con @StateObject)
class VisualizerLinkTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func fire() {
        handler()
    }
}

// MARK: - Visualizador Circular
struct CircularAudioVisualizer: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var amplitudes: [CGFloat] = Array(repeating: 0, count: 48)
    @State private var displayLink: CADisplayLink?
    @State private var isVisible = false

    var body: some View {
        ZStack {
            ForEach(0..<amplitudes.count, id: \.self) { index in
                let angle = Double(index) / Double(amplitudes.count) * 360
                let height = amplitudes[index] * 50

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: 3, height: height)
                    .offset(y: -height / 2)
                    .rotationEffect(.degrees(angle))
            }
        }
        .frame(width: 120, height: 120)
        .drawingGroup()
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
    }

    private func startVisualization() {
        stopVisualization()
        displayLink = CADisplayLink(target: CircularLinkTarget { [weak self] in
            self?.updateAmplitudes()
        }, selector: #selector(CircularLinkTarget.fire))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopVisualization() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateAmplitudes() {
        guard isVisible, audioEngine.isPlaying else { return }

        let baseAmplitude: CGFloat = 0.12
        let randomVariation: CGFloat = CGFloat.random(in: 0.15...0.45)

        amplitudes = amplitudes.map { current in
            let variation = CGFloat.random(in: 0.3...0.9)
            let target = min(1.0, baseAmplitude + (variation * randomVariation))
            // ✅ Suavizado: se acerca al 70% del objetivo cada frame
            return current + (target - current) * 0.7
        }
    }
}

/// Wrapper para CADisplayLink circular
class CircularLinkTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func fire() {
        handler()
    }
}