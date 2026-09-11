package com.aurora.player.services

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.palette.graphics.Palette
import com.aurora.player.R
import com.aurora.player.models.Song

/**
 * Gestor central del tema: color de acento aplicable en toda la app.
 * Equivalente a ThemeManager.swift en iOS.
 */
class ThemeManager private constructor(private val context: Context) {

    companion object {
        private const val PREFS_NAME = "aurora_theme"
        private const val KEY_ACCENT_FROM_ARTWORK = "accent_from_artwork"
        private const val KEY_ACCENT_COLOR = "accent_color"
        private const val KEY_ACCENT_INDEX = "accent_index"
        private const val KEY_THEME_MODE = "theme_mode"
        private const val KEY_REDUCE_TRANSPARENCY = "reduce_transparency"
        private const val KEY_ARTWORK_CORNER = "artwork_corner"
        private const val KEY_SHOW_VISUALIZER = "show_visualizer"
        private const val KEY_LYRICS_DEFAULT = "lyrics_by_default"

        /** Colores de acento manual (0=predeterminado, misma tabla de iOS). */
        val ACCENT_COLORS = listOf(
            0xFF9E66F2.toInt(), // Morado (predeterminado)
            0xFF338CF2.toInt(), // Azul Aurora
            0xFF1ABF80.toInt(), // Esmeralda
            0xFFF24D99.toInt(), // Rosa Neón
            0xFFFA9E26.toInt(), // Ámbar Solar
            0xFF1C1C21.toInt(), // Negro Grafito
            0xFF8C141C.toInt()  // Rojo Oscuro
        )
        val ACCENT_NAMES = listOf(
            "Morado (predeterminado)", "Azul Aurora", "Esmeralda",
            "Rosa Neón", "Ámbar Solar", "Negro Grafito", "Rojo Oscuro"
        )

        fun accentColorForIndex(index: Int): Int {
            val i = index.coerceIn(0, ACCENT_COLORS.size - 1)
            return ACCENT_COLORS[i]
        }

        @Volatile
        private var instance: ThemeManager? = null

        fun getInstance(context: Context): ThemeManager {
            return instance ?: synchronized(this) {
                instance ?: ThemeManager(context.applicationContext).also { instance = it }
            }
        }
    }

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _accentColor = MutableLiveData<Int>()
    val accentColor: LiveData<Int> = _accentColor
    private val _accentIndex = MutableLiveData(prefs.getInt(KEY_ACCENT_INDEX, 0))
    val accentIndex: LiveData<Int> = _accentIndex

    // Modo de tema: 0=Sistema, 1=Claro, 2=Oscuro (equivale a uiTheme en iOS)
    private val _themeMode = MutableLiveData(prefs.getInt(KEY_THEME_MODE, 0))
    val themeMode: LiveData<Int> = _themeMode

    fun setThemeMode(mode: Int) {
        val m = mode.coerceIn(0, 2)
        _themeMode.value = m
        prefs.edit().putInt(KEY_THEME_MODE, m).apply()
        AppCompatDelegate.setDefaultNightMode(
            when (m) {
                1 -> AppCompatDelegate.MODE_NIGHT_NO      // Claro
                2 -> AppCompatDelegate.MODE_NIGHT_YES     // Oscuro
                else -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM // Sistema
            }
        )
    }

    /** Aplica el modo guardado al arrancar (lo llama AuroraPlayerApp). */
    fun applySavedThemeMode() {
        AppCompatDelegate.setDefaultNightMode(
            when (prefs.getInt(KEY_THEME_MODE, 0)) {
                1 -> AppCompatDelegate.MODE_NIGHT_NO
                2 -> AppCompatDelegate.MODE_NIGHT_YES
                else -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
            }
        )
    }

    var accentFromArtwork: Boolean
        get() = prefs.getBoolean(KEY_ACCENT_FROM_ARTWORK, true)
        set(value) {
            prefs.edit().putBoolean(KEY_ACCENT_FROM_ARTWORK, value).apply()
            if (!value) {
                _accentColor.value = accentColorForIndex(_accentIndex.value ?: 0)
            } else {
                latestSongForAccent?.let { extractColorFromArtwork(it) }
            }
        }

    private var latestSongForAccent: Song? = null

    val defaultAccentColor: Int
        get() = context.getColor(R.color.accent_default)

    init {
        _accentIndex.value = prefs.getInt(KEY_ACCENT_INDEX, 0)
        val savedColor = prefs.getInt(KEY_ACCENT_COLOR, 0)
        _accentColor.value = if (savedColor == 0 || !accentFromArtwork)
            accentColorForIndex(_accentIndex.value ?: 0) else savedColor
    }

    fun setAccentIndex(index: Int) {
        val clamped = index.coerceIn(0, ACCENT_COLORS.size - 1)
        _accentIndex.value = clamped
        prefs.edit().putInt(KEY_ACCENT_INDEX, clamped).apply()
        if (!accentFromArtwork) {
            _accentColor.value = accentColorForIndex(clamped)
        }
    }

    fun currentAccentInt(): Int {
        return _accentColor.value ?: accentColorForIndex(_accentIndex.value ?: 0)
    }

    fun getCurrentAccentColor(): Int = currentAccentInt()

    // MARK: - Ajustes de apariencia/reproducción (equivale a @AppStorage de iOS)
    val isReduceTransparencyEnabled: Boolean
        get() = prefs.getBoolean(KEY_REDUCE_TRANSPARENCY, false)

