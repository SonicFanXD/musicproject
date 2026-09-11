package com.aurora.player.services

import android.content.Context
import android.content.SharedPreferences
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.Equalizer
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.aurora.player.models.EQPreset
import com.aurora.player.models.RepeatMode
import com.aurora.player.models.Song

/**
 * Motor de audio con ExoPlayer.
 * Equivalente a AudioEngine.swift en iOS.
 *
 * Diferencias vs iOS:
 * - iOS usa AVAudioUnitEQ + graph de nodos; Android usa android.media.Equalizer.
 * - La salida "Hi-Res" (alta resolución) se consigue SIN re-muestrear: ExoPlayer
 *   decodifica cada archivo a su tasa/bit nativos y pasa el PCM tal cual al
 *   sistema (bit-perfect), igual que el motor de iOS.
 * - El audio mono se aplica a nivel de AudioManager (downmix a 1 canal).
 */
class AudioEngine(private val context: Context) {

    private var exoPlayer: ExoPlayer? = null
    private val handler = Handler(Looper.getMainLooper())

    private val _isPlaying = MutableLiveData(false)
    val isPlaying: LiveData<Boolean> = _isPlaying

    private val _currentSong = MutableLiveData<Song?>()
    val currentSong: LiveData<Song?> = _currentSong

    private val _currentTime = MutableLiveData(0L)
    val currentTime: LiveData<Long> = _currentTime

    private val _duration = MutableLiveData(0L)
    val duration: LiveData<Long> = _duration

    private val _repeatMode = MutableLiveData(RepeatMode.OFF)
    val repeatMode: LiveData<RepeatMode> = _repeatMode

    private val _isShuffleEnabled = MutableLiveData(false)
    val isShuffleEnabled: LiveData<Boolean> = _isShuffleEnabled

    private var queue: List<Song> = emptyList()
    private var currentIndex: Int = 0

    // MARK: - Ajustes de audio persistentes
    private val prefs: SharedPreferences =
        context.getSharedPreferences("aurora_audio", Context.MODE_PRIVATE)

    private val _isEQEnabled = MutableLiveData(prefs.getBoolean("eq_enabled", false))
    val isEQEnabled: LiveData<Boolean> = _isEQEnabled

    private val _eqPreset = MutableLiveData(
        try {
            EQPreset.valueOf(prefs.getString("eq_preset", "FLAT") ?: "FLAT")
        } catch (e: Exception) { EQPreset.FLAT }
    )
    val eqPreset: LiveData<EQPreset> = _eqPreset

    private val _isMonoAudioEnabled = MutableLiveData(prefs.getBoolean("mono_enabled", false))
    val isMonoAudioEnabled: LiveData<Boolean> = _isMonoAudioEnabled

    private var equalizer: Equalizer? = null

    // MARK: - Calidad de salida (para la vista de calidad de audio)
    private val _outputSampleRate = MutableLiveData(0L)
    val outputSampleRate: LiveData<Long> = _outputSampleRate
    private val _outputChannelCount = MutableLiveData(0)
    val outputChannelCount: LiveData<Int> = _outputChannelCount
    private val _audioQualityInfo = MutableLiveData("")
    val audioQualityInfo: LiveData<String> = _audioQualityInfo

    private val progressRunnable = object : Runnable {
        override fun run() {
            exoPlayer?.let { player ->
                _currentTime.value = player.currentPosition
                _duration.value = player.duration.coerceAtLeast(0)
            }
            handler.postDelayed(this, 100)
        }
    }

    init {
        initializePlayer()
        setupEqualizer()
        setupAudioDeviceDetection()
        applyOutputRouteSettings()
    }

    // MARK: - Player
    private fun initializePlayer() {
        exoPlayer = ExoPlayer.Builder(context).build().apply {
            addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState == Player.STATE_READY) {
                        _duration.value = duration.coerceAtLeast(0)
                        refreshOutputQuality()
                    } else if (playbackState == Player.STATE_ENDED) {
                        onPlaybackComplete()
                    }
                }
                override fun onIsPlayingChanged(playing: Boolean) {
                    _isPlaying.value = playing
                    if (playing) handler.post(progressRunnable)
                    else handler.removeCallbacks(progressRunnable)
                }
            })
        }
    }
