import SwiftUI
import UIKit
import Combine

/// ✅ MODO PRESENTACIÓN (3.0): detecta GRABACIÓN DE PANTALLA y CAPTURAS.
///
/// Qué hace: oculta la barra de estado, limita el FPS del visualizador, detiene
/// las animaciones decorativas y muestra una píldora "Grabando".
/// Qué NO hace: no toca el motor de audio, la ruta de reproducción ni la calidad
/// sonora — es puramente visual.
///
/// ⚠️ Solo se accede desde el hilo principal (`init` consulta UIKit), por eso no
/// se marca @MainActor: se sigue la misma convención que ThemeManager/Localization.
final class CaptureModeManager: ObservableObject {
    static let shared = CaptureModeManager()

    /// true mientras el sistema graba la pantalla (QuickTime/AirPlay o grabación
    /// desde el centro de control).
    @Published private(set) var isScreenCaptured: Bool = false
    /// Fecha de la última captura de pantalla.
    @Published private(set) var lastScreenshotAt: Date?

    /// ✅ Una señal por CADA captura de pantalla: `lastScreenshotAt` solo no basta,
    /// porque dos capturas seguidas cambian la fecha pero deben volver a mostrar
    /// el toast.
    let screenshotPublisher = PassthroughSubject<Void, Never>()

    private init() {
        isScreenCaptured = Self.screenIsCaptured
        // ✅ `queue: .main`: la notificación de captura llega en un hilo arbitrario
        // y el estado publicado tiene que actualizarse en el hilo de interfaz.
        NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshCaptureState()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.lastScreenshotAt = Date()
            self.screenshotPublisher.send()
            AppLog.info(.interface, "Captura de pantalla realizada")
        }
    }

    /// ✅ `UIScreen.main` está deprecado en iOS 16: se consulta la pantalla de la
    /// primera escena conectada.
    private static var screenIsCaptured: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
            .isCaptured ?? false
    }

    /// Relee el estado de captura. Público para poder sincronizar al volver a
    /// primer plano: una grabación puede haber empezado con la app en segundo
    /// plano (cuando la notificación no se atiende).
    func refreshCaptureState() {
        let captured = Self.screenIsCaptured
        guard captured != isScreenCaptured else { return }
        isScreenCaptured = captured
        AppLog.info(.interface, captured
            ? "Grabación de pantalla iniciada: modo presentación activo"
            : "Grabación de pantalla finalizada: modo normal restaurado")
    }
}

/// ✅ 3.0: política ÚNICA para animaciones DECORATIVAS (halo del play, indicadores
/// de "suena ahora", pulsos). Durante una grabación de pantalla se desactivan: no
/// aportan nada al vídeo y mantienen la GPU trabajando sin motivo.
enum DecorativeMotion {
    /// ¿Se permiten animaciones decorativas ahora mismo?
    static var isAllowed: Bool { !CaptureModeManager.shared.isScreenCaptured }

    /// Devuelve la animación solo si está activa Y permitida; si no, nil → la
    /// vista queda estática, sin bucle consumiendo frames.
    static func animation(_ animation: Animation?, isActive: Bool) -> Animation? {
        (isActive && isAllowed) ? animation : nil
    }

    /// ✅ Pasar `nil` como animación NO detiene un `repeatForever` ya en marcha:
    /// la vista queda esperando el próximo cambio de la propiedad animada, y como
    /// mientras se graba esa propiedad no cambia, el bucle seguiría oscilando.
    /// Esta clave unifica "está sonando" con "se permite animar", así al empezar
    /// la grabación la propiedad ANIMADA vuelve a su valor base y el bucle muere.
    static func isAnimating(_ isActive: Bool) -> Bool { isActive && isAllowed }
}
