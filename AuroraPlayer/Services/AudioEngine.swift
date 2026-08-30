import Foundation
import AVFoundation
import MediaPlayer
import UIKit

final class AudioEngine: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentSong: Song?
    @Published private(set) var currentRouteName = "Altavoz"

    // MARK: - Audio

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var audioFile: AVAudioFile?
    private var sampleRate: Double = 44_100

    // Tiempo desde donde fue programado el segmento actual.
    private var scheduledStartTime: TimeInterval = 0

    // MARK: - Queue

    private var playlist: [Song] = []
    private(set) var currentIndex: Int = 0

    // Identifica la reproducción/programación actual.
    // Sirve para ignorar callbacks viejos de AVAudioPlayerNode.
    private var playbackGeneration: UInt = 0

    private var isChangingTrack = false

    // MARK: - Timers

    private var displayTimer: Timer?

    // MARK: - Persistence

    private let stateDefaultsKey = "com.aurora.playbackState.v2"
    private var hasRestored = false

    // MARK: - Init

    override init() {
        super.init()

        setupAudioSession()
        setupAudioEngine()
        setupNotifications()
        setupRemoteCommands()

        updateRouteName()
    }

    deinit {
        displayTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)

        MPRemoteCommandCenter.shared().playCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.removeTarget(nil)
    }

    // MARK: - Setup

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: []
            )

            try session.setActive(true)

        } catch {
            print("AuroraPlayer AudioSession error:", error)
        }
    }

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)

        // Conectamos UNA SOLA VEZ.
        // No hay que desconectar/reconectar el nodo cada vez que cambia la canción.
        audioEngine.connect(
            playerNode,
            to: audioEngine.mainMixerNode,
            format: nil
        )

        audioEngine.prepare()
    }

    private func setupNotifications() {

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    // MARK: - Application lifecycle

    @objc private func applicationWillResignActive() {
        saveState()
        updateNowPlayingInfo()
    }

    // MARK: - Public playback API

    func play(song: Song, from songs: [Song]? = nil) {

        if let songs {
            playlist = songs

            if let index = songs.firstIndex(where: { $0.id == song.id }) {
                currentIndex = index
            } else {
                playlist.insert(song, at: 0)
                currentIndex = 0
            }

        } else {
            playlist = [song]
            currentIndex = 0
        }

        playCurrentSong(startAt: 0)
    }

    func pause() {

        guard isPlaying else {
            saveState()
            updateNowPlayingInfo()
            return
        }

        updateCurrentTime()

        playerNode.pause()

        isPlaying = false

        stopDisplayTimer()

        saveState()
        updateNowPlayingInfo()
    }

    func resume() {

        guard currentSong != nil,
              audioFile != nil else {
            return
        }

        do {
            try ensureAudioEngineRunning()
        } catch {
            print("AuroraPlayer resume error:", error)
            return
        }

        playerNode.play()

        isPlaying = true

        startDisplayTimer()

        saveState()
        updateNowPlayingInfo()
    }

    func stop() {

        // Invalidamos inmediatamente cualquier callback anterior.
        playbackGeneration &+= 1

        playerNode.stop()

        audioFile = nil

        isPlaying = false
        currentTime = 0
        scheduledStartTime = 0
        duration = 0

        stopDisplayTimer()

        saveState()
        updateNowPlayingInfo()
    }

    // MARK: - Next / Previous

    func playNext() {

        guard !isChangingTrack else {
            return
        }

        guard !playlist.isEmpty else {
            return
        }

        let nextIndex = currentIndex + 1

        guard nextIndex < playlist.count else {
            // Fin de la cola.
            playerNode.stop()

            isPlaying = false
            currentTime = duration

            stopDisplayTimer()

            saveState()
            updateNowPlayingInfo()

            return
        }

        isChangingTrack = true

        currentIndex = nextIndex

        // La siguiente canción empieza desde 0.
        playCurrentSong(startAt: 0)

        isChangingTrack = false
    }

    func playPrevious() {

        guard !isChangingTrack else {
            return
        }

        guard !playlist.isEmpty else {
            return
        }

        updateCurrentTime()

        // Comportamiento típico de reproductores:
        // si llevamos más de 3 segundos, vuelve al principio.
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }

        let previousIndex = currentIndex - 1

        guard previousIndex >= 0 else {
            seek(to: 0)
            return
        }

        isChangingTrack = true

        currentIndex = previousIndex

        playCurrentSong(startAt: 0)

        isChangingTrack = false
    }

    // MARK: - Current song

    private func playCurrentSong(startAt time: TimeInterval) {

        guard !playlist.isEmpty,
              currentIndex >= 0,
              currentIndex < playlist.count else {
            return
        }

        let song = playlist[currentIndex]

        // Invalidamos callbacks de la canción anterior.
        playbackGeneration &+= 1

        let generation = playbackGeneration

        // Detener lo anterior.
        playerNode.stop()
        stopDisplayTimer()

        do {

            let file = try AVAudioFile(forReading: song.url)

            let fileSampleRate = file.processingFormat.sampleRate
            let fileDuration = Double(file.length) / fileSampleRate

            guard file.length > 0,
                  fileDuration > 0 else {
                print("AuroraPlayer: archivo vacío:", song.title)

                handleInvalidCurrentSong(generation: generation)
                return
            }

            audioFile = file
            sampleRate = fileSampleRate
            duration = fileDuration

            currentSong = song

            let safeTime = max(
                0,
                min(time, fileDuration)
            )

            currentTime = safeTime
            scheduledStartTime = safeTime

            try ensureAudioEngineRunning()

            let startFrame = AVAudioFramePosition(
                safeTime * fileSampleRate
            )

            let framesAvailable = file.length - startFrame

            guard framesAvailable > 0 else {
                handlePlaybackFinished(
                    generation: generation
                )
                return
            }

            let frameCount = AVAudioFrameCount(
                min(
                    Int64(framesAvailable),
                    Int64(AVAudioFrameCount.max)
                )
            )

            playerNode.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: frameCount,
                at: nil
            ) { [weak self] in

                guard let self else {
                    return
                }

                DispatchQueue.main.async {

                    // MUY IMPORTANTE:
                    // si este callback pertenece a una canción anterior,
                    // lo ignoramos.
                    guard self.playbackGeneration == generation else {
                        return
                    }

                    self.handlePlaybackFinished(
                        generation: generation
                    )
                }
            }

            playerNode.play()

            isPlaying = true

            startDisplayTimer()

            updateNowPlayingInfo()
            saveState()

        } catch {

            print(
                "AuroraPlayer: no se pudo reproducir \(song.title):",
                error.localizedDescription
            )

            handleInvalidCurrentSong(
                generation: generation
            )
        }
    }

    private func handleInvalidCurrentSong(generation: UInt) {

        guard playbackGeneration == generation else {
            return
        }

        if currentIndex + 1 < playlist.count {
            currentIndex += 1
            playCurrentSong(startAt: 0)
        } else {
            isPlaying = false
            stopDisplayTimer()
            updateNowPlayingInfo()
            saveState()
        }
    }

    // MARK: - Playback completion

    private func handlePlaybackFinished(generation: UInt) {

        guard playbackGeneration == generation else {
            return
        }

        // Si el usuario pulsó pause/stop mientras se estaba ejecutando
        // el callback, NO debemos avanzar.
        guard isPlaying else {
            return
        }

        // Si estamos cambiando manualmente de canción, tampoco.
        guard !isChangingTrack else {
            return
        }

        // Evitamos que el callback vuelva a ejecutarse mientras
        // cambiamos de canción.
        isChangingTrack = true

        playerNode.stop()

        if currentIndex + 1 < playlist.count {

            currentIndex += 1

            isChangingTrack = false

            playCurrentSong(startAt: 0)

        } else {

            // Fin real de la cola.
            isChangingTrack = false

            isPlaying = false
            currentTime = duration

            stopDisplayTimer()

            saveState()
            updateNowPlayingInfo()
        }
    }

    // MARK: - Seeking

    func seek(to time: TimeInterval) {

        guard let file = audioFile else {
            return
        }

        let safeTime = max(
            0,
            min(time, duration)
        )

        let wasPlaying = isPlaying

        // Nueva generación: invalida el callback anterior.
        playbackGeneration &+= 1

        let generation = playbackGeneration

        playerNode.stop()

        scheduledStartTime = safeTime
        currentTime = safeTime

        do {

            try ensureAudioEngineRunning()

            let startFrame = AVAudioFramePosition(
                safeTime * sampleRate
            )

            let framesAvailable = file.length - startFrame

            guard framesAvailable > 0 else {
                isPlaying = false
                stopDisplayTimer()
                updateNowPlayingInfo()
                saveState()
                return
            }

            let frameCount = AVAudioFrameCount(
                min(
                    Int64(framesAvailable),
                    Int64(AVAudioFrameCount.max)
                )
            )

            playerNode.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: frameCount,
                at: nil
            ) { [weak self] in

                guard let self else {
                    return
                }

                DispatchQueue.main.async {

                    guard self.playbackGeneration == generation else {
                        return
                    }

                    self.handlePlaybackFinished(
                        generation: generation
                    )
                }
            }

            if wasPlaying {
                playerNode.play()
                isPlaying = true
                startDisplayTimer()
            } else {
                playerNode.pause()
                isPlaying = false
                stopDisplayTimer()
            }

            updateNowPlayingInfo()
            saveState()

        } catch {

            print("AuroraPlayer seek error:", error)
        }
    }

    // MARK: - Audio engine

    private func ensureAudioEngineRunning() throws {

        let session = AVAudioSession.sharedInstance()

        if !session.isOtherAudioPlaying {
            try session.setActive(
                true,
                options: []
            )
        }

        if !audioEngine.isRunning {
            audioEngine.prepare()
            try audioEngine.start()
        }
    }

    // MARK: - Progress

    private func startDisplayTimer() {

        stopDisplayTimer()

        displayTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in

            guard let self else {
                return
            }

            self.updateCurrentTime()
        }
    }

    private func stopDisplayTimer() {

        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func updateCurrentTime() {

        guard isPlaying,
              audioFile != nil,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(
                forNodeTime: nodeTime
              ),
              playerTime.sampleRate > 0 else {
            return
        }

        let elapsed = Double(
            playerTime.sampleTime
        ) / playerTime.sampleRate

        let newTime = scheduledStartTime + elapsed

        guard newTime >= 0 else {
            return
        }

        currentTime = min(
            newTime,
            duration
        )
    }

    // MARK: - Route

    @objc private func handleRouteChange(
        _ notification: Notification
    ) {
        updateRouteName()
    }

    private func updateRouteName() {

        let session = AVAudioSession.sharedInstance()

        guard let output = session.currentRoute.outputs.first else {
            return
        }

        DispatchQueue.main.async {

            switch output.portType {

            case .bluetoothA2DP,
                 .bluetoothHFP,
                 .bluetoothLE:

                self.currentRouteName =
                    "Bluetooth: \(output.portName)"

            case .headphones:

                self.currentRouteName =
                    "Audífonos: \(output.portName)"

            case .builtInSpeaker:

                self.currentRouteName = "Altavoz"

            default:

                self.currentRouteName =
                    output.portName
            }
        }
    }

    // MARK: - Interruptions

    @objc private func handleInterruption(
        _ notification: Notification
    ) {

        guard
            let info = notification.userInfo,
            let rawType =
                info[AVAudioSession.interruptionTypeKey]
                    as? UInt,
            let type =
                AVAudioSession.InterruptionType(
                    rawValue: rawType
                )
        else {
            return
        }

        switch type {

        case .began:

            if isPlaying {
                pause()
            }

        case .ended:

            guard
                let rawOptions =
                    info[
                        AVAudioSession
                            .interruptionOptionKey
                    ] as? UInt
            else {
                return
            }

            let options =
                AVAudioSession.InterruptionOptions(
                    rawValue: rawOptions
                )

            if options.contains(.shouldResume) {
                resume()
            }

        @unknown default:
            break
        }
    }

    // MARK: - Lock screen / Control Center

    private func setupRemoteCommands() {

        let center =
            MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget {
            [weak self] _ in

            guard let self,
                  self.currentSong != nil else {
                return .noActionableNowPlayingItem
            }

            self.resume()

            return .success
        }

        center.pauseCommand.addTarget {
            [weak self] _ in

            guard let self,
                  self.currentSong != nil else {
                return .noActionableNowPlayingItem
            }

            self.pause()

            return .success
        }

        center.togglePlayPauseCommand.addTarget {
            [weak self] _ in

            guard let self,
                  self.currentSong != nil else {
                return .noActionableNowPlayingItem
            }

            if self.isPlaying {
                self.pause()
            } else {
                self.resume()
            }

            return .success
        }

        center.nextTrackCommand.addTarget {
            [weak self] _ in

            guard let self else {
                return .commandFailed
            }

            self.playNext()

            return .success
        }

        center.previousTrackCommand.addTarget {
            [weak self] _ in

            guard let self else {
                return .commandFailed
            }

            self.playPrevious()

            return .success
        }

        center.changePlaybackPositionCommand.addTarget {
            [weak self] event in

            guard
                let self,
                let event =
                    event as?
                    MPChangePlaybackPositionCommandEvent
            else {
                return .commandFailed
            }

            self.seek(
                to: event.positionTime
            )

            return .success
        }
    }

    // MARK: - Now Playing

    private func updateNowPlayingInfo() {

        guard let song = currentSong else {

            MPNowPlayingInfoCenter
                .default()
                .nowPlayingInfo = nil

            return
        }

        let folderName =
            song.url
                .deletingLastPathComponent()
                .lastPathComponent

        // Si Song todavía no tiene metadatos ID3/metadata,
        // usamos la carpeta como artista/álbum provisional.
        let artist =
            folderName.isEmpty
            ? "Aurora Player"
            : folderName

        let album =
            folderName.isEmpty
            ? "Música local"
            : folderName

        var info: [String: Any] = [

            MPMediaItemPropertyTitle:
                song.title,

            MPMediaItemPropertyArtist:
                artist,

            MPMediaItemPropertyAlbumTitle:
                album,

            MPMediaItemPropertyPlaybackDuration:
                duration,

            MPNowPlayingInfoPropertyElapsedPlaybackTime:
                currentTime,

            MPNowPlayingInfoPropertyPlaybackRate:
                isPlaying ? 1.0 : 0.0
        ]

        // Artwork permanente.
        // No se elimina al pausar.
        if let artwork = makeDefaultArtwork() {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter
            .default()
            .nowPlayingInfo = info
    }

    private func makeDefaultArtwork()
        -> MPMediaItemArtwork? {

        guard
            let image =
                UIImage(
                    systemName:
                        "music.note"
                )
        else {
            return nil
        }

        let size =
            CGSize(
                width: 600,
                height: 600
            )

        return MPMediaItemArtwork(
            boundsSize: size
        ) { _ in
            return image
        }
    }

    // MARK: - Persistence

    private struct PlaybackState: Codable {

        let songID: String
        let currentIndex: Int
        let currentTime: TimeInterval
        let isPlaying: Bool
    }

    func saveState() {

        guard let song = currentSong else {
            return
        }

        // Actualizamos la posición antes de guardar.
        if isPlaying {
            updateCurrentTime()
        }

        let state = PlaybackState(
            songID: song.id.uuidString,
            currentIndex: currentIndex,
            currentTime: currentTime,
            isPlaying: isPlaying
        )

        do {

            let data =
                try JSONEncoder()
                    .encode(state)

            UserDefaults.standard.set(
                data,
                forKey: stateDefaultsKey
            )

        } catch {

            print(
                "AuroraPlayer save state error:",
                error
            )
        }
    }

    func restoreState(with allSongs: [Song]) {

        guard !hasRestored else {
            return
        }

        hasRestored = true

        guard
            let data =
                UserDefaults.standard.data(
                    forKey: stateDefaultsKey
                )
        else {
            return
        }

        do {

            let state =
                try JSONDecoder()
                    .decode(
                        PlaybackState.self,
                        from: data
                    )

            guard
                let songID =
                    UUID(
                        uuidString:
                            state.songID
                    ),
                let song =
                    allSongs.first(
                        where: {
                            $0.id == songID
                        }
                    )
            else {
                UserDefaults.standard.removeObject(
                    forKey: stateDefaultsKey
                )
                return
            }

            playlist = allSongs

            if let index =
                playlist.firstIndex(
                    where: {
                        $0.id == song.id
                    }
                ) {
                currentIndex = index
            } else {
                currentIndex =
                    max(
                        0,
                        min(
                            state.currentIndex,
                            max(playlist.count - 1, 0)
                        )
                    )
            }

            // Cargamos la canción pero respetamos
            // el estado guardado.
            loadSongForRestore(
                song: song,
                time: state.currentTime,
                shouldPlay: state.isPlaying
            )

        } catch {

            print(
                "AuroraPlayer restore state error:",
                error
            )

            UserDefaults.standard.removeObject(
                forKey: stateDefaultsKey
            )
        }
    }

    private func loadSongForRestore(
        song: Song,
        time: TimeInterval,
        shouldPlay: Bool
    ) {

        playbackGeneration &+= 1

        let generation =
            playbackGeneration

        playerNode.stop()
        stopDisplayTimer()

        do {

            let file =
                try AVAudioFile(
                    forReading: song.url
                )

            let rate =
                file.processingFormat.sampleRate

            let fileDuration =
                Double(file.length) / rate

            guard fileDuration > 0 else {
                return
            }

            audioFile = file
            sampleRate = rate
            duration = fileDuration
            currentSong = song

            let safeTime =
                max(
                    0,
                    min(
                        time,
                        fileDuration
                    )
                )

            currentTime = safeTime
            scheduledStartTime = safeTime

            try ensureAudioEngineRunning()

            let startFrame =
                AVAudioFramePosition(
                    safeTime * rate
                )

            let framesAvailable =
                file.length - startFrame

            guard framesAvailable > 0 else {
                isPlaying = false
                updateNowPlayingInfo()
                return
            }

            let frameCount =
                AVAudioFrameCount(
                    min(
                        Int64(framesAvailable),
                        Int64(AVAudioFrameCount.max)
                    )
                )

            playerNode.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: frameCount,
                at: nil
            ) { [weak self] in

                guard let self else {
                    return
                }

                DispatchQueue.main.async {

                    guard
                        self.playbackGeneration
                            == generation
                    else {
                        return
                    }

                    self.handlePlaybackFinished(
                        generation: generation
                    )
                }
            }

            if shouldPlay {

                playerNode.play()

                isPlaying = true

                startDisplayTimer()

            } else {

                playerNode.pause()

                isPlaying = false
            }

            updateNowPlayingInfo()

        } catch {

            print(
                "AuroraPlayer restore audio error:",
                error
            )
        }
    }
}