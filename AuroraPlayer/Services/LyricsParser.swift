import Foundation

// MARK: - Enhanced Lyrics Parser with automatic type detection
class LyricsParser {

    // MARK: - Parse lyrics from string with intelligent detection
    static func parse(_ lyrics: String) -> LyricsType {
        let trimmedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedLyrics.isEmpty else {
            return .none
        }

        // ✅ DIAGNÓSTICO - VER FORMATO REAL: loggear los primeros 200 caracteres
        // para ver qué formato real tienen las letras de los archivos de audio
        let preview = String(trimmedLyrics.prefix(200))
        AppLog.info(.playback, "🔍 LYRICS RAW (primeros 200 chars): \(preview)")

        // ✅ DETECCIÓN MEJORADA: Priorizar formatos word-by-word
        if hasWordByWordFormat(trimmedLyrics) {
            let result = parseWordByWord(trimmedLyrics)
            if result.isWordByWord {
                AppLog.info(.playback, "Lyrics: formato word-by-word detectado")
                return .synchronized(result)
            }
        }

        if hasLRCTimestamps(trimmedLyrics) {
            let result = parseLRC(trimmedLyrics)
            if result.isWordByWord {
                AppLog.info(.playback, "Lyrics: formato LRC word-by-word detectado")
            } else {
                AppLog.info(.playback, "Lyrics: formato LRC línea por línea detectado")
            }
            return .synchronized(result)
        }

        if hasEnhancedLineFormat(trimmedLyrics) {
            AppLog.info(.playback, "Lyrics: formato línea mejorado detectado")
            return .synchronized(parseEnhancedLines(trimmedLyrics))
        }

        // ✅ DETECCIÓN TTML: verificar si tiene formato <span begin/end>
        if hasTTMLFormat(trimmedLyrics) {
            AppLog.info(.playback, "Lyrics: formato TTML Apple Music detectado")
            // TODO: Implementar parser TTML si se confirma este formato
            return .plain(trimmedLyrics)
        }

        AppLog.info(.playback, "Lyrics: formato plano detectado")
        return .plain(trimmedLyrics)
    }

    // MARK: - Detection helpers

    private static func hasLRCTimestamps(_ text: String) -> Bool {
        let pattern = "\\[\\d{1,2}:\\d{2}(\\.\\d{1,3})?\\]"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        // ✅ CRÍTICO - FIX LYRICS: reducido de >2 a >1 para detectar formatos con pocas líneas
        // Muchas canciones tienen letras sincronizadas con solo 1-2 líneas, y el umbral
        // anterior de >2 causaba que se detectaran como "no lyrics"
        return (regex?.numberOfMatches(in: text, options: [], range: range) ?? 0) > 1
    }

    private static func hasWordByWordFormat(_ text: String) -> Bool {
        // ✅ DETECCIÓN MEJORADA: múltiples formatos word-by-word
        // Formato Apple Music: timestamps entre palabras
        let pattern1 = "<\\d{1,2}:\\d{2}(\\.\\d{1,3})?>"
        let regex1 = try? NSRegularExpression(pattern: pattern1, options: [])
        let range1 = NSRange(location: 0, length: text.utf16.count)
        // ✅ CRÍTICO - FIX LYRICS: reducido de >5 a >3 para detectar más formatos
        if (regex1?.numberOfMatches(in: text, options: [], range: range1) ?? 0) > 3 {
            return true
        }

        // Formato alternativo: timestamps entre palabras sin <>
        let pattern2 = "\\[\\d{1,2}:\\d{2}(\\.\\d{1,3})?\\]"
        let regex2 = try? NSRegularExpression(pattern: pattern2, options: [])
        let range2 = NSRange(location: 0, length: text.utf16.count)
        let lineCount = text.components(separatedBy: .newlines).count
        let matchCount = regex2?.numberOfMatches(in: text, options: [], range: range2) ?? 0
        // ✅ CRÍTICO - FIX LYRICS: reducido de *2 a *1.5 para detectar más formatos
        if matchCount > Int(Double(lineCount) * 1.5) {
            return true
        }

        return false
    }

    private static func hasEnhancedLineFormat(_ text: String) -> Bool {
        let pattern = "^\\d{1,2}:\\d{2}(\\.\\d{1,3})?\\s+"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let range = NSRange(location: 0, length: text.utf16.count)
        return (regex?.numberOfMatches(in: text, options: [], range: range) ?? 0) > 2
    }

    // ✅ DETECCIÓN TTML: formato Apple Music con <span begin="X" end="Y">
    private static func hasTTMLFormat(_ text: String) -> Bool {
        // Buscar patrón <span begin="..." end="...">
        let pattern = "<span\\s+begin=\"[^\"]+\"\\s+end=\"[^\"]+\""
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        return (regex?.numberOfMatches(in: text, options: [], range: range) ?? 0) > 1
    }

    // MARK: - Parse LRC (line-by-line and word-by-word)

