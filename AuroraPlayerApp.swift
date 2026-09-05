import SwiftUI

@main
struct AuroraPlayerApp: App {
    @StateObject private var theme = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                // ✅ ELIMINADO .id(theme.accentIndex): forzar re-creación de
                // toda la jerarquía causaba bugs visuales (parpadeos, reset
                // de scroll, pérdida de estado). .tint() por sí solo propaga
                // el color a TODOS los componentes de SwiftUI nativamente.
                .tint(theme.accent)
                .preferredColorScheme(nil)
        }
    }
}
