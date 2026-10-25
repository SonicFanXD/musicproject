import SwiftUI
import UIKit

// ══════════════════════════════════════════════════════════════════════════
// M3E COLOR — sistema tonal Material 3 real.
//
// Cada rol de color apunta a un TONO concreto (0…100) de una paleta generada
// desde el acento. En M3 el tono es una luminosidad ABSOLUTA: las superficies
// claras usan tonos altos (98/96/94…) y las oscuras tonos bajos (6/10/12…).
// Por eso no se invierte el tono en modo oscuro: el rol ya elige otro tono.
//
// · `M3ETone`           → escala de tonos oficial.
// · `M3ETonalPalette`   → hue + croma del seed, con caída de croma en extremos.
// · `M3EColor`          → roles light/dark dinámicos (trait collection).
//
// El seed se lee en RGB y se convierte a HSL a mano (no se usa
// getHue/getSaturation/getBrightness, que pierden precisión con P3).
// ══════════════════════════════════════════════════════════════════════════

// MARK: - Escala de tonos

enum M3ETone: Double {
    case t0 = 0
    case t4 = 4
    case t6 = 6
    case t10 = 10
    case t12 = 12
    case t17 = 17
    case t20 = 20
    case t22 = 22
    case t24 = 24
    case t30 = 30
    case t40 = 40
    case t50 = 50
    case t60 = 60
    case t70 = 70
    case t80 = 80
    case t87 = 87
    case t90 = 90
    case t92 = 92
    case t94 = 94
    case t95 = 95
    case t96 = 96
    case t98 = 98
    case t99 = 99
    case t100 = 100
}

// MARK: - Paleta tonal

/// Paleta derivada del seed. `hue` y `chroma` están normalizados a 0…1.
struct M3ETonalPalette {
    let hue: CGFloat
    let chroma: CGFloat

    init(hue: CGFloat, chroma: CGFloat) {
        self.hue = Self.normalizedHue(hue)
        self.chroma = min(max(chroma, 0), 1)
    }

    init(seed: Color) {
        self.init(uiColor: UIColor(seed))
    }

    init(uiColor: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1

        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let hsl = Self.rgbToHSL(red: red, green: green, blue: blue)
            self.hue = Self.normalizedHue(hsl.hue)
            self.chroma = min(max(hsl.saturation, 0), 1)
        } else {
            // Fallback: violeta neutro si el seed no se puede leer.
            self.hue = 0.75
            self.chroma = 0.45
        }
    }

    /// Color HSL para un tono absoluto. El tono 100 es blanco y el 0 negro;
    /// los roles oscuros usan tonos bajos, no una inversión de luminosidad.
    func tone(_ tone: M3ETone) -> Color {
        Color(uiColor: uiColor(tone))
    }

    private static func normalizedHue(_ hue: CGFloat) -> CGFloat {
        var value = hue.truncatingRemainder(dividingBy: 1)
        if value < 0 { value += 1 }
        return value
    }

    /// Variante UIColor para el proveedor dinámico de `M3EColor` (evita el
    /// viaje Color → UIColor dentro del closure de traits).
    func uiColor(_ tone: M3ETone) -> UIColor {
        let toneValue = CGFloat(tone.rawValue)
        let lightness = min(max(toneValue / 100, 0), 1)
        let chromaFactor = Self.chromaFactor(for: toneValue)
        let saturation = min(max(chroma * chromaFactor, 0), 1)
        let rgb = Self.hslToRGB(hue: hue, saturation: saturation, lightness: lightness)
        return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    // MARK: Derivación

    /// Caída de croma en los extremos: el tono 40 conserva el color, los
    /// tonos 90+ y 0-10 se acercan al neutro para que las superficies y los
    /// textos no parezcan pintura fluorescente.
    private static func chromaFactor(for tone: CGFloat) -> CGFloat {
        let stops: [(tone: CGFloat, factor: CGFloat)] = [
            (0, 0.10),
            (10, 0.30),
            (20, 0.54),
            (30, 0.78),
            (40, 1.00),
            (50, 0.94),
            (60, 0.84),
            (70, 0.70),
            (80, 0.54),
            (90, 0.36),
            (95, 0.24),
            (99, 0.10),
            (100, 0.05)
        ]

        for index in 0..<(stops.count - 1) {
            let lower = stops[index]
            let upper = stops[index + 1]
            guard tone >= lower.tone, tone <= upper.tone else { continue }
            let span = upper.tone - lower.tone
            guard span > 0 else { return lower.factor }
            let progress = (tone - lower.tone) / span
            return lower.factor + (upper.factor - lower.factor) * progress
        }
        return 0.10
    }

    private static func rgbToHSL(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) -> (hue: CGFloat, saturation: CGFloat) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        let delta = maximum - minimum

        guard delta > 0 else { return (0, 0) }

        let saturation = lightness > 0.5
            ? delta / max(0.0001, 2 - maximum - minimum)
            : delta / max(0.0001, maximum + minimum)

        var hue: CGFloat
        if maximum == red {
            hue = (green - blue) / delta + (green < blue ? 6 : 0)
        } else if maximum == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue /= 6
        return (hue, saturation)
    }

    private static func hslToRGB(
        hue: CGFloat,
        saturation: CGFloat,
        lightness: CGFloat
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        guard saturation > 0 else {
            return (lightness, lightness, lightness)
        }

        let q = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q

        func channel(_ value: CGFloat) -> CGFloat {
            var t = value
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2.0 { return q }
            if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
            return p
        }

        return (
            channel(hue + 1.0 / 3.0),
            channel(hue),
            channel(hue - 1.0 / 3.0)
        )
    }
}