    private static func parseLRC(_ text: String) -> SynchronizedLyrics {
        let lines = text.components(separatedBy: .newlines)
        var lyricLines: [LyricLine] = []
        var lyricWords: [LyricWord] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let timestamps = extractTimestamps(from: trimmedLine)
            let textContent = stripTimestamps(from: trimmedLine)

            guard !timestamps.isEmpty, !textContent.isEmpty else { continue }

            // Word-by-word: multiple timestamps con palabras individuales
            // ✅ MEJORA: separación más robusta de palabras
            let words = textContent.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if timestamps.count > 1 && timestamps.count == words.count {
                for (index, timestamp) in timestamps.enumerated() {
                    if index < words.count {
                        let word = cleanText(words[index])
                        if !word.isEmpty {
                            let duration: TimeInterval? = index < timestamps.count - 1 ? timestamps[index + 1] - timestamp : nil
                            lyricWords.append(LyricWord(time: timestamp, text: word, duration: duration))
                        }
                    }
                }
            } else {
                lyricLines.append(LyricLine(time: timestamps[0], text: cleanText(textContent)))
            }
        }

        if lyricLines.count > 1 {
            let needsSorting = zip(lyricLines, lyricLines.dropFirst()).contains { $0.time > $1.time }
            if needsSorting { lyricLines.sort { $0.time < $1.time } }
        }

        if lyricWords.count > 1 {
            let needsSorting = zip(lyricWords, lyricWords.dropFirst()).contains { $0.time > $1.time }
            if needsSorting { lyricWords.sort { $0.time < $1.time } }
        }

