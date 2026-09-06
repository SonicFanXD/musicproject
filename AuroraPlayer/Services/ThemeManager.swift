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

    // ✅ La caché de colores vive en AppTheme.artworkColorCache (compartida)

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
        if let cached = AppTheme.artworkColorCache.object(forKey: cacheKey) {
            artworkAccentUIColor = cached
            artworkAccentColor = Self.normalizeArtworkAccent(cached)
            applyGlobalUIKitTint()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let dominant = AppTheme.dominantColor(from: artwork)
            guard let dominant else { return }
            AppTheme.artworkColorCache.setObject(dominant, forKey: cacheKey)
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

        // ✅ FIX carátulas grises/oscuras: antes se devolvía el acento por
        // defecto cuando la saturación/brillo eran bajos → portadas negras o
        // grises "no se detectaban". Ahora conservamos el MATIZ real de la
        // carátula y solo elevamos saturación/brillo al rango legible.
        let newSaturation = min(0.85, max(0.40, saturation))
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

    // ✅ Caché global COMPARTIDA: NowPlaying, AlbumDetail, ArtistDetail y
    // ThemeManager extraen de las MISMAS carátulas → un solo cálculo por arte.
    // Clave = id de canción/álbum/artista. NSCache se limpia solo bajo presión.
    static let artworkColorCache = NSCache<NSString, UIColor>()

    /// Wrapper con caché: usar SIEMPRE este desde las vistas (no dominantColor directo).
    static func cachedDominantColor(from artwork: UIImage, key: String) -> UIColor? {
        let nsKey = key as NSString
        if let cached = artworkColorCache.object(forKey: nsKey) { return cached }
        guard let color = dominantColor(from: artwork) else { return nil }
        artworkColorCache.setObject(color, forKey: nsKey)
        return color
    }

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

        // Histograma HSB FINO: hue 0..35, sat 0..5, bright 0..5 (36*6*6 buckets)
        // ✅ PERF: HSV calculado inline (antes: 1 alloc de UIColor + getHue por
        // píxel = ~2300 allocs por carátula durante la indexación).
        // ✅ PRECISIÓN: además del peso por bucket, se acumula el hue como
        // vector (cos/sin) y sat/br ponderados → el color final es el PROMEDIO
        // EXACTO del cluster ganador, no el centro tosco del bucket.
        let hueBins = 36, satBins = 6, brBins = 6
        let bucketCount = hueBins * satBins * brBins
        var buckets = [Float](repeating: 0, count: bucketCount)
        var hueX = [Float](repeating: 0, count: bucketCount)
        var hueY = [Float](repeating: 0, count: bucketCount)
        var satSum = [Float](repeating: 0, count: bucketCount)
        var brSum = [Float](repeating: 0, count: bucketCount)
        var totalR: Float = 0, totalG: Float = 0, totalB: Float = 0, totalCount: Float = 0
        for y in 0..<height {
            for x in 0..<width {
                let off = y * bytesPerRow + x * 4
                let r = Float(data[off]) / 255
                let g = Float(data[off + 1]) / 255
                let b = Float(data[off + 2]) / 255
                let a = Float(data[off + 3]) / 255
                guard a > 0.5 else { continue }

                totalR += r; totalG += g; totalB += b; totalCount += 1

                // HSV inline (equivalente a getHue, sin allocs)
                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let delta = maxC - minC
                let br = maxC
                let s: Float = maxC == 0 ? 0 : delta / maxC
                // ✅ FIX carátulas negras/grises: antes se descartaban con
                // s>=0.15 && br>=0.15 → portadas oscuras devolvían nil y caían
                // al acento por defecto. Ahora se aceptan con filtros mínimos
                // (solo descartamos píxeles casi-puros blanco/negro sin matiz).
                guard s >= 0.03, br >= 0.04 else { continue }
                var h: Float = 0
                if delta > 0 {
                    if maxC == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
                    else if maxC == g { h = (b - r) / delta + 2 }
                    else { h = (r - g) / delta + 4 }
                    h /= 6
                    if h < 0 { h += 1 }
                }
                let hi = min(hueBins - 1, Int(h * Float(hueBins)))
                let si = min(satBins - 1, Int(s * Float(satBins)))
                let bi = min(brBins - 1, Int(br * Float(brBins)))
                // Peso: saturación² × proximidad del brillo a 0.62 (colores vivos,
                // no demasiado oscuros/claros). Factor 1.3 escala la campana.
                let weight = s * s * max(0, 1.15 - abs(br - 0.62) * 1.3)
                let w = max(weight, 0.0001)
                let idx = (bi * satBins + si) * hueBins + hi
                buckets[idx] += w
                let angle = Float(h * 2 * .pi)
                hueX[idx] += cos(angle) * w
                hueY[idx] += sin(angle) * w
                satSum[idx] += s * w
                brSum[idx] += br * w
            }
        }

        if let best = buckets.enumerated().max(by: { $0.element < $1.element }), best.element > 0 {
            let idx = best.offset
            let w = best.element
            // ✅ Color EXACTO del cluster: hue vía promedio vectorial (sin saltos
            // en el wrap 0/360), sat y br como medias ponderadas reales.
            var hue = CGFloat(atan2f(hueY[idx], hueX[idx]) / (2 * .pi))
            if hue < 0 { hue += 1 }
            let saturation = CGFloat(min(0.95, max(0.08, satSum[idx] / w)))
            let brightness = CGFloat(min(0.92, max(0.10, brSum[idx] / w)))
            return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        }
        // ✅ Fallback: promedio real de la carátula (p. ej. portada monocromática
        // sin matiz). `readableColor` lo normaliza para legibilidad.
        guard totalCount > 0 else { return nil }
        return UIColor(
            red: CGFloat(totalR / totalCount),
            green: CGFloat(totalG / totalCount),
            blue: CGFloat(totalB / totalCount),
            alpha: 1
        )
    }

    static func dominantColor(from uiColor: UIColor?) -> UIColor? {
        uiColor
    }
}
