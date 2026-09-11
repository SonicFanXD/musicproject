package com.aurora.player.services

import android.content.Context
import android.content.SharedPreferences
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData

/**
 * Gestor central de idioma. Equivalente a Localization.swift en iOS.
 * Las Activities observan currentLanguage para re-renderizar al instante.
 */
class Localization private constructor(private val context: Context) {

    enum class Language(val code: Int) { SPANISH(0), ENGLISH(1) }

    companion object {
        @Volatile private var instance: Localization? = null
        private const val PREFS = "aurora_lang"
        private const val KEY = "com.aurora.language"
        fun getInstance(context: Context): Localization {
            return instance ?: synchronized(this) {
                instance ?: Localization(context.applicationContext).also { instance = it }
            }
        }
        fun localized(context: Context, key: String): String {
            return getInstance(context).get(key)
        }
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private val _currentLanguage = MutableLiveData<Language>()
    val currentLanguage: LiveData<Language> = _currentLanguage

    init {
        val saved = prefs.getInt(KEY, 0)
        _currentLanguage.value = if (saved == 1) Language.ENGLISH else Language.SPANISH
    }

    fun setLanguage(lang: Language) {
        _currentLanguage.value = lang
        prefs.edit().putInt(KEY, lang.code).apply()
    }

    /** Idioma actual sin LiveData (para chips/pickers). */
    val current: Language
        get() = _currentLanguage.value ?: Language.SPANISH

    fun get(key: String): String {
        val lang = _currentLanguage.value ?: Language.SPANISH
        val table: Map<String, Pair<String, String>> = mapOf(
            "settings.title" to ("Ajustes" to "Settings"),
            "settings.library" to ("Biblioteca" to "Library"),
            "settings.audio" to ("Audio" to "Audio"),
            "settings.appearance" to ("Apariencia" to "Appearance"),
            "settings.playback" to ("Reproducción" to "Playback"),
            "settings.about" to ("Acerca de" to "About"),
            "library.search" to ("Buscar canciones, álbumes, artistas…" to "Search songs, albums, artists…"),
            "library.empty" to ("Sin música" to "No music found"),
            "actions.play" to ("Reproducir" to "Play"),
            "actions.like" to ("Me gusta" to "Like"),
            "actions.unlike" to ("Ya no me gusta" to "Unlike"),
            "context.addToPlaylist" to ("Añadir a playlist" to "Add to playlist"),
            "context.playNext" to ("Reproducir siguiente" to "Play next"),
            "context.playNow" to ("Reproducir ahora" to "Play now"),
            "nowPlaying.queue" to ("Cola" to "Queue"),
            "nowPlaying.lyrics" to ("Letra" to "Lyrics"),
            "quality.accessibility.cast" to ("Enviar a dispositivo" to "Cast to device"),
            "details.unknownArtist" to ("Artista desconocido" to "Unknown artist"),
            // Secciones y ajustes (Ajustes)
            "settings.performance" to ("Rendimiento" to "Performance"),
            "settings.stats" to ("Estadísticas" to "Statistics"),
            "settings.customization" to ("Personalización" to "Customization"),
            "settings.advanced" to ("Avanzado" to "Advanced"),
            "settings.logs" to ("Registros" to "Logs"),
            "settings.language" to ("Idioma" to "Language"),
            "settings.theme" to ("Tema" to "Theme"),
            "settings.reduceTransparency" to ("Reducir transparencia" to "Reduce transparency"),
            "settings.artworkCorners" to ("Esquinas de carátula" to "Artwork corners"),
            "settings.visualizer" to ("Visualizador" to "Visualizer"),
            "settings.lyricsDefault" to ("Letras por defecto" to "Lyrics by default"),
            "settings.equalizer" to ("Equalizador" to "Equalizer"),
            "settings.monoAudio" to ("Audio Mono" to "Mono Audio"),
            "settings.audioOutput" to ("Salida de audio" to "Audio output"),
            "settings.device" to ("Dispositivo" to "Device"),
            "settings.accentFromArtwork" to ("Acento desde carátula" to "Accent from artwork"),
            "library.songs" to ("Canciones" to "Songs"),
            "library.albums" to ("Álbumes" to "Albums"),
            "library.artists" to ("Artistas" to "Artists")
        )
        val pair = table[key] ?: return key
        return if (lang == Language.SPANISH) pair.first else pair.second
    }
}
