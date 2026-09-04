extension FileAccessService {
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
            song.artist.isEmpty ? "Artista desconocido" : song.artist
        }
        
        return grouped.map { (artistName, songs) in
            Artist(
                name: artistName,
                songs: songs
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct AlbumKey: Hashable {
    let album: String
    let artist: String
}