import Foundation
import UIKit

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct MusicFolder: Identifiable, Codable {
    let id: UUID
    let displayName: String
    let bookmarkData: Data

    init(id: UUID = UUID(), displayName: String, bookmarkData: Data) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
    }
}

struct MusicFile: Identifiable, Codable {
    let id: UUID
    let displayName: String
    let bookmarkData: Data

    init(id: UUID = UUID(), displayName: String, bookmarkData: Data) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
    }
}

enum RepeatMode: String, CaseIterable, Codable {
    case off, all, one
}

enum EQPreset: String, CaseIterable, Codable {
    case flat, bass, treble, vocal, classical, electronic, pop, rock, jazz

    var displayName: String {
        switch self {
        case .flat: return "Plano"
        case .bass: return "Graves"
        case .treble: return "Agudos"
        case .vocal: return "Vocales"
        case .classical: return "Clásica"
        case .electronic: return "Electrónica"
        case .pop: return "Pop"
        case .rock: return "Rock"
        case .jazz: return "Jazz"
        }
    }

    var gains: [Float] {
        switch self {
        case .flat: return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bass: return [8, 7, 5, 3, 0, 0, 0, 0, 0, 0]
        case .treble: return [0, 0, 0, 0, 0, 0, 3, 5, 7, 8]
        case .vocal: return [2, 4, 5, 4, 2, 0, 0, 0, 0, 0]
        case .classical: return [5, 4, 3, 2, 0, 0, 2, 3, 4, 5]
        case .electronic: return [6, 5, 3, 0, -2, -2, 0, 3, 5, 6]
        case .pop: return [3, 4, 3, 1, 0, 0, 1, 3, 4, 3]
        case .rock: return [6, 5, 4, 2, 0, 0, 2, 4, 5, 6]
        case .jazz: return [4, 3, 2, 2, 0, 0, 2, 3, 4, 4]
        }
    }
}

struct Song: Identifiable, Equatable, Codable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String
    let albumArtist: String
    let album: String
    let artworkData: Data?
    let duration: TimeInterval
    let lyrics: String
    let formatDescription: String
    let discNumber: Int?
    let trackNumber: Int
    let releaseDate: Date?
    let sampleRate: Double
    let bitDepth: Int
    let channelCount: Int

    init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        artist: String = "",
        albumArtist: String = "",
        album: String = "",
        artworkData: Data? = nil,
        duration: TimeInterval = 0,
        lyrics: String = "",
        formatDescription: String = "",
        discNumber: Int? = nil,
        trackNumber: Int = 0,
        releaseDate: Date? = nil,
        sampleRate: Double = 0,
        bitDepth: Int = 0,
        channelCount: Int = 0
    ) {
        self.id = id
        self.url = url
        self.title = title?.isEmpty == false ? title! : url.deletingPathExtension().lastPathComponent
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.artworkData = artworkData
        self.duration = duration
        self.lyrics = lyrics
        self.formatDescription = formatDescription
        self.discNumber = discNumber.flatMap { $0 > 0 ? $0 : nil }
        self.trackNumber = max(0, trackNumber)
        self.releaseDate = releaseDate
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id
    }
}

extension Song {
    private static let artworkCache: NSCache<NSUUID, UIImage> = {
        let cache = NSCache<NSUUID, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    var artwork: UIImage? {
        guard let data = artworkData else { return nil }
        if let cached = Song.artworkCache.object(forKey: id as NSUUID) {
            return cached
        }
        guard let image = UIImage(data: data) else { return nil }
        Song.artworkCache.setObject(image, forKey: id as NSUUID)
        return image
    }

    var displayName: String {
        album.isEmpty ? "\(title) • \(artist)" : title
    }

    var displaySubtitle: String {
        var components: [String] = []
        if !artist.isEmpty { components.append(artist) }
        if !album.isEmpty { components.append(album) }
        return components.joined(separator: " • ")
    }

    /// Descripción detallada del formato de audio basada en metadatos reales del archivo
    var audioQualityDescription: String {
        var parts: [String] = []
        let format = formatDescription.isEmpty ? url.pathExtension.uppercased() : formatDescription
        parts.append(format)

        if bitDepth > 0 && (format == "FLAC" || format == "ALAC" || format == "WAV" || format == "AIFF") {
            parts.append("\(bitDepth)-bit")
        }

        if sampleRate > 0 {
            parts.append(sampleRate >= 48000 ? "\(Int(sampleRate / 1000))kHz" : "\(Int(sampleRate))Hz")
        }

        if channelCount == 2 {
            parts.append("Estéreo")
        } else if channelCount == 1 {
            parts.append("Mono")
        } else if channelCount > 2 {
            parts.append("\(channelCount).1")
        }

        if sampleRate > 48000 || bitDepth > 16 {
            parts.append("Hi-Res")
        }

        return parts.joined(separator: " · ")
    }
}

struct Album: Identifiable, Equatable {
    var id: String { "\(artist)|\(name)" }
    let name: String
    let artist: String
    let songs: [Song]

