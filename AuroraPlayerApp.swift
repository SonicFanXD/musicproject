```swift
import SwiftUI

@main
struct AuroraPlayerApp: App {

    @StateObject
    private var audioEngine =
        AudioEngine()

    var body: some Scene {

        WindowGroup {

            ContentView()
                .environmentObject(
                    audioEngine
                )
        }
    }
}
```