// MARK: - Roles M3

enum M3EColor {

    /// Seed: acento manual o color extraído de la portada.
    static var seed: Color { AppTheme.accent }

    /// Paleta activa. Se reconstruye cuando cambia el seed.
    static var palette: M3ETonalPalette { M3ETonalPalette(uiColor: AppTheme.accentUIColor) }

    // MARK: Acento y contenedores

    static var primary: Color { role(.t40, .t80) }
    static var onPrimary: Color { role(.t100, .t20) }
    static var primaryContainer: Color { role(.t90, .t30) }
    static var onPrimaryContainer: Color { role(.t10, .t90) }

    static var secondary: Color { role(.t40, .t80) }
    static var onSecondary: Color { role(.t100, .t20) }
    static var secondaryContainer: Color { role(.t90, .t30) }
    static var onSecondaryContainer: Color { role(.t10, .t90) }

    /// Tercera paleta: hue del seed + 60°.
    static var tertiary: Color { role(.t40, .t80, hueShift: 60.0 / 360.0) }
    static var onTertiary: Color { role(.t100, .t20, hueShift: 60.0 / 360.0) }
    static var tertiaryContainer: Color { role(.t90, .t30, hueShift: 60.0 / 360.0) }
    static var onTertiaryContainer: Color { role(.t10, .t90, hueShift: 60.0 / 360.0) }

    /// Error: hue fijo de 25°, independiente del acento.
    static var error: Color { role(.t40, .t80, hueOverride: 25.0 / 360.0, chromaOverride: 0.72) }
    static var onError: Color { role(.t100, .t20, hueOverride: 25.0 / 360.0, chromaOverride: 0.72) }
    static var errorContainer: Color { role(.t90, .t30, hueOverride: 25.0 / 360.0, chromaOverride: 0.72) }
    static var onErrorContainer: Color { role(.t10, .t90, hueOverride: 25.0 / 360.0, chromaOverride: 0.72) }

    // MARK: Superficies tonales

    static var surface: Color { role(.t98, .t6) }
    static var surfaceDim: Color { role(.t87, .t6) }
    static var surfaceBright: Color { role(.t98, .t24) }

    static var surfaceContainerLowest: Color { role(.t100, .t4) }
    static var surfaceContainerLow: Color { role(.t96, .t10) }
    static var surfaceContainer: Color { role(.t94, .t12) }
    static var surfaceContainerHigh: Color { role(.t92, .t17) }
    static var surfaceContainerHighest: Color { role(.t90, .t22) }

    static var onSurface: Color { role(.t10, .t90) }
    static var onSurfaceVariant: Color { role(.t30, .t80) }
    static var surfaceVariant: Color { role(.t90, .t30) }

    // MARK: Bordes e inversos

    static var outline: Color { role(.t50, .t60) }
    static var outlineVariant: Color { role(.t80, .t30) }

    static var inverseSurface: Color { role(.t20, .t90) }
    static var inverseOnSurface: Color { role(.t95, .t20) }
    static var inversePrimary: Color { role(.t80, .t40) }

    static var scrim: Color { Color.black }

    // MARK: Dinamismo light/dark

    private static func role(
        _ light: M3ETone,
        _ dark: M3ETone,
        hueShift: CGFloat = 0,
        hueOverride: CGFloat? = nil,
        chromaOverride: CGFloat? = nil,
        chromaScale: CGFloat = 1
    ) -> Color {
        let base = palette
        return Color(uiColor: UIColor { traits in
            let tone = traits.userInterfaceStyle == .dark ? dark : light
            let shifted = M3ETonalPalette(
                hue: hueOverride ?? (base.hue + hueShift),
                chroma: min(1, chromaOverride ?? (base.chroma * chromaScale))
            )
            return shifted.uiColor(tone)
        })
    }
}
