import SwiftUI

struct AppBackground: View {
    var accentTint: Color = .accentColor

    @State private var glowPulse = false
    @State private var driftOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemBackground).opacity(0.96),
                    Color(.systemBackground).opacity(0.90)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Lavado de color superior derecho (más sutil)
            RadialGradient(
                colors: [
                    accentTint.opacity(0.06),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 480
            )
            .opacity(glowPulse ? 1.0 : 0.6)
            .offset(driftOffset)

            // Lavado de color inferior izquierdo
            RadialGradient(
                colors: [
                    accentTint.opacity(0.04),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 420
            )
            .opacity(glowPulse ? 0.6 : 1.0)
            .offset(x: -driftOffset.width, y: -driftOffset.height)
        }
        .ignoresSafeArea()
        // Solo usar drawingGroup si hay animaciones para optimizar rendimiento
        .drawingGroup()
        .onAppear { startAnimating() }
        .onChange(of: accentTint) { newValue in
            // si cambias el tinte (p. ej. color del artwork actual),
            // que el cambio también sea fluido y no un salto brusco
            withAnimation(.easeInOut(duration: 0.6)) {}
        }
    }

    private func startAnimating() {
        guard !reduceMotion else {
            // Accesibilidad: si el usuario activó "Reducir movimiento",
            // mostramos el fondo estático sin el pulso infinito.
            glowPulse = true
            return
        }

        withAnimation(
            .easeInOut(duration: 6)
                .repeatForever(autoreverses: true)
        ) {
            glowPulse = true
        }

        // Segundo movimiento sutil, con otra duración, para que el
        // "respirar" del fondo no se sienta mecánico ni repetitivo.
        withAnimation(
            .easeInOut(duration: 10)
                .repeatForever(autoreverses: true)
        ) {
            driftOffset = CGSize(width: 24, height: 16)
        }
    }
}