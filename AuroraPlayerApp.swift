import SwiftUI

@main
struct AuroraPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // El color de acento morado se define en Assets.xcassets/AccentColor,
                // así Color.accentColor y .tint coinciden en TODA la app
                // (antes .tint() era morado pero Color.accentColor caía al azul del sistema).
                .tint(Color.accentColor)
                .preferredColorScheme(nil) // Follow system appearance
        }
    }
}