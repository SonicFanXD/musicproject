import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class AudioEngine: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentSong: Song?
    @Published private(set) var currentRouteName = "Altavoz"
    @Published var isShuffleEnabled = false { didSet { saveState() } }
    @Published var repeatMode: RepeatMode = .off { didSet { saveState() } }

    private var playlist: [Song] = []
    private(set) var currentIndex = 0
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var displayTimer: Timer?
    private var sampleRate = 44_100.0
    private var seekOffset: TimeInterval = 0
    private var playbackGeneration = 0
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var nowPlayingArtworkSongID: UUID?
    private var lastNowPlayingPositionUpdate: TimeInterval = 0
    private var isConfigured = false
    private var hasRestored = false
    private let stateDefaultsKey = "com.aurora.playbackState"

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true)
        } catch { AppLog.error(.playback, "Sesión de audio: \(error.localizedDescription)") }
        engine.attach(playerNode)
        // El motor adapta el archivo al formato nativo de cada salida sin imponer 44.1 kHz.
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        updateRouteName()
        setupRemoteCommandCenter()
    }

    @objc private func applicationWillResignActive() { saveState() }

    func play(song: Song, from songs: [Song]? = nil) {
        configureIfNeeded()
        playlist = songs?.isEmpty == false ? songs! : [song]
        currentIndex = playlist.firstIndex(where: { $0.id == song.id }) ?? 0
        playCurrentSong()
    }

    private func playCurrentSong(startAt time: TimeInterval = 0, shouldPlay: Bool = true) {
        guard playlist.indices.contains(currentIndex) else { stop(clearSong: true); return }
        let song = playlist[currentIndex]
        stopPlayback(resetPosition: true)
        do {
            let file = try AVAudioFile(forReading: song.url)
            let rate = file.processingFormat.sampleRate
            guard rate > 0, file.length > 0 else { throw PlaybackError.invalidAudioFile }
            audioFile = file; sampleRate = rate; duration = Double(file.length) / rate; currentSong = song
            prepareNowPlayingArtwork(for: song)
            let position = min(max(0, time), duration)
            seekOffset = position; currentTime = position
            if !engine.isRunning { try engine.start() }
            scheduleFile(file, from: AVAudioFramePosition(position * rate), shouldPlay: shouldPlay)
            isPlaying = shouldPlay
            if shouldPlay { startDisplayTimer() }
            updateNowPlayingInfo(); saveState()
            AppLog.info(.playback, "Reproduciendo \(song.title), \(Int(rate)) Hz, \(file.processingFormat.channelCount) canales")
        } catch {
            AppLog.error(.playback, "No se pudo reproducir \(song.title): \(error.localizedDescription)")
            advanceAfterFailure()
        }
    }

    private func scheduleFile(_ file: AVAudioFile, from startFrame: AVAudioFramePosition, shouldPlay: Bool) {
        playbackGeneration += 1
        let generation = playbackGeneration
        playerNode.stop()
        let start = min(max(startFrame, 0), file.length)
        let remaining = file.length - start
        guard remaining > 0 else { handlePlaybackFinished(); return }
        playerNode.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(remaining), at: nil) { [weak self] in
            DispatchQueue.main.async { guard self?.playbackGeneration == generation else { return }; self?.handlePlaybackFinished() }
        }
        if shouldPlay { playerNode.play() }
    }

    func playNext() {
        guard !playlist.isEmpty else { return }
        if isShuffleEnabled, playlist.count > 1 {
            var next = currentIndex
            while next == currentIndex { next = Int.random(in: playlist.indices) }
            currentIndex = next
        } else if currentIndex + 1 < playlist.count { currentIndex += 1
        } else if repeatMode == .all { currentIndex = 0
        } else { stop(clearSong: true); return }
        playCurrentSong()
    }

    func playPrevious() {
        guard !playlist.isEmpty else { return }
        if currentTime > 3 { seek(to: 0); return }
        if currentIndex > 0 { currentIndex -= 1
        } else if repeatMode == .all { currentIndex = playlist.count - 1
        } else { seek(to: 0); return }
        playCurrentSong()
    }

    func pause() {
        guard isPlaying else { return }
        updateCurrentTime(); playerNode.pause(); isPlaying = false; stopDisplayTimer(); updateNowPlayingInfo(); saveState()
        AppLog.debug(.playback, "Pausa")
    }

    func resume() {
        configureIfNeeded(); guard audioFile != nil else { return }
        do { if !engine.isRunning { try engine.start() } } catch { AppLog.error(.playback, "Motor: \(error.localizedDescription)"); return }
        playerNode.play(); isPlaying = true; startDisplayTimer(); updateNowPlayingInfo(); saveState()
    }

    func stop(clearSong: Bool = false) {
        stopPlayback(resetPosition: true)
        if clearSong { currentSong = nil; duration = 0; updateNowPlayingInfo() }
        saveState()
    }

    private func stopPlayback(resetPosition: Bool) {
        playbackGeneration += 1; playerNode.stop(); audioFile = nil; isPlaying = false; stopDisplayTimer()
        if resetPosition { currentTime = 0; seekOffset = 0 }
    }

    func seek(to time: TimeInterval) {
        guard let file = audioFile else { return }
        let position = min(max(0, time), duration), wasPlaying = isPlaying
        seekOffset = position; currentTime = position
        scheduleFile(file, from: AVAudioFramePosition(position * sampleRate), shouldPlay: wasPlaying)
        updateNowPlayingInfo(); saveState()
    }

    func toggleShuffle() { isShuffleEnabled.toggle() }
    func cycleRepeatMode() { repeatMode = switch repeatMode { case .off: .all; case .all: .one; case .one: .off } }

    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.updateCurrentTime() }
    }
    private func stopDisplayTimer() { displayTimer?.invalidate(); displayTimer = nil }
    private func updateCurrentTime() {
        guard let nodeTime = playerNode.lastRenderTime, let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        currentTime = min(duration, seekOffset + Double(playerTime.sampleTime) / playerTime.sampleRate)
        // La pantalla bloqueada interpola la posición; una actualización espaciada
        // corrige posibles desajustes sin trabajo ni decodificación por cada tick.
        if currentTime - lastNowPlayingPositionUpdate >= 5 {
            updateNowPlayingInfo()
        }
    }
    private func handlePlaybackFinished() { guard isPlaying else { return }; repeatMode == .one ? playCurrentSong() : playNext() }
    private func advanceAfterFailure() {
        guard playlist.count > 1 else { stop(clearSong: true); return }
        currentIndex = currentIndex + 1 < playlist.count ? currentIndex + 1 : 0; playCurrentSong()
    }

    @objc private func handleRouteChange(_: Notification) { updateRouteName() }
    private func updateRouteName() {
        guard let output = AVAudioSession.sharedInstance().currentRoute.outputs.first else { return }
        currentRouteName = switch output.portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: "Bluetooth: \(output.portName)"
        case .headphones: "Audífonos: \(output.portName)"
        case .builtInSpeaker: "Altavoz"
        default: output.portName
        }
        AppLog.debug(.playback, "Ruta: \(currentRouteName)")
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
        if type == .began { pause(); return }
        let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
        if options.contains(.shouldResume) { resume() }
    }

    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in guard let self else { return .commandFailed }; self.isPlaying ? self.pause() : self.resume(); return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.playNext(); return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.playPrevious(); return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }; self?.seek(to: event.positionTime); return .success }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if !song.artist.isEmpty { info[MPMediaItemPropertyArtist] = song.artist }
        if !song.album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = song.album }
        if let nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        lastNowPlayingPositionUpdate = currentTime
        AppLog.debug(.metadata, "Centro de control actualizado: \(song.title)")
    }

    private func prepareNowPlayingArtwork(for song: Song) {
        guard nowPlayingArtworkSongID != song.id else { return }
        nowPlayingArtworkSongID = song.id
        nowPlayingArtwork = song.artworkData.flatMap(UIImage.init(data:)).map { image in
            MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
    }

    func saveState() {
        guard let song = currentSong else { UserDefaults.standard.removeObject(forKey: stateDefaultsKey); return }
        UserDefaults.standard.set(["songURL": song.url.absoluteString, "currentTime": currentTime, "isPlaying": isPlaying, "shuffle": isShuffleEnabled, "repeat": repeatMode.rawValue], forKey: stateDefaultsKey)
    }
    func restoreState(with songs: [Song]) {
        guard !hasRestored, let state = UserDefaults.standard.dictionary(forKey: stateDefaultsKey), let url = state["songURL"] as? String, let song = songs.first(where: { $0.url.absoluteString == url }) else { return }
        configureIfNeeded(); playlist = songs; currentIndex = songs.firstIndex(where: { $0.id == song.id }) ?? 0
        isShuffleEnabled = state["shuffle"] as? Bool ?? false
        repeatMode = RepeatMode(rawValue: state["repeat"] as? String ?? "") ?? .off
        playCurrentSong(startAt: state["currentTime"] as? TimeInterval ?? 0, shouldPlay: state["isPlaying"] as? Bool ?? false); hasRestored = true
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

private enum PlaybackError: LocalizedError { case invalidAudioFile
    var errorDescription: String? { "El archivo no contiene muestras reproducibles." }
}
