import SwiftUI
import AVFoundation
import QuartzCore
import UIKit

// MARK: - Optimizador de batería para el visualizador
// ✅ Ajusta dinámicamente el frame rate del visualizador según el estado de
// energía/térmico del dispositivo:
//   · 60fps: energía normal y estado térmico nominal (pantalla activa)
//   · 30fps: modo bajo consumo activado, o estado térmico fair/serious/critical
// Cuando la app pasa a segundo plano o la pantalla se apaga, iOS PAUSA el
// CADisplayLink automáticamente (no pide frames), así que no hay que hacer más.
@MainActor
final class VisualizerFrameRate: ObservableObject {
    static let shared = VisualizerFrameRate()
    @Published private(set) var fps: Int = 60

    private init() {
        update()
        // Nota: Foundation no expone una constante Swift para el cambio de
        // estado de energía; el nombre oficial documentado por Apple es
        // "NSProcessInfoPowerStateDidChange".
        NotificationCenter.default.addObserver(
            forName: Notification.Name("NSProcessInfoPowerStateDidChange"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }

    private func update() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            fps = 30
            return
        }
        switch ProcessInfo.processInfo.thermalState {
        case .fair, .serious, .critical:
            fps = 30
        default:
            fps = 60
        }
    }
}

struct AudioVisualizer: View {
    @ObservedObject var audioEngine: AudioEngine
    var tintColor: Color = AppTheme.accent
    /// ✅ Segundo color de la paleta (el de la carátula). Si no hay, el gradiente
    /// se construye con el primario atenuado: nunca queda de un solo tono.
    var secondaryTintColor: Color? = nil
    // ✅ Observa el frame rate óptimo según batería/térmica para adaptarse
    // en tiempo real (60↔30fps) sin reiniciar el CADisplayLink.
    @ObservedObject private var frameRate = VisualizerFrameRate.shared
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.08, count: 24)
    @State private var displayLink: CADisplayLink?
    @State private var phase: Double = 0
    @State private var isVisible = false
    @State private var smoothedAmplitudes: [CGFloat] = Array(repeating: 0.08, count: 24)
    // ✅ CRÍTICO - BATERÍA: observar scenePhase para detener el visualizador
    // cuando la app pasa a segundo plano, incluso si la vista sigue visible
    // (ej. NowPlaying abierto antes de bloquear la pantalla).
    @Environment(\.scenePhase) private var scenePhase
    // ✅ REDUCIR MOVIMIENTO (Ajustes → Apariencia): barras estáticas. No se crea
    // el CADisplayLink, así que no se pide ni un frame por segundo mientras el
    // visualizador está en pantalla: es ahorro real de CPU/GPU, no solo estético.
    @AppStorage("com.aurora.reduceMotion") private var reduceMotion = false

    /// ✅ Gradiente de las barras: se construye UNA vez por render (antes cada
    /// barra creaba el suyo, idéntico, en cada frame) y usa los DOS colores.
    private var barGradient: LinearGradient {
        LinearGradient(
            colors: [
                tintColor.opacity(0.95),
                (secondaryTintColor ?? tintColor).opacity(0.6),
                tintColor.opacity(0.2)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    var body: some View {
        let gradient = barGradient
        GeometryReader { geometry in
            // ✅ FIX DESBORDE: width fijo al contenedor — al usarse en la PlayerBar
            // (contenedor de ~18pt) el HStack intrínseco (~110pt con 24 barras)
            // desbordaba a la derecha y tapaba título/artista/corazón. Con
            // .frame(width:) el HStack se comprime y las barras se recortan
            // ordenadas de izquierda a derecha, sin salirse nunca del marco.
            HStack(spacing: 2.5) {
                ForEach(0..<amplitudes.count, id: \.self) { index in
                    let normalizedIndex = Double(index) / Double(amplitudes.count - 1)
                    let sineWave = sin(phase + Double(index) * 0.6) * 0.18
                    let centerBoost = 0.15 * (1.0 - pow(normalizedIndex - 0.5, 2) * 4)
                    let adjustedAmplitude = max(0.05, min(1.0, smoothedAmplitudes[index] + CGFloat(sineWave) + CGFloat(centerBoost)))

                    Capsule()
                        .fill(gradient)
                        .frame(width: max(2.5, geometry.size.width / CGFloat(amplitudes.count) - 2))
                        .frame(height: max(3, adjustedAmplitude * geometry.size.height))
                }
            }
            .frame(height: geometry.size.height, alignment: .bottom)
            .frame(width: geometry.size.width, alignment: .leading)
            .shadow(color: tintColor.opacity(0.1), radius: 4, y: 1)
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
        // ✅ Aplicar "reducir movimiento" al instante si el usuario lo toca con el
        // visualizador en pantalla (startVisualization ya se encarga de parar el
        // anterior y de congelarlo o reanudarlo).
        .onChange(of: reduceMotion) { _ in
            startVisualization()
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
        // ✅ Batería: adapta los fps en tiempo real (60↔30) al cambiar el estado
        // de bajo consumo/térmico, sin reiniciar el CADisplayLink.
        .onReceive(frameRate.$fps) { fps in
            displayLink?.preferredFramesPerSecond = fps
        }
        // ✅ CRÍTICO - BATERÍA: detener el visualizador cuando la app pasa a
        // segundo plano para ahorrar CPU/GPU. Reanudar al volver a primer plano.
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                stopVisualization()
                isVisible = false
            } else if newPhase == .active && audioEngine.isPlaying {
                isVisible = true
                startVisualization()
            }
        }
    }

    /// ✅ Perfil fijo (campana suave) para el modo de movimiento reducido: se lee
    /// como un visualizador "congelado", no como barras planas. `fileprivate`
    /// porque el anillo (`CircularAudioVisualizer`) usa el mismo perfil.
    fileprivate static func staticProfile(count: Int) -> [CGFloat] {
        (0..<count).map { index in
            let t = Double(index) / Double(max(count - 1, 1))
            return CGFloat(0.18 + 0.34 * (1 - pow(t * 2 - 1, 2)))
        }
    }

    private func startVisualization() {
        stopVisualization()

        // ✅ REDUCIR MOVIMIENTO: barras estáticas y SIN display link (ni un frame).
        if reduceMotion {
            let profile = Self.staticProfile(count: smoothedAmplitudes.count)
            smoothedAmplitudes = profile
            amplitudes = profile
            return
        }

        displayLink = CADisplayLink(target: VisualizerLinkTarget { [self] in
            updateAmplitudes()
        }, selector: #selector(VisualizerLinkTarget.fire(displayLink:)))
        // ✅ Batería: usar el frame rate adaptativo (60fps normal, 30fps en
        // bajo consumo o calor)
        displayLink?.preferredFramesPerSecond = frameRate.fps
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopVisualization() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateAmplitudes() {
        guard isVisible, audioEngine.isPlaying else { return }

        phase += 0.25

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

/// Wrapper para CADisplayLink (retención segura del selector)
final class VisualizerLinkTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func fire(displayLink: CADisplayLink) {
        handler()
    }
}

// MARK: - Visualizador Circular (optimizado)
struct CircularAudioVisualizer: View {
    @ObservedObject var audioEngine: AudioEngine
    /// ✅ Misma paleta que la barra: antes usaba `AppTheme.accent` hardcodeado, así
    /// que ignoraba el acento de portada y el modo manual.
    var tintColor: Color = AppTheme.accent
    var secondaryTintColor: Color? = nil
    // ✅ Batería: mismo controlador de frame rate adaptativo (60↔30fps)
    @ObservedObject private var frameRate = VisualizerFrameRate.shared
    @State private var amplitudes: [CGFloat] = Array(repeating: 0, count: 48)
    @State private var displayLink: CADisplayLink?
    @State private var isVisible = false
    @State private var phase: Double = 0
    // ✅ CRÍTICO - BATERÍA: observar scenePhase para detener en segundo plano
    @Environment(\.scenePhase) private var scenePhase
    // ✅ REDUCIR MOVIMIENTO: mismo criterio que el visualizador de barras — sin
    // CADisplayLink, el anillo queda con un perfil fijo y no consume frames.
    @AppStorage("com.aurora.reduceMotion") private var reduceMotion = false

    var body: some View {
        // ✅ Un solo gradiente por render (y de dos colores).
        let gradient = LinearGradient(
            colors: [tintColor, (secondaryTintColor ?? tintColor).opacity(0.4)],
            startPoint: .bottom,
            endPoint: .top
        )
        ZStack {
            ForEach(0..<amplitudes.count, id: \.self) { index in
                let angle = Double(index) / Double(amplitudes.count) * 360
                let height = 8 + amplitudes[index] * 45

                Capsule()
                    .fill(gradient)
                    .frame(width: 2.5, height: height)
                    .offset(y: -height / 2 - 35)
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
        // ✅ Aplicar "reducir movimiento" al instante si se toca con el anillo en
        // pantalla (startVisualization para el anterior y lo congela o reanuda).
        .onChange(of: reduceMotion) { _ in
            startVisualization()
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
        // ✅ Batería: adapta los fps en tiempo real (60↔30) al cambiar el estado
        // de bajo consumo/térmico, sin reiniciar el CADisplayLink.
        .onReceive(frameRate.$fps) { fps in
            displayLink?.preferredFramesPerSecond = fps
        }
        // ✅ CRÍTICO - BATERÍA: detener el visualizador cuando la app pasa a
        // segundo plano para ahorrar CPU/GPU. Reanudar al volver a primer plano.
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                stopVisualization()
                isVisible = false
            } else if newPhase == .active && audioEngine.isPlaying {
                isVisible = true
                startVisualization()
            }
        }
    }

    private func startVisualization() {
        stopVisualization()

        // ✅ REDUCIR MOVIMIENTO: anillo estático y SIN display link.
        if reduceMotion {
            let profile = AudioVisualizer.staticProfile(count: amplitudes.count)
            amplitudes = profile
            return
        }

        displayLink = CADisplayLink(target: VisualizerLinkTarget { [self] in
            updateCircularAmplitudes()
        }, selector: #selector(VisualizerLinkTarget.fire(displayLink:)))
        // ✅ Batería: usar el frame rate adaptativo (60fps normal, 30fps en
        // bajo consumo o calor)
        displayLink?.preferredFramesPerSecond = frameRate.fps
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopVisualization() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateCircularAmplitudes() {
        guard isVisible, audioEngine.isPlaying else { return }

        phase += 0.15

        // ✅ Antes: `amplitudes.map { amplitudes.firstIndex(of: $0) }` → O(n²) por
        // frame y, con amplitudes repetidas, devolvía el PRIMER índice coincidente:
        // la barra de la posición `index` se dibujaba con el ángulo de otra (bug
        // visual), además de recorrer 48² elementos por frame. `enumerated()` da el
        // índice real en una sola pasada.
        amplitudes = amplitudes.enumerated().map { index, current in
            let travel = sin(phase + Double(index) * 0.4) * 0.3
            let target = min(1.0, max(0.05, 0.25 + travel + CGFloat.random(in: 0.1...0.4) * 0.5))
            return current + (target - current) * 0.6
        }
    }
}