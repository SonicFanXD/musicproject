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
    // ✅ SISTEMA DOS COLORES: segundo color de la carátula, el mismo que usan
    // botones, chips, cards y PlayerBar (dominante + secundario reales).
    // Opcional: si llega nil (acento manual o carátula sin secundario) se
    // conserva el degradado de un solo color de siempre, sin romper nada.
    var secondaryTintColor: Color? = nil
    // ✅ Observa el frame rate óptimo según batería/térmica (60↔30fps). Ahora
    // alimenta el `minimumInterval` del TimelineView: no hay CADisplayLink que
    // ajustar, el propio schedule deja de pedir frames.
    @ObservedObject private var frameRate = VisualizerFrameRate.shared
    // ✅ CRÍTICO - BATERÍA: en segundo plano el visualizador se pausa igual que
    // antes lo hacía el CADisplayLink: no se pide ni un frame.
    @Environment(\.scenePhase) private var scenePhase
    // ✅ 24 barras separadas 2.5pt: misma geometría que la versión de HStack.
    private let barCount = 24
    private let barSpacing: CGFloat = 2.5

    var body: some View {
        // ✅ RENDIMIENTO: una sola pasada de dibujo por frame. El TimelineView
        // entrega la fecha al Canvas —sin @State intermedio—, así que ya no hay
        // 24 subvistas SwiftUI ni diff de árbol por frame: ese coste por frame
        // en A11 (no la GPU) era lo que dejaba el visualizador en ~30fps.
        // `paused` sustituye a start/stopVisualization: ni un frame en pausa ni
        // en background, y al volver a primer plano se reanuda solo.
        TimelineView(.animation(minimumInterval: 1.0 / Double(frameRate.fps),
                                paused: !isAnimating)) { timeline in
            Canvas { context, size in
                drawBars(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        // ✅ El shadow se aplica UNA vez al Canvas entero (antes, uno por barra).
        // Sin .drawingGroup(): el Canvas ya se rasteriza solo y envolverlo añadía
        // una pasada offscreen extra sin quitar el coste de SwiftUI, que era el
        // que importaba.
        .shadow(color: tintColor.opacity(0.1), radius: 4, y: 1)
        .opacity(audioEngine.isPlaying ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.3), value: audioEngine.isPlaying)
    }

    /// ✅ Solo animamos reproduciendo y con la app en primer plano.
    private var isAnimating: Bool {
        audioEngine.isPlaying && scenePhase != .background
    }

    /// ✅ Dibuja las 24 barras en UNA pasada (antes: 24 Capsule en un HStack).
    /// La altura de cada barra es una función pura de (tiempo, índice): senos +
    /// un "jitter" determinista — sin `CGFloat.random` por barra y por frame
    /// (eran 24 randoms por frame) y sin estado que fuerce re-render.
    private func drawBars(in context: inout GraphicsContext, size: CGSize, time: Double) {
        guard size.width > 0, size.height > 0 else { return }

        // ✅ FIX DESBORDE (PlayerBar): la versión de HStack se salía del marco de
        // ~18pt. Aquí el ancho se reparte para que las 24 barras quepan enteras;
        // si el contenedor es más estrecho que 24×2.5pt, el Canvas recorta las
        // barras ordenadas de izquierda a derecha, sin salirse nunca del marco.
        let barWidth = max(2.5, (size.width - barSpacing * CGFloat(barCount - 1)) / CGFloat(barCount))
        let gradient = Gradient(colors: barGradientColors)
        // ✅ 0.25 rad/frame a 60fps = 15 rad/s: la misma velocidad que antes,
        // ahora expresada en tiempo real (deja de depender de los fps reales).
        let phase = time * 15.0

        for index in 0..<barCount {
            let position = Double(index)
            let normalizedIndex = position / Double(barCount - 1)

            // Viaje lento + jitter determinista (dos senos incoherentes ≈ ruido
            // barato): mismo rango 0.08...0.28 que el random anterior.
            let travel = sin(phase * 1.1 + position * 0.7) * 0.22
            let jitter = 0.5 + 0.5 * sin(phase * 0.53 + position * 2.1) * cos(phase * 0.31 + position * 1.3)
            let target = min(1.0, max(0.05, 0.35 + travel + (0.08 + 0.20 * jitter) * 0.4))

            // ✅ Onda + realce del centro: idénticos a la versión anterior.
            let wave = sin(phase + position * 0.6) * 0.18
            let centerBoost = 0.15 * (1.0 - pow(normalizedIndex - 0.5, 2) * 4)
            let amplitude = min(1.0, max(0.05, target + wave + centerBoost))

            let barHeight = max(3, CGFloat(amplitude) * size.height)
            let rect = CGRect(
                x: CGFloat(index) * (barWidth + barSpacing),
                y: size.height - barHeight,
                width: barWidth,
                height: barHeight
            )
            // ✅ Capsule = radio completo (mitad del lado menor).
            let barPath = Path(roundedRect: rect, cornerRadius: min(barWidth, barHeight) / 2)
            // ✅ Degradado abajo → arriba por barra, igual que el LinearGradient
            // (.bottom → .top) de la versión anterior.
            context.fill(
                barPath,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: rect.midX, y: rect.maxY),
                    endPoint: CGPoint(x: rect.midX, y: rect.minY)
                )
            )
        }
    }

    /// ✅ Degradado de las barras: DOS colores reales (dominante de la carátula +
    /// su secundario) cuando hay secundario; si no, el degradado de un solo color
    /// con tres paradas que usaba antes. Mismo criterio que `accentPair` del resto
    /// de la app, pero sin tocar la dirección (abajo → arriba) de las barras.
    private var barGradientColors: [Color] {
        if let secondary = secondaryTintColor {
            return [tintColor, secondary]
        }
        return [tintColor.opacity(0.95), tintColor.opacity(0.5), tintColor.opacity(0.2)]
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
    // ✅ SISTEMA DOS COLORES: mismo criterio que `AudioVisualizer`. Opcional: si
    // llega nil se conserva la segunda parada al 40% del acento de siempre.
    var secondaryTintColor: Color? = nil
    // ✅ Batería: mismo controlador de frame rate adaptativo (60↔30fps)
    @ObservedObject private var frameRate = VisualizerFrameRate.shared
    @State private var amplitudes: [CGFloat] = Array(repeating: 0, count: 48)
    @State private var displayLink: CADisplayLink?
    @State private var isVisible = false
    @State private var phase: Double = 0
    // ✅ CRÍTICO - BATERÍA: observar scenePhase para detener en segundo plano
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            ForEach(0..<amplitudes.count, id: \.self) { index in
                let angle = Double(index) / Double(amplitudes.count) * 360
                let height = 8 + amplitudes[index] * 45

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, secondaryTintColor ?? AppTheme.accent.opacity(0.4)],
                            startPoint: .bottom, endPoint: .top
                        )
                    )
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

        amplitudes = amplitudes.map { current in
            let index = amplitudes.firstIndex(of: current) ?? 0
            let travel = sin(phase + Double(index) * 0.4) * 0.3
            let target = min(1.0, max(0.05, 0.25 + travel + CGFloat.random(in: 0.1...0.4) * 0.5))
            return current + (target - current) * 0.6
        }
    }
}