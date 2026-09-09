import Foundation

// MARK: - Índice de búsqueda de la biblioteca
// ✅ RENDIMIENTO: antes la búsqueda filtraba + re-ordenaba TODA la librería
// en cada tecla (lowercased() por ítem, contains y localizedStandardCompare).
// Con librerías grandes eso bloqueaba el main thread y hacía imposible
// escribir en el buscador. Ahora:
//   1. Las cadenas se normalizan UNA vez por ítem (insensible a mayúsculas,
//      acentos y anchura — "canción" encuentra "cancion") y se cachean aquí.
//   2. El matching es por PALABRAS: todas las palabras de la consulta deben
//      coincidir en título, artista o álbum (subcadena o prefijo de palabra).
//   3. Los resultados se ordenan por RELEVANCIA: coincidencia exacta >
//      empieza con > contiene; el título pondera más que artista/álbum.
//   4. El índice solo se reconstruye cuando cambia la librería, no por tecla.
final class LibrarySearchIndex {

    static let shared = LibrarySearchIndex()

    struct SongEntry {
        let title: String
        let artist: String
        let albumArtist: String
        let album: String
    }

    struct AlbumEntry {
        let name: String
        let artist: String
        // ✅ Títulos de las canciones del álbum: buscar por el nombre de una
        // canción ahora TAMBIÉN encuentra su álbum (antes solo se buscaba en
        // nombre+artista y muchos álbumes "no se detectaban").
        let songTitles: [String]
    }

    struct ArtistEntry {
        // ✅ Búsqueda de artistas SOLO por nombre: antes también se buscaba en
        // los títulos de canciones y álbumes del artista, lo que devolvía
        // artistas que no tenían nada que ver con lo buscado (falsos positivos)
        // y hacía fallar el AND de todas las palabras cuando una palabra solo
        // existía en una canción.
        let name: String
    }

    private(set) var songEntries: [UUID: SongEntry] = [:]
    private(set) var albumEntries: [String: AlbumEntry] = [:]
    private(set) var artistEntries: [String: ArtistEntry] = [:]

    private var songSignature: [UUID] = []
    private var albumSignature: [String] = []
    private var artistSignature: [String] = []

    /// Normalización compartida: minúsculas, sin diacríticos ni diferencias
    /// de anchura (CJK/fullwidth). Una sola llamada por campo, cacheada.
    static func fold(_ string: String) -> String {
        guard !string.isEmpty else { return "" }
        return string.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
    }

    /// Reconstruye el índice solo si las colecciones realmente cambiaron
    /// (comparación por ids — O(n) barata, sin tocar strings).
    func update(songs: [Song], albums: [Album], artists: [Artist]) {
        let sSig = songs.map(\.id)
        let aSig = albums.map(\.id)
        let arSig = artists.map(\.id)
        guard sSig != songSignature || aSig != albumSignature || arSig != artistSignature else { return }
        songSignature = sSig
        albumSignature = aSig
        artistSignature = arSig

        var newSongs: [UUID: SongEntry] = [:]
        newSongs.reserveCapacity(songs.count)
        for song in songs {
            newSongs[song.id] = SongEntry(
                title: Self.fold(song.title),
                artist: Self.fold(song.artist),
                albumArtist: Self.fold(song.albumArtist),
                album: Self.fold(song.album)
            )
        }
        songEntries = newSongs

        var newAlbums: [String: AlbumEntry] = [:]
        newAlbums.reserveCapacity(albums.count)
        for album in albums {
            newAlbums[album.id] = AlbumEntry(
                name: Self.fold(album.name),
                artist: Self.fold(album.artist),
                songTitles: album.songs.map { Self.fold($0.title) }
            )
        }
        albumEntries = newAlbums

        var newArtists: [String: ArtistEntry] = [:]
        newArtists.reserveCapacity(artists.count)
        for artist in artists {
            newArtists[artist.id] = ArtistEntry(
                name: Self.fold(artist.name)
            )
        }
        artistEntries = newArtists
    }

    // MARK: - Matching por palabras

