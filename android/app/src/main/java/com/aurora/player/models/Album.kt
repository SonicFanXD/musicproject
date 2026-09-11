package com.aurora.player.models

/**
 * Modelo de datos para un álbum.
 */
data class Album(
    val id: String,
    val title: String,
    val artist: String,
    val year: Int = 0,
    val artworkUri: String? = null,
    val songs: List<Song> = emptyList()
) {
    /**
     * Duración total del álbum en milisegundos
     */
    val totalDuration: Long
        get() = songs.sumOf { it.duration }

    /**
     * Número de canciones en el álbum
     */
    val songCount: Int
        get() = songs.size

    /**
     * Formatea la duración total en formato hh:mm:ss o mm:ss
     */
    fun formattedDuration(): String {
        val totalSeconds = totalDuration / 1000
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = totalSeconds % 60

        return if (hours > 0) {
            String.format("%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format("%d:%02d", minutes, seconds)
        }
    }
}

/**
 * Modelo de datos para un artista.
 */
data class Artist(
    val id: String,
    val name: String,
    val artworkUri: String? = null,
    val albums: List<Album> = emptyList(),
    val songs: List<Song> = emptyList()
) {
    /**
     * Número de álbumes del artista
     */
    val albumCount: Int
        get() = albums.size

    /**
     * Número de canciones del artista
     */
    val songCount: Int
        get() = songs.size

    /**
     * Duración total de todas las canciones
     */
    val totalDuration: Long
        get() = songs.sumOf { it.duration }
}

/**
 * Modelo de datos para una playlist.
 */
data class Playlist(
    val id: String,
    val name: String,
    val description: String = "",
    val songIds: List<String> = emptyList(),
    val artworkUri: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
) {
    val songCount: Int get() = songIds.size
}

/**
 * Carpeta de música (SAF en Android, equivale a MusicFolder con bookmark en iOS).
 * En Android se guarda el treeUri persistido, no bookmarkData.
 */
data class MusicFolder(
    val id: String,
    val displayName: String,
    val treeUri: String
)