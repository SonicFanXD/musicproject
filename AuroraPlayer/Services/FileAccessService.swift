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
    // Cambiar la versión fuerza una única reconstrucción al corregir el mapeo de tags.
    private let libraryCacheFileName = "library-metadata-v3.json"
    private var activeURLs: [UUID: URL] = [:]
    private var activeFileURLs: [UUID: URL] = [:]
    private var scanGeneration = 0
    private var indexedSongURLs = Set<URL>()
    private var activeDiscoveries = 0
    private var cacheSaveWorkItem: DispatchWorkItem?
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
        loadCachedSongs()
        if songs.isEmpty && (!folders.isEmpty || !files.isEmpty) {
            rescanAllFolders()
        } else {
            restoreSecurityScopedAccess()
        }
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
    }

    private func loadFiles() {
        guard let data = UserDefaults.standard.data(forKey: filesDefaultsKey),
              let saved = try? JSONDecoder().decode([MusicFile].self, from: data) else { return }
        files = saved
    }

    private func restoreSecurityScopedAccess() {
        for folder in folders {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: folder.bookmarkData, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            activeURLs[folder.id] = url
        }
        for file in files {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: file.bookmarkData, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            activeFileURLs[file.id] = url
        }
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
        guard !folders.isEmpty || !files.isEmpty else {
            removeCachedSongs()
            return
        }
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
                    self.scheduleCacheSave()
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
                lyrics = metadataText(item)
            case "discNumber":
                discNumber = item.numberValue?.intValue
            case "trackNumber":
                trackNumber = item.numberValue?.intValue ?? 0
            default:
                break
            }
        }

        for item in formatMetadata {
            let identifier = normalizedMetadataIdentifier(item)
            let key = ((item.key as? String) ?? "").lowercased()

            // iTunes/MP4 usa `aART`, `trkn` y `disk`; otros formatos suelen
            // exponer nombres descriptivos. Se soportan las dos variantes.
            if (identifier.contains("albumartist") || key == "aart" || key == "album artist"),
               let value = metadataText(item).nilIfEmpty {
                albumArtist = value
            }
            if title == nil, (identifier.contains("title") || key == "©nam") { title = metadataText(item) }
            if artist.isEmpty, (identifier.contains("artist") || key == "©art"), key != "aart" { artist = metadataText(item) }
            if album.isEmpty, (identifier.contains("album") || key == "©alb"), key != "aart" { album = metadataText(item) }
            if identifier.contains("discnumber") || identifier.contains("disknumber") || key == "disk" {
                discNumber = metadataNumber(item)
            }
            if identifier.contains("tracknumber") || key == "trkn" {
                trackNumber = metadataNumber(item) ?? 0
            }
        }

        // Algunos contenedores no exponen la letra como metadata común; se revisan
        // los formatos disponibles sin cargar el archivo de audio completo.
        if lyrics.isEmpty {
            lyrics = formatMetadata.first(where: { item in
                let id = normalizedMetadataIdentifier(item)
                let key = ((item.key as? String) ?? "").lowercased()
                return item.commonKey?.rawValue == "lyrics" || id.contains("lyric") || key == "©lyr" || key.contains("lyric")
            }).map { self.metadataText($0) } ?? ""
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
            albumArtist: albumArtist,
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

    private func normalizedMetadataIdentifier(_ item: AVMetadataItem) -> String {
        let identifier = item.identifier?.rawValue ?? ""
        return identifier.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private func metadataText(_ item: AVMetadataItem) -> String {
        if let value = item.stringValue { return value }
        guard let data = item.dataValue else { return "" }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .utf16LittleEndian)
            ?? ""
    }

    private func metadataNumber(_ item: AVMetadataItem) -> Int? {
        if let number = item.numberValue?.intValue, number > 0 { return number }
        if let value = item.stringValue, let number = Int(value), number > 0 { return number }
        // `trkn` y `disk` de MP4 suelen guardar dos UInt16 tras 4 bytes de cabecera.
        if let data = item.dataValue, data.count >= 6 {
            let bytes = [UInt8](data)
            let number = Int(bytes[4]) << 8 | Int(bytes[5])
            if number > 0 { return number }
        }
        return nil
    }

    private func saveFolders() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func saveFiles() {
        guard let data = try? JSONEncoder().encode(files) else { return }
        UserDefaults.standard.set(data, forKey: filesDefaultsKey)
    }

    private var libraryCacheURL: URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return directory.appendingPathComponent(libraryCacheFileName)
    }

    private func loadCachedSongs() {
        guard let url = libraryCacheURL,
              let data = try? Data(contentsOf: url),
              let cachedSongs = try? JSONDecoder().decode([Song].self, from: data) else { return }
        songs = cachedSongs
        indexedSongURLs = Set(cachedSongs.map(\.url))
        AppLog.info(.library, "Biblioteca recuperada de caché: \(cachedSongs.count) canciones")
    }

    private func scheduleCacheSave() {
        cacheSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.saveCachedSongs() }
        cacheSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
    }

    private func saveCachedSongs() {
        guard let url = libraryCacheURL,
              let data = try? JSONEncoder().encode(songs) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            AppLog.debug(.library, "Caché de biblioteca guardada: \(songs.count) canciones")
        } catch {
            AppLog.error(.library, "No se pudo guardar caché: \(error.localizedDescription)")
        }
    }

    private func removeCachedSongs() {
        cacheSaveWorkItem?.cancel()
        guard let url = libraryCacheURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    deinit {
        saveCachedSongs()
        for (_, url) in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
        for (_, url) in activeFileURLs { url.stopAccessingSecurityScopedResource() }
    }
}
