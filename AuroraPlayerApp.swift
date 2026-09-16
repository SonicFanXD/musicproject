import SwiftUI

@main
struct AuroraPlayerApp: App {
    @StateObject private var theme = ThemeManager.shared
    // ✅ HUD de FPS global (UIWindow independiente, visible en todas las pantallas)
    @AppStorage("com.aurora.showFPS") private var showFPS = false
    // ✅ Leer el tema guardado (0=Sistema, 1=Claro, 2=Oscuro) para aplicarlo globalmente
    @AppStorage("com.aurora.uiTheme") private var savedThemeIndex = 0
    // ✅ Manejo de ciclo de vida para evitar errores de touch al reanudar
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                // ✅ ELIMINADO .id(theme.accentIndex): forzar re-creación de
                // toda la jerarquía causaba bugs visuales (parpadeos, reset
                // de scroll, pérdida de estado). .tint() por sí solo propaga
                // el color a TODOS los componentes de SwiftUI nativamente.
                .tint(theme.accent)
                .preferredColorScheme(savedThemeIndex == 1 ? .light : savedThemeIndex == 2 ? .dark : nil)
                .onAppear {
                    FPSOverlayController.shared.setEnabled(showFPS)
                    // ✅ Logs técnicos: memoria, térmico, ciclo de vida, rutas de audio
                    AppLog.bootstrap()
                    AppLog.info(.lifecycle, "App iniciada (v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))")
                }
                .onChange(of: showFPS) { newValue in
                    FPSOverlayController.shared.setEnabled(newValue)
                }
                // ✅ FIX: Manejar cambios de ciclo de vida para evitar errores de touch
                // al reanudar la app desde background. Forzar un refresh de la UI
                // cuando la app vuelve a activa para limpiar estados inconsistentes.
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        AppLog.info(.lifecycle, "App volvió a estado activo")
                        // ✅ Forzar actualización de tema y estado para evitar touch bugs
                        theme.objectWillChange.send()
                    case .background:
                        AppLog.info(.lifecycle, "App pasó a background")
                    case .inactive:
                        AppLog.info(.lifecycle, "App pasó a inactivo")
                    @unknown default:
                        break
                    }
                }
        }
    }
}
