import SwiftUI
import Combine
import CryptoKit

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
        // ✅ PUNTO ÚNICO: primario y secundario salen del MISMO par resuelto
        // (una sola pasada de clustering) y se cachean JUNTOS bajo la huella
        // de la imagen. Ni la lectura ni las claves dependen del id de la
        // canción: la misma carátula comparte sus colores en toda la app.
        if let cached = AppTheme.cachedAccentPair(for: artwork) {
            artworkAccentUIColor = cached.primary
            artworkAccentColor = Self.normalizeArtworkAccent(cached.primary)
            if let secondary = cached.secondary {
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
            guard let pair = AppTheme.resolvedAccentPair(from: artwork) else { return }
            AppTheme.cacheAccentPair(pair, for: artwork)
            DispatchQueue.main.async {
                guard let self, self.accentFromArtwork else { return }
                self.artworkAccentUIColor = pair.primary
                self.artworkAccentColor = Self.normalizeArtworkAccent(pair.primary)
                if let secondary = pair.secondary {
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
            // ✅ CAUSA RAÍZ del morado por defecto: en una instalación limpia
            // (sin legacy "dynamicColor") el modo quedaba APAGADO y
            // resolveArtworkAccent() ni siquiera se ejecutaba → toda la app
            // mostraba el acento manual (morado, índice 0) con CUALQUIER
            // portada y con cualquier heurística. El flag accentHeuristicV2
            // solo elige el ALGORITMO, no la compuerta. El acento desde
            // carátula es el comportamiento insignia: una instalación nueva
            // ahora lo activa por defecto (apagable en Ajustes; el reset de
            // ajustes sigue dejándolo en manual).
            accentFromArtwork = (legacy as? Bool) ?? true
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
    // Clave = huella de imagen (accentCacheKey(for:)), NUNCA id de canción /
    // álbum / artista: la misma carátula comparte sus colores tenga el origen
    // que tenga. NSCache se limpia solo bajo presión.
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

    /// ✅ HUELLA DE IMAGEN: clave estable de caché para una carátula.
    /// ✅ FIX portadas idénticas: antes era ObjectIdentifier (identidad del
    /// objeto) + tamaño. Dos canciones con los MISMOS bytes de portada pero
    /// instancias UIImage distintas tenían claves distintas → cálculo duplicado
    /// y resultados que podían divergir. Ahora: SHA256 de los bytes PNG
    /// renderizables (CryptoKit, framework del sistema, sin dependencias) +
    /// tamaño — huella del CONTENIDO, estable entre ejecuciones (el Hasher de
    /// Data.hashValue NO lo es: queda descartado como clave) y compartida por
    /// cualquier instancia nacida de los mismos bytes. Nada de ids de canción.
    /// pngData() da bytes canónicos de la imagen ya decodificada (misma
    /// instancia → mismos bytes garantizados). Sin datos renderizables:
    /// fallback por tamaño (caso degenerado). La caché de MINIATURAS (L995)
    /// no se toca: ahí el ObjectIdentifier es correcto porque comparte la
    /// instancia renderizada.
    static func accentCacheKey(for artwork: UIImage) -> String {
        let sizeSuffix = "\(Int(artwork.size.width.rounded()))x\(Int(artwork.size.height.rounded()))"
        guard let data = artwork.pngData(), !data.isEmpty else {
            return "size-\(sizeSuffix)"
        }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha-\(hex.prefix(32))-\(sizeSuffix)"
    }

    /// ✅ Lee el PAR (primario, secundario) cacheado bajo la huella de la
    /// imagen. `nil` si aún no está cacheado — NO recalcula: el cálculo es
    /// una sola pasada (`resolvedAccentPair`) y se guarda con `cacheAccentPair`.
    /// `artworkSecondaryColorCache` solo guarda aciertos, así que un
    /// `secondary == nil` aquí significa "calculado y sin secundario" (mono),
    /// nunca "pendiente de calcular".
    static func cachedAccentPair(for artwork: UIImage) -> (primary: UIColor, secondary: UIColor?)? {
        let key = accentCacheKey(for: artwork) as NSString
        guard let primary = artworkColorCache.object(forKey: key) else { return nil }
        return (primary, artworkSecondaryColorCache.object(forKey: key))
    }

    /// ✅ Guarda el par completo bajo la huella de la imagen. Único escritor
    /// de las dos cachés de acento → primario y secundario SIEMPRE coherentes
    /// (misma pasada de clustering, misma clave).
    static func cacheAccentPair(_ pair: (primary: UIColor, secondary: UIColor?), for artwork: UIImage) {
        let key = accentCacheKey(for: artwork) as NSString
        artworkColorCache.setObject(pair.primary, forKey: key)
        if let secondary = pair.secondary {
            artworkSecondaryColorCache.setObject(secondary, forKey: key)
        }
    }

    /// ✅ Caché del SEGUNDO color: el clustering vuelve a recorrer la portada, así
    /// que se cachea igual que el primario (misma clave = huella de imagen).
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
    /// `centralityWeight` = 1 + (1 - distancia normalizada al centro) × boost:
    /// pondera el ranking de la ruta HSB (y también el de la ruta Oklab).
    private struct HSBPixel {
        let hue: CGFloat
        let saturation: CGFloat
        let brightness: CGFloat
        let centralityWeight: CGFloat
    }

    /// ✅ Un sector de tono (30°) con la suma de los píxeles que caen dentro.
    /// La media del tono usa vectores unitarios (media circular) para que los
    /// tonos que cruzan el 0° (rojos) no salgan desplazados.
    private struct HueSector {
        var count = 0
        /// ✅ Suma de peso de centralidad × saturación de sus píxeles: criterio
        /// de ranking FIJO de la ruta HSB (el flag com.aurora.accentHeuristicV2
        /// ya no alterna el conteo: ahora selecciona HSB (OFF) vs Oklab (ON)).
        var weightedScore: CGFloat = 0
        var hueVectorX: CGFloat = 0
        var hueVectorY: CGFloat = 0
        var saturationSum: CGFloat = 0
        var brightnessSum: CGFloat = 0

        mutating func add(_ pixel: HSBPixel) {
            count += 1
            weightedScore += pixel.centralityWeight * pixel.saturation
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

    /// ✅ SELECTOR de heurística de acento: `false` → ruta HSB (comportamiento
    /// histórico, píxel a píxel); `true` → clustering perceptual en Oklab/OKLCH.
    /// ✅ FIX desincronía con el toggle: la clave AUSENTE cuenta como ON (V2 por
    /// defecto). Antes leía bool(forKey:) = false y el toggle de Ajustes
    /// (@AppStorage con default true) mostraba ON mientras el motor usaba HSB —
    /// la misma clase de mentira visual que el morado. Reset de ajustes borra
    /// la clave → vuelve a ON, igual que el default del @AppStorage.
    static var accentHeuristicV2Enabled: Bool {
        if UserDefaults.standard.object(forKey: accentHeuristicV2FlagKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: accentHeuristicV2FlagKey)
    }
    static let accentHeuristicV2FlagKey = "com.aurora.accentHeuristicV2"
    /// ✅ v2: peso extra de los píxeles cercanos al centro. 0.5 = un píxel del
    /// centro llega a valer 1.5× uno de la esquina. Constante de calibración.
    private static let accentCentralityBoost: CGFloat = 0.5

    /// ⚡ Algoritmo por clustering de hue (estilo Apple Music)
    /// Devuelve el color primario (sector de tono con más píxeles) y, si existe,
    /// el secundario (siguiente sector poblado con un tono a ≥30° del primario).
    /// nil si la portada no aporta suficiente color → el llamador usa el fallback.
    private static func clusteredAccentColors(from artwork: UIImage) -> (primary: UIColor, secondary: UIColor?)? {
        // ✅ com.aurora.accentHeuristicV2 = true → clustering en Oklab (perceptual).
        // false o clave ausente → ruta HSB original SIN CAMBIOS (los píxeles,
        // filtros, sectores y ranking son exactamente los de hoy). Un nil en la
        // ruta Oklab NO hace fallback a HSB: cae al histograma clásico como
        // cualquier portada sin color suficiente (mismo contrato que siempre).
        if accentHeuristicV2Enabled,
           let perceptual = clusteredAccentColorsOklab(from: artwork) {
            return perceptual
        }
        guard let pixels = coloredPixels(from: artwork) else { return nil }

        var sectors = [HueSector](repeating: HueSector(), count: hueSectorCount)
        for pixel in pixels {
            let index = min(hueSectorCount - 1, max(0, Int(pixel.hue / hueSectorWidth)))
            sectors[index].add(pixel)
        }

        // ✅ El sector con MÁS píxeles es el color dominante visual (un logo rojo
        // pequeño ya no gana a un fondo azul mayoritario: cada sector suma todos
        // sus píxeles, no un cubo RGB concreto).
        // ✅ Ranking por centralidad × saturación (el que hoy corre por defecto:
        // un color pequeño pero saturado puede ganarle a un fondo grande y
        // apagado). El flag ya no alterna este ranking — su única función ahora
        // es elegir HSB (OFF) vs Oklab (ON) — así la ruta HSB produce los colores
        // exactos de siempre tanto con la clave ausente como escrita a false.
        // El secundario mantiene la separación de tono ≥30° y su umbral de
        // píxeles; solo cambia el orden del ranking.
        let ranked = sectors.enumerated().sorted {
            $0.element.weightedScore > $1.element.weightedScore
        }
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
        // ✅ v2: semidiagonal en píxeles para normalizar la distancia al centro
        // a [0, 1] (0 = centro exacto, 1 = esquina).
        let halfDiagonal = sqrt(CGFloat(width * width + height * height)) / 2
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

                // ✅ v2: peso de centralidad = 1 + (1 - d normalizada) × boost.
                let dx = (CGFloat(x) + 0.5) - CGFloat(width) / 2
                let dy = (CGFloat(y) + 0.5) - CGFloat(height) / 2
                let normalizedDistance = min(1, sqrt(dx * dx + dy * dy) / halfDiagonal)
                pixels.append(HSBPixel(
                    hue: hue * 360,
                    saturation: saturation,
                    brightness: brightness,
                    centralityWeight: 1 + (1 - normalizedDistance) * accentCentralityBoost
                ))
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

    // MARK: - Clustering perceptual en Oklab (flag com.aurora.accentHeuristicV2)

    /// ✅ OKLAB (Björn Ottosson, dominio público): espacio perceptualmente
    /// uniforme. A diferencia de HSB, distancias iguales se PERCIBEN iguales en
    /// toda la rueda (30° de verde ≈ 30° de azul) y las mezclas siguen el eje
    /// perceptual: púrpura + amarillo no colapsa en marrón sucio. Pipeline puro
    /// sRGB → linear → LMS (raíz cúbica) → L,a,b. Sin dependencias externas.
    private struct OklabPixel {
        let l: CGFloat          // luminancia perceptual (0...1)
        let a: CGFloat          // eje verde↔rojo (rango pequeño, ±0.4 típico)
        let b: CGFloat          // eje azul↔amarillo
        let chroma: CGFloat     // sqrt(a² + b²)
        let hue: CGFloat        // grados 0..<360 (atan2(b, a))
        let centralityWeight: CGFloat
    }

    /// Sector de tono OKLCH (30°). La media del tono usa los vectores (a, b)
    /// ponderados por croma (media circular): los huees que cruzan el 0° (rojos)
    /// no salen desplazados — mismo principio que `HueSector` en HSB.
    private struct OklabSector {
        var count = 0
        /// ✅ Σ peso de centralidad × croma PERCEPTUAL: un color vibrante pero
        /// pequeño puede ganarle a un fondo apagado grande (equivalente v2).
        var weightedScore: CGFloat = 0
        var lSum: CGFloat = 0
        var chromaSum: CGFloat = 0
        var aChromaSum: CGFloat = 0   // Σ a × croma (media circular del tono)
        var bChromaSum: CGFloat = 0   // Σ b × croma

        mutating func add(_ pixel: OklabPixel) {
            count += 1
            weightedScore += pixel.centralityWeight * pixel.chroma
            lSum += pixel.l
            chromaSum += pixel.chroma
            aChromaSum += pixel.a * pixel.chroma
            bChromaSum += pixel.b * pixel.chroma
        }

        /// Croma medio del sector (umbrales de neutralidad y de secundario).
        var meanChroma: CGFloat {
            guard count > 0 else { return 0 }
            return chromaSum / CGFloat(count)
        }

        /// Tono medio OKLCH en grados (0..<360) sobre la suma ponderada por croma.
        var meanHue: CGFloat {
            var degrees = atan2(bChromaSum, aChromaSum) * 180 / .pi
            if degrees < 0 { degrees += 360 }
            return degrees
        }

        /// Color medio del sector en sRGB (con mapeo de gamut si se sale).
        var averageColor: UIColor? {
            guard count > 0 else { return nil }
            return oklabToSRGBColor(
                lSum / CGFloat(count),
                aChromaSum / CGFloat(count),
                bChromaSum / CGFloat(count)
            )
        }
    }

    /// Límites de la ruta Oklab (espejo perceptual de los umbrales HSB):
    /// alpha < 0.5, L < 0.10 (casi negro) y L > 0.95 (casi blanco).
    /// ✅ FIX morado: el croma mínimo era 0.03 — POR ENCIMA del equivalente del
    /// filtro HSB (sat ≥ 0.10 ≈ croma 0.016–0.032 según L, medido). Portadas con
    /// colores suaves (SORNERO: gris + azul) perdían TODOS sus píxeles → nil →
    /// acento por defecto. 0.015 es la cota inferior del rango HSB con margen
    /// para el ruido de cuantización de 8 bits.
    private static let oklabMinLightness: CGFloat = 0.10
    private static let oklabMaxLightness: CGFloat = 0.95
    private static let oklabMinChroma: CGFloat = 0.015
    /// ✅ FIX morado: mínimo de píxeles SOLO de esta ruta (el 100 de HSB se
    /// calibró con sat ≥ 0.10 ≈ croma 0.016–0.032; filtrar más apretado exigía
    /// el doble de píxeles que HSB para lo mismo). 50 = mismo criterio real.
    private static let oklabMinimumColoredPixels = 50
    /// ✅ Secundario en OKLCH: croma mínimo 0.05 y separación de tono ≥60°
    /// (no 30°: 60° en hue perceptual es lo que el ojo distingue como "otro
    /// color" de forma consistente en toda la rueda).
    private static let oklchNeutralChroma: CGFloat = 0.05
    private static let oklchSecondaryMinChroma: CGFloat = 0.05
    private static let oklchSecondaryHueDelta: CGFloat = 60
    /// ✅ TERCERA PASADA (secundario neutro, V2): se recogen además los píxeles
    /// "grises con tinte" que el filtro principal rechaza. Suelo 0.002 y no
    /// 0.005: el gris de SORNERO mide ≈0.0027 de croma y con 0.005 volvería a
    /// perderse; los grises digitales puros (0.000 exacto) siguen fuera.
    private static let oklabNeutralMinChroma: CGFloat = 0.002
    /// ✅ La tercera pasada solo corre si el primario es VIVO (croma ≥ 0.10).
    /// Con primario neutro sin secundario con color se mantiene el mono actual.
    private static let oklchNeutralLiveChroma: CGFloat = 0.10

    /// sRGB gamma (0...1) → lineal. Misma curva que `luminance(of:)`.
    private static func oklabLinearFromSRGB(_ v: CGFloat) -> CGFloat {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    /// Lineal (0...1) → sRGB gamma.
    private static func oklabSRGBFromLinear(_ v: CGFloat) -> CGFloat {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    /// sRGB (0...1, sin alpha) → Oklab (L, a, b). Matriz sRGB D65 y fórmulas de
    /// Ottosson (https://bottosson.github.io/posts/oklab/), dominio público.
    private static func oklabFromSRGB(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> (l: CGFloat, a: CGFloat, b: CGFloat) {
        let lr = oklabLinearFromSRGB(r)
        let lg = oklabLinearFromSRGB(g)
        let lb = oklabLinearFromSRGB(b)
        // Linear RGB → LMS
        let l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
        let m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
        let s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb
        let l_ = CGFloat(cbrt(Double(l)))
        let m_ = CGFloat(cbrt(Double(m)))
        let s_ = CGFloat(cbrt(Double(s)))
        // LMS' → Oklab
        return (
            0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }

    /// Oklab → RGB lineal (inverso de Ottosson).
    private static func oklabToLinearRGB(_ l: CGFloat, _ a: CGFloat, _ b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let lc = l_ * l_ * l_
        let mc = m_ * m_ * m_
        let sc = s_ * s_ * s_
        return (
            4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc,
            -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc,
            -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc
        )
    }

    /// Oklab (L, a, b) → UIColor sRGB. Si el color medio cae fuera del gamut
    /// sRGB (posible al promediar un sector), se reduce el croma por bisección
    /// manteniendo L y el tono: recortar canales desplazaría el tono.
    private static func oklabToSRGBColor(_ l: CGFloat, _ a: CGFloat, _ b: CGFloat) -> UIColor? {
        var chroma = sqrt(a * a + b * b)
        let invChroma = chroma > 1e-9 ? 1 / chroma : 0
        let hueA = a * invChroma
        let hueB = b * invChroma

        func linearRGB(_ c: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            oklabToLinearRGB(l, hueA * c, hueB * c)
        }
        func isInsideGamut(_ c: CGFloat) -> Bool {
            let (r, g, bl) = linearRGB(c)
            return r >= -0.001 && r <= 1.001 && g >= -0.001 && g <= 1.001 && bl >= -0.001 && bl <= 1.001
        }
        if !isInsideGamut(chroma) {
            var low: CGFloat = 0
            var high = chroma
            for _ in 0..<8 {
                let mid = (low + high) / 2
                if isInsideGamut(mid) { low = mid } else { high = mid }
            }
            chroma = low
        }

        let (lr, lg, lb) = linearRGB(chroma)
        func clamp01(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }
        return UIColor(
            red: clamp01(oklabSRGBFromLinear(lr)),
            green: clamp01(oklabSRGBFromLinear(lg)),
            blue: clamp01(oklabSRGBFromLinear(lb)),
            alpha: 1
        )
    }

    /// ✅ Píxeles significativos de la portada (64×64) en Oklab. Misma
    /// construcción de contexto que la ruta HSB (`coloredPixels`); solo cambia
    /// la conversión y los filtros por píxel, ahora en espacio perceptual.
    /// Devuelve DOS depósitos: los píxeles con color (clustering principal) y
    /// los neutros con tinte (oklabNeutralMinChroma ≤ croma < oklabMinChroma,
    /// mismos límites de L) para la tercera pasada del secundario neutro.
    private static func oklabPixels(from artwork: UIImage) -> (chromatic: [OklabPixel], neutral: [OklabPixel])? {
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
        // ✅ Semidiagonal en píxeles para normalizar la distancia al centro
        // a [0, 1] (0 = centro exacto, 1 = esquina). Igual que la ruta HSB.
        let halfDiagonal = sqrt(CGFloat(width * width + height * height)) / 2
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)

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

        var pixels: [OklabPixel] = []
        pixels.reserveCapacity(width * height)
        var neutralPixels: [OklabPixel] = []
        neutralPixels.reserveCapacity(width * height)

        // ✅ Diagnóstico del embudo (visible en Registros bajo .artwork): cuántos
        // píxeles filtra CADA etapa, para verificar en dispositivo que la ruta
        // Oklab no descarta la portada entera (bug del morado por defecto).
        var failedAlpha = 0
        var failedLightness = 0
        var failedChroma = 0
        let totalPixels = width * height

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                guard CGFloat(data[offset + 3]) / 255 >= 0.5 else {
                    failedAlpha += 1
                    continue
                }

                let oklab = oklabFromSRGB(
                    CGFloat(data[offset]) / 255,
                    CGFloat(data[offset + 1]) / 255,
                    CGFloat(data[offset + 2]) / 255
                )
                let chroma = sqrt(oklab.a * oklab.a + oklab.b * oklab.b)
                guard oklab.l >= oklabMinLightness, oklab.l <= oklabMaxLightness else {
                    failedLightness += 1
                    continue
                }
                // El suelo real de la pasada es oklabNeutralMinChroma; quien no
                // lo alcanza va al contador y muere. Los que quedan se reparten
                // después entre el depósito con color y el de neutros.
                guard chroma >= oklabNeutralMinChroma else {
                    failedChroma += 1
                    continue
                }

                var hue = atan2(oklab.b, oklab.a) * 180 / .pi
                if hue < 0 { hue += 360 }

                // ✅ Peso de centralidad idéntico a la ruta HSB.
                let dx = (CGFloat(x) + 0.5) - CGFloat(width) / 2
                let dy = (CGFloat(y) + 0.5) - CGFloat(height) / 2
                let normalizedDistance = min(1, sqrt(dx * dx + dy * dy) / halfDiagonal)
                let pixel = OklabPixel(
                    l: oklab.l,
                    a: oklab.a,
                    b: oklab.b,
                    chroma: chroma,
                    hue: hue,
                    centralityWeight: 1 + (1 - normalizedDistance) * accentCentralityBoost
                )
                // ✅ Un píxel nunca va a los dos depósitos.
                if chroma >= oklabMinChroma {
                    pixels.append(pixel)
                } else {
                    neutralPixels.append(pixel)
                }
            }
        }

        // ✅ Umbral SOLO de esta ruta (50 vs 100 de HSB): ver oklabMinimumColoredPixels.
        guard pixels.count >= oklabMinimumColoredPixels else {
            AppLog.info(.artwork, String(format: "Oklab: portada descartada — %ld/%ld píxeles con color (mínimo %ld; α %ld, L %ld, croma %ld filtrados)", pixels.count, totalPixels, oklabMinimumColoredPixels, failedAlpha, failedLightness, failedChroma))
            return nil
        }
        AppLog.info(.artwork, String(format: "Oklab: %ld/%ld píxeles con color, %ld neutros con tinte (α %ld, L %ld, croma %ld filtrados)", pixels.count, totalPixels, neutralPixels.count, failedAlpha, failedLightness, failedChroma))
        return (pixels, neutralPixels)
    }

    /// ⚡ Clustering de hue en OKLCH — alternativa perceptual a la ruta HSB.
    /// Misma estructura de 12 sectores de 30°; SOLO cambia el espacio de color:
    /// 1. Muestreo 64×64 y filtros en Oklab (alpha, L, croma — ver umbrales).
    /// 2. Primario = sector con mayor Σ (peso de centralidad × croma).
    /// 3. Secundario: primer sector con croma ≥ 0.05 y tono a ≥60° OKLCH del
    ///    primario; si el primario es neutro (croma < 0.05), gana el de mayor
    ///    croma sin importar el tono. Sin secundario → nil (fallback a mono,
    ///    mismo contrato que la ruta HSB).
    private static func clusteredAccentColorsOklab(from artwork: UIImage) -> (primary: UIColor, secondary: UIColor?)? {
        guard let samples = oklabPixels(from: artwork) else { return nil }

        var sectors = [OklabSector](repeating: OklabSector(), count: hueSectorCount)
        for pixel in samples.chromatic {
            let index = min(hueSectorCount - 1, max(0, Int(pixel.hue / hueSectorWidth)))
            sectors[index].add(pixel)
        }

        let ranked = sectors.enumerated().sorted {
            $0.element.weightedScore > $1.element.weightedScore
        }
        guard let winner = ranked.first, winner.element.count > 0,
              let primary = winner.element.averageColor else { return nil }

        var secondary: UIColor?
        if winner.element.meanChroma < oklchNeutralChroma {
            // ✅ Primario neutro: el hue de un sector casi gris no es fiable →
            // secundario por croma descendente, sin importar el tono.
            let candidates = ranked.dropFirst().filter {
                $0.element.count > 10 && $0.element.meanChroma >= oklchSecondaryMinChroma
            }
            if let best = candidates.max(by: { $0.element.meanChroma < $1.element.meanChroma }) {
                secondary = best.element.averageColor
            }
        } else {
            let primaryHue = winner.element.meanHue
            for candidate in ranked.dropFirst() where candidate.element.count > 10 {
                guard candidate.element.meanChroma >= oklchSecondaryMinChroma,
                      angularDistance(candidate.element.meanHue, primaryHue) >= oklchSecondaryHueDelta else { continue }
                secondary = candidate.element.averageColor
                break
            }
            // ✅ TERCERA PASADA — secundario neutro (solo primario vivo): si la
            // portada tiene una masa gris con tinte dominante (SORNERO), el
            // sector neutro con MÁS PÍXELES la aporta como secundario. Con
            // primario neutro sin secundario con color se queda el mono actual.
            if secondary == nil, winner.element.meanChroma >= oklchNeutralLiveChroma {
                secondary = bestNeutralSecondary(from: samples.neutral)
            }
        }

        return (primary, secondary)
    }

    /// ✅ Secundario neutro: sector con MÁS PÍXELES del depósito gris (conteo
    /// puro, sin ponderar por croma: aquí el croma es casi cero por definición).
    /// Mismo umbral de supervivencia (≥10 px) que el secundario con color.
    private static func bestNeutralSecondary(from neutralPixels: [OklabPixel]) -> UIColor? {
        guard !neutralPixels.isEmpty else { return nil }

        var sectors = [OklabSector](repeating: OklabSector(), count: hueSectorCount)
        for pixel in neutralPixels {
            let index = min(hueSectorCount - 1, max(0, Int(pixel.hue / hueSectorWidth)))
            sectors[index].add(pixel)
        }
        guard let winner = sectors.enumerated().max(by: { $0.element.count < $1.element.count }),
              winner.element.count >= 10,
              let color = winner.element.averageColor else { return nil }
        AppLog.info(.artwork, "Oklab: secundario neutro del sector \(winner.offset) (\(winner.element.count) px)")
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

    // MARK: - API pública de extracción

    /// ✅ PUNTO ÚNICO DE EXTRACCIÓN: resuelve primario + secundario de una
    /// carátula en UNA sola pasada de clustering, con la normalización de
    /// legibilidad (readableColor) ya aplicada a ambos. ThemeManager lo usa
    /// como única fuente; las vistas consumen sus propiedades publicadas.
    /// - `nil`: la carátula no aporta color suficiente (el llamador usa su fallback).
    /// - `secondary == nil`: carátula monocromática → fallback a mono intacto.
    static func resolvedAccentPair(from artwork: UIImage) -> (primary: UIColor, secondary: UIColor?)? {
        guard let clustered = clusteredAccentColors(from: artwork) else { return nil }
        return (
            UIColor(AppTheme.readableColor(from: clustered.primary)),
            clustered.secondary.map { UIColor(normalizedAccentSecondary(from: $0)) }
        )
    }

    /// ✅ Normalización del SECUNDARIO: ruta estándar readableColor, con UNA
    /// excepción — con V2 activa, un secundario NEUTRO (croma Oklab < 0.05;
    /// solo puede salir de la tercera pasada de `clusteredAccentColorsOklab`,
    /// y con el flag OFF es imposible: la ruta HSB nunca lo produce) se
    /// normaliza SOLO en brillo, con los mismos topes de readableColor.
    /// Forzarle saturación 0.30 convertiría el gris de la portada en un
    /// gris-azulado que no es lo que el ojo ve. El primario y los secundarios
    /// con color siguen la ruta de siempre, sin cambios.
    private static func normalizedAccentSecondary(from uiColor: UIColor) -> Color {
        if accentHeuristicV2Enabled {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 1
            if uiColor.getRed(&r, green: &g, blue: &b, alpha: &alpha) {
                let oklab = oklabFromSRGB(r, g, b)
                if sqrt(oklab.a * oklab.a + oklab.b * oklab.b) < oklchNeutralChroma {
                    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
                    if uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil) {
                        let newBrightness = brightness < 0.28 ? 0.33 : (brightness > 0.92 ? 0.90 : brightness)
                        return Color(uiColor: UIColor(hue: hue, saturation: saturation, brightness: newBrightness, alpha: 1))
                    }
                }
            }
        }
        return AppTheme.readableColor(from: uiColor)
    }

    /// ⚡ Algoritmo por clustering de hue (estilo Apple Music):
    /// 1. Portada reducida a 64×64 (menos ruido, más rápido).
    /// 2. Cada píxel se convierte a HSB y se filtran transparentes, casi negros,
    ///    casi blancos y grises.
    /// 3. Los píxeles restantes se agrupan por TONO en 12 sectores de 30° y el
    ///    sector con mayor puntuación ponderada por centralidad y saturación da
    ///    el color dominante visual. Con com.aurora.accentHeuristicV2 = true
    ///    esta ruta se sustituye por el clustering perceptual en Oklab (ver
    ///    `clusteredAccentColorsOklab`); el fallback y los cachés son los mismos.
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
