import SwiftUI

struct PlayerBar: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var showingNowPlaying = false

    // ✅ Scrub optimizado: preview local a 60fps, seek real solo al soltar
    @State private var isScrubbing = false
    @State private var scrubPreviewProgress: Double = 0

    // Animaciones optimizadas (una sola @State, triggers discretos = 60fps)
    @State private var playButtonScale: CGFloat = 1.0

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
                        // Artwork con animación de reproducción suave
                        artwork(for: song)

                        // Song info con expanded tap target
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                        .onTapGesture {
                            openNowPlaying()
                        }

                        // Controles rediseñados con animaciones spring
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

                            // Play/Pause con animación de escala
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

                                    // Halo sutil cuando reproduce (animado con trigger discreto)
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
                                .frame(width: 44, height: 44)
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
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                    // Barra de progreso con touch área expandida
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.18))
                                .frame(height: 4)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor.opacity(0.75), Color.accentColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geometry.size.width * progress), height: 4)
                        }
                        .frame(height: 4)
                        .frame(maxHeight: .infinity) // centra verticalmente
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
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
                    .frame(height: 4 + 28) // 4pt bar + 14pt padding top/bottom
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                }
                .background {
                    // ✅ Más redondeada: cápsula continua 26pt con material premium
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
                    // Borde sutil superior para profundidad
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
                .onAppear {
                    artworkAppear()
                }
                .sheet(isPresented: $showingNowPlaying) {
                    NowPlayingView(audioEngine: audioEngine)
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showingNowPlaying = true
        }
    }

    // MARK: - Artwork (sin animación repeatForever constante = 60fps)
    @ViewBuilder
    private func artwork(for song: Song) -> some View {
        if let art = song.artwork {
            Image(uiImage: art)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                .overlay(
                    // Indicador sutil de reproducción
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(audioEngine.isPlaying ? 0.45 : 0.0), lineWidth: 1.5)
                        .animation(.easeInOut(duration: 0.35), value: audioEngine.isPlaying)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    openNowPlaying()
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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