package com.aurora.player.models

import android.net.Uri

/**
 * Modelo de datos para una canción.
 * Equivalente a Song.swift en iOS.
 */
data class Song(
    val id: String,
    val title: String,
    val artist: String,
    val album: String,
    val albumArtist: String,
    val duration: Long, // en milisegundos
    val trackNumber: Int = 0,
    val year: Int = 0,
    val audioUrl: String,
    val artworkUri: String? = null,
    val genre: String = "",
    val isLiked: Boolean = false,
    val filePath: String = ""
) {
    /**
     * Retorna el artista preferido (albumArtist si está disponible, si no artist)
     */
    val preferredArtist: String
        get() = if (albumArtist.isNotEmpty()) albumArtist else artist

    /**
     * Formatea la duración en formato mm:ss
     */
    fun formattedDuration(): String {
        val totalSeconds = duration / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return String.format("%d:%02d", minutes, seconds)
    }
}

/**
 * Categorías de la biblioteca (equivalente a LibraryCategory en iOS)
 */
enum class LibraryCategory(val displayName: String) {
    SONGS("Songs"),
    ALBUMS("Albums"),
    ARTISTS("Artists"),
    PLAYLISTS("Playlists")
}

/**
 * Opciones de ordenamiento para canciones
 */
enum class SortOption {
    TITLE,
    ARTIST,
    ALBUM,
    DURATION,
    DATE_ADDED
}

/**
 * Opciones de ordenamiento para álbumes
 */
enum class AlbumSortOption {
    TITLE,
    ARTIST,
    YEAR
}

/**
 * Opciones de ordenamiento para artistas
 */
enum class ArtistSortOption {
    NAME,
    ALBUM_COUNT
}

/**
 * Modos de repetición
 */
enum class RepeatMode {
    OFF,
    ALL,
    ONE
}

/**
 * Presets de ecualizador (igual ganancia por banda que EQPreset.swift en iOS).
 * 10 bandas: [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000] Hz.
 */
enum class EQPreset(val displayName: String, val gains: List<Float>) {
    FLAT("Plano", listOf(0,0,0,0,0,0,0,0,0,0)),
    BASS("Graves", listOf(8,7,5,3,0,0,0,0,0,0)),
    TREBLE("Agudos", listOf(0,0,0,0,0,0,3,5,7,8)),
    VOCAL("Vocales", listOf(2,4,5,4,2,0,0,0,0,0)),
    CLASSICAL("Clásica", listOf(5,4,3,2,0,0,2,3,4,5)),
    ELECTRONIC("Electrónica", listOf(6,5,3,0,-2,-2,0,3,5,6)),
    POP("Pop", listOf(3,4,3,1,0,0,1,3,4,3)),
    ROCK("Rock", listOf(6,5,4,2,0,0,2,4,5,6)),
    JAZZ("Jazz", listOf(4,3,2,2,0,0,2,3,4,4));
}