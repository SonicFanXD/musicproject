import Foundation

/// Traduce SynchronizedLyrics (segundos, sin lineIndex/wordIndex reales) al
/// LyricsToken de LyricsModels.swift (ms, con índices reales). Se ejecuta
/// UNA vez al cargar la letra — nunca en el hot path de render.
///
/// ✅ Reemplaza a la conversión que vivía dentro de la clase privada
/// LyricsEngine de LyricsView.swift, que tenía un bug real: lineIndex se
/// declaraba en 0 y nunca se incrementaba, así que TODAS las palabras de la
/// canción caían en la "línea 0" — tokensByLine terminaba con una sola
/// entrada conteniendo el tema completo.
enum LyricsTokenBuilder {

    private static let defaultDurationMs = 500 // mismo valor que usaba el código anterior

    static func makeTokens(from lyrics: SynchronizedLyrics) -> (tokens: [LyricsToken], lines: [LyricsVisualLine]) {
        guard !lyrics.words.isEmpty else { return ([], []) }

        let sortedLines = lyrics.lines // ya vienen ordenadas por LyricsParser
        let words = lyrics.words

        var tokens: [LyricsToken] = []
        tokens.reserveCapacity(words.count)

        var lineCursor = 0
        var wordIndexInLine = 0

        for (wordPos, word) in words.enumerated() {
            // ✅ Este es el fix del bug: se avanza lineCursor de verdad cuando
            // la SIGUIENTE línea del parser ya empezó, en vez de dejarlo fijo.
            while lineCursor + 1 < sortedLines.count && word.time >= sortedLines[lineCursor + 1].time {
                lineCursor += 1
                wordIndexInLine = 0
            }

            let startMs = Int((word.time * 1000).rounded())
            let endMs: Int
            if let duration = word.duration, duration > 0 {
                endMs = startMs + Int((duration * 1000).rounded())
            } else if wordPos + 1 < words.count {
                endMs = Int((words[wordPos + 1].time * 1000).rounded())
            } else {
                endMs = startMs + defaultDurationMs
            }

            tokens.append(LyricsToken(
                id: word.id.uuidString,   // mismo esquema de id que usaba el código anterior
                text: word.text,
                startMs: startMs,
                endMs: max(endMs, startMs + 1),
                lineIndex: lineCursor,
                wordIndex: wordIndexInLine
            ))
            wordIndexInLine += 1
        }

        // Agrupar tokens contiguos por lineIndex en una sola pasada.
        var lines: [LyricsVisualLine] = []
        var groupStart = 0
        for i in 1...tokens.count {
            let isBoundary = i == tokens.count || tokens[i].lineIndex != tokens[groupStart].lineIndex
            guard isBoundary else { continue }
            let group = tokens[groupStart..<i]
            let lineIdx = tokens[groupStart].lineIndex
            lines.append(LyricsVisualLine(
                id: "l\(lineIdx)",
                lineIndex: lineIdx,
                startMs: group.first!.startMs,
                endMs: group.last!.endMs,
                tokenIDs: group.map { $0.id }
            ))
            groupStart = i
        }

        return (tokens, lines)
    }
}