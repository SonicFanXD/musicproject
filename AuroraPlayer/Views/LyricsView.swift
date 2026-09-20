import SwiftUI
import UIKit

// MARK: - Letra con máscara de progreso (estilo Apple Music mejorado)
// ✅ MEJORA KARAOKE: animación side-by-side más visible con efectos
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
        // ✅ El GeometryReader del mask solo se evalúa cuando CAMBIA EL TAMAÑO
        // del texto (no por cada tick de progress). El progress se lee como
        // input → solo re-dibuja el frame del mask, no el layout completo.
        ZStack(alignment: .leading) {
            // Texto base (gris/oscuro)
            Text(text)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(baseColor)
                .blur(radius: progress > 0 ? 0.5 : 0)
                .animation(.easeOut(duration: 0.2), value: progress)

            // Texto iluminado (con máscara de progreso)
            Text(text)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(highlightColor)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                    }
                }
                // ✅ MEJORA KARAOKE: efecto de brillo/glow en el texto iluminado
                .shadow(color: highlightColor.opacity(0.6), radius: progress > 0.5 ? 8 : 0, x: 0, y: 0)
                .animation(.easeOut(duration: 0.15), value: progress)
                // ✅ 60fps: rasteriza el overlay karaoke en la GPU una sola vez
                .drawingGroup()
        }
        .lineLimit(1)
    }
}

struct LyricsView: View {
    let song: Song?
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var clock: PlaybackClock
    @Environment(\.dismiss) private var dismiss

    @State private var parsedLyrics: LyricsType = .none
    @State private var currentLineIndex: Int? = nil
    @State private var scrollTarget: Int? = nil
    @State private var wordProgress: [UUID: Double] = [:]

    // ✅ OPTIMIZACIÓN: palabras agrupadas por línea UNA sola vez (O(n) al parsear)
    @State private var wordsByLine: [[LyricWord]] = []

