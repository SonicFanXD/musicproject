import Foundation

// MARK: - Enhanced Lyrics Parser with automatic type detection
class LyricsParser {

    // MARK: - Parse lyrics from string with intelligent detection
    static func parse(_ lyrics: String) -> LyricsType {
        let trimmedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedLyrics.isEmpty else {
            return .none
        }

        // Enhanced detection for different lyric types
        if hasLRCTimestamps(trimmedLyrics) {
            let synchronized = parseLRC(trimmedLyrics)
            return .synchronized(synchronized)
        }

        // Detect enhanced synchronized format (word-by-word)
        if hasWordByWordFormat(trimmedLyrics) {
            let synchronized = parseWordByWord(trimmedLyrics)
            return .synchronized(synchronized)
        }

        // Detect enhanced line-by-line format
        if hasEnhancedLineFormat(trimmedLyrics) {
            let synchronized = parseEnhancedLines(trimmedLyrics)
            return .synchronized(synchronized)
        }

        // Plain lyrics
        return .plain(trimmedLyrics)
    }

    // MARK: - Detect LRC timestamps [mm:ss.xx]
    private static func hasLRCTimestamps(_ text: String) -> Bool {
        let pattern = "\\[\\d{1,2}:\\d{2}(\\.\\d{1,3})?\\]"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = regex?.numberOfMatches(in: text, options: [], range: range) ?? 0
        return matches > 2 // Need at least a few lines to consider it LRC
    }

    // MARK: - Detect word-by-word format (<mm:ss.xx>word)
    private static func hasWordByWordFormat(_ text: String) -> Bool {
        let pattern = "<\\d{1,2}:\\d{2}(\\.\\d{1,3})?>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = regex?.numberOfMatches(in: text, options: [], range: range) ?? 0
        return matches > 5 // Need multiple word timestamps
    }

    // MARK: - Detect enhanced line format (mm:ss.xx text)
    private static func hasEnhancedLineFormat(_ text: String) -> Bool {
        let pattern = "^\\d{1,2}:\\d{2}(\\.\\d{1,3})?\\s+"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = regex?.numberOfMatches(in: text, options: [], range: range) ?? 0
        return matches > 2
    }

    // MARK: - Parse LRC format (both line and word-by-word) - PRESERVING ORIGINAL TIMESTAMPS
    private static func parseLRC(_ text: String) -> SynchronizedLyrics {
        let lines = text.components(separatedBy: .newlines)
        var lyricLines: [LyricLine] = []
        var lyricWords: [LyricWord] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let timestamps = extractLRCTimestamps(from: trimmedLine)
            let textContent = extractLRCTextContent(from: trimmedLine)

            guard !timestamps.isEmpty, !textContent.isEmpty else { continue }

            // PRESERVACIÓN CRÍTICA: Usar exactamente los timestamps originales
            // Detect word-by-word: multiple timestamps with single word matches
            if timestamps.count > 1 && timestamps.count <= textContent.components(separatedBy: " ").count + 2 {
                let words = textContent.components(separatedBy: " ")
                for (index, timestamp) in timestamps.enumerated() {
                    if index < words.count {
                        let word = words[index].trimmingCharacters(in: .punctuationCharacters)
                        if !word.isEmpty {
                            // Calcular duración basándonos en timestamps originales exactos
                            let duration: TimeInterval?
                            if index < timestamps.count - 1 {
                                duration = timestamps[index + 1] - timestamp
                            } else {
                                duration = nil
                            }
                            // PRESERVAR timestamp exacto original
                            lyricWords.append(LyricWord(time: timestamp, text: word, duration: duration))
                        }
                    }
                }
            } else {
                // Line-by-line synchronized - PRESERVAR timestamp exacto original
                lyricLines.append(LyricLine(time: timestamps[0], text: textContent))
            }
        }

        // PRESERVACIÓN: No modificar el orden original si ya está cronológico
        // Solo ordenar si parece desordenado
        if lyricLines.count > 1 {
            let needsSorting = zip(lyricLines, lyricLines.dropFirst()).contains { $0.time > $1.time }
            if needsSorting {
                lyricLines.sort { $0.time < $1.time }
            }
        }

        if lyricWords.count > 1 {
            let needsSorting = zip(lyricWords, lyricWords.dropFirst()).contains { $0.time > $1.time }
            if needsSorting {
                lyricWords.sort { $0.time < $1.time }
            }
        }

        let isWordByWord = !lyricWords.isEmpty && lyricWords.count > lyricLines.count