    var artwork: UIImage? {
        songs.first(where: { $0.artworkData != nil })?.artwork
    }

    private static let colorCache: NSCache<NSString, UIColor> = {
        let cache = NSCache<NSString, UIColor>()
        cache.countLimit = 200
        return cache
    }()

    var dominantColor: UIColor? {
        guard let artwork = artwork else { return nil }
        if let cached = Album.colorCache.object(forKey: id as NSString) {
            return cached
        }
        let color = ColorExtractor.dominantColor(from: artwork)
        if let color = color {
            Album.colorCache.setObject(color, forKey: id as NSString)
        }
        return color
    }
}

struct Artist: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let songs: [Song]

    var albums: [Album] {
        let grouped = Dictionary(grouping: songs) { $0.album }
        return grouped.map { (albumName, songs) in
            Album(
                name: albumName.isEmpty ? "Álbum desconocido" : albumName,
                artist: name,
                songs: songs.sorted { $0.trackNumber < $1.trackNumber }
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var artwork: UIImage? {
        songs.first(where: { $0.artworkData != nil })?.artwork
    }
}

enum ColorExtractor {
    static func dominantColor(from image: UIImage) -> UIColor? {
        let size = CGSize(width: 32, height: 32)
        guard let resized = downscale(image: image, to: size) else { return nil }

        guard let cgImage = resized.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }

        let bytesPerPixel = 4
        let width = cgImage.width
        let height = cgImage.height

        var colorBuckets: [Int: (count: Int, r: CGFloat, g: CGFloat, b: CGFloat)] = [:]

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = CGFloat(bytes[offset]) / 255.0
                let g = CGFloat(bytes[offset + 1]) / 255.0
                let b = CGFloat(bytes[offset + 2]) / 255.0
                let a = CGFloat(bytes[offset + 3]) / 255.0

                guard a > 0.5 else { continue }

                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let brightness = maxC

                guard brightness > 0.2, brightness < 0.95 else { continue }

                let rBucket = Int(r * 4)
                let gBucket = Int(g * 4)
                let bBucket = Int(b * 4)
                let key = rBucket * 16 + gBucket * 4 + bBucket

                if var bucket = colorBuckets[key] {
                    bucket.count += 1
                    bucket.r += r
                    bucket.g += g
                    bucket.b += b
                    colorBuckets[key] = bucket
                } else {
                    colorBuckets[key] = (1, r, g, b)
                }
            }
        }

        var bestKey: Int?
        var bestScore: CGFloat = -1

        for (key, bucket) in colorBuckets {
            let avgR = bucket.r / CGFloat(bucket.count)
            let avgG = bucket.g / CGFloat(bucket.count)
            let avgB = bucket.b / CGFloat(bucket.count)
            let maxC = max(avgR, avgG, avgB)
            let minC = min(avgR, avgG, avgB)
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC

            let score = CGFloat(bucket.count) * (0.5 + saturation * 0.5)
            if score > bestScore {
                bestScore = score
                bestKey = key
            }
        }

        if let key = bestKey, let bucket = colorBuckets[key] {
            let avgR = bucket.r / CGFloat(bucket.count)
            let avgG = bucket.g / CGFloat(bucket.count)
            let avgB = bucket.b / CGFloat(bucket.count)
            return UIColor(red: avgR, green: avgG, blue: avgB, alpha: 1.0)
        }

        return averageColor(from: bytes, width: width, height: height)
    }

    private static func downscale(image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    private static func averageColor(from bytes: UnsafePointer<UInt8>, width: Int, height: Int) -> UIColor? {
        var totalR: CGFloat = 0, totalG: CGFloat = 0, totalB: CGFloat = 0
        var count = 0
        for y in stride(from: 0, to: height, by: 6) {
            for x in stride(from: 0, to: width, by: 6) {
                let offset = (y * width + x) * 4
                let r = CGFloat(bytes[offset]) / 255.0
                let g = CGFloat(bytes[offset + 1]) / 255.0
                let b = CGFloat(bytes[offset + 2]) / 255.0
                let brightness = max(r, g, b)
                if brightness > 0.2, brightness < 0.9 {
                    totalR += r; totalG += g; totalB += b; count += 1
                }
            }
        }
        guard count > 0 else { return UIColor.systemPurple }
        return UIColor(red: totalR / CGFloat(count), green: totalG / CGFloat(count), blue: totalB / CGFloat(count), alpha: 1.0)
    }
}

struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var songIDs: [UUID]
    var createdAt: Date
    var modifiedAt: Date
    var coverArtworkData: Data?

    init(id: UUID = UUID(), name: String, description: String = "", songIDs: [UUID] = [], createdAt: Date = Date(), modifiedAt: Date = Date(), coverArtworkData: Data? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.songIDs = songIDs
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.coverArtworkData = coverArtworkData
    }

    var artwork: UIImage? {
        guard let data = coverArtworkData else { return nil }
        return UIImage(data: data)
    }
}