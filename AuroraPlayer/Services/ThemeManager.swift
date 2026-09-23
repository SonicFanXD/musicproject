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
            // ✅ Dos colores: detectar secundario también (con caché: el
            // clustering recorre la portada otra vez y esto está en el hilo
            // principal)
            if let secondary = AppTheme.cachedSecondaryDominantColor(
                from: artwork,
                key: song.id.uuidString,
                primary: cached
            ) {
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
            let secondary = AppTheme.cachedSecondaryDominantColor(
                from: artwork,
                key: song.id.uuidString,
                primary: dominant
            )
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
        resolvedAccentGradient(opacity: 1)
    }

    /// ✅ Gradiente con opacidad aplicada a CADA color. Necesario porque en
    /// iOS 16 `LinearGradient.opacity(_:)` devuelve una View y no un ShapeStyle
    /// (no compila dentro de `.fill(...)`). El degradado es más tenue pero
    /// conserva el efecto de dos colores en fondos, chips y barras.
    func resolvedAccentGradient(opacity: Double) -> LinearGradient {
        if accentFromArtwork, let primary = artworkAccentColor, let secondary = artworkSecondaryColor {
            return LinearGradient(
                colors: [primary.opacity(opacity), secondary.opacity(opacity)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if accentFromArtwork, let c = artworkAccentColor {
            return LinearGradient(
                colors: [c.opacity(opacity), c.opacity(opacity * 0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [accent.opacity(opacity), accent.opacity(opacity * 0.4)],
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

    /// ✅ Variante con opacidad (para fondos, bordes y barras con alpha).
    static func accentGradient(opacity: Double) -> LinearGradient {
        ThemeManager.shared.resolvedAccentGradient(opacity: opacity)
    }

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

        // ✅ D2: umbrales de presencia. El piso de saturación sube de 0.15 a
        // 0.25 y el de brillo de 0.20 a 0.28, para que los colores pastel y
        // los casi negros no salgan apagados sobre la carátula. Los MÁXIMOS no
        // se tocan (>0.98 → 0.95 y >0.92 → 0.90): los colores ya vivos
        // conservan su identidad. Los valores de destino suben en la misma
        // proporción (0.20 → 0.30 y 0.25 → 0.33) para no crear el caso
        // inverso: con el destino viejo, una saturación de 0.24 habría BAJADO
        // a 0.20 al cruzar el umbral nuevo. El hue (sector de clustering) NO
        // se toca: esto solo reescala el color ya extraído.
        let newSaturation: CGFloat
        let newBrightness: CGFloat
        
        // Saturación: solo corregir si es muy baja (<0.25) o muy alta (>0.98)
        if saturation < 0.25 {
            newSaturation = 0.30
        } else if saturation > 0.98 {
            newSaturation = 0.95
        } else {
            newSaturation = saturation
        }
        
        // Brillo: solo corregir si es muy bajo (<0.28) o muy alto (>0.92)
        if brightness < 0.28 {
            newBrightness = 0.33
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
    static let artworkColorCache: NSCache<NSString, UIColor> = {
        let cache = NSCache<NSString, UIColor>()
        // ✅ B1: era la ÚNICA caché del proyecto sin tope (la de secundarios ya
        // lo tenía en 300 y la de miniaturas en 400 + 12 MB). Guarda un color
        // por canción/álbum/artista, así que en bibliotecas grandes crecía sin
        // límite hasta que iOS avisaba de memoria. Mismo valor que la caché de
        // secundarios, que almacena exactamente el mismo tipo de dato.
        cache.countLimit = 400
        return cache
    }()

    /// Wrapper con caché: usar SIEMPRE este desde las vistas (no dominantColor directo).
    static func cachedDominantColor(from artwork: UIImage, key: String) -> UIColor? {
        let nsKey = key as NSString
        if let cached = artworkColorCache.object(forKey: nsKey) { return cached }
        guard let color = dominantColor(from: artwork) else { return nil }
        artworkColorCache.setObject(color, forKey: nsKey)
        return color
    }

    /// ✅ Caché del SEGUNDO color: el clustering vuelve a recorrer la portada, así
    /// que se cachea igual que el primario (misma clave = id de canción/álbum).
    /// Solo se guardan aciertos: un `nil` (sin secundario) se recalcula, que es
    /// el caso barato (nunca hay gradiente que pintar).
    static let artworkSecondaryColorCache: NSCache<NSString, UIColor> = {
        let cache = NSCache<NSString, UIColor>()
        cache.countLimit = 300
        return cache
    }()

    /// Wrapper con caché del secundario.
    static func cachedSecondaryDominantColor(from artwork: UIImage, key: String, primary: UIColor) -> UIColor? {
        let nsKey = key as NSString
        if let cached = artworkSecondaryColorCache.object(forKey: nsKey) { return cached }
        guard let color = secondaryDominantColor(from: artwork, primary: primary) else { return nil }
        artworkSecondaryColorCache.setObject(color, forKey: nsKey)
        return color
    }

    // MARK: - Clustering de HUE (estilo Apple Music)

    /// ✅ Píxel de la portada ya convertido a HSB (hue en grados 0..<360).
    private struct HSBPixel {
        let hue: CGFloat
        let saturation: CGFloat
        let brightness: CGFloat
    }

    /// ✅ Un sector de tono (30°) con la suma de los píxeles que caen dentro.
    /// La media del tono usa vectores unitarios (media circular) para que los
    /// tonos que cruzan el 0° (rojos) no salgan desplazados.
    private struct HueSector {
        var count = 0
        var hueVectorX: CGFloat = 0
        var hueVectorY: CGFloat = 0
        var saturationSum: CGFloat = 0
        var brightnessSum: CGFloat = 0

        mutating func add(_ pixel: HSBPixel) {
            count += 1
            let radians = pixel.hue * .pi / 180
            hueVectorX += cos(radians)
            hueVectorY += sin(radians)
            saturationSum += pixel.saturation
            brightnessSum += pixel.brightness
        }

        /// Tono medio del sector en grados (0..<360).
        var averageHue: CGFloat {
            guard count > 0 else { return 0 }
            var degrees = atan2(hueVectorY, hueVectorX) * 180 / .pi
            if degrees < 0 { degrees += 360 }
            return degrees
        }

        /// Color medio (H medio, S medio, V medio) del sector.
        var averageColor: UIColor? {
            guard count > 0 else { return nil }
            return UIColor(
                hue: averageHue / 360,
                saturation: saturationSum / CGFloat(count),
                brightness: brightnessSum / CGFloat(count),
                alpha: 1
            )
        }
    }

    /// 12 sectores de 30°: agrupar por TONO, no por cubo RGB exacto.
    private static let hueSectorCount = 12
    private static let hueSectorWidth: CGFloat = 360 / CGFloat(hueSectorCount)
    /// ✅ Muestreo a 64×64: menos ruido y más rápido que a 80×80.
    private static let dominantSampleEdge: CGFloat = 64
    /// ✅ Mínimo de píxeles con color real para fiarse del clustering. Por debajo,
    /// la portada es prácticamente monocromática (blanco y negro, grises) y se
    /// delega en el histograma RGB clásico.
    private static let minimumColoredPixels = 100
    /// ✅ Separación mínima de tono entre primario y secundario.
    private static let minimumSecondaryHueDelta: CGFloat = 30

    /// ⚡ Algoritmo por clustering de hue (estilo Apple Music)
    /// Devuelve el color primario (sector de tono con más píxeles) y, si existe,
    /// el secundario (siguiente sector poblado con un tono a ≥30° del primario).
    /// nil si la portada no aporta suficiente color → el llamador usa el fallback.
    private static func clusteredAccentColors(from artwork: UIImage) -> (primary: UIColor, secondary: UIColor?)? {
        guard let pixels = coloredPixels(from: artwork) else { return nil }

        var sectors = [HueSector](repeating: HueSector(), count: hueSectorCount)
        for pixel in pixels {
            let index = min(hueSectorCount - 1, max(0, Int(pixel.hue / hueSectorWidth)))
            sectors[index].add(pixel)
        }

        // ✅ El sector con MÁS píxeles es el color dominante visual (un logo rojo
        // pequeño ya no gana a un fondo azul mayoritario: cada sector suma todos
        // sus píxeles, no un cubo RGB concreto).
        let ranked = sectors.enumerated().sorted { $0.element.count > $1.element.count }
        guard let winner = ranked.first, winner.element.count > 0,
              let primary = winner.element.averageColor else { return nil }

        let primaryHue = winner.element.averageHue
        var secondary: UIColor?
        for candidate in ranked.dropFirst() where candidate.element.count > 10 {
            guard let color = candidate.element.averageColor else { continue }
            if angularDistance(candidate.element.averageHue, primaryHue) >= minimumSecondaryHueDelta {
                secondary = color
                break
            }
        }

        return (primary, secondary)
    }

    /// ✅ Píxeles significativos de la portada (64×64) en HSB.
    /// FILTRO: se descartan los transparentes (alpha < 0.5), los casi negros
    /// (brillo < 0.10), los casi blancos (brillo > 0.95) y los grises
    /// (saturación < 0.10) — siempre presentes en cualquier portada y que
    /// ensucian el resultado.
    private static func coloredPixels(from artwork: UIImage) -> [HSBPixel]? {
        let size = CGSize(width: dominantSampleEdge, height: dominantSampleEdge)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        artwork.draw(in: CGRect(origin: .zero, size: size))
        guard let cgImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)

        // ✅ `withUnsafeMutableBytes` garantiza que el puntero que ve CoreGraphics
        // es el mismo buffer que leemos después (sin copias temporales).
        let drawn = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(
                    data: base, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var pixels: [HSBPixel] = []
        pixels.reserveCapacity(width * height)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                guard CGFloat(data[offset + 3]) / 255 >= 0.5 else { continue }

                let pixelColor = UIColor(
                    red: CGFloat(data[offset]) / 255,
                    green: CGFloat(data[offset + 1]) / 255,
                    blue: CGFloat(data[offset + 2]) / 255,
                    alpha: 1
                )
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                guard pixelColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil) else { continue }

                guard brightness >= 0.10, brightness <= 0.95, saturation >= 0.10 else { continue }
                pixels.append(HSBPixel(hue: hue * 360, saturation: saturation, brightness: brightness))
            }
        }

        guard pixels.count >= minimumColoredPixels else { return nil }
        return pixels
    }

    /// ✅ Distancia angular mínima entre dos tonos (0...180°).
    private static func angularDistance(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        let delta = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
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

    // MARK: - API pública de extracción

    /// ⚡ Algoritmo por clustering de hue (estilo Apple Music):
    /// 1. Portada reducida a 64×64 (menos ruido, más rápido).
    /// 2. Cada píxel se convierte a HSB y se filtran transparentes, casi negros,
    ///    casi blancos y grises.
    /// 3. Los píxeles restantes se agrupan por TONO en 12 sectores de 30° y el
    ///    sector con más píxeles da el color dominante visual.
    /// 4. Si no quedan 100 píxeles con color (portadas en blanco y negro o casi
    ///    planas) se usa el histograma RGB clásico como fallback.
    static func dominantColor(from artwork: UIImage) -> UIColor? {
        if let clustered = clusteredAccentColors(from: artwork) { return clustered.primary }
        return legacyDominantColor(from: artwork)
    }

    /// ✅ SISTEMA DOS COLORES: segundo sector poblado con un tono perceptualmente
    /// distinto (≥30°) del primario. nil si la portada es monocromática.
    static func secondaryDominantColor(from artwork: UIImage, primary: UIColor) -> UIColor? {
        if let clustered = clusteredAccentColors(from: artwork) { return clustered.secondary }
        return legacySecondaryDominantColor(from: artwork, primary: primary)
    }

    // MARK: - Fallback clásico (histograma RGB)
    /// Extrae el color más REPRESENTATIVO de una portada:
    /// ✅ SISTEMA DE MAYORÍA: cuantización RGB para encontrar el color más frecuente
    /// No usa promedio (puede ser sesgado), usa frecuencia de colores
    private static func legacyDominantColor(from artwork: UIImage) -> UIColor? {
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

    /// ✅ Fallback clásico del segundo color (histograma RGB): solo se usa con
    /// portadas sin color significativo, donde el clustering no tiene datos.
    private static func legacySecondaryDominantColor(from artwork: UIImage, primary: UIColor) -> UIColor? {
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
