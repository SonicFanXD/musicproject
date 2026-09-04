import Foundation

// MARK: - Lyric Line (para lyrics sincronizadas por línea)
struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval // tiempo en segundos
    let text: String
    
    init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
    
    static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Lyric Word (para lyrics word-by-word)
struct LyricWord: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval // tiempo en segundos
    let text: String
    let duration: TimeInterval? // duración opcional de la palabra
    
    init(time: TimeInterval, text: String, duration: TimeInterval? = nil) {
        self.time = time
        self.text = text
        self.duration = duration
    }
    
    static func == (lhs: LyricWord, rhs: LyricWord) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Synchronized Lyrics (contiene ambos tipos)
struct SynchronizedLyrics: Equatable {
    let lines: [LyricLine]
    let words: [LyricWord]
    let isWordByWord: Bool
    
    var isEmpty: Bool {
        lines.isEmpty && words.isEmpty
    }
    
    init(lines: [LyricLine] = [], words: [LyricWord] = [], isWordByWord: Bool = false) {
        self.lines = lines
        self.words = words
        self.isWordByWord = isWordByWord
    }
    
    static func == (lhs: SynchronizedLyrics, rhs: SynchronizedLyrics) -> Bool {
        lhs.lines.count == rhs.lines.count &&
        lhs.words.count == rhs.words.count &&
        lhs.isWordByWord == rhs.isWordByWord
    }
}

// MARK: - Lyrics Type (para diferenciar tipos)
enum LyricsType {
    case none
    case plain(String) // lyrics normales sin sincronización
    case synchronized(SynchronizedLyrics) // lyrics sincronizadas
}