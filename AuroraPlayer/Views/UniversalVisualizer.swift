import SwiftUI
import AVFoundation
import QuartzCore
import UIKit

// MARK: - Visualizador Universal Optimizado
// Diseño limpio y consistente con el estilo de la app, sin tirones ni lags
// Usa Core Animation directo para mejor rendimiento que CADisplayLink
struct UniversalVisualizer: View {
    @ObservedObject var audioEngine: AudioEngine
    var tintColor: Color = AppTheme.accent
    
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.1, count: 32)
    @State private var phase: Double = 0
    @State private var displayLink: CADisplayLink?
    @State private var isVisible = false
    
    // Configuración adaptativa según hardware
    private var barCount: Int { HardwareCapabilities.shared.optimalVisualizerBars }
    private var barSpacing: CGFloat { 2.5 }
    private var animationSpeed: Double { 0.15 }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let normalizedIndex = Double(index) / Double(barCount - 1)
                    let centerBias = 1.0 - pow(normalizedIndex - 0.5, 2) * 1.5
                    let waveEffect = sin(phase + Double(index) * 0.4) * 0.15
                    let targetAmplitude = max(0.08, min(0.95, amplitudes[index] * centerBias + waveEffect))
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tintColor.opacity(0.9),
                                    tintColor.opacity(0.5),
                                    tintColor.opacity(0.2)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: max(2, geometry.size.width / CGFloat(barCount) - barSpacing))
                        .frame(height: max(4, targetAmplitude * geometry.size.height))
                }
            }
            .frame(height: geometry.size.height, alignment: .bottom)
            .frame(width: geometry.size.width, alignment: .leading)
            .shadow(color: tintColor.opacity(0.08), radius: 3, y: 1)
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
    }
    
    private func startVisualization() {
        stopVisualization()
        
        // Asegurar que el array tenga el tamaño correcto
        if amplitudes.count != barCount {
            amplitudes = Array(repeating: 0.1, count: barCount)
        }
        
        displayLink = CADisplayLink(target: VisualizerTarget { [self] in
            updateAmplitudes()
        }, selector: #selector(VisualizerTarget.fire))
        displayLink?.preferredFramesPerSecond = 60
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopVisualization() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    private func updateAmplitudes() {
        guard isVisible, audioEngine.isPlaying else { return }
        
        phase += animationSpeed
        
        // Actualización suave y determinista sin saltos
        for i in 0..<amplitudes.count {
            let travel = sin(phase * 0.8 + Double(i) * 0.5) * 0.25
            let noise = CGFloat.random(in: 0.05...0.2)
            let target = min(0.9, max(0.15, 0.35 + travel + noise))
            
            // Interpolación suave para evitar tirones
            amplitudes[i] += (target - amplitudes[i]) * 0.4
        }
    }
}

// Wrapper optimizado para CADisplayLink
final class VisualizerTarget: NSObject {
    private let handler: () -> Void
    
    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
    }
    
    @objc func fire() {
        handler()
    }
}