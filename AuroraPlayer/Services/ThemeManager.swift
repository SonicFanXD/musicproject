import SwiftUI
import Combine
import UIKit       // explícito: UITraitCollection (escala del dispositivo para las miniaturas)
import CoreImage   // fondo de carátula pre-difuminado (framework de Apple, sin dependencias)

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
        // 12MB ≈ 150 miniaturas de 144px (fila de 48pt @3x) o ≈ 8 de 600px
        // (portada hero de álbum @3x); las carátulas completas nunca entran aquí
        // (siguen en Song.artworkCache).
        cache.countLimit = 400
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    /// Escala de píxeles del dispositivo para rasterizar miniaturas.
    /// En iOS es 2x (iPhone no-Plus, iPad) o 3x (iPhone Plus / Pro).
    /// - `UITraitCollection.current` es la vía NO deprecada (`UIScreen.main`
    ///   está obsoleto en iOS 16). Durante el `body` de una vista SwiftUI
    ///   devuelve la escala real de la pantalla.
    /// - Si por el contexto de llamada (funciones libres de lista, body fuera
    ///   de un ámbito de traits) llegara un valor no utilizable, se asume 3x:
    ///   pedir de MÁS cuesta unos KB; pedir de MENOS se ve suave al ampliar.
    private static var thumbnailScale: CGFloat {
        let traitScale = UITraitCollection.current.displayScale
        return traitScale >= 2 ? traitScale : 3
    }

    /// Miniatura cacheada de una carátula. Mismo resultado que
    /// `artwork.preparingThumbnail(of:)` (y mismo fallback a la original),
    /// pero sin recomputarla en cada render de fila.
    /// - Parameter size: tamaño en PUNTOS que ocupa la carátula en pantalla
    ///   (NO píxeles). El helper multiplica por la escala del dispositivo para
    ///   que el bitmap tenga exactamente los píxeles que se van a dibujar:
    ///   ni uno menos (ampliar se ve suave — p. ej. pedir 96 px para una fila
    ///   de 48 pt en un iPhone Plus, que es 3x y necesita 144 px) ni uno más
    ///   (RAM extra en cada fila del scroll).
    /// - Parameter scale: escala explícita (por defecto, la del dispositivo).
    static func thumbnail(from artwork: UIImage, size: CGSize, scale: CGFloat? = nil) -> UIImage {
        let deviceScale = scale ?? thumbnailScale
        let width = max(1, Int((size.width * deviceScale).rounded(.up)))
        let height = max(1, Int((size.height * deviceScale).rounded(.up)))
        let key = "\(ObjectIdentifier(artwork).hashValue)-\(width)x\(height)" as NSString

        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let thumbnail = artwork.preparingThumbnail(of: CGSize(width: width, height: height)) else {
            return artwork
        }
        // Costo = bytes del bitmap (RGBA) para que NSCache expulse por RAM real.
        thumbnailCache.setObject(thumbnail, forKey: key, cost: width * height * 4)
        return thumbnail
    }

    // MARK: - Fondo de carátula PRE-DIFUMINADO (identidad estilo Apple Music)

    /// ✅ UN `CIContext` para toda la app. Crear uno por llamada es de las
    /// operaciones más caras de Core Image (compila el kernel y prepara el
    /// contexto de GPU); reutilizarlo hace que el desenfoque cueste milisegundos.
    private static let filterContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Caché del fondo difuminado por canción. Bastan 4 entradas (la actual y las
    /// de los saltos inmediatos: anterior/siguiente/repetir) y el tope de memoria
    /// evita retener bitmaps que ya no se usan. `NSCache` se vacía solo bajo
    /// presión de memoria, que es exactamente lo que queremos en el A11.
    static let blurredArtworkCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 4
        cache.totalCostLimit = 6 * 1024 * 1024
        return cache
    }()

    /// Fondo ya calculado para esa canción (nil mientras no exista).
    static func cachedBlurredArtwork(key: String) -> UIImage? {
        blurredArtworkCache.object(forKey: key as NSString)
    }

    /// Difumina y OSCURECE la carátula UNA vez por canción. Pensado para llamarse
    /// SIEMPRE desde un hilo de fondo (`DispatchQueue.global(qos: .userInitiated)`):
    /// Core Image no toca el hilo principal y el resultado se guarda en caché, así
    /// que durante la reproducción el coste en CPU/GPU es 0 — la vista solo sube
    /// una textura ya lista.
    ///
    /// Pipeline (deliberadamente baratísimo: se trabaja sobre ~320px, no sobre la
    /// carátula de 768px, porque el desenfoque destruye el detalle de todos modos):
    /// 1. Reducción a un cuadrado de `edge` px (recorte centrado, sin ampliar nunca).
    /// 2. `CIGaussianBlur` con un radio proporcional al tamaño reducido.
    /// 3. `CIExposureAdjust`: oscurecido MULTIPLICATIVO (no aditivo). Es el velo
    ///    del diseño clásico — la carátula al `opacity(0.45)` sobre fondo oscuro —
    ///    pero horneado en el bitmap: así el texto blanco de NowPlaying se lee
    ///    sobre CUALQUIER portada (incluida una blanca) sin pagar un velo extra
    ///    por frame. Al ser multiplicativo, las portadas oscuras no se convierten
    ///    en un rectángulo negro: conservan su color.
    ///    El valor por defecto `-1.15 EV` **no es arbitrario**: 2^-1.15 = 0.45,
    ///    el mismo brillo efectivo que tenía el `opacity(0.45)` original sobre el
    ///    fondo oscuro de la ventana. Es la identidad de siempre, calculada una vez.
    /// 4. `CIColorControls`: un poco de saturación, porque el oscurecido apaga el
    ///    color y el fondo tiene que seguir siendo "el de la canción".
    /// - Parameter edge: lado del cuadrado de trabajo en píxeles.
    /// - Returns: `nil` si la carátula no es convertible (nunca se inventa un fondo).
    static func blurredArtwork(from artwork: UIImage,
                               key: String,
                               edge: CGFloat = 320,
                               radius: CGFloat = 18,
                               exposure: Float = -1.15) -> UIImage? {
        if let cached = blurredArtworkCache.object(forKey: key as NSString) { return cached }
        guard let source = CIImage(image: artwork) else { return nil }

        // 1) Normalizar el origen (algunas carátulas llegan con extent desplazado)
        //    y reducir sin AMPLIAR: si la portada ya es pequeña, se queda igual.
        let extent = source.extent
        guard extent.width >= 1, extent.height >= 1 else { return nil }
        let normalized = source.transformed(
            by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
        )
        let longest = max(normalized.extent.width, normalized.extent.height)
        let scale = min(1, edge / longest)
        let reduced = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // 2) Recorte CENTRADO al cuadrado: el fondo cubre la pantalla con
        //    `scaledToFill`, así que el encuadre tiene que ser el mismo.
        let side = min(reduced.extent.width, reduced.extent.height)
        guard side >= 1 else { return nil }
        let square = reduced.cropped(to: CGRect(
            x: reduced.extent.midX - side / 2,
            y: reduced.extent.midY - side / 2,
            width: side,
            height: side
        ))

        // 3) Gaussiano. El radio va en píxeles de la imagen REDUCIDA: al
        //    estirarse a pantalla completa el desenfoque aparente equivale al
        //    radio × (ancho de pantalla / lado reducido), del orden del
        //    `blur(radius: 25)` del diseño original.
        //
        //    ⚠️ `clampedToExtent()` ANTES de difuminar es imprescindible: el
        //    gaussiano muestrea fuera de la imagen y, sin clamp, los píxeles de
        //    fuera son TRANSPARENTES → los bordes del cuadrado se desvanecen a
        //    negro y, al estirar el fondo a pantalla completa, eso se ve como
        //    franjas oscuras arriba y abajo (el `+60` del diseño antiguo era el
        //    parche de aquel bug). Con el clamp, Core Image repite el píxel del
        //    borde y el recorte queda limpio de esquina a esquina.
        let edgeClamped = square.clampedToExtent()
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(edgeClamped, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let blurred = blurFilter.outputImage else { return nil }

        // 4) Velo horneado + saturación.
        guard let exposureFilter = CIFilter(name: "CIExposureAdjust") else { return nil }
        exposureFilter.setValue(blurred, forKey: kCIInputImageKey)
        exposureFilter.setValue(exposure, forKey: kCIInputEVKey)
        guard let darkened = exposureFilter.outputImage else { return nil }

        guard let colorFilter = CIFilter(name: "CIColorControls") else { return nil }
        colorFilter.setValue(darkened, forKey: kCIInputImageKey)
        colorFilter.setValue(1.18, forKey: kCIInputSaturationKey)
        colorFilter.setValue(1.0, forKey: kCIInputContrastKey)
        colorFilter.setValue(0.0, forKey: kCIInputBrightnessKey)
        guard let final = colorFilter.outputImage else { return nil }

        // 5) Rasterizar SOLO el cuadrado (el blur expande el extent y el clamp lo
        //    hace infinito; pedir esa ROI concreta hace que Core Image calcule
        //    únicamente esos píxeles, que es lo que abarata el proceso).
        guard let cgImage = filterContext.createCGImage(final, from: square.extent) else { return nil }
        let result = UIImage(cgImage: cgImage)
        blurredArtworkCache.setObject(result, forKey: key as NSString,
                                      cost: cgImage.width * cgImage.height * 4)
        return result
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
