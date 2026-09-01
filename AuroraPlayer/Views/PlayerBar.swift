import SwiftUI

struct PlayerBar: View {
    @ObservedObject var audioEngine: AudioEngine
    let song: Song
    @State private var showNowPlaying = false

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: audioEngine.currentTime, total: max(audioEngine.duration, 1))
                .tint(.accentColor)

            HStack {
                Button { showNowPlaying = true } label: {
                    HStack(spacing: 10) {
                        if let data = song.artworkData, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 5))
                        } else { Image(systemName: "music.note").frame(width: 38, height: 38).background(.quaternary, in: RoundedRectangle(cornerRadius: 5)) }
                        VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline)
                        .bold()
                        .lineLimit(1)

                    Text(audioEngine.currentRouteName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        }
                    }
                }.buttonStyle(.plain)

                Spacer()

                HStack(spacing: 18) {
                    Button {
                        audioEngine.playPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20))
                    }

                    Button {
                        if audioEngine.isPlaying {
                            audioEngine.pause()
                        } else {
                            audioEngine.resume()
                        }
                    } label: {
                        Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 40))
                    }

                    Button {
                        audioEngine.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20))
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .sheet(isPresented: $showNowPlaying) { NowPlayingView(audioEngine: audioEngine) }
    }
}
