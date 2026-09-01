import SwiftUI
import UIKit

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                coverGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        artwork
                        songInformation
                        progress
                        controls
                        if let song = audioEngine.currentSong, !song.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            LyricsView(lyrics: song.lyrics, currentTime: audioEngine.currentTime)
                        }
                    }
                    .padding(.horizontal).padding(.bottom, 36)
                }
            }
            .navigationTitle("Ahora suena")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() }.foregroundStyle(.white) } }
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(.white)
        }
    }

    private var coverGradient: some View {
        ZStack {
            if let data = audioEngine.currentSong?.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().blur(radius: 32).scaleEffect(1.2).opacity(0.72)
            } else { Color.indigo }
            LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.5), .black.opacity(0.94)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var artwork: some View {
        Group {
            if let data = audioEngine.currentSong?.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { Image(systemName: "music.note").resizable().scaledToFit().padding(70).foregroundStyle(.white.opacity(0.7)) }
        }
        .frame(maxWidth: 420).aspectRatio(1, contentMode: .fit)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(radius: 18)
    }

    @ViewBuilder private var songInformation: some View {
        if let song = audioEngine.currentSong {
            VStack(alignment: .leading, spacing: 6) {
                Text(song.title).font(.title2.bold()).lineLimit(2).foregroundStyle(.white)
                Text([song.artist, song.album].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                if !song.formatDescription.isEmpty {
                    Label(song.formatDescription, systemImage: "waveform").font(.caption).foregroundStyle(.white.opacity(0.85)).padding(.top, 2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progress: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { audioEngine.currentTime }, set: { audioEngine.seek(to: $0) }), in: 0...max(audioEngine.duration, 1)).tint(.white)
            HStack { Text(time(audioEngine.currentTime)); Spacer(); Text(time(audioEngine.duration)) }
                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
        }
    }

    private var controls: some View {
        HStack(spacing: 34) {
            Button(action: audioEngine.toggleShuffle) { Image(systemName: "shuffle").foregroundStyle(audioEngine.isShuffleEnabled ? .white : .white.opacity(0.55)) }
            Button(action: audioEngine.playPrevious) { Image(systemName: "backward.fill").font(.title2) }
            Button { audioEngine.isPlaying ? audioEngine.pause() : audioEngine.resume() } label: { Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 66)) }
            Button(action: audioEngine.playNext) { Image(systemName: "forward.fill").font(.title2) }
            Button(action: audioEngine.cycleRepeatMode) { Image(systemName: audioEngine.repeatMode.symbolName).foregroundStyle(audioEngine.repeatMode == .off ? .white.opacity(0.55) : .white) }
                .accessibilityLabel(audioEngine.repeatMode.accessibilityLabel)
        }.foregroundStyle(.white)
    }

    private func time(_ value: TimeInterval) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}

private struct LyricsView: View {
    let lyrics: String
    let currentTime: TimeInterval
    private var lines: [LyricLine] { LyricLine.parse(lyrics) }
    private var activeIndex: Int? { lines.lastIndex { $0.time <= currentTime } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LETRA").font(.caption.bold()).foregroundStyle(.white.opacity(0.65))
            if lines.contains(where: { $0.time != nil }) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line.text).font(.title3.bold()).foregroundStyle(index == activeIndex ? .white : .white.opacity(0.4)).id(index)
                            }
                        }
                    }.frame(maxHeight: 230)
                    .onChange(of: activeIndex) { index in
                        if let index { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .center) } }
                    }
                }
            } else {
                Text(lyrics).font(.body).foregroundStyle(.white.opacity(0.9)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
    }
}

private struct LyricLine {
    let time: TimeInterval?
    let text: String

    static func parse(_ lyrics: String) -> [LyricLine] {
        let pattern = "\\[(\\d{1,2}):(\\d{2})(?:\\.(\\d{1,3}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [LyricLine(time: nil, text: lyrics)] }
        return lyrics.components(separatedBy: .newlines).flatMap { raw in
            let matches = regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
            let text = regex.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "").trimmingCharacters(in: .whitespaces)
            guard !matches.isEmpty else { return text.isEmpty ? [] : [LyricLine(time: nil, text: text)] }
            return matches.compactMap { match in
                guard let minutes = Int((raw as NSString).substring(with: match.range(at: 1))), let seconds = Int((raw as NSString).substring(with: match.range(at: 2))) else { return nil }
                let fraction = match.range(at: 3).location == NSNotFound ? 0 : Double("0." + (raw as NSString).substring(with: match.range(at: 3)))!
                return LyricLine(time: Double(minutes * 60 + seconds) + fraction, text: text)
            }
        }.sorted { ($0.time ?? -.infinity) < ($1.time ?? -.infinity) }
    }
}