        return SynchronizedLyrics(lines: lyricLines, words: lyricWords, isWordByWord: isWordByWord)
    }

    // MARK: - Parse word-by-word format (<mm:ss.xx>word) - PRESERVING ORIGINAL TIMESTAMPS
    private static func parseWordByWord(_ text: String) -> SynchronizedLyrics {
        var lyricWords: [LyricWord] = []
        let pattern = "<(\\d{1,2}):(\\d{2})(\\.(\\d{1,3}))?>([^<]+)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return SynchronizedLyrics()
        }

        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches {
            if let minutesRange = Range(match.range(at: 1), in: text),
               let secondsRange = Range(match.range(at: 2), in: text),
               let textRange = Range(match.range(at: 5), in: text) {

                let minutes = Double(text[minutesRange]) ?? 0
                let seconds = Double(text[secondsRange]) ?? 0
                let wordText = String(text[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                var milliseconds: Double = 0
                if match.range(at: 4).location != NSNotFound,
                   let msRange = Range(match.range(at: 4), in: text) {
                    let msString = String(text[msRange])
                    milliseconds = Double("0." + msString) ?? 0
                }

                // PRESERVAR timestamp exacto original con precisión milisegundo
                let timestamp = minutes * 60 + seconds + milliseconds
                if !wordText.isEmpty {
                    lyricWords.append(LyricWord(time: timestamp, text: wordText, duration: nil))
                }
            }
        }

        // PRESERVACIÓN: Solo ordenar si los timestamps parecen desordenados
        if lyricWords.count > 1 {
            let needsSorting = zip(lyricWords, lyricWords.dropFirst()).contains { $0.time > $1.time }
            if needsSorting {
                lyricWords.sort { $0.time < $1.time }
            }
        }

        // Generate lines from words (group words that belong to same line)
        // PRESERVAR timestamps originales en la agrupación
        var lyricLines: [LyricLine] = []
        var currentLineWords: [LyricWord] = []
        var lastTime: TimeInterval = 0

        for word in lyricWords {
            if word.time - lastTime > 2.0 { // New line after 2 seconds gap
                if !currentLineWords.isEmpty {
                    let lineText = currentLineWords.map { $0.text }.joined(separator: " ")
                    // PRESERVAR timestamp del primer palabra original
                    lyricLines.append(LyricLine(time: currentLineWords.first?.time ?? 0, text: lineText))
                }
                currentLineWords = []
            }
            currentLineWords.append(word)
            lastTime = word.time
        }

        if !currentLineWords.isEmpty {
            let lineText = currentLineWords.map { $0.text }.joined(separator: " ")
            lyricLines.append(LyricLine(time: currentLineWords.first?.time ?? 0, text: lineText))
        }

        // PRESERVACIÓN: No reordenar líneas ya generadas con timestamps originales
        if lyricLines.count > 1 {
            let needsSorting = zip(lyricLines, lyricLines.dropFirst()).contains { $0.time > $1.time }
            if needsSorting {
                lyricLines.sort { $0.time < $1.time }
            }
        }

        return SynchronizedLyrics(lines: lyricLines, words: lyricWords, isWordByWord: true)
    }

    // MARK: - Parse enhanced line format (mm:ss.xx text) - PRESERVING ORIGINAL TIMESTAMPS
    private static func parseEnhancedLines(_ text: String) -> SynchronizedLyrics {
        let lines = text.components(separatedBy: .newlines)
        var lyricLines: [LyricLine] = []

        let pattern = "^(\\d{1,2}):(\\d{2})(\\.(\\d{1,3}))?\\s+(.+)$"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return SynchronizedLyrics()
        }

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let range = NSRange(location: 0, length: trimmedLine.utf16.count)
            guard let match = regex.firstMatch(in: trimmedLine, options: [], range: range) else { continue }

            if let minutesRange = Range(match.range(at: 1), in: trimmedLine),
               let secondsRange = Range(match.range(at: 2), in: trimmedLine),
               let textRange = Range(match.range(at: 5), in: trimmedLine) {

                let minutes = Double(trimmedLine[minutesRange]) ?? 0
                let seconds = Double(trimmedLine[secondsRange]) ?? 0
                let lineText = String(trimmedLine[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                var milliseconds: Double = 0
                if match.range(at: 4).location != NSNotFound,
                   let msRange = Range(match.range(at: 4), in: trimmedLine) {
                    let msString = String(trimmedLine[msRange])
                    milliseconds = Double("0." + msString) ?? 0
                }

                // PRESERVAR timestamp exacto original con precisión milisegundo
                let timestamp = minutes * 60 + seconds + milliseconds
                if !lineText.isEmpty {
                    lyricLines.append(LyricLine(time: timestamp, text: lineText))
                }
            }
        }

        // PRESERVACIÓN: Solo ordenar si los timestamps parecen desordenados
        if lyricLines.count > 1 {
            let needsSorting = zip(lyricLines, lyricLines.dropFirst()).contains { $0.time > $1.time }
            if needsSorting {
                lyricLines.sort { $0.time < $1.time }
            }
        }

        return SynchronizedLyrics(lines: lyricLines, words: [], isWordByWord: false)
    }

    // MARK: - Extract LRC timestamps from line
    private static func extractLRCTimestamps(from line: String) -> [TimeInterval] {
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

    // MARK: - Extract LRC text content (without timestamps)
    private static func extractLRCTextContent(from line: String) -> String {
        let pattern = "\\[\\d{1,2}:\\d{2}(\\.\\d{1,3})?\\]"
        let result = line.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Get current line based on time
    static func getCurrentLine(from lyrics: SynchronizedLyrics, at time: TimeInterval) -> LyricLine? {
        guard !lyrics.lines.isEmpty else { return nil }

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

    // MARK: - Get current words based on time
    static func getCurrentWords(from lyrics: SynchronizedLyrics, at time: TimeInterval) -> [LyricWord] {
        guard !lyrics.words.isEmpty else { return [] }

        var activeWords: [LyricWord] = []

        for word in lyrics.words {
            if word.time <= time {
                if let duration = word.duration {
                    if time <= word.time + duration {
                        activeWords.append(word)
                    }
                } else {
                    if let nextWordIndex = lyrics.words.firstIndex(where: { $0.id == word.id }),
                       nextWordIndex < lyrics.words.count - 1 {
                        let nextWord = lyrics.words[nextWordIndex + 1]
                        if time < nextWord.time {
                            activeWords.append(word)
                        }
                    } else {
                        activeWords.append(word)
                    }
                }
            }
        }

        return activeWords
    }

    // MARK: - Get current line index for scrolling
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