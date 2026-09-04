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
        // Optimized timer frequency: 0.25s is enough for smooth visuals while reducing CPU load
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
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

        // Optimized: only process words within a 3-second window around current time
        // This avoids iterating over all words in the song on every timer tick
        let windowStart = currentTime - 1.0
        let windowEnd = currentTime + 2.0

        // Binary search to find the starting index (words are time-sorted)
        let words = syncLyrics.words
        guard !words.isEmpty else { return }

        var startIndex = 0
        var endIndex = words.count - 1
        while startIndex < endIndex {
            let mid = (startIndex + endIndex) / 2
            if words[mid].time < windowStart {
                startIndex = mid + 1
            } else {
                endIndex = mid
            }
        }

        // Safety: if all words are before the window, nothing to process
        guard startIndex < words.count else { return }

        // Clear old progress entries outside the window
        if currentWordProgress.count > 0 {
            let activeIDs = Set(currentWordProgress.keys)
            for id in activeIDs {
                if let word = words.first(where: { $0.id == id }),
                   word.time < windowStart || word.time > windowEnd {
                    currentWordProgress.removeValue(forKey: id)
                }
            }
        }

        // Only process words in the active window
        for word in words[startIndex...] {
            guard word.time <= windowEnd else { break }
            if let duration = word.duration {
                let timeDiff = currentTime - word.time
                if timeDiff >= -0.5 && timeDiff <= duration + 0.5 {
                    let progress = min(1.0, max(0.0, timeDiff / duration))
                    if progress > 0 && progress < 1 {
                        currentWordProgress[word.id] = progress
                    } else {
                        currentWordProgress.removeValue(forKey: word.id)
                    }
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
    
    // MARK: - Empty Lyrics View (Enhanced iOS 16 design)
    private var emptyLyricsView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: "quote.bubble")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text("No hay letras disponibles")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            Text("Esta canción no tiene información de letras en su metadata.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Plain Lyrics View
    private func plainLyricsView(text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 18))
                .foregroundStyle(.primary)
                .lineSpacing(12)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                            .background(
                                // Subtle background for active line
                                currentLineIndex == index ?
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.08))
                                    .blur(radius: 10) : nil
                            )
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

                        // Karaoke mode effect wrapper
                        let showKaraokeEffect = showKaraokeMode && currentLineIndex == index

                        wordByWordLineView(line: line, words: wordsInLine, isActive: currentLineIndex == index)
                            .id(index)
                            .overlay(
                                // Karaoke mode background effect
                                showKaraokeEffect ?
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.1))
                                    .blur(radius: 20) : nil
                            )
                            .background(
                                // Active line indicator
                                currentLineIndex == index ?
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1) : nil
                            )
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

    // MARK: - Update Active Words (optimized with binary search window)
    private func updateActiveWords(for time: TimeInterval) {
        guard case .synchronized(let syncLyrics) = parsedLyrics,
              syncLyrics.isWordByWord else { return }

        let words = syncLyrics.words
        guard !words.isEmpty else {
            activeWordIds = []
            return
        }

        var newActiveWordIds: Set<UUID> = []

        // Binary search to find words near the current time
        let windowStart = time - 0.5
        let windowEnd = time + 3.0

        var startIndex = 0
        var endIndex = words.count - 1
        while startIndex < endIndex {
            let mid = (startIndex + endIndex) / 2
            if words[mid].time < windowStart {
                startIndex = mid + 1
            } else {
                endIndex = mid
            }
        }

        // Safety: if all words are before the window, nothing is active
        guard startIndex < words.count else {
            activeWordIds = []
            return
        }

        // Only check words within the active window
        for word in words[startIndex...] {
            guard word.time <= windowEnd else { break }
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
                    .fill(Color.accentColor.opacity(glowIntensity * 0.25))
                    .blur(radius: 15)
            )
            .shadow(color: Color.accentColor.opacity(glowIntensity * 0.2), radius: 12, x: 0, y: 4)
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
                scale = 1.10
                opacity = 1.0
                yOffset = -3.0
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
    @State private var yOffset: CGFloat = 0.0

    var body: some View {
        Text(word)
            .font(.system(size: isLineActive ? 22 : 18, weight: isActive ? .bold : .regular))
            .foregroundStyle(wordColor)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(y: yOffset)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(wordColor.opacity(glowIntensity * 0.4))
                    .blur(radius: 10)
            )
            .shadow(color: wordColor.opacity(glowIntensity * 0.3), radius: 8, x: 0, y: 2)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isActive)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isLineActive)
            .animation(.easeOut(duration: 0.15), value: progress)
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
                scale = 1.18
                opacity = 1.0
                glowIntensity = 1.0
                yOffset = -3.0
            }
        } else if isLineActive {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                scale = 1.0
                opacity = 0.75
                glowIntensity = 0.0
                yOffset = 0.0
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                scale = 0.95
                opacity = 0.4
                glowIntensity = 0.0
                yOffset = 0.0
            }
        }
    }

    private func updateProgressAnimation() {
        if isActive && progress > 0 {
            // Enhanced progress animation with more dynamic effects
            let scaleVariation = 1.18 + (sin(progress * .pi * 2) * 0.06)
            let glowVariation = 1.0 - (progress * 0.4)
            let yOffsetVariation = -3.0 + (sin(progress * .pi) * 2.0)

            withAnimation(.easeInOut(duration: 0.08)) {
                scale = scaleVariation
                glowIntensity = glowVariation
                yOffset = yOffsetVariation
            }
        }
    }
}