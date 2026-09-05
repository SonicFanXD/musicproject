import SwiftUI
import UIKit

// MARK: - Letra con máscara de progreso (estilo Apple Music)
// El problema anterior: el GeometryReader de la máscara no tenía tamaño
// definido → el ancho era 0 y el texto nunca se "iluminaba".
// Fix: se mide el Text una sola vez y la máscara usa ese ancho.
struct MaskedLyricText: View {
    let text: String
    let baseColor: Color
    let highlightColor: Color
    let progress: Double
    let fontSize: CGFloat
    let fontWeight: Font.Weight

    var body: some View {
        // ✅ FIX: la máscara usa un GeometryReader LOCAL (mask alignment .leading),
        // así cada línea mide su propio ancho. La versión anterior usaba una
        // PreferenceKey compartida: con varias líneas en el LazyVStack todas
        // recibían el mismo ancho y el efecto karaoke no se veía.
        Text(text)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundStyle(baseColor)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundStyle(highlightColor)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle()
                                .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                        }
                    }
            }
            .lineLimit(1)
    }
}

struct LyricsView: View {
    let song: Song?
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var parsedLyrics: LyricsType = .none
    @State private var currentLineIndex: Int? = nil
    @State private var scrollTarget: Int? = nil
    @State private var wordProgress: [UUID: Double] = [:]

    // ✅ OPTIMIZACIÓN: palabras agrupadas por línea UNA sola vez (O(n) al parsear)
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
        // ✅ Rasteriza el fondo difuminado en la GPU una sola vez:
        // evita re-blur en cada frame de scroll (60fps estables).
        .drawingGroup(opaque: true)
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

    // MARK: - Plain Lyrics View (mejorado: fondo glass + scroll)
    private func plainLyricsView(text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.primary)
                .lineSpacing(14)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Synchronized Lyrics View (línea animada con spring + tap-to-seek)
    private func synchronizedLyricsView(lyrics: SynchronizedLyrics) -> some View {
        ScrollViewReader { proxy in
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
                    // ✅ Spring críticamente amortiguado (damping 1.0): desplazamiento
                    // suave y directo SIN rebote (antes "subía y bajaba" con easeInOut
                    // + anchos de línea distintos). Animación de offset → GPU, 60fps.
                    withAnimation(.spring(response: 0.55, dampingFraction: 1.0)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Word by Word Lyrics View (karaoke estilo Apple Music + tap-to-seek)
    private func wordByWordLyricsView(lyrics: SynchronizedLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
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
                    // ✅ Misma animación amortiguada que el auto-scroll (consistencia)
                    withAnimation(.spring(response: 0.55, dampingFraction: 1.0)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Seek a línea (tap en letra)
    private func seekToLine(_ index: Int, time: TimeInterval, proxy: ScrollViewProxy) {
        Haptics.light()
        audioEngine.seek(to: time)
        currentLineIndex = index
        // ✅ Misma animación amortiguada que el auto-scroll (consistencia)
        withAnimation(.spring(response: 0.55, dampingFraction: 1.0)) {
            proxy.scrollTo(index, anchor: .center)
        }
    }

    // MARK: - Lyric Line View (animación de línea mejorada: escala + opacidad + gradiente)
    private func lyricLineView(line: LyricLine, isActive: Bool) -> some View {
        Text(line.text)
            .font(.system(size: isActive ? 24 : 20, weight: isActive ? .bold : .medium))
            // ✅ Línea activa con gradiente sutil (estilo Apple Music)
            .foregroundStyle(
                isActive
                    ? AnyShapeStyle(LinearGradient(
                        colors: [.primary, Color.primary.opacity(0.75)],
                        startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.secondary)
            )
            .opacity(isActive ? 1.0 : 0.65)
            .scaleEffect(isActive ? 1.0 : 0.95)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            // ✅ Amortiguación crítica: transición de línea sin rebote (60fps, GPU)
            .animation(.spring(response: 0.4, dampingFraction: 1.0), value: isActive)
    }

    // MARK: - Word by Word Line View
    // Estilo Apple Music: la línea se muestra gris y las palabras se van
    // "cubriendo de blanco" según su progreso. Optimizado: un solo Text
    // con máscara por línea (no re-render por palabra).
    // Single-line "karaoke" usando máscara continua (más suave y barato)
    private func wordByWordLineView(line: LyricLine, words: [LyricWord], isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MaskedLyricText(
                text: words.map(\.text).joined(separator: " "),
                baseColor: isActive ? Color.secondary : Color.secondary.opacity(0.6),
                // ✅ FIX: usa AppTheme.accent para respetar el ajuste "Color de acento"
                highlightColor: AppTheme.accent,
                progress: lineProgress,
                fontSize: isActive ? 23 : 19,
                fontWeight: isActive ? .bold : .medium
            )
            .animation(.easeOut(duration: 0.15), value: lineProgress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    // Progreso de la línea activa: suma de progresos de sus palabras / nº de palabras.
    // wordProgress solo contiene palabras dentro de la ventana temporal cercana,
    // así que accedemos por id a las de la línea activa.
    private var lineProgress: Double {
        guard let current = currentLineIndex, current >= 0, current < wordsByLine.count else { return 0 }
        let lineWords = wordsByLine[current]
        guard !lineWords.isEmpty else { return 0 }
        let total = lineWords.reduce(0.0) { $0 + (wordProgress[$1.id] ?? 0.0) }
        return min(1.0, total / Double(lineWords.count))
    }

    // MARK: - Update Word Progress (búsqueda binaria + ventana)
    private func updateWordProgress(for time: TimeInterval) {
        guard case .synchronized(let syncLyrics) = parsedLyrics,
              syncLyrics.isWordByWord else { return }

        let words = syncLyrics.words
        guard !words.isEmpty else {
            wordProgress = [:]
            return
        }

        var newProgress: [UUID: Double] = [:]

        // ✅ FIX: ventana amplia hacia atrás para que las palabras ya cantadas
        // mantengan progreso 1.0 (antes con 0.3s el karaoke "retrocedía").
        let windowStart = time - 15.0
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

        if case .synchronized(let syncLyrics) = parsed, syncLyrics.isWordByWord {
            let lines = syncLyrics.lines
            let words = syncLyrics.words
            DispatchQueue.global(qos: .userInitiated).async {
                var grouped: [[LyricWord]] = []
                var wordIndex = 0

                for (lineIndex, line) in lines.enumerated() {
                    var lineWords: [LyricWord] = []
                    let lineEnd = lineIndex < lines.count - 1 ? lines[lineIndex + 1].time : .infinity

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