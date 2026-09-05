import Foundation

// MARK: - Enhanced Lyrics Parser with automatic type detection
class LyricsParser {

    // MARK: - Parse lyrics from string with intelligent detection
    static func parse(_ lyrics: String) -> LyricsType {
        let trimmedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedLyrics.isEmpty else {
            return .none
        }

        if hasLRCTimestamps(trimmedLyrics) {
            return .synchronized(parseLRC(trimmedLyrics))
        }

        if hasWordByWordFormat(trimmedLyrics) {
            return .synchronized(parseWordByWord(trimmedLyrics))
        }

        if hasEnhancedLineFormat(trimmedLyrics) {
            return .synchronized(parseEnhancedLines(trimmedLyrics))
        }

        return .plain(trimmedLyrics)
    }

    // MARK: - Detection helpers

    private static func hasLRCTimestamps(_ text: String) -> Bool {
        let pattern = "\\[\\d{1,2}:\\d{2}(\\.\\d{1,3})?\\]"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        return (regex?.numberOfMatches(in: text, options: [], range: range) ?? 0) > 2
    }

    private static func hasWordByWordFormat(_ text: String) -> Bool {
        let pattern = "<\\d{1,2}:\\d{2}(\\.\\d{1,3})?>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        return (regex?.numberOfMatches(in: text, options: [], range: range) ?? 0) > 5
    }

    private static func hasEnhancedLineFormat(_ text: String) -> Bool {
        let pattern = "^\\d{1,2}:\\d{2}(\\.\\d{1,3})?\\s+"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let range = NSRange(location: 0, length: text.utf16.count)
        return (regex?.numberOfMatches(in: text, options: [], range: range) ?? 0) > 2
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

            // Word-by-word: multiple timestamps with single words
            if timestamps.count > 1 && timestamps.count <= textContent.components(separatedBy: " ").count + 2 {
                let words = textContent.components(separatedBy: " ")
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
        var lyricWords: [LyricWord] = []
        let pattern = "<(\\d{1,2}):(\\d{2})(\\.(\\d{1,3}))?>([^<]+)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return SynchronizedLyrics()
        }

        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = regex.matches(in: text, options: [], range: range)

        var tempWords: [(time: Double, text: String)] = []

        for match in matches {
            guard let minutesRange = Range(match.range(at: 1), in: text),
                  let secondsRange = Range(match.range(at: 2), in: text),
                  let textRange = Range(match.range(at: 5), in: text) else { continue }

            let minutes = Double(text[minutesRange]) ?? 0
            let seconds = Double(text[secondsRange]) ?? 0
            let wordText = cleanText(String(text[textRange]))

            var milliseconds: Double = 0
            if match.range(at: 4).location != NSNotFound, let msRange = Range(match.range(at: 4), in: text) {
                milliseconds = Double("0." + String(text[msRange])) ?? 0
            }

            let timestamp = minutes * 60 + seconds + milliseconds
            if !wordText.isEmpty {
                tempWords.append((time: timestamp, text: wordText))
            }
        }

        // Calculate duration for each word based on next word's timestamp
        for (index, word) in tempWords.enumerated() {
            let duration: TimeInterval? = index < tempWords.count - 1 ? tempWords[index + 1].time - word.time : nil
            lyricWords.append(LyricWord(time: word.time, text: word.text, duration: duration))
        }

        if lyricWords.count > 1 {
            let needsSorting = zip(lyricWords, lyricWords.dropFirst()).contains { $0.time > $1.time }
            if needsSorting { lyricWords.sort { $0.time < $1.time } }
        }

        // Generate lines from words
        var lyricLines: [LyricLine] = []
        var currentLineWords: [LyricWord] = []
        var lastTime: TimeInterval = 0

        for word in lyricWords {
            if word.time - lastTime > 2.0 {
                if !currentLineWords.isEmpty {
                    lyricLines.append(LyricLine(time: currentLineWords.first?.time ?? 0, text: currentLineWords.map { $0.text }.joined(separator: " ")))
                }
                currentLineWords = []
            }
            currentLineWords.append(word)
            lastTime = word.time
        }

        if !currentLineWords.isEmpty {
            lyricLines.append(LyricLine(time: currentLineWords.first?.time ?? 0, text: currentLineWords.map { $0.text }.joined(separator: " ")))
        }

        return SynchronizedLyrics(lines: lyricLines, words: lyricWords, isWordByWord: true)
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