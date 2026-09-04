import SwiftUI
import AVFoundation

struct AudioVisualizer: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var amplitudes: [CGFloat] = Array(repeating: 0, count: 32)
    @State private var animationTimer: Timer?

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<amplitudes.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.8),
                                    Color.accentColor.opacity(0.4)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: geometry.size.width / CGFloat(amplitudes.count) - 2)
                        .frame(height: amplitudes[index] * geometry.size.height)
                        .animation(.easeInOut(duration: 0.1), value: amplitudes[index])
                }
            }
            .frame(height: geometry.size.height)
        }
        .onAppear {
            startVisualization()
        }
        .onDisappear {
            stopVisualization()
        }
        .onChange(of: audioEngine.isPlaying) { isPlaying in
            if isPlaying {
                startVisualization()
            } else {
                stopVisualization()
                resetAmplitudes()
            }
        }
    }

    private func startVisualization() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateAmplitudes()
        }
    }

    private func stopVisualization() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func resetAmplitudes() {
        withAnimation(.easeOut(duration: 0.3)) {
            amplitudes = Array(repeating: 0, count: 32)
        }
    }

    private func updateAmplitudes() {
        guard audioEngine.isPlaying else { return }

        // Simular visualización basada en el estado de reproducción
        // En una implementación real, usaríamos AVAudioEngine.analyzer
        let baseAmplitude: CGFloat = 0.1
        let randomVariation: CGFloat = CGFloat.random(in: 0.05...0.3)

        amplitudes = amplitudes.map { _ in
            let variation = CGFloat.random(in: 0.2...0.8)
            return min(1.0, baseAmplitude + (variation * randomVariation))
        }
    }
}

// MARK: - Visualizador Circular
struct CircularAudioVisualizer: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var amplitudes: [CGFloat] = Array(repeating: 0, count: 64)
    @State private var animationTimer: Timer?

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
                    .animation(.easeInOut(duration: 0.1), value: amplitudes[index])
            }
        }
        .frame(width: 120, height: 120)
        .onAppear {
            startVisualization()
        }
        .onDisappear {
            stopVisualization()
        }
        .onChange(of: audioEngine.isPlaying) { isPlaying in
            if isPlaying {
                startVisualization()
            } else {
                stopVisualization()
                resetAmplitudes()
            }
        }
    }

    private func startVisualization() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateAmplitudes()
        }
    }

    private func stopVisualization() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func resetAmplitudes() {
        withAnimation(.easeOut(duration: 0.3)) {
            amplitudes = Array(repeating: 0, count: 64)
        }
    }

    private func updateAmplitudes() {
        guard audioEngine.isPlaying else { return }

        let baseAmplitude: CGFloat = 0.1
        let randomVariation: CGFloat = CGFloat.random(in: 0.1...0.4)

        amplitudes = amplitudes.map { _ in
            let variation = CGFloat.random(in: 0.3...0.9)
            return min(1.0, baseAmplitude + (variation * randomVariation))
        }
    }
}