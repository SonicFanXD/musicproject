import Foundation
import AVFoundation
import ImageIO
import UIKit

// ✅ Cache de liked songs para evitar recalcular en cada render de fila
final class LikedSongsCache {
    static let shared = LikedSongsCache()
    private var cache: Set<UUID> = []
    private var isValid = false

    func isLiked(_ songID: UUID) -> Bool {
        guard isValid else { return false }
        return cache.contains(songID)
    }

    func update(likedIDs: Set<UUID>) {
        cache = likedIDs
        isValid = true
    }

    func invalidate() {
        isValid = false
    }

    private init() {}
}

class FileAccessService: ObservableObject {
    @Published var folders: [MusicFolder] = []
    @Published var files: [MusicFile] = []
    @Published var songs: [Song] = [] {
        didSet {
            // ✅ Solo reconstruir si las canciones realmente cambiaron
            // Evita recalcular en cada asignación redundante
            needsRebuild = true
        }
    }

    // ✅ Flag diferido para reconstruir colecciones solo cuando se necesiten
    private var needsRebuild = false
    @Published var playlists: [Playlist] = []
    @Published private(set) var scanTotal = 0
    @Published private(set) var scanProcessed = 0
    @Published private(set) var isScanning = false
    
    // ✅ Contador de canciones pendientes de indexación (para UI)
    var pendingSongsCount: Int { pendingSongs.count }
    // ✅ Splash: indica si el caché de biblioteca ya terminó de cargar,
    // para que la UI muestre las canciones desde el primer frame.
    @Published private(set) var isInitialLibraryLoaded = false
    // ✅ Flag para saber si alguna vez se cargaron canciones (para diferenciar primera vez de re-escaneo)
    private var hasEverLoadedSongs = false
    // ✅ Propiedad pública para que la UI sepa si es la primera carga
    var isFirstLibraryLoad: Bool { !hasEverLoadedSongs }

    private let defaultsKey = "com.aurora.musicFolders"
    private let filesDefaultsKey = "com.aurora.musicFiles"
    private let playlistsDefaultsKey = "com.aurora.playlists"
    // ✅ v14: re-indexado forzado para corregir bitDepth = 0 guardado en v13
    // (FLAC/ALAC sin inferencia de profundidad → "-" en AudioQualityDetail).
    // ✅ v15: re-indexado forzado para poblar `fileModificationDate` (nuevo
    // campo) en TODA la librería existente. Sin este re-indexado único, las
    // canciones ya cacheadas quedarían con fileModificationDate = nil para
    // siempre y el detector de metadata editada (ver scanFolder) nunca
    // tendría con qué comparar la fecha en disco.
    private let libraryCacheFileName = "library-metadata-v15.json"
    private let likedSongsKey = "com.aurora.likedSongs"
    private let likedPlaylistName = "Me Gusta"
    private var activeURLs: [UUID: URL] = [:]
    private var activeFileURLs: [UUID: URL] = [:]
    private var scanGeneration = 0
    // ✅ Claves de canciones ya indexadas (rutas normalizadas, NO URL exactas).
    // Comparar `URL` con `==` fallaba cuando la URL enumerada del disco y la
    // guardada en caché diferían en normalización (`/private/var/...` vs
    // `/var/...`, u otra codificación) → las 722 canciones "ya tenidas" se
    // consideraban nuevas y se reindexaban completas en cada escaneo.
    private var indexedSongKeys = Set<String>()
    // ✅ DEDUPE DE REGISTRO: evita que la misma URL se registre DOS veces en
    // el mismo escaneo (bookmarks de carpetas solapadas, o carpeta + archivo
    // suelto apuntando al mismo disco). Antes el filtro usaba solo
    // indexedSongKeys, que se actualiza cuando el lote TERMINA → el segundo
    // registro de la misma canción pasaba el filtro y scanTotal se inflaba
    // (2000 para 1312 canciones). La clave incluye la generación para que un
    // escaneo nuevo pueda re-registrar lo que el anterior descartó.
    private var registrationClaims = Set<String>()
    /// Ruta canonica para comparar canciones entre disco y cache.
    static func libraryKey(for url: URL) -> String {
        var path = url.standardizedFileURL.path
        // /private/var/... y /var/... son el mismo archivo (symlink /var).
        if path.hasPrefix("/private/") { path = String(path.dropFirst("/private".count)) }
        return path
    }
    // ✅ Claves vistas en disco durante el escaneo en curso. Al terminar un
    // rescan DIFERENCIAL se eliminan las canciones cuyas claves NO se vieron
    // (borradas fuera de la app). Solo aplica cuando pruneMissingOnFinish.
    private var seenOnDiskKeys = Set<String>()
    private var pruneMissingOnFinish = false
    private var activeDiscoveries = 0
    // ✅ Detección silenciosa al abrir la app: enumera el disco en background
    // SIN tocar isScanning/scanTotal (sin tarjeta compacta ni re-renders).
    // Solo si aparecen canciones NUEVAS se indexan e incorporan al final.
    private var isBackgroundDetecting = false
    private var activeSilentDiscoveries = 0
    // ✅ A7: fuentes que TERMINARON de enumerar con éxito en el ciclo
    // silencioso en curso. La poda de borrados solo se habilita si
    // successCount == folders.count (ver finishSilentBatchIfDone): si una
    // carpeta no resolvió su bookmark, no tenía acceso security-scoped o su
    // enumerador no pudo crearse, sus claves NO están en seenOnDiskKeys y
    // podar borraría la biblioteca COMPLETA de esa carpeta.
    private var silentFoldersSucceeded = 0
    private var silentFilesSucceeded = 0
    private var silentTotal = 0
    private var silentProcessed = 0
    private var silentBatches: [(urls: [URL], generation: Int, modifiedKeys: Set<String>)] = []
    private var silentInFlight = 0
    private var cacheSaveWorkItem: DispatchWorkItem?
    private var sortWorkItem: DispatchWorkItem?

    // Cola de lotes con concurrencia limitada: antes se lanzaba un Task sin
    // límite por lote, saturando memoria/CPU con bibliotecas grandes
    // (causa principal del crash durante la indexación).
    // ✅ FIX metadata editada: modifiedKeys viaja junto con el lote para que,
    // al fusionar resultados, se sepa cuáles de las URLs de este lote son
    // ACTUALIZACIONES (archivo ya indexado, tag editado) en vez de altas.
    private var queuedBatches: [(urls: [URL], generation: Int, modifiedKeys: Set<String>)] = []
    // ✅ Nº de lotes en vuelo POR generación de escaneo. Un contador único por
    // generación evita que un lote OBSOLETO (de un rescan anterior que todavía
    // se estaba procesando) corrompa el contador global: antes, un rescan hacía
    // inFlightBatches=0 y, cuando terminaba un lote viejo, su defer hacía -=1
    // dejándolo en -1 → el límite de concurrencia se rompía (se lanzaban más de
    // 4 lotes a la vez, saturando memoria/CPU) y el cálculo de isScanning
    // (hasPendingWork) quedaba sin sentido. Ahora cada lote descuenta su propia
    // generación y el total se obtiene sumando todas — los lotes viejos siguen
    // contando capacidad mientras corren y nunca dejan el contador en negativo.
    private var inFlightByGeneration: [Int: Int] = [:]
    private var inFlightBatches: Int {
        inFlightByGeneration.values.reduce(0, +)
    }
    // ✅ CONCURRENCIA OPTIMIZADA: ventana aumentada de lecturas AVAsset en vuelo.
    // Aumentado de 4 a 8 para iPhone 8/A11 con suficiente RAM para indexación más rápida
    // Los índices preservan el orden original (determinista).
    private let maxConcurrentMetadataReads = 16
    // ✅ Lotes de 4 en vuelo × 50 URLs: más paralelismo para indexación más rápida
    // sin saturar memoria en dispositivos modernos.
    private let maxInFlightBatches = 4
    // ✅ Lotes más grandes: 50 → 75 URLs para menos overhead de scheduling
    private let metadataBatchSize = 150

    // Colecciones derivadas cacheadas: se recalculan solo cuando cambia `songs`,
    // no en cada render de la UI.
    private var cachedAlbums: [Album] = []
    private var cachedArtists: [Artist] = []
    private var pendingSongs: [Song] = []
    private var isSortScheduled = false

