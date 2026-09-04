import SwiftUI

struct LyricsView: View {
    let song: Song?
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var parsedLyrics: LyricsType = .none
    @State private var currentLineIndex: Int? = nil
    @State private var scrollTarget: Int? = nil
    @State private var activeWordIds: Set<UUID> = []
    @State private var currentWordProgress: [UUID: Double] = [:]
    @State private var animationTimer: Timer?
    @State private var showKaraokeMode: Bool = false
    @State private var readingCursor: TimeInterval = 0
    
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
                ToolbarItem(placement: .topBarLeading) {
                    if case .synchronized(let syncLyrics) = parsedLyrics, syncLyrics.isWordByWord {
                        Button {
                            showKaraokeMode.toggle()
                        } label: {
                            Image(systemName: showKaraokeMode ? "sparkles" : "textformat")
                                .foregroundStyle(showKaraokeMode ? Color.accentColor : .secondary)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }
            .onAppear {
                parseLyrics()
                startAnimationTimer()
            }
            .onDisappear {
                stopAnimationTimer()
            }
            .onChange(of: audioEngine.currentTime) { newTime in
                updateCurrentLine(for: newTime)
                updateActiveWords(for: newTime)
            }
        }
    }

    // MARK: - Animation Timer
    private func startAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            updateWordProgress()
            updateReadingCursor()
        }
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func updateWordProgress() {
        guard case .synchronized(let syncLyrics) = parsedLyrics,
              syncLyrics.isWordByWord else { return }

        let currentTime = audioEngine.currentTime

        // Actualizar progreso de cada palabra activa
        for word in syncLyrics.words {
            if let duration = word.duration {
                let progress = min(1.0, max(0.0, (currentTime - word.time) / duration))
                if progress > 0 && progress < 1 {
                    currentWordProgress[word.id] = progress
                } else {
                    currentWordProgress.removeValue(forKey: word.id)
                }
            }
        }
    }

    private func updateReadingCursor() {
        guard case .synchronized(let syncLyrics) = parsedLyrics,
              syncLyrics.isWordByWord,
              showKaraokeMode else { return }

        let currentTime = audioEngine.currentTime
        readingCursor = currentTime
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
        AnimatedLineView(
            text: line.text,
            isActive: isActive
        )
    }
}

// MARK: - Animated Line View (Beautiful synchronized line animations)
struct AnimatedLineView: View {
    let text: String
    let isActive: Bool

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.5
    @State private var yOffset: CGFloat = 0.0
    @State private var glowIntensity: Double = 0.0

    var body: some View {
        Text(text)
            .font(.system(size: isActive ? 24 : 20, weight: isActive ? .bold : .regular))
            .foregroundStyle(isActive ? .primary : .secondary)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(y: yOffset)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(glowIntensity * 0.2))
                    .blur(radius: 12)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isActive)
            .onAppear {
                updateAnimationState()
            }
            .onChange(of: isActive) { _ in
                updateAnimationState()
            }
    }

    private func updateAnimationState() {
        if isActive {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                scale = 1.08
                opacity = 1.0
                yOffset = -2.0
                glowIntensity = 1.0
            }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                scale = 1.0
                opacity = 0.5
                yOffset = 0.0
                glowIntensity = 0.0
            }
        }
    }
    
    // MARK: - Word by Word Line View (Optimized for performance)
    private func wordByWordLineView(line: LyricLine, words: [LyricWord], isActive: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                let isWordActive = isWordActive(word, at: audioEngine.currentTime)
                let wordProgress = currentWordProgress[word.id] ?? 0.0

                AnimatedWordView(
                    word: word.text,
                    isActive: isWordActive,
                    isLineActive: isActive,
                    progress: wordProgress
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
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

    // MARK: - Update Active Words
    private func updateActiveWords(for time: TimeInterval) {
        guard case .synchronized(let syncLyrics) = parsedLyrics,
              syncLyrics.isWordByWord else { return }

        var newActiveWordIds: Set<UUID> = []

        for word in syncLyrics.words {
            if isWordActive(word, at: time) {
                newActiveWordIds.insert(word.id)
            }
        }

        activeWordIds = newActiveWordIds
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

// MARK: - Animated Word View (Beautiful word-by-word animations)
struct AnimatedWordView: View {
    let word: String
    let isActive: Bool
    let isLineActive: Bool
    let progress: Double

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.5
    @State private var glowIntensity: Double = 0.0

    var body: some View {
        Text(word)
            .font(.system(size: isLineActive ? 22 : 18, weight: isActive ? .bold : .regular))
            .foregroundStyle(wordColor)
            .scaleEffect(scale)
            .opacity(opacity)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(wordColor.opacity(glowIntensity * 0.3))
                    .blur(radius: 8)
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isActive)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isLineActive)
            .animation(.easeOut(duration: 0.2), value: progress)
            .onAppear {
                updateAnimationState()
            }
            .onChange(of: isActive) { _ in
                updateAnimationState()
            }
            .onChange(of: isLineActive) { _ in
                updateAnimationState()
            }
            .onChange(of: progress) { _ in
                updateProgressAnimation()
            }
    }

    private var wordColor: Color {
        if isActive {
            return Color.accentColor
        } else if isLineActive {
            return .primary
        } else {
            return .secondary
        }
    }

    private func updateAnimationState() {
        if isActive {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                scale = 1.15
                opacity = 1.0
                glowIntensity = 1.0
            }
        } else if isLineActive {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                scale = 1.0
                opacity = 0.7
                glowIntensity = 0.0
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                scale = 0.95
                opacity = 0.4
                glowIntensity = 0.0
            }
        }
    }

    private func updateProgressAnimation() {
        if isActive && progress > 0 {
            // Animación suave basada en el progreso de la palabra
            let scaleVariation = 1.15 + (sin(progress * .pi) * 0.05)
            let glowVariation = 1.0 - (progress * 0.3)

            withAnimation(.easeInOut(duration: 0.1)) {
                scale = scaleVariation
                glowIntensity = glowVariation
            }
        }
    }
}