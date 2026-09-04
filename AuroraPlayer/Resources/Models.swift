import Foundation
import UIKit // Necesario para UIImage y el manejo de portadas

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

    var symbolName: String {
        switch self {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .off: return "Repetición desactivada"
        case .all: return "Repetir todas"
        case .one: return "Repetir canción"
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
        self.title = title?.isEmpty == false
            ? title!
            : url.deletingPathExtension().lastPathComponent
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

// MARK: - Extensiones de Compatibilidad para Song
extension Song {
    /// Convierte dinámicamente los datos de portada crudos en un UIImage consumible por las vistas
    var artwork: UIImage? {
        if let data = artworkData {
            return UIImage(data: data)
        }
        return nil
    }
}

// MARK: - Modelos de Biblioteca (Album y Artist)
struct Album: Identifiable, Equatable {
    let id: UUID
    let name: String
    let artist: String
    let songs: [Song]
    
    var artwork: UIImage? {
        if let songWithArtwork = songs.first(where: { $0.artworkData != nil }),
           let data = songWithArtwork.artworkData {
            return UIImage(data: data)
        }
        return nil
    }
}

struct Artist: Identifiable, Equatable {
    let id: UUID
    let name: String
    let songs: [Song]
    
    var albums: [Album] {
        let grouped = Dictionary(grouping: songs) { $0.album }
        return grouped.map { (albumName, songs) in
            Album(
                id: UUID(),
                name: albumName.isEmpty ? "Álbum desconocido" : albumName,
                artist: name,
                songs: songs.sorted { $0.trackNumber < $1.trackNumber }
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    var artwork: UIImage? {
        if let songWithArtwork = songs.first(where: { $0.artworkData != nil }),
           let data = songWithArtwork.artworkData {
            return UIImage(data: data)
        }
        return nil
    }
}

// MARK: - Agrupación automática para FileAccessService
extension FileAccessService {
    /// Genera la lista de Álbumes agrupando las canciones leídas dinámicamente
    var albums: [Album] {
        let grouped = Dictionary(grouping: songs) { song in
            let albumName = song.album.isEmpty ? "Álbum desconocido" : song.album
            let artistName = song.albumArtist.isEmpty ? (song.artist.isEmpty ? "Artista desconocido" : song.artist) : song.albumArtist
            return AlbumKey(album: albumName, artist: artistName)
        }
        
        return grouped.map { (key, songs) in
            Album(
                id: UUID(),
                name: key.album,
                artist: key.artist,
                songs: songs.sorted { $0.trackNumber < $1.trackNumber }
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /// Genera la lista de Artistas agrupando las canciones leídas dinámicamente
    var artists: [Artist] {
        let grouped = Dictionary(grouping: songs) { song in
            song.artist.isEmpty ? "Artista desconocido" : song.artist
        }
        
        return grouped.map { (artistName, songs) in
            Artist(
                id: UUID(),
                name: artistName,
                songs: songs
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct AlbumKey: Hashable {
    let album: String
    let artist: String
}