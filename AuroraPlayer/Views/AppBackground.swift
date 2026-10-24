import SwiftUI

// Fondo de pantalla M3E: superficie tonal derivada del acento, no el gris de
// iOS. La base es `surface` y el pie baja un nivel de elevación para dar
// profundidad sin blur, material ni una sola capa offscreen extra.
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                M3EColor.surface,
                M3EColor.surfaceContainerLow
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .drawingGroup(opaque: true)
    }
}
