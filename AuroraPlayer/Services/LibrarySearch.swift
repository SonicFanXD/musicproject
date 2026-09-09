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
    }

    struct ArtistEntry {
        let name: String
        // Títulos/álbumes de sus canciones: un artista aparece si una de sus
        // canciones coincide con la búsqueda.
        let songTitles: [String]
        let songAlbums: [String]
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
                artist: Self.fold(album.artist)
            )
        }
        albumEntries = newAlbums

        var newArtists: [String: ArtistEntry] = [:]
        newArtists.reserveCapacity(artists.count)
        for artist in artists {
            newArtists[artist.id] = ArtistEntry(
                name: Self.fold(artist.name),
                songTitles: artist.songs.map { Self.fold($0.title) },
                songAlbums: artist.songs.map { Self.fold($0.album) }
            )
        }
        artistEntries = newArtists
    }

    // MARK: - Matching por palabras (parte 2)

    /// Puntaje de UNA palabra contra los campos (en orden de prioridad:
    /// el índice 0 es el campo principal, p. ej. el título).
    /// Retorna nil si la palabra no coincide.
    private static func wordScore(_ word: String, fields: [String]) -> Int? {
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
        return best
    }

    /// Coincidencia por palabras: TODAS las palabras de la consulta deben
    /// aparecer en algún campo. El puntaje total es la suma de la mejor
    /// coincidencia de cada palabra.
    static func matchScore(words: [String], fields: [String]) -> Int? {
        guard !words.isEmpty else { return 0 }
        var total = 0
        for word in words {
            guard let s = wordScore(word, fields: fields) else { return nil }
            total += s
        }
        return total
    }

    // MARK: - Búsquedas

    /// Canciones que coinciden, ordenadas por relevancia (mejor puntaje
    /// primero, estable para puntajes iguales).
    func searchSongs(_ songs: [Song], query: String) -> [Song] {
        let words = Self.queryWords(query)
        guard !words.isEmpty else { return songs }
        var scored: [(song: Song, score: Int)] = []
        scored.reserveCapacity(min(songs.count, 64))
        for song in songs {
            guard let e = songEntries[song.id] else { continue }
            if let score = Self.matchScore(words: words, fields: [e.title, e.artist, e.albumArtist, e.album]) {
                scored.append((song, score))
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
            guard let e = albumEntries[album.id] else { continue }
            if let score = Self.matchScore(words: words, fields: [e.name, e.artist]) {
                scored.append((album, score))
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
            guard let e = artistEntries[artist.id] else { continue }
            // El nombre del artista es el campo principal; sus canciones y
            // álbumes también hacen que aparezca.
            var fields = [e.name, e.name]
            fields.append(contentsOf: e.songAlbums)
            fields.append(contentsOf: e.songTitles)
            if let score = Self.matchScore(words: words, fields: fields) {
                scored.append((artist, score))
            }
        }
        scored.sort { $0.score > $1.score }
        return scored.map(\.artist)
    }
}
