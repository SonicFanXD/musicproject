
import Foundation
import AVFoundation
import UIKit

final class FileAccessService: ObservableObject {

    @Published private(set) var folders: [MusicFolder] = []
    @Published private(set) var songs: [Song] = []

    private let defaultsKey =
        "com.aurora.musicFolders"

    private var activeURLs: [UUID: URL] = [:]

    private var scanGeneration = UUID()

    private let supportedExtensions: Set<String> = [
        "mp3",
        "m4a",
        "aac",
        "wav",
        "wave",
        "aiff",
        "aif",
        "flac"
    ]

    init() {
        loadFolders()
    }

    // MARK: - Add folder

    func addFolder(url: URL) {

        guard url.startAccessingSecurityScopedResource() else {
            print(
                "AuroraPlayer: no se pudo acceder a la carpeta."
            )
            return
        }

        do {

            let bookmarkData =
                try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )

            // Evitar agregar la misma carpeta dos veces.
            if folders.contains(
                where: {
                    $0.displayName ==
                    url.lastPathComponent
                }
            ) {
                url.stopAccessingSecurityScopedResource()
                return
            }

            let folder = MusicFolder(
                displayName:
                    url.lastPathComponent,
                bookmarkData:
                    bookmarkData
            )

            folders.append(folder)

            activeURLs[folder.id] = url

            saveFolders()

            scanFolder(
                url,
                generation: scanGeneration
            )

        } catch {

            print(
                "AuroraPlayer bookmark error:",
                error.localizedDescription
            )

            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Remove folder

    func removeFolder(
        _ folder: MusicFolder
    ) {

        if let url =
            activeURLs[folder.id] {

            url.stopAccessingSecurityScopedResource()

            activeURLs.removeValue(
                forKey: folder.id
            )
        }

        folders.removeAll {
            $0.id == folder.id
        }

        saveFolders()

        rescanAllFolders()
    }

    // MARK: - Refresh

    func refreshAllFolders() {
        rescanAllFolders()
    }

    private func rescanAllFolders() {

        // Invalidamos cualquier escaneo anterior.
        scanGeneration = UUID()

        let generation = scanGeneration

        songs = []

        for folder in folders {
            resolveAndScan(
                folder,
                generation: generation
            )
        }
    }

    // MARK: - Load folders

    private func loadFolders() {

        guard
            let data =
                UserDefaults.standard.data(
                    forKey: defaultsKey
                ),
            let savedFolders =
                try? JSONDecoder().decode(
                    [MusicFolder].self,
                    from: data
                )
        else {
            return
        }

        folders = savedFolders

        rescanAllFolders()
    }

    // MARK: - Resolve bookmark

    private func resolveAndScan(
        _ folder: MusicFolder,
        generation: UUID
    ) {

        if let previousURL =
            activeURLs[folder.id] {

            previousURL.stopAccessingSecurityScopedResource()

            activeURLs.removeValue(
                forKey: folder.id
            )
        }

        var isStale = false

        do {

            let url =
                try URL(
                    resolvingBookmarkData:
                        folder.bookmarkData,
                    bookmarkDataIsStale:
                        &isStale
                )

            guard
                url.startAccessingSecurityScopedResource()
            else {
                print(
                    "AuroraPlayer: acceso rechazado:",
                    folder.displayName
                )
                return
            }

            activeURLs[folder.id] = url

            if isStale {

                do {

                    let newBookmark =
                        try url.bookmarkData(
                            options: .minimalBookmark,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )

                    if let index =
                        folders.firstIndex(
                            where: {
                                $0.id == folder.id
                            }
                        ) {

                        folders[index] =
                            MusicFolder(
                                id: folder.id,
                                displayName:
                                    folder.displayName,
                                bookmarkData:
                                    newBookmark
                            )

                        saveFolders()
                    }

                } catch {

                    print(
                        "AuroraPlayer: error actualizando bookmark:",
                        error.localizedDescription
                    )
                }
            }

            scanFolder(
                url,
                generation: generation
            )

        } catch {

            print(
                "AuroraPlayer: error resolviendo bookmark:",
                error.localizedDescription
            )
        }
    }

    // MARK: - Scan

    private func scanFolder(
        _ url: URL,
        generation: UUID
    ) {

        DispatchQueue.global(
            qos: .userInitiated
        ).async { [weak self] in

            guard let self else {
                return
            }

            let keys: [URLResourceKey] = [
                .isDirectoryKey
            ]

            var foundSongs: [Song] = []

            guard
                let enumerator =
                    FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys:
                            keys,
                        options: [
                            .skipsHiddenFiles
                        ]
                    )
            else {
                return
            }

            for case let fileURL as URL in enumerator {

                autoreleasepool {

                    let values =
                        try? fileURL.resourceValues(
                            forKeys:
                                Set(keys)
                        )

                    if values?.isDirectory == true {
                        return
                    }

                    let ext =
                        fileURL
                            .pathExtension
                            .lowercased()

                    guard
                        self.supportedExtensions
                            .contains(ext)
                    else {
                        return
                    }

                    let metadata =
                        self.readMetadata(
                            from: fileURL
                        )

                    let song =
                        Song(
                            url: fileURL,
                            title: metadata.title,
                            artist: metadata.artist,
                            album: metadata.album,
                            artworkData:
                                metadata.artworkData
                        )

                    foundSongs.append(song)
                }
            }

            foundSongs.sort {
                $0.title.localizedCaseInsensitiveCompare(
                    $1.title
                ) == .orderedAscending
            }

            DispatchQueue.main.async {

                guard
                    self.scanGeneration ==
                        generation
                else {
                    return
                }

                self.songs.append(
                    contentsOf: foundSongs
                )

                self.songs.sort {
                    $0.title.localizedCaseInsensitiveCompare(
                        $1.title
                    ) == .orderedAscending
                }
            }
        }
    }

    // MARK: - Metadata

    private struct SongMetadata {
        let title: String?
        let artist: String
        let album: String
        let artworkData: Data?
    }

    private func readMetadata(
        from url: URL
    ) -> SongMetadata {

        let asset =
            AVAsset(url: url)

        var title: String?
        var artist = ""
        var album = ""
        var artworkData: Data?

        for item in asset.commonMetadata {

            guard
                let identifier =
                    item.commonKey?.rawValue
            else {
                continue
            }

            switch identifier {

            case AVMetadataKeySpace.common
                .rawValue + ".title":

                if let value =
                    item.stringValue,
                   !value.isEmpty {
                    title = value
                }

            case AVMetadataKeySpace.common
                .rawValue + ".artist":

                artist =
                    item.stringValue ?? ""

            case AVMetadataKeySpace.common
                .rawValue + ".albumName":

                album =
                    item.stringValue ?? ""

            case AVMetadataKeySpace.common
                .rawValue + ".artwork":

                if let data =
                    item.dataValue {
                    artworkData = data
                }

            default:
                break
            }
        }

        return SongMetadata(
            title: title,
            artist: artist,
            album: album,
            artworkData: artworkData
        )
    }

    // MARK: - Persistence

    private func saveFolders() {

        guard
            let data =
                try? JSONEncoder().encode(
                    folders
                )
        else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: defaultsKey
        )
    }

    deinit {

        for (_, url) in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

