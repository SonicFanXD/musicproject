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
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        artwork(for: song)

                        VStack(alignment: .leading, spacing: 2) {
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
                            showingNowPlaying = true
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button {
                                audioEngine.playPrevious()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 16))
                            }

                            Button {
                                if audioEngine.isPlaying {
                                    audioEngine.pause()
                                } else {
                                    audioEngine.resume()
                                }
                            } label: {
                                Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18))
                            }

                            Button {
                                audioEngine.playNext()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                .background(Color(UIColor.secondarySystemBackground))
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
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))

                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
        }
    }
}
