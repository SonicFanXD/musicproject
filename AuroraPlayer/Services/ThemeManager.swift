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
            AppLog.info(.settings, "Acento desde carátula: \(accentFromArtwork ? "activado" : "desactivado")")
            if accentFromArtwork {
                // ✅ FIX: al ACTIVAR el toggle, re-extraer al instante el color de
                // la última canción. Sin esto, artworkAccentColor quedaba nil y
                // toda la interfaz seguía con el acento manual hasta cambiar de
                // canción (que era el único punto donde se llamaba la extracción).
                updateArtworkAccent(from: latestSongForAccent)
            } else {
                artworkAccentColor = nil
                artworkAccentUIColor = nil
            }
            applyGlobalUIKitTint()
        }
    }

    // ✅ Última canción procesada: se guarda SIEMPRE (aunque el modo esté
    // apagado) para poder extraer el color al instante si el usuario activa
    // el toggle más adelante, sin depender del cambio de canción.
    private var latestSongForAccent: Song?

    @Published private(set) var artworkAccentColor: Color?
    @Published private(set) var artworkAccentUIColor: UIColor?
    // ✅ SISTEMA DOS COLORES: segundo color dominante para gradiente premium
    @Published private(set) var artworkSecondaryColor: Color?
    @Published private(set) var artworkSecondaryUIColor: UIColor?

    // ✅ La caché de colores vive en AppTheme.artworkColorCache (compartida)

    /// Extrae el color dominante de la portada en segundo plano y lo publica.
    /// Llamado por AudioEngine cada vez que cambia la canción actual.
    func updateArtworkAccent(from song: Song?) {
        // ✅ Guardar la canción SIEMPRE (modo activo o no) para poder resolver
        // el color al instante si se activa el toggle desde Settings.
        if let song { latestSongForAccent = song }
        guard accentFromArtwork else { return }
        resolveArtworkAccent(from: latestSongForAccent)
    }

    /// Resuelve y publica el color dominante de la portada de una canción.
    private func resolveArtworkAccent(from song: Song?) {
        guard let song, let artwork = song.artwork else {
            artworkAccentColor = nil
            artworkAccentUIColor = nil
            artworkSecondaryColor = nil
            artworkSecondaryUIColor = nil
            return
        }
        let cacheKey = song.id.uuidString as NSString
        if let cached = AppTheme.artworkColorCache.object(forKey: cacheKey) {
            artworkAccentUIColor = cached
            artworkAccentColor = Self.normalizeArtworkAccent(cached)
            // ✅ Dos colores: detectar secundario también
            if let secondary = AppTheme.secondaryDominantColor(from: artwork, primary: cached) {
                artworkSecondaryUIColor = secondary
                artworkSecondaryColor = Self.normalizeArtworkAccent(secondary)
                AppLog.info(.playback, "✅ PALETA DOS COLORES: secundario encontrado (cache)")
            } else {
                AppLog.info(.playback, "⚠️ PALETA DOS COLORES: sin secundario (cache)")
            }
            applyGlobalUIKitTint()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let dominant = AppTheme.dominantColor(from: artwork)
            guard let dominant else { return }
            AppTheme.artworkColorCache.setObject(dominant, forKey: cacheKey)
            let secondary = AppTheme.secondaryDominantColor(from: artwork, primary: dominant)
            DispatchQueue.main.async {
                guard let self, self.accentFromArtwork else { return }
                self.artworkAccentUIColor = dominant
                self.artworkAccentColor = Self.normalizeArtworkAccent(dominant)
                if let secondary = secondary {
                    self.artworkSecondaryUIColor = secondary
                    self.artworkSecondaryColor = Self.normalizeArtworkAccent(secondary)
                    AppLog.info(.playback, "✅ PALETA DOS COLORES: secundario encontrado (nuevo)")
                } else {
                    AppLog.info(.playback, "⚠️ PALETA DOS COLORES: sin secundario (nuevo)")
                }
                self.applyGlobalUIKitTint()
            }
        }
    }

    /// ✅ Gradiente de dos colores universal para todos los elementos
    /// Si hay dos colores de carátula, usa gradiente con más contraste
    var resolvedAccentGradient: LinearGradient {
        if accentFromArtwork, let primary = artworkAccentColor, let secondary = artworkSecondaryColor {
            return LinearGradient(
                colors: [primary, secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if accentFromArtwork, let c = artworkAccentColor {
            return LinearGradient(
                colors: [c, c.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [accent, accent.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Color final efectivo del acento: usa el color primario sólido
    /// para compatibilidad con vistas que no soportan gradientes
    var resolvedAccent: Color {
        if accentFromArtwork, let c = artworkAccentColor {
            return c
        }
        return accent
    }

    private static func normalizeArtworkAccent(_ uiColor: UIColor) -> Color {
        AppTheme.readableColor(from: uiColor)
    }

    @Published var accentIndex: Int {
        didSet {
            UserDefaults.standard.set(accentIndex, forKey: Self.key)
            AppLog.info(.settings, "Color de acento cambiado (índice \(accentIndex))")
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
        // ✅ MIGRACIÓN: si nunca se configuró el acento desde carátula,
        // heredar el valor del antiguo toggle "dynamicColor" (ajuste único
        // para todos los entornos: NowPlaying, álbumes, artistas, tint global)
        if UserDefaults.standard.object(forKey: Self.artworkAccentKey) == nil {
            let legacy = UserDefaults.standard.object(forKey: "com.aurora.dynamicColor")
            accentFromArtwork = (legacy as? Bool) ?? false
            UserDefaults.standard.set(accentFromArtwork, forKey: Self.artworkAccentKey)
        } else {
            accentFromArtwork = UserDefaults.standard.bool(forKey: Self.artworkAccentKey)
        }
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
    
    /// ✅ Gradiente de dos colores universal para elementos que lo soportan
    static var accentGradient: LinearGradient { ThemeManager.shared.resolvedAccentGradient }

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

        // ✅ MEJORA: Rangos más conservadores para respetar el color original.
        // Solo se corrige cuando es estrictamente necesario para legibilidad.
        // Esto permite que colores pastel, oscuros o neón mantengan su identidad.
        let newSaturation: CGFloat
        let newBrightness: CGFloat
        
        // Saturación: solo corregir si es muy baja (<0.15) o muy alta (>0.98)
        if saturation < 0.15 {
            newSaturation = 0.20
        } else if saturation > 0.98 {
            newSaturation = 0.95
        } else {
            newSaturation = saturation
        }
        
        // Brillo: solo corregir si es muy bajo (<0.20) o muy alto (>0.92)
        if brightness < 0.20 {
            newBrightness = 0.25
        } else if brightness > 0.92 {
            newBrightness = 0.90
        } else {
            newBrightness = brightness
        }

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

    /// Devuelve siempre blanco para mantener consistencia visual
    /// (el usuario prefiere texto blanco en lugar de contraste automático).
    static func contrastingText(on uiColor: UIColor) -> Color {
        .white
    }
    static func contrastingText(on uiColor: UIColor?) -> Color {
        .white
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

    // MARK: - Miniaturas de carátula (caché)

    // ✅ `preparingThumbnail(of:)` decodifica la portada COMPLETA (768px ≈ 2.4MB)
    // y devuelve un UIImage NUEVO en cada llamada. En filas que se re-renderizan
    // (scroll, cambios de estado del motor) eso es CPU y churn de memoria en A11.
    // Clave = instancia de la carátula (`Song.artwork` ya devuelve la MISMA
    // instancia cacheada por id de canción) + tamaño en píxeles.
    static let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // ✅ ANTI-JETSAM (iPhone 8 Plus / 3GB): tope por MEMORIA, no por conteo.
        // 12MB ≈ 330 miniaturas de 96px o ≈ 33 de 300px; las carátulas completas
        // nunca entran aquí (siguen en Song.artworkCache).
        cache.countLimit = 400
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    /// Miniatura cacheada de una carátula. Mismo resultado que
    /// `artwork.preparingThumbnail(of:)` (y mismo fallback a la original),
    /// pero sin recomputarla en cada render de fila.
    static func thumbnail(from artwork: UIImage, size: CGSize) -> UIImage {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let key = "\(ObjectIdentifier(artwork).hashValue)-\(width)x\(height)" as NSString

        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let thumbnail = artwork.preparingThumbnail(of: CGSize(width: width, height: height)) else {
            return artwork
        }
        // Costo = bytes del bitmap (RGBA) para que NSCache expulse por RAM real.
        thumbnailCache.setObject(thumbnail, forKey: key, cost: width * height * 4)
        return thumbnail
    }

    /// Extrae el color más REPRESENTATIVO de una portada:
    /// ✅ SISTEMA DE MAYORÍA: cuantización RGB para encontrar el color más frecuente
    /// No usa promedio (puede ser sesgado), usa frecuencia de colores
    static func dominantColor(from artwork: UIImage) -> UIColor? {
        let size = CGSize(width: 80, height: 80)
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

        // ✅ Sistema de cuantización para encontrar el color más frecuente
        let levels = 8 // 8 niveles por canal = 512 buckets
        var colorBuckets = [Int](repeating: 0, count: levels * levels * levels)
        var bucketSums: [[Float]] = Array(repeating: Array(repeating: 0, count: 3), count: levels * levels * levels)

        for y in 0..<height {
            for x in 0..<width {
                let off = y * bytesPerRow + x * 4
                let r = Float(data[off]) / 255
                let g = Float(data[off + 1]) / 255
                let b = Float(data[off + 2]) / 255
                let a = Float(data[off + 3]) / 255
                guard a > 0.6 else { continue }

                // Cuantizar RGB
                let ri = min(levels - 1, Int(r * Float(levels)))
                let gi = min(levels - 1, Int(g * Float(levels)))
                let bi = min(levels - 1, Int(b * Float(levels)))
                let idx = (bi * levels + gi) * levels + ri

                colorBuckets[idx] += 1
                bucketSums[idx][0] += r
                bucketSums[idx][1] += g
                bucketSums[idx][2] += b
            }
        }

        // ✅ Encontrar el bucket con más píxeles (color de mayoría)
        var maxCount = 0
        var bestIdx = 0
        for i in 0..<colorBuckets.count {
            if colorBuckets[i] > maxCount {
                maxCount = colorBuckets[i]
                bestIdx = i
            }
        }

        guard maxCount > 0 else { return nil }

        // ✅ Promedio del bucket ganador para precisión
        let count = Float(colorBuckets[bestIdx])
        let r = bucketSums[bestIdx][0] / count
        let g = bucketSums[bestIdx][1] / count
        let b = bucketSums[bestIdx][2] / count

        return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }

    /// ✅ SISTEMA DOS COLORES: extrae el segundo color dominante
    /// Usa el mismo sistema de frecuencia para encontrar el segundo más común
    static func secondaryDominantColor(from artwork: UIImage, primary: UIColor) -> UIColor? {
        let size = CGSize(width: 80, height: 80)
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

        // ✅ Sistema de cuantización igual que dominantColor
        let levels = 8
        var colorBuckets = [Int](repeating: 0, count: levels * levels * levels)
        var bucketSums: [[Float]] = Array(repeating: Array(repeating: 0, count: 3), count: levels * levels * levels)

        for y in 0..<height {
            for x in 0..<width {
                let off = y * bytesPerRow + x * 4
                let r = Float(data[off]) / 255
                let g = Float(data[off + 1]) / 255
                let b = Float(data[off + 2]) / 255
                let a = Float(data[off + 3]) / 255
                guard a > 0.6 else { continue }

                let ri = min(levels - 1, Int(r * Float(levels)))
                let gi = min(levels - 1, Int(g * Float(levels)))
                let bi = min(levels - 1, Int(b * Float(levels)))
                let idx = (bi * levels + gi) * levels + ri

                colorBuckets[idx] += 1
                bucketSums[idx][0] += r
                bucketSums[idx][1] += g
                bucketSums[idx][2] += b
            }
        }

        // ✅ Obtener RGB del primario para evitar colores similares
        var primaryR: CGFloat = 0, primaryG: CGFloat = 0, primaryB: CGFloat = 0
        primary.getRed(&primaryR, green: &primaryG, blue: &primaryB, alpha: nil)

        // ✅ Encontrar el segundo bucket más frecuente que sea diferente del primario
        let sortedBuckets = colorBuckets.enumerated().sorted { $0.element > $1.element }
        for (idx, count) in sortedBuckets where count > 10 {
            let r = bucketSums[idx][0] / Float(count)
            let g = bucketSums[idx][1] / Float(count)
            let b = bucketSums[idx][2] / Float(count)

            // ✅ Verificar si es suficientemente diferente del primario
            let diff = abs(r - Float(primaryR)) + abs(g - Float(primaryG)) + abs(b - Float(primaryB))
            if diff > 0.15 { // ✅ CRÍTICO - PALETA DOS COLORES: reducido de 0.3 a 0.15
                // para permitir más secundarios. El umbral anterior era muy estricto
                // y muchas carátulas no tenían un secundario lo suficientemente diferente,
                // causando que el gradiente de dos colores nunca se aplicara.
                return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
            }
        }

        return nil
    }

    static func dominantColor(from uiColor: UIColor?) -> UIColor? {
        uiColor
    }
}
