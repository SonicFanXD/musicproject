import SwiftUI

struct LyricsView: View {
    let song: Song?
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss
    
    @State private var parsedLyrics: LyricsType = .none
    @State private var currentLineIndex: Int? = nil
    @State private var scrollTarget: Int? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                
                switch parsedLyrics {
                case .none:
                    emptyLyricsView
                case .plain(let text):
                    plainLyricsView(text: text)
                case .synchronized(let syncLyrics):
                    if syncLyrics.isWordByWord {
                        wordByWordLyricsView(lyrics: syncLyrics)
                    } else {
                        synchronizedLyricsView(lyrics: syncLyrics)
                    }
                }
            }
            .navigationTitle("Letras")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }
            .onAppear {
                parseLyrics()
            }
            .onChange(of: audioEngine.currentTime) { newTime in
                updateCurrentLine(for: newTime)
            }
        }
    }
    
    // MARK: - Empty Lyrics View
    private var emptyLyricsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 45))
                .foregroundStyle(.tertiary)
            
            Text("No hay letras disponibles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Text("Esta canción no tiene información de letras en su metadata.")
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
    
    // MARK: - Plain Lyrics View
    private func plainLyricsView(text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 18))
                .foregroundStyle(.primary)
                .lineSpacing(12)
                .padding(24)
        }
    }
    
    // MARK: - Synchronized Lyrics View (por línea)
    private func synchronizedLyricsView(lyrics: SynchronizedLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        lyricLineView(line: line, isActive: currentLineIndex == index)
                            .id(index)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .onChange(of: scrollTarget) { target in
                if let target = target {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }
    
    // MARK: - Word by Word Lyrics View
    private func wordByWordLyricsView(lyrics: SynchronizedLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        let wordsInLine = lyrics.words.filter { word in
                            word.time >= line.time && 
                            (index < lyrics.lines.count - 1 ? word.time < lyrics.lines[index + 1].time : true)
                        }
                        
                        wordByWordLineView(line: line, words: wordsInLine, isActive: currentLineIndex == index)
                            .id(index)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .onChange(of: scrollTarget) { target in
                if let target = target {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }
    
    // MARK: - Lyric Line View (Optimized for performance)
    private func lyricLineView(line: LyricLine, isActive: Bool) -> some View {
        Text(line.text)
            .font(.system(size: isActive ? 22 : 18, weight: isActive ? .bold : .regular))
            .foregroundStyle(isActive ? .primary : .secondary)
            .opacity(isActive ? 1.0 : 0.5)
            .scaleEffect(isActive ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.25), value: isActive) // Optimized animation
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .drawingGroup() // Optimizes rendering performance
    }
    
    // MARK: - Word by Word Line View (Optimized for performance)
    private func wordByWordLineView(line: LyricLine, words: [LyricWord], isActive: Bool) -> some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                let isWordActive = isWordActive(word, at: audioEngine.currentTime)
                
                Text(word.text)
                    .font(.system(size: isActive ? 20 : 17, weight: isWordActive ? .bold : .regular))
                    .foregroundStyle(isWordActive ? .primary : (isActive ? .secondary : .tertiary))
                    .opacity(isActive ? (isWordActive ? 1.0 : 0.6) : 0.4)
                    .scaleEffect(isWordActive ? 1.08 : 1.0) // Reduced scale for better performance
                    .animation(.easeOut(duration: 0.15), value: isWordActive) // Faster animation
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
    
    // MARK: - Check if word is active
    private func isWordActive(_ word: LyricWord, at time: TimeInterval) -> Bool {
        let wordStartTime = word.time
        let wordEndTime: TimeInterval
        
        if let duration = word.duration {
            wordEndTime = wordStartTime + duration
        } else {
            // Estimar duración basada en longitud de la palabra
            wordEndTime = wordStartTime + Double(word.text.count) * 0.15
        }
        
        return time >= wordStartTime && time < wordEndTime
    }
    
    // MARK: - Parse Lyrics
    private func parseLyrics() {
        guard let lyrics = song?.lyrics, !lyrics.isEmpty else {
            parsedLyrics = .none
            return
        }
        
        parsedLyrics = LyricsParser.parse(lyrics)
    }
    
    // MARK: - Update Current Line (Optimized for performance)
    private func updateCurrentLine(for time: TimeInterval) {
        switch parsedLyrics {
        case .synchronized(let syncLyrics):
            if let newIndex = LyricsParser.getCurrentLineIndex(from: syncLyrics, at: time) {
                // Only update if significantly different to reduce animations
                if currentLineIndex != newIndex {
                    currentLineIndex = newIndex
                    scrollTarget = newIndex
                }
            }
        default:
            break
        }
    }
}