package com.aurora.player.views

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import androidx.lifecycle.LifecycleOwner
import com.aurora.player.services.AudioEngine
import com.aurora.player.services.ThemeManager

/**
 * Visualizador de barras animadas. Equivalente a AudioVisualizer.swift en iOS.
 * Las barras pulsan mientras suena la música (animación dirigida por el estado
 * de reproducción; no necesita permisos de micrófono).
 */
class AudioVisualizerView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    private var isPlaying = false
    private var accentColor = 0xFFAF52DE.toInt()
    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val barCount = 24
    private var frame = 0L
    private val amplitudes = FloatArray(barCount)

    fun setPlaying(playing: Boolean) {
        isPlaying = playing
        if (playing) postInvalidateOnAnimation()
    }

    fun setAccent(color: Int) {
        accentColor = color
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        barPaint.color = accentColor
        val w = width.toFloat()
        val h = height.toFloat()
        val slot = w / barCount
        val barWidth = slot * 0.55f
        for (i in 0 until barCount) {
            val phase = frame * 0.09f + i * 0.55f
            val base = if (isPlaying) {
                val wave = (Math.sin(phase.toDouble()) * 0.5 + 0.5).toFloat()
                val pulse = (Math.sin(frame * 0.021 + i * 0.7).toFloat() * 0.5f + 0.5f)
                wave * (0.25f + pulse * 0.75f)
            } else {
                (Math.sin(phase.toDouble()) * 0.5 + 0.5).toFloat() * 0.10f + 0.05f
            }
            amplitudes[i] += (base - amplitudes[i]) * 0.25f
            val barHeight = (h * 0.12f) + amplitudes[i] * h * 0.82f
            val left = i * slot + (slot - barWidth) / 2f
            canvas.drawRoundRect(
                left, h - barHeight, left + barWidth, h,
                barWidth / 2f, barWidth / 2f, barPaint
            )
        }
        if (isPlaying) {
            frame++
            postInvalidateOnAnimation()
        }
    }

    /** Suscribe el visualizador al acento dinámico y al estado de reproducción. */
    fun bind(owner: LifecycleOwner, engine: AudioEngine, theme: ThemeManager) {
        setAccent(theme.getCurrentAccentColor())
        theme.accentColor.observe(owner) { setAccent(it ?: accentColor) }
        engine.isPlaying.observe(owner) { setPlaying(it == true) }
    }
}
