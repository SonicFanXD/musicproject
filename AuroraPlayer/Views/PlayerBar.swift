import SwiftUI

struct PlayerBar: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var showingNowPlaying = false
    @State private var artworkScale: CGFloat = 1.0

    private var progress: Double {
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(audioEngine.currentTime / audioEngine.duration, 0), 1)
    }

    var body: some View {
        Group {
            if let song = audioEngine.currentSong {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        // Artwork with subtle scale animation
                        artwork(for: song)
                            .scaleEffect(artworkScale)
                            .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: artworkScale)

                        // Song info with expanded tap target
                        VStack(alignment: .leading, spacing: 3) {
                            Text(song.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(song.artist.isEmpty ? "Artista desconocido" : song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                showingNowPlaying = true
                            }
                        }

                        // Native controls with generous touch targets
                        HStack(spacing: 6) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                audioEngine.playPrevious()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 38, height: 38)
                                    .background {
                                        Circle()
                                            .fill(.regularMaterial)
                                    }
                            }
                            .buttonStyle(.plain)

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if audioEngine.isPlaying {
                                    audioEngine.pause()
                                } else {
                                    audioEngine.resume()
                                }
                            } label: {
                                Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 42, height: 42)
                                    .background {
                                        Circle()
                                            .fill(Color.accentColor.opacity(0.15))
                                    }
                            }
                            .buttonStyle(.plain)

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                audioEngine.playNext()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 38, height: 38)
                                    .background {
                                        Circle()
                                            .fill(.regularMaterial)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    // Native progress bar with expanded touch target area
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 5)

                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.accentColor)
                                .frame(width: geometry.size.width * progress, height: 5)
                        }
                    }
                    .frame(height: 5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10) // Expands touch area without changing visual height
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard audioEngine.duration > 0 else { return }
                                let width = UIScreen.main.bounds.width - 32
                                let percentage = max(0, min(1, value.location.x / width))
                                audioEngine.seek(to: audioEngine.duration * percentage)
                            }
                    )
                    .padding(.bottom, 6)
                }
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 5)
                }
                .onAppear {
                    artworkScale = 1.05
                }
                .sheet(isPresented: $showingNowPlaying) {
                    NowPlayingView(audioEngine: audioEngine)
                }
            }
        }
    }

    @ViewBuilder
    private func artwork(for song: Song) -> some View {
        if let art = song.artwork {
            Image(uiImage: art)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showingNowPlaying = true
                    }
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showingNowPlaying = true
                }
            }
        }
    }
}
