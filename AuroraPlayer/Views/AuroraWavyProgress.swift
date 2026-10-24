import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// AURORA WAVY PROGRESS — barra ondulada M3E.
//
// Implementación mínima y a prueba de fallos:
//  · La PISTA se dibuja SIEMPRE (aunque progress == 0), así la barra nunca
//    puede desaparecer.
//  · La onda activa es un `Path` sinusoidal real:
//        y = midY + sin(x * frequency + phase) * amplitude
//    con la fase tomada de `TimelineView(.animation)`.
//  · El thumb se posiciona con `width * progress` del `GeometryReader`; nunca
//    con `UIScreen.main.bounds`.
//  · Sin `repeatForever`: al pausar, `TimelineView` se pausa y la onda se
//    dibuja plana (amplitud 0) sobre la parte activa.
//  · El gesto de arrastre vive en PlayerBar / NowPlayingView (el componente
//    solo dibuja).
// ══════════════════════════════════════════════════════════════════════════

struct AuroraWavyProgress: View {
    let progress: Double
    let isPlaying: Bool
    let isScrubbing: Bool

    /// Se conserva por compatibilidad con las llamadas existentes. El gesto lo
    /// gestiona la vista anfitriona.
    var onScrub: ((Double) -> Void)? = nil

    var thickness: CGFloat = 4
    var amplitude: CGFloat = 2.4
    var waveLength: CGFloat = 24
    var trackColor: Color = Color.secondary.opacity(0.22)
    var colors: [Color] = [AppTheme.accent, AppTheme.accent.opacity(0.5)]
    var showsThumb: Bool = true
    var thumbSize: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    private var isAnimating: Bool {
        isPlaying && !reduceMotion && scenePhase == .active
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let midY = size.height / 2
            let activeWidth = size.width * clampedProgress

            ZStack(alignment: .leading) {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimating)) { timeline in
                    Canvas { context, canvasSize in
                        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                        let mid = canvasSize.height / 2

                        // 1) Pista completa (gris). SIEMPRE visible.
                        var track = Path()
                        track.move(to: CGPoint(x: 0, y: mid))
                        track.addLine(to: CGPoint(x: canvasSize.width, y: mid))
                        context.stroke(
                            track,
                            with: .color(trackColor),
                            style: StrokeStyle(lineWidth: thickness, lineCap: .round)
                        )

                        // 2) Parte activa: onda mientras suena, línea plana en pausa.
                        guard activeWidth > 0.5 else { return }

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
                                Gradient(colors: colors),
                                startPoint: CGPoint(x: 0, y: 0),
                                endPoint: CGPoint(x: max(activeWidth, 1), y: 0)
                            ),
                            style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)
                        )
                    }
                    .frame(width: size.width, height: size.height)
                }
                .frame(width: size.width, height: size.height)

                // 3) Thumb: posición real con el ancho del GeometryReader.
                if showsThumb, size.width > 0 {
                    Circle()
                        .fill(colors.first ?? AppTheme.accent)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                        )
                        .frame(width: thumbSize, height: thumbSize)
                        .scaleEffect(isScrubbing ? 1.3 : 1.0)
                        .animation(AuroraMotion.spatialFast, value: isScrubbing)
                        .shadow(color: .black.opacity(isScrubbing ? 0.25 : 0.15), radius: 3, x: 0, y: 1)
                        .position(
                            x: min(max(activeWidth, thumbSize / 2),
                                   max(thumbSize / 2, size.width - thumbSize / 2)),
                            y: midY
                        )
                }
            }
            .frame(width: size.width, height: size.height)
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
