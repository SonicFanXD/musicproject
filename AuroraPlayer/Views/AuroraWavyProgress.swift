import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// AURORA WAVY PROGRESS — indicador de progreso ONDULADO de Material 3
// Expressive, nativo en SwiftUI y pensado para el A11 (iPhone 8 Plus).
//
// ✅ FASE 1 (bucle infinito): CERO `repeatForever`. La fase de la onda se
//    calcula con la fecha que entrega `TimelineView(.animation)`; no hay
//    @State que rearmar ni transacción que SwiftUI vuelva a encolar cuando la
//    vista se re-renderiza (barra, sheet, cambio de sección).
// ✅ RENDIMIENTO: el `Path` de la onda se construye UNA sola vez por tamaño,
//    FUERA del cierre por frame. Cada frame solo traslada ese path
//    (`translateBy`) y lo estira en Y para el aplanado (`scaleBy`): son
//    transformaciones del contexto (GPU), no geometría recalculada.
// ✅ AL PAUSAR: la amplitud se aplana con una curva crítica (sin overshoot) y
//    el `TimelineView` se pausa en cuanto termina el aplanado (0,85 s): no
//    queda pidiendo frames ni con la app en segundo plano.
// ✅ El componente NO instala gestos: el arrastre/seek vive en `PlayerBar` y
//    `NowPlayingView`, que necesitan su propio `GeometryReader` y su lógica de
//    haptics/seek. Así no hay gestos duplicados compitiendo por el toque.
// ══════════════════════════════════════════════════════════════════════════

struct AuroraWavyProgress: View {
    let progress: Double
    let isPlaying: Bool
    let isScrubbing: Bool

    /// Se conserva por compatibilidad con las llamadas existentes. El gesto de
    /// arrastre lo gestiona la vista anfitriona (ver comentario de cabecera).
    var onScrub: ((Double) -> Void)? = nil

    // Tokens visuales M3E.
    var thickness: CGFloat = 4
    var amplitude: CGFloat = 2.4
    var waveLength: CGFloat = 22
    var waveSpeed: Double = 26          // puntos por segundo
    var colors: [Color] = [AppTheme.accent, AppTheme.accent.opacity(0.45)]
    var trackColor: Color = Color.secondary.opacity(0.16)
    var thumbColor: Color = Color(UIColor.systemBackground)
    var thumbSize: CGFloat = 12
    var showsThumb: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Ancla del último cambio play/pausa: permite aplanar/desplegar la onda
    /// con una curva exponencial sin `withAnimation` ni estado por frame.
    @State private var animationAnchor = Date()
    /// Mantiene vivos unos frames tras pausar para que el aplanado se vea.
    @State private var isSettling = false

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    private var motionEnabled: Bool {
        !reduceMotion && scenePhase == .active
    }

