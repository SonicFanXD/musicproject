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
        case .flat: return Localization.localized("eq.flat")
        case .bass: return Localization.localized("eq.bass")
        case .treble: return Localization.localized("eq.treble")
        case .vocal: return Localization.localized("eq.vocal")
        case .classical: return Localization.localized("eq.classical")
        case .electronic: return Localization.localized("eq.electronic")
        case .pop: return Localization.localized("eq.pop")
        case .rock: return Localization.localized("eq.rock")
        case .jazz: return Localization.localized("eq.jazz")
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
        self.title = (title?.isEmpty == false) ? title! : url.deletingPathExtension().lastPathComponent
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

    /// ✅ FIX multi-disco: orden canónico (disco 1 antes que disco 2, luego pista).
    /// Antes solo se ordenaba por trackNumber → en álbumes con Disc 1 y Disc 2
    /// (ambos arrancan en pista 1) el sort inestable podía poner primero el Disc 2.
    static func discAwareOrder(_ lhs: Song, _ rhs: Song) -> Bool {
        let ld = lhs.discNumber ?? 1
        let rd = rhs.discNumber ?? 1
        if ld != rd { return ld < rd }
        if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
        // ✅ localizedStandardCompare: orden natural ("Track 2" < "Track 10").
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

extension Song {
    private static let artworkCache: NSCache<NSUUID, UIImage> = {
        let cache = NSCache<NSUUID, UIImage>()
        // ✅ ANTI-CRASH: límite por MEMORIA (costo), no solo por conteo.
        // Cada UIImage decodificada ocupa ancho×alto×4 bytes en RAM (768²×4 =
        // 2.4MB a la resolución actual). countLimit 500 sin costLimit permitía
        // >1GB de bitmaps → jetsam kill al scrollear listas grandes.
        cache.countLimit = 120
        cache.totalCostLimit = 200 * 1024 * 1024 // 200MB de bitmaps decodificados
        return cache
    }()

    var artwork: UIImage? {
        guard let data = artworkData else { return nil }
        if let cached = Song.artworkCache.object(forKey: id as NSUUID) {
            return cached
        }
        guard let image = UIImage(data: data) else { return nil }
        // Costo = bytes del bitmap decodificado (RGBA), para que totalCostLimit
        // refleje la RAM real consumida y NSCache expulse bajo presión.
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        Song.artworkCache.setObject(image, forKey: id as NSUUID, cost: cost)
        return image
    }

    var displayName: String {
        if album.isEmpty && !artist.isEmpty {
            return "\(title) • \(artist)"
        }
        return title
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
            // ✅ Formato consistente en kHz: 44100 → "44.1kHz" (antes "44100Hz"
            // mientras 48000 mostraba "48kHz"). String(format:) no usa el locale,
            // así que el punto decimal es estable en todos los idiomas.
            let kHz = sampleRate / 1000.0
            let formatted = kHz.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(kHz))kHz"
                : String(format: "%.1f", kHz) + "kHz"
            parts.append(formatted)
        }

        if channelCount == 2 {
            parts.append(Localization.localized("audio.quality.stereo"))
        } else if channelCount == 1 {
            parts.append(Localization.localized("audio.quality.mono"))
        } else if channelCount > 2 {
            parts.append("\(channelCount).1")
        }

        if sampleRate > 48000 || bitDepth > 16 {
            parts.append(Localization.localized("audio.quality.hiRes"))
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

    // ✅ Fecha de salida del álbum (la más antigua de las canciones)
    var releaseDate: Date? {
        songs.compactMap { $0.releaseDate }.min()
    }

    // ✅ UNIFICADO: delega en la caché/algorithm compartidos de AppTheme —
    // NowPlaying, AlbumDetail y ArtistDetail ahora obtienen el MISMO color
    // para la misma carátula (una sola extracción por arte).
    var dominantColor: UIColor? {
        guard let artwork = artwork else { return nil }
        return AppTheme.cachedDominantColor(from: artwork, key: id)
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
                songs: songs.sorted(by: Song.discAwareOrder)
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var artwork: UIImage? {
        songs.first(where: { $0.artworkData != nil })?.artwork
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
