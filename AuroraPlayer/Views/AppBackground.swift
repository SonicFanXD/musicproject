import SwiftUI

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemBackground).opacity(0.97),
                    Color(.systemBackground).opacity(0.93)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Un lavado de color muy sutil para dar profundidad sin
            // costo de rendimiento (es un solo degradado estático).
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.07),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}