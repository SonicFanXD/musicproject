import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// AURORA RIPPLE — el feedback táctil de Android.
//
// Cada pulsación añade un círculo que crece desde el punto del toque y se
// desvanece en 450 ms. `TimelineView` queda PAUSADO cuando no hay ripples, así
// que en reposo no pide frames. No hay `repeatForever`: cada ripple nace, se
// dibuja y se retira.
//
// Con `accessibilityReduceMotion` no se dibuja ninguno; queda solo el scale
// que ya aportan los button styles.
//
// ⚠️ DESCONECTADO TEMPORALMENTE (regresión e714dfa): NO aplicar este modifier
// al label de un `Button` ni dentro de un `ButtonStyle`. El DragGesture de
// `onChanged` compite con el tap interno del botón y lo deja sin acción. Se
// conserva el código para rediseñarlo como overlay pasivo (sin gesto).
// ══════════════════════════════════════════════════════════════════════════

struct RippleState: Identifiable {
    let id: UUID
    let position: CGPoint
    let startedAt: TimeInterval

    init(id: UUID = UUID(), position: CGPoint, startedAt: TimeInterval) {
        self.id = id
        self.position = position
        self.startedAt = startedAt
    }
}

struct AuroraRippleModifier: ViewModifier {
    var color: Color = M3EColor.onSurface.opacity(0.12)
    var cornerRadius: CGFloat = 16

    @State private var ripples: [RippleState] = []
    /// Un solo ripple por pulsación: evita que `onChanged` (que se dispara en
    /// cada frame del dedo) llene la lista de círculos.
    @State private var activeTouchID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let duration: TimeInterval = 0.45

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion, !ripples.isEmpty {
                    GeometryReader { _ in
                        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                            Canvas { context, size in
                                let now = timeline.date.timeIntervalSinceReferenceDate
                                let maxRadius = (size.width * size.width
                                                 + size.height * size.height).squareRoot() * 2

                                for ripple in ripples {
                                    let elapsed = now - ripple.startedAt
                                    guard elapsed >= 0, elapsed <= duration else { continue }
                                    let progress = CGFloat(min(max(elapsed / duration, 0), 1))
                                    let radius = maxRadius * progress
                                    let rect = CGRect(
                                        x: ripple.position.x - radius,
                                        y: ripple.position.y - radius,
                                        width: radius * 2,
                                        height: radius * 2
                                    )
                                    context.fill(
                                        Path(ellipseIn: rect),
                                        with: .color(color.opacity(Double(1 - progress)))
                                    )
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !reduceMotion, activeTouchID == nil else { return }

                        // El ripple nace al TOCAR, no al soltar. El punto de
                        // inicio se reconstruye con location - translation
                        // para no depender de `startLocation`.
                        let start = CGPoint(
                            x: value.location.x - value.translation.width,
                            y: value.location.y - value.translation.height
                        )
                        let id = UUID()
                        let ripple = RippleState(
                            id: id,
                            position: start,
                            startedAt: Date().timeIntervalSinceReferenceDate
                        )
                        activeTouchID = id
                        ripples.append(ripple)

                        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                            ripples.removeAll { $0.id == id }
                            if activeTouchID == id { activeTouchID = nil }
                        }
                    }
                    .onEnded { value in
                        // Si el dedo se fue en un scroll, el ripple se retira
                        // en vez de quedar como una mancha al soltar.
                        let distance = (value.translation.width * value.translation.width
                                        + value.translation.height * value.translation.height).squareRoot()
                        if distance >= 10, let id = activeTouchID {
                            ripples.removeAll { $0.id == id }
                        }
                        // La pulsación termina aunque el ripple siga 450 ms
                        // desvaneciéndose: el siguiente toque puede crear otro.
                        activeTouchID = nil
                    }
            )
    }
}

extension View {
    func auroraRipple(
        cornerRadius: CGFloat = 16,
        color: Color = M3EColor.onSurface.opacity(0.12)
    ) -> some View {
        modifier(AuroraRippleModifier(color: color, cornerRadius: cornerRadius))
    }
}
