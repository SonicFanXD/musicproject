import SwiftUI

struct PlayerBar: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var showingNowPlaying = false

    private var progress: Double {
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(audioEngine.currentTime / audioEngine.duration, 0), 1)
    }

    var body: some View {
        Group {
            if let song = audioEngine.currentSong {
                HStack(spacing: 12) {
                    // Artwork + Song Info
                    HStack(spacing: 12) {
                        artwork(for: song)

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
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingNowPlaying = true
                    }

                    Spacer(minLength: 4)

                    // Previous
                    Button {
                        audioEngine.playPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)

                    // Play / Pause
                    Button {
                        if audioEngine.isPlaying {
                            audioEngine.pause()
                        } else {
                            audioEngine.resume()
                        }
                    } label: {
                        Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    // .opaqueGlassCircle(isPressed: !audioEngine.isPlaying) // ❌ Eliminado: método no existe
                    .scaleEffect(audioEngine.isPlaying ? 1.0 : 0.92)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6))

                    // Next
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
                .opaqueGlass(cornerRadius: 24, tintIntensity: 0.08, strokeIntensity: 0.35)
                .overlay(alignment: .bottom) {
                    MiniProgressTrack(progress: progress)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.spring(response: 0.4, dampingFraction: 0.85))
                .sheet(isPresented: $showingNowPlaying) {
                    NowPlayingView(audioEngine: audioEngine)
                }
            }
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artwork(for song: Song) -> some View {
        if let image = song.artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
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
                    .fill(.white.opacity(0.15))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(4, geometry.size.width * progress), height: 4)
                    .animation(.linear(duration: 0.4))
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 4, x: 0, y: 2)
            }
        }
        .frame(height: 4)
        .allowsHitTesting(false)
    }
}