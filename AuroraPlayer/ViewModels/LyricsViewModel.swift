import Foundation
import Combine

@MainActor
final class LyricsViewModel: ObservableObject {
    @Published var activeID: Int?
    @Published var lyricsLines: [LyricsLine] = []
    @Published var hasLyrics = false
    @Published private(set) var currentTime: TimeInterval = 0

    weak var audioEngine: AudioEngine?
    private var engine: LyricsEngine?
    private var clockCancellable: AnyCancellable?
    private var lastClockDate = Date()
    private var lastClockTime: TimeInterval = 0

    func connectAudioEngine(_ audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
        clockCancellable?.cancel()
        clockCancellable = audioEngine.clock.$time
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.receiveClockTime(time)
            }
    }

    func parseLyrics(_ text: String) {
        let parsed = LyricsParser.parse(text)
        let lines: [LyricsLine]
        switch parsed {
        case .synchronized(let synchronized):
            lines = synchronized.lines.enumerated().map { index, line in
                let startMs = Int((line.time * 1000).rounded())
                let nextStartMs = index + 1 < synchronized.lines.count
                    ? Int((synchronized.lines[index + 1].time * 1000).rounded())
                    : startMs + 10_000
                return LyricsLine(
                    id: index,
                    text: line.text,
                    startMs: startMs,
                    endMs: max(startMs + 1, nextStartMs)
                )
            }
        case .none, .plain:
            lines = []
        }

        lyricsLines = lines
        engine = LyricsEngine(lines: lines)
        hasLyrics = !lines.isEmpty
        activeID = nil
        currentTime = audioEngine?.clock.time ?? 0
        lastClockTime = currentTime
        lastClockDate = Date()
        updateActiveLine(at: Int((currentTime * 1000).rounded()))
    }

    func handleSeek() {
        let time = audioEngine?.currentTime ?? currentTime
        lastClockTime = time
        currentTime = time
        lastClockDate = Date()
        updateActiveLine(at: Int((time * 1000).rounded()))
    }

    /// Kept as compatibility no-ops for existing callers. Clock observation is
    /// lifecycle-independent and does not need a second timer or start/stop API.
    func startMonitoring() {}
    func stopMonitoring() {}

    func line(at index: Int) -> LyricsLine? {
        engine?.line(at: index)
    }

    var lineCount: Int {
        lyricsLines.count
    }

    /// Extrapolates between clock publisher ticks while playback is running.
    func interpolatedTime(at date: Date = Date()) -> TimeInterval {
        guard audioEngine?.isPlaying == true else { return currentTime }
        return max(0, lastClockTime + date.timeIntervalSince(lastClockDate))
    }

    private func receiveClockTime(_ time: TimeInterval) {
        lastClockTime = time
        currentTime = time
        lastClockDate = Date()
        updateActiveLine(at: Int((time * 1000).rounded()))
    }

    private func updateActiveLine(at timeMs: Int) {
        let newID = engine?.activeIndex(at: timeMs)
        if newID != activeID {
            activeID = newID
        }
    }
}
