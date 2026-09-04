import SwiftUI

@main
struct AuroraPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.accentColor)
                .preferredColorScheme(nil) // Follow system appearance
        }
    }
}