    fun setReduceTransparency(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_REDUCE_TRANSPARENCY, enabled).apply()
    }

    /** Fondo de tarjeta según el ajuste "Reducir transparencia". */
    fun cardBackgroundRes(): Int =
        if (isReduceTransparencyEnabled) R.drawable.opaque_background else R.drawable.glass_background

    /** Radio de esquinas de la carátula en dp (0..44, como el slider de iOS). */
    var artworkCornerDp: Float
        get() = prefs.getFloat(KEY_ARTWORK_CORNER, 22f)
        set(value) { prefs.edit().putFloat(KEY_ARTWORK_CORNER, value.coerceIn(0f, 44f)).apply() }

    val isVisualizerEnabled: Boolean
        get() = prefs.getBoolean(KEY_SHOW_VISUALIZER, true)

    fun setVisualizerEnabled(v: Boolean) {
        prefs.edit().putBoolean(KEY_SHOW_VISUALIZER, v).apply()
    }

    val isLyricsByDefaultEnabled: Boolean
        get() = prefs.getBoolean(KEY_LYRICS_DEFAULT, false)

    fun setLyricsByDefaultEnabled(v: Boolean) {
        prefs.edit().putBoolean(KEY_LYRICS_DEFAULT, v).apply()
    }

    fun updateArtworkAccent(song: Song?) {
        song?.let { latestSongForAccent = it }
        if (accentFromArtwork) {
            extractColorFromArtwork(song)
        }
    }

    private fun extractColorFromArtwork(song: Song?) {
        if (song == null) {
            _accentColor.postValue(defaultAccentColor)
            return
        }
        Thread {
            try {
                // 1. Portada embebida del archivo (MediaMetadataRetriever)
                // 2. artworkUri si existe (SAF / MediaStore)
                var bitmap = loadEmbeddedArtwork(song.audioUrl)
                if (bitmap == null && song.artworkUri != null) {
                    bitmap = loadBitmapFromUri(song.artworkUri)
                }
                if (bitmap != null) {
                    val dominantColor = extractDominantColor(bitmap)
                    val readableColor = normalizeForReadability(dominantColor)
                    _accentColor.postValue(readableColor)
                    prefs.edit().putInt(KEY_ACCENT_COLOR, readableColor).apply()
                } else {
                    _accentColor.postValue(defaultAccentColor)
                }
                bitmap?.recycle()
            } catch (e: Exception) {
                _accentColor.postValue(defaultAccentColor)
            }
        }.start()
    }

    private fun loadEmbeddedArtwork(audioUrl: String): Bitmap? {
        return try {
            val mmr = android.media.MediaMetadataRetriever()
            mmr.setDataSource(context, android.net.Uri.parse(audioUrl))
            val art = mmr.embeddedPicture
            mmr.release()
            if (art != null) android.graphics.BitmapFactory.decodeByteArray(art, 0, art.size)
            else null
        } catch (e: Exception) { null }
    }

    private fun loadBitmapFromUri(uriString: String): Bitmap? {
        return try {
            val uri = android.net.Uri.parse(uriString)
            context.contentResolver.openInputStream(uri)?.use { inputStream ->
                val bytes = inputStream.readBytes()
                // Downsample: la portada solo se usa para Palette, 200px basta
                val opts = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
                android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
                var sample = 1
                while (opts.outWidth / sample > 200 || opts.outHeight / sample > 200) sample *= 2
                val real = android.graphics.BitmapFactory.Options().apply { inSampleSize = sample }
                android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, real)
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun extractDominantColor(bitmap: Bitmap): Int {
        val palette = Palette.from(bitmap).generate()

        palette.getVibrantColor(Color.TRANSPARENT)?.let { vibrant ->
            if (vibrant != Color.TRANSPARENT && isColorVibrant(vibrant)) {
                return vibrant
            }
        }

        palette.getDarkVibrantColor(Color.TRANSPARENT)?.let { darkVibrant ->
            if (darkVibrant != Color.TRANSPARENT) {
                return darkVibrant
            }
        }

        palette.getLightVibrantColor(Color.TRANSPARENT)?.let { lightVibrant ->
            if (lightVibrant != Color.TRANSPARENT) {
                return lightVibrant
            }
        }

        return palette.dominantSwatch?.rgb ?: defaultAccentColor
    }

    private fun isColorVibrant(color: Int): Boolean {
        val hsv = FloatArray(3)
        Color.colorToHSV(color, hsv)
        val saturation = hsv[1]
        val brightness = hsv[2]
        return saturation >= 0.12f && brightness >= 0.10f && brightness <= 0.92f
    }

    private fun normalizeForReadability(color: Int): Int {
        val hsv = FloatArray(3)
        Color.colorToHSV(color, hsv)
        hsv[1] = hsv[1].coerceIn(0.08f, 0.95f)
        hsv[2] = hsv[2].coerceIn(0.10f, 0.92f)
        return Color.HSVToColor(hsv)
    }

    fun contrastingText(on backgroundColor: Int): Int {
        val luminance = calculateLuminance(backgroundColor)
        return if (luminance > 0.5) Color.BLACK else Color.WHITE
    }

    private fun calculateLuminance(color: Int): Double {
        val r = Color.red(color) / 255.0
        val g = Color.green(color) / 255.0
        val b = Color.blue(color) / 255.0
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}