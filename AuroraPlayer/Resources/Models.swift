import Foundation
import UIKit

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

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
    case off, all, one
}

enum EQPreset: String, CaseIterable, Codable {
    case flat, bass, treble, vocal, classical, electronic, pop, rock, jazz, concert

    var displayName: String {
        switch self {
        case .flat: return Localization.localized("eq.flat")
        case .bass: return Localization.localized("eq.bass")
        case .treble: return Localization.localized("eq.treble")
        case .vocal: return Localization.localized("eq.vocal")
        case .classical: return Localization.localized("eq.classical")
        case .electronic: return Localization.localized("eq.electronic")
        case .pop: return Localization.localized("eq.pop")
        case .rock: return Localization.localized("eq.rock")
        case .jazz: return Localization.localized("eq.jazz")
        case .concert: return Localization.localized("eq.concert")
        }
    }

    var gains: [Float] {
        switch self {
        case .flat: return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bass: return [8, 7, 5, 3, 0, 0, 0, 0, 0, 0]
        case .treble: return [0, 0, 0, 0, 0, 0, 3, 5, 7, 8]
        case .vocal: return [2, 4, 5, 4, 2, 0, 0, 0, 0, 0]
        case .classical: return [5, 4, 3, 2, 0, 0, 2, 3, 4, 5]
        case .electronic: return [6, 5, 3, 0, -2, -2, 0, 3, 5, 6]
        case .pop: return [3, 4, 3, 1, 0, 0, 1, 3, 4, 3]
        case .rock: return [6, 5, 4, 2, 0, 0, 2, 4, 5, 6]
        case .jazz: return [4, 3, 2, 2, 0, 0, 2, 3, 4, 4]
        // ✅ CONCIERTO: realce de presencia (2-4 kHz) y aire (8-16 kHz) con un
        // leve cuerpo bajo (100-125 Hz) que simula la reverb de una sala grande.
        // Universal: la misma curva aplica a cualquier canción y género.
        case .concert: return [2.5, 3.0, 3.5, 2.0, 1.0, 0.5, 1.5, 3.0, 2.0, 1.5]
        }
    }
}

/// ✅ CÓDEC REAL del stream de audio (FourCC), con su nombre comercial y si el
/// motor propio puede decodificarlo.
///
/// Motivo: iOS envuelve Dolby Digital Plus (E-AC-3) en un contenedor MP4, así
/// que un archivo ".m4a"/".mp4" puede ser Dolby y no AAC. La extensión no dice
/// nada del codec: hay que leer el ASBD del track de audio
/// (`CMFormatDescriptionGetMediaSubType`) y guardar el FourCC real.
/// AVAudioEngine/AVAudioFile NO decodifican E-AC-3 ni AC-3 (iOS no expone
/// decodificador Dolby a apps de terceros), pero AVPlayer sí de forma nativa.
enum AudioCodec {
    /// ✅ ¿Es un codec Dolby (E-AC-3/AC-3) que el motor propio no decodifica?
    static func isDolby(_ fourCC: String?) -> Bool {
        let code = normalized(fourCC)
        return code == "ec-3" || code == "ec3" || code == "ac-3" || code == "ac3"
    }

    /// ✅ FourCC → nombre comercial legible. Devuelve nil sin datos y el propio
    /// FourCC (en mayúsculas) para codecs sin nombre conocido.
    static func displayName(for fourCC: String?) -> String? {
        guard let raw = fourCC?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        switch normalized(raw) {
        case "ec-3", "ec3", "eac3", "ddp": return "Dolby Digital Plus (E-AC-3)"
        case "ac-3", "ac3": return "Dolby Digital (AC-3)"
        case "mp4a": return "AAC"
        case "alac": return "ALAC"
        case "flac": return "FLAC"
        case "lpcm", "sowt", "twos": return "PCM"
        default: return raw.uppercased()
        }
    }

    /// ✅ Normaliza el FourCC para comparar: minúsculas y sin espacios (los
    /// FourCC de 3 letras llegan con relleno, p. ej. "mp3 " → "mp3").
    private static func normalized(_ fourCC: String?) -> String {
        (fourCC ?? "").lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// ✅ Contenedores cuyo nombre de formato (y su codec) NO se puede deducir de
    /// la extensión: dentro de un .mp4/.m4a puede haber AAC, ALAC o Dolby.
    static let containerExtensions: Set<String> = ["mp4", "m4a", "m4v", "mov", "m4b"]
}

struct Song: Identifiable, Equatable, Codable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String
    let albumArtist: String
    let album: String
    let artworkData: Data?

