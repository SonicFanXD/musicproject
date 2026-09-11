package com.aurora.player.models

/**
 * Modelo de datos para las letras sincronizadas (LRC format).
 * Equivalente a LyricsModels.swift en iOS.
 */

/**
 * Una línea individual de letra con timestamp
 */
data class LyricLine(
    val timestamp: Long, // en milisegundos
    val text: String,
    val endTime: Long = 0 // cuándo termina esta línea (para resaltado)
) {
    /**
     * Formatea el timestamp en formato mm:ss.ms
     */
    fun formattedTimestamp(): String {
        val totalSeconds = timestamp / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        val milliseconds = (timestamp % 1000) / 10
        return String.format("%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}

/**
 * Letras completas de una canción
 */
data class Lyrics(
    val songId: String,
    val lines: List<LyricLine>,
    val isSynced: Boolean = true,
    val source: String = ""
) {
    /**
     * Retorna la línea activa para un tiempo dado
     */
    fun activeLineAt(timeMs: Long): LyricLine? {
        return lines.lastOrNull { it.timestamp <= timeMs }
    }

    /**
     * Retorna el índice de la línea activa para un tiempo dado
     */
    fun activeLineIndexAt(timeMs: Long): Int {
        return lines.indexOfLast { it.timestamp <= timeMs }
    }

    /**
     * Retorna el texto completo sin timestamps
     */
    val plainText: String
        get() = lines.joinToString("\n") { it.text }

    /**
     * Duración total de las letras
     */
    val duration: Long
        get() = lines.maxOfOrNull { it.endTime } ?: lines.maxOfOrNull { it.timestamp } ?: 0
}

/**
 * Parser para archivos LRC
 */
object LyricsParser {
    /**
     * Parsea un string en formato LRC
     * Formato: [mm:ss.ms]Texto de la línea
     */
    fun parse(lrcContent: String, songId: String): Lyrics {
        val lines = mutableListOf<LyricLine>()
        val timeRegex = Regex("\\[(\\d{2}):(\\d{2})\\.(\\d{2,3})\\](.*)")

        lrcContent.lines().forEach { line ->
            val match = timeRegex.find(line.trim())
            if (match != null) {
                val minutes = match.groupValues[1].toLongOrNull() ?: 0
                val seconds = match.groupValues[2].toLongOrNull() ?: 0
                val milliseconds = match.groupValues[3].toLongOrNull() ?: 0
                val text = match.groupValues[4].trim()

                val timestamp = (minutes * 60 + seconds) * 1000 + milliseconds * 10
                lines.add(LyricLine(timestamp = timestamp, text = text))
            }
        }

        // Ordenar por timestamp
        val sortedLines = lines.sortedBy { it.timestamp }

        // Calcular endTime para cada línea
        val linesWithEndTime = sortedLines.mapIndexed { index, line ->
            val endTime = if (index < sortedLines.size - 1) {
                sortedLines[index + 1].timestamp
            } else {
                line.timestamp + 5000 // 5 segundos para la última línea
            }
            line.copy(endTime = endTime)
        }

        return Lyrics(
            songId = songId,
            lines = linesWithEndTime,
            isSynced = true
        )
    }

    /**
     * Parsea letras sin sincronización (solo texto)
     */
    fun parsePlainText(text: String, songId: String): Lyrics {
        val lines = text.lines()
            .filter { it.isNotBlank() }
            .mapIndexed { index, line ->
                LyricLine(
                    timestamp = index * 5000L, // 5 segundos por línea como default
                    text = line.trim()
                )
            }

        return Lyrics(
            songId = songId,
            lines = lines,
            isSynced = false
        )
    }
}