import Foundation
import Intents

// MARK: - Intents para Siri
class AuroraIntents {
    
    static func configureIntents() {
        // Donar sugerencias de Siri para la app
        let playIntent = INPlayMediaIntent()
        INVoiceShortcutCenter.shared.setShortcutSuggestions([INShortcut(intent: playIntent)]) { error in
            if let error = error {
                print("Error configurando intents: \(error)")
            }
        }
    }
    
    static func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) {
        switch shortcutItem.type {
        case "com.aurora.player.play":
            NotificationCenter.default.post(name: .playbackResume, object: nil)
        case "com.aurora.player.pause":
            NotificationCenter.default.post(name: .playbackPause, object: nil)
        case "com.aurora.player.shuffle":
            NotificationCenter.default.post(name: .playbackShuffle, object: nil)
        case "com.aurora.player.search":
            NotificationCenter.default.post(name: .openSearch, object: nil)
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
