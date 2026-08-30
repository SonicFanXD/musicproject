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

struct Song: Identifiable {
    let id: UUID
    let url: URL
    let title: String

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
    }
}