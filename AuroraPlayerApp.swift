import SwiftUI

@main
struct AuroraPlayerApp: App {
    // Custom accent color - less blue, more elegant purple/indigo
    private let customAccent = Color(red: 0.55, green: 0.35, blue: 0.85)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(customAccent)
                .preferredColorScheme(nil) // Follow system appearance
        }
    }
}
