import SwiftUI

struct PlayerBar: View {
    @ObservedObject var audioEngine: AudioEngine

    @State private var showingNowPlaying = false

    private var progress: Double {
        guard audioEngine.duration > 0 else {
            return 0
        }

        return min(
            max(audioEngine.currentTime / audioEngine.duration, 0),
            1
        )
    }

    var body: some View {
        Group {
            if let song = audioEngine.currentSong {
                HStack(spacing: 12) {

                    // MARK: - Artwork + Song Info

                    HStack(spacing: 12) {
                        artwork(for: song)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(song.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(
                                song.artist.isEmpty
                                    ? "Artista desconocido"
                                    : song.artist
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingNowPlaying = true
                    }

                    Spacer(minLength: 4)

                    // MARK: - Previous

                    Button {
                        audioEngine.playPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)

                    // MARK: - Play / Pause

                    Button {
                        if audioEngine.isPlaying {
                            audioEngine.pause()
                        } else {
                            audioEngine.resume()
                        }
                    } label: {
                        Image(
                            systemName: audioEngine.isPlaying
                                ? "pause.fill"
                                : "play.fill"
                        )
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background {
                            Circle()
                                .fill(
                                    Color.accentColor.opacity(0.20)
                                )
                        }
                        .overlay {
                            Circle()
                                .stroke(
                                    .white.opacity(0.25),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)

                    // MARK: - Next

                    Button {
                        audioEngine.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(
                        cornerRadius: 24,
                        style: .continuous
                    )
                    .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 24,
                        style: .continuous
                    )
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.45),
                                .white.opacity(0.12),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
                .overlay(alignment: .bottom) {
                    MiniProgressTrack(
                        progress: progress
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                }
                .shadow(
                    color: .black.opacity(0.18),
                    radius: 16,
                    y: 7
                )
                .sheet(isPresented: $showingNowPlaying) {
                    NowPlayingView(
                        audioEngine: audioEngine
                    )
                }
            }
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artwork(for song: Song) -> some View {
        if let artworkData = song.artworkData,
           let image = UIImage(data: artworkData) {

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                    .stroke(
                        .white.opacity(0.18),
                        lineWidth: 1
                    )
                }

        } else {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
                .fill(.thinMaterial)

                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50, height: 50)
        }
    }
}

// MARK: - Mini Progress Track

struct MiniProgressTrack: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {

                Capsule()
                    .fill(.white.opacity(0.12))
                    .frame(height: 3)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(
                        width: max(
                            3,
                            geometry.size.width * progress
                        ),
                        height: 3
                    )
            }
        }
        .frame(height: 3)
        .allowsHitTesting(false)
    }
}

