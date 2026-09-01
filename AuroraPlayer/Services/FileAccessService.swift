import Foundation
import AVFoundation
import ImageIO
import UIKit

class FileAccessService: ObservableObject {
    @Published var folders: [MusicFolder] = []
    @Published var files: [MusicFile] = []
    @Published var songs: [Song] = []
    @Published private(set) var scanTotal = 0
    @Published private(set) var scanProcessed = 0
    @Published private(set) var isScanning = false

    private let defaultsKey = "com.aurora.musicFolders"
    private let filesDefaultsKey = "com.aurora.musicFiles"
    private var activeURLs: [UUID: URL] = [:]
    private var activeFileURLs: [UUID: URL] = [:]
    private var scanGeneration = 0
    private var indexedSongURLs = Set<URL>()
    private var activeDiscoveries = 0
    private let metadataQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.aurora.metadata"
        queue.qualityOfService = .userInitiated
        // Dos lectores simultáneos ofrecen buen rendimiento sin saturar memoria/I-O.
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private let metadataBatchSize = 24

    private let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "wave", "aiff", "aif", "flac"
    ]

    init() {
        loadFolders()
        loadFiles()
    }

    func addFolder(url: URL) {
        beginIncrementalProgressIfNeeded()
        guard url.startAccessingSecurityScopedResource() else {
            AppLog.error(.library, "No se pudo acceder a la carpeta seleccionada")
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
            AppLog.error(.library, "Error al crear bookmark: \(error.localizedDescription)")
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

    func addFiles(urls: [URL]) {
        beginIncrementalProgressIfNeeded()
        for url in urls where supportedExtensions.contains(url.pathExtension.lowercased()) {
            guard url.startAccessingSecurityScopedResource() else { continue }
            do {
                let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                let file = MusicFile(displayName: url.lastPathComponent, bookmarkData: bookmark)
                files.append(file)
                activeFileURLs[file.id] = url
                saveFiles()
                scanSingleFile(url)
            } catch {
                url.stopAccessingSecurityScopedResource()
                AppLog.error(.library, "Bookmark de archivo: \(error.localizedDescription)")
            }
        }
    }

    func removeFile(_ file: MusicFile) {
        activeFileURLs.removeValue(forKey: file.id)?.stopAccessingSecurityScopedResource()
        files.removeAll { $0.id == file.id }
        saveFiles()
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

    private func loadFiles() {
        guard let data = UserDefaults.standard.data(forKey: filesDefaultsKey),
              let saved = try? JSONDecoder().decode([MusicFile].self, from: data) else { return }
        files = saved
        for file in files { resolveAndScan(file) }
    }

    private func resolveAndScan(_ file: MusicFile) {
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: file.bookmarkData, bookmarkDataIsStale: &stale)
            guard url.startAccessingSecurityScopedResource() else { return }
            activeFileURLs[file.id] = url
            scanSingleFile(url)
        } catch { AppLog.error(.library, "No se pudo restaurar \(file.displayName): \(error.localizedDescription)") }
    }

    private func rescanAllFolders() {
        scanGeneration += 1
        metadataQueue.cancelAllOperations()
        songs = []
        indexedSongURLs.removeAll(keepingCapacity: true)
        scanTotal = 0
        scanProcessed = 0
        activeDiscoveries = 0
        isScanning = !folders.isEmpty || !files.isEmpty
        for folder in folders {
            resolveAndScan(folder)
        }
        for file in files {
            resolveAndScan(file)
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
                AppLog.error(.library, "No se pudo acceder a: \(folder.displayName)")
                return
            }

            activeURLs[folder.id] = url

            if isStale {
                AppLog.info(.library, "Actualizando bookmark de \(folder.displayName)")
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
                        AppLog.info(.library, "Bookmark actualizado")
                    }
                } catch {
                    AppLog.error(.library, "Error al regenerar bookmark: \(error.localizedDescription)")
                }
            }

            scanFolder(url)
        } catch {
            AppLog.error(.library, "Error al resolver bookmark de \(folder.displayName): \(error.localizedDescription)")
        }
    }

    private func scanFolder(_ url: URL) {
        let generation = scanGeneration
        activeDiscoveries += 1
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let keys: [URLResourceKey] = [.isDirectoryKey]
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) {
                var batch: [URL] = []
                for case let fileURL as URL in enumerator {
                    let values = try? fileURL.resourceValues(forKeys: Set(keys))
                    if values?.isDirectory == true { continue }
                    guard self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
                    batch.append(fileURL)
                    if batch.count == self.metadataBatchSize {
                        self.registerMetadataBatch(batch, generation: generation)
                        batch.removeAll(keepingCapacity: true)
                    }
                }
                if !batch.isEmpty { self.registerMetadataBatch(batch, generation: generation) }
            }
            DispatchQueue.main.async { self.finishDiscovery(generation: generation) }
        }
    }

    private func scanSingleFile(_ url: URL) {
        let generation = scanGeneration
        isScanning = true
        registerMetadataBatch([url], generation: generation)
    }

    private func registerMetadataBatch(_ urls: [URL], generation: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.scanGeneration else { return }
            self.scanTotal += urls.count
            self.enqueueMetadataBatch(urls, generation: generation)
        }
    }

    private func enqueueMetadataBatch(_ urls: [URL], generation: Int) {
        metadataQueue.addOperation { [weak self] in
            guard let self else { return }
            let foundSongs = urls.map { self.makeSong(from: $0) }
            DispatchQueue.main.async {
                guard generation == self.scanGeneration else { return }
                self.scanProcessed += urls.count
                let uniqueSongs = foundSongs.filter { self.indexedSongURLs.insert($0.url).inserted }
                if !uniqueSongs.isEmpty {
                    self.songs.append(contentsOf: uniqueSongs)
                    self.songs.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    AppLog.debug(.library, "Lote cargado: \(uniqueSongs.count); total: \(self.songs.count)")
                }
                self.updateScanningState()
            }
        }
    }

    private func finishDiscovery(generation: Int) {
        guard generation == scanGeneration else { return }
        activeDiscoveries = max(0, activeDiscoveries - 1)
        updateScanningState()
    }

    private func updateScanningState() {
        isScanning = activeDiscoveries > 0 || scanProcessed < scanTotal
    }

    private func beginIncrementalProgressIfNeeded() {
        guard !isScanning else { return }
        scanTotal = 0
        scanProcessed = 0
    }

    private func makeSong(from url: URL) -> Song {
        let metadata = readMetadata(from: url)
        return Song(url: url, title: metadata.title, artist: metadata.artist, albumArtist: metadata.albumArtist, album: metadata.album, artworkData: metadata.artworkData, duration: metadata.duration, lyrics: metadata.lyrics, formatDescription: metadata.formatDescription, discNumber: metadata.discNumber, trackNumber: metadata.trackNumber)
    }

    private struct SongMetadata {
        let title: String?
        let artist: String
        let albumArtist: String
        let album: String
        let artworkData: Data?
        let duration: TimeInterval
        let lyrics: String
        let formatDescription: String
        let discNumber: Int?
        let trackNumber: Int
    }

    private func readMetadata(from url: URL) -> SongMetadata {
        let asset = AVAsset(url: url)
        var title: String?
        var artist = ""
        var albumArtist = ""
        var album = ""
        var artworkData: Data?
        var lyrics = ""
        var discNumber: Int?
        var trackNumber = 0
        let formatMetadata = asset.availableMetadataFormats.flatMap { asset.metadata(forFormat: $0) }

        for item in asset.commonMetadata {
            switch item.commonKey?.rawValue {
            case "title":
                if let value = item.stringValue, !value.isEmpty {
                    title = value
                }
            case "artist":
                artist = item.stringValue ?? ""
            case "albumName":
                album = item.stringValue ?? ""
            case "artwork":
                artworkData = item.dataValue.flatMap(thumbnailArtwork)
            case "lyrics":
                lyrics = item.stringValue ?? ""
            case "discNumber":
                discNumber = item.numberValue?.intValue
            case "trackNumber":
                trackNumber = item.numberValue?.intValue ?? 0
            default:
                break
            }
        }

        for item in formatMetadata {
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            if identifier.contains("albumartist") {
                albumArtist = item.stringValue ?? ""
            }
            if title == nil, identifier.contains("title") { title = item.stringValue }
            if artist.isEmpty, identifier.contains("artist"), !identifier.contains("albumartist") { artist = item.stringValue ?? "" }
            if album.isEmpty, identifier.contains("album"), !identifier.contains("albumartist") { album = item.stringValue ?? "" }
            if identifier.contains("discnumber"),
               let number = item.numberValue?.intValue {
                discNumber = number
            }
            if identifier.contains("tracknumber"),
               let number = item.numberValue?.intValue {
                trackNumber = number
            }
        }

        // Algunos contenedores no exponen la letra como metadata común; se revisan
        // los formatos disponibles sin cargar el archivo de audio completo.
        if lyrics.isEmpty {
            lyrics = formatMetadata
                .first(where: { $0.commonKey?.rawValue == "lyrics" || $0.identifier?.rawValue.localizedCaseInsensitiveContains("lyrics") == true })?
                .stringValue ?? ""
        }
        let audioFile = try? AVAudioFile(forReading: url)
        let sampleRate = audioFile?.processingFormat.sampleRate ?? 0
        let bits = audioFile?.processingFormat.streamDescription.pointee.mBitsPerChannel ?? 0
        let formatDescription = [url.pathExtension.uppercased(), bits > 0 ? "\(bits) bits" : nil, sampleRate > 0 ? "\(Int(sampleRate / 1000)) kHz" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")

        return SongMetadata(
            title: title,
            artist: artist,
            albumArtist: albumArtist.isEmpty ? artist : albumArtist,
            album: album,
            artworkData: artworkData,
            duration: asset.duration.isNumeric ? max(0, asset.duration.seconds) : 0,
            lyrics: lyrics,
            formatDescription: formatDescription,
            discNumber: discNumber,
            trackNumber: trackNumber
        )
    }

    private func thumbnailArtwork(_ data: Data) -> Data {
        // Una portada de 600 px es suficiente para la vista completa y evita que
        // una biblioteca grande mantenga cientos de MB en imágenes originales.
        guard data.count > 350_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 600,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let compressed = UIImage(cgImage: image).jpegData(compressionQuality: 0.82) else { return data }
        return compressed
    }

    private func saveFolders() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func saveFiles() {
        guard let data = try? JSONEncoder().encode(files) else { return }
        UserDefaults.standard.set(data, forKey: filesDefaultsKey)
    }

    deinit {
        for (_, url) in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
        for (_, url) in activeFileURLs { url.stopAccessingSecurityScopedResource() }
    }
}
