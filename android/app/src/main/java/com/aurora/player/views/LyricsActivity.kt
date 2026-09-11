package com.aurora.player.views

import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import com.aurora.player.R
import com.aurora.player.databinding.ActivityLyricsBinding
import com.aurora.player.models.Lyrics
import com.aurora.player.models.LyricsParser
import com.aurora.player.models.Song
import com.aurora.player.viewmodels.LibraryViewModel

/**
 * Letras sincronizadas. Equivalente a LyricsView.swift en iOS:
 * resalta la línea activa según el tiempo de reproducción y hace
 * scroll automático hasta ella.
 *
 * Fuente de letras en Android: archivo .lrc junto al audio
 * (mismo nombre que la canción), parseado con LyricsParser.
 */
class LyricsActivity : AppCompatActivity() {
    private lateinit var binding: ActivityLyricsBinding
    private val vm: LibraryViewModel by viewModels()
    private var lyrics: Lyrics? = null
    private val lineViews = mutableListOf<TextView>()
    private var lastActiveIndex = -1

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityLyricsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.btnBack.setOnClickListener { finish() }
        observe()
    }

    private fun observe() {
        vm.audioEngine.currentSong.observe(this) { song ->
            binding.songTitle.text = song?.title ?: getString(R.string.lyrics_title)
            binding.songArtist.text = song?.artist ?: ""
            loadLyrics(song)
        }
        vm.audioEngine.currentTime.observe(this) { pos -> highlight(pos) }
    }

    private fun loadLyrics(song: Song?) {
        binding.lyricsContainer.removeAllViews()
        lineViews.clear()
        lyrics = null
        lastActiveIndex = -1
        if (song == null) { showEmpty(); return }
        Thread {
            val text = try {
                vm.fileAccess.findLyricsFile(song)?.readText()
            } catch (e: Exception) { null }
            runOnUiThread {
                if (isFinishing) return@runOnUiThread
                if (text.isNullOrBlank()) { showEmpty(); return@runOnUiThread }
                val parsed = LyricsParser.parse(text, song.id)
                if (parsed.lines.isEmpty()) { showEmpty(); return@runOnUiThread }
                lyrics = parsed
                binding.emptyView.visibility = View.GONE
                binding.lyricsScroll.visibility = View.VISIBLE
                parsed.lines.forEach { line ->
                    val tv = TextView(this).apply {
                        text = line.text.ifBlank { "·" }
                        textSize = 22f
                        gravity = Gravity.CENTER
                        setTextColor(getColor(R.color.lyrics_inactive))
                        setLineSpacing(0f, 1.4f)
                        setPadding(0, 14, 0, 14)
                    }
                    binding.lyricsContainer.addView(tv)
                    lineViews.add(tv)
                }
                highlight(vm.audioEngine.currentTime.value ?: 0L)
            }
        }.start()
    }

    private fun highlight(posMs: Long) {
        val l = lyrics ?: return
        val idx = l.activeLineIndexAt(posMs)
        if (idx == lastActiveIndex) return
        lastActiveIndex = idx
        val active = getColor(R.color.lyrics_active)
        val inactive = getColor(R.color.lyrics_inactive)
        lineViews.forEachIndexed { i, tv ->
            val isActive = i == idx
            tv.setTextColor(if (isActive) active else inactive)
            tv.setTypeface(null, if (isActive) Typeface.BOLD else Typeface.NORMAL)
            tv.alpha = if (isActive) 1f else 0.6f
        }
        if (idx in lineViews.indices) {
            val target = lineViews[idx]
            binding.lyricsScroll.post {
                binding.lyricsScroll.smoothScrollTo(
                    0, target.top - binding.lyricsScroll.height / 3)
            }
        }
    }

    private fun showEmpty() {
        binding.lyricsScroll.visibility = View.GONE
        binding.emptyView.visibility = View.VISIBLE
    }
}
