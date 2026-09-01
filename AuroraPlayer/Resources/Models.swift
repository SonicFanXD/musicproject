import Foundation

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

struct Song: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String
    let album: String
    let artworkData: Data?
    let duration: TimeInterval

    init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        artist: String = "",
        album: String = "",
        artworkData: Data? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.url = url
        self.title = title?.isEmpty == false
            ? title!
            : url.deletingPathExtension().lastPathComponent
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.duration = duration
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id
    }
}
