import SwiftUI
import UIKit

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showLyrics = false
    @State private var showQueue = false

    var body: some View {
        NavigationStack {
            ZStack {
                coverGradient.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    GeometryReader { geometry in
                        VStack(spacing: 20) {
                            artwork(side: min(280, max(180, geometry.size.width - 40)))
                            songInformation
                            progress
                            controls
                        }
                        // Un ancho concreto evita que ScrollView propague un
                        // ancho ilimitado y desplace textos/controles fuera.
                        .frame(width: max(0, geometry.size.width - 40), alignment: .top)
                        .padding(.vertical, 16)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                    .frame(minHeight: 640)
                }
            }
            .navigationTitle("Ahora suena")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() }.foregroundStyle(.white) }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showQueue = true } label: { Image(systemName: "list.bullet") }
                            .accessibilityLabel("Ver cola de reproducción")
                        Button { showLyrics = true } label: { Image(systemName: "quote.bubble") }
                            .disabled(audioEngine.currentSong?.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                            .accessibilityLabel("Ver letra")
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(.white)
            .fullScreenCover(isPresented: $showLyrics) {
                if let song = audioEngine.currentSong { LyricsScreen(song: song, audioEngine: audioEngine) }
            }
            .sheet(isPresented: $showQueue) { PlaybackQueueView(audioEngine: audioEngine) }
        }
    }

    private var coverGradient: some View {
        ZStack {
            if let data = audioEngine.currentSong?.artworkData, let image = UIImage(data: data) {
                // `scaledToFit` conserva la relación original de la portada.
                // El frame y clip impiden que el blur expanda el layout.
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(1.12).blur(radius: 26).opacity(0.58).clipped()
            } else { Color(red: 0.06, green: 0.05, blue: 0.10) }
            LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.76)], startPoint: .top, endPoint: .bottom)
        }
    }

    private func artwork(side: CGFloat) -> some View {
        Group {
            if let data = audioEngine.currentSong?.artworkData, let image = UIImage(data: data) {
                // Conserva portadas no cuadradas sin estirarlas ni recortarlas.
                Image(uiImage: image).resizable().scaledToFit()
            } else { Image(systemName: "music.note").resizable().scaledToFit().padding(70).foregroundStyle(.white.opacity(0.7)) }
        }
        // `maxWidth` no restringe la altura de una imagen vertical. Un marco
        // explícito garantiza una portada cuadrada y mantiene los controles visibles.
        .frame(width: side, height: side)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(radius: 18)
    }

    @ViewBuilder private var songInformation: some View {
        if let song = audioEngine.currentSong {
            VStack(alignment: .leading, spacing: 6) {
                Text(song.title).font(.title2.bold()).lineLimit(2).fixedSize(horizontal: false, vertical: true).foregroundStyle(.white)
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
        HStack(spacing: 0) {
            Button(action: audioEngine.toggleShuffle) { Image(systemName: "shuffle").foregroundStyle(audioEngine.isShuffleEnabled ? .white : .white.opacity(0.55)) }
            Spacer(minLength: 12)
            Button(action: audioEngine.playPrevious) { Image(systemName: "backward.fill").font(.title2) }
            Spacer(minLength: 12)
            Button { audioEngine.isPlaying ? audioEngine.pause() : audioEngine.resume() } label: { Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 66)) }
            Spacer(minLength: 12)
            Button(action: audioEngine.playNext) { Image(systemName: "forward.fill").font(.title2) }
            Spacer(minLength: 12)
            Button(action: audioEngine.cycleRepeatMode) { Image(systemName: audioEngine.repeatMode.symbolName).foregroundStyle(audioEngine.repeatMode == .off ? .white.opacity(0.55) : .white) }
                .accessibilityLabel(audioEngine.repeatMode.accessibilityLabel)
        }.foregroundStyle(.white)
    }

    private func time(_ value: TimeInterval) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}

private struct PlaybackQueueView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(audioEngine.playbackQueue) { song in
                Button { audioEngine.play(song: song, from: audioEngine.playbackQueue) } label: {
                    HStack(spacing: 12) {
                        artwork(song)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(song.title).lineLimit(1)
                            Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if song.id == audioEngine.currentSong?.id { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint) }
                    }
                }.buttonStyle(.plain)
            }
            .navigationTitle("En reproducción")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
        }
    }

    @ViewBuilder private func artwork(_ song: Song) -> some View {
        if let data = song.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 7))
        } else { Image(systemName: "music.note").frame(width: 46, height: 46).background(.quaternary, in: RoundedRectangle(cornerRadius: 7)) }
    }
}

