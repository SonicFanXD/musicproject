import SwiftUI

@main
struct AuroraPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(Color(UIColor.systemBackground))
                .edgesIgnoringSafeArea(.all)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}