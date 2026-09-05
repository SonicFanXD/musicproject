import SwiftUI

struct PlayerBar: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    @State private var showingNowPlaying = false

    // ✅ Scrub optimizado: preview local a 60fps, seek real solo al soltar
    @State private var isScrubbing = false
    @State private var scrubPreviewProgress: Double = 0

    // Animaciones optimizadas (una sola @State, triggers discretos = 60fps)
    @State private var playButtonScale: CGFloat = 1.0

    // ✅ Esquinas del artwork sincronizadas con el ajuste de Apariencia
    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.compactPlayerBar") private var compactPlayerBar = false

    private var progress: Double {
        if isScrubbing { return scrubPreviewProgress }
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(audioEngine.currentTime / audioEngine.duration, 0), 1)
    }

    var body: some View {
        Group {
            if let song = audioEngine.currentSong {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        // ✅ Artwork con mejor calidad y animación
                        artwork(for: song)

                        // ✅ Song info con tap target expandido
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(song.artist.isEmpty ? "Artista desconocido" : song.artist)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            // ✅ Mini visualizador junto al título cuando reproduce
                            if audioEngine.isPlaying {
                                HStack(spacing: 2.5) {
                                    ForEach(0..<3, id: \.self) { bar in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.accentColor)
                                            .frame(width: 2.5, height: bar % 2 == 0 ? 11 : 6)
                                            .animation(
                                                .easeInOut(duration: 0.4 + Double(bar) * 0.1).repeatForever(autoreverses: true),
                                                value: audioEngine.isPlaying
                                            )
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                        .onTapGesture {
                            openNowPlaying()
                        }

                        // ✅ Botón de me gusta en la barra de reproducción
                        Button {
                            Haptics.light()
                            fileAccessService.toggleLike(song)
                        } label: {
                            Image(systemName: fileAccessService.isLiked(song) ? "heart.fill" : "heart")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(fileAccessService.isLiked(song) ? .red : .secondary)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // ✅ Controles rediseñados con mejor feedback visual
                        HStack(spacing: 2) {
                            // Previous
                            Button {
                                Haptics.light()
                                audioEngine.playPrevious()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Circle())
                                    .scaleEffect(playButtonScale)
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.85))
                            .accessibilityLabel("Canción anterior")

                            // Play/Pause con animación de escala y halo
                            Button {
                                Haptics.medium()
                                animatePlayButton()
                                if audioEngine.isPlaying {
                                    audioEngine.pause()
                                } else {
                                    audioEngine.resume()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor)

                                    // ✅ Halo animado cuando reproduce
                                    Circle()
                                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 2)
                                        .scaleEffect(audioEngine.isPlaying ? 1.12 : 1.0)
                                        .opacity(audioEngine.isPlaying ? 0.9 : 0)
                                        .animation(
                                            audioEngine.isPlaying
                                                ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                                                : .easeOut(duration: 0.2),
                                            value: audioEngine.isPlaying
                                        )

                                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: compactPlayerBar ? 40 : 44, height: compactPlayerBar ? 40 : 44)
                                .shadow(color: Color.accentColor.opacity(0.35), radius: 8, x: 0, y: 3)
                                .scaleEffect(playButtonScale)
                                .contentShape(Circle())
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.88))
                            .accessibilityLabel(audioEngine.isPlaying ? "Pausar" : "Reproducir")

                            // Next
                            Button {
                                Haptics.light()
                                audioEngine.playNext()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Circle())
                                    .scaleEffect(playButtonScale)
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.85))
                            .accessibilityLabel("Siguiente canción")
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .padding(.top, compactPlayerBar ? 8 : 12)
                    .padding(.bottom, 4)

                    // ✅ Barra de progreso mejorada con preview de scrub
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.18))
                                .frame(height: compactPlayerBar ? 3 : 4)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor.opacity(0.75), Color.accentColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geometry.size.width * progress), height: compactPlayerBar ? 3 : 4)

                            // ✅ Indicador de posición al hacer scrub
                            if isScrubbing {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 10, height: 10)
                                    .offset(x: geometry.size.width * scrubPreviewProgress - 5)
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            }
                        }
                        .frame(height: compactPlayerBar ? 3 : 4)
                        // ✅ FIX: el área táctil era enorme (maxHeight infinity +
                        // padding 14) y robaba los toques del artwork/título,
                        // impidiendo abrir NowPlayingView tras reanudar la app.
                        // Ahora el gesto se limita a la barra (+6pt de margen)
                        // y un toque simple (sin arrastre) abre NowPlaying.
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openNowPlaying()
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard audioEngine.duration > 0, geometry.size.width > 0 else { return }
                                    // ✅ Preview local a 60fps (sin toques al engine durante el arrastre)
                                    isScrubbing = true
                                    scrubPreviewProgress = max(0, min(1, value.location.x / geometry.size.width))
                                }
                                .onEnded { value in
                                    guard audioEngine.duration > 0, geometry.size.width > 0 else { return }
                                    // ✅ Seek real UNA sola vez al soltar
                                    let percentage = max(0, min(1, value.location.x / geometry.size.width))
                                    isScrubbing = false
                                    audioEngine.seek(to: audioEngine.duration * percentage)
                                }
                        )
                    }
                    .frame(height: (compactPlayerBar ? 3 : 4) + 12)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                }
                .background {
                    // ✅ Esquinas muy redondeadas (34pt) con material premium
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
                    // Borde sutil superior para profundidad
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
                .onAppear {
                    artworkAppear()
                }
                .sheet(isPresented: $showingNowPlaying) {
                    NowPlayingView(audioEngine: audioEngine, fileAccessService: fileAccessService)
                }
            }
        }
    }

    // MARK: - Animaciones optimizadas

    /// Animación de aparición del artwork (spring una sola vez, sin repeatForever)
    private func artworkAppear() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            // trigger inicial
        }
    }

    /// Animación de feedback del botón play (spring discreto, no repeatForever)
    private func animatePlayButton() {
        playButtonScale = 0.88
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            playButtonScale = 1.0
        }
    }

    private func openNowPlaying() {
        Haptics.light()
        showingNowPlaying = true
    }

    // MARK: - Artwork (calidad alta, animación sutil = 60fps)
    @ViewBuilder
    private func artwork(for song: Song) -> some View {
        if let art = song.artwork {
            Image(uiImage: art)
                .resizable()
                .interpolation(.high) // ✅ Mejor calidad de interpolación
                .scaledToFill()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                .overlay(
                    // ✅ Indicador de reproducción con animación suave
                    RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous)
                        .stroke(Color.accentColor.opacity(audioEngine.isPlaying ? 0.45 : 0.0), lineWidth: 1.5)
                        .animation(.easeInOut(duration: 0.35), value: audioEngine.isPlaying)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    openNowPlaying()
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)

                Image(systemName: audioEngine.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .animation(.easeInOut(duration: 0.3), value: audioEngine.isPlaying)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openNowPlaying()
            }
        }
    }
}

// MARK: - ButtonStyle con feedback de presión (reusable, GPU barato)
struct PressableButtonStyle: ButtonStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
