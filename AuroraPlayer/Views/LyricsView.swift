import SwiftUI
import UIKit

struct LyricsView: View {
    let song: Song?
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var parsedLyrics: LyricsType = .none
    @State private var currentLineIndex: Int? = nil
    @State private var scrollTarget: Int? = nil
    @State private var wordProgress: [UUID: Double] = [:]

    // ✅ OPTIMIZACIÓN: palabras agrupadas por línea UNA sola vez (O(n) al parsear),
    // en lugar de filtrar O(n²) en cada frame de render como antes.
    @State private var wordsByLine: [[LyricWord]] = []

    var body: some View {
        NavigationStack {
            ZStack {
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Letras")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .accessibilityLabel("Letras")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .onAppear {
                parseLyrics()
            }
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
                        .interpolation(.medium)
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
        .allowsHitTesting(false)
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
            // ✅ OPTIMIZACIÓN: LazyVStack solo crea las líneas visibles
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        lyricLineView(line: line, isActive: currentLineIndex == index)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                seekToLine(index, time: line.time, proxy: proxy)
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
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        // ✅ OPTIMIZACIÓN: usa el array precalculado wordsByLine (O(1) por línea)
                        // en vez de filtrar todas las palabras en cada render
                        let wordsInLine = index < wordsByLine.count ? wordsByLine[index] : []

                        wordByWordLineView(line: line, words: wordsInLine, isActive: currentLineIndex == index)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                seekToLine(index, time: line.time, proxy: proxy)
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

    // MARK: - Seek a línea (tap en letra)
    // ✅ FIX del bug: tras el seek, el AudioEngine ahora mantiene el reloj consistente
    // (seekOffset actualizado), así que la animación CONTINÚA desde la línea tocada
    // en vez de reiniciar. Además marcamos la línea como activa inmediatamente
    // y hacemos scroll para que el usuario vea el salto al instante.
    private func seekToLine(_ index: Int, time: TimeInterval, proxy: ScrollViewProxy) {
        Haptics.light()
        audioEngine.seek(to: time)
        currentLineIndex = index
        // Scroll inmediato para feedback visual instantáneo
        withAnimation(.easeInOut(duration: 0.4)) {
            proxy.scrollTo(index, anchor: .center)
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

        var newProgress: [UUID: Double] = [:]

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
                if timeDiff >= 0 && timeDiff <= duration {
                    newProgress[word.id] = min(1.0, max(0.0, timeDiff / duration))
                } else if timeDiff > duration {
                    newProgress[word.id] = 1.0
                }
            } else {
                if timeDiff >= 0 {
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

    // MARK: - Parse Lyrics (con precomputo de palabras por línea)
    private func parseLyrics() {
        guard let lyrics = song?.lyrics, !lyrics.isEmpty else {
            parsedLyrics = .none
            wordsByLine = []
            return
        }
        let parsed = LyricsParser.parse(lyrics)
        parsedLyrics = parsed

        // ✅ OPTIMIZACIÓN: agrupar palabras por línea UNA vez (O(n)) en lugar de
        // filtrar en cada render (O(n²) por frame). También se hace en background
        // para no bloquear el primer frame en canciones con muchas letras.
        if case .synchronized(let syncLyrics) = parsed, syncLyrics.isWordByWord {
            let lines = syncLyrics.lines
            let words = syncLyrics.words
            DispatchQueue.global(qos: .userInitiated).async {
                var grouped: [[LyricWord]] = []
                var wordIndex = 0

                for (lineIndex, line) in lines.enumerated() {
                    var lineWords: [LyricWord] = []
                    let lineEnd = lineIndex < lines.count - 1 ? lines[lineIndex + 1].time : .infinity

                    // Las palabras están ordenadas por tiempo: avance lineal
                    while wordIndex < words.count, words[wordIndex].time < line.time {
                        wordIndex += 1
                    }
                    while wordIndex < words.count, words[wordIndex].time < lineEnd {
                        lineWords.append(words[wordIndex])
                        wordIndex += 1
                    }

                    grouped.append(lineWords)
                }

                DispatchQueue.main.async {
                    wordsByLine = grouped
                }
            }
        } else {
            wordsByLine = []
        }
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