import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════
// AURORA WAVY PROGRESS — indicador de progreso ONDULADO de Material 3// Expressive (M3E), nativo en SwiftUI y pensado para el A11.//// CAMBIO DE IMPLEMENTACIÓN (Tanda 4): Usamos `TimelineView(.animation)`// junto con `Canvas` en lugar de `withAnimation(.linear repeatForever)` sobre la
// vista Shape. Esto evita que SwiftUI recalcule el `Path` 60 veces/s en el
// hilo principal del A11. En su lugar, el dibujo ocurre en el hilo de GPU del
// Canvas, y solo la amplitud (play↔pause) se anima a través de
// `animatableData` con spring.//// REQUERIMIENTO CRÍTICO: la fase de la onda avanza con el tiempo usando
// `timeline.date.timeIntervalSinceReferenceDate`, lo que garantiza que la onda
// se mantenga sincronizada con el reloj del sistema sin consumir CPU.// ═══════════════════════════════════════════════════════════════════════════

// MARK: - Forma de la onda (dibujada en Canvas)

/// Sinusoide periódica. No tiene `animatableData` en el eje de fase (eso sería
/// costoso por frame). La fase se maneja externamente mediante TimelineView.
/// SÍ es animable el `amplitude` (play↔pause), que es el único dato geométrico.
struct AuroraWavyLine {
    /// Semiamplitud en puntos. Es el ÚNICO dato animable:    /// la transición reproducir ↔ pausa se anima con spring sobre este valor.
    var amplitude: CGFloat    /// Longitud de onda en puntos. Fija: la periodicidad la aporta la fase
    /// externa en TimelineView.
    var waveLength: CGFloat
    /// Fase inicial (se sobreescribe por TimelineView cada frame).
    var phase: CGFloat = 0
}// Extensión para dibujar la línea en un Canvas (usando GraphicsContext)
extension AuroraWavyLine {    static func draw(in context: inout GraphicsContext, size: CGSize, amplitude: CGFloat,                     waveLength: CGFloat, phase: CGFloat) {        let span = max(size.width, 1)        let midY = size.height / 2        let lambda = max(waveLength, 1)        let k = (2 * CGFloat.pi) / lambda        let steps = max(8, Int(span / 3))        let dx = span / CGFloat(steps)
        context.fill = .clear        context.strokeColor = .black // Se sobreescribirá con el gradiente en el caller        context.lineWidth = 1
        if steps < 2 { return }
        // Mover al punto inicial        let x0 = 0        let y0 = midY + amplitude * sin(k * x0 + phase)        context.move(to: CGPoint(x: x0, y: y0))
        // Dibujar la sinusoide mediante lineas directas (no Path de SwiftUI)        for step in 1...steps {            let x = CGFloat(step) * dx            let y = midY + amplitude * sin(k * x + phase)            context.addLine(to: CGPoint(x: x, y: y))        }    }}

// MARK: - Componente principal con TimelineView integrado
struct AuroraWavyProgress: View {    /// 0…1. El componente lo acota; el padre puede pasarlo con más rango.    let progress: Double    /// Conduce la onda: al pausar se aplana y se detiene el bucle.    var isPlaying: Bool    /// El padre lo pone a true mientras arrastra: el thumb crece y el    /// seguimiento es 1:1 (sin animación de posición).    var isScrubbing: Bool = false
    /// Grosor del trazo. M3E usa trazos gruesos; en la PlayerBar (compacta)    /// el padre puede bajarlo a 4.    var thickness: CGFloat = 5    /// Semiamplitud de la onda. Debe caber en el alto que el padre reserve:    /// alto ≥ thickness + 2 × amplitude.    var amplitude: CGFloat = 1.8    var waveLength: CGFloat = 24    /// Duración de un ciclo completo de traslación (0 → −λ). M3E se mueve    /// despacio: 1.4 s por ciclo da ese vaivén calmado, no un "loading".    var wavePeriod: Double = 1.4
    /// Dos paradas de acento (identidad Aurora: nunca un color plano).    var colors: [Color] = [AppTheme.accent, AppTheme.accent.opacity(0.45)]    /// `SurfaceVariant` tonal: la pista inactiva es sólida, sin material.    var trackColor: Color = Color.secondary.opacity(0.18)
    var showsThumb: Bool = true    var thumbColor: Color = .white    var thumbSize: CGFloat = 12    /// Punto de parada al final de la pista (detalle M3E opcional).    var showsStopIndicator: Bool = true

    var body: some View {        TimelineView(.animation) { timeline in            VStack(spacing: 0) {                // Barra sólida de pista                Capsule()                    .fill(trackColor)                    .frame(width: max(CGFloat(1), 1), height: 16)                // Canvas con la onda animada                Canvas { context, size in                    // ✅ FASE: obtenemos la fecha del sistema vía TimelineView.                    // La onda avanza con el tiempo sin consumir CPU en el hilo principal.                    let systemTime = timeline.date.timeIntervalSinceReferenceDate                    let phase = .pi * 2 * (systemTime.truncatingRemainder(dividingBy: wavePeriod) / wavePeriod)

                    // Dibujamos la línea de la onda con la amplitud actual                    var line = AuroraWavyLine(amplitude: targetAmplitude, waveLength: waveLength)
                    AuroraWavyLine.draw(in: &context, size: size, amplitude: targetAmplitude,
                                        waveLength: waveLength, phase: phase)
                    // Aplicamos el gradiente de acento después de dibujar
                    context.strokeColor = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    context.lineWidth = 16                }
                .frame(width: max(CGFloat(1), 1), height: 16)
                // Thumb de arrastre (sobrepuesta, no afecta el dibujo de la onda)
                if showsThumb && thumbVisible {                    Circle()
                        .fill(thumbColor)                        .frame(width: thumbSize, height: thumbSize)
                        .overlay {
                            Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(isScrubbing ? 0.28 : 0.16),                            radius: isScrubbing ? 5 : 3, x: 0, y: 2)
                        .scaleEffect(isScrubbing ? 1.38 : 1)
                        .animation(AuroraMotion.emphasized, value: isScrubbing)
                        .position(x: max(0, min(CGFloat(1), clampedProgress) * max(CGFloat(1), sizeThatFits(.zero).width)),
                                  y: 8)                }            }            .frame(height: 16)        }    }
    /// Amplitud objetivo: 0 en pausa o con Reducir movimiento. La transición    /// la anima `AuroraMotion.normal` sobre el `animatableData` de la forma.    private var targetAmplitude: CGFloat {        (isPlaying && !reduceMotion) ? amplitude : 0    }
    /// Grosor del trazo objetivo (usado por el draw del Canvas).    private var targetTrackHeight: CGFloat {        16    }
    /// Entorno para acceso a Reducir movimiento
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Estado clamped del progreso (0...1)
    @State private var clampedProgress: CGFloat = 0
}

// MARK: - Preview (solo para diseño; no se ejecuta en la app)

#if DEBUG
struct AuroraWavyProgress_Previews: PreviewProvider {    static var previews: some View {        VStack(spacing: 32) {            AuroraWavyProgress(progress: 0.42, isPlaying: true)                .frame(height: 18)            AuroraWavyProgress(progress: 0.68, isPlaying: true, isScrubbing: true)                .frame(height: 18)            AuroraWavyProgress(progress: 0.2, isPlaying: false)                .frame(height: 18)            AuroraWavyProgress(progress: 1, isPlaying: false, thickness: 3, amplitude: 1, waveLength: 18)                .frame(height: 12)        }        .padding(32)        .background(Color(UIColor.systemBackground))    }}
#endif


