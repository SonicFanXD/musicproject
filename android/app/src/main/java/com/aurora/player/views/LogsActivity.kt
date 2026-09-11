package com.aurora.player.views

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.aurora.player.databinding.ActivityLogsBinding
import com.aurora.player.services.Logger

/**
 * Visor de registros en memoria. Equivalente a LogsView.swift en iOS.
 */
class LogsActivity : AppCompatActivity() {
    private lateinit var binding: ActivityLogsBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityLogsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.btnBack.setOnClickListener { finish() }
        binding.logsText.text = Logger.dump().ifBlank { "—" }
        binding.btnClear.setOnClickListener {
            Logger.clear()
            binding.logsText.text = "—"
            Toast.makeText(this, R.string.logs_clear, Toast.LENGTH_SHORT).show()
        }
    }
}
