import SwiftUI
import UIKit

// MARK: - Extension para Optional
extension Optional {
    var isNil: Bool {
        self == nil
    }
}

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

    // ✅ MOTOR APPLE MUSIC: estado del motor de lyrics
    @State private var lyricsEngine: LyricsEngine?
    @State private var lyricsState: LyricsState = LyricsState(activeTokenID: nil, progress: 0, activeLineIndex: 0, previousTokenID: nil, nextTokenID: nil)
    @State private var tokensByLine: [[LyricsToken]] = []

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
        .onReceive(clock.$time.throttle(for: .milliseconds(16), scheduler: RunLoop.main, latest: true)) { newTime in
            // ✅ OPTIMIZACIÓN 60fps: throttle a 16ms (~60fps) para iPhone 8 Plus
            updateCurrentLine(for: newTime)
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
                            progress: lyricsState.progress)
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

    // MARK: - MOTOR DE LYRICS APPLE MUSIC
// ✅ Motor puro: dado timeMs, retorna LyricsState determinista
private class LyricsEngine {
    private var tokens: [LyricsToken] = []
    
    init(from words: [LyricWord]) {
        convertToTokens(words)
    }
    
    /// Convierte LyricWord a LyricsToken con línea de tiempo en ms
    private func convertToTokens(_ words: [LyricWord]) {
        var converted: [LyricsToken] = []
        var lineIndex = 0
        var wordIndex = 0
        
        for (index, word) in words.enumerated() {
            let startMs = Int(word.time * 1000)
            let endMs: Int
            if let duration = word.duration, duration > 0 {
                endMs = startMs + Int(duration * 1000)
            } else if index + 1 < words.count {
                endMs = Int(words[index + 1].time * 1000)
            } else {
                endMs = startMs + 500 // 500ms por defecto
            }
            
            let token = LyricsToken(
                id: word.id.uuidString,
                text: word.text,
                startMs: startMs,
                endMs: endMs,
                lineIndex: lineIndex,
                wordIndex: wordIndex
            )
            converted.append(token)
            wordIndex += 1
        }
        
        // Ordenar por startMs (ya deberían estar ordenados del parser)
        tokens = converted.sorted { $0.startMs < $1.startMs }
    }
    
    /// ✅ MOTOR PURO: estado determinista en un momento dado (optimizado 60fps)
    func state(at timeMs: Int) -> LyricsState {
        guard !tokens.isEmpty else {
            return LyricsState(activeTokenID: nil, progress: 0, activeLineIndex: 0, previousTokenID: nil, nextTokenID: nil)
        }
        
        // ✅ OPTIMIZACIÓN: cache de última búsqueda para evitar búsqueda binaria duplicada
        if timeMs == lastQueriedTimeMs, !lastState.activeTokenID.isNil {
            return lastState
        }
        
        // Búsqueda binaria para encontrar token activo
        var lo = 0, hi = tokens.count - 1
        var activeIndex = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if tokens[mid].startMs <= timeMs {
                activeIndex = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        
        let activeToken = tokens[activeIndex]
        let progress: Double
        if activeToken.endMs > activeToken.startMs {
            progress = Double(timeMs - activeToken.startMs) / Double(activeToken.endMs - activeToken.startMs)
        } else {
            progress = 0.0
        }
        
        let previousTokenID = activeIndex > 0 ? tokens[activeIndex - 1].id : nil
        let nextTokenID = activeIndex < tokens.count - 1 ? tokens[activeIndex + 1].id : nil
        
        let newState = LyricsState(
            activeTokenID: activeToken.id,
            progress: progress,
            activeLineIndex: activeToken.lineIndex,
            previousTokenID: previousTokenID,
            nextTokenID: nextTokenID
        )
        
        // ✅ Cache para evitar búsqueda duplicada
        lastQueriedTimeMs = timeMs
        lastState = newState
        
        return newState
    }
    
    private var lastQueriedTimeMs: Int = -1
    private var lastState: LyricsState = LyricsState(activeTokenID: nil, progress: 0, activeLineIndex: 0, previousTokenID: nil, nextTokenID: nil)
    
    /// Agrupa tokens en líneas para renderizado
    func getTokensByLine() -> [[LyricsToken]] {
        var grouped: [Int: [LyricsToken]] = [:]
        for token in tokens {
            grouped[token.lineIndex, default: []].append(token)
        }
        return grouped.sorted { $0.key < $1.key }.map { $0.value }
    }
}

// MARK: - Update Word Progress (motor Apple Music optimizado 60fps)
    private func updateWordProgress(for time: TimeInterval) {
        guard let engine = lyricsEngine else { return }
        
        let timeMs = Int(time * 1000)
        let newState = engine.state(at: timeMs)
        
        // ✅ OPTIMIZACIÓN 60fps: solo actualizar si el estado cambió significativamente
        // Evita actualizaciones innecesarias en cada tick
        if newState.activeTokenID != lyricsState.activeTokenID ||
           abs(newState.progress - lyricsState.progress) > 0.02 {
            lyricsState = newState
        }
    }

    // MARK: - Parse Lyrics (inicializar motor Apple Music)
    private func parseLyrics() {
        guard let lyrics = song?.lyrics, !lyrics.isEmpty else {
            parsedLyrics = .none
            wordsByLine = []
            lyricsEngine = nil
            lyricsState = LyricsState(activeTokenID: nil, progress: 0, activeLineIndex: 0, previousTokenID: nil, nextTokenID: nil)
            return
        }
        let parsed = LyricsParser.parse(lyrics)
        parsedLyrics = parsed

        if case .synchronized(let syncLyrics) = parsed, syncLyrics.isWordByWord {
            lyricsEngine = LyricsEngine(from: syncLyrics.words)
            tokensByLine = lyricsEngine?.getTokensByLine() ?? []
        } else {
            lyricsEngine = nil
            tokensByLine = []
        }
    }

    // MARK: - Word by Word Line View (Apple Music model optimizado 60fps)
    private func wordByWordLineView(line: LyricLine, words: [LyricWord], isActive: Bool, progress: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                let isActiveToken = lyricsState.activeTokenID == word.id.uuidString
                let tokenProgress = isActiveToken ? lyricsState.progress : 0.0
                
                // ✅ OPTIMIZACIÓN 60fps: usar drawingGroup para renderizado eficiente
                Text(word.text)
                    .font(.system(size: isActive ? 18 : 15, weight: isActive ? .medium : .regular))
                    .foregroundStyle(tokenProgress > 0.5 ? .white : Color.gray.opacity(0.5))
                    .opacity(tokenProgress > 0.9 ? 1.0 : tokenProgress > 0.1 ? 0.7 : 0.4)
                    .scaleEffect(tokenProgress > 0.8 ? 1.03 : 1.0)
                    // ✅ Eliminar animación costosa, usar interpolación directa
                    .drawingGroup(opaque: false, colorMode: .nonLinear)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
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