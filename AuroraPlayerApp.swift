import SwiftUI

@main
struct AuroraPlayerApp: App {
    @StateObject private var audioEngine = AudioEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioEngine) // Opcional, pero lo dejamos para futuro
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background, .inactive:
                // Guardar estado cuando la app pase a segundo plano
                audioEngine.saveState()
            case .active:
                // No hacemos nada al volver, ya se restaura en ContentView
                break
            @unknown default:
                break
            }
        }
    }
}