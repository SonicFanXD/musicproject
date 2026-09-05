import SwiftUI

@main
struct AuroraPlayerApp: App {
    @StateObject private var theme = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                // El acento elegido en Ajustes se aplica aquí: .tint() propaga
                // el color al entorno, así Color.accentColor y .tint coinciden
                // en TODA la app.
                // ✅ FIX: .id(theme.accentIndex) fuerza re-crear la jerarquía
                // cuando cambia el acento, haciendo que TODOS los
                // Color.accentColor se actualicen al instante (antes .tint
                // no re-renderizaba la jerarquía con el nuevo color).
                .tint(theme.accent)
                .id(theme.accentIndex)
                .preferredColorScheme(nil) // Follow system appearance
        }
    }
}