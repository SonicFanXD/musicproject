import SwiftUI

struct OpaqueGlass<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color = .white

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Material principal
                    shape
                        .fill(.ultraThinMaterial)

                    // Tinte suave
                    shape
                        .fill(tint.opacity(0.08))

                    // Brillo superior
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.18),
                                    tint.opacity(0.08),
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
                                .white.opacity(0.55),
                                .white.opacity(0.15),
                                .white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(shape)
            .shadow(
                color: .black.opacity(0.18),
                radius: 16,
                x: 0,
                y: 7
            )
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