    /// ✅ PERF (v16): SHA256 de la portada. El JSON de caché ya NO lleva los
    /// bytes de la imagen (249 MB con 1147 canciones que se cargaban enteros en
    /// RAM al arrancar): viven como JPEG en
    /// Application Support/artwork-cache/<sha256>.jpg y aquí queda solo la
    /// referencia. Optional para que el caché viejo (sin este campo) siga
    /// decodificando bien: Codable lo trata como ausente → nil.
    let artworkHash: String?
    let duration: TimeInterval
    let lyrics: String
    let formatDescription: String
    let discNumber: Int?
    let trackNumber: Int
    let releaseDate: Date?
    let sampleRate: Double
    let bitDepth: Int
    let channelCount: Int
    let bitrate: Int?  // ✅ Bitrate para formatos con pérdida (MP3/AAC)
    // ✅ FIX metadata editada que no se refleja: fecha de modificación del
    // ARCHIVO en disco al momento de leer sus metadatos. FileAccessService
    // la compara contra la fecha actual del archivo en cada escaneo — si
    // difieren, el archivo se re-lee aunque su ruta ya estuviera indexada
    // (antes el escaneo diferencial solo miraba si la RUTA era conocida,
    // nunca si el CONTENIDO había cambiado, así que una edición de tags
    // externa nunca se detectaba). Optional para que el caché viejo (sin
    // este campo) siga decodificando bien: Codable lo trata como ausente → nil.
    let fileModificationDate: Date?

    /// ✅ CÓDEC REAL del stream de audio (FourCC leído del ASBD del asset:
    /// "ec-3", "ac-3", "mp4a", "alac", "lpcm"…). La extensión NO basta: iOS
    /// envuelve Dolby Digital Plus (E-AC-3) en un contenedor MP4/M4A, así que
    /// un ".m4a"/".mp4" puede ser Dolby aunque se anunciara como AAC.
    /// Optional para que el caché viejo (sin este campo) siga decodificando
    /// bien: Codable lo trata como ausente → nil.
    let codecName: String?

