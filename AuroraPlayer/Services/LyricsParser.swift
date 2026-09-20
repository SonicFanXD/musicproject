import Foundation

// MARK: - Simplified Lyrics Parser (line-by-line only)
// ✅ Eliminado sistema word-by-word por bugs y complejidad
// ✅ Ahora usa LRCParser optimizado para formato híbrido y clásico
class LyricsParser {

    // MARK: - Parse lyrics from string
    static func parse(_ lyrics: String) -> LyricsType {
        let trimmedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedLyrics.isEmpty else {
            return .none
        }

        // ✅ Usar nuevo LRCParser para formato híbrido y clásico
        let lines = LRCParser.parse(trimmedLyrics)
        
        guard !lines.isEmpty else {
            return .plain(trimmedLyrics)
        }
        
        // ✅ Convertir a SynchronizedLyrics para compatibilidad con modelo existente
        let syncLyrics = SynchronizedLyrics(
            lines: lines.map { line in
                LyricLine(
                    id: UUID(),
                    text: line.cleanText,
                    time: TimeInterval(line.startMs) / 1000.0,
                    duration: TimeInterval(line.endMs - line.startMs) / 1000.0
                )
            },
            words: [], // ✅ Eliminado word-by-word
            isWordByWord: false // ✅ Ahora siempre line-by-line
        )
        
        return .synchronized(syncLyrics)
    }
    
    // MARK: - Cleanup (funciones obsoletas eliminadas)
    // Eliminado: parseWordByWord, parseLRC, hasWordByWordFormat, etc.
    // Todo el procesamiento word-by-word fue eliminado por bugs y complejidad
}
