import Foundation

class FileAccessService: ObservableObject {
    @Published var folders: [MusicFolder] = []
    @Published var songs: [Song] = []

    private let defaultsKey = "com.aurora.musicFolders"
    private var activeURLs: [UUID: URL] = [:]

    private let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "wave", "aiff", "aif", "flac"
    ]

    init() {
        loadFolders()
    }

    func addFolder(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("No se pudo acceder a la carpeta seleccionada")
            return
        }

        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let folder = MusicFolder(
                displayName: url.lastPathComponent,
                bookmarkData: bookmarkData
            )

            folders.append(folder)
            activeURLs[folder.id] = url
            saveFolders()
            scanFolder(url)
        } catch {
            print("Error al crear el marcador: \(error.localizedDescription)")
            url.stopAccessingSecurityScopedResource()
        }
    }

    func removeFolder(_ folder: MusicFolder) {
        if let url = activeURLs[folder.id] {
            url.stopAccessingSecurityScopedResource()
            activeURLs.removeValue(forKey: folder.id)
        }

        folders.removeAll { $0.id == folder.id }
        saveFolders()
        rescanAllFolders()
    }

    func refreshAllFolders() {
        rescanAllFolders()
    }

    private func loadFolders() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let savedFolders = try? JSONDecoder().decode([MusicFolder].self, from: data) else {
            return
        }

        folders = savedFolders
        rescanAllFolders()
    }

    private func rescanAllFolders() {
        songs = []
        for folder in folders {
            resolveAndScan(folder)
        }
    }

    private func resolveAndScan(_ folder: MusicFolder) {
        if let previousURL = activeURLs[folder.id] {
            previousURL.stopAccessingSecurityScopedResource()
            activeURLs.removeValue(forKey: folder.id)
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: folder.bookmarkData,
                bookmarkDataIsStale: &isStale
            )

            guard url.startAccessingSecurityScopedResource() else {
                print("No se pudo acceder a: \(folder.displayName)")
                return
            }

            activeURLs[folder.id] = url

            if isStale {
                print("Bookmark obsoleto para \(folder.displayName). Regenerando...")
                do {
                    let newBookmarkData = try url.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                        let updatedFolder = MusicFolder(
                            id: folder.id,
                            displayName: folder.displayName,
                            bookmarkData: newBookmarkData
                        )
                        folders[index] = updatedFolder
                        saveFolders()
                        print("Bookmark regenerado y guardado")
                    }
                } catch {
                    print("Error al regenerar bookmark: \(error.localizedDescription)")
                }
            }

            scanFolder(url)
        } catch {
            print("Error al resolver bookmark de \(folder.displayName): \(error.localizedDescription)")
        }
    }

    private func scanFolder(_ url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let keys: [URLResourceKey] = [.isDirectoryKey]
            var foundSongs: [Song] = []

            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    let values = try? fileURL.resourceValues(forKeys: Set(keys))
                    if values?.isDirectory == true { continue }

                    let ext = fileURL.pathExtension.lowercased()
                    guard self.supportedExtensions.contains(ext) else { continue }

                    foundSongs.append(Song(url: fileURL))
                }
            }

            DispatchQueue.main.async {
                self.songs.append(contentsOf: foundSongs)
            }
        }
    }

    private func saveFolders() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    deinit {
        for (_, url) in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }
}