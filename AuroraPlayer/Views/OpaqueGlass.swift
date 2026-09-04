import SwiftUI

struct OpaqueGlass<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color = .white

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Material ultra delgado para máxima transparencia
                    shape
                        .fill(.ultraThinMaterial)

                    // Tinte muy sutil (reducido para mayor transparencia)
                    shape
                        .fill(tint.opacity(0.05))

                    // Brillo superior muy ligero
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.12),
                                    tint.opacity(0.04),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.30),
                                .white.opacity(0.08),
                                .white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .clipShape(shape)
            .shadow(
                color: .black.opacity(0.08),
                radius: 10,
                x: 0,
                y: 4
            )
            .animation(.easeInOut(duration: 0.2), value: tint)
    }
}

extension View {
    func opaqueGlass(
        cornerRadius: CGFloat = 20,
        tint: Color = .white
    ) -> some View {
        modifier(
            OpaqueGlass(
                shape: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                ),
                tint: tint
            )
        )
    }

    func opaqueGlassCapsule(
        tint: Color = .white
    ) -> some View {
        modifier(
            OpaqueGlass(
                shape: Capsule(),
                tint: tint
            )
        )
    }
}