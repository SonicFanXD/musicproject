```swift
import Foundation
import CryptoKit

struct MusicFolder: Identifiable, Codable, Equatable {
    let id: UUID
    let displayName: String
    let bookmarkData: Data

    init(
        id: UUID = UUID(),
        displayName: String,
        bookmarkData: Data
    ) {
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
        url: URL,
        title: String? = nil,
        artist: String = "",
        album: String = "",
        artworkData: Data? = nil
    ) {
        self.url = url

        // ID estable basado en la ruta del archivo.
        self.id = Song.stableID(for: url)

        self.title =
            title?.isEmpty == false
            ? title!
            : url.deletingPathExtension().lastPathComponent

        self.artist = artist
        self.album = album
        self.artworkData = artworkData
    }

    private static func stableID(for url: URL) -> UUID {
        let normalizedPath =
            url.standardizedFileURL
                .absoluteString
                .lowercased()

        let digest =
            SHA256.hash(
                data: Data(
                    normalizedPath.utf8
                )
            )

        let bytes = Array(digest.prefix(16))

        var uuidBytes = bytes

        // Ajustar bits para formar un UUID válido.
        uuidBytes[6] =
            (uuidBytes[6] & 0x0F) | 0x50

        uuidBytes[8] =
            (uuidBytes[8] & 0x3F) | 0x80

        return UUID(
            uuid: (
                uuidBytes[0],
                uuidBytes[1],
                uuidBytes[2],
                uuidBytes[3],
                uuidBytes[4],
                uuidBytes[5],
                uuidBytes[6],
                uuidBytes[7],
                uuidBytes[8],
                uuidBytes[9],
                uuidBytes[10],
                uuidBytes[11],
                uuidBytes[12],
                uuidBytes[13],
                uuidBytes[14],
                uuidBytes[15]
            )
        )
    }

    static func == (
        lhs: Song,
        rhs: Song
    ) -> Bool {
        lhs.id == rhs.id
    }
}
```