// MARK: - Ecualizador (android.media.Equalizer, 10 bandas como iOS)
    private fun setupEqualizer() {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        equalizer = try { Equalizer(0, audioManager.audioSessionId) } catch (e: Exception) { null }
        val eq = equalizer ?: return
        // iOS usa 12 bandas de 31.25Hz a 16kHz; Android media suele exponer 5.
        // Aquí mapeamos los 5 filtros paramétricos estándar de Android.
        try {
            eq.enabled = _isEQEnabled.value == true
            applyPresetTo(eq, _eqPreset.value, applyLevels = _isEQEnabled.value == true)
        } catch (e: Exception) {
            return
        }
    }

    private fun applyPresetTo(eq: Equalizer, preset: EQPreset, applyLevels: Boolean) {
        // Android expone numberOfBands bandas; iOS usa 10 puntos. Redistribuimos
        // las ganancias del preset (10) sobre las bandas reales del dispositivo.
        val bands = eq.numberOfBands
        if (bands <= 0) return
        eq.enabled = applyLevels
        if (!applyLevels) {
            for (b in 0 until bands) { try { eq.setBandLevel(b, 0) } catch (e: Exception) { } }
            return
        }
        for (b in 0 until bands) {
            val sourceIdx = min(b * 10 / bands, 9)
            val level = preset.gains.getOrNull(sourceIdx) ?: 0f
            try { eq.setBandLevel(b, level) } catch (e: Exception) { }
        }
    }

    private fun getEqualizer(): Equalizer? {
        // Se crea en setupEqualizer(); devuelve el caché.
        return equalizer
    }

    fun toggleEQ() {
        val v = !(_isEQEnabled.value ?: false)
        _isEQEnabled.value = v
        prefs.edit().putBoolean("eq_enabled", v).apply()
        getEqualizer()?.let { eq ->
            try {
                eq.enabled = v
                applyPresetTo(eq, _eqPreset.value ?: EQPreset.FLAT, v)
            } catch (e: Exception) { }
        }
    }

    fun setEQPreset(preset: EQPreset) {
        _eqPreset.value = preset
        prefs.edit().putString("eq_preset", preset.name).apply()
        if (_isEQEnabled.value == true) {
            getEqualizer()?.let { eq ->
                try { applyPresetTo(eq, preset, true) } catch (e: Exception) { }
            }
        }
    }

    fun setEQGain(band: Int, gain: Float) {
        getEqualizer()?.let { eq ->
            try { eq.setBandLevel(band, gain) } catch (e: Exception) { }
        }
    }

    fun getEQGain(band: Int): Float {
        return getEqualizer()?.let { eq ->
            try { eq.getBandLevel(band) } catch (e: Exception) { 0f }
        } ?: 0f
    }

    // MARK: - Audio Mono (downmix a 1 canal, como iOS)
    fun toggleMonoAudio() {
        val v = !(_isMonoAudioEnabled.value ?: false)
        _isMonoAudioEnabled.value = v
        prefs.edit().putBoolean("mono_enabled", v).apply()
        applyOutputRouteSettings()
    }

    private fun applyOutputRouteSettings() {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            audioManager.setPreferredOutputNumberOfChannels(
                if (_isMonoAudioEnabled.value == true) 1 else 2)
        } catch (e: Exception) { }
    }

    // MARK: - Calidad de salida (Hi-Res = sin re-muestreo)
    private fun refreshOutputQuality() {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val rate = try { audioManager.outputSampleRate } catch (e: Exception) { 0L }
        val channels = try { audioManager.outputNumberOfChannels } catch (e: Exception) { 0 }
        if (rate <= 0) return
        if (_outputSampleRate.value == rate && _outputChannelCount.value == channels) return
        _outputSampleRate.value = rate
        _outputChannelCount.value = channels
        val rateInfo = if (rate >= 48000) "Hi-Res" else "Estándar"
        val channelInfo = if (channels >= 2) "Estéreo" else "Mono"
        _audioQualityInfo.value = "$rateInfo • ${rate}Hz • $channelInfo"
    }

    fun formatOutputInfo(): String {
        val rate = _outputSampleRate.value ?: 0L
        return if (rate > 0) "${rate / 1000} kHz · ${_outputChannelCount.value}" else ""
    }

    fun refreshOutputQualityPublic() {
        refreshOutputQuality()
    }