    private var isAnimating: Bool {
        motionEnabled && (isPlaying || isSettling)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let activeWidth = size.width * clampedProgress

            ZStack(alignment: .leading) {
                // Pista sólida (SurfaceVariant), sin material.
                Capsule(style: .continuous)
                    .fill(trackColor)
                    .frame(height: thickness)

                // Onda activa, recortada al progreso real.
                wave(size: size)
                    .mask(alignment: .leading) {
                        RoundedRectangle(cornerRadius: max(0.5, thickness / 2), style: .continuous)
                            .frame(width: max(0, activeWidth), height: size.height)
                    }

                if showsThumb, size.width > 0 {
                    Circle()
                        .fill(thumbColor)
                        .overlay(
                            Circle().strokeBorder(
                                (colors.first ?? AppTheme.accent).opacity(0.9),
                                lineWidth: 2
                            )
                        )
                        .frame(width: thumbSize, height: thumbSize)
                        .scaleEffect(isScrubbing ? 1.35 : 1.0)
                        .animation(AuroraMotion.spatialFast, value: isScrubbing)
                        .shadow(
                            color: .black.opacity(isScrubbing ? 0.25 : 0.12),
                            radius: isScrubbing ? 5 : 2,
                            x: 0,
                            y: 1
                        )
                        .position(
                            x: min(max(activeWidth, thumbSize / 2), max(thumbSize / 2, size.width - thumbSize / 2)),
                            y: size.height / 2
                        )
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .onChange(of: isPlaying) { playing in
            animationAnchor = Date()
            if playing {
                isSettling = false
            } else {
                isSettling = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    isSettling = false
                }
            }
        }
    }

    // MARK: - Capa de la onda

    @ViewBuilder
    private func wave(size: CGSize) -> some View {
        // ✅ Se construye aquí, FUERA del cierre por frame: solo depende del
        // tamaño. El ancho extra (una longitud de onda) permite trasladar el
        // path sin que aparezca un hueco en el borde derecho.
        let path = Self.wavePath(
            width: size.width + waveLength,
            amplitude: amplitude,
            waveLength: waveLength
        )

        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimating)) { timeline in
            Canvas { context, canvasSize in
                let middle = canvasSize.height / 2
                let elapsed = max(0, timeline.date.timeIntervalSince(animationAnchor))
                let ratio = Self.flattenRatio(expanded: isPlaying, elapsed: elapsed)

                // Fase + aplanado: transformaciones del MISMO path (GPU).
                context.translateBy(x: 0, y: middle)
                context.scaleBy(x: 1, y: max(0.02, ratio))
                context.translateBy(
                    x: -Self.phaseOffset(
                        at: timeline.date,
                        waveLength: waveLength,
                        speed: waveSpeed
                    ),
                    y: 0
                )

                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: colors),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: canvasSize.width, y: 0)
                    ),
                    style: StrokeStyle(
                        lineWidth: thickness,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
    }

    // MARK: - Geometría

    private static func wavePath(width: CGFloat, amplitude: CGFloat, waveLength: CGFloat) -> Path {
        var path = Path()
        let lambda = max(waveLength, 1)
        let span = max(width, 2)
        let steps = max(2, Int(ceil(span / 2)))
        let dx = span / CGFloat(steps)
        let k = 2 * CGFloat.pi / lambda

        path.move(to: CGPoint(x: 0, y: 0))
        for step in 1...steps {
            let x = dx * CGFloat(step)
            path.addLine(to: CGPoint(x: x, y: sin(k * x) * amplitude))
        }
        return path
    }

    /// Desplazamiento periódico de la fase. Se acota al periodo con
    /// `truncatingRemainder` para no perder precisión con la fecha absoluta.
    private static func phaseOffset(at date: Date, waveLength: CGFloat, speed: Double) -> CGFloat {
        let lambda = max(Double(waveLength), 1)
        let cycle = lambda / max(speed, 1)
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        return CGFloat(t) * CGFloat(max(speed, 1))
    }

    /// Curva crítica amortiguada: `base` va de 1 a 0 en ~0.5 s. Desplegar usa
    /// `1 - base` y aplanar usa `base`, así ambos sentidos arrancan sin salto.
    private static func flattenRatio(expanded: Bool, elapsed: TimeInterval) -> CGFloat {
        let k = 9.0
        let base = CGFloat((1 + k * elapsed) * exp(-k * elapsed))
        return expanded ? 1 - base : base
    }
}

// MARK: - Preview (solo para diseño; no se ejecuta en la app)

#if DEBUG
struct AuroraWavyProgress_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 28) {
            AuroraWavyProgress(progress: 0.42, isPlaying: true, isScrubbing: false)
                .frame(height: 18)
            AuroraWavyProgress(progress: 0.68, isPlaying: true, isScrubbing: true)
                .frame(height: 18)
            AuroraWavyProgress(progress: 0.2, isPlaying: false, isScrubbing: false)
                .frame(height: 16)
        }
        .padding(32)
        .background(Color(UIColor.systemBackground))
    }
}
#endif