    init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        artist: String = "",
        albumArtist: String = "",
        album: String = "",
        artworkData: Data? = nil,
        artworkHash: String? = nil,
        duration: TimeInterval = 0,
        lyrics: String = "",
        formatDescription: String = "",
        discNumber: Int? = nil,
        trackNumber: Int = 0,
        releaseDate: Date? = nil,
        sampleRate: Double = 0,
        bitDepth: Int = 0,
        channelCount: Int = 0,
        bitrate: Int? = nil,
        fileModificationDate: Date? = nil,
        codecName: String? = nil
    ) {
        self.id = id
        self.url = url
        self.title = (title?.isEmpty == false) ? title! : url.deletingPathExtension().lastPathComponent
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.artworkData = artworkData
        self.artworkHash = artworkHash
        self.duration = duration
        self.lyrics = lyrics
        self.formatDescription = formatDescription
        self.discNumber = discNumber.flatMap { $0 > 0 ? $0 : nil }
        self.trackNumber = max(0, trackNumber)
        self.releaseDate = releaseDate
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
        self.bitrate = bitrate
        self.fileModificationDate = fileModificationDate
        self.codecName = codecName
    }

    /// ✅ ¿Hay que reproducir este archivo con AVPlayer? El motor propio
    /// (AVAudioEngine/AVAudioFile) NO decodifica Dolby: iOS no expone
    /// decodificador E-AC-3/AC-3 a apps de terceros. AVPlayer sí lo hace de
    /// forma nativa (desde iOS 9.3), así que estas pistas van directas a esa
    /// ruta — es un modo INTENCIONAL, no un fallo del motor.
    var requiresAVPlayerPlayback: Bool {
        if AudioCodec.isDolby(codecName) { return true }
        // ✅ Caché viejo (indexado antes de la detección por FourCC): sin
        // `codecName` se cae a la extensión, que ya delataba los .ac3/.ec3/.ddp.
        // Un .m4a/.mp4 Dolby necesita re-indexarse para entrar por aquí.
        guard codecName == nil else { return false }
        return ["ac3", "ec3", "eac3", "ddp"].contains(url.pathExtension.lowercased())
    }

    /// ✅ Nombre legible del códec detectado (nil si el archivo no se ha
    /// re-indexado todavía con la detección por FourCC).
    var codecDisplayName: String? {
        AudioCodec.displayName(for: codecName)
    }

    /// ✅ ¿Hay que re-leer la metadata para conocer el codec? Solo para
    /// contenedores (.mp4/.m4a/.m4v/.mov), donde la extensión no dice nada: el
    /// caché se escribió antes de que la app leyera el FourCC del track y sin él
    /// no se puede saber si hay que reproducir con AVPlayer (Dolby) o con el
    /// motor propio (AAC/ALAC). Se re-lee UNA vez; después `codecName` ya está.
    var needsCodecDetection: Bool {
        codecName == nil && AudioCodec.containerExtensions.contains(url.pathExtension.lowercased())
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id
    }

    /// ✅ FIX metadata editada: copia con el MISMO contenido pero conservando la
    /// identidad (`id`) ya indexada. Obligatorio al re-leer la metadata de un
    /// archivo conocido: "Me Gusta" y las playlists guardan `songIDs` (UUID),
    /// `isLiked` compara por `id`, y el resaltado de "sonando ahora" + el
    /// restaurado de reproducción buscan por `id`. Si la re-lectura generara un
    /// UUID nuevo, la canción desaparecería de las playlists y el estado
    /// guardado quedaría apuntando a un id huérfano para siempre.
    func preservingID(_ id: UUID) -> Song {
        Song(
            id: id,
            url: url,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            artworkData: artworkData,
            artworkHash: artworkHash,
            duration: duration,
            lyrics: lyrics,
            formatDescription: formatDescription,
            discNumber: discNumber,
            trackNumber: trackNumber,
            releaseDate: releaseDate,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channelCount: channelCount,
            bitrate: bitrate,
            fileModificationDate: fileModificationDate,
            codecName: codecName
        )
    }

    /// ✅ FIX multi-disco: orden canónico (disco 1 antes que disco 2, luego pista).
    /// Antes solo se ordenaba por trackNumber → en álbumes con Disc 1 y Disc 2
    /// (ambos arrancan en pista 1) el sort inestable podía poner primero el Disc 2.
    static func discAwareOrder(_ lhs: Song, _ rhs: Song) -> Bool {
        let ld = lhs.discNumber ?? 1
        let rd = rhs.discNumber ?? 1
        if ld != rd { return ld < rd }
        if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
        // ✅ localizedStandardCompare: orden natural ("Track 2" < "Track 10").
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    /// ✅ FIX multi-disco: normaliza el nombre de álbum para AGRUPAR los discos
    /// del mismo álbum que llegan con nombres distintos en los metadatos
    /// ("Álbum (Disc 1)" / "Álbum (Disc 2)", "Álbum - CD1", "Álbum [Disc 1 of 2]"...).
    /// Quita el sufijo de disco al final del nombre y colapsa espacios. La
    /// comparación de agrupación es además insensible a mayúsculas/minúsculas.
    /// Si al quitar el sufijo queda vacío (p.ej. un álbum que se llama solo
    /// "Disc 1"), devuelve el nombre original sin partirlo.
    static func normalizedAlbumName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty, let regex = try? NSRegularExpression(
            pattern: "[\\s\\-–—_:·]*[\\(\\[\\{]?\\s*(?:disc|disco|cd)\\s*[0-9]+(?:\\s*(?:of|de|/)\\s*[0-9]+)?\\s*[\\)\\]\\}]?\\s*$",
            options: [.caseInsensitive]
        ) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : s
    }

    /// Clave de agrupación de álbumes: artista + álbum normalizados (une los
    /// discos del mismo álbum y evita duplicados por capitalización distinta).
    static func albumGroupKey(album rawAlbum: String, artist rawArtist: String) -> String {
        let album = normalizedAlbumName(rawAlbum).lowercased()
        let artist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return artist + "|" + album
    }

    /// Clave de agrupación de ARTISTAS: la MISMA normalización del artista que
    /// usa albumGroupKey (trim + minúsculas). ✅ FIX: antes los buckets de
    /// artista se creaban con el string crudo de albumArtist, así que
    /// variantes de escritura ("X" vs "x", espacios extra) partían las
    /// canciones en dos artistas distintos: el álbum mostraba todas sus
    /// canciones (p. ej. 13) pero la página del artista solo una parte (9).
    static func artistGroupKey(_ rawArtist: String) -> String {
        rawArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension Song {
    private static let artworkCache: NSCache<NSUUID, UIImage> = {
        let cache = NSCache<NSUUID, UIImage>()
        // ✅ ANTI-CRASH: límite por MEMORIA (costo), no solo por conteo.
        // Cada UIImage decodificada ocupa ancho×alto×4 bytes en RAM (768²×4 =
        // 2.4MB a la resolución actual). countLimit 500 sin costLimit permitía
        // >1GB de bitmaps → jetsam kill al scrollear listas grandes.
        cache.countLimit = 120
        cache.totalCostLimit = 200 * 1024 * 1024 // 200MB de bitmaps decodificados
        return cache
    }()

    /// ✅ PERF (v16): la portada ya no viaja dentro del JSON de la biblioteca.
    /// Si el Song viene del caché trae solo `artworkHash` y los bytes se leen
    /// del JPEG en disco; el resto del camino (decodificar + NSCache por
    /// canción) es idéntico, así que sigue habiendo UNA decodificación por
    /// canción por más veces que se lea.
    var artwork: UIImage? {
        guard let data = artworkData ?? Song.artworkDataFromDisk(for: artworkHash) else { return nil }
        if let cached = Song.artworkCache.object(forKey: id as NSUUID) {
            return cached
        }
        guard let image = UIImage(data: data) else { return nil }
        // Costo = bytes del bitmap decodificado (RGBA), para que totalCostLimit
        // refleje la RAM real consumida y NSCache expulse bajo presión.
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        Song.artworkCache.setObject(image, forKey: id as NSUUID, cost: cost)
        return image
    }

    /// ✅ PERF (v16): ruta del JPEG de una portada, una por hash de CONTENIDO
    /// (mil canciones del mismo álbum comparten un único archivo). Vive en
    /// Application Support y no en Caches: el sistema no purga esa carpeta, y
    /// una portada purgada por iOS dejaría la carátula en blanco hasta el
    /// siguiente re-indexado.
    static func artworkFileURL(for hash: String) -> URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        // Dos llamadas a propósito: un solo componente con "artwork-cache/…"
        // se percent-encodea (%2F) en la implementación nueva de URL.
        return directory.appendingPathComponent("artwork-cache").appendingPathComponent("\(hash).jpg")
    }

    /// ✅ PERF (v16): bytes de la portada que el JSON ya no guarda.
    private static func artworkDataFromDisk(for hash: String?) -> Data? {
        guard let hash, let url = artworkFileURL(for: hash) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// ✅ PERF (v16): copia del Song con la portada FUERA del JSON — `artworkData`
    /// vaciado y su contenido referenciado por hash. Solo para guardar el
    /// caché: en memoria la app sigue usando el Song completo.
    func referencingArtworkFile(hash: String) -> Song {
        Song(
            id: id,
            url: url,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            artworkData: nil,
            artworkHash: hash,
            duration: duration,
            lyrics: lyrics,
            formatDescription: formatDescription,
            discNumber: discNumber,
            trackNumber: trackNumber,
            releaseDate: releaseDate,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channelCount: channelCount,
            bitrate: bitrate,
            fileModificationDate: fileModificationDate,
            codecName: codecName
        )
    }

    var displayName: String {
        if album.isEmpty && !artist.isEmpty {
            return "\(title) • \(artist)"
        }
        return title
    }

    var displaySubtitle: String {
        var components: [String] = []
        if !artist.isEmpty { components.append(artist) }
        if !album.isEmpty { components.append(album) }
        return components.joined(separator: " • ")
    }

    /// ¿Es Hi-Res? (sampleRate estrictamente mayor a 48 kHz).
    /// CD Quality (44.1 kHz) y 48 kHz NO son Hi-Res.
    var isHiRes: Bool {
        sampleRate > 48000
    }

    /// ¿Es lossless? Centraliza la heurística (formatos sin pérdida +
    /// caso M4A que puede ser AAC con pérdida o ALAC sin pérdida).
    /// Nota: FileAccessService guarda formatDescription SOLO como extensión
    /// (ej. "FLAC", "M4A", "MP3") — no contiene "ALAC" — así que la rama
    /// principal es la extensión del archivo.
    var isLossless: Bool {
        let ext = url.pathExtension.uppercased()
        let losslessFormats: Set<String> = ["FLAC", "WAV", "WAVE", "AIFF", "AIF", "ALAC"]
        if losslessFormats.contains(ext) {
            return true
        }
        // M4A puede ser AAC (comprimido, bitDepth suele ser 0) o ALAC
        // (lossless, normalmente 16/24-bit). 48 kHz por sí solo NO basta.
        if ext == "M4A" {
            return bitDepth >= 16 || sampleRate > 48000
        }
        return false
    }

    /// Nombre PURO del formato: primera parte de `formatDescription` (que
    /// FileAccessService guarda COMPUESTA, p.ej. "FLAC · 24 bits · 44 kHz").
    /// ✅ FIX kHz duplicado en la cápsula de NowPlaying: antes `audioQualityDescription`
    /// trataba la cadena compuesta como si fuera solo el nombre ("FLAC") y volvía
    /// a añadir el sample rate → "FLAC · 24 bits · 44 kHz · 44.1kHz". Con este
    /// helper el formato es siempre un solo nombre ("FLAC", "WAV", "Dolby Digital Plus"…).
    var formatName: String {
        let raw = formatDescription.isEmpty ? url.pathExtension.uppercased() : formatDescription
        let first = raw.split(separator: "·").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = first, !first.isEmpty { return first }
        return url.pathExtension.uppercased()
    }

    /// Descripción detallada del formato de audio basada en metadatos reales del archivo
    var audioQualityDescription: String {
        var parts: [String] = []
        let format = formatName
        parts.append(format)

        // ✅ Reordenar: bits ANTES de kHz
        if bitDepth > 0 && (format == "FLAC" || format == "ALAC" || format == "WAV" || format == "AIFF") {
            parts.append("\(bitDepth)-bit")
        }

        if sampleRate > 0 {
            // ✅ Formato consistente en kHz: 44100 → "44.1kHz" (antes "44100Hz"
            // mientras 48000 mostraba "48kHz"). String(format:) no usa el locale,
            // así que el punto decimal es estable en todos los idiomas.
            let kHz = sampleRate / 1000.0
            let formatted = kHz.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(kHz))kHz"
                : String(format: "%.1f", kHz) + "kHz"
            parts.append(formatted)
        }

        if channelCount == 2 {
            parts.append(Localization.localized("audio.quality.stereo"))
        } else if channelCount == 1 {
            parts.append(Localization.localized("audio.quality.mono"))
        } else if channelCount > 2 {
            parts.append("\(channelCount).1")
        }

        if sampleRate > 48000 {
            parts.append(Localization.localized("audio.quality.hiRes"))
        }

        return parts.joined(separator: " · ")
    }
}

