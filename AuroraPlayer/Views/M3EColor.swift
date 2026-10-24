import SwiftUI
import UIKit

// ══════════════════════════════════════════════════════════════════════════
// M3E COLOR — paleta TONAL de Material 3 Expressive.
//
// M3 no usa grises neutros del sistema para las superficies: cada rol se
// deriva del color de acento (hue + una fracción de su saturación) y de un
// nivel de luminosidad fijo. Eso es lo que hace que una card se lea como
// "Material" y no como una celda de iOS, incluso cuando el acento cambia
// desde la carátula.
//
// · `surface`            → fondo de pantalla (casi blanco / casi negro).
// · `surfaceContainer*`  → cards y contenedores; más claro = más bajo,
//                          más oscuro = más elevado (tonal elevation).
// · `outline`            → bordes de 1.5 pt al 20 %.
// · `primaryContainer`   → relleno tonal de acciones secundarias.
//
// Todos los valores son `Color` dinámicos: se resuelven con el trait de
// interfaz activo, así el modo claro/oscuro no exige dos paletas en código.
// ══════════════════════════════════════════════════════════════════════════

enum M3EColor {

    // MARK: - Acento

    static var primary: Color { AppTheme.accent }

    /// Texto/icono sobre `primary`. Se elige por brillo real del acento para
    /// no dejar texto blanco sobre un amarillo claro.
    static var onPrimary: Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 1
        if UIColor(AppTheme.accent).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            return brightness > 0.76 ? Color(white: 0.10) : .white
        }
        return .white
    }

    static var primaryContainer: Color {
        tone(
            light: (brightness: 0.88, chroma: 0.42),
            dark: (brightness: 0.30, chroma: 0.50)
        )
    }

    static var onPrimaryContainer: Color {
        tone(
            light: (brightness: 0.20, chroma: 0.55),
            dark: (brightness: 0.94, chroma: 0.08)
        )
    }

    // MARK: - Superficies (tonal elevation)

    static var surface: Color {
        tone(
            light: (brightness: 0.985, chroma: 0.030),
            dark: (brightness: 0.055, chroma: 0.100)
        )
    }

    static var surfaceContainerLowest: Color {
        tone(
            light: (brightness: 1.000, chroma: 0.020),
            dark: (brightness: 0.035, chroma: 0.080)
        )
    }

    static var surfaceContainerLow: Color {
        tone(
            light: (brightness: 0.958, chroma: 0.035),
            dark: (brightness: 0.085, chroma: 0.110)
        )
    }

    static var surfaceContainer: Color {
        tone(
            light: (brightness: 0.935, chroma: 0.045),
            dark: (brightness: 0.105, chroma: 0.120)
        )
    }

    static var surfaceContainerHigh: Color {
        tone(
            light: (brightness: 0.905, chroma: 0.055),
            dark: (brightness: 0.135, chroma: 0.130)
        )
    }

    static var surfaceContainerHighest: Color {
        tone(
            light: (brightness: 0.875, chroma: 0.065),
            dark: (brightness: 0.170, chroma: 0.140)
        )
    }

    /// Superficie de chips no seleccionados y campos de texto.
    static var surfaceVariant: Color {
        tone(
            light: (brightness: 0.900, chroma: 0.060),
            dark: (brightness: 0.200, chroma: 0.140)
        )
    }

    // MARK: - Bordes y texto secundario

    /// `outline` de M3: neutro tintado, suficientemente oscuro para que al
    /// 20 % de opacidad siga leyéndose como borde y no desaparezca.
    static var outline: Color {
        tone(
            light: (brightness: 0.500, chroma: 0.140),
            dark: (brightness: 0.620, chroma: 0.140)
        )
    }

    static var outlineVariant: Color {
        tone(
            light: (brightness: 0.800, chroma: 0.080),
            dark: (brightness: 0.300, chroma: 0.100)
        )
    }

    static var onSurfaceVariant: Color {
        tone(
            light: (brightness: 0.420, chroma: 0.120),
            dark: (brightness: 0.780, chroma: 0.080)
        )
    }

    // MARK: - Derivación tonal

    /// Genera un `Color` dinámico a partir del hue del acento y dos tuplas
    /// (brillo, fracción de saturación) para claro/oscuro.
    ///
    /// La saturación se escala MUY por debajo del acento: una superficie M3
    /// tiene croma 4-8, no el croma de un botón filled. Con `chroma: 0.04`
    /// un acento al 80 % de saturación deja la superficie al 3.2 %.
    private static func tone(
        light: (brightness: CGFloat, chroma: CGFloat),
        dark: (brightness: CGFloat, chroma: CGFloat)
    ) -> Color {
        var hue: CGFloat = 0.75
        var saturation: CGFloat = 0.45
        var brightness: CGFloat = 0.8
        var alpha: CGFloat = 1
        if !UIColor(AppTheme.accent).getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        ) {
            hue = 0.75
            saturation = 0.45
        }

        let accentHue = hue
        let accentSaturation = saturation

        return Color(uiColor: UIColor { traits in
            let config = traits.userInterfaceStyle == .dark ? dark : light
            let resolvedSaturation = min(0.90, max(0.0, accentSaturation * config.chroma))
            return UIColor(
                hue: accentHue,
                saturation: resolvedSaturation,
                brightness: min(max(config.brightness, 0.0), 1.0),
                alpha: 1.0
            )
        })
    }
}
