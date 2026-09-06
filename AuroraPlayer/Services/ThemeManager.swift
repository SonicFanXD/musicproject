import SwiftUI
import Combine

/// Gestor central del tema: color de acento aplicable en toda la app.
/// Las vistas usan `AppTheme.accent` en lugar de `Color.accentColor`
/// para que el ajuste "Color de acento" tenga efecto real.
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let key = "com.aurora.accentColor"
    private static let artworkAccentKey = "com.aurora.accentFromArtwork"

    /// ✅ NUEVO: modo "acento desde carátula" — cuando está activo, todo el
    /// color de acento de la app se toma del color dominante de la portada
    /// de la canción en reproducción (con normalización de legibilidad).
    @Published var accentFromArtwork: Bool {
        didSet {
            UserDefaults.standard.set(accentFromArtwork, forKey: Self.artworkAccentKey)
            if !accentFromArtwork {
                artworkAccentColor = nil
                artworkAccentUIColor = nil
            }
            applyGlobalUIKitTint()
        }
    }

    @Published private(set) var artworkAccentColor: Color?
    @Published private(set) var artworkAccentUIColor: UIColor?

    // Caché de color por canción (id) para no re-extraer el histograma HSB
    private static let artworkColorCache = NSCache<NSString, UIColor>()

    /// Extrae el color dominante de la portada en segundo plano y lo publica.
    /// Llamado por AudioEngine cada vez que cambia la canción actual.
    func updateArtworkAccent(from song: Song?) {
        guard accentFromArtwork else { return }
        guard let song, let artwork = song.artwork else {
            artworkAccentColor = nil
            artworkAccentUIColor = nil
            return
        }
        let cacheKey = song.id.uuidString as NSString
        if let cached = Self.artworkColorCache.object(forKey: cacheKey) {
            artworkAccentUIColor = cached
            artworkAccentColor = Self.normalizeArtworkAccent(cached)
            applyGlobalUIKitTint()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let dominant = AppTheme.dominantColor(from: artwork)
            guard let dominant else { return }
            Self.artworkColorCache.setObject(dominant, forKey: cacheKey)
            DispatchQueue.main.async {
                guard let self, self.accentFromArtwork else { return }
                self.artworkAccentUIColor = dominant
                self.artworkAccentColor = Self.normalizeArtworkAccent(dominant)
                self.applyGlobalUIKitTint()
            }
        }
    }

    /// Color final efectivo del acento: el de la carátula si el modo está
    /// activo y hay color disponible; si no, el acento manual.
    var resolvedAccent: Color {
        if accentFromArtwork, let c = artworkAccentColor { return c }
        return accent
    }

    private static func normalizeArtworkAccent(_ uiColor: UIColor) -> Color {
        AppTheme.readableColor(from: uiColor)
    }

    @Published var accentIndex: Int {
        didSet {
            UserDefaults.standard.set(accentIndex, forKey: Self.key)
            // ✅ FIX "rastros del color por defecto": propagar el acento a
            // UIKit globalmente (ventanas, route picker, alertas nativas,
            // controles heredados) — .tint() de SwiftUI no cubre UIKit.
            applyGlobalUIKitTint()
        }
    }

    /// Aplica el color de acento a todas las ventanas UIKit existentes.
    private func applyGlobalUIKitTint() {
        // ✅ Respeta el modo "acento desde carátula" en UIKit también
        let uiColor: UIColor
        if accentFromArtwork, let c = artworkAccentUIColor {
            uiColor = c
        } else {
            uiColor = UIColor(accent)
        }
        DispatchQueue.main.async {
            UIWindow.appearance().tintColor = uiColor
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                for window in scene.windows {
                    window.tintColor = uiColor
                }
            }
        }
    }

    private init() {
        // ✅ FIX CI: 'key' es estático, debe referenciarse como Self.key
        let saved = UserDefaults.standard.integer(forKey: Self.key)
        accentIndex = (saved >= 0 && saved < 7) ? saved : 0
        accentFromArtwork = UserDefaults.standard.bool(forKey: Self.artworkAccentKey)
        // ✅ Aplicar el tint UIKit al arrancar (restaura el ajuste guardado)
        applyGlobalUIKitTint()
    }

    func setAccent(_ index: Int) {
        accentIndex = index
    }

    var accent: Color {
        Self.color(for: accentIndex)
    }

    static func color(for index: Int) -> Color {
        switch index {
        case 1: return Color(red: 0.20, green: 0.55, blue: 0.95) // Azul Aurora
        case 2: return Color(red: 0.10, green: 0.75, blue: 0.50) // Esmeralda
        case 3: return Color(red: 0.95, green: 0.30, blue: 0.60) // Rosa Neón
        case 4: return Color(red: 0.98, green: 0.62, blue: 0.15) // Ámbar Solar
        case 5: return Color(red: 0.11, green: 0.11, blue: 0.13) // Negro Grafito
        case 6: return Color(red: 0.55, green: 0.08, blue: 0.11) // Rojo Oscuro
        default: return Color(red: 0.62, green: 0.40, blue: 0.95) // Morado (predeterminado)
        }
    }
}

