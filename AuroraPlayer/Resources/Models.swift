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

struct Song: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String
    let album: String
    let artworkData: Data?

    init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        artist: String = "",
        album: String = "",
        artworkData: Data? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title?.isEmpty == false
            ? title!
            : url.deletingPathExtension().lastPathComponent
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id
    }
}
