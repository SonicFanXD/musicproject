import Foundation
import Intents
import IntentsUI

// MARK: - Intents para Siri
class AuroraIntents {
    
    static func configureIntents() {
        // Donar sugerencias de Siri para la app
        INVoiceShortcutCenter.shared.setSuggestions([
            INShortcut(intent: INPlayMediaIntent(), phrases: ["Reproducir", "Play"])
        ]) { error in
            if let error = error {
                print("Error configurando intents: \(error)")
            }
        }
    }
    
    static func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) {
        switch shortcutItem.type {
        case "com.aurora.player.play":
            NotificationCenter.default.post(name: .init(rawValue: "com.aurora.playback.resume"))
        case "com.aurora.player.pause":
            NotificationCenter.default.post(name: .init(rawValue: "com.aurora.playback.pause"))
        case "com.aurora.player.shuffle":
            NotificationCenter.default.post(name: .init(rawValue: "com.aurora.playback.shuffle"))
        case "com.aurora.player.search":
            NotificationCenter.default.post(name: .init(rawValue: "com.aurora.openSearch"))
        default:
            break
        }
    }
}

// MARK: - Extensiones para notificaciones
extension Notification.Name {
    static let openSearch = Notification.Name("com.aurora.openSearch")
    static let playbackResume = Notification.Name("com.aurora.playback.resume")
    static let playbackPause = Notification.Name("com.aurora.playback.pause")
    static let playbackShuffle = Notification.Name("com.aurora.playback.shuffle")
}
