import Foundation
import AVFoundation
import MediaPlayer

class AudioEngine: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentSong: Song?
    @Published var currentRouteName: String = "Altavoz"

    private var playlist: [Song] = []
    private(set) var currentIndex: Int = 0

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var displayTimer: Timer?
    private var sampleRate: Double = 44100
    private var seekOffset: TimeInterval = 0

    private let stateDefaultsKey = "com.aurora.playbackState"
    private var hasRestored: Bool = false

    override init() {
        super.init()
        setupSession()
        setupEngine()
        observeRouteChanges()
        observeInterruptions()
        setupRemoteCommandCenter()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    private func setupSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            updateRouteName()
        } catch {
            print("Error configurando AVAudioSession: \(error.localizedDescription)")
        }
    }

    private func setupEngine() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
    }

    func play(song: Song, from playlist: [Song]? = nil) {
        if let playlist = playlist {
            self.playlist = playlist
            if let index = playlist.firstIndex(where: { $0.id == song.id }) {
                currentIndex = index
            } else {
                self.playlist.insert(song, at: 0)
                currentIndex = 0
            }
        } else {
            self.playlist = [song]
            currentIndex = 0
        }
        playCurrentSong()
        saveState()
    }

    private func playCurrentSong() {
        guard currentIndex >= 0 && currentIndex < playlist.count else {
            stop()
            return
        }

        let song = playlist[currentIndex]
        stop()

        do {
            let file = try AVAudioFile(forReading: song.url)
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            duration = Double(file.length) / sampleRate

            engine.disconnectNodeInput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)

            if !engine.isRunning {
                try engine.start()
            }

            scheduleFile(file, from: 0)

            currentSong = song
            seekOffset = 0
            isPlaying = true
            startDisplayTimer()
            updateNowPlayingInfo()
            saveState()
        } catch {
            print("Error al reproducir \(song.title): \(error.localizedDescription)")
            playNext()
        }
    }

    private func scheduleFile(_ file: AVAudioFile, from startFrame: AVAudioFramePosition) {
        playerNode.stop()

        let framesToPlay = AVAudioFrameCount(file.length - startFrame)
        guard framesToPlay > 0 else {
            playNext()
            return
        }

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: framesToPlay,
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.handlePlaybackFinished()
            }
        }

        playerNode.play()
    }

    func playNext() {
        guard !playlist.isEmpty else { return }
        let nextIndex = currentIndex + 1
        guard nextIndex < playlist.count else {
            stop()
            return
        }
        currentIndex = nextIndex
        playCurrentSong()
    }

    func playPrevious() {
        guard !playlist.isEmpty else { return }
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        let prevIndex = currentIndex - 1
        guard prevIndex >= 0 else { return }
        currentIndex = prevIndex
        playCurrentSong()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopDisplayTimer()
        updateNowPlayingInfo()
        saveState()
    }

    func resume() {
        guard audioFile != nil else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        playerNode.play()
        isPlaying = true
        startDisplayTimer()
        updateNowPlayingInfo()
        saveState()
    }

    func stop() {
        playerNode.stop()
        audioFile = nil
        isPlaying = false
        currentTime = 0
        seekOffset = 0
        stopDisplayTimer()
    }

    func seek(to time: TimeInterval) {
        guard let file = audioFile else { return }
        let clampedTime = max(0, min(time, duration))
        let startFrame = AVAudioFramePosition(clampedTime * sampleRate)

        seekOffset = clampedTime
        scheduleFile(file, from: startFrame)
        currentTime = clampedTime

        if !isPlaying {
            playerNode.pause()
        }

        updateNowPlayingInfo()
        saveState()
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func updateCurrentTime() {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }

        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        currentTime = seekOffset + elapsed
    }

    private func handlePlaybackFinished() {
        if isPlaying {
            playNext()
        } else {
            isPlaying = false
            currentTime = 0
            stopDisplayTimer()
            updateNowPlayingInfo()
            saveState()
        }
    }

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        updateRouteName()
    }

    private func updateRouteName() {
        let session = AVAudioSession.sharedInstance()
        guard let output = session.currentRoute.outputs.first else { return }

        DispatchQueue.main.async {
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                self.currentRouteName = "Bluetooth: \(output.portName)"
            case .headphones:
                self.currentRouteName = "Audífonos (Jack 3.5mm): \(output.portName)"
            case .builtInSpeaker:
                self.currentRouteName = "Altavoz"
            default:
                self.currentRouteName = output.portName
            }
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            if isPlaying { pause() }
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, self.currentSong != nil else { return .noActionableNowPlayingItem }
            self.resume()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self, self.currentSong != nil else { return .noActionableNowPlayingItem }
            self.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self, self.currentSong != nil else { return .noActionableNowPlayingItem }
            if self.isPlaying {
                self.pause()
            } else {
                self.resume()
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.playNext()
            return .success
        }
        commandCenter.nextTrackCommand.isEnabled = true

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.playPrevious()
            return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

       let info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func saveState() {
        guard let song = currentSong else {
            UserDefaults.standard.removeObject(forKey: stateDefaultsKey)
            return
        }

        let state: [String: Any] = [
            "songID": song.id.uuidString,
            "currentTime": currentTime,
            "isPlaying": isPlaying,
            "duration": duration
        ]
        UserDefaults.standard.set(state, forKey: stateDefaultsKey)
    }

    func restoreState(with allSongs: [Song]) {
        guard !hasRestored else { return }
        guard let state = UserDefaults.standard.dictionary(forKey: stateDefaultsKey) else { return }
        guard let songIDString = state["songID"] as? String,
              let songID = UUID(uuidString: songIDString),
              let song = allSongs.first(where: { $0.id == songID }) else {
            UserDefaults.standard.removeObject(forKey: stateDefaultsKey)
            return
        }

        let savedTime = state["currentTime"] as? TimeInterval ?? 0
        let wasPlaying = state["isPlaying"] as? Bool ?? false

        self.playlist = allSongs
        if let index = allSongs.firstIndex(where: { $0.id == songID }) {
            self.currentIndex = index
        } else {
            self.playlist.insert(song, at: 0)
            self.currentIndex = 0
        }

        do {
            let file = try AVAudioFile(forReading: song.url)
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            duration = Double(file.length) / sampleRate

            engine.disconnectNodeInput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)

            if !engine.isRunning {
                try engine.start()
            }

            let startFrame = AVAudioFramePosition(savedTime * sampleRate)
            scheduleFile(file, from: startFrame)

            currentSong = song
            seekOffset = savedTime
            currentTime = savedTime

            if wasPlaying {
                playerNode.play()
                isPlaying = true
                startDisplayTimer()
            } else {
                playerNode.pause()
                isPlaying = false
            }

            updateNowPlayingInfo()
            hasRestored = true
        } catch {
            print("Error al restaurar estado: \(error.localizedDescription)")
            UserDefaults.standard.removeObject(forKey: stateDefaultsKey)
        }
    }

    @objc private func applicationWillResignActive() {
        saveState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}