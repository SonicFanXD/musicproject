import SwiftUI

struct AppBackground: View {
    // ✅ TEMAS: el fondo raíz sigue el modo guardado. En Sistema/Claro/Oscuro se
    // delega en los colores dinámicos (resultado idéntico al anterior); en
    // Medianoche / Crepúsculo / Papel se usan los dos colores propios del tema.
    @AppStorage(AppThemeMode.storageKey) private var savedThemeIndex = 0

    var body: some View {
        LinearGradient(
            colors: AppThemeMode.mode(forStoredIndex: savedThemeIndex).backgroundColors,
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .drawingGroup(opaque: true)
    }
}
