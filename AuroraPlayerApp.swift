import SwiftUI

@main
struct AuroraPlayerApp: App {
    @StateObject private var theme = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                // El acento elegido en Ajustes se aplica aquí: .tint() propaga
                // el color al entorno, así Color.accentColor y .tint coinciden
                // en TODA la app y reaccionan al cambiar el ajuste.
                .tint(theme.accent)
                .preferredColorScheme(nil) // Follow system appearance
        }
    }
}