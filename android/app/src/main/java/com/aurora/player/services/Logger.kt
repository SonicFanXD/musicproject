package com.aurora.player.services

import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale

/**
 * Logger en memoria con buffer circular. Equivalente a Logger.swift en iOS
 * (se muestra en la pantalla de Registros/Logs de Ajustes).
 */
object Logger {
    private const val MAX = 400
    private val entries = ArrayDeque<String>()
    private val fmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    @Synchronized fun info(tag: String, msg: String) = add("INFO", tag, msg)
    @Synchronized fun warn(tag: String, msg: String) = add("WARN", tag, msg)
    @Synchronized fun error(tag: String, msg: String) = add("ERROR", tag, msg)

    private fun add(level: String, tag: String, msg: String) {
        entries.addLast("${fmt.format(Date())}  $level/$tag: $msg")
        if (entries.size > MAX) entries.removeFirst()
    }

    @Synchronized fun dump(): String = entries.joinToString("\n")

    @Synchronized fun clear() = entries.clear()
}