private struct LyricsScreen: View {
    let song: Song
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                if let data = song.artworkData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(1.12).blur(radius: 30).opacity(0.68).clipped().ignoresSafeArea()
                } else { Color.indigo.ignoresSafeArea() }
                LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                GeometryReader { geometry in
                    LyricsView(lyrics: song.lyrics, currentTime: audioEngine.currentTime, expanded: true)
                        .frame(width: max(0, geometry.size.width - 56), height: geometry.size.height, alignment: .top)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(.white)
        }
    }
}

private struct LyricsView: View {
    let lyrics: String
    let currentTime: TimeInterval
    var expanded = false
    private var lines: [LyricLine] { LyricLine.parse(lyrics) }
    private var activeIndex: Int? { lines.lastIndex { $0.time.map { $0 <= currentTime } ?? false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LETRA").font(.caption.bold()).foregroundStyle(.white.opacity(0.65))
            if lines.contains(where: { $0.time != nil }) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                TimedLyricText(line: line, currentTime: currentTime, isActiveLine: index == activeIndex).id(index)
                            }
                        }
                    }.frame(maxHeight: expanded ? .infinity : 230)
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
    let words: [TimedWord]

    static func parse(_ lyrics: String) -> [LyricLine] {
        let pattern = "\\[(\\d{1,2}):(\\d{2})(?:\\.(\\d{1,3}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [LyricLine(time: nil, text: lyrics, words: [])] }
        let wordPattern = "<(\\d{1,2}):(\\d{2})(?:\\.(\\d{1,3}))?>"
        let wordRegex = try? NSRegularExpression(pattern: wordPattern)
        return lyrics.components(separatedBy: .newlines).flatMap { raw in
            let matches = regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
            let withoutLineTimes = regex.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
            let words = timedWords(in: withoutLineTimes, regex: wordRegex)
            let text = wordRegex?.stringByReplacingMatches(in: withoutLineTimes, range: NSRange(withoutLineTimes.startIndex..., in: withoutLineTimes), withTemplate: "").trimmingCharacters(in: .whitespaces) ?? withoutLineTimes.trimmingCharacters(in: .whitespaces)
            guard !matches.isEmpty else { return text.isEmpty ? [] : [LyricLine(time: nil, text: text, words: words)] }
            return matches.compactMap { match in
                guard let minutes = Int((raw as NSString).substring(with: match.range(at: 1))), let seconds = Int((raw as NSString).substring(with: match.range(at: 2))) else { return nil }
                let fraction = match.range(at: 3).location == NSNotFound ? 0 : Double("0." + (raw as NSString).substring(with: match.range(at: 3)))!
                return LyricLine(time: Double(minutes * 60 + seconds) + fraction, text: text, words: words)
            }
        }.sorted { ($0.time ?? -.infinity) < ($1.time ?? -.infinity) }
    }

    private static func timedWords(in text: String, regex: NSRegularExpression?) -> [TimedWord] {
        guard let regex else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.enumerated().compactMap { index, match in
            guard let minutes = Int((text as NSString).substring(with: match.range(at: 1))),
                  let seconds = Int((text as NSString).substring(with: match.range(at: 2))) else { return nil }
            let fraction = match.range(at: 3).location == NSNotFound ? 0 : Double("0." + (text as NSString).substring(with: match.range(at: 3)))!
            let start = NSMaxRange(match.range)
            let end = index + 1 < matches.count ? matches[index + 1].range.location : (text as NSString).length
            let word = (text as NSString).substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespaces)
            return word.isEmpty ? nil : TimedWord(time: Double(minutes * 60 + seconds) + fraction, text: word)
        }
    }
}

private struct TimedWord {
    let time: TimeInterval
    let text: String
}

private struct TimedLyricText: View {
    let line: LyricLine
    let currentTime: TimeInterval
    let isActiveLine: Bool

    private var activeWordCount: Int {
        line.words.filter { $0.time <= currentTime }.count
    }

    var body: some View {
        if line.words.isEmpty {
            Text(line.text).font(.title3.bold()).foregroundStyle(isActiveLine ? .white : .white.opacity(0.4))
                .scaleEffect(isActiveLine ? 1 : 0.97)
                .animation(.easeInOut(duration: 0.22), value: isActiveLine)
        } else {
            line.words.enumerated().reduce(Text("")) { result, word in
                result + Text(word.element.text + (word.offset + 1 == line.words.count ? "" : " "))
                    .foregroundColor(isActiveLine && word.element.time <= currentTime ? .white : .white.opacity(0.4))
            }
            .font(.title3.bold())
            .scaleEffect(isActiveLine ? 1 : 0.97)
            // Una sola transición breve por cambio de palabra: no hay timers ni
            // cálculos adicionales y el coste queda limitado a la línea visible.
            .animation(.easeInOut(duration: 0.16), value: activeWordCount)
        }
    }
}