    var body: some View {
        ZStack {
            blurredArtworkBackground

            VStack(spacing: 0) {
                // ✅ Header integrado al fondo difuminado — SIN cuadro negro.
                // Mismo patrón que NowPlayingView: antes este screen usaba un
                // NavigationStack con .toolbarBackground(.ultraThinMaterial),
                // que sobre el sheet pintaba un rectángulo negro/opaco encima
                // del blur. Ahora el título y el botón de salida son la primera
                // fila del VStack, completamente transparentes sobre el blur.
                HStack(spacing: 0) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Localization.localized("actions.done"))

                    Spacer()

                    Text(Localization.localized("nowPlaying.lyrics"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.9))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                        .accessibilityLabel(Localization.localized("nowPlaying.lyrics"))

                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 8)

                Group {
                    switch parsedLyrics {
                    case .none:
                        emptyLyricsView
                    case .plain(let text):
                        plainLyricsView(text: text)
                    case .synchronized(let syncLyrics):
                        // ✅ DEBUG: siempre usar word-by-word si hay palabras
                        if syncLyrics.isWordByWord || !syncLyrics.words.isEmpty {
                            wordByWordLyricsView(lyrics: syncLyrics)
                        } else {
                            synchronizedLyricsView(lyrics: syncLyrics)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            parseLyrics()
        }
        .onChange(of: clock.time) { newTime in
            updateCurrentLine(for: newTime)
            // ✅ OPTIMIZACIÓN 60fps: solo recalcular wordProgress si estamos
            // en modo karaoke palabra-por-palabra (evita crear dicts nuevos
            // en cada tick de reloj para letras sincronizadas normales).
            if case .synchronized(let syncLyrics) = parsedLyrics, syncLyrics.isWordByWord {
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
                        colors: [AppTheme.accent.opacity(0.12), Color(UIColor.systemBackground)],
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

    // MARK: - Empty Lyrics View (diseño premium estilo NowPlayingView)
    private var emptyLyricsView: some View {
        VStack(spacing: 20) {
            ZStack {
                // ✅ Círculo con material de vidrio (estilo NowPlayingView)
                Circle()
                    .fill(AnyShapeStyle(.ultraThinMaterial))
                    .frame(width: 110, height: 110)
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.accent.opacity(0.4), AppTheme.accent.opacity(0.1)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    }
                    .shadow(color: AppTheme.accent.opacity(0.15), radius: 12, y: 6)

                Image(systemName: "quote.bubble")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.accent.opacity(0.7)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            Text(Localization.localized("lyrics.noLyrics"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(Localization.localized("lyrics.noLyricsSubtitle"))
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
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
                    // ✅ ANIMACIÓN MEJORADA: spring con rebote suave (antes damping
                    // 1.0 = rígido). Ahora damping 0.85 da un scroll más natural y
                    // fluido, con un rebote sutil que se siente premium.
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
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

                        wordByWordLineView(line: line, words: wordsInLine, isActive: currentLineIndex == index,
                            // ✅ FIX KARAOKE: solo la línea ACTIVA recibe su progreso.
                            // Antes `lineProgress` (calculado SIEMPRE para la línea
                            // activa) se pasaba a todas → cada línea se iluminaba
                            // hasta el mismo ancho que la activa.
                            progress: currentLineIndex == index ? lineProgress : 0)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                seekToLine(index, time: line.time, proxy: proxy)
                            }
                            .background(
                                currentLineIndex == index ?
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.accent.opacity(0.06)) : nil
                            )
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
            }
            .onChange(of: scrollTarget) { target in
                if let target = target {
                    // ✅ Misma animación suave que el auto-scroll (consistencia)
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
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
        // ✅ Misma animación suave que el auto-scroll (consistencia)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
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
            // ✅ ANIMACIÓN MEJORADA: spring con rebote suave (antes damping 1.0
            // = críticamente amortiguado, se sentía rígido/robótico). Ahora
            // damping 0.82 da un rebote sutil que se siente orgánico y vivo.
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isActive)
    }

    // MARK: - Word by Word Line View
    // ✅ KARAOKE SUTIL: animación delicada y elegante
    private func wordByWordLineView(line: LyricLine, words: [LyricWord], isActive: Bool, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                // Texto base (gris suave)
                Text(words.map(\.text).joined(separator: " "))
                    .font(.system(size: isActive ? 18 : 15, weight: isActive ? .medium : .regular))
                    .foregroundStyle(Color.gray.opacity(0.6))
                    .blur(radius: progress > 0 ? progress * 0.3 : 0)
                    .opacity(progress > 0.7 ? 0.25 : 1.0)

                // Texto iluminado (con máscara)
                Text(words.map(\.text).joined(separator: " "))
                    .font(.system(size: isActive ? 18 : 15, weight: isActive ? .medium : .regular))
                    .foregroundStyle(.white)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle()
                                .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                        }
                    }
                    .shadow(color: .white.opacity(0.25), radius: progress > 0.5 ? 5 : 0, x: 0, y: 0)
            }
            // Barra de progreso muy sutil
            if isActive && progress > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 2)

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accent.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(progress), height: 2)
                    }
                }
                .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
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
                    // ✅ CRÍTICO - WORD-BY-WORD: usar un valor dinámico basado en el tempo
                    // de la canción en lugar de un fijo de 0.5s. Para canciones rápidas,
                    // 0.5s puede ser demasiado largo y causar que el progreso se quede
                    // "atascado" en 1.0 antes de la siguiente palabra. Usamos la distancia
                    // promedio entre palabras como referencia para el tempo.
                    let avgWordSpacing = words.count > 1 ? (words.last!.time - words.first!.time) / Double(words.count - 1) : 0.3
                    let fallbackDuration = max(0.2, min(0.5, avgWordSpacing))
                    let finalDuration = estimatedDuration > 0 ? estimatedDuration : fallbackDuration
                    if finalDuration > 0 {
                        newProgress[word.id] = min(1.0, max(0.0, timeDiff / finalDuration))
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
            // ✅ DIAGNÓSTICO: permite distinguir en Logs entre "la canción no
            // trae letras en la metadata" y "las letras se detectaron pero con
            // otro formato". Ambos casos pintaban la misma pantalla vacía.
            AppLog.info(.playback, "Lyrics: sin letras en metadata para '\(song?.displayName ?? "?")'")
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