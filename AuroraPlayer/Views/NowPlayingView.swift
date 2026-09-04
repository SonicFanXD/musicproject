import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    private var progress: Double {
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(audioEngine.currentTime / audioEngine.duration, 0), 1)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                if let artwork = audioEngine.currentSong?.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 250, height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 10)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 250, height: 250)

                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 8) {
                    Text(audioEngine.currentSong?.title ?? "Sin canción")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(audioEngine.currentSong?.artist ?? "—")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: Color.accentColor))

                    HStack {
                        Text(formatTime(audioEngine.currentTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(formatTime(audioEngine.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 40)

                HStack(spacing: 30) {
                    Button {
                        audioEngine.toggleShuffle()
                    } label: {
                        Image(systemName: audioEngine.isShuffleEnabled ? "shuffle.circle.fill" : "shuffle")
                            .font(.title3)
                            .foregroundStyle(audioEngine.isShuffleEnabled ? Color.accentColor : .secondary)
                    }

                    Button {
                        audioEngine.playPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title)
                    }

                    Button {
                        if audioEngine.isPlaying {
                            audioEngine.pause()
                        } else {
                            audioEngine.resume()
                        }
                    } label: {
                        Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.accentColor)
                    }

                    Button {
                        audioEngine.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title)
                    }

                    Button {
                        audioEngine.cycleRepeatMode()
                    } label: {
                        Image(systemName: repeatIcon)
                            .font(.title3)
                            .foregroundStyle(audioEngine.repeatMode != .off ? Color.accentColor : .secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Reproduciendo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                }
            }
        }
    }

    private var repeatIcon: String {
        switch audioEngine.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat.circle.fill"
        case .one:
            return "repeat.1.circle.fill"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
