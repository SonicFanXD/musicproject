import Foundation

class LyricsParser {

    // MARK: - Parse lyrics from string
    static func parse(_ lyrics: String) -> LyricsType {
        let trimmedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedLyrics.isEmpty else {
            return .none
        }

        if let ttml = TTMLParser.parse(trimmedLyrics) {
            return .synchronized(ttml)
        }

        let lines = LRCParser.parse(trimmedLyrics)
        
        guard !lines.isEmpty else {
            return .plain(trimmedLyrics)
        }
        
        let syncLyrics = SynchronizedLyrics(
            lines: lines.map { line in
                LyricLine(
                    time: TimeInterval(line.startMs) / 1000.0,
                    text: line.cleanText
                )
            },
            words: [],
            isWordByWord: false
        )
        
        return .synchronized(syncLyrics)
    }
    
}
