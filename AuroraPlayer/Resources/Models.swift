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
    case off
    case all
    case one
}

enum EQPreset: String, CaseIterable, Codable {
    case flat
    case bass
    case treble
    case vocal
    case classical
    case electronic
    case pop
    case rock
    case jazz

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
        case .flat:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bass:
            return [8, 7, 5, 3, 0, 0, 0, 0, 0, 0]
        case .treble:
            return [0, 0, 0, 0, 0, 0, 3, 5, 7, 8]
        case .vocal:
            return [2, 4, 5, 4, 2, 0, 0, 0, 0, 0]
        case .classical:
            return [5, 4, 3, 2, 0, 0, 2, 3, 4, 5]
        case .electronic:
            return [6, 5, 3, 0, -2, -2, 0, 3, 5, 6]
        case .pop:
            return [3, 4, 3, 1, 0, 0, 1, 3, 4, 3]
        case .rock:
            return [6, 5, 4, 2, 0, 0, 2, 4, 5, 6]
        case .jazz:
            return [4, 3, 2, 2, 0, 0, 2, 3, 4, 4]
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
        releaseDate: Date? = nil
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
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id
    }
}

extension Song {
    var artwork: UIImage? {
        guard let data = artworkData else { return nil }
        return UIImage(data: data)
    }
}

struct Album: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let artist: String
    let songs: [Song]
    
    var artwork: UIImage? {
        songs.first(where: { $0.artworkData != nil }).flatMap { UIImage(data: $0.artworkData!) }
    }
}

struct Artist: Identifiable, Equatable {
    let id = UUID()
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
        songs.first(where: { $0.artworkData != nil }).flatMap { UIImage(data: $0.artworkData!) }
    }
}