import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// AURORA WAVY PROGRESS — indicador de progreso ONDULADO de Material 3
// Expressive (M3E), nativo en SwiftUI y pensado para el A11.
// ══════════════════════════════════════════════════════════════════════════

// MARK: - Forma de la onda (dibujada con Path)

// Sinusoide periódica dibujada con Path de SwiftUI.
// La fase se gestiona externamente mediante TimelineView.
struct AuroraWavyLine {
    var amplitude: CGFloat
    var waveLength: CGFloat
    var phase: CGFloat = 0

    // Dibujar la línea usando Path de SwiftUI y context.stroke()
    static func draw(in context: GraphicsContext, size: CGSize, amplitude: CGFloat,
                     waveLength: CGFloat, phase: CGFloat) {
        let span = max(size.width, 1)
        let midY = size.height / 2.0
        let lambda = max(waveLength, 1)
        let k = (2 * CGFloat.pi) / lambda
        let steps = max(8, Int(span / 3))
        let dx = span / CGFloat(steps)

        // Crear el Path de la onda
        var path = Path()

        // Mover al punto inicial
        path.move(to: CGPoint(x: 0, y: midY))

        // Dibujar la sinusoide mediante addLine en el Path
        for step in 1...steps {
            let x = CGFloat(step) * dx
            let y = midY + amplitude * sin(k * x + phase)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        // Dibujar el path en el contexto con el gradiente
        context.stroke(path, with: .color(.black), lineWidth: 1)
    }
}

// MARK: - Componente principal con TimelineView

struct AuroraWavyProgress: View {
    let progress: Double
    var isPlaying: Bool
    var isScrubbing: Bool = false

    var thickness: CGFloat = 5
    var amplitude: CGFloat = 1.8
    var waveLength: CGFloat = 24
    var wavePeriod: Double = 1.4

    var colors: [Color] = [AppTheme.accent, AppTheme.accent.opacity(0.45)]
    var trackColor: Color = Color.secondary.opacity(0.18)

    var showsThumb: Bool = true
    var thumbColor: Color = .white
    var thumbSize: CGFloat = 12
    var showsStopIndicator: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Amplitud objetivo: 0 en pausa o con Reducir movimiento.
    private var targetAmplitude: CGFloat {
        (isPlaying && !reduceMotion) ? amplitude : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Barra sólida de pista
            Capsule()
                .fill(trackColor)
                .frame(width: max(CGFloat(1), 1), height: 16)

            // Canvas con la onda animada vía TimelineView
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    // ✅ FASE: obtenemos la fecha del sistema vía TimelineView.
                    let systemTime = timeline.date.timeIntervalSinceReferenceDate
                    let phase = .pi * 2 * (systemTime.truncatingRemainder(dividingBy: wavePeriod) / wavePeriod)

                    // Dibujamos la línea de la onda con la amplitud actual
                    var line = AuroraWavyLine(amplitude: targetAmplitude, waveLength: waveLength, phase: phase)
                    AuroraWavyLine.draw(in: context, size: size, amplitude: targetAmplitude,
                                        waveLength: waveLength, phase: phase)

                    // Aplicamos el gradiente de acento después de dibujar
                    context.strokeColor = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    context.lineWidth = 16
                }
                .frame(width: max(CGFloat(1), 1), height: 16)

                // Thumb de arrastre (sobrepuesta, no afecta el dibujo de la onda)
                if showsThumb {
                    Circle()
                        .fill(thumbColor)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay {
                            Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(isScrubbing ? 0.28 : 0.16),
                                radius: isScrubbing ? 5 : 3, x: 0, y: 2)
                        .scaleEffect(isScrubbing ? 1.38 : 1)
                        .animation(AuroraMotion.emphasized, value: isScrubbing)
                        .position(x: max(0, min(CGFloat(1), CGFloat(progress)) * max(CGFloat(1), 300)),
                                  y: 8)
                }
            }
        }
        .frame(height: 16)
    }
}

// MARK: - Preview (solo para diseño; no se ejecuta en la app)

#if DEBUG
struct AuroraWavyProgress_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 32) {
            AuroraWavyProgress(progress: 0.42, isPlaying: true)
                .frame(height: 18)
            AuroraWavyProgress(progress: 0.68, isPlaying: true, isScrubbing: true)
                .frame(height: 18)
            AuroraWavyProgress(progress: 0.2, isPlaying: false)
                .frame(height: 18)
            AuroraWavyProgress(progress: 1, isPlaying: false, thickness: 3, amplitude: 1, waveLength: 18)
                .frame(height: 12)
        }
        .padding(32)
        .background(Color(UIColor.systemBackground))
    }
}
#endif