        return SynchronizedLyrics(lines: lyricLines, words: lyricWords, isWordByWord: !lyricWords.isEmpty && lyricWords.count > lyricLines.count)
    }

    // MARK: - Parse word-by-word format (<mm:ss.xx>word)

    private static func parseWordByWord(_ text: String) -> SynchronizedLyrics {
        // ✅ MEJORA: Soportar formato híbrido con timestamps de línea [mm:ss.xx]
        // y timestamps de palabra <mm:ss.xx>word dentro de cada línea
        var lyricWords: [LyricWord] = []
        var lyricLines: [LyricLine] = []
        
        // Patrón para timestamps de línea: [mm:ss.xx]
        let lineTimestampPattern = "\\[(\\d{1,2}):(\\d{2})(\\.(\\d{1,3}))?\\]"
        // Patrón para timestamps de palabra: <mm:ss.xx>word
        let wordTimestampPattern = "<(\\d{1,2}):(\\d{2})(\\.(\\d{1,3}))?>([^<]+)"
        
        // Dividir el texto en líneas separadas por timestamps de línea
        let lines = text.components(separatedBy: "\n")
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            
            // Extraer timestamp de línea si existe
            var lineTime: TimeInterval = 0
            if let lineTimestamp = extractFirstTimestamp(from: trimmedLine, pattern: lineTimestampPattern) {
                lineTime = lineTimestamp
            }
            
            // Extraer todas las palabras con sus timestamps
            var tempWords: [(time: Double, text: String)] = []
            
            if let wordRegex = try? NSRegularExpression(pattern: wordTimestampPattern, options: []) {
                let range = NSRange(location: 0, length: trimmedLine.utf16.count)
                let matches = wordRegex.matches(in: trimmedLine, options: [], range: range)
                
                for match in matches {
                    guard let minutesRange = Range(match.range(at: 1), in: trimmedLine),
                          let secondsRange = Range(match.range(at: 2), in: trimmedLine),
                          let textRange = Range(match.range(at: 5), in: trimmedLine) else { continue }
                    
                    let minutes = Double(trimmedLine[minutesRange]) ?? 0
                    let seconds = Double(trimmedLine[secondsRange]) ?? 0
                    let wordText = cleanText(String(trimmedLine[textRange]))
                    
                    var milliseconds: Double = 0
                    if match.range(at: 4).location != NSNotFound, let msRange = Range(match.range(at: 4), in: trimmedLine) {
                        milliseconds = Double("0." + String(trimmedLine[msRange])) ?? 0
                    }
                    
                    let timestamp = minutes * 60 + seconds + milliseconds
                    if !wordText.isEmpty {
                        tempWords.append((time: timestamp, text: wordText))
                    }
                }
            }
            
            // Si hay palabras con timestamps, crear LyricWord objects
            if !tempWords.isEmpty {
                for (index, word) in tempWords.enumerated() {
                    let duration: TimeInterval? = index < tempWords.count - 1 ? tempWords[index + 1].time - word.time : nil
                    lyricWords.append(LyricWord(time: word.time, text: word.text, duration: duration))
                }
                
                // Crear línea completa con todas las palabras
                let lineText = tempWords.map { $0.text }.joined(separator: " ")
                lyricLines.append(LyricLine(time: lineTime > 0 ? lineTime : tempWords.first?.time ?? 0, text: lineText))
            } else {
                // Si no hay palabras word-by-word, tratar como línea normal
                let textContent = stripTimestamps(from: trimmedLine)
                if !textContent.isEmpty {
                    lyricLines.append(LyricLine(time: lineTime, text: cleanText(textContent)))
                }
            }
        }

        if lyricWords.count > 1 {
            let needsSorting = zip(lyricWords, lyricWords.dropFirst()).contains { $0.time > $1.time }
            if needsSorting { lyricWords.sort { $0.time < $1.time } }
        }
        
        if lyricLines.count > 1 {
            let needsSorting = zip(lyricLines, lyricLines.dropFirst()).contains { $0.time > $1.time }
            if needsSorting { lyricLines.sort { $0.time < $1.time } }
        }

        return SynchronizedLyrics(lines: lyricLines, words: lyricWords, isWordByWord: !lyricWords.isEmpty && lyricWords.count > lyricLines.count)
    }
    
    // ✅ HELPER: Extraer primer timestamp de una línea
    private static func extractFirstTimestamp(from text: String, pattern: String) -> TimeInterval? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        
        guard let minutesRange = Range(match.range(at: 1), in: text),
              let secondsRange = Range(match.range(at: 2), in: text) else { return nil }
        
        let minutes = Double(text[minutesRange]) ?? 0
        let seconds = Double(text[secondsRange]) ?? 0
        
        var milliseconds: Double = 0
        if match.range(at: 4).location != NSNotFound, let msRange = Range(match.range(at: 4), in: text) {
            milliseconds = Double("0." + String(text[msRange])) ?? 0
        }
        
        return minutes * 60 + seconds + milliseconds
    }

    // MARK: - Parse enhanced line format (mm:ss.xx text)

    private static func parseEnhancedLines(_ text: String) -> SynchronizedLyrics {
        var lyricLines: [LyricLine] = []
        let pattern = "^(\\d{1,2}):(\\d{2})(\\.(\\d{1,3}))?\\s+(.+)$"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return SynchronizedLyrics()
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let range = NSRange(location: 0, length: trimmedLine.utf16.count)
            guard let match = regex.firstMatch(in: trimmedLine, options: [], range: range) else { continue }

            guard let minutesRange = Range(match.range(at: 1), in: trimmedLine),
                  let secondsRange = Range(match.range(at: 2), in: trimmedLine),
                  let textRange = Range(match.range(at: 5), in: trimmedLine) else { continue }

            let minutes = Double(trimmedLine[minutesRange]) ?? 0
            let seconds = Double(trimmedLine[secondsRange]) ?? 0
            let lineText = cleanText(String(trimmedLine[textRange]))

            var milliseconds: Double = 0
            if match.range(at: 4).location != NSNotFound, let msRange = Range(match.range(at: 4), in: trimmedLine) {
                milliseconds = Double("0." + String(trimmedLine[msRange])) ?? 0
            }

            let timestamp = minutes * 60 + seconds + milliseconds
            if !lineText.isEmpty {
                lyricLines.append(LyricLine(time: timestamp, text: lineText))
            }
        }

        if lyricLines.count > 1 {
            let needsSorting = zip(lyricLines, lyricLines.dropFirst()).contains { $0.time > $1.time }
            if needsSorting { lyricLines.sort { $0.time < $1.time } }
        }

        return SynchronizedLyrics(lines: lyricLines, words: [], isWordByWord: false)
    }

    // MARK: - Timestamp extraction and stripping

    private static func extractTimestamps(from line: String) -> [TimeInterval] {
        var timestamps: [TimeInterval] = []
        let pattern = "\\[(\\d{1,2}):(\\d{2})(\\.(\\d{1,3}))?\\]"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return timestamps }
        let range = NSRange(location: 0, length: line.utf16.count)

        for match in regex.matches(in: line, options: [], range: range) {
            guard let minutesRange = Range(match.range(at: 1), in: line),
                  let secondsRange = Range(match.range(at: 2), in: line) else { continue }

            let minutes = Double(line[minutesRange]) ?? 0
            let seconds = Double(line[secondsRange]) ?? 0
            var milliseconds: Double = 0

            if match.range(at: 4).location != NSNotFound, let msRange = Range(match.range(at: 4), in: line) {
                milliseconds = Double("0." + String(line[msRange])) ?? 0
            }

            timestamps.append(minutes * 60 + seconds + milliseconds)
        }

        return timestamps
    }

    /// Elimina TODOS los patrones de timestamp de un texto
    private static func stripTimestamps(from text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "\\[\\d{1,2}:\\d{2}(\\.\\d{1,3})?\\]", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<\\d{1,2}:\\d{2}(\\.\\d{1,3})?>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<.*?>", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Limpieza final de texto: elimina brackets, timestamps residuales y puntuación suelta
    private static func cleanText(_ text: String) -> String {
        var cleaned = text
        // Eliminar cualquier bracket residual
        cleaned = cleaned.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "<.*?>", with: "", options: .regularExpression)
        // Eliminar timestamps sueltos
        cleaned = cleaned.replacingOccurrences(of: "\\d{1,2}:\\d{2}(\\.\\d{1,3})?", with: "", options: .regularExpression)
        // Limpiar puntuación suelta al inicio
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") || cleaned.hasPrefix(",") || cleaned.hasPrefix("-") || cleaned.hasPrefix("—") {
            cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return cleaned
    }

    // MARK: - Query helpers

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