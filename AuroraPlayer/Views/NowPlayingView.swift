import SwiftUI
import UIKit

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                artwork
                if let song = audioEngine.currentSong {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(song.title).font(.title2.bold()).lineLimit(2)
                        Text([song.artist, song.album].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(spacing: 4) {
                    Slider(value: Binding(get: { audioEngine.currentTime }, set: { audioEngine.seek(to: $0) }), in: 0...max(audioEngine.duration, 1))
                    HStack { Text(time(audioEngine.currentTime)); Spacer(); Text(time(audioEngine.duration)) }
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 34) {
                    Button(action: audioEngine.toggleShuffle) { Image(systemName: "shuffle").foregroundStyle(audioEngine.isShuffleEnabled ? Color.accentColor : .secondary) }
                    Button(action: audioEngine.playPrevious) { Image(systemName: "backward.fill").font(.title2) }
                    Button { audioEngine.isPlaying ? audioEngine.pause() : audioEngine.resume() } label: { Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 66)) }
                    Button(action: audioEngine.playNext) { Image(systemName: "forward.fill").font(.title2) }
                    Button(action: audioEngine.cycleRepeatMode) { Image(systemName: audioEngine.repeatMode.symbolName).foregroundStyle(audioEngine.repeatMode == .off ? Color.secondary : Color.accentColor) }
                        .accessibilityLabel(audioEngine.repeatMode.accessibilityLabel)
                }
                Text(audioEngine.currentRouteName).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Ahora suena")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } } }
        }
    }

    private var artwork: some View {
        Group {
            if let data = audioEngine.currentSong?.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { Image(systemName: "music.note").resizable().scaledToFit().padding(70).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: 420).aspectRatio(1, contentMode: .fit).background(.quaternary, in: RoundedRectangle(cornerRadius: 18)).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func time(_ value: TimeInterval) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}
