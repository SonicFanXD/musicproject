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

    /// âœ… FIX multi-disco: orden canÃ³nico (disco 1 antes que disco 2, luego pista).
    /// Antes solo se ordenaba por trackNumber â†’ en Ã¡lbumes con Disc 1 y Disc 2
    /// (ambos arrancan en pista 1) el sort inestable podÃ­a poner primero el Disc 2.
    static func discAwareOrder(_ lhs: Song, _ rhs: Song) -> Bool {
        let ld = lhs.discNumber ?? 1
        let rd = rhs.discNumber ?? 1
        if ld != rd { return ld < rd }
        if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

extension Song {
    private static let artworkCache: NSCache<NSUUID, UIImage> = {
        let cache = NSCache<NSUUID, UIImage>()
        cache.countLimit = 500 // âœ… Aumentado para mantener mÃ¡s portadas en cachÃ©
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
        album.isEmpty ? "\(title) â€¢ \(artist)" : title
    }

    var displaySubtitle: String {
        var components: [String] = []
        if !artist.isEmpty { components.append(artist) }
        if !album.isEmpty { components.append(album) }
        return components.joined(separator: " • ")
    }

    /// DescripciÃ³n detallada del formato de audio basada en metadatos reales del archivo
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
        // âœ… Unificado: usa el mismo extractor HSB mejorado (con fallback para
        // carÃ¡tulas oscuras/grises) que NowPlaying/ThemeManager â€” antes habÃ­a
        // DOS implementaciones distintas y esta daba resultados diferentes.
        let color = AppTheme.dominantColor(from: artwork)
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
                name: albumName.isEmpty ? "Ãlbum desconocido" : albumName,
                artist: name,
                songs: songs.sorted(by: Song.discAwareOrder)
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
