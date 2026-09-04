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
                    HStack(spacing: 16) {
                        // Artwork with native animation
                        artwork(for: song)
                            .scaleEffect(artworkScale)
                            .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: artworkScale)

                        // Song info with native typography
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(song.artist.isEmpty ? "Artista desconocido" : song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                showingNowPlaying = true
                            }
                        }

                        Spacer()

                        // Native controls with system materials
                        HStack(spacing: 8) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                audioEngine.playPrevious()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 36, height: 36)
                                    .background {
                                        Circle()
                                            .fill(.regularMaterial)
                                    }
                            }

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if audioEngine.isPlaying {
                                    audioEngine.pause()
                                } else {
                                    audioEngine.resume()
                                }
                            } label: {
                                Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 42, height: 42)
                                    .background {
                                        Circle()
                                            .fill(Color.accentColor.opacity(0.15))
                                    }
                            }

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                audioEngine.playNext()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 36, height: 36)
                                    .background {
                                        Circle()
                                            .fill(.regularMaterial)
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)

                    // Native progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 5)

                            // Progress fill
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.accentColor)
                                .frame(width: geometry.size.width * progress, height: 5)
                        }
                    }
                    .frame(height: 5)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
                .background {
                    // Native system material
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.regularMaterial)
                }
                .onAppear {
                    artworkScale = audioEngine.isPlaying ? 1.04 : 1.0
                }
                .onChange(of: audioEngine.isPlaying) { isPlaying in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        artworkScale = isPlaying ? 1.04 : 1.0
                    }
                }
                .sheet(isPresented: $showingNowPlaying) {
                    NowPlayingView(audioEngine: audioEngine)
                }
            }
        }
    }

    @ViewBuilder
    private func artwork(for song: Song) -> some View {
        if let image = song.artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
        }
    }
}