struct Album: Identifiable, Equatable {
    var id: String { "\(artist)|\(name)" }
    let name: String
    let artist: String
    let songs: [Song]

    var artwork: UIImage? {
        songs.first(where: { $0.artworkData != nil || $0.artworkHash != nil })?.artwork
    }

    // ✅ Año del álbum DETERMINISTA: el año con más canciones; en empate,
    // gana el año MÁS ANTIGUO (lanzamiento original, no la reedición).
    // `Dictionary.max` con solo conteo era no-determinista en empates y un
    // solo tag erróneo movía todo el álbum (antes se usaba `.min()` global).
    // Si ninguna canción tiene fecha, retornar nil (álbum sin año).
    var releaseDate: Date? {
        let dates = songs.compactMap { $0.releaseDate }
        guard !dates.isEmpty else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let byYear = Dictionary(grouping: dates) { calendar.component(.year, from: $0) }
        let best = byYear.sorted {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            return $0.key < $1.key
        }.first
        return best?.value.min()
    }

    // ✅ UNIFICADO: delega en la caché/algorithm compartidos de AppTheme —
    // NowPlaying, AlbumDetail y ArtistDetail ahora obtienen el MISMO color
    // para la misma carátula (una sola extracción por arte).
    var dominantColor: UIColor? {
        guard let artwork = artwork else { return nil }
        return AppTheme.cachedDominantColor(from: artwork, key: id)
    }
}

