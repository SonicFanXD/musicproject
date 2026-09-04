import Foundation

// MARK: - Lyrics Parser
class LyricsParser {
    
    // MARK: - Parse lyrics from string
    static func parse(_ lyrics: String) -> LyricsType {
        let trimmedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedLyrics.isEmpty else {
            return .none
        }
        
        // Detectar si tiene formato LRC (timestamps)
        if hasLRCTimestamps(trimmedLyrics) {
            let synchronized = parseLRC(trimmedLyrics)
            return .synchronized(synchronized)
        }
        
        // Lyrics normales
        return .plain(trimmedLyrics)
    }
    
    // MARK: - Detectar si tiene timestamps LRC
    private static func hasLRCTimestamps(_ text: String) -> Bool {
        // Patrón regex para timestamps LRC: [mm:ss.xx] o [mm:ss]
        let pattern = "\\[\\d{1,2}:\\d{2}(\\.\\d{1,3})?\\]"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        
        let matches = regex?.numberOfMatches(in: text, options: [], range: range) ?? 0
        return matches > 0
    }
    
    // MARK: - Parse LRC format
    private static func parseLRC(_ text: String) -> SynchronizedLyrics {
        let lines = text.components(separatedBy: .newlines)
        var lyricLines: [LyricLine] = []
        var lyricWords: [LyricWord] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            
            // Extraer timestamps y texto
            let timestamps = extractTimestamps(from: trimmedLine)
            let textContent = extractTextContent(from: trimmedLine)
            
            guard !timestamps.isEmpty, !textContent.isEmpty else { continue }
            
            // Detectar si es word-by-word (múltiples timestamps en una línea)
            if timestamps.count > 1 {
                // Es word-by-word
                let words = textContent.components(separatedBy: " ")
                for (index, timestamp) in timestamps.enumerated() {
                    if index < words.count {
                        let word = words[index].trimmingCharacters(in: .punctuationCharacters)
                        if !word.isEmpty {
                            // Calcular duración si es posible
                            let duration: TimeInterval?
                            if index < timestamps.count - 1 {
                                duration = timestamps[index + 1] - timestamp
                            } else {
                                duration = nil
                            }
                            lyricWords.append(LyricWord(time: timestamp, text: word, duration: duration))
                        }
                    }
                }
            } else {
                // Es línea normal
                lyricLines.append(LyricLine(time: timestamps[0], text: textContent))
            }
        }
        
        // Ordenar por tiempo
        lyricLines.sort { $0.time < $1.time }
        lyricWords.sort { $0.time < $1.time }
        
        let isWordByWord = !lyricWords.isEmpty && lyricWords.count > lyricLines.count
        
        return SynchronizedLyrics(lines: lyricLines, words: lyricWords, isWordByWord: isWordByWord)
    }
    
    // MARK: - Extraer timestamps de una línea
    private static func extractTimestamps(from line: String) -> [TimeInterval] {
        var timestamps: [TimeInterval] = []
        let pattern = "\\[(\\d{1,2}):(\\d{2})(\\.(\\d{1,3}))?\\]"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return timestamps
        }
        
        let range = NSRange(location: 0, length: line.utf16.count)
        let matches = regex.matches(in: line, options: [], range: range)
        
        for match in matches {
            if let minutesRange = Range(match.range(at: 1), in: line),
               let secondsRange = Range(match.range(at: 2), in: line) {
                let minutes = Double(line[minutesRange]) ?? 0
                let seconds = Double(line[secondsRange]) ?? 0
                
                var milliseconds: Double = 0
                if match.range(at: 4).location != NSNotFound,
                   let msRange = Range(match.range(at: 4), in: line) {
                    let msString = String(line[msRange])
                    milliseconds = Double("0." + msString) ?? 0
                }
                
                let totalSeconds = minutes * 60 + seconds + milliseconds
                timestamps.append(totalSeconds)
            }
        }
        
        return timestamps
    }
    
    // MARK: - Extraer contenido de texto (sin timestamps)
    private static func extractTextContent(from line: String) -> String {
        // Remover todos los timestamps
        let pattern = "\\[\\d{1,2}:\\d{2}(\\.\\d{1,3})?\\]"
        let result = line.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Obtener línea actual basada en tiempo
    static func getCurrentLine(from lyrics: SynchronizedLyrics, at time: TimeInterval) -> LyricLine? {
        guard !lyrics.lines.isEmpty else { return nil }
        
        // Encontrar la última línea cuyo tiempo sea <= al tiempo actual
        var currentLine: LyricLine?
        for line in lyrics.lines {
            if line.time <= time {
                currentLine = line
            } else {
                break
            }
        }
        
        return currentLine
    }
    
    // MARK: - Obtener palabras actuales basadas en tiempo
    static func getCurrentWords(from lyrics: SynchronizedLyrics, at time: TimeInterval) -> [LyricWord] {
        guard !lyrics.words.isEmpty else { return [] }
        
        // Encontrar todas las palabras que deberían estar activas
        var activeWords: [LyricWord] = []
        
        for word in lyrics.words {
            if word.time <= time {
                // Verificar si la palabra todavía debería estar visible
                if let duration = word.duration {
                    if time <= word.time + duration {
                        activeWords.append(word)
                    }
                } else {
                    // Sin duración específica, usar la siguiente palabra como referencia
                    if let nextWordIndex = lyrics.words.firstIndex(where: { $0.id == word.id }),
                       nextWordIndex < lyrics.words.count - 1 {
                        let nextWord = lyrics.words[nextWordIndex + 1]
                        if time < nextWord.time {
                            activeWords.append(word)
                        }
                    } else {
                        // Última palabra
                        activeWords.append(word)
                    }
                }
            }
        }
        
        return activeWords
    }
    
    // MARK: - Obtener índice de línea actual para scroll
    static func getCurrentLineIndex(from lyrics: SynchronizedLyrics, at time: TimeInterval) -> Int? {
        guard !lyrics.lines.isEmpty else { return nil }
        
        for (index, line) in lyrics.lines.enumerated() {
            if line.time > time {
                return index > 0 ? index - 1 : 0
            }
        }
        
        return lyrics.lines.count - 1
    }
}