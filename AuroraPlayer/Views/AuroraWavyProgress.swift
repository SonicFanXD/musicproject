import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// AURORA WAVY PROGRESS — barra ondulada M3E, INTERACTIVA.
//
// · La PISTA es una `Capsule` de SwiftUI, fuera del Canvas: siempre visible.
// · La ONDA es un `Path` sinusoidal real (`y = midY + sin(...) * amplitude`)
//   dibujado solo hasta `width * progress`, con la fase de TimelineView.
// · El GESTO vive AQUÍ (no en la vista anfitriona): arrastre continuo con
//   `onScrub`, seek único al soltar con `onScrubEnd` y `onTap` para los toques
//   sin desplazamiento (en PlayerBar abre NowPlaying).
// · Canvas y thumb llevan `.allowsHitTesting(false)`: el único hit target es
//   el `contentShape` del contenedor, así el arrastre nunca se pierde.
// · Cero `repeatForever`: al pausar, el TimelineView se pausa.
// ══════════════════════════════════════════════════════════════════════════

struct AuroraWavyProgress: View {
    let progress: Double
    let isPlaying: Bool
    let isScrubbing: Bool

    /// Se llama en cada frame del arrastre con el progreso 0...1.
    var onScrub: ((Double) -> Void)? = nil
    /// Se llama UNA vez al soltar. Si no existe, se reutiliza `onScrub`.
    var onScrubEnd: ((Double) -> Void)? = nil
    /// Toque sin arrastre (p. ej. abrir NowPlaying desde la PlayerBar).
    var onTap: (() -> Void)? = nil

    var thickness: CGFloat = 4
    var amplitude: CGFloat = 2.4
    var waveLength: CGFloat = 24
    var trackColor: Color = Color.secondary.opacity(0.22)
    var colors: [Color] = [AppTheme.accent, AppTheme.accent.opacity(0.5)]
    var showsThumb: Bool = true
    var thumbSize: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    // Progreso local durante el arrastre: el thumb sigue al dedo al instante,
    // sin esperar a que la vista anfitriona publique su preview.
    @State private var dragPreview: Double? = nil
    @State private var dragStarted = false
    @State private var dragMoved = false

    /// Nunca NaN ni fuera de 0...1.
    private var clampedProgress: CGFloat {
        let value = progress.isFinite ? CGFloat(progress) : 0
        return min(max(value, 0), 1)
    }

    private var renderedProgress: CGFloat {
        if let preview = dragPreview, preview.isFinite {
            return min(max(CGFloat(preview), 0), 1)
        }
        return clampedProgress
    }

    private var isAnimating: Bool {
        isPlaying && !reduceMotion && scenePhase == .active
    }

    private var isDragging: Bool {
        isScrubbing || dragPreview != nil
    }

    private var gradientColors: [Color] {
        colors.count >= 2 ? colors : [AppTheme.accent, AppTheme.accent]
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let midY = size.height / 2
            let activeWidth = size.width * renderedProgress

            ZStack(alignment: .leading) {
                // 1) Pista completa.
                Capsule(style: .continuous)
                    .fill(trackColor)
                    .frame(height: thickness)

                // 2) Onda activa.
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimating)) { timeline in
                    Canvas { context, canvasSize in
                        guard activeWidth > 0.5,
                              canvasSize.width > 0,
                              canvasSize.height > 0 else { return }

                        let mid = canvasSize.height / 2
                        let seconds = timeline.date.timeIntervalSinceReferenceDate
                        let phase = CGFloat(seconds.truncatingRemainder(dividingBy: 1_000)) * 4
                        let amp: CGFloat = isAnimating ? amplitude : 0
                        let frequency = 2 * CGFloat.pi / max(waveLength, 1)

                        var wave = Path()
                        wave.move(to: CGPoint(x: 0, y: mid + sin(phase) * amp))

                        var x: CGFloat = 0
                        while x < activeWidth {
                            let y = mid + sin(x * frequency + phase) * amp
                            wave.addLine(to: CGPoint(x: x, y: y))
                            x += 2
                        }
                        let endY = mid + sin(activeWidth * frequency + phase) * amp
                        wave.addLine(to: CGPoint(x: activeWidth, y: endY))

                        context.stroke(
                            wave,
                            with: .linearGradient(
                                Gradient(colors: gradientColors),
                                startPoint: CGPoint(x: 0, y: 0),
                                endPoint: CGPoint(x: max(activeWidth, 1), y: 0)
                            ),
                            style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)

                // 3) Thumb: estrictamente `width * progress`.
                if showsThumb, size.width > 0 {
                    Circle()
                        .fill(gradientColors.first ?? AppTheme.accent)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                        )
                        .frame(width: thumbSize, height: thumbSize)
                        .scaleEffect(isDragging ? 1.3 : 1.0)
                        .animation(AuroraMotion.spatialFast, value: isDragging)
                        .shadow(color: .black.opacity(isScrubbing ? 0.25 : 0.15), radius: 3, x: 0, y: 1)
                        .position(x: activeWidth, y: midY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            // ✅ Hit target ampliado 10 pt por arriba y por abajo: la barra mide
            // 16/18 pt, pero el dedo necesita ~44 pt para agarrarla sin fallar.
            .contentShape(Rectangle().inset(by: -10))
            .gesture(dragGesture(width: size.width))
        }
        .frame(maxWidth: .infinity, minHeight: 16)
    }

    /// Arrastre con distinción toque/scrub: el toque (< 4 pt) no hace seek y
    /// dispara `onTap`; a partir de ahí el thumb sigue al dedo y se hace un
    /// único seek al soltar.
    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !dragStarted {
                    dragStarted = true
                    dragMoved = false
                    dragPreview = Double(clampedProgress)
                }

                let dx = value.translation.width
                let dy = value.translation.height
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance > 4 else { return }
                dragMoved = true

                guard width > 0 else { return }
                let newProgress = min(max(value.location.x / width, 0), 1)
                dragPreview = Double(newProgress)
                onScrub?(Double(newProgress))
            }
            .onEnded { value in
                let finalProgress: Double
                if dragMoved, width > 0 {
                    finalProgress = Double(min(max(value.location.x / width, 0), 1))
                } else {
                    finalProgress = Double(clampedProgress)
                }

                if dragMoved {
                    if let scrubEnd = onScrubEnd {
                        scrubEnd(finalProgress)
                    } else {
                        onScrub?(finalProgress)
                    }
                } else {
                    onTap?()
                }

                dragPreview = nil
                dragStarted = false
                dragMoved = false
            }
    }
}

// MARK: - Preview (solo para diseño; no se ejecuta en la app)

#if DEBUG
struct AuroraWavyProgress_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 28) {
            AuroraWavyProgress(progress: 0.42, isPlaying: true, isScrubbing: false)
                .frame(height: 18)
            AuroraWavyProgress(progress: 0.68, isPlaying: false, isScrubbing: true)
                .frame(height: 18)
            AuroraWavyProgress(progress: 0, isPlaying: false, isScrubbing: false)
                .frame(height: 18)
        }
        .padding(32)
        .background(Color(UIColor.systemBackground))
    }
}
#endif