struct Artist: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let songs: [Song]

    var albums: [Album] {
        // ✅ FIX multi-disco: misma normalización que la biblioteca — los discos
        // del mismo álbum con nombres distintos en los metadatos se unen en uno.
        let grouped = Dictionary(grouping: songs) { song -> String in
            Song.albumGroupKey(album: song.album, artist: name)
        }
        return grouped.map { (key, albumSongs) in
            let originalAlbums = albumSongs.map { $0.album.isEmpty ? "Álbum desconocido" : $0.album }
            let albumName = originalAlbums.count > 1
                ? Song.normalizedAlbumName(originalAlbums.first ?? "")
                : (originalAlbums.first ?? "Álbum desconocido")
            return Album(
                name: albumName,
                artist: name,
                songs: albumSongs.sorted(by: Song.discAwareOrder)
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var artwork: UIImage? {
        songs.first(where: { $0.artworkData != nil || $0.artworkHash != nil })?.artwork
    }
}


struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var songIDs: [UUID]
    var createdAt: Date
    var modifiedAt: Date
    var coverArtworkData: Data?

    init(id: UUID = UUID(), name: String, description: String = "", songIDs: [UUID] = [], createdAt: Date = Date(), modifiedAt: Date = Date(), coverArtworkData: Data? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.songIDs = songIDs
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.coverArtworkData = coverArtworkData
    }

    var artwork: UIImage? {
        guard let data = coverArtworkData else { return nil }
        return UIImage(data: data)
    }
}