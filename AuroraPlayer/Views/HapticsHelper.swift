import UIKit

/// Helper centralizado para respuestas hápticas.
/// Respeta la configuración "Respuesta táctil" de Ajustes.
enum Haptics {
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "com.aurora.enableHaptics") as? Bool ?? true
    }

    static func light() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func soft() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}