package com.aurora.player.views

import android.os.Bundle
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import com.aurora.player.R
import com.aurora.player.databinding.ActivityEqualizerBinding
import com.aurora.player.models.EQPreset
import com.aurora.player.viewmodels.LibraryViewModel

class EqualizerActivity : AppCompatActivity() {
    private lateinit var binding: ActivityEqualizerBinding
    private val vm: LibraryViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityEqualizerBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.btnBack.setOnClickListener { finish() }
        binding.switchEQ.isChecked = vm.audioEngine.isEQEnabled.value == true
        binding.switchEQ.setOnCheckedChangeListener { _, _ -> vm.audioEngine.toggleEQ() }
        buildPresets()
        bindEqTitle()
    }

    private fun buildPresets() {
        val container = binding.presetRow
        // Limpiar hijos previos si los hubiera
        while (container.childCount > 0) {
            container.removeView(container.getChildAt(0))
        }
        val isEnabled = vm.audioEngine.isEQEnabled.value == true
        val selected = vm.audioEngine.eqPreset.value
        EQPreset.entries.forEach { preset ->
            val chip = layoutInflater.inflate(R.layout.chip_preset, container, false)
            val label = chip.findViewById<android.widget.TextView>(R.id.chipText)
            val isSelected = isEnabled && selected == preset
            val bg = if (isSelected) R.drawable.play_button_background else R.drawable.control_button_background
            chip.background = resources.getDrawable(bg, theme)
            label.text = preset.displayName
            label.setTextColor(
                if (isSelected) getColor(R.color.icon_on_accent)
                else getColor(R.color.control_icon)
            )
            chip.setOnClickListener { vm.audioEngine.setEQPreset(preset) }
            container.addView(chip)
        }
    }

    private fun bindEqTitle() {
        vm.audioEngine.isEQEnabled.observe(this) { updateEqTitle() }
        vm.audioEngine.eqPreset.observe(this) { updateEqTitle() }
        updateEqTitle()
    }

    private fun updateEqTitle() {
        val enabled = vm.audioEngine.isEQEnabled.value == true
        val preset = vm.audioEngine.eqPreset.value
        binding.eqTitle.text = if (enabled)
            "${getString(R.string.equalizer_active)} (${preset?.displayName})"
        else getString(R.string.equalizer_disabled)
        binding.switchEQ.isChecked = enabled
        buildPresets()
    }
}