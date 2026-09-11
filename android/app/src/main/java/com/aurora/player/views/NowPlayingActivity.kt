package com.aurora.player.views

import android.content.Intent
import android.graphics.Outline
import android.os.Bundle
import android.view.View
import android.view.ViewOutlineProvider
import android.widget.SeekBar
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import coil.load
import com.aurora.player.R
import com.aurora.player.databinding.ActivityNowPlayingBinding
import com.aurora.player.models.RepeatMode
import com.aurora.player.services.Logger
import com.aurora.player.services.ThemeManager
import com.aurora.player.viewmodels.LibraryViewModel
import com.google.android.gms.cast.framework.CastButtonFactory

class NowPlayingActivity : AppCompatActivity() {
    private lateinit var binding: ActivityNowPlayingBinding
    private val vm: LibraryViewModel by viewModels()
    private var scrubbing = false
    private var openedLyricsOnce = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityNowPlayingBinding.inflate(layoutInflater)
        setContentView(binding.root)
        CastButtonFactory.setUpMediaRouteButton(this, binding.castButton)
        binding.btnBack.setOnClickListener { finish() }
        binding.btnPlayPause.setOnClickListener { vm.audioEngine.togglePlayPause() }
        binding.btnNext.setOnClickListener { vm.audioEngine.next() }
        binding.btnPrev.setOnClickListener { vm.audioEngine.previous() }
        binding.btnShuffle.setOnClickListener { vm.audioEngine.toggleShuffle() }
        binding.btnRepeat.setOnClickListener { vm.audioEngine.cycleRepeatMode() }
        binding.btnLike.setOnClickListener {
            vm.audioEngine.currentSong.value?.let { vm.toggleLike(it) }
        }
        binding.btnLyrics.setOnClickListener {
            startActivity(Intent(this, LyricsActivity::class.java))
        }
        binding.btnEqualizer.setOnClickListener {
            startActivity(Intent(this, EqualizerActivity::class.java))
        }

        // Visualizador + esquinas de carátula (ajustes de Apariencia/Reproducción)
        val theme = ThemeManager.getInstance(this)
        binding.visualizer.bind(this, vm.audioEngine, theme)
        binding.visualizer.visibility =
            if (theme.isVisualizerEnabled) View.VISIBLE else View.GONE
        applyArtworkCorners()
        Logger.info("playback", "NowPlaying abierta")
        binding.seekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(s: SeekBar?, p: Int, u: Boolean) {}
            override fun onStartTrackingTouch(s: SeekBar?) { scrubbing = true }
            override fun onStopTrackingTouch(s: SeekBar?) {
                scrubbing = false
                val dur = vm.audioEngine.duration.value ?: 0L
                vm.audioEngine.seekTo(((s?.progress ?: 0) / 1000f * dur).toLong())
            }
        })
        observe()
    }

    override fun onResume() {
        super.onResume()
        // Re-aplicar por si el usuario cambió el radio en Ajustes
        applyArtworkCorners()
        val theme = ThemeManager.getInstance(this)
        binding.visualizer.visibility =
            if (theme.isVisualizerEnabled) View.VISIBLE else View.GONE
    }

    /** Recorta la carátula con el radio ajustable (0..44pt). */
    private fun applyArtworkCorners() {
        val theme = ThemeManager.getInstance(this)
        val radius = theme.artworkCornerDp * resources.displayMetrics.density
        binding.artwork.clipToOutline = true
        binding.artwork.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, radius)
            }
        }
        binding.artwork.invalidateOutline()
    }

    private fun observe() {
        vm.audioEngine.currentSong.observe(this) { song ->
            binding.songTitle.text = song?.title ?: ""
            binding.songArtist.text = song?.preferredArtist ?: ""
            if (song?.artworkUri != null) binding.artwork.load(song.artworkUri)
            else binding.artwork.setImageResource(R.drawable.ic_music_note)
            binding.btnLike.setImageResource(
                if (song?.isLiked == true) R.drawable.ic_favorite else R.drawable.ic_favorite_border)
            // ✅ "Letras por defecto": abrir la pantalla de letras automáticamente
            val theme = ThemeManager.getInstance(this)
            if (song != null && theme.isLyricsByDefaultEnabled && !openedLyricsOnce) {
                openedLyricsOnce = true
                startActivity(Intent(this, LyricsActivity::class.java))
            }
        }
        vm.audioEngine.isPlaying.observe(this) { playing ->
            // Botón morado: el icono siempre blanco (ic_*_accent), en claro y oscuro.
            binding.btnPlayPause.setImageResource(
                if (playing == true) R.drawable.ic_pause_accent else R.drawable.ic_play_accent)
        }
        vm.audioEngine.currentTime.observe(this) { pos ->
            if (!scrubbing) {
                val dur = vm.audioEngine.duration.value ?: 0L
                binding.seekBar.progress = if (dur > 0) (pos * 1000L / dur).toInt() else 0
            }
            binding.timeCurrent.text = formatMs(pos)
        }
        vm.audioEngine.duration.observe(this) { dur ->
            binding.timeTotal.text = formatMs(dur)
        }
        vm.audioEngine.isShuffleEnabled.observe(this) { enabled ->
            binding.btnShuffle.alpha = if (enabled == true) 1f else 0.4f
        }
        vm.audioEngine.repeatMode.observe(this) { mode ->
            binding.btnRepeat.setImageResource(
                when (mode) {
                    RepeatMode.ONE -> R.drawable.ic_repeat_one
                    else -> R.drawable.ic_repeat
                }
            )
            binding.btnRepeat.alpha = if (mode == RepeatMode.OFF) 0.4f else 1f
        }
    }

    private fun formatMs(ms: Long): String {
        if (ms <= 0) return "0:00"
        val totalSec = ms / 1000
        val m = totalSec / 60
        val s = totalSec % 60
        return String.format("%d:%02d", m, s)
    }
}