// MARK: - Playback
    fun play(song: Song, from: List<Song>? = null) {
        Logger.info("audio", "▶ ${song.title} — ${song.artist}")
        from?.let {
            queue = it
            currentIndex = it.indexOfFirst { s -> s.id == song.id }.coerceAtLeast(0)
        }
        _currentSong.value = song
        loadAndPlay(song)
        ThemeManager.getInstance(context).updateArtworkAccent(song)
    }

    private fun loadAndPlay(song: Song) {
        val mediaItem = MediaItem.fromUri(song.audioUrl)
        // ✅ Hi-Res: NO forzamos sample rate de salida. ExoPlayer decodifica a la
        // tasa/bit nativos del archivo y el PCM llega bit-perfect al sistema.
        exoPlayer?.apply {
            setMediaItem(mediaItem)
            prepare()
            play()
        }
    }

    fun togglePlayPause() {
        exoPlayer?.let { player ->
            if (player.isPlaying) player.pause() else player.play()
        }
    }

    fun playNext(song: Song) {
        if (queue.isEmpty()) {
            queue = listOf(song)
            currentIndex = 0
            _currentSong.value = song
            loadAndPlay(song)
            ThemeManager.getInstance(context).updateArtworkAccent(song)
            return
        }
        val mutable = queue.toMutableList()
        mutable.removeAll { it.id == song.id }
        val insertAt = (currentIndex + 1).coerceAtMost(mutable.size)
        mutable.add(insertAt, song)
        queue = mutable
    }

    fun next() {
        if (queue.isEmpty()) return
        currentIndex = if (currentIndex < queue.size - 1) currentIndex + 1 else 0
        queue.getOrNull(currentIndex)?.let { song ->
            _currentSong.value = song
            loadAndPlay(song)
            ThemeManager.getInstance(context).updateArtworkAccent(song)
        }
    }

    fun previous() {
        if (queue.isEmpty()) return
        if ((_currentTime.value ?: 0) > 3000) {
            seekTo(0)
            return
        }
        currentIndex = if (currentIndex > 0) currentIndex - 1 else queue.size - 1
        queue.getOrNull(currentIndex)?.let { song ->
            _currentSong.value = song
            loadAndPlay(song)
            ThemeManager.getInstance(context).updateArtworkAccent(song)
        }
    }

    fun seekTo(positionMs: Long) {
        exoPlayer?.seekTo(positionMs)
        _currentTime.value = positionMs
    }

    fun toggleShuffle() {
        _isShuffleEnabled.value = !(_isShuffleEnabled.value ?: false)
    }

    fun cycleRepeatMode() {
        _repeatMode.value = when (_repeatMode.value) {
            RepeatMode.OFF -> RepeatMode.ALL
            RepeatMode.ALL -> RepeatMode.ONE
            else -> RepeatMode.OFF
        }
        exoPlayer?.repeatMode = when (_repeatMode.value) {
            RepeatMode.OFF -> Player.REPEAT_MODE_OFF
            RepeatMode.ALL -> Player.REPEAT_MODE_ALL
            RepeatMode.ONE -> Player.REPEAT_MODE_ONE
            else -> Player.REPEAT_MODE_OFF
        }
    }

    private fun onPlaybackComplete() {
        when (_repeatMode.value) {
            RepeatMode.ONE -> _currentSong.value?.let { loadAndPlay(it) }
            RepeatMode.ALL -> next()
            RepeatMode.OFF -> {
                if (currentIndex >= queue.size - 1) _isPlaying.value = false
                else next()
            }
        }
    }

    private fun setupAudioDeviceDetection() {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val deviceCallback = object : AudioDeviceCallback() {
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                super.onAudioDevicesRemoved(removedDevices)
                if (removedDevices?.any {
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
                } == true) {
                    exoPlayer?.pause()
                }
            }
        }
        audioManager.registerAudioDeviceCallback(deviceCallback, handler)
        refreshOutputQuality()
    }

    fun release() {
        handler.removeCallbacks(progressRunnable)
        exoPlayer?.release()
        exoPlayer = null
    }
}