    /// Palabras normalizadas de la consulta (ignora vacías).
    static func queryWords(_ query: String) -> [String] {
        fold(query)
            .split { $0.isWhitespace }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Puntaje de UNA palabra contra los campos (en orden de prioridad:
    /// el índice 0 es el campo principal, p. ej. el título).
    /// `compactFields` son los mismos campos sin espacios: permiten encontrar
    /// "Daft Punk" escribiendo "daftpunk" (coincidencia más débil).
    /// Retorna nil si la palabra no coincide.
    private static func wordScore(_ word: String, fields: [String], compactFields: [String]) -> Int? {
        var best: Int?
        for (idx, field) in fields.enumerated() where !field.isEmpty {
            // Peso base por campo: el campo principal (título) pondera más.
            let fieldWeight = 10 - min(idx, 4)
            var score: Int
            if field == word {
                score = 100
            } else if field.hasPrefix(word) {
                score = 60
            } else {
                guard let range = field.range(of: word) else { continue }
                // Prefijo de palabra dentro del campo ("imagine" encuentra
                // "Imagine Dragons") vale más que coincidencia en medio.
                let prevIsLetter = range.lowerBound > field.startIndex
                    && field[field.index(before: range.lowerBound)].isLetter
                score = prevIsLetter ? 20 : 35
            }
            score += fieldWeight
            if best == nil || score > best! { best = score }
        }
        // ✅ Coincidencia compacta: la consulta sin espacios contra campos sin
        // espacios. Puntaje bajo: es una coincidencia más débil.
        if best == nil, word.count >= 3 {
            for (idx, compact) in compactFields.enumerated() {
                if compact.contains(word) {
                    let s = 12 + (10 - min(idx, 4))
                    if best == nil || s > best! { best = s }
                }
            }
        }
        return best
    }

    private static func compactFields(_ fields: [String]) -> [String] {
        fields.map { $0.replacingOccurrences(of: " ", with: "") }
    }

    /// Coincidencia estricta: TODAS las palabras de la consulta deben aparecer.
    /// El puntaje total es la suma de la mejor coincidencia de cada palabra.
    static func matchScore(words: [String], fields: [String]) -> Int? {
        let compact = compactFields(fields)
        guard !words.isEmpty else { return 0 }
        var total = 0
        for word in words {
            guard let s = wordScore(word, fields: fields, compactFields: compact) else { return nil }
            total += s
        }
        return total
    }

    /// ✅ Coincidencia RELAJADA: al menos UNA palabra debe coincidir. Solo se
    /// usa cuando la estricta no devolvió resultados, para no dejar la búsqueda
    /// vacía porque una palabra no existe en ningún campo.
    static func relaxedScore(words: [String], fields: [String]) -> Int? {
        let compact = compactFields(fields)
        var total = 0
        var matched = 0
        for word in words {
            if let s = wordScore(word, fields: fields, compactFields: compact) {
                total += s
                matched += 1
            }
        }
        return matched > 0 ? total : nil
    }

    // MARK: - Búsquedas

    /// Canciones que coinciden, ordenadas por relevancia (mejor puntaje
    /// primero, estable para puntajes iguales).
    func searchSongs(_ songs: [Song], query: String) -> [Song] {
        let words = Self.queryWords(query)
        guard !words.isEmpty else { return songs }
        var scored: [(song: Song, score: Int)] = []
        scored.reserveCapacity(min(songs.count, 64))
        var fields: [String] = []
        for song in songs {
            // ✅ Fallback al vuelo si la entrada no existe en el índice.
            let e = songEntries[song.id] ?? SongEntry(
                title: Self.fold(song.title),
                artist: Self.fold(song.artist),
                albumArtist: Self.fold(song.albumArtist),
                album: Self.fold(song.album)
            )
            fields = [e.title, e.artist, e.albumArtist, e.album]
            if let score = Self.matchScore(words: words, fields: fields) {
                scored.append((song, score))
            } else if words.count > 1, let relaxed = Self.relaxedScore(words: words, fields: fields) {
                // ✅ Modo relajado: si la búsqueda estricta no encuentra nada
                // en TODA la búsqueda, aceptar coincidencias parciales (alguna
                // palabra) en una segunda pasada, en vez de devolver vacío.
                scored.append((song, relaxed / 2))
            }
        }
        scored.sort { $0.score > $1.score }
        return scored.map(\.song)
    }

    func searchAlbums(_ albums: [Album], query: String) -> [Album] {
        let words = Self.queryWords(query)
        guard !words.isEmpty else { return albums }
        var scored: [(album: Album, score: Int)] = []
        scored.reserveCapacity(min(albums.count, 32))
        for album in albums {
            // ✅ Fallback si la entrada del índice no existe (índice desactualizado):
            // se calcula al vuelo en vez de DESCARTAR el álbum silenciosamente —
            // esa era otra causa de "álbumes que existen y no aparecen".
            let e = albumEntries[album.id] ?? AlbumEntry(
                name: Self.fold(album.name),
                artist: Self.fold(album.artist),
                songTitles: album.songs.map { Self.fold($0.title) }
            )
            var fields = [e.name, e.artist]
            fields.append(contentsOf: e.songTitles)
            if let score = Self.matchScore(words: words, fields: fields) {
                scored.append((album, score))
            } else if words.count > 1, let relaxed = Self.relaxedScore(words: words, fields: fields) {
                scored.append((album, relaxed / 2))
            }
        }
        scored.sort { $0.score > $1.score }
        return scored.map(\.album)
    }

    func searchArtists(_ artists: [Artist], query: String) -> [Artist] {
        let words = Self.queryWords(query)
        guard !words.isEmpty else { return artists }
        var scored: [(artist: Artist, score: Int)] = []
        scored.reserveCapacity(min(artists.count, 32))
        for artist in artists {
            // ✅ Fallback al vuelo si la entrada no existe en el índice.
            let e = artistEntries[artist.id] ?? ArtistEntry(name: Self.fold(artist.name))
            // ✅ SOLO el nombre del artista decide si aparece. Si buscas por el
            // título de una canción, usa la pestaña de Canciones.
            let fields = [e.name]
            if let score = Self.matchScore(words: words, fields: fields) {
                scored.append((artist, score))
            } else if words.count > 1, let relaxed = Self.relaxedScore(words: words, fields: fields) {
                scored.append((artist, relaxed / 2))
            }
        }
        scored.sort { $0.score > $1.score }
        return scored.map(\.artist)
    }
}
