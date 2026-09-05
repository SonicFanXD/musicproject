import UIKit

/// Helper centralizado para respuestas hápticas.
/// Respeta la configuración "Respuesta táctil" e "Intensidad táctil" de Ajustes.
/// ✅ OPTIMIZADO: caché de generators (crear uno por llamada tiene coste de
/// preparación del Taptic Engine; reutilizarlos reduce latencia y CPU).
enum Haptics {
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "com.aurora.enableHaptics") as? Bool ?? true
    }

    /// Intensidad configurable (0.0–1.0). Escala el impacto del generator.
    private static var intensity: CGFloat {
        let value = UserDefaults.standard.object(forKey: "com.aurora.hapticIntensity") as? Double ?? 1.0
        return CGFloat(min(max(value, 0.0), 1.0))
    }

    // ✅ Caché de generators por estilo: evita recrear el Taptic Engine
    // en cada llamada (latencia menor, menos CPU en A11).
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)

    /// Preparar el Taptic Engine de forma anticipada (opcional, mejora latencia)
    static func prepare() {
        guard isEnabled else { return }
        lightGenerator.prepare()
        mediumGenerator.prepare()
    }

    static func light() {
        guard isEnabled else { return }
        lightGenerator.impactOccurred(intensity: intensity)
    }

    static func medium() {
        guard isEnabled else { return }
        mediumGenerator.impactOccurred(intensity: intensity)
    }

    static func soft() {
        light()
    }
}