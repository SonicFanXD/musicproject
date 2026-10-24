import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// AURORA WAVY PROGRESS — LinearWavyProgressIndicator de M3E.
//
// · PISTA: `Capsule` de SwiftUI fuera del Canvas (siempre visible).
// · ONDA: `Path` sinusoidal real, `y = midY + sin(x·f + fase)·amplitud`,
//   dibujado solo hasta `width · progress`. La fase avanza a UNA longitud de
//   onda por segundo (`2π rad/s`) con la fecha de `TimelineView`.
// · La AMPLITUD es proporcional al progreso y se aplana al pausar con una
//   caída exponencial acotada (~0.4 s). Al terminar, el TimelineView se
//   pausa: no queda ninguna transacción viva ni `repeatForever`.
// · El GESTO vive aquí: arrastre con `onScrub`, seek único con `onScrubEnd`
//   y `onTap` para el toque sin desplazamiento. Canvas y thumb no reciben
//   toques; el hit target se amplía 8 pt arriba/abajo.
// · El thumb escala con `spatialFast` y dispara hápticos al empezar/soltar.
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
    var amplitude: CGFloat = 3.2
    var waveLength: CGFloat = 24
    var trackColor: Color = M3EColor.outlineVariant.opacity(0.55)
    var colors: [Color] = [AppTheme.accent, AppTheme.accent.opacity(0.55)]
    var showsThumb: Bool = true
    var thumbSize: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Progreso local durante el arrastre: el thumb sigue al dedo al instante.
    @State private var dragPreview: Double? = nil
    @State private var dragStarted = false
    @State private var dragMoved = false

    /// Aplanado acotado tras pausar (no hay animación infinita).
    @State private var flattenStart: Date? = nil
    @State private var isFlattening = false

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

    private var isActive: Bool {
        guard !reduceMotion, scenePhase == .active else { return false }
        return isPlaying || isFlattening
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

                // 2) Onda activa. El TimelineView se pausa al terminar el
                //    aplanado; mientras corre, la fase sale de la fecha.
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isActive)) { timeline in
                    Canvas { context, canvasSize in
                        guard activeWidth > 0.5,
                              canvasSize.width > 0,
                              canvasSize.height > 0 else { return }

                        let mid = canvasSize.height / 2
                        let seconds = timeline.date.timeIntervalSinceReferenceDate
                        // 1 longitud de onda / segundo: 2π rad/s.
                        let phase = CGFloat(seconds.truncatingRemainder(dividingBy: 1_000)) * (2 * .pi)
                        let frequency = 2 * CGFloat.pi / max(waveLength, 1)
                        let amp = currentAmplitude(at: timeline.date)

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
                        .scaleEffect(isDragging ? 1.35 : 1.0)
                        .animation(AuroraMotion.spatialFast, value: isDragging)
                        .shadow(color: .black.opacity(isDragging ? 0.25 : 0.15), radius: 3, x: 0, y: 1)
                        .position(x: activeWidth, y: midY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            // Hit target ampliado 8 pt por arriba y por abajo: la barra mide
            // 16/18 pt, pero el dedo necesita ~34 pt para agarrarla.
            .contentShape(Rectangle().inset(by: -8))
            .gesture(dragGesture(width: size.width))
        }
        .frame(maxWidth: .infinity, minHeight: 16)
        .onChange(of: isPlaying) { playing in
            guard !playing, !reduceMotion else {
                flattenStart = nil
                isFlattening = false
                return
            }
            // Aplanado corto: mantiene el TimelineView vivo solo 0.4 s.
            flattenStart = Date()
            isFlattening = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isFlattening = false
                flattenStart = nil
            }
        }
    }

    /// Amplitud del frame. Proporcional al progreso mientras suena; al pausar
    /// decae exponencialmente desde la última amplitud (sin salto brusco).
    private func currentAmplitude(at date: Date) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let proportional = amplitude * renderedProgress
        if isPlaying {
            return proportional
        }
        guard isFlattening, let start = flattenStart else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(start))
        return proportional * CGFloat(exp(-9.0 * elapsed))
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
                    Haptics.selection()
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
                    Haptics.light()
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
        .background(M3EColor.surface)
    }
}
#endif
