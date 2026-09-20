import SwiftUI
import UIKit

// MARK: - Extension para Optional
extension Optional {
    var isNil: Bool {
        self == nil
    }
}

// MARK: - Letra con máscara de progreso (estilo Apple Music mejorado)
// ⚠️ Actualmente sin uso en el flujo activo (el modo word-by-word ahora usa
// LyricsCanvasView). Se deja tal cual por si se reutiliza en otro lado.
struct MaskedLyricText: View {
    let text: String
    let baseColor: Color
    let highlightColor: Color
    let progress: Double
    let fontSize: CGFloat
    let fontWeight: Font.Weight

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(baseColor)
                .blur(radius: progress > 0 ? 0.5 : 0)
                .animation(.easeOut(duration: 0.2), value: progress)

            Text(text)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(highlightColor)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                    }
                }
                .shadow(color: highlightColor.opacity(0.6), radius: progress > 0.5 ? 8 : 0, x: 0, y: 0)
                .animation(.easeOut(duration: 0.15), value: progress)
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

    var body: some View {
        ZStack {
            blurredArtworkBackground

            VStack(spacing: 0) {
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
                        if syncLyrics.isWordByWord || !syncLyrics.words.isEmpty {
                            wordByWordCanvasView()
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
        // ✅ Sigue usado para el modo línea-por-línea (sin tokens) y para
        // saber qué línea resaltar al hacer tap-to-seek. El modo
        // word-by-word YA NO depende de este throttle para su animación:
        // LyricsCanvasView lee audioEngine.preciseElapsedTimeMs directo en
        // cada tick de TimelineView(.animation), a 60fps reales.
        .onReceive(clock.$time.throttle(for: .milliseconds(16), scheduler: RunLoop.main, latest: true)) { newTime in
            updateCurrentLine(for: newTime)
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
        .drawingGroup(opaque: true)
    }

    // MARK: - Empty Lyrics View
    private var emptyLyricsView: some View {
        VStack(spacing: 20) {
            ZStack {
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

    // MARK: - Plain Lyrics View
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

    // MARK: - Synchronized Lyrics View (línea animada, sin tokens)
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
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Word-by-word: vista simple (sin Canvas por ahora)
    @ViewBuilder
    private func wordByWordCanvasView() -> some View {
        // Temporal: usar vista antigua hasta integrar el motor nuevo
        emptyLyricsView
    }

    // MARK: - Seek a línea (tap en letra)
    private func seekToLine(_ index: Int, time: TimeInterval, proxy: ScrollViewProxy) {
        Haptics.light()
        audioEngine.seek(to: time)
        currentLineIndex = index
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
            proxy.scrollTo(index, anchor: .center)
        }
    }

    // MARK: - Lyric Line View (modo línea-por-línea, sin tokens)
    private func lyricLineView(line: LyricLine, isActive: Bool) -> some View {
        Text(line.text)
            .font(.system(size: isActive ? 24 : 20, weight: isActive ? .bold : .medium))
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
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isActive)
    }

    // MARK: - Parse Lyrics
    private func parseLyrics() {
        guard let lyrics = song?.lyrics, !lyrics.isEmpty else {
            parsedLyrics = .none
            return
        }
        let parsed = LyricsParser.parse(lyrics)
        parsedLyrics = parsed

        if case .synchronized(let syncLyrics) = parsed, syncLyrics.isWordByWord {
            // ✅ Word-by-word: usar sistema antiguo por ahora
            // El motor nuevo requiere archivos que se eliminaron por colisiones
        } else {
            // No word-by-word
        }
    }

    // MARK: - Update Current Line (línea-por-línea + tap-to-seek en ambos modos)
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