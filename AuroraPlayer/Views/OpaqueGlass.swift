import SwiftUI

/// Modificador de vidrio esmerilado opaco, optimizado para fluidez en iOS 16+.
struct OpaqueGlass<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color = .white
    var tintIntensity: Double = 0.05
    var strokeIntensity: Double = 0.30
    var isPressed: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var tintGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(0.12),
                tint.opacity(tintIntensity + 0.04),
                tint.opacity(tintIntensity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var strokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(strokeIntensity),
                .white.opacity(strokeIntensity * 0.27),
                .white.opacity(strokeIntensity * 0.07)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    // Fallback sólido: sin blur en vivo, más barato y accesible
                    shape
                        .fill(Color(white: 0.14))
                        .overlay { shape.fill(tintGradient) }
                } else {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay { shape.fill(tintGradient) }
                }
            }
            .overlay {
                shape.stroke(strokeGradient, lineWidth: 0.8)
            }
            .clipShape(shape)
            .compositingGroup() // aplana material + tinte + stroke antes de la sombra -> menos overdraw
            .shadow(
                color: .black.opacity(isPressed ? 0.04 : 0.08),
                radius: isPressed ? 5 : 10,
                x: 0,
                y: isPressed ? 2 : 4
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6))
            .animation(.spring(response: 0.35, dampingFraction: 0.75))
    }
}

extension View {
    func opaqueGlass(
        cornerRadius: CGFloat = 20,
        tint: Color = .white,
        tintIntensity: Double = 0.05,
        strokeIntensity: Double = 0.30,
        isPressed: Bool = false
    ) -> some View {
        modifier(
            OpaqueGlass(
                shape: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                ),
                tint: tint,
                tintIntensity: tintIntensity,
                strokeIntensity: strokeIntensity,
                isPressed: isPressed
            )
        )
    }

    func opaqueGlassCapsule(
        tint: Color = .white,
        tintIntensity: Double = 0.05,
        strokeIntensity: Double = 0.30,
        isPressed: Bool = false
    ) -> some View {
        modifier(
            OpaqueGlass(
                shape: Capsule(),
                tint: tint,
                tintIntensity: tintIntensity,
                strokeIntensity: strokeIntensity,
                isPressed: isPressed
            )
        )
    }
}