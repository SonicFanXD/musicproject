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

            // Lavado de color superior derecho (más sutil)
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.06),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 480
            )
            .opacity(glowPulse ? 1.0 : 0.6)

            // Lavado de color inferior izquierdo
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.04),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 420
            )
            .opacity(glowPulse ? 0.6 : 1.0)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 6)
                    .repeatForever(autoreverses: true)
            ) {
                glowPulse = true
            }
        }
    }
}