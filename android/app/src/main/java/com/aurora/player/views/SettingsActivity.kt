package com.aurora.player.views

import android.content.Intent
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import androidx.activity.viewModels
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.aurora.player.R
import com.aurora.player.databinding.ActivitySettingsBinding
import com.aurora.player.services.AudioEngine
import com.aurora.player.services.Localization
import com.aurora.player.services.ThemeManager
import com.aurora.player.viewmodels.LibraryViewModel

class SettingsActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySettingsBinding
    private val vm: LibraryViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        val engine: AudioEngine = vm.audioEngine
        val theme = ThemeManager.getInstance(this)

        binding.rowEqualizer.setOnClickListener {
            startActivity(Intent(this, EqualizerActivity::class.java))
        }

        binding.switchMonoAudio.isChecked = engine.isMonoAudioEnabled.value == true
        binding.switchMonoAudio.setOnCheckedChangeListener { _, _ ->
            engine.toggleMonoAudio()
        }

        binding.switchArtworkAccent.isChecked = theme.accentFromArtwork
        binding.switchArtworkAccent.setOnCheckedChangeListener { _, checked ->
            theme.accentFromArtwork = checked
        }

        binding.switchKeepScreenOn.setOnCheckedChangeListener { _, checked ->
            if (checked) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }

        engine.audioQualityInfo.observe(this) { info ->
            binding.rowAudioOutput.text = "${getString(R.string.settings_audio_output)}: $info"
        }
        engine.refreshOutputQualityPublic()
        binding.rowDevice.text = "${getString(R.string.settings_device)}: ${Build.MODEL}"

        setupAccentPicker(theme)
        setupThemePicker(theme)
        setupLanguagePicker(theme)
        setupReduceTransparency(theme)
        setupArtworkCorners(theme)
        setupPlaybackToggles(theme)
        setupStats()
        localizeTexts()

        binding.rowLogs.setOnClickListener {
            startActivity(Intent(this, LogsActivity::class.java))
        }
        binding.rowAbout.setOnClickListener { showAbout() }
    }

    private fun showAbout() {
        val pm = packageManager.getPackageInfo(packageName, 0)
        @Suppress("DEPRECATION") val code = pm.versionCode
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.app_name))
            .setMessage("${getString(R.string.about_version)}: v${pm.versionName} ($code)")
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    private fun setupLanguagePicker(theme: ThemeManager) {
        val picker = binding.languagePicker
        val labels = listOf(
            getString(R.string.language_spanish),
            getString(R.string.language_english)
        )
        val loc = Localization.getInstance(this)
        val current = if (loc.current == Localization.Language.ENGLISH) 1 else 0
        labels.forEachIndexed { index, label ->
            val chip = layoutInflater.inflate(R.layout.chip_preset, picker, false)
            val chipText = chip.findViewById<android.widget.TextView>(R.id.chipText)
            val isSelected = index == current
            chip.background = resources.getDrawable(
                if (isSelected) R.drawable.play_button_background else R.drawable.control_button_background,
                theme)
            chipText.text = label
            chipText.setTextColor(
                if (isSelected) getColor(R.color.icon_on_accent) else getColor(R.color.control_icon))
            chip.setOnClickListener {
                loc.setLanguage(
                    if (index == 1) Localization.Language.ENGLISH else Localization.Language.SPANISH)
                recreate()
            }
            picker.addView(chip)
        }
    }

    private fun setupReduceTransparency(theme: ThemeManager) {
        binding.switchReduceTransparency.isChecked = theme.isReduceTransparencyEnabled
        binding.switchReduceTransparency.setOnCheckedChangeListener { _, checked ->
            theme.setReduceTransparency(checked)
            recreate()
        }
        if (theme.isReduceTransparencyEnabled) {
            swapGlassBackgrounds(binding.root as android.view.ViewGroup, theme,
                theme.cardBackgroundRes())
        }
    }

    /** Cambia el fondo de las tarjetas (cristal → opaco) si el ajuste está activo. */
    private fun swapGlassBackgrounds(
        group: android.view.ViewGroup, theme: ThemeManager, res: Int
    ) {
        val glass = resources.getDrawable(R.drawable.glass_background, theme).constantState
        for (i in 0 until group.childCount) {
            val child = group.getChildAt(i)
            if (child.background != null && child.background.constantState == glass) {
                child.background = resources.getDrawable(res, theme)
            }
            if (child is android.view.ViewGroup) swapGlassBackgrounds(child, theme, res)
        }
    }

    private fun setupThemePicker(theme: ThemeManager) {
        val picker = binding.themePicker
        val labels = listOf(
            getString(R.string.settings_theme_system),
            getString(R.string.settings_theme_light),
            getString(R.string.settings_theme_dark)
        )
        val current = theme.themeMode.value ?: 0
        labels.forEachIndexed { index, label ->
            val chip = layoutInflater.inflate(R.layout.chip_preset, picker, false)
            val chipText = chip.findViewById<android.widget.TextView>(R.id.chipText)
            val isSelected = index == current
            chip.background = resources.getDrawable(
                if (isSelected) R.drawable.play_button_background else R.drawable.control_button_background,
                theme)
            chipText.text = label
            chipText.setTextColor(
                if (isSelected) getColor(R.color.icon_on_accent) else getColor(R.color.control_icon))
            chip.setOnClickListener {
                theme.setThemeMode(index)
                picker.removeAllViews()
                setupThemePicker(theme)
            }
            picker.addView(chip)
        }
    }

    private fun setupArtworkCorners(theme: ThemeManager) {
        val initial = (theme.artworkCornerDp / 2f).toInt()
        binding.sliderArtworkCorners.progress = initial
        binding.labelArtworkCornersValue.text = "${initial * 2}pt"
        binding.sliderArtworkCorners.setOnSeekBarChangeListener(
            object : android.widget.SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: android.widget.SeekBar?, p: Int, fromUser: Boolean) {
                    theme.artworkCornerDp = p * 2f
                    binding.labelArtworkCornersValue.text = "${p * 2}pt"
                }
                override fun onStartTrackingTouch(s: android.widget.SeekBar?) {}
                override fun onStopTrackingTouch(s: android.widget.SeekBar?) {}
            })
    }

    private fun setupPlaybackToggles(theme: ThemeManager) {
        binding.switchVisualizer.isChecked = theme.isVisualizerEnabled
        binding.switchVisualizer.setOnCheckedChangeListener { _, checked ->
            theme.setVisualizerEnabled(checked)
        }
        binding.switchLyricsDefault.isChecked = theme.isLyricsByDefaultEnabled
        binding.switchLyricsDefault.setOnCheckedChangeListener { _, checked ->
            theme.setLyricsByDefaultEnabled(checked)
        }
    }

    /** Textos de secciones/filas localizados vía Localization (Español/English). */
    private fun localizeTexts() {
        val loc = Localization.getInstance(this)
        binding.sectionAudio.text = loc.get("settings.audio")
        binding.sectionAppearance.text = loc.get("settings.appearance")
        binding.sectionPlayback.text = loc.get("settings.playback")
        binding.sectionPerformance.text = loc.get("settings.performance")
        binding.sectionCustomization.text = loc.get("settings.customization")
        binding.sectionStats.text = loc.get("settings.stats")
        binding.sectionAdvanced.text = loc.get("settings.advanced")
        binding.rowEqualizer.text = loc.get("settings.equalizer")
        binding.switchMonoAudio.text = loc.get("settings.monoAudio")
        binding.switchArtworkAccent.text = loc.get("settings.accentFromArtwork")
        binding.labelTheme.text = loc.get("settings.theme")
        binding.switchReduceTransparency.text = loc.get("settings.reduceTransparency")
        binding.labelArtworkCorners.text = loc.get("settings.artworkCorners")
        binding.labelLanguage.text = loc.get("settings.language")
        binding.switchVisualizer.text = loc.get("settings.visualizer")
        binding.switchLyricsDefault.text = loc.get("settings.lyricsDefault")
        binding.rowLogs.text = loc.get("settings.logs")
        binding.rowAbout.text = loc.get("settings.about")
        binding.rowDevice.text = "${loc.get("settings.device")}: ${Build.MODEL}"
    }

    private fun setupAccentPicker(theme: ThemeManager) {
        val picker = binding.accentPicker
        ThemeManager.ACCENT_COLORS.forEachIndexed { index, color ->
            val dot = View(this)
            dot.layoutParams = LinearLayout.LayoutParams(44, 44)
            dot.setOnClickListener {
                theme.setAccentIndex(index)
                refreshAccentDots(theme)
            }
            picker.addView(dot)
        }
        refreshAccentDots(theme)
    }

    private fun refreshAccentDots(theme: ThemeManager) {
        val current = theme.accentIndex.value ?: 0
        val picker = binding.accentPicker
        for (i in 0 until picker.childCount) {
            val child = picker.getChildAt(i)
            val color = ThemeManager.ACCENT_COLORS[i]
            // Círculo del color; borde grueso blanco en la opción activa
            val d = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(color)
                if (i == current) {
                    setStroke(3, 0xFFFFFFFF.toInt())
                } else {
                    setStroke(2, 0x33FFFFFF)
                }
            }
            child.background = d
            child.elevation = if (i == current) 10f else 0f
        }
    }

    private fun setupStats() {
        vm.songs.observe(this) { songs ->
            binding.rowStatSongs.text = "${getString(R.string.library_songs)}: ${songs.size}"
        }
        vm.albums.observe(this) { albums ->
            binding.rowStatAlbums.text = "${getString(R.string.library_albums)}: ${albums.size}"
        }
        vm.artists.observe(this) { artists ->
            binding.rowStatArtists.text = "${getString(R.string.library_artists)}: ${artists.size}"
        }
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }
}