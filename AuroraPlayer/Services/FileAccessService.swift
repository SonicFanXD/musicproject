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
    private let libraryCacheFileName = "library-metadata-v7.json"
    private var activeURLs: [UUID: URL] = [:]
    private var activeFileURLs: [UUID: URL] = [:]
    private var scanGeneration = 0
    private var indexedSongURLs = Set<URL>()
    private var activeDiscoveries = 0
    private var cacheSaveWorkItem: DispatchWorkItem?
    private let metadataQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.aurora.metadata"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let metadataBatchSize = 10

    private let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "wave", "aiff", "aif", "flac"
    ]

    init() {
        loadFolders()
        loadFiles()
        loadCachedSongs()
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

            // Verificar que no sea duplicado
            if folders.contains(where: { $0.displayName == folder.displayName }) {
                AppLog.error(.library, "La carpeta ya existe: \(folder.displayName)")
                url.stopAccessingSecurityScopedResource()
                return
            }

            folders.append(folder)
            activeURLs[folder.id] = url
            saveFolders()
            scanFolder(url)
            AppLog.info(.library, "Carpeta añadida: \(folder.displayName)")
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
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?

            coordinator.coordinate(
                readingItemAt: url,
                options: [],
                error: &coordinationError
            ) { coordinatedURL in
                let keys: [URLResourceKey] = [.isDirectoryKey]
                guard let enumerator = FileManager.default.enumerator(
                    at: coordinatedURL,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles]
                ) else { return }

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

            if let coordinationError {
                AppLog.error(.library, "No se pudo leer la carpeta: \(coordinationError.localizedDescription)")
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
        Task { @MainActor in
            guard generation == self.scanGeneration else { return }

            var foundSongs: [Song] = []
            for url in urls {
                let song = await makeSong(from: url)
                foundSongs.append(song)
            }

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

    private func makeSong(from url: URL) async -> Song {
        let metadata = await readMetadata(from: url)
        return Song(url: url, title: metadata.title, artist: metadata.artist, albumArtist: metadata.albumArtist, album: metadata.album, artworkData: metadata.artworkData, duration: metadata.duration, lyrics: metadata.lyrics, formatDescription: metadata.formatDescription, discNumber: metadata.discNumber, trackNumber: metadata.trackNumber, releaseDate: metadata.releaseDate)
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
        let releaseDate: Date?
    }

    // MARK: - readMetadata (ACTUALIZADO PARA iOS 16+ CON ASYNC/AWAIT)
    private func readMetadata(from url: URL) async -> SongMetadata {
        let asset = AVAsset(url: url)
        var title: String?
        var artist = ""
        var albumArtist = ""
        var album = ""
        var artworkData: Data?
        var lyrics = ""
        var discNumber: Int?
        var trackNumber = 0
        var releaseDate: Date?
        var duration: TimeInterval = 0

        do {
            // Usar las nuevas APIs asíncronas de iOS 16+
            let availableFormats = try await asset.load(.availableMetadataFormats)
            var formatMetadata: [AVMetadataItem] = []

            for format in availableFormats {
                let metadata = try await asset.loadMetadata(for: format)
                formatMetadata.append(contentsOf: metadata)
            }

            let commonMetadata = try await asset.load(.commonMetadata)

            for item in commonMetadata {
                switch item.commonKey?.rawValue {
                case "title":
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        title = value
                    }
                case "artist":
                    artist = (try? await item.load(.stringValue)) ?? ""
                case "albumName":
                    album = (try? await item.load(.stringValue)) ?? ""
                case "artwork":
                    if let data = try? await item.load(.dataValue) {
                        artworkData = thumbnailArtwork(data)
                    }
                case "lyrics":
                    lyrics = (try? await item.load(.stringValue)) ?? ""
                case "discNumber":
                    discNumber = (try? await item.load(.numberValue))?.intValue
                case "trackNumber":
                    trackNumber = (try? await item.load(.numberValue))?.intValue ?? 0
                case "creationDate":
                    releaseDate = try? await item.load(.dateValue)
                default:
                    break
                }
            }

            for item in formatMetadata {
                let identifier = normalizedMetadataIdentifier(item)
                let key = metadataKey(item)

                if (identifier.contains("albumartist") || key == "aart" || key == "album artist" || key == "tpe2"),
                   let value = await metadataText(item), !value.isEmpty {
                    albumArtist = value
                }
                if title == nil, (identifier.contains("title") || key == "©nam" || key == "tit2") {
                    title = await metadataText(item)
                }
                if artist.isEmpty, (identifier.contains("artist") || key == "©art" || key == "tpe1"), key != "aart" {
                    artist = (await metadataText(item)) ?? ""
                }
                if album.isEmpty, (identifier.contains("album") || key == "©alb" || key == "talb"), key != "aart" {
                    album = (await metadataText(item)) ?? ""
                }
                if identifier.contains("discnumber") || identifier.contains("disknumber") || key.contains("disk") || key.contains("tpos") {
                    discNumber = await metadataNumberAsync(item)
                }
                if identifier.contains("tracknumber") || key.contains("trkn") || key.contains("trck") {
                    trackNumber = (await metadataNumberAsync(item)) ?? 0
                }
                if releaseDate == nil, identifier.contains("date") || identifier.contains("year") || key.contains("day") || key.contains("tdrc") {
                    releaseDate = await metadataDateAsync(item)
                }
            }

            // Fallback para letras e información ID3/FLAC/M4A
            if let embedded = readID3Metadata(from: url) ?? readFLACMetadata(from: url) ?? readM4AMetadata(from: url) {
                title = title ?? embedded.title
                if artist.isEmpty { artist = embedded.artist ?? "" }
                if albumArtist.isEmpty { albumArtist = embedded.albumArtist ?? "" }
                if album.isEmpty { album = embedded.album ?? "" }
                if trackNumber == 0 { trackNumber = embedded.trackNumber ?? 0 }
                if discNumber == nil { discNumber = embedded.discNumber }
                if releaseDate == nil { releaseDate = embedded.releaseDate }
                if lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lyrics = embedded.lyrics ?? "" }
            }

            if lyrics.isEmpty {
                if let lyricsItem = formatMetadata.first(where: { item in
                    let id = normalizedMetadataIdentifier(item)
                    let key = metadataKey(item)
                    return item.commonKey?.rawValue == "lyrics" || id.contains("lyric") || key == "©lyr" || key.contains("lyric") || key == "uslt" || key == "sylt"
                }) {
                    lyrics = await lyricsText(lyricsItem)
                }
            }
            if lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                for item in formatMetadata {
                    let id = self.normalizedMetadataIdentifier(item)
                    let key = self.metadataKey(item)
                    if item.commonKey?.rawValue == "lyrics" || id.contains("lyric") || key.contains("lyr") || key == "uslt" || key == "sylt" {
                        let candidateLyrics = await lyricsText(item)
                        if !candidateLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            lyrics = candidateLyrics
                            break
                        }
                    }
                }
            }

            // Cargar duración con la nueva API
            let assetDuration = try await asset.load(.duration)
            duration = assetDuration.isNumeric ? max(0, assetDuration.seconds) : 0

        } catch {
            AppLog.error(.library, "Error cargando metadatos: \(error.localizedDescription)")
            // Fallback a métodos síncronos si falla la carga asíncrona
            return await readMetadataFallback(from: url)
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
            duration: duration,
            lyrics: lyrics,
            formatDescription: formatDescription,
            discNumber: discNumber,
            trackNumber: trackNumber,
            releaseDate: releaseDate
        )
    }

    // Fallback síncrono para iOS < 16 o si falla la carga asíncrona
    private func readMetadataFallback(from url: URL) async -> SongMetadata {
        let asset = AVAsset(url: url)
        var title: String?
        var artist = ""
        var albumArtist = ""
        var album = ""
        var artworkData: Data?
        var lyrics = ""
        var discNumber: Int?
        var trackNumber = 0
        var releaseDate: Date?

        // Usar APIs síncronas (deprecadas pero funcionan)
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
            case "creationDate":
                releaseDate = item.dateValue
            default:
                break
            }
        }

        for item in formatMetadata {
            let identifier = normalizedMetadataIdentifier(item)
            let key = metadataKey(item)

            if (identifier.contains("albumartist") || key == "aart" || key == "album artist" || key == "tpe2"),
               let value = metadataTextSync(item), !value.isEmpty {
                albumArtist = value
            }
            if title == nil, (identifier.contains("title") || key == "©nam" || key == "tit2") {
                title = metadataTextSync(item)
            }
            if artist.isEmpty, (identifier.contains("artist") || key == "©art" || key == "tpe1"), key != "aart" {
                artist = metadataTextSync(item) ?? ""
            }
            if album.isEmpty, (identifier.contains("album") || key == "©alb" || key == "talb"), key != "aart" {
                album = metadataTextSync(item) ?? ""
            }
            if identifier.contains("discnumber") || identifier.contains("disknumber") || key.contains("disk") || key.contains("tpos") {
                discNumber = metadataNumberSync(item)
            }
            if identifier.contains("tracknumber") || key.contains("trkn") || key.contains("trck") {
                trackNumber = metadataNumberSync(item) ?? 0
            }
            if releaseDate == nil, identifier.contains("date") || identifier.contains("year") || key.contains("day") || key.contains("tdrc") {
                releaseDate = metadataDateSync(item)
            }
        }

        if let embedded = readID3Metadata(from: url) ?? readFLACMetadata(from: url) ?? readM4AMetadata(from: url) {
            title = title ?? embedded.title
            if artist.isEmpty { artist = embedded.artist ?? "" }
            if albumArtist.isEmpty { albumArtist = embedded.albumArtist ?? "" }
            if album.isEmpty { album = embedded.album ?? "" }
            if trackNumber == 0 { trackNumber = embedded.trackNumber ?? 0 }
            if discNumber == nil { discNumber = embedded.discNumber }
            if releaseDate == nil { releaseDate = embedded.releaseDate }
            if lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lyrics = embedded.lyrics ?? "" }
        }

        if lyrics.isEmpty {
            lyrics = formatMetadata.first(where: { item in
                let id = normalizedMetadataIdentifier(item)
                let key = metadataKey(item)
                return item.commonKey?.rawValue == "lyrics" || id.contains("lyric") || key == "©lyr" || key.contains("lyric") || key == "uslt" || key == "sylt"
            }).map { self.lyricsTextSync($0) } ?? ""
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
            trackNumber: trackNumber,
            releaseDate: releaseDate
        )
    }

    private func thumbnailArtwork(_ data: Data) -> Data {
        guard data.count > 100_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 300,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let compressed = UIImage(cgImage: image).jpegData(compressionQuality: 0.7) else { return data }
        return compressed
    }

    private func normalizedMetadataIdentifier(_ item: AVMetadataItem) -> String {
        let identifier = item.identifier?.rawValue ?? ""
        return identifier.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private func metadataText(_ item: AVMetadataItem) async -> String? {
        if let value = try? await item.load(.stringValue) { return value }
        guard let data = try? await item.load(.dataValue) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .utf16LittleEndian)
    }

    // Non-async version for backwards compatibility
    private func metadataTextSync(_ item: AVMetadataItem) -> String? {
        // Use deprecated properties for non-async context
        if let value = item.stringValue { return value }
        guard let data = item.dataValue else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .utf16LittleEndian)
    }

    private func metadataKey(_ item: AVMetadataItem) -> String {
        guard let key = item.key else { return "" }
        return String(describing: key).lowercased()
    }

    private func lyricsText(_ item: AVMetadataItem) async -> String {
        let key = metadataKey(item)
        let identifier = normalizedMetadataIdentifier(item)
        let isSynchronizedID3 = key == "sylt" || identifier.contains("sylt")
        
        guard (key == "uslt" || isSynchronizedID3 || identifier.contains("uslt")), let data = item.dataValue else {
            let fallbackText = await metadataText(item)
            return fallbackText ?? ""
        }
        
        if isSynchronizedID3, let parsed = synchronizedID3Lyrics(data), !parsed.isEmpty {
            return parsed
        }
        
        guard data.count > 4 else {
            let fallbackText = await metadataText(item)
            return fallbackText ?? ""
        }
        
        let bytes = [UInt8](data)
        let encoding = bytes[0]
        let payload = Data(bytes.dropFirst(4))
        
        if encoding == 0 || encoding == 3 {
            let terminator = payload.firstIndex(of: 0).map { payload.index(after: $0) } ?? payload.startIndex
            if let result = String(data: payload[terminator...], encoding: encoding == 3 ? .utf8 : .isoLatin1)?.trimmingCharacters(in: .controlCharacters) {
                return result
            }
            let fallbackText = await metadataText(item)
            return fallbackText ?? ""
        }
        
        let values = [UInt8](payload)
        if let end = values.indices.dropLast().first(where: { values[$0] == 0 && values[$0 + 1] == 0 }), end + 2 < values.count {
            let text = Data(values[(end + 2)...])
            if let result = String(data: text, encoding: encoding == 1 ? .utf16 : .utf16BigEndian)?.trimmingCharacters(in: .controlCharacters) {
                return result
            }
            let fallbackText = await metadataText(item)
            return fallbackText ?? ""
        }
        
        let fallbackText = await metadataText(item)
        return fallbackText ?? ""
    }

    // Non-async version for backwards compatibility
    private func lyricsTextSync(_ item: AVMetadataItem) -> String {
        let key = metadataKey(item)
        let identifier = normalizedMetadataIdentifier(item)
        let isSynchronizedID3 = key == "sylt" || identifier.contains("sylt")
        
        guard (key == "uslt" || isSynchronizedID3 || identifier.contains("uslt")), let data = item.dataValue else {
            if let value = item.stringValue { return value }
            guard let data = item.dataValue else { return "" }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .utf16LittleEndian) ?? ""
        }
        
        if isSynchronizedID3, let parsed = synchronizedID3Lyrics(data), !parsed.isEmpty {
            return parsed
        }
        
        guard data.count > 4 else {
            if let value = item.stringValue { return value }
            guard let data = item.dataValue else { return "" }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .utf16LittleEndian) ?? ""
        }
        
        let bytes = [UInt8](data)
        let encoding = bytes[0]
        let payload = Data(bytes.dropFirst(4))
        
        if encoding == 0 || encoding == 3 {
            let terminator = payload.firstIndex(of: 0).map { payload.index(after: $0) } ?? payload.startIndex
            let result = String(data: payload[terminator...], encoding: encoding == 3 ? .utf8 : .isoLatin1)?.trimmingCharacters(in: .controlCharacters)
            if let result = result {
                return result
            }
            if let value = item.stringValue { return value }
            guard let data = item.dataValue else { return "" }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .utf16LittleEndian) ?? ""
        }
        
        let values = [UInt8](payload)
        if let end = values.indices.dropLast().first(where: { values[$0] == 0 && values[$0 + 1] == 0 }), end + 2 < values.count {
            let text = Data(values[(end + 2)...])
            let result = String(data: text, encoding: encoding == 1 ? .utf16 : .utf16BigEndian)?.trimmingCharacters(in: .controlCharacters)
            if let result = result {
                return result
            }
            if let value = item.stringValue { return value }
            guard let data = item.dataValue else { return "" }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .utf16LittleEndian) ?? ""
        }
        
        if let value = item.stringValue { return value }
        guard let data = item.dataValue else { return "" }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .utf16LittleEndian) ?? ""
    }

    private func synchronizedID3Lyrics(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count > 7, (bytes[0] == 0 || bytes[0] == 3), bytes[4] == 2 else { return nil }
        var index = 6
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        guard index < bytes.count else { return nil }
        index += 1
        var lines: [String] = []
        while index < bytes.count {
            let textStart = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            guard index < bytes.count, index + 4 < bytes.count else { break }
            let text = String(data: Data(bytes[textStart..<index]), encoding: bytes[0] == 3 ? .utf8 : .isoLatin1)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            index += 1
            let milliseconds = (UInt32(bytes[index]) << 24) | (UInt32(bytes[index + 1]) << 16) | (UInt32(bytes[index + 2]) << 8) | UInt32(bytes[index + 3])
            index += 4
            guard !text.isEmpty else { continue }
            let minutes = milliseconds / 60_000
            let seconds = (milliseconds % 60_000) / 1_000
            let hundredths = (milliseconds % 1_000) / 10
            lines.append(String(format: "[%u:%02u.%02u]%@", minutes, seconds, hundredths, text))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func metadataNumberSync(_ item: AVMetadataItem) -> Int? {
        if let number = item.numberValue?.intValue, number > 0 { return number }
        if let value = item.stringValue,
           let number = Int(value.split(separator: "/", maxSplits: 1).first ?? ""), number > 0 { return number }
        if let data = item.dataValue, data.count >= 6 {
            let bytes = [UInt8](data)
            let number = Int(bytes[4]) << 8 | Int(bytes[5])
            if number > 0 { return number }
        }
        return nil
    }

    // ✅ CORREGIDO: optional chaining en nilIfEmpty
    private func metadataDateSync(_ item: AVMetadataItem) -> Date? {
        if let date = item.dateValue { return date }
        guard let text = metadataTextSync(item)?.nilIfEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: text) { return date }
        formatter.dateFormat = "yyyy"
        return formatter.date(from: text)
    }

    // Versiones asíncronas para iOS 16+
    private func metadataNumberAsync(_ item: AVMetadataItem) async -> Int? {
        if let number = (try? await item.load(.numberValue))?.intValue, number > 0 { return number }
        if let value = try? await item.load(.stringValue),
           let number = Int(value.split(separator: "/", maxSplits: 1).first ?? ""), number > 0 { return number }
        if let data = try? await item.load(.dataValue), data.count >= 6 {
            let bytes = [UInt8](data)
            let number = Int(bytes[4]) << 8 | Int(bytes[5])
            if number > 0 { return number }
        }
        return nil
    }

    private func metadataDateAsync(_ item: AVMetadataItem) async -> Date? {
        if let date = try? await item.load(.dateValue) { return date }
        guard let text = (await metadataText(item))?.nilIfEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: text) { return date }
        formatter.dateFormat = "yyyy"
        return formatter.date(from: text)
    }

    private struct ID3Metadata {
        var title: String?
        var artist: String?
        var albumArtist: String?
        var album: String?
        var trackNumber: Int?
        var discNumber: Int?
        var releaseDate: Date?
        var lyrics: String?
    }

    private func readID3Metadata(from url: URL) -> ID3Metadata? {
        guard url.pathExtension.lowercased() == "mp3",
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 10), header.count == 10 else { return nil }
        let h = [UInt8](header)
        guard Array(h[0..<3]) == [73, 68, 51], (h[3] == 3 || h[3] == 4) else { return nil }
        let tagSize = Int(h[6] & 0x7F) << 21 | Int(h[7] & 0x7F) << 14 | Int(h[8] & 0x7F) << 7 | Int(h[9] & 0x7F)
        guard tagSize > 0, tagSize <= 8_000_000, let tagData = try? handle.read(upToCount: tagSize) else { return nil }
        let bytes = [UInt8](tagData)
        var index = 0
        var metadata = ID3Metadata()
        while index + 10 <= bytes.count {
            let identifier = String(bytes: bytes[index..<(index + 4)], encoding: .ascii) ?? ""
            guard !identifier.trimmingCharacters(in: CharacterSet(charactersIn: "\0")).isEmpty else { break }
            let size: Int
            if h[3] == 4 {
                size = Int(bytes[index + 4] & 0x7F) << 21 | Int(bytes[index + 5] & 0x7F) << 14 | Int(bytes[index + 6] & 0x7F) << 7 | Int(bytes[index + 7] & 0x7F)
            } else {
                size = Int(bytes[index + 4]) << 24 | Int(bytes[index + 5]) << 16 | Int(bytes[index + 6]) << 8 | Int(bytes[index + 7])
            }
            index += 10
            guard size > 0, index + size <= bytes.count else { break }
            let payload = Data(bytes[index..<(index + size)])
            index += size
            switch identifier {
            case "TIT2": metadata.title = id3Text(payload)
            case "TPE1": metadata.artist = id3Text(payload)
            case "TPE2": metadata.albumArtist = id3Text(payload)
            case "TALB": metadata.album = id3Text(payload)
            case "TRCK": metadata.trackNumber = id3Number(payload)
            case "TPOS": metadata.discNumber = id3Number(payload)
            case "TDRC", "TYER": metadata.releaseDate = metadata.releaseDate ?? date(from: id3Text(payload))
            case "USLT": metadata.lyrics = id3UnsynchronizedLyrics(payload)
            case "SYLT": metadata.lyrics = synchronizedID3Lyrics(payload)
            default: break
            }
        }
        return metadata
    }

    private func readFLACMetadata(from url: URL) -> ID3Metadata? {
        guard url.pathExtension.lowercased() == "flac",
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let signature = try? handle.read(upToCount: 4), signature == Data([0x66, 0x4C, 0x61, 0x43]) else { return nil }
        var metadata = ID3Metadata()
        var bytesRead = 4
        var isLast = false
        while !isLast, bytesRead < 8_000_000 {
            guard let header = try? handle.read(upToCount: 4), header.count == 4 else { break }
            bytesRead += 4
            let h = [UInt8](header)
            isLast = h[0] & 0x80 != 0
            let type = h[0] & 0x7F
            let size = Int(h[1]) << 16 | Int(h[2]) << 8 | Int(h[3])
            guard size >= 0, bytesRead + size <= 8_000_000, let block = try? handle.read(upToCount: size), block.count == size else { break }
            bytesRead += size
            guard type == 4 else { continue }
            let comments = flacComments(block)
            metadata.title = comments["TITLE"]
            metadata.artist = comments["ARTIST"]
            metadata.albumArtist = comments["ALBUMARTIST"] ?? comments["ALBUM ARTIST"]
            metadata.album = comments["ALBUM"]
            metadata.trackNumber = comments["TRACKNUMBER"].flatMap(number(from:))
            metadata.discNumber = (comments["DISCNUMBER"] ?? comments["DISC"]).flatMap(number(from:))
            metadata.releaseDate = date(from: comments["DATE"] ?? comments["YEAR"])
            metadata.lyrics = comments["SYNCEDLYRICS"] ?? comments["LYRICS"] ?? comments["UNSYNCEDLYRICS"]
            return metadata
        }
        return nil
    }

    private func readM4AMetadata(from url: URL) -> ID3Metadata? {
        guard ["m4a", "mp4", "alac"].contains(url.pathExtension.lowercased()),
              let handle = try? FileHandle(forReadingFrom: url),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else { return nil }
        defer { try? handle.close() }
        var offset: UInt64 = 0
        var moovData: Data?
        while offset + 8 <= UInt64(fileSize) {
            guard let header = try? handle.read(upToCount: 8), header.count == 8 else { break }
            let bytes = [UInt8](header)
            let atomSize = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
            let atomType = String(bytes: bytes[4..<8], encoding: .isoLatin1) ?? ""
            guard atomSize >= 8 else { break }
            if atomType == "moov" {
                let payloadSize = atomSize - 8
                guard payloadSize <= 8_000_000, let payload = try? handle.read(upToCount: payloadSize), payload.count == payloadSize else { return nil }
                moovData = payload
                break
            }
            offset += UInt64(atomSize)
            guard offset <= UInt64(fileSize) else { break }
            try? handle.seek(toOffset: offset)
        }
        guard let moovData, let ilst = m4aItemList(in: moovData) else { return nil }
        var metadata = ID3Metadata()
        for (name, payload) in ilst {
            switch name {
            case "©nam": metadata.title = m4aText(payload)
            case "©ART": metadata.artist = m4aText(payload)
            case "aART": metadata.albumArtist = m4aText(payload)
            case "©alb": metadata.album = m4aText(payload)
            case "trkn": metadata.trackNumber = m4aNumber(payload)
            case "disk": metadata.discNumber = m4aNumber(payload)
            case "©day": metadata.releaseDate = date(from: m4aText(payload))
            case "©lyr": metadata.lyrics = m4aText(payload)
            default: break
            }
        }
        return metadata
    }

    private func m4aItemList(in data: Data) -> [(String, Data)]? {
        let bytes = [UInt8](data)
        func bigEndian(_ offset: Int) -> Int? {
            guard offset + 4 <= bytes.count else { return nil }
            return Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }
        func atoms(in range: Range<Int>, meta: Bool = false) -> [(String, Range<Int>)] {
            var result: [(String, Range<Int>)] = []
            var index = range.lowerBound + (meta ? 4 : 0)
            while index + 8 <= range.upperBound, let size = bigEndian(index), size >= 8, index + size <= range.upperBound {
                let name = String(bytes: bytes[(index + 4)..<(index + 8)], encoding: .isoLatin1) ?? ""
                result.append((name, (index + 8)..<(index + size)))
                index += size
            }
            return result
        }
        func locateILST(in range: Range<Int>) -> Range<Int>? {
            for (name, contents) in atoms(in: range) {
                if name == "ilst" { return contents }
                if ["moov", "udta", "meta"].contains(name) {
                    let nested = (name == "meta" && contents.count >= 4) ? (contents.lowerBound + 4)..<contents.upperBound : contents
                    if let found = locateILST(in: nested) { return found }
                }
            }
            return nil
        }
        guard let range = locateILST(in: 0..<bytes.count) else { return nil }
        var result: [(String, Data)] = []
        for (name, contents) in atoms(in: range) {
            for (childName, dataContents) in atoms(in: contents) where childName == "data" {
                guard dataContents.count >= 8 else { continue }
                result.append((name, Data(bytes[dataContents.dropFirst(8)])))
            }
        }
        return result
    }

    private func m4aText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters).nilIfEmpty
            ?? String(data: data, encoding: .utf16)?.trimmingCharacters(in: .controlCharacters).nilIfEmpty
    }

    private func m4aNumber(_ data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        let number = Int(bytes[2]) << 8 | Int(bytes[3])
        return number > 0 ? number : nil
    }

    private func flacComments(_ data: Data) -> [String: String] {
        let bytes = [UInt8](data)
        func littleEndianInt(_ offset: Int) -> Int? {
            guard offset + 4 <= bytes.count else { return nil }
            return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        guard let vendorLength = littleEndianInt(0) else { return [:] }
        var offset = 4 + vendorLength
        guard let count = littleEndianInt(offset) else { return [:] }
        offset += 4
        var result: [String: String] = [:]
        for _ in 0..<count {
            guard let length = littleEndianInt(offset), length >= 0, offset + 4 + length <= bytes.count else { break }
            offset += 4
            let entry = String(data: Data(bytes[offset..<(offset + length)]), encoding: .utf8) ?? ""
            offset += length
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<separator]).uppercased()
            let value = String(entry[entry.index(after: separator)...])
            if !value.isEmpty, result[key] == nil { result[key] = value }
        }
        return result
    }

    private func id3Text(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard let encoding = bytes.first, bytes.count > 1 else { return nil }
        let text = Data(bytes.dropFirst())
        let value: String?
        switch encoding {
        case 0: value = String(data: text, encoding: .isoLatin1)
        case 1: value = String(data: text, encoding: .utf16)
        case 2: value = String(data: text, encoding: .utf16BigEndian)
        case 3: value = String(data: text, encoding: .utf8)
        default: value = nil
        }
        return value?.trimmingCharacters(in: .controlCharacters).nilIfEmpty
    }

    private func id3Number(_ data: Data) -> Int? {
        guard let text = id3Text(data) else { return nil }
        return number(from: text)
    }

    private func number(from value: String) -> Int? {
        Int(value.split(separator: "/", maxSplits: 1).first ?? "")
    }

    private func id3UnsynchronizedLyrics(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count > 4 else { return nil }
        let encoding = bytes[0]
        let payload = Array(bytes.dropFirst(4))
        let textBytes: [UInt8]
        if encoding == 0 || encoding == 3 {
            guard let end = payload.firstIndex(of: 0), end + 1 < payload.count else { return nil }
            textBytes = Array(payload[(end + 1)...])
        } else {
            guard let end = payload.indices.dropLast().first(where: { payload[$0] == 0 && payload[$0 + 1] == 0 }), end + 2 < payload.count else { return nil }
            textBytes = Array(payload[(end + 2)...])
        }
        let value: String?
        switch encoding {
        case 0: value = String(data: Data(textBytes), encoding: .isoLatin1)
        case 1: value = String(data: Data(textBytes), encoding: .utf16)
        case 2: value = String(data: Data(textBytes), encoding: .utf16BigEndian)
        case 3: value = String(data: Data(textBytes), encoding: .utf8)
        default: value = nil
        }
        return value?.trimmingCharacters(in: .controlCharacters).nilIfEmpty
    }

    private func date(from value: String?) -> Date? {
        guard let value = value?.nilIfEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = value.count >= 10 ? "yyyy-MM-dd" : "yyyy"
        return formatter.date(from: value)
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
        guard let url = libraryCacheURL else {
            finishInitialLibraryLoad(with: [])
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cachedSongs = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Song].self, from: $0) } ?? []
            DispatchQueue.main.async {
                self?.finishInitialLibraryLoad(with: cachedSongs)
            }
        }
    }

    private func finishInitialLibraryLoad(with cachedSongs: [Song]) {
        songs = cachedSongs
        indexedSongURLs = Set(cachedSongs.map(\.url))
        if cachedSongs.isEmpty && (!folders.isEmpty || !files.isEmpty) {
            rescanAllFolders()
        } else {
            restoreSecurityScopedAccess()
        }
        if !cachedSongs.isEmpty {
            AppLog.info(.library, "Biblioteca recuperada de caché: \(cachedSongs.count) canciones")
        }
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

    // MARK: - Albums y Artists (CORREGIDO)
    var albums: [Album] {
        let grouped = Dictionary(grouping: songs) { song in
            let albumName = song.album.isEmpty ? "Álbum desconocido" : song.album
            let artistName = song.albumArtist.isEmpty ? (song.artist.isEmpty ? "Artista desconocido" : song.artist) : song.albumArtist
            return AlbumKey(album: albumName, artist: artistName)
        }

        return grouped.map { (key, songs) in
            Album(
                name: key.album,
                artist: key.artist,
                songs: songs.sorted { $0.trackNumber < $1.trackNumber }
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var artists: [Artist] {
        let grouped = Dictionary(grouping: songs) { song in
            // Usar albumArtist para agrupar por el artista del álbum, no de la canción
            let artistName = song.albumArtist.isEmpty ? (song.artist.isEmpty ? "Artista desconocido" : song.artist) : song.albumArtist
            return artistName
        }

        return grouped.map { (artistName, songs) in
            Artist(
                name: artistName,
                songs: songs
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    deinit {
        saveCachedSongs()
        for (_, url) in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
        for (_, url) in activeFileURLs { url.stopAccessingSecurityScopedResource() }
    }
}

private struct AlbumKey: Hashable {
    let album: String
    let artist: String
}