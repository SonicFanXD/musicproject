import Foundation
import Combine

/// ✅ 3.0 GESTIÓN TÉRMICA INTELIGENTE.
///
/// El estado térmico del dispositivo decide cuánto trabajo VISUAL se permite:
///
/// | Nivel             | Visualizador | Halos/pulsos | Blurs a pantalla completa |
/// |-------------------|--------------|--------------|---------------------------|
/// | nominal           | 60 fps       | sí           | sí                        |
/// | fair              | 30 fps       | sí           | sí                        |
/// | serious           | 30 fps       | no           | sí                        |
/// | critical          | apagado      | no           | no (color sólido)         |
///
/// (Fair ya solo calienta un poco: se recorta el visualizador, que es el bucle
/// continuo. Los halos son animaciones cortas y se reservan para serious.)
///
/// ⚠️ REGLA DE ORO: la térmica NUNCA toca el motor de audio, la ruta de
/// reproducción ni la calidad sonora. Solo se recorta lo decorativo, y al bajar
/// la temperatura todo se restaura automáticamente.
///
/// ⚠️ Igual que ThemeManager/CaptureModeManager, no se marca `@MainActor`: el
/// estado se actualiza en el hilo principal desde la notificación del sistema
/// (`queue: .main`).
final class ThermalManager: ObservableObject {
    static let shared = ThermalManager()

    @Published private(set) var level: ThermalLevel

    private init() {
        level = Self.map(ProcessInfo.processInfo.thermalState)
        // ✅ `queue: .main`: la notificación puede llegar en cualquier hilo y el
        // estado publicado se lee desde la interfaz.
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Conveniencias (solo visual)

    /// ✅ serious/critical: se detienen halos y pulsos decorativos
    /// (`repeatForever`). El visualizador ya cae a 30 fps desde fair.
    var shouldReduceVisualEffects: Bool {
        level >= .serious
    }

    /// ✅ Solo en critical: el blur a pantalla completa es lo más caro de
    /// renderizar en un A11, así que se sustituye por color sólido.
    var shouldDisableHeavyBlur: Bool {
        level >= .critical
    }

    /// ✅ FPS objetivo del visualizador: 60 nominal, 30 fair/serious y 0 (apagado)
    /// en critical.
    var visualizerFPS: Int {
        switch level {
        case .nominal: return 60
        case .fair, .serious: return 30
        case .critical: return 0
        }
    }

    // MARK: - Estado

    /// Relee el estado térmico del sistema.
    func refresh() {
        let current = Self.map(ProcessInfo.processInfo.thermalState)
        guard current != level else { return }
        level = current
        AppLog.info(.performance, "Estado térmico: \(current) — \(visualizerFPS == 0 ? "visualizador apagado" : "\(visualizerFPS) fps")")
    }

    static func map(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
}

/// Nivel térmico propio: `Comparable` para poder escribir reglas acumulativas
/// (`level >= .serious`) sin repetir listas de casos en cada consumidor.
enum ThermalLevel: Int, Comparable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
