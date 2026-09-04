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
                        // Artwork with subtle breathing animation
                        artwork(for: song)
                            .scaleEffect(artworkScale)
                            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: artworkScale)

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

                        // Controls - simplified for performance
                        HStack(spacing: 10) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                audioEngine.playPrevious()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.primary)
                                    .frame(width: 32, height: 32)
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
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 36, height: 36)
                            }

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                audioEngine.playNext()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.primary)
                                    .frame(width: 32, height: 32)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    // Simplified progress bar for performance
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 4)

                            // Progress
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.accentColor)
                                .frame(width: geometry.size.width * progress, height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
                .background(.ultraThinMaterial)
                .onAppear {
                    artworkScale = audioEngine.isPlaying ? 1.03 : 1.0
                }
                .onChange(of: audioEngine.isPlaying) { isPlaying in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        artworkScale = isPlaying ? 1.03 : 1.0
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
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))

                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
        }
    }
}