    private let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "wave", "aiff", "aif", "flac",
        // ✅ Dolby Digital (AC-3) y Dolby Digital Plus (E-AC-3): se indexan y se
        // reproducen vía el reproductor de respaldo (AVPlayer), porque
        // AVAudioFile no decodifica estos codecs (audio envolvente).
        "ac3", "ec3", "eac3", "ddp",
        // ✅ CONTENEDORES MP4/M4V: iOS envuelve Dolby Digital Plus (E-AC-3) en
        // MP4, así que el codec real solo se conoce leyendo el FourCC del track
        // de audio. Se indexan SOLO si el archivo es de audio (ver
        // videoContainerExtensions): un .mp4 de película no es una canción.
        "mp4", "m4v"
    ]

    /// ✅ Contenedores que pueden llevar vídeo además de audio: para estos,
    /// `makeSong` confirma que el archivo es de audio antes de indexarlo (una
    /// carpeta con películas llenaría la biblioteca de "canciones" que no
    /// suenan). Un .mp4/.m4v con Dolby sí entra: es audio puro.
    private static let videoContainerExtensions: Set<String> = ["mp4", "m4v", "mov"]

    /// ✅ FIX bit depth FLAC/ALAC (replica del fix fd5cddf que se perdió con
    /// el restore): AVFoundation reporta mBitsPerChannel = 0 vía ASBD para
    /// FLAC/ALAC → sin esto TODAS las canciones mostraban "-" en la UI.
    /// Se infiere la profundidad del bitrate del track (rango típico:
    /// <1000 kbps → 16, <2000 → 24, resto → 32). SOLO aplica a codecs
    /// lossless (formatID 'flac'/'alac' o extensión); los lossy (MP3/AAC)
    /// quedan en 0 y la UI muestra "—" (los kbps tienen su propia fila).
    /// Inferir profundidad de bits cuando el ASBD (mBitsPerChannel) la reporta 0 para
    /// FLAC/ALAC. Usa sample rate como señal (más robusto que bitrate, que es inherentemente
    /// impreciso: FLAC 16-bit y 24-bit comprimidos pueden tener bitrate similar).
    /// Ver comentario de usabilidad en la vista AudioQualityDetailView.
    static func inferBitDepth(fileBits: Int, formatID: UInt32, ext: String, sampleRate: Double) -> Int {
        if fileBits > 0, fileBits <= 32 { return fileBits }
        let e = ext.lowercased()
        let isLosslessCodec = formatID == 0x666C6163 /* 'flac' */
            || formatID == 0x616C6163 /* 'alac' */
            || e == "flac" || e == "alac"
        guard isLosslessCodec, sampleRate > 0 else { return 0 }
        // Sample rate como señal de profundidad (no bitrate, que cruza frecuentemente
        // umbrales de 16 vs 24 bits en archivos reales comprimidos):
        if sampleRate >= 96000 { return 24 }        // Hi-Res → 24-bit casi seguro
        if sampleRate <= 48000 { return 16 }        // CD/estándar → 16-bit por defecto
        return 0                                     // zona gris (48001–95999 Hz): no inferimos
    }

    /// Etiqueta legible del formato. `codecName` es el FourCC REAL del stream de
    /// audio (leído del ASBD del asset): cuando aporta información manda sobre la
    /// extensión, porque un E-AC-3 dentro de un contenedor MP4/M4A se anunciaba
    /// como "MP4"/"M4A" aunque el motor propio no pueda decodificarlo.
    private static func formatLabel(for ext: String, codecName: String? = nil) -> String {
        if AudioCodec.isDolby(codecName), let dolby = AudioCodec.displayName(for: codecName) {
            return dolby
        }
        let e = ext.lowercased()
        if AudioCodec.containerExtensions.contains(e), let codec = AudioCodec.displayName(for: codecName) {
            return codec
        }
        switch e {
        case "ec3", "eac3", "ddp": return "Dolby Digital Plus"
        case "ac3": return "Dolby Digital"
        case "wav", "wave": return "WAV"
        case "aiff", "aif": return "AIFF"
        default: return ext.uppercased()
        }
    }

    /// ✅ FourCC → texto. `CMFormatDescriptionGetMediaSubType` devuelve el codec
    /// del stream tal como lo declara el contenedor: 'ec-3' (Dolby Digital
    /// Plus), 'ac-3' (Dolby Digital), 'mp4a' (AAC), 'alac', 'lpcm'… Es la única
    /// forma de saber el codec real: el ASBD de un E-AC-3 dice 2 canales a
    /// 48 kHz, exactamente igual que un AAC estéreo.
    private static func fourCCString(_ code: FourCharCode) -> String? {
        guard code != 0 else { return nil }
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        // Si algún byte no es ASCII imprimible el FourCC no es texto: se guarda
        // en hexadecimal para no inventar un nombre de codec.
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else {
            return String(format: "0x%08X", code)
        }
        let text = (String(bytes: bytes, encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    init() {
        loadFolders()
        loadFiles()
        loadPlaylists()
        loadCachedSongs()
    }

    // 🔄 Precarga de portadas en caché tras recuperar del archivo
    func prewarmArtworkCache() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let songsToWarm = self.songs.prefix(50)
            for song in songsToWarm {
                _ = song.artwork // Fuerza la extracción y caché
            }
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

            // Verificar que no sea duplicado
            if folders.contains(where: { $0.displayName == folder.displayName }) {
                AppLog.error(.library, "La carpeta ya existe: \(folder.displayName)")
                url.stopAccessingSecurityScopedResource()
                return
            }

            folders.append(folder)
            // ✅ BOOKMARKS: el handle de acceso se CONSERVA a propósito — el
            // escaneo que arranca ahora lee el contenido de los archivos de
            // forma asíncrona (AVAsset + parsers binarios en background) y
            // necesita el security-scoped access activo. Su stop ocurre en
            // resolveAndScan(folder) (próximo rescan: stop previo antes de
            // renovar) o removeFolder — ciclo balanceado, sin fuga acumulada.
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
            // ✅ BOOKMARKS: verificar duplicado por nombre ANTES de gastar el
            // handle de acceso (antes: bookmark creado, @Published mutado y
            // guard revertido a medias → file huérfano sin indexar + handle
            // sin liberar).
            guard !files.contains(where: { $0.displayName == url.lastPathComponent }) else { continue }
            guard url.startAccessingSecurityScopedResource() else { continue }
            do {
                let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                let file = MusicFile(displayName: url.lastPathComponent, bookmarkData: bookmark)
                files.append(file)
                // ✅ BOOKMARKS: el handle se conserva — la indexación asíncrona
                // del archivo necesita el acceso activo. Su stop ocurre en
                // resolveAndScan(file) o removeFile.
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

    private func resolveAndScan(_ file: MusicFile, silent: Bool = false) {
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: file.bookmarkData, bookmarkDataIsStale: &stale)
            guard url.startAccessingSecurityScopedResource() else { return }
            // ✅ BOOKMARKS: liberar el acceso previo antes de sobreescribir el
            // mapa (cada rescan acumulaba un start sin su stop).
            if let previous = activeFileURLs[file.id] {
                previous.stopAccessingSecurityScopedResource()
            }
            activeFileURLs[file.id] = url
            scanSingleFile(url, silent: silent)
        } catch { AppLog.error(.library, "No se pudo restaurar \(file.displayName): \(error.localizedDescription)") }
    }

    private func rescanAllFolders() {
        // ✅ DIFERENCIAL (antes: borrado total): conserva las canciones en
        // memoria y solo indexa lo que cambió en disco. Antes `songs = []`
        // obligaba a re-leer las 722 de cero en cada pull-to-refresh o al
        // volver a la app tras el chequeo de accesibilidad. Ahora:
        // 1) se parte de las claves ya indexadas (no se re-leen),
        // 2) solo las URLs NO vistas se meten a la cola de metadatos,
        // 3) al terminar, se eliminan las que ya no existen en disco
        //    (canciones borradas fuera de la app).
        scanGeneration += 1
        queuedBatches.removeAll(keepingCapacity: true)
        pendingSongs = []
        isSortScheduled = false
        // ✅ Cancelar cualquier detección silenciosa en curso: su generación
        // queda obsoleta y no debe bloquear futuras detecciones ni mezclar
        // resultados con este rescan.
        isBackgroundDetecting = false
        activeSilentDiscoveries = 0
        silentBatches.removeAll(keepingCapacity: true)
        // ✅ Claims de la generación vieja ya no aplican (la clave incluye la
        // generación, pero se limpian para acotar memoria).
        registrationClaims.removeAll(keepingCapacity: true)
        indexedSongKeys = Set(songs.map { Self.libraryKey(for: $0.url) })
        seenOnDiskKeys = []
        pruneMissingOnFinish = true
        scanTotal = 0
        scanProcessed = 0
        activeDiscoveries = 0
        isScanning = !folders.isEmpty || !files.isEmpty
        AppLog.info(.library, "Re-escaneo iniciado: \(folders.count) carpetas, \(files.count) archivos sueltos")
        guard !folders.isEmpty || !files.isEmpty else {
            removeCachedSongs()
            return
        }
        // ✅ IMPORTANTE: NO guardar caché vacío aquí, solo al completar.
        for folder in folders {
            resolveAndScan(folder)
        }
        for file in files {
            resolveAndScan(file)
        }
        // ✅ FIX isScanning atascado: si TODOS los bookmarks fallan al resolver
        // (permisos de sandbox reseteados por iOS, carpeta renombrada/borrada),
        // ningún descubrimiento arranca y NADA vuelve a llamar a
        // updateScanningState() → el spinner de "Actualizando biblioteca" se
        // quedaba en true para siempre y el botón de actualizar quedaba
        // deshabilitado. Recalcular aquí el estado: si algún descubrimiento
        // arrancó sigue escaneando; si no, cierra limpio (con seenOnDiskKeys
        // vacío la poda NO se aplica — carpeta ilegible ≠ canciones borradas).
        updateScanningState()
    }

    /// RAM residente actual en MB (diagnóstico de rendimiento en los logs
    /// de indexación — lectura barata de un syscall, sin costo perceptible).
    var residentMemoryMB: Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.resident_size / (1024 * 1024))
    }

    // ✅ Escaneo incremental: solo agrega canciones nuevas sin borrar las existentes
    func scanForNewSongsOnly() {
        guard !isScanning, !folders.isEmpty || !files.isEmpty else { return }
        beginIncrementalProgressIfNeeded()
        scanGeneration += 1
        // ✅ Cancelar detección silenciosa pendiente (generación obsoleta).
        isBackgroundDetecting = false
        activeSilentDiscoveries = 0
        silentBatches.removeAll(keepingCapacity: true)
        registrationClaims.removeAll(keepingCapacity: true)
        // ✅ Guardar las claves ya indexadas para no duplicar
        indexedSongKeys = Set(songs.map { Self.libraryKey(for: $0.url) })
        seenOnDiskKeys = []
        pruneMissingOnFinish = false
        AppLog.info(.library, "Escaneo incremental iniciado: \(folders.count) carpetas, \(files.count) archivos")
        for folder in folders {
            resolveAndScan(folder)
        }
        for file in files {
            resolveAndScan(file)
        }
    }
    
    // ✅ Escaneo en segundo plano al inicio (verificar si hay canciones nuevas)
    // SILENT: no toca `isScanning` ni `scanTotal/scanProcessed` → la UI no
    // muestra tarjeta/indicador compacto ni re-renderiza la lista, y el
    // arranque es instantáneo. Solo indexa lo NUEVO (diferencial por
    // libraryKey); si no hay nada nuevo, no publica nada.
    func backgroundScanForNewSongs() {
        // ✅ FIX CONGELAMIENTO: si un rescan NORMAL está en vuelo, NO arrancar
        // la detección silenciosa. `scanGeneration += 1` huerfanaba los lotes
        // del rescan en curso (se descartaban sin contar en scanProcessed) →
        // isScanning atascado y la animación congelada. El rescan activo ya
        // incorporará las canciones nuevas por sí mismo.
        guard !isBackgroundDetecting, !isScanning, hasEverLoadedSongs, !folders.isEmpty || !files.isEmpty else { return }
        // ✅ La caché ya pobló `songs` + `indexedSongKeys` en init: NO se
        // reconstruyen aquí (antes se hacía `Set(songs.map...)` en el main
        // con miles de canciones → tirón al abrir).
        registrationClaims.removeAll(keepingCapacity: true)
        seenOnDiskKeys = []
        // ✅ A7: los contadores de éxito arrancan en 0. La poda NO se habilita
        // aquí: solo la habilita finishSilentBatchIfDone si TODAS las carpetas
        // registradas (y los archivos sueltos) terminaron de enumerar bien.
        silentFoldersSucceeded = 0
        silentFilesSucceeded = 0
        // ✅ FIX metadata editada: forzar verificación de fechas de modificación
        // incluso en modo silencioso para detectar cambios de metadata externos
        pruneMissingOnFinish = false
        isBackgroundDetecting = true
        scanGeneration += 1
        AppLog.info(.library, "Detección silenciosa en segundo plano: \(folders.count) carpetas")
        for folder in folders {
            resolveAndScan(folder, silent: true)
        }
        for file in files {
            resolveAndScan(file, silent: true)
        }
        // ✅ A7: si NINGUNA enumeración llegó a arrancar (todos los bookmarks
        // de carpeta fallaron, o solo hay archivos sueltos ya indexados y sin
        // cambios → registerMetadataBatch los descarta y nadie invoca
        // finishDiscovery), nadie cerraría el ciclo: isBackgroundDetecting
        // quedaría atascado en true y la poda silenciosa jamás se evaluaría.
        // Aquí NO se puede podar: con 0 carpetas enumeradas con éxito,
        // successCount != folders.count y pruneMissingOnFinish sigue en false.
        if activeSilentDiscoveries == 0 {
            finishSilentBatchIfDone(generation: scanGeneration)
        }
    }

    private func resolveAndScan(_ folder: MusicFolder, silent: Bool = false) {
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

            scanFolder(url, silent: silent)
        } catch {
            AppLog.error(.library, "Error al resolver bookmark de \(folder.displayName): \(error.localizedDescription)")
        }
    }

    private func scanFolder(_ url: URL, silent: Bool = false) {
        let generation = scanGeneration
        // ✅ Snapshot en el MAIN (scanFolder siempre se llama desde el main):
        // leer indexedSongKeys dentro del bloque background sería una carrera
        // con las inserciones de los lotes que terminan en el main.
        let knownKeys = Set(indexedSongKeys)
        // ✅ FIX metadata editada: snapshot de la fecha de modificación con la
        // que se indexó cada canción conocida. Se compara contra la fecha
        // ACTUAL del archivo en disco para saber si sus tags cambiaron desde
        // la última lectura (edición externa de metadata).
        var knownModDates: [String: Date] = [:]
        knownModDates.reserveCapacity(songs.count)
        for song in songs {
            guard let modDate = song.fileModificationDate else { continue }
            knownModDates[Self.libraryKey(for: song.url)] = modDate
        }
        // ✅ UPGRADE DE METADATOS (detección de códec): canciones ya indexadas
        // cuyo contenedor (.mp4/.m4a/.m4v/.mov) aún no tiene leído el FourCC del
        // track de audio. Se re-leen UNA vez para poder elegir la ruta de
        // reproducción correcta (Dolby → AVPlayer); después ya traen `codecName`
        // y esta lista queda vacía.
        let knownCodecUpgradeKeys = Set(
            songs.filter { $0.needsCodecDetection }.map { Self.libraryKey(for: $0.url) }
        )
        if silent {
            // ✅ Detección silenciosa: NO toca isScanning/scanTotal → sin
            // tarjeta compacta, sin indicador, sin re-renders. Los contadores
            // de descubrimiento sí se llevan para saber cuándo terminó y
            // apagar el flag `isBackgroundDetecting`.
            activeSilentDiscoveries += 1
        } else {
            activeDiscoveries += 1
            isScanning = true
        }
        DispatchQueue.global(qos: .utility).async { [weak self, knownKeys] in
            guard let self = self else { return }

            defer {
                // ✅ SEGURIDAD: finishDiscovery SIEMPRE se llama, incluso si el
                // enumerator falla → evita que isScanning se quede atascado en
                // true para siempre (bug de "tirones" al dejar de responder
                // la barra de progreso).
                DispatchQueue.main.async { self.finishDiscovery(generation: generation, silent: silent) }
            }

            // ✅ SIN NSFileCoordinator: `coordinate(readingItemAt:...)` exige
            // un closure y Swift 6 no permite mutar vars capturadas desde él
            // (el `cannot find 'seenKeys' in scope` que rompía el build).
            // FileManager.default.enumerator lee directo sin coordinador:
            // para una app de solo lectura de música es suficiente y elimina
            // el problema de raíz (sin boxes, sin capture lists frágiles).
            // ✅ FIX metadata editada: se agrega .contentModificationDateKey
            // para poder comparar la fecha en disco contra knownModDates.
            let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                AppLog.error(.library, "No se pudo crear enumerador para: \(url.lastPathComponent)")
                return
            }

            var batch: [URL] = []
            // ✅ FIX metadata editada: acompaña a `batch` con las claves de
            // ESE lote que son actualizaciones (archivo ya indexado, pero con
            // fecha de modificación más nueva), no altas nuevas. Va pegado al
            // lote (no a una variable compartida) para que no exista ninguna
            // ventana de tiempo entre "se detecta la modificación" y "se
            // aplica el filtro" en el main.
            var batchModifiedKeys = Set<String>()
            // URLs ya indexadas NO entran a la cola de metadatos, SALVO que
            // su fecha de modificación en disco haya cambiado (ver abajo).
            // (registerMetadataBatch también filtra como segunda barrera.)
            var seenKeys = Set<String>()
            seenKeys.reserveCapacity(1024)
            var fileCount = 0
            for case let fileURL as URL in enumerator {
                // ✅ SEGURIDAD: capturar excepciones de recursos corruptos
                // para que un archivo problemático no detenga toda la carpeta
                let values = try? fileURL.resourceValues(forKeys: Set(keys))
                // ✅ A8: los directorios se saltan aquí y basta. El
                // FileManager.enumerator ya es recursivo (no se pasa
                // .skipsSubdirectoryDescendants) y su enumeración se recorre
                // en ESTE mismo bucle, así que las subcarpetas se escanean
                // sin recursión manual. La rama recursiva que había debajo
                // era INALCANZABLE (este mismo `if` con `continue` la
                // precedía) y se eliminó sin pérdida de funcionalidad.
                if values?.isDirectory == true { continue }
                
                guard self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }

                fileCount += 1
                let key = Self.libraryKey(for: fileURL)
                seenKeys.insert(key)
                
                if knownKeys.contains(key) {
                    // ✅ FIX metadata editada: si el archivo ya estaba
                    // indexado, solo se re-lee cuando su fecha de
                    // modificación en disco es MÁS RECIENTE que la que se
                    // guardó la última vez (edición externa de tags).
                    // ✅ UPGRADE DE CÓDEC: además se re-lee si su contenedor
                    // todavía no tiene el FourCC leído (ver
                    // knownCodecUpgradeKeys) — una sola vez por canción.
                    var shouldRefresh = knownCodecUpgradeKeys.contains(key)
                    if let diskDate = values?.contentModificationDate,
                       let savedDate = knownModDates[key],
                       diskDate > savedDate {
                        shouldRefresh = true
                    }
                    if shouldRefresh {
                        batchModifiedKeys.insert(key)
                        batch.append(fileURL)
                        if batch.count == self.metadataBatchSize {
                            self.registerMetadataBatch(batch, generation: generation, silent: silent, modifiedKeys: batchModifiedKeys)
                            batch.removeAll(keepingCapacity: true)
                            batchModifiedKeys.removeAll(keepingCapacity: true)
                        }
                    }
                    continue
                }
                
                batch.append(fileURL)
                if batch.count == self.metadataBatchSize {
                    // ✅ FIX: propagar `silent` — sin esto, los lotes de la
                    // detección silenciosa entraban por la vía NORMAL
                    // (scanTotal += n → isScanning = true a mitad de la
                    // detección, aparecía la tarjeta compacta al abrir la app).
                    self.registerMetadataBatch(batch, generation: generation, silent: silent, modifiedKeys: batchModifiedKeys)
                    batch.removeAll(keepingCapacity: true)
                    batchModifiedKeys.removeAll(keepingCapacity: true)
                }
            }
            if !batch.isEmpty { self.registerMetadataBatch(batch, generation: generation, silent: silent, modifiedKeys: batchModifiedKeys) }
            AppLog.debug(.library, "Carpeta \(url.lastPathComponent): \(fileCount) archivos encontrados")
            // ✅ Registrar TODAS las URLs vistas (indexadas o no) para poder
            // podar al final las canciones borradas del disco. Un solo envío
            // al main por carpeta (no uno por archivo): con 722 canciones
            // eran 722 dispatches que saturaban el main.
            let folderSeenKeys = seenKeys
            // ✅ A7: se envía SIEMPRE (aunque no haya claves) para poder contar
            // la carpeta como "enumerada con éxito" también cuando está vacía;
            // con el envío condicional anterior, una carpeta vacía habría
            // deshabilitado la poda para siempre.
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.scanGeneration else { return }
                self.seenOnDiskKeys.formUnion(folderSeenKeys)
                // ✅ A7: el enumerador se creó y el recorrido terminó sin
                // fallar → esta carpeta cuenta para la salvaguarda de poda.
                if silent { self.silentFoldersSucceeded += 1 }
            }
        }
    }

    private func scanSingleFile(_ url: URL, silent: Bool = false) {
        let generation = scanGeneration
        if !silent { isScanning = true }
        // ✅ La URL suelta también cuenta como "vista en disco" para la poda.
        let key = Self.libraryKey(for: url)
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.scanGeneration else { return }
            self.seenOnDiskKeys.insert(key)
            // ✅ A7: mismo trato que las carpetas para los archivos sueltos:
            // si su bookmark no se pudo resolver al arrancar, su clave no
            // queda "vista en disco" y la poda silenciosa NO debe correr.
            if silent { self.silentFilesSucceeded += 1 }
        }
        // ✅ FIX metadata editada: un archivo suelto (fuera de una carpeta)
        // también debe re-leerse si ya estaba indexado pero cambió su fecha
        // de modificación en disco (antes nunca se refrescaba una vez
        // indexado, igual que las carpetas).
        if indexedSongKeys.contains(key) {
            let knownSong = songs.first(where: { Self.libraryKey(for: $0.url) == key })
            // ✅ UPGRADE DE CÓDEC: un archivo suelto cuyo contenedor aún no tiene
            // el FourCC leído se re-lee una vez (misma razón que en scanFolder).
            if knownSong?.needsCodecDetection == true {
                registerMetadataBatch([url], generation: generation, silent: silent, modifiedKeys: [key])
                return
            }
            let knownDate = knownSong?.fileModificationDate
            let diskDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let knownDate, let diskDate, diskDate > knownDate else { return }
            registerMetadataBatch([url], generation: generation, silent: silent, modifiedKeys: [key])
            return
        }
        registerMetadataBatch([url], generation: generation, silent: silent)
    }

    private func registerMetadataBatch(_ urls: [URL], generation: Int, silent: Bool = false, modifiedKeys: Set<String> = []) {
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.scanGeneration else { return }
            // ✅ ESCANEO INCREMENTAL + DEDUPE: filtrar claves ya indexadas Y
            // claves ya reclamadas en ESTA generación. Antes solo se miraba
            // indexedSongKeys (que se actualiza cuando el lote TERMINA), así
            // que la misma canción registrada dos veces (carpetas solapadas,
            // carpeta + archivo suelto) pasaba dos veces el filtro → scanTotal
            // inflado (2000 para 1312). Comparar por RUTA NORMALIZADA.
            // ✅ FIX metadata editada: si la clave viene marcada en
            // `modifiedKeys` (archivo ya indexado pero modificado en disco),
            // SÍ se deja pasar aunque ya esté en indexedSongKeys — antes se
            // descartaba siempre, por eso una edición de tags nunca llegaba
            // a re-leerse.
            let newUrls = urls.filter { url in
                let key = Self.libraryKey(for: url)
                if self.indexedSongKeys.contains(key) && !modifiedKeys.contains(key) { return false }
                return self.registrationClaims.insert("\(generation)|\(key)").inserted
            }
            guard !newUrls.isEmpty else { return }
            if silent {
                // ✅ Silencioso: las nuevas van a una cola aparte con sus
                // propios contadores (no tocan scanTotal/isScanning → la UI
                // ni se entera hasta que haya canciones listas).
                self.silentTotal += newUrls.count
                self.enqueueSilentBatch(newUrls, generation: generation, modifiedKeys: modifiedKeys)
            } else {
                self.scanTotal += newUrls.count
                self.enqueueMetadataBatch(newUrls, generation: generation, modifiedKeys: modifiedKeys)
            }
        }
    }

    private func enqueueMetadataBatch(_ urls: [URL], generation: Int, modifiedKeys: Set<String> = []) {
        queuedBatches.append((urls, generation, modifiedKeys))
        processNextMetadataBatchIfNeeded()
    }

    // ✅ Cola silenciosa: misma ventana acotada que la normal, pero con sus
    // propios contadores y SIN tocar @Published (sin re-renders ni tarjeta).
    // Prioridad .background para no competir con el scroll/animaciones.
    private func enqueueSilentBatch(_ urls: [URL], generation: Int, modifiedKeys: Set<String> = []) {
        silentBatches.append((urls, generation, modifiedKeys))
        processNextSilentBatchIfNeeded()
    }

    private func processNextSilentBatchIfNeeded() {
        guard silentInFlight < 1, !silentBatches.isEmpty else { return }
        let batch = silentBatches.removeFirst()
        let generation = batch.generation
        silentInFlight += 1

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.silentInFlight = max(0, self.silentInFlight - 1)
                    self.processNextSilentBatchIfNeeded()
                    self.finishSilentBatchIfDone(generation: generation)
                }
            }

            let foundSongs: [Song] = await withTaskGroup(of: (Int, Song?).self) { group in
                let initialCount = min(self.maxConcurrentMetadataReads, batch.urls.count)
                for index in 0..<initialCount {
                    group.addTask {
                        (index, await self.makeSong(from: batch.urls[index]))
                    }
                }
                var nextIndex = initialCount
                var results = Array<Song?>(repeating: nil, count: batch.urls.count)
                for await (index, song) in group {
                    results[index] = song
                    if nextIndex < batch.urls.count {
                        let queuedIndex = nextIndex
                        nextIndex += 1
                        group.addTask {
                            (queuedIndex, await self.makeSong(from: batch.urls[queuedIndex]))
                        }
                    }
                }
                return results.compactMap { $0 }
            }

            await MainActor.run {
                guard self.scanGeneration == generation else { return }
                self.silentProcessed += batch.urls.count
                // ✅ FIX metadata editada: las claves de batch.modifiedKeys son
                // ACTUALIZACIONES (canción ya indexada, tag editado): se aceptan
                // y CONSERVAN su `id` original — si cambiara, la canción saldría
                // de "Me Gusta" y de las playlists (guardan songIDs).
                let uniqueSongs = self.mergeFreshlyReadSongs(foundSongs, modifiedKeys: batch.modifiedKeys)
                if !uniqueSongs.isEmpty {
                    self.pendingSongs.append(contentsOf: uniqueSongs)
                }
            }
        }
    }

    // ✅ Al terminar la detección silenciosa: si hubo canciones NUEVAS se hace
    // UN solo sort + UNA sola publicación (sin tarjeta compacta). Si no hubo
    // nada nuevo, no se publica nada: la lista ni parpadea y el arranque es
    // instantáneo.
    private func finishSilentBatchIfDone(generation: Int) {
        guard generation == scanGeneration,
              activeSilentDiscoveries == 0,
              silentBatches.isEmpty,
              silentInFlight == 0 else { return }
        isBackgroundDetecting = false
        let found = silentProcessed
        silentTotal = 0
        silentProcessed = 0
        // ✅ A7: SALVAGUARDA de poda. Solo se poda si TODAS las fuentes
        // registradas terminaron de enumerar con éxito
        // (successCount == folders.count, y lo mismo para los archivos
        // sueltos). Caso borde que evita: si iOS no concede el acceso
        // security-scoped al arrancar (carpeta externa/iCloud aún no
        // disponible, bookmark rancio, permisos reiniciados), las claves de
        // esa carpeta NO están en seenOnDiskKeys → podar con ese conjunto
        // incompleto borraría TODA la biblioteca de la carpeta. Carpeta
        // ilegible ≠ canciones borradas: en ese caso pruneMissingOnFinish
        // queda en false para este ciclo.
        let allSourcesEnumerated = silentFoldersSucceeded == folders.count
            && silentFilesSucceeded == files.count
        silentFoldersSucceeded = 0
        silentFilesSucceeded = 0
        // ¿La poda eliminaría algo? Se decide ANTES de publicar nada: si no
        // hay bajas, el arranque no re-renderiza la lista (mismo
        // comportamiento que antes de A7).
        let pruneDue = allSourcesEnumerated && !seenOnDiskKeys.isEmpty && songs.contains {
            !seenOnDiskKeys.contains(Self.libraryKey(for: $0.url))
        }
        if pruneDue {
            pruneMissingOnFinish = true
            AppLog.info(.library, "Detección silenciosa: poda habilitada (\(folders.count) carpetas + \(files.count) archivos enumerados) · \(found) nuevas")
            // ✅ Mismo cierre que el rescan normal: sort final + poda + UNA
            // sola publicación. isScanning se mantiene false → sin tarjeta ni
            // spinner durante todo el ciclo silencioso.
            finalizeScanIfNeeded()
            return
        }
        // ✅ Las claves vistas por la detección silenciosa no se usan (sin
        // poda en este ciclo). Liberarlas para no retener memoria del
        // enumerado completo.
        seenOnDiskKeys = []
        guard !pendingSongs.isEmpty else {
            AppLog.info(.library, "Detección silenciosa: sin canciones nuevas")
            return
        }
        AppLog.info(.library, "Detección silenciosa: \(found) nuevas, incorporando")
        scheduleSortAndCache()
    }

    // ✅ Descarga un cupo de lote para una generación concreta. Nunca deja el
    // contador en negativo: si la generación ya no tiene cupos (lote doblemente
    // finalizado o un reset) se ignora. Esto protege el límite de concurrencia
    // frente a lotes obsoletos que terminan después de un rescan.
    private func decrementInFlight(generation: Int) {
        guard let count = inFlightByGeneration[generation], count > 0 else { return }
        if count == 1 {
            inFlightByGeneration.removeValue(forKey: generation)
        } else {
            inFlightByGeneration[generation] = count - 1
        }
    }

    private func processNextMetadataBatchIfNeeded() {
        guard inFlightBatches < maxInFlightBatches, !queuedBatches.isEmpty else { return }
        let batch = queuedBatches.removeFirst()
        let generation = batch.generation

        inFlightByGeneration[generation, default: 0] += 1

        // ✅ METADATA FUERA DEL MAIN ACTOR: la lectura de AVAsset (asset.load,
        // item.load) y TaskGroup se ejecutan en background. Antes todo el lote
        // (### 50 URLs × 3 lotes en vuelo) se esperaba/serializaba en el main
        // actor → UI bloqueada, tirones y mayor probabilidad de que la indexación
        // se ralentizara o quedara incompleta en bibliotecas grandes. La mutación
        // del estado @Published (scanProcessed, pendingSongs, songs) sigue en el
        // main actor, pero el trabajo pesado corre fuera.
        Task.detached(priority: .utility) { [weak self, weak batchOwner = self] in
            guard let self else { return }

            // ✅ DEcremento garantizado: "defer" que siempre devuelve el cupo del
            // lote, SIN importar si la generación cambió o hubo error. Se
            // ejecuta en el main actor porque inFlightBatches es estado de la
            // clase (no-atomic). Sin este defer, un lote con generación vieja
            // (rescan iniciado mientras se procesaba) dejaba inFlightBatches
            // alto y la indexación se atascaba → no se procesaban más lotes.
            // ✅ FIX: tras bajar el contador, re-evaluar isScanning y lanzar el
            // siguiente lote. Antes, el defer bajaba inFlightBatches DESPUÉS de
            // la última llamada a updateScanningState(), por lo que isScanning
            // quedaba atascado en true y la fila de progreso no desaparecía.
            defer {
                Task { @MainActor in
                    batchOwner?.decrementInFlight(generation: generation)
                    batchOwner?.updateScanningState()
                    batchOwner?.processNextMetadataBatchIfNeeded()
                }
            }

            // INDEXACIÓN PARALELA CON VENTANA ACOTADA: procesar las URLs del
            // lote con máx `maxConcurrentMetadataReads` lecturas en vuelo.
            // Sin ventana (una tarea por URL del lote) se saturaba CPU/RAM y
            // la UI pegaba tirones. Los índices preservan el orden original
            // para resultados deterministas.
            let foundSongs: [Song] = await withTaskGroup(of: (Int, Song?).self) { group in
                let initialCount = min(self.maxConcurrentMetadataReads, batch.urls.count)
                for index in 0..<initialCount {
                    group.addTask {
                        (index, await self.makeSong(from: batch.urls[index]))
                    }
                }
                var nextIndex = initialCount
                var results = Array<Song?>(repeating: nil, count: batch.urls.count)
                for await (index, song) in group {
                    results[index] = song
                    if nextIndex < batch.urls.count {
                        let queuedIndex = nextIndex
                        nextIndex += 1
                        group.addTask {
                            (queuedIndex, await self.makeSong(from: batch.urls[queuedIndex]))
                        }
                    }
                }
                return results.compactMap { $0 }
            }

            // ✅ Actualizar el estado @Published en el main actor.
            await MainActor.run {
                guard self.scanGeneration == generation else {
                    // Lote obsoleto (nuevo rescan): descartarlo, no encadenar.
                    return
                }
                self.scanProcessed += batch.urls.count
                // ✅ Segunda barrera anti-duplicados (misma clave normalizada que
                // registerMetadataBatch): dos lotes en vuelo pueden traer la
                // misma canción antes de que el otro la registre.
                // ✅ FIX metadata editada: las claves de batch.modifiedKeys son
                // ACTUALIZACIONES (canción ya indexada, tag editado): se aceptan
                // y CONSERVAN su `id` original — si cambiara, la canción saldría
                // de "Me Gusta" y de las playlists (guardan songIDs).
                let uniqueSongs = self.mergeFreshlyReadSongs(foundSongs, modifiedKeys: batch.modifiedKeys)
                if !uniqueSongs.isEmpty {
                    self.pendingSongs.append(contentsOf: uniqueSongs)
                    self.scheduleSortAndCache()
                    AppLog.debug(.library, "Lote cargado: \(uniqueSongs.count); total: \(self.pendingSongs.count)")
                }
                self.updateScanningState()
                self.processNextMetadataBatchIfNeeded()
            }
        }
    }

    private func scheduleSortAndCache() {
        // ✅ Sort diferido: solo se programa una vez, se ejecuta cuando termina el scan
        guard !isSortScheduled else { return }
        isSortScheduled = true

        // ✅ FIX CARRERA DE DATOS: el snapshot se toma AQUÍ, en el main
        // (scheduleSortAndCache siempre se llama desde el main actor). Antes se
        // leía `songs + pendingSongs` dentro del DispatchWorkItem (hilo global)
        // MIENTRAS los MainActor.run de los lotes que terminan hacían
        // pendingSongs.append en el main → read/write concurrente de un Array
        // (corrupción de heap: crash raro e irreproducible en bibliotecas
        // grandes). Las canciones que lleguen durante los 100ms de delay
        // permanecen en pendingSongs y las incorpora el siguiente sort o el
        // final (mismas garantías que había, sin la carrera).
        // ✅ FIX metadata editada: pendingSongs VA PRIMERO. dedupeSongsByUrl
        // conserva la PRIMERA aparición de cada URL — si una canción en
        // pendingSongs es una actualización (mismo URL que una ya presente
        // en `songs`, pero con metadata re-leída), tiene que ganarle a la
        // versión vieja del caché. Con el orden anterior (songs + pendingSongs)
        // la versión vieja siempre ganaba y la edición nunca se reflejaba.
        let snapshot = pendingSongs + songs

        // ✅ Usar DispatchWorkItem para poder cancelar si llega otro lote
        sortWorkItem?.cancel()
        sortWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // ✅ Sort en background (sin sleep, sin bloqueo), sobre la
            // snapshot inmutable capturada en el main.
            // ✅ Deduplicar: un lote que llega mientras se ordena puede quedar
            // en ambas listas → duplicados en la librería (conteo 13 vs 9).
            let sortedSongs = dedupeSongsByUrl(snapshot).sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

            DispatchQueue.main.async {
                self.isSortScheduled = false
                self.songs = sortedSongs
                // ✅ ANTES `pendingSongs.removeAll()` borraba TODO, incluso las
                // canciones que llegaron (desde el main) MIENTRAS se ordenaba en
                // background → se perdían del índice (biblioteca incompleta).
                // Ahora solo se descartan las que SÍ influyeron en el sort; las
                // recién llegadas permanecen en pendingSongs y se incorporan en
                // el siguiente flush / sort final.
                let includedIDs = Set(sortedSongs.map { $0.id })
                self.pendingSongs.removeAll { includedIDs.contains($0.id) }
                self.needsRebuild = true // ✅ Reconstruir álbumes/artistas con nuevas canciones
                self.scheduleCacheSave()
                // Si quedaron canciones por incorporar (caso límite de orden de
                // llegada), re-intentar el flush/sort final.
                if !self.pendingSongs.isEmpty {
                    self.updateScanningState()
                }
            }
        }

        // ✅ OPTIMIZACIÓN: Delay de 0.35s para agrupar lotes (publicación
        // acotada). Publicar `songs` en cada lote re-renderizaba la lista
        // completa + reconstruía álbumes/artistas a 10Hz → tirones. Con el
        // delay, los lotes que llegan en la misma ventana se fusionan en UN
        // solo sort + UNA sola publicación. Más rápido en la práctica y sin
        // tirones (mismo patrón que el debounce del buscador).
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.35, execute: sortWorkItem!)
    }

    private func finishDiscovery(generation: Int, silent: Bool = false) {
        guard generation == scanGeneration else { return }
        if silent {
            activeSilentDiscoveries = max(0, activeSilentDiscoveries - 1)
            finishSilentBatchIfDone(generation: generation)
            return
        }
        activeDiscoveries = max(0, activeDiscoveries - 1)
        updateScanningState()
    }

    private func updateScanningState() {
        let wasScanning = isScanning
        // ✅ FIX: isScanning también debe considerar los lotes pendientes de
        // procesar. Antes, si finishDiscovery bajaba activeDiscoveries a 0 pero
        // quedaban lotes en la cola, isScanning pasaba a false prematuramente y
        // el sort final tomaba `songs + pendingSongs` INCOMPLETO.
        let hasPendingWork = !queuedBatches.isEmpty || inFlightBatches > 0
        // ✅ FIX CONGELAMIENTO: si no queda trabajo pendiente NI descubrimientos
        // activos, cerrar AUNQUE scanProcessed < scanTotal. Los lotes huérfanos
        // de una generación obsoleta (un backgroundScan o rescan que llegó
        // mientras este escaneaba) se descartan SIN contar en scanProcessed →
        // el contador nunca cuadraba → isScanning atascado en true y la barra
        // de progreso congelada para siempre. Con esta condición, al no quedar
        // nada por hacer el estado cierra limpio.
        isScanning = activeDiscoveries > 0 || hasPendingWork

        // ✅ Al finalizar: verificar si hay sort pendiente que ejecutar.
        // El rescan DIFERENCIAL también debe cerrar aunque NO haya canciones
        // nuevas (pendingSongs vacío): si no, la poda de borrados nunca corre
        // y el pruneMissingOnFinish quedaría pendiente para siempre.
        if wasScanning && !isScanning {
            finalizeScanIfNeeded()
        }
    }

    /// ✅ A7: cierre común de un escaneo (normal o silencioso), extraído de
    /// updateScanningState SIN cambiar su semántica: fusiona pendingSongs +
    /// songs, aplica la PODA de borrados si pruneMissingOnFinish está activo
    /// y publica el resultado en UN solo sort + UNA sola publicación.
    /// El escaneo silencioso lo usa para poder podar sin tocar `isScanning`
    /// (sin tarjeta de progreso ni spinner).
    private func finalizeScanIfNeeded() {
        guard (!pendingSongs.isEmpty || pruneMissingOnFinish), !isSortScheduled else { return }
        // ✅ Final sort en background para evitar congelamiento (sin sleep)
        isSortScheduled = true
        let shouldPrune = pruneMissingOnFinish
        let seenKeys = seenOnDiskKeys
        // ✅ Deduplicar al fusionar (mismos duplicados que en el sort de arriba).
        // ✅ FIX metadata editada: mismo motivo que en scheduleSortAndCache
        // — pendingSongs primero para que una actualización le gane a la
        // versión vieja cacheada en el dedupe por URL.
        var allSongs = dedupeSongsByUrl(pendingSongs + songs)
        if shouldPrune, !seenKeys.isEmpty {
            // ✅ Podar borrados: conserva las que se vieron en disco. Con
            // Set vacío NO se poda (carpeta ilegible ≠ canciones borradas).
            allSongs = allSongs.filter { seenKeys.contains(Self.libraryKey(for: $0.url)) }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            // ✅ FIX: Orden alfabético por título como ordenamiento por defecto.
            // Esto asegura que las canciones tengan un orden consistente al cargar
            // desde disco, mientras las opciones del usuario pueden cambiar este orden.
            let sortedSongs = allSongs.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

            DispatchQueue.main.async {
                self.isSortScheduled = false
                let addedCount = sortedSongs.count - self.songs.count
                self.songs = sortedSongs
                self.indexedSongKeys = Set(sortedSongs.map { Self.libraryKey(for: $0.url) })
                self.pruneMissingOnFinish = false
                self.seenOnDiskKeys = []
                // ✅ Solo descartar las canciones que entraron en el sort. Las
                // que llegaron mientras se ordenaba (p.ej. del lote final) NO
                // se borran: permanecen en pendingSongs para una pasada final.
                let includedIDs = Set(sortedSongs.map { $0.id })
                self.pendingSongs.removeAll { includedIDs.contains($0.id) }
                self.needsRebuild = true // ✅ Reconstruir álbumes/artistas con nuevas canciones
                self.scheduleCacheSave()
                if addedCount > 0 {
                    AppLog.info(.library, "Indexación completada: \(sortedSongs.count) canciones (+\(addedCount) nuevas) · RAM \(self.residentMemoryMB) MB")
                } else {
                    AppLog.info(.library, "Indexación completada: \(sortedSongs.count) canciones (sin cambios) · RAM \(self.residentMemoryMB) MB")
                }
                if !self.pendingSongs.isEmpty {
                    self.updateScanningState()
                }
            }
        }
    }

    private func beginIncrementalProgressIfNeeded() {
        guard !isScanning else { return }
        scanTotal = 0
        scanProcessed = 0
    }

    /// ✅ FIX metadata editada: IDs de las canciones YA indexadas por ruta
    /// normalizada. Se usa como lookup para que una re-lectura conserve la
    /// identidad (`id`) de la versión en caché — ver `mergeFreshlyReadSongs`.
    /// `songs` (publicada) manda; `pendingSongs` solo cubre las que todavía no
    /// entraron al sort.
    private func existingSongIDsByKey() -> [String: UUID] {
        var lookup: [String: UUID] = [:]
        lookup.reserveCapacity(songs.count + pendingSongs.count)
        for song in songs {
            lookup[Self.libraryKey(for: song.url)] = song.id
        }
        for song in pendingSongs where lookup[Self.libraryKey(for: song.url)] == nil {
            lookup[Self.libraryKey(for: song.url)] = song.id
        }
        return lookup
    }

    /// ✅ FIX metadata editada: fusiona las canciones recién leídas de un lote
    /// aplicando la barrera anti-duplicados de siempre, pero tratando las
    /// claves de `modifiedKeys` (archivo ya indexado cuyo tag cambió) como
    /// ACTUALIZACIONES: se aceptan y CONSERVAN el `id` original.
    /// Debe llamarse en el main actor (mutar `indexedSongKeys`).
    private func mergeFreshlyReadSongs(_ foundSongs: [Song], modifiedKeys: Set<String>) -> [Song] {
        guard !modifiedKeys.isEmpty else {
            return foundSongs.filter { self.indexedSongKeys.insert(Self.libraryKey(for: $0.url)).inserted }
        }
        let idLookup = existingSongIDsByKey()
        return foundSongs.compactMap { song -> Song? in
            let key = Self.libraryKey(for: song.url)
            if modifiedKeys.contains(key) {
                guard let existingID = idLookup[key], existingID != song.id else { return song }
                return song.preservingID(existingID)
            }
            return self.indexedSongKeys.insert(key).inserted ? song : nil
        }
    }

    private func makeSong(from url: URL) async -> Song? {
        // ✅ CONTENEDORES MP4/M4V: iOS envuelve Dolby Digital Plus (E-AC-3) en
        // MP4. Se indexan para poder detectar el códec real y reproducirlo con
        // AVPlayer, pero SOLO si son audio: un .mp4 de vídeo (película,
        // videoclip) no es una canción y no debe entrar en la biblioteca. Los
        // dos llamadores ya tratan el resultado como opcional
        // (`withTaskGroup(of: (Int, Song?))` + `compactMap`), así que devolver
        // nil aquí descarta el archivo sin tocar el resto del escaneo.
        if Self.videoContainerExtensions.contains(url.pathExtension.lowercased()) {
            let asset = AVAsset(url: url)
            let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            guard videoTracks.isEmpty else {
                AppLog.info(.metadata, "Omitido \(url.lastPathComponent): contenedor de vídeo (no es audio)")
                return nil
            }
        }
        let metadata = await readMetadata(from: url)
        // ✅ FIX metadata editada: guardar la fecha de modificación del
        // archivo tal como estaba AL MOMENTO de esta lectura. scanFolder
        // compara este valor contra la fecha actual en disco en el próximo
        // escaneo para decidir si hace falta re-leer metadata.
        let modDate: Date? = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return Song(url: url, title: metadata.title, artist: metadata.artist, albumArtist: metadata.albumArtist, album: metadata.album, artworkData: metadata.artworkData, duration: metadata.duration, lyrics: metadata.lyrics, formatDescription: metadata.formatDescription, discNumber: metadata.discNumber, trackNumber: metadata.trackNumber, releaseDate: metadata.releaseDate, sampleRate: metadata.sampleRate, bitDepth: metadata.bitDepth, channelCount: metadata.channelCount, bitrate: metadata.bitrate, fileModificationDate: modDate, codecName: metadata.codecName)
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
        let sampleRate: Double
        let bitDepth: Int
        let channelCount: Int
        let bitrate: Int?
        /// ✅ CÓDEC REAL del stream (FourCC): "ec-3", "ac-3", "mp4a"…
        let codecName: String?
    }

    // MARK: - readMetadata (OPTIMIZADO: una sola apertura de archivo, sin lecturas redundantes, con timeout)
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
        // ✅ dateIsStrong vive en el scope COMPLETO del método: el parser
        // binario de abajo lo consulta para saber si debe confirmar una fecha
        // que vino solo de fuente débil (ver "Prioridad de fechas").
        var dateIsStrong = false
        // ⛔️ FECHA DE ARCHIVO PROHIBIDA: la fecha de creación del archivo
        // (cuándo se copió/descargó) NUNCA se usa como año. Era la causa
        // principal del "álbum de 2023 con año 2026". Si el archivo no trae
        // tag de año real (TDRC/TDRL/TDOR/TYER/©day/DATE), releaseDate queda
        // nil: la canción se ordena al final y el álbum no muestra pill de
        // año. Mejor SIN año que con un año INVENTADO.
        var duration: TimeInterval = 0

        // ✅ Timeout para evitar que archivos corruptos congelen la indexación
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 segundos timeout
        }

        do {
            // ✅ OPTIMIZACIÓN: Cargar TODOS los valores en paralelo
            async let durationTask = asset.load(.duration)
            async let commonMetadataTask = asset.load(.commonMetadata)
            
            let commonMetadata = try await commonMetadataTask
            let durationTime = try await durationTask
            duration = durationTime.seconds

            // ✅ Cancelar timeout si carga fue exitosa
            timeoutTask.cancel()

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
                // ⛔️ "creationDate" NO se lee: puede ser la fecha del ARCHIVO
                // (no del lanzamiento). El año real viene por formatMetadata
                // (TDRC/TDRL/TDOR/TYER/©day) o por el parser binario.
                default:
                    break
                }
            }

            // Solo leer formatMetadata si faltan campos esenciales O la fecha.
            // (La fecha va separada: un tema puede traer título/artista pero
            // sin año en commonMetadata; sin esto el tag real ©day/TDRC/DATE
            // jamás se leía y el álbum caía al creationDate del archivo.)
            if title == nil || artist.isEmpty || album.isEmpty || albumArtist.isEmpty || lyrics.isEmpty || releaseDate == nil {
                let availableFormats = try await asset.load(.availableMetadataFormats)
                var formatMetadata: [AVMetadataItem] = []

                for format in availableFormats {
                    let metadata = try await asset.loadMetadata(for: format)
                    formatMetadata.append(contentsOf: metadata)
                }

                var strongReleaseDate: Date?
                var weakReleaseDate: Date?
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
                    if discNumber == nil, identifier.contains("discnumber") || identifier.contains("disknumber") || key.contains("disk") || key.contains("tpos") {
                        discNumber = await metadataNumberAsync(item)
                    }
                    if trackNumber == 0, identifier.contains("tracknumber") || key.contains("trkn") || key.contains("trck") {
                        trackNumber = (await metadataNumberAsync(item)) ?? 0
                    }
                    // ✅ FIX DEFINITIVO año 2026 (TDEN): los rippers (foobar2000,
                    // Mp3tag…) escriben la fecha de RIP/ENCODE en TDEN ("encoding
                    // date"). TDEN contiene "date" y NO "creation", y como el
                    // bucle tomaba el PRIMER item de fecha, TDEN (año del rip
                    // = 2026) ganaba sobre TDRC (año real = 2023). Ahora se
                    // excluyen las fechas TÉCNICAS y se PRIORIZAN los tags de
                    // release (TDRC/TDRL/TDOR/TYER/©day) sobre los genéricos.
                    let isDateTag = identifier.contains("date") || identifier.contains("year") || key.contains("day") || key.contains("tdrc")
                    // ⛔️ FECHAS TÉCNICAS PROHIBIDAS (además de creación/TDEN/TENC/
                    // encoded): las fechas de SÍNCRONIZACIÓN que iTunes añade con el
                    // año del momento — dateAdded / purchaseDate / playDate /
                    // lastPlayedDate / encodingDate / modificationDate / uploadDate…
                    // valen 2026 en un álbum de 2023. Recuerda que el identificador
                    // llega normalizado: "com.apple.iTunes:dateAdded" →
                    // "comappleitunesdateadded".
                    let isTechnicalDate = identifier.contains("creation") || identifier.contains("tden") || identifier.contains("tenc")
                        || identifier.contains("encod") || identifier.contains("added") || identifier.contains("purchas")
                        || identifier.contains("playdate") || identifier.contains("lastplayed") || identifier.contains("modif")
                        || identifier.contains("updat") || identifier.contains("upload") || identifier.contains("download")
                    if isDateTag, !isTechnicalDate {
                        let parsed = await metadataDateAsync(item)
                        let isReleaseTag = identifier.contains("tdrc") || identifier.contains("tdrl") || identifier.contains("tdor") || identifier.contains("tyer") || key.contains("day") || key.contains("year")
                        if isReleaseTag {
                            if strongReleaseDate == nil { strongReleaseDate = parsed }
                        } else if weakReleaseDate == nil {
                            weakReleaseDate = parsed
                        }
                    }
                    if lyrics.isEmpty {
                        let id = self.normalizedMetadataIdentifier(item)
                        let key = self.metadataKey(item)
                        if item.commonKey?.rawValue == "lyrics" || id.contains("lyric") || key.contains("lyr") || key == "uslt" || key == "sylt" {
                            let candidateLyrics = await lyricsText(item)
                            if !candidateLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                lyrics = candidateLyrics
                            }
                        }
                    }
                }

                // ✅ Prioridad de fechas: tag de RELEASE (TDRC/TDRL/TDOR/TYER/©day)
                // > tag de fecha genérico. Nunca una fecha técnica (TDEN/creación/
                // dateAdded/purchaseDate/playDate…).
                // dateIsStrong marca si el año salió de un tag de release REAL;
                // si solo hubo fecha débil, el parser binario podrá confirmarla.
                dateIsStrong = strongReleaseDate != nil
                releaseDate = strongReleaseDate ?? weakReleaseDate
            }

            // Fallback binario SOLO si faltan campos esenciales (evita doble lectura de archivo)
            // Incluye lyrics: AVFoundation a menudo NO mapea USLT/SYLT/©lyr/LYRICS
            // (ID3, FLAC vorbis) a commonKey, y sin esto las letras jamás se extraían.
            // La fecha también va incluida: puede faltar aunque el resto exista. También
            // corre cuando la fecha vino SOLO de una fuente débil (dateIsStrong == false):
            // el parser binario lee frames de release reales y debe poder confirmarla.
            if title == nil || artist.isEmpty || album.isEmpty || lyrics.isEmpty || releaseDate == nil || !dateIsStrong {
                if let embedded = readID3Metadata(from: url) ?? readFLACMetadata(from: url) ?? readM4AMetadata(from: url) {
                    title = title ?? embedded.title
                    if artist.isEmpty { artist = embedded.artist ?? "" }
                    if albumArtist.isEmpty { albumArtist = embedded.albumArtist ?? "" }
                    if album.isEmpty { album = embedded.album ?? "" }
                    if trackNumber == 0 { trackNumber = embedded.trackNumber ?? 0 }
                    if discNumber == nil { discNumber = embedded.discNumber }
                    // ✅ La fecha del parser binario (SOLO frames reales de release:
                    // TDRC/TYER/©day/DATE/YEAR) GANA sobre la fecha débil de
                    // AVFoundation. Antes, una fecha débil (p.ej. dateAdded=2026)
                    // dejaba releaseDate != nil y el TDRC real (2023) jamás se leía.
                    if releaseDate == nil || !dateIsStrong { releaseDate = embedded.releaseDate ?? releaseDate }
                    if lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lyrics = embedded.lyrics ?? "" }
                }
            }

            // ⛔️ Sin fallback de fecha de archivo: si ningún tag trajo año,
            // releaseDate queda nil (mejor sin año que con año inventado).
            let assetDuration = try await durationTask
            duration = assetDuration.isNumeric ? max(0, assetDuration.seconds) : 0

        } catch {
            // ✅ Manejar timeout y errores sin interrumpir toda la indexación
            timeoutTask.cancel()
            AppLog.error(.library, "Error cargando metadatos: \(error.localizedDescription) - \(url.lastPathComponent)")

            // ✅ Fallback básico para que el archivo no se pierda
            if title == nil {
                title = url.deletingPathExtension().lastPathComponent
            }
            if artist.isEmpty {
                artist = Localization.localized("details.unknownArtist")
            }
            if album.isEmpty {
                album = Localization.localized("details.unknownAlbum")
            }
        }

        // Obtener sample rate, bit depth y canales del archivo de audio.
        // ✅ FIX bit depth ausente en la UI: AVAudioFile.fileFormat reporta
        // mBitsPerChannel = 0 para FLAC/ALAC, así que se lee el ASBD real del
        // audioTrack del asset. Además se evita re-abrir el archivo (tirones
        // de indexación con cientos de cargas concurrentes).
        var sampleRate: Double = 0
        var bitDepth: Int = 0
        var channelCount: Int = 0
        var bitrateKbps: Int?
        /// ✅ CÓDEC REAL del stream de audio (FourCC del track, no la extensión).
        var detectedCodec: String?
        let audioTrack: AVAssetTrack? = (try? await asset.loadTracks(withMediaType: .audio))?.first
        if let track = audioTrack {
            let formatDescriptions = try? await track.load(.formatDescriptions)
            if let firstDesc = formatDescriptions?.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(firstDesc) {
                // ✅ DETECCIÓN DE CÓDEC: CMFormatDescriptionGetMediaSubType da el
                // FourCC del stream (el ASBD no distingue E-AC-3 de AAC).
                detectedCodec = Self.fourCCString(CMFormatDescriptionGetMediaSubType(firstDesc))
                if AudioCodec.isDolby(detectedCodec) {
                    AppLog.info(.metadata, "Dolby detectado (\(detectedCodec ?? "?")) en \(url.lastPathComponent) → reproducción por AVPlayer")
                }
                sampleRate = Double(asbd.pointee.mSampleRate)
                channelCount = Int(asbd.pointee.mChannelsPerFrame)
                let fileBits = Int(asbd.pointee.mBitsPerChannel)
                // ✅ FIX bit depth FLAC/ALAC: inferir del bitrate cuando el ASBD
                // reporta 0 (ver inferBitDepth).
                bitDepth = Self.inferBitDepth(
                    fileBits: fileBits,
                    formatID: asbd.pointee.mFormatID,
                    ext: url.pathExtension,
                    sampleRate: sampleRate
                )
                // ✅ DEBUG: Log para verificar extracción de bitDepth
                AppLog.debug(.metadata, "Archivo: \(url.lastPathComponent) - bitDepth extraído: \(bitDepth) (raw: \(fileBits))")
            }
        }
        // ✅ LOSSLESS → profundidad real; LOSSY (MP3/AAC, bitDepth 0) →
        // bitrate medio en kbps (la "calidad" equivalente del codec).
        if bitDepth == 0, let track = audioTrack {
            let rate = try? await track.load(.estimatedDataRate)
            if let rate = rate, rate.isFinite, rate > 0 { bitrateKbps = Int(rate / 1000) }
        }
        // Formato: la etiqueta sale del códec REAL cuando se conoce (evita abrir
        // AVAudioFile y evita anunciar "MP4" un archivo Dolby).
        let formatDescription = [
            Self.formatLabel(for: url.pathExtension, codecName: detectedCodec),
            bitDepth > 0 ? "\(bitDepth) bits" : nil,
            bitrateKbps.map { "~\($0) kbps" } ?? nil,
            sampleRate > 0 ? "\(Int(sampleRate / 1000)) kHz" : nil
        ]
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
            releaseDate: releaseDate,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channelCount: channelCount,
            bitrate: bitrateKbps,
            codecName: detectedCodec
        )
    }

    // Fallback asíncrono moderno (si falla la carga principal). Sin APIs deprecadas.
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
        // ⛔️ Igual que en readMetadata: fecha de archivo PROHIBIDA.
        var durationSeconds: Double = 0

        do {
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
                // ⛔️ "creationDate" NO se lee (fecha del archivo ≠ lanzamiento).
                default:
                    break
                }
            }
            let assetDuration = try await asset.load(.duration)
            durationSeconds = assetDuration.isNumeric ? max(0, assetDuration.seconds) : 0
        } catch {
            AppLog.error(.library, "readMetadataFallback: \(error.localizedDescription)")
        }

        // Fallback binario (ID3/FLAC/M4A) para lo que AVFoundation no mapea.
        // La fecha también va incluida: puede faltar aunque el resto exista.
        if title == nil || artist.isEmpty || album.isEmpty || lyrics.isEmpty || releaseDate == nil {
            if let embedded = readID3Metadata(from: url) ?? readFLACMetadata(from: url) ?? readM4AMetadata(from: url) {
                // ✅ FIX "símbolos raros": AVFoundation a veces devuelve texto
                // corrupto (mojibake / U+FFFD) según la codificación del tag.
                // Antes ese valor corrupto bloqueaba al parser binario (que solo
                // rellenaba campos vacíos). Ahora el parser binario SIEMPRE
                // reemplaza valores corruptos.
                if title == nil || isCorruptText(title) { title = embedded.title ?? title }
                if artist.isEmpty || isCorruptText(artist) { artist = embedded.artist ?? artist }
                if albumArtist.isEmpty || isCorruptText(albumArtist) { albumArtist = embedded.albumArtist ?? albumArtist }
                if album.isEmpty || isCorruptText(album) { album = embedded.album ?? album }
                if trackNumber == 0 { trackNumber = embedded.trackNumber ?? 0 }
                if discNumber == nil { discNumber = embedded.discNumber }
                if releaseDate == nil { releaseDate = embedded.releaseDate }
                if lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lyrics = embedded.lyrics ?? "" }
            }
        }

        // (La fecha de creación del archivo NUNCA se usa: año nil si no hay tag.)

        // ✅ FIX bit depth ausente en la UI: igual que en readMetadata, el ASBD
        // real se lee del audioTrack del asset (AVAudioFile reporta 0 bits
        // para FLAC/ALAC y re-abre el archivo).
        let audioTrack = (try? await asset.loadTracks(withMediaType: .audio))?.first
        let sampleRate: Double
        let fileBits: Int
        let channels: Int
        /// ✅ CÓDEC REAL del stream (FourCC): mismo criterio que en readMetadata
        /// (aquí el archivo no se pudo leer con AVAsset completo, pero el track
        /// de audio sí está y su FourCC es la única fuente fiable del codec).
        var fallbackCodec: String?
        if let track = audioTrack {
            let formatDescriptions = try? await track.load(.formatDescriptions)
            if let firstDesc = formatDescriptions?.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(firstDesc) {
                fallbackCodec = Self.fourCCString(CMFormatDescriptionGetMediaSubType(firstDesc))
                sampleRate = Double(asbd.pointee.mSampleRate)
                fileBits = Int(asbd.pointee.mBitsPerChannel)
                channels = Int(asbd.pointee.mChannelsPerFrame)
            } else {
                sampleRate = 0
                fileBits = 0
                channels = 0
            }
        } else {
            sampleRate = 0
            fileBits = 0
            channels = 0
        }
        let bits = Self.inferBitDepth(
            fileBits: fileBits,
            formatID: 0, // fallback: decisión por extensión
            ext: url.pathExtension,
            sampleRate: sampleRate
        )
        // ✅ LOSSLESS → bits reales; LOSSY (bitDepth 0) → bitrate medio kbps.
        var lastFormatBitrate: Int?
        if bits == 0, let track = audioTrack {
            let rate = try? await track.load(.estimatedDataRate)
            if let rate = rate, rate.isFinite, rate > 0 { lastFormatBitrate = Int(rate / 1000) }
        }
        let formatDescription = [Self.formatLabel(for: url.pathExtension, codecName: fallbackCodec), bits > 0 ? "\(bits) bits" : nil, lastFormatBitrate.map { "~\($0) kbps" } ?? nil, sampleRate > 0 ? "\(Int(sampleRate / 1000)) kHz" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")

        return SongMetadata(
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            artworkData: artworkData,
            duration: durationSeconds,
            lyrics: lyrics,
            formatDescription: formatDescription,
            discNumber: discNumber,
            trackNumber: trackNumber,
            releaseDate: releaseDate,
            sampleRate: sampleRate,
            bitDepth: Int(bits),
            channelCount: Int(channels),
            bitrate: lastFormatBitrate,
            codecName: fallbackCodec
        )
    }

    private func thumbnailArtwork(_ data: Data) -> Data {
        // ✅ PUNTO DULCE NITIDEZ/MEMORIA: 768px @ 0.72.
        // - 640px (original) se veía borroso en NowPlaying (350pt @2x = 700px).
        // - 1280px (intento anterior) CRASHEABA a ~900 canciones: ~300KB de Data
        //   por portada × 900 = ~270MB en el JSON de caché, y 6.5MB decodificados
        //   por imagen en el artworkCache → jetsam kill.
        // - 768px: cubre el tamaño máximo de display (350pt@2x) con nitidez,
        //   ~120KB por Data y 2.4MB decodificados → 3× menos memoria.
        // - q 0.72 (antes 0.8): ~15% menos bytes por portada en disco/RAM con
        //   calidad visual idéntica a 768px (los artefactos del JPEG son
        //   inapreciables a este tamaño); bibliotecas de 1300+ temas bajan
        //   ~25-30MB de RAM (aviso de memoria repetido en iPhone 8 / 2GB).
        guard data.count > 100_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 768,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let compressed = UIImage(cgImage: image).jpegData(compressionQuality: 0.72) else { return data }
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

    private func metadataKey(_ item: AVMetadataItem) -> String {
        guard let key = item.key else { return "" }
        return String(describing: key).lowercased()
    }

    private func lyricsText(_ item: AVMetadataItem) async -> String {
        let key = metadataKey(item)
        let identifier = normalizedMetadataIdentifier(item)
        let isSynchronizedID3 = key == "sylt" || identifier.contains("sylt")
        
        guard (key == "uslt" || isSynchronizedID3 || identifier.contains("uslt")),
              let data = try? await item.load(.dataValue) else {
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
        // ✅ El año mostrado es el ESCRITO en el tag: parsear el TEXTO antes
        // que dateValue. dateValue devuelve un instante absoluto y, en zonas
        // negativas, "2023-01-01T00:00:00Z" cae al 31 dic del año anterior.
        if let raw = (await metadataText(item))?.nilIfEmpty,
           let parsed = Self.parseReleaseDate(raw) {
            return parsed
        }
        if let date = try? await item.load(.dateValue) {
            // Fallback sin texto (o texto no parseable): normalizar el
            // instante a medianoche LOCAL (día del calendario local) en
            // gregoriano para consistencia con el parser.
            let calendar = Calendar(identifier: .gregorian)
            return calendar.date(from: calendar.dateComponents([.year, .month, .day], from: date))
        }
        return nil
    }

    /// ✅ Parser TOLERANTE de fechas de tags: los años reales vienen en
    /// muchos formatos ("2023", "2023-05-17", "2023/05/17", "17-05-2023",
    /// "17.05.2023", "2023-05-17T...Z", "© 2023", "2023; 2023-05-01"...).
    /// El parser anterior solo aceptaba ISO8601 / yyyy-MM-dd / yyyy → cualquier
    /// otra variante devolvía nil y la canción caía al creationDate (2026).
    ///
    /// ✅ FIX AÑO INCORRECTO: el año que se MUESTRA debe ser el ESCRITO en el
    /// tag, no el instante convertido a la zona local. Antes, una fecha ISO con
    /// hora y offset ("2023-01-01T00:00:00Z") se convertía como instante
    /// absoluto y, en zonas negativas (UTC-6), el 1 de enero caía al 31 de
    /// diciembre del año ANTERIOR → álbumes lanzados un 1 de enero (muy común
    /// en recopilaciones/greatest hits) mostraban 2022 en vez de 2023. Todas
    /// las rutas devuelven una fecha a MEDIANOCHE LOCAL construida con los
    /// componentes escritos.
    static func parseReleaseDate(_ raw: String) -> Date? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // "2023; 2023-05-01" → quedarse con el primer valor.
        if let semi = text.firstIndex(of: ";") { text = String(text[..<semi]).trimmingCharacters(in: .whitespacesAndNewlines) }
        // ✅ Cortar la parte de HORA de ISO ("2023-01-01T00:00:00Z" →
        // "2023-01-01" y "2023-05-17 12:00:00" → "2023-05-17"): el año mostrado
        // es el escrito en el tag, y la hora + offset solo sirven para
        // desviarlo a la zona local (año −1).
        if let t = text.firstIndex(of: "T"), t > text.startIndex {
            text = String(text[..<t]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let space = text.firstIndex(of: " "), text.contains(":") {
            // "yyyy-MM-dd HH:mm:ss" → quedarse solo con la fecha
            text = String(text[..<space]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // ✅ Fechas ambiguas con año al FINAL ("17-05-2023", "17/05/2023",
        // "05-17-2023", "17.05.2023"): resolver de forma DETERMINISTA antes
        // del parser lenient (que podría leer "17" como año → 17/2017). El
        // valor >12 es el día; si ninguno lo excede se asume día-primero
        // (convención común en es/LatAm).
        if text.range(of: "^\\d{1,2}[./-]\\d{1,2}[./-]\\d{4}$", options: .regularExpression) != nil {
            let parts = text.components(separatedBy: CharacterSet(charactersIn: "-/."))
            if parts.count == 3,
               let y = Int(parts[2]), (1900...2100).contains(y),
               let a = Int(parts[0]), let b = Int(parts[1]) {
                let (day, month) = a > 12 ? (a, b) : (b, a)
                if (1...31).contains(day), (1...12).contains(month) {
                    var c = DateComponents()
                    c.year = y; c.month = month; c.day = day
                    return Calendar(identifier: .gregorian).date(from: c)
                }
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = true
        // ✅ Solo formatos año-PRIMERO (desambiguados arriba los que tienen el
        // año al final). Sin offsets ni horas: la hora ya se cortó antes.
        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "yyyyMMdd", "yyyy-MM", "yyyyMM", "yyyy"] {
            formatter.dateFormat = format
            guard let date = formatter.date(from: text) else { continue }
            // ✅ Acotación de cordura: descartar años imposibles (9999, 1…)
            // que el parser lenient podría fabricar con textos raros.
            let year = Calendar(identifier: .gregorian).component(.year, from: date)
            if (1900...2100).contains(year) { return date }
        }
        // Último recurso: extraer el primer año de 4 dígitos (1900–2100).
        // "© 2023 Remaster" → 2023 en vez de nil → creationDate.
        if let regex = try? NSRegularExpression(pattern: "(19|20)\\d{2}") {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let yearRange = Range(match.range, in: text),
               let year = Int(text[yearRange]),
               (1900...2100).contains(year) {
                var components = DateComponents()
                components.year = year
                components.month = 1
                components.day = 1
                return Calendar(identifier: .gregorian).date(from: components)
            }
        }
        return nil
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

    /// ✅ Detecta texto corrupto de metadatos: caracteres de reemplazo (U+FFFD),
    /// controles raros o símbolos de mojibake típicos (Ã, â€, etc.).
    private func isCorruptText(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        if value.contains("\u{FFFD}") { return true }
        let scalars = value.unicodeScalars
        if scalars.contains(where: { $0.value < 0x20 && $0 != "\n" && $0 != "\r" && $0 != "\t" }) { return true }
        // Mojibake clásico UTF-8 leído como Latin-1 / Windows-1252
        if value.contains("Ã") || value.contains("â€") || value.contains("Â") { return true }
        return false
    }

    private func id3Text(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard let encoding = bytes.first, bytes.count > 1 else { return nil }
        let text = Data(bytes.dropFirst())
        let value: String?
        switch encoding {
        case 0:
            // ✅ FIX mojibake: muchos tags declaran Latin-1 pero contienen UTF-8
            // (acentos como "é" aparecían como "Ã©"). Si el payload es UTF-8
            // válido, usarlo; si no, caer a Latin-1 como declara el tag.
            value = String(data: text, encoding: .utf8) ?? String(data: text, encoding: .isoLatin1)
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
        // Mismo parser tolerante que AVFoundation (metadataDateAsync): si
        // aquí se devolviera nil por un formato poco común ("© 2023",
        // "17.05.2023"), la canción caería al creationDate del archivo.
        return Self.parseReleaseDate(value)
    }

    private func saveFolders() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func saveFiles() {
        guard let data = try? JSONEncoder().encode(files) else { return }
        UserDefaults.standard.set(data, forKey: filesDefaultsKey)
    }

    // MARK: - Playlist Management
    private func loadPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: playlistsDefaultsKey),
              let savedPlaylists = try? JSONDecoder().decode([Playlist].self, from: data) else {
            return
        }
        playlists = savedPlaylists
    }

    private func savePlaylists() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        UserDefaults.standard.set(data, forKey: playlistsDefaultsKey)
    }

    func createPlaylist(name: String, description: String = "") -> Playlist {
        let playlist = Playlist(name: name, description: description)
        playlists.append(playlist)
        savePlaylists()
        AppLog.info(.library, "Playlist creada: \(name)")
        return playlist
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        savePlaylists()
        AppLog.info(.library, "Playlist eliminada: \(playlist.name)")
    }

    func addSongToPlaylist(_ song: Song, playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        if !playlists[index].songIDs.contains(song.id) {
            playlists[index].songIDs.append(song.id)
            playlists[index].modifiedAt = Date()
            savePlaylists()
            AppLog.info(.library, "Canción añadida a playlist: \(playlist.name)")
        }
    }

    func removeSongFromPlaylist(_ song: Song, playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].songIDs.removeAll { $0 == song.id }
        playlists[index].modifiedAt = Date()
        savePlaylists()
        AppLog.info(.library, "Canción eliminada de playlist: \(playlist.name)")
    }

    func updatePlaylist(_ playlist: Playlist, name: String? = nil, description: String? = nil) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        if let name = name { playlists[index].name = name }
        if let description = description { playlists[index].description = description }
        playlists[index].modifiedAt = Date()
        savePlaylists()
    }

    func songsInPlaylist(_ playlist: Playlist) -> [Song] {
        // Diccionario para búsqueda O(1) en lugar de O(n) por canción
        let songsByID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        return playlist.songIDs.compactMap { songsByID[$0] }
    }
    
    // MARK: - Liked Songs (Me Gusta)
    
    /// Returns the "Me Gusta" playlist, creating it if it doesn't exist
    var likedPlaylist: Playlist? {
        playlists.first(where: { $0.name == likedPlaylistName })
    }
    
    /// Ensures the "Me Gusta" playlist exists (called on app start)
    func ensureLikedPlaylistExists() {
        if likedPlaylist == nil {
            let playlist = Playlist(name: likedPlaylistName, description: "Canciones que te gustan")
            playlists.insert(playlist, at: 0)
            savePlaylists()
            AppLog.info(.library, "Playlist 'Me Gusta' creada automáticamente")
        }
    }
    
    /// Check if a song is liked (usa cache O(1) en vez de O(n))
    func isLiked(_ song: Song) -> Bool {
        // ✅ Usar cache si es válido, si no calcular y cachear
        if LikedSongsCache.shared.isLiked(song.id) {
            return true
        }
        // Fallback: calcular y actualizar cache
        guard let liked = likedPlaylist else {
            LikedSongsCache.shared.update(likedIDs: [])
            return false
        }
        let likedSet = Set(liked.songIDs)
        LikedSongsCache.shared.update(likedIDs: likedSet)
        return likedSet.contains(song.id)
    }

    /// Toggle like status for a song
    func toggleLike(_ song: Song) {
        ensureLikedPlaylistExists()
        guard let index = playlists.firstIndex(where: { $0.name == likedPlaylistName }) else { return }

        if playlists[index].songIDs.contains(song.id) {
            playlists[index].songIDs.removeAll { $0 == song.id }
        } else {
            playlists[index].songIDs.append(song.id)
        }
        playlists[index].modifiedAt = Date()
        savePlaylists()
        // ✅ Invalidar cache para que se recalcule en el próximo acceso
        LikedSongsCache.shared.invalidate()
    }
    
    /// Get all liked songs
    var likedSongs: [Song] {
        guard let liked = likedPlaylist else { return [] }
        return songsInPlaylist(liked)
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
            let start = Date()
            let rawData = try? Data(contentsOf: url)
            let cachedSongs = rawData.flatMap { try? JSONDecoder().decode([Song].self, from: $0) } ?? []
            let elapsed = Date().timeIntervalSince(start)
            let sizeKB = (rawData?.count ?? 0) / 1024
            DispatchQueue.main.async {
                AppLog.info(.cache, "Caché de biblioteca cargado: \(cachedSongs.count) canciones, \(sizeKB) KB, \(String(format: "%.2f", elapsed))s")
                self?.finishInitialLibraryLoad(with: cachedSongs)
            }
        }
    }

    private func finishInitialLibraryLoad(with cachedSongs: [Song]) {
        // ✅ FIX conteo de álbumes/artistas (13 vs 9): versiones anteriores
        // podían dejar DUPLICADOS en el caché (misma URL dos veces). Cada
        // duplicado inflaba album.songs.count, pero el ForEach de detalle
        // (id: \.element.id) colapsaba las filas → "dice 13 y son 9".
        // Se deduplica AL CARGAR el caché y el rescan posterior ya no las
        // re-agrega (indexedSongKeys se construye desde la lista limpia).
        let uniqueCached = dedupeSongsByUrl(cachedSongs)
        songs = uniqueCached
        isInitialLibraryLoaded = true
        hasEverLoadedSongs = true
        indexedSongKeys = Set(uniqueCached.map { Self.libraryKey(for: $0.url) })
        if uniqueCached.isEmpty && (!folders.isEmpty || !files.isEmpty) {
            rescanAllFolders()
        } else {
            restoreSecurityScopedAccess()
            // Verificar accesibilidad en un hilo de fondo: con 1000+ canciones,
            // hacer fileExists en el hilo principal congela la app al iniciar.
            let urls = uniqueCached.map(\.url)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let inaccessibleCount = urls.filter { !FileManager.default.fileExists(atPath: $0.path) }.count
                DispatchQueue.main.async {
                    guard inaccessibleCount > 0 else { return }
                    AppLog.warning(.library, "\(inaccessibleCount) canciones inaccesibles, re-escaneando")
                    self?.rescanAllFolders()
                }
            }
        }
        if !cachedSongs.isEmpty {
            AppLog.info(.library, "Biblioteca recuperada de caché: \(cachedSongs.count) canciones")
        }
    }

    private func scheduleCacheSave() {
        cacheSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.saveCachedSongs() }
        cacheSaveWorkItem = workItem
        // ✅ ANTI-CRASH: delay 5s (antes 1s). Con bibliotecas grandes el JSON
        // pesa ~200-300MB (portadas incluidas); serializarlo tras cada lote del
        // escaneo multiplicaba los picos de memoria → jetsam kill ~900 canciones.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func saveCachedSongs() {
        guard let url = libraryCacheURL else { return }
        // ✅ ANTI-CRASH: encode en background. JSONEncoder().encode() sobre
        // 900+ canciones con artworkData construía el Data completo (y una copia
        // para escribir .atomic) en el MAIN THREAD → freeze + pico de memoria
        // doble + crash. La instantánea de `songs` se captura aquí (main) y el
        // encode/escritura corren fuera.
        let snapshot = songs
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                AppLog.info(.cache, "Caché de biblioteca guardado: \(snapshot.count) canciones, \(data.count / 1024) KB")
            } catch {
                AppLog.error(.library, "No se pudo guardar caché: \(error.localizedDescription)")
            }
        }
    }

    private func removeCachedSongs() {
        cacheSaveWorkItem?.cancel()
        guard let url = libraryCacheURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Albums y Artists (cacheados: se recalculan solo cuando cambia `songs`)

    var albums: [Album] {
        if needsRebuild { rebuildDerivedCollections() }
        return cachedAlbums
    }
    var artists: [Artist] {
        if needsRebuild { rebuildDerivedCollections() }
        return cachedArtists
    }

    /// ✅ Deduplicación por URL (mantiene la primera aparición). Usada al
    /// cargar caché, al fusionar lotes del escaneo y al agrupar álbumes/artistas.
    private func dedupeSongsByUrl(_ input: [Song]) -> [Song] {
        var seen = Set<URL>()
        seen.reserveCapacity(input.count)
        return input.filter { seen.insert($0.url).inserted }
    }

    private func rebuildDerivedCollections() {
        // ✅ FIX conteo (13 vs 9): deduplicar por URL antes de agrupar. Un
        // duplicado inflaba album.songs.count y artist.songs.count mientras el
        // ForEach del detalle ocultaba la fila repetida.
        let allSongs = dedupeSongsByUrl(songs)
        // ✅ FIX multi-disco: agrupar por (artista, álbum) NORMALIZADOS. Los discos
        // del mismo álbum suelen traer nombres distintos por disco
        // ("X (Disc 1)" / "X (Disc 2)") o capitalización distinta; antes cada
        // variante creaba un álbum separado → no se reproducían de corrido y
        // repeat-all no volvía a empezar por el disco 1.
        let groupedAlbums = Dictionary(grouping: allSongs) { song -> String in
            let albumName = song.album.isEmpty ? "Álbum desconocido" : song.album
            let artistName = song.albumArtist.isEmpty ? (song.artist.isEmpty ? "Artista desconocido" : song.artist) : song.albumArtist
            return Song.albumGroupKey(album: albumName, artist: artistName)
        }

        cachedAlbums = groupedAlbums.map { (key, albumSongs) in
            // Nombre visible: si el grupo unió varios nombres originales (discos),
            // mostrar la versión normalizada; si solo hay uno, respetar el original.
            let originalAlbums = albumSongs.map { $0.album.isEmpty ? "Álbum desconocido" : $0.album }
            let name = originalAlbums.count > 1
                ? Song.normalizedAlbumName(originalAlbums.first ?? "")
                : (originalAlbums.first ?? key)
            // Artista visible: el más frecuente entre las canciones del grupo
            // (respeta la capitalización original de los metadatos).
            let artistCounts = Dictionary(grouping: albumSongs) { song in
                song.albumArtist.isEmpty ? (song.artist.isEmpty ? "Artista desconocido" : song.artist) : song.albumArtist
            }
            let artist = artistCounts.max { $0.value.count < $1.value.count }?.key ?? key
            return Album(
                name: name,
                artist: artist,
                songs: albumSongs.sorted(by: Song.discAwareOrder)
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // ✅ FIX artista partido (álbum 13, artista 9): agrupar por la clave
        // NORMALIZADA (misma normalización que albumGroupKey). Variantes de
        // escritura del mismo artista ("X" vs "x") ya NO crean buckets
        // separados. El nombre visible es la variante más frecuente.
        let groupedArtists = Dictionary(grouping: allSongs) { song -> String in
            let effective = song.albumArtist.isEmpty ? (song.artist.isEmpty ? "Artista desconocido" : song.artist) : song.albumArtist
            return Song.artistGroupKey(effective)
        }

        cachedArtists = groupedArtists.map { (artistKey, artistSongs) in
            let nameCounts = Dictionary(grouping: artistSongs) { song -> String in
                song.albumArtist.isEmpty ? (song.artist.isEmpty ? "Artista desconocido" : song.artist) : song.albumArtist
            }
            let displayName = nameCounts.max { $0.value.count < $1.value.count }?.key ?? artistKey
            return Artist(
                name: displayName,
                songs: artistSongs
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        needsRebuild = false // ✅ Marcar como actualizado
    }

    deinit {
        saveCachedSongs()
        for (_, url) in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
        for (_, url) in activeFileURLs { url.stopAccessingSecurityScopedResource() }
    }
}