/// Acceso cómodo al acento actual desde cualquier vista.
/// Se lee en cada render, así que reacciona al cambiar el ajuste.
enum AppTheme {
    /// Acento efectivo: respeta el modo "acento desde carátula" si está activo.
    static var accent: Color { ThemeManager.shared.resolvedAccent }

    /// ✅ Acento como UIColor: reemplaza los antiguos fallbacks
    /// `UIColor.systemPurple` hardcodeados (no respetaban el ajuste).
    static var accentUIColor: UIColor {
        if ThemeManager.shared.accentFromArtwork, let c = ThemeManager.shared.artworkAccentUIColor {
            return c
        }
        return UIColor(ThemeManager.shared.accent)
    }

    /// Normaliza un color extraído de una portada para que siempre sea
    /// legible como color de acento: saturación y brillo dentro de un
    /// rango que garantiza contraste sobre fondos claro/oscuro.
    /// Evita textos/botones invisibles cuando la portada es casi negra,
    /// blanca o desaturada.
    static func readableColor(from uiColor: UIColor) -> Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 1
        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return ThemeManager.shared.accent
        }

        // Portadas grises/negras/blancas: poca saturación → poco útil como acento
        guard saturation >= 0.12 && brightness >= 0.12 else {
            return ThemeManager.shared.accent
        }

        // En modo claro un color muy oscuro no contrasta contra sombras;
        // en oscuro un color muy claro compite con los textos primarios.
        // Rango objetivo 0.45–0.80 cubre ambos casos con buena legibilidad.
        let newSaturation = min(0.85, max(0.45, saturation))
        let newBrightness = min(0.80, max(0.45, brightness))

        return Color(uiColor: UIColor(
            hue: hue,
            saturation: newSaturation,
            brightness: newBrightness,
            alpha: 1.0
        ))
    }

    /// Versión directa desde un UIColor opcional (para dominantColor de álbumes)
    static func readableColor(from uiColor: UIColor?) -> Color {
        guard let uiColor else { return ThemeManager.shared.accent }
        return readableColor(from: uiColor)
    }

    // MARK: - Contraste inteligente (WCAG relativo)

    /// Luminancia relativa 0...1 del UIColor (fórmula WCAG).
    static func luminance(of uiColor: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0.5 }
        func linear(_ v: CGFloat) -> CGFloat {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Devuelve blanco o negro según contraste con el fondo dado
    /// (texto/borde siempre legible sobre el color de la portada).
    static func contrastingText(on uiColor: UIColor) -> Color {
        luminance(of: uiColor) > 0.5 ? Color.black : Color.white
    }
    static func contrastingText(on uiColor: UIColor?) -> Color {
        guard let uiColor else { return .white }
        return contrastingText(on: uiColor)
    }

    // MARK: - Extracción de color dominante (más vivo)

    /// Extrae el color más REPRESENTATIVO y vibrante de una portada:
    /// en vez del promedio (que era apagado/grisáceo), usa un histograma
    /// HSB y elige el bucket con mayor saturación×peso y brillo moderado.
    static func dominantColor(from artwork: UIImage) -> UIColor? {
        let size = CGSize(width: 48, height: 48)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        artwork.draw(in: CGRect(origin: .zero, size: size))
        guard let cgImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()

        let bytesPerRow = cgImage.bytesPerRow
        let width = cgImage.width
        let height = cgImage.height
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &data, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Histograma HSB: hue 0..23, sat 0..4, bright 0..4 (24*5*5 buckets)
        var buckets = [Float](repeating: 0, count: 24 * 5 * 5)
        for y in 0..<height {
            for x in 0..<width {
                let off = y * bytesPerRow + x * 4
                let r = CGFloat(data[off]) / 255
                let g = CGFloat(data[off + 1]) / 255
                let b = CGFloat(data[off + 2]) / 255
                let a = CGFloat(data[off + 3]) / 255
                guard a > 0.5 else { continue }
                let ui = UIColor(red: r, green: g, blue: b, alpha: 1)
                var h: CGFloat = 0
                var s: CGFloat = 0
                var br: CGFloat = 0
                var alpha: CGFloat = 0
                guard ui.getHue(&h, saturation: &s, brightness: &br, alpha: &alpha) else { continue }
                // Ignorar grises (poco útiles como acento)
                guard s >= 0.15 && br >= 0.15 else { continue }
                let hi = min(23, Int(h * 24))
                let si = min(4, Int(s * 5))
                let bi = min(4, Int(br * 5))
                // Peso: saturación² × distancia del brillo de 0.6 (colores vivos, no demasiado oscuros/claros)
                let weight = Float(s * s) * Float(1.0 - abs(br - 0.6) * 1.2)
                buckets[(bi * 5 + si) * 24 + hi] += max(weight, 0)
            }
        }

        guard let best = buckets.enumerated().max(by: { $0.element < $1.element }), best.element > 0 else { return nil }
        let idx = best.offset
        let hi = idx % 24
        let si = (idx / 24) % 5
        let bi = idx / (24 * 5)
        return UIColor(
            hue: (CGFloat(hi) + 0.5) / 24,
            saturation: (CGFloat(si) + 0.5) / 5,
            brightness: (CGFloat(bi) + 0.5) / 5,
            alpha: 1
        )
    }

    static func dominantColor(from uiColor: UIColor?) -> UIColor? {
        uiColor
    }
}
