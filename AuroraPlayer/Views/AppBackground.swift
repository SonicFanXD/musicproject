import SwiftUI

struct AppBackground: View {
    @State private var glowPulse = false

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

            // Lavado de color superior derecho
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.09),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 480
            )
            .opacity(glowPulse ? 1.0 : 0.65)

            // Lavado de color inferior izquierdo, en contrafase con el anterior
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.05),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 420
            )
            .opacity(glowPulse ? 0.65 : 1.0)
        }
        .ignoresSafeArea()
        .onAppear {
            // Animación muy lenta (6s) y solo de opacidad: barata en CPU/GPU,
            // segura incluso en un iPhone 8 Plus. No recrea geometría.
            withAnimation(
                .easeInOut(duration: 6)
                    .repeatForever(autoreverses: true)
            ) {
                glowPulse = true
            }
        }
    
}