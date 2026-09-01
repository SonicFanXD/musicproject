import SwiftUI
import UIKit

struct PlayerBar: View {
    @ObservedObject var audioEngine: AudioEngine
    let song: Song
    @State private var showNowPlaying = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { showNowPlaying = true } label: {
                    HStack(spacing: 10) {
                        artwork
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(song.artist.isEmpty ? audioEngine.currentRouteName : song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: audioEngine.playPrevious) { Image(systemName: "backward.fill") }
                Button { audioEngine.isPlaying ? audioEngine.pause() : audioEngine.resume() } label: {
                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 38, height: 38).background(Color.accentColor, in: Circle()).foregroundStyle(.white)
                }
                Button(action: audioEngine.playNext) { Image(systemName: "forward.fill") }
            }
            ProgressView(value: audioEngine.currentTime, total: max(audioEngine.duration, 1)).tint(.accentColor).scaleEffect(y: 0.75)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .sheet(isPresented: $showNowPlaying) { NowPlayingView(audioEngine: audioEngine) }
    }

    @ViewBuilder private var artwork: some View {
        if let data = song.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(Circle())
        } else { Image(systemName: "music.note").frame(width: 44, height: 44).background(.quaternary, in: Circle()) }
    }
}
