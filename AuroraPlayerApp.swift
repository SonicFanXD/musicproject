import SwiftUI

@main
struct AuroraPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(Color(UIColor.systemBackground)) // ✅ Fondo que se extiende
                .edgesIgnoringSafeArea(.all)                 // ✅ Ocupa toda la pantalla
        }
    }
}