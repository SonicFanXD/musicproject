import SwiftUI

struct LyricsView: View {
    let song: Song?
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var parsedLyrics: LyricsType = .none
    @State private var currentLineIndex: Int? = nil
    @State private var scrollTarget: Int? = nil
    @State private var wordProgress: [UUID: Double] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                // Fondo difuminado del artwork
                blurredArtworkBackground

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
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                }
            }
            .onAppear { parseLyrics() }
            .onChange(of: audioEngine.currentTime) { newTime in
                updateCurrentLine(for: newTime)
                updateWordProgress(for: newTime)
            }
        }
    }

    // MARK: - Fondo difuminado del artwork
    private var blurredArtworkBackground: some View {
        GeometryReader { geometry in
            Group {
                if let artwork = song?.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 60)
                        .opacity(0.4)
                        .overlay(Color(UIColor.systemBackground).opacity(0.72))
                } else {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.12), Color(UIColor.systemBackground)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Empty Lyrics View
    private var emptyLyricsView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 100, height: 100)
                Image(systemName: "quote.bubble").font(.system(size: 48, weight: .semibold)).foregroundStyle(Color.accentColor)
            }
            Text("No hay letras disponibles").font(.system(size: 20, weight: .bold)).foregroundStyle(.primary)
            Text("Esta canción no tiene información de letras en su metadata.")
                .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 60)
    }

    // MARK: - Plain Lyrics View
    private func plainLyricsView(text: String) -> some View {
        ScrollView {
            Text(text).font(.system(size: 19, weight: .medium)).foregroundStyle(.primary).lineSpacing(14)
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Synchronized Lyrics View (con tap-to-seek)
    private func synchronizedLyricsView(lyrics: SynchronizedLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        lyricLineView(line: line, isActive: currentLineIndex == index)
                            .id(index)
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                audioEngine.seek(to: line.time)
                                currentLineIndex = index
                            }
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
            }
            .onChange(of: scrollTarget) { target in
                if let target = target {
                    withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(target, anchor: .center) }
                }
            }
        }
    }

    // MARK: - Word by Word Lyrics View (karaoke animado + tap-to-seek)
    private func wordByWordLyricsView(lyrics: SynchronizedLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        let wordsInLine = lyrics.words.filter { word in
                            word.time >= line.time &&
                            (index < lyrics.lines.count - 1 ? word.time < lyrics.lines[index + 1].time : true)
                        }

                        wordByWordLineView(line: line, words: wordsInLine, isActive: currentLineIndex == index)
                            .id(index)
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                audioEngine.seek(to: line.time)
                                currentLineIndex = index
                            }
                            .background(
                                currentLineIndex == index ?
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.06)) : nil
                            )
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
            }
            .onChange(of: scrollTarget) { target in
                if let target = target {
                    withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(target, anchor: .center) }
                }
            }
        }
    }

    // MARK: - Lyric Line View (brillante)
    private func lyricLineView(line: LyricLine, isActive: Bool) -> some View {
        Text(line.text)
            .font(.system(size: isActive ? 24 : 20, weight: isActive ? .bold : .medium))
            .foregroundStyle(isActive ? .primary : .secondary)
            .opacity(isActive ? 1.0 : 0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isActive)
    }

    // MARK: - Word by Word Line View (karaoke con animación fluida)
    private func wordByWordLineView(line: LyricLine, words: [LyricWord], isActive: Bool) -> some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(words.enumerated()), id: \.element.id) { _, word in
                let progress = wordProgress[word.id] ?? 0.0

                Text(word.text)
                    .font(.system(size: isActive ? 22 : 18, weight: progress > 0 ? .bold : .medium))
                    .foregroundStyle(karaokeColor(progress: progress, isActive: isActive))
                    .opacity(isActive ? (progress > 0 ? 1.0 : 0.85) : 0.75)
                    .scaleEffect(1.0 + (progress * 0.08))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: progress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    // MARK: - Color karaoke (gradiente de inactivo a activo)
    private func karaokeColor(progress: Double, isActive: Bool) -> Color {
        if !isActive { return .secondary }
        if progress >= 1.0 { return Color.accentColor }
        if progress > 0 { return Color.accentColor.opacity(0.4 + progress * 0.6) }
        return .primary
    }

    // MARK: - Update Word Progress (animación karaoke suave)
    private func updateWordProgress(for time: TimeInterval) {
        guard case .synchronized(let syncLyrics) = parsedLyrics,
              syncLyrics.isWordByWord else { return }

        let words = syncLyrics.words
        guard !words.isEmpty else {
            wordProgress = [:]
            return
        }

        var newProgress: [UUID: Double] = {}

        // Binary search para ventana de tiempo
        let windowStart = time - 0.3
        let windowEnd = time + 2.0

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

        guard startIndex < words.count else {
            wordProgress = [:]
            return
        }

        for (index, word) in words[startIndex...].enumerated() {
            guard word.time <= windowEnd else { break }

            let timeDiff = time - word.time
            if let duration = word.duration, duration > 0 {
                // Palabra con duración conocida: progreso suave 0→1
                if timeDiff >= 0 && timeDiff <= duration {
                    newProgress[word.id] = min(1.0, max(0.0, timeDiff / duration))
                } else if timeDiff > duration {
                    newProgress[word.id] = 1.0
                }
            } else {
                // Sin duración: estimación basada en tiempo hasta siguiente palabra
                if timeDiff >= 0 {
                    // Buscar siguiente palabra para estimar duración
                    let nextWordTime = startIndex + index + 1 < words.count ? words[startIndex + index + 1].time : word.time + 0.5
                    let estimatedDuration = nextWordTime - word.time
                    if estimatedDuration > 0 {
                        newProgress[word.id] = min(1.0, max(0.0, timeDiff / estimatedDuration))
                    } else {
                        newProgress[word.id] = min(1.0, timeDiff * 2.0)
                    }
                }
            }
        }

        wordProgress = newProgress
    }

    // MARK: - Parse Lyrics
    private func parseLyrics() {
        guard let lyrics = song?.lyrics, !lyrics.isEmpty else {
            parsedLyrics = .none
            return
        }
        parsedLyrics = LyricsParser.parse(lyrics)
    }

    // MARK: - Update Current Line
    private func updateCurrentLine(for time: TimeInterval) {
        switch parsedLyrics {
        case .synchronized(let syncLyrics):
            if let newIndex = LyricsParser.getCurrentLineIndex(from: syncLyrics, at: time) {
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