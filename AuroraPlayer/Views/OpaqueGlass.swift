import SwiftUI

struct OpaqueGlass<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color = .white

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Material principal (ya es el más transparente de iOS)
                    shape
                        .fill(.ultraThinMaterial)

                    // Tinte suave, más discreto que antes
                    shape
                        .fill(tint.opacity(0.05))

                    // Brillo superior, reducido para dejar ver más el fondo
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.14),
                                    tint.opacity(0.05),
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
                                .white.opacity(0.40),
                                .white.opacity(0.12),
                                .white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(shape)
            .shadow(
                color: .black.opacity(0.14),
                radius: 14,
                x: 0,
                y: 6
            )
            // Transición suave cuando cambia el tinte (p. ej. canción activa),
            // sin animaciones continuas que consuman batería.
            .animation(.easeInOut(duration: 0.25), value: tint)
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