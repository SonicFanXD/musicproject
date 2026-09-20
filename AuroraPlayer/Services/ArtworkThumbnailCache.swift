import Foundation
import UIKit

// MARK: - Caché de thumbnails de artwork
// ✅ OPT: UIImage.preparingThumbnail(of:) NO es caché — crea una UIImage nueva cada vez.
// Esta clase cachea los thumbnails generados para evitar decodificaciones repetidas
// que causan tirones y picos de RAM durante el scroll rápido.
final class ArtworkThumbnailCache {
    static let shared = ArtworkThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()

    private init() {
        // Configurar límites de caché para evitar consumo excesivo de RAM
        cache.countLimit = 200  // Máximo 200 thumbnails en caché
        cache.totalCostLimit = 30 * 1024 * 1024  // 30 MB máximo
    }

    /// Obtiene o genera un thumbnail de la imagen dada.
    /// - Parameters:
    ///   - songID: ID de la canción (usado como parte de la clave de caché)
    ///   - image: Imagen original de la portada
    ///   - size: Tamaño deseado del thumbnail
    /// - Returns: Thumbnail generado (o existente en caché)
    func thumbnail(for songID: UUID, from image: UIImage, size: CGSize) -> UIImage {
        let cacheKey = "\(songID.uuidString)_\(Int(size.width))x\(Int(size.height))"

        lock.lock()
        defer { lock.unlock() }

        // Verificar si ya está en caché
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        // Generar thumbnail si no está en caché
        let thumbnail = image.preparingThumbnail(of: size) ?? image

        // Calcular costo estimado en bytes (ancho × alto × 4 bytes por pixel RGBA)
        let cost = Int(size.width * size.height * 4)
        cache.setObject(thumbnail, forKey: cacheKey as NSString, cost: cost)

        return thumbnail
    }

    /// Obtiene o genera un thumbnail para playlist (sin songID).
    /// Usa el hash de los datos de la imagen como clave alternativa.
    /// - Parameters:
    ///   - imageData: Datos de la imagen para generar clave única
    ///   - image: Imagen original de la portada
    ///   - size: Tamaño deseado del thumbnail
    /// - Returns: Thumbnail generado (o existente en caché)
    func thumbnail(for imageData: Data, from image: UIImage, size: CGSize) -> UIImage {
        let cacheKey = "playlist_\(imageData.hashValue)_\(Int(size.width))x\(Int(size.height))"

        lock.lock()
        defer { lock.unlock() }

        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let thumbnail = image.preparingThumbnail(of: size) ?? image
        let cost = Int(size.width * size.height * 4)
        cache.setObject(thumbnail, forKey: cacheKey as NSString, cost: cost)

        return thumbnail
    }

    /// Limpia toda la caché (útil para liberar memoria bajo presión)
    func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
    }
}
