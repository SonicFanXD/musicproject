import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// AURORA WAVY PROGRESS — versión simple y estable.
//
// · Pista completa en gris (`Capsule`, 4 pt).
// · Parte activa: UNA línea sinusoidal (`Path` + `stroke` de 4 pt) que llega
//   hasta `width * progress`. La fase sale de `TimelineView` a una longitud de
//   onda por segundo; al pausar, el TimelineView se pausa y la amplitud es 0.
// · Thumb: un círculo simple posicionado exactamente en `width * progress`.
// · El gesto vive aquí: arrastre con `onScrub`, seek único en `onScrubEnd` y
//   toque sin desplazamiento con `onTap`. El Canvas no recibe toques.
// · Sin `repeatForever`, sin gradientes por frame y sin estados de aplanado
//   complejos: menos trabajo por frame en el A11.
// ══════════════════════════════════════════════════════════════════════════

struct AuroraWavyProgress: View {
    let progress: Double
    let isPlaying: Bool
    let isScrubbing: Bool

    var onScrub: ((Double) -> Void)? = nil
    var onScrubEnd: ((Double) -> Void)? = nil
    var onTap: (() -> Void)? = nil

    var thickness: CGFloat = 4
    var amplitude: CGFloat = 3.2
    var waveLength: CGFloat = 24
    var trackColor: Color = M3EColor.outlineVariant.opacity(0.55)
    var colors: [Color] = [M3EColor.primary, M3EColor.primary]
    var showsThumb: Bool = true
    var thumbSize: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var dragPreview: Double? = nil
    @State private var dragStarted = false
    @State private var dragMoved = false

    private var activeColor: Color {
        colors.first ?? M3EColor.primary
    }

    private var displayedProgress: CGFloat {
        let value = dragPreview ?? progress
        guard value.isFinite else { return 0 }
        return min(max(CGFloat(value), 0), 1)
    }

    private var isInteracting: Bool {
        isScrubbing || dragStarted || dragPreview != nil
    }

    /// La onda también vive mientras el usuario arrastra, aunque la pista esté
    /// en pausa: el scrub se siente vivo y no como una barra estática.
    private var waveActive: Bool {
        (isPlaying || isInteracting) && scenePhase == .active && !reduceMotion
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let midY = height / 2
            let activeWidth = width * displayedProgress

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(trackColor)
                    .frame(width: width, height: thickness)

                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !waveActive)) { timeline in
                    Canvas { context, _ in
                        guard activeWidth > 0.5 else { return }

                        let seconds = timeline.date.timeIntervalSinceReferenceDate
                        // Al arrastrar la onda acelera y gana amplitud; al
                        // soltar vuelve a su ritmo normal.
                        let speed: CGFloat = isInteracting ? 1.65 : 1.0
                        let phase = CGFloat(seconds.truncatingRemainder(dividingBy: 1_000)) * (2 * .pi) * speed
                        let currentWaveLength = isInteracting ? max(waveLength * 0.65, 8) : waveLength
                        let frequency = 2 * CGFloat.pi / max(currentWaveLength, 1)
                        let amplitudeFactor = isInteracting ? 1.75 : max(displayedProgress, 0.25)
                        let waveAmplitude = waveActive ? amplitude * amplitudeFactor : 0

                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: midY + sin(phase) * waveAmplitude))

                        var x: CGFloat = 0
                        while x <= activeWidth {
                            let y = midY + sin(x * frequency + phase) * waveAmplitude
                            path.addLine(to: CGPoint(x: x, y: y))
                            x += 2
                        }

                        context.stroke(
                            path,
                            with: .color(activeColor),
                            style: StrokeStyle(
                                lineWidth: thickness,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }
                .frame(width: width, height: height)
                .allowsHitTesting(false)

                if showsThumb {
                    Circle()
                        .fill(activeColor)
                        .overlay(
                            Circle().strokeBorder(M3EColor.surface, lineWidth: 2)
                        )
                        .frame(width: thumbSize, height: thumbSize)
                        .scaleEffect(isDragging ? 1.25 : 1.0)
                        .animation(AuroraMotion.spatialFast, value: isDragging)
                        .position(x: activeWidth, y: midY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height)
            // Hit target 8 pt más alto/abajo que la barra visual.
            .contentShape(Rectangle().inset(by: -8))
            .gesture(dragGesture(width: width))
        }
        .frame(maxWidth: .infinity, minHeight: 16)
    }

    private var isDragging: Bool {
        isScrubbing || dragPreview != nil
    }

    /// Arrastre con distinción toque/scrub: menos de 4 pt es un toque (no hace
    /// seek y dispara `onTap`); a partir de ahí el thumb sigue al dedo y se
    /// hace un único seek al soltar.
    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !dragStarted {
                    dragStarted = true
                    dragMoved = false
                    dragPreview = Double(displayedProgress)
                    Haptics.selection()
                }

                let distance = (value.translation.width * value.translation.width
                    + value.translation.height * value.translation.height).squareRoot()
                guard distance > 4, width > 0 else { return }
                dragMoved = true

                let newProgress = min(max(value.location.x / width, 0), 1)
                dragPreview = Double(newProgress)
                onScrub?(Double(newProgress))
            }
            .onEnded { value in
                let finalProgress: Double
                if dragMoved, width > 0 {
                    finalProgress = Double(min(max(value.location.x / width, 0), 1))
                } else {
                    finalProgress = Double(displayedProgress)
                }

                if dragMoved {
                    Haptics.light()
                    if let onScrubEnd {
                        onScrubEnd(finalProgress)
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
