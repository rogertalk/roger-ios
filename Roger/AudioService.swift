import Alamofire
import AVFoundation
import Crashlytics
import UIKit

private class Player: NSObject, AVAudioPlayerDelegate {
    enum State {
        case loading, playing, done
    }

    let playedChunk = Event<PlayableChunk>()
    var queue: [PlayableChunk]

    /// An event that is triggered every time the state changes. The event value is *the old state* (for the new state, read the `state` property).
    let stateChanged = Event<State>()

    var currentTime: TimeInterval {
        return self.audioPlayer?.currentTime ?? 0
    }

    var currentRate: Float {
        didSet {
            self.audioPlayer?.rate = self.currentRate
        }
    }

    /// The total duration of the chunks that have been played so far.
    private(set) var playedChunksDuration = 0

    deinit {
        self.loadingTimer?.invalidate()
    }

    init(items: [PlayableChunk]) {
        self.queue = items
        self.currentIndex = self.queue.count - 1
        self.currentRate = SettingsManager.playbackRate
        AudioService.instance.currentChunkChanged.emit()
        super.init()
    }

    // MARK: - AVAudioPlayer delegate

    @objc func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.skipNext()
    }

    func play(_ startAt: Int64? = nil) {
        // Set the currentIndex based on the given start time in the queue.
        var offset = 0.0
        if let startPosition = startAt {
            for i in 0 ..< queue.count {
                let chunk = queue[i]
                if chunk.end > startPosition {
                    offset = max(0.0, Double(startPosition - chunk.start) / 1000)
                    self.currentIndex = i
                    break
                }
            }
        }

        // Try to play the appropriate chunk.
        guard AudioService.instance.hasCachedAudioURL(self.currentChunk.audioURL as URL) else {
            // Begin download if it is not already cached
            AudioService.instance.cacheRemoteAudioURL(self.currentChunk.audioURL as URL)
            if self.loadingTimer == nil {
                self.loadingTimer = Timer.scheduledTimer(
                    timeInterval: 0.3, target: self, selector: #selector(Player.tryPlayChunk), userInfo: nil, repeats: true)
                self.state = .loading
            }
            return
        }

        let localURL = AudioService.instance.getLocalAudioURL(self.currentChunk.audioURL as URL)

        // Ensure this file is playable
        guard AVAsset(url: localURL).isPlayable else {
            self.skipNext()
            return
        }
        // Setup and play the current chunk.
        self.audioPlayer?.stop()
        NSLog("Attempting playback")

        if let player = try? AVAudioPlayer(contentsOf: localURL) {
            // Setup new player
            player.currentTime = offset
            player.delegate = self
            player.isMeteringEnabled = true
            player.enableRate = true
            player.rate = self.currentRate
            player.play()
            self.audioPlayer = player
            self.state = .playing

            // Set back to default mode for maximum volume output
            _ = try? AVAudioSession.sharedInstance().setMode(AVAudioSessionModeDefault)
            if AudioService.instance.usingLoudspeaker {
                _ = try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
            }
        } else {
            NSLog("Failed to load URL %@", localURL.absoluteString)
        }
    }

    /// Check whether this chunk has been properly downloaded before attempting playback
    private dynamic func tryPlayChunk() {
        guard AudioService.instance.hasCachedAudioURL(self.currentChunk.audioURL as URL) else {
            return
        }
        // Clear this if it was running.
        self.loadingTimer?.invalidate()
        self.loadingTimer = nil
        self.play()
    }

    // Refactor to make this recursive
    func rewind(_ seconds: TimeInterval = 5) {
        var newTime: TimeInterval = 0
        defer {
            self.audioPlayer?.currentTime = newTime
        }
        if self.currentTime > seconds * 1.6 {
            newTime = self.currentTime - seconds
        } else if self.currentTime > seconds * 0.6 {
            newTime = 0
        } else {
            // Ensure there are previous chunks to rewind to.
            guard self.currentIndex > 0 else {
                return
            }
            // Switch to the previous chunk.
            self.currentIndex -= 1
            newTime = max(0, Double(self.currentChunk.duration / 1000) - seconds)
            self.play()
        }
    }

    func forward(_ seconds: TimeInterval = 5) {
        guard self.currentTime + seconds < Double(self.currentChunk.duration / 1000) else {
            self.skipNext()
            return
        }
        self.audioPlayer?.currentTime += seconds
    }

    func skipPrevious() {
        self.currentIndex = max(0, self.currentIndex - 1)
        self.audioPlayer?.currentTime = 0
        self.play()
    }

    func skipNext() {
        // Let listeners know that a chunk was played.
        self.playedChunksDuration += self.currentChunk.duration
        self.playedChunk.emit(self.currentChunk)

        // Ensure there are chunks to forward to.
        guard self.currentIndex < self.queue.count - 1 else {
            self.stop()
            return
        }

        NSLog("Play next")
        // Move to the next item in the queue.
        self.currentIndex += 1
        self.play()
    }

    func stop() {
        self.state = .done
        self.audioPlayer?.stop()
        self.loadingTimer?.invalidate()
        self.loadingTimer = nil
    }

    func getRemainingPlayDuration() -> Double {
        var duration = 0.0
        // Add up the duration of unplayed chunks
        for i in self.currentIndex ..< self.queue.count {
            duration += Double(self.queue[i].duration) / 1000
        }
        return duration - (self.audioPlayer?.currentTime ?? 0)
    }

    // MARK: - Private

    private var currentIndex: Int = 0 {
        didSet {
            guard self.queue[oldValue].senderId != self.currentChunk.senderId else {
                return
            }
            AudioService.instance.currentChunkChanged.emit()
        }
    }

    fileprivate var currentChunk: PlayableChunk {
        return self.queue[self.currentIndex]
    }

    private var loadingTimer: Timer?

    /// The current state of the player.
    private(set) var state = State.done {
        didSet {
            if self.state == oldValue {
                return
            }
            self.stateChanged.emit(oldValue)
        }
    }

    fileprivate var audioPlayer: AVAudioPlayer?
}

// MARK: -

class AudioService {
    enum State {
        case unknown
        case idle
        case playing(ready: Bool)
        case recording
    }

    static let instance = AudioService()

    var audioLevel: Double {
        switch self.state {
        case .playing:
            // Smooth out changes in the audio level
            // Grow instantly but smooth out decreases in level
            var level: Double = 0
            if let audioPlayer = self.player?.audioPlayer {
                audioPlayer.updateMeters()
                level = pow(10, Double(audioPlayer.averagePower(forChannel: 0)) / 40)
            }
            return level
        case .recording:
            self.recorder.updateMeters()
            return pow(10, Double(self.recorder.averagePower(forChannel: 0)) / 40)
        default:
            return 0
        }
    }

    var canRecord: Bool {
        // Note: The iPhone simulator always allows microphone access.
        return TARGET_OS_SIMULATOR != 0 || AVAudioSession.sharedInstance().recordPermission() == .granted
    }

    /// The stream that is currently being acted on by the audio service.
    private(set) var currentStream: Stream? {
        didSet {
            oldValue?.changed.removeListener(self)
            self.currentStream?.changed.addListener(self, method: AudioService.streamChanged)
        }
    }

    var currentChunk: PlayableChunk? {
        return self.player?.currentChunk
    }

    /// How many seconds have been recorded.
    var recordedDuration: Double {
        guard let start = self.recordingStarted else {
            return 0
        }
        return CACurrentMediaTime() - start
    }

    /// How many seconds are left to play.
    var remainingPlayDuration: Double {
        guard let player = self.player else {
            return 0
        }
        return player.getRemainingPlayDuration()
    }

    /// Whether the loudspeaker is currently being used.
    private(set) var usingLoudspeaker = false
    /// Whether headphones are currently connected.
    var deviceConnected: Bool {
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains
            {
                switch $0.portType {
                    case AVAudioSessionPortHeadphones,
                         AVAudioSessionPortLineOut,
                         AVAudioSessionPortBluetoothA2DP,
                         AVAudioSessionPortBluetoothHFP,
                         AVAudioSessionPortCarAudio,
                         AVAudioSessionPortAirPlay:
                    return true
                default:
                    return false
                }
        }
    }

    /// The current state of the audio.
    private(set) var state = State.idle {
        didSet {
            SettingsManager.updateScreenAutolockEnabled()
            self.stateChanged.emit(oldValue)
        }
    }

    /// Emitted when the loudspeaker is turned on/off.
    let loudspeakerChanged = Event<Void>()
    /// Emitted when headphones or another device is connected
    let routeChanged = Event<Void>()

    /// An event that is posted whenever the audio state changes. The event value is *the old state* (for the new state, read the `state` property).
    let stateChanged = Event<State>()
    /// Posted whenever the currently playing chunk changes
    let currentChunkChanged = Event<Void>()

    /// Requests that the specified audio URL is cached locally.
    func cacheRemoteAudioURL(_ url: URL, callback: ((Bool) -> Void)? = nil) {
        // Don't "download" from the file system and avoid duplicate downloads.
        if url.isFileURL || self.hasCachedAudioURL(url) || self.pendingDownloads.contains(url) {
            callback?(false)
            return
        }
        NSLog("[AudioService] %@", "Downloading \(url)")
        self.pendingDownloads.insert(url)
        // Start a download which will move the audio file to the cache directory when done.
        // TODO: Verify that Alamofire uses background transfer.
        let request = Alamofire.download(url, method: .get, parameters: nil, encoding: URLEncoding.default, headers: nil, to: {
            (_, _) -> (URL, DownloadRequest.DownloadOptions) in
            // Return the path on disk where the audio file should be stored.
            return (self.getLocalAudioURL(url), [])
        })
        request.response(completionHandler: {
            self.pendingDownloads.remove(url)
            if let error = $0.error {
                NSLog("[AudioService] %@", "Download failed: \(error) (\(url))")
                callback?(false)
            } else {
                NSLog("[AudioService] %@", "Download completed: \(url)")
                callback?(true)
            }
        })
    }

    /// Gets how many seconds of audio there is to play for the specified stream.
    func getPlayDuration(_ stream: Stream) -> Double {
        let lastPlayPosition = SettingsManager.getPlayPosition(stream) ?? 0
        var duration = 0
        for chunk in stream.getUnplayedChunks() {
            if chunk.end < lastPlayPosition {
                continue
            }

            duration += chunk.duration
            // Subtract any part of the chunk that has already been played
            if chunk.start < lastPlayPosition {
                duration -= (lastPlayPosition - chunk.start)
            }
        }
        return Double(duration) / 1000
    }

    func getPlayDuration(_ profile: Profile) -> Double {
        let milliseconds = profile.greeting?.duration ?? 0
        return Double(milliseconds) / 1000
    }

    func playProfile(_ profile: Profile, preferLoudspeaker: Bool = false, reason: String = "Other") {
        self.stop(reason: "StartedPlaying")
        guard let chunk = profile.greeting else {
            return
        }
        self.updateAudioRoutes(preferLoudspeaker: preferLoudspeaker)
        self.player = Player(items: [chunk])
        self.state = .playing(ready: false)
        self.playingStateEntered = CACurrentMediaTime()
        Answers.logCustomEvent(withName: "Start Playing", customAttributes: [
            "Duration": chunk.duration,
            "Reason": reason,
            "Stream": "No"
            ])
        self.player?.play()
    }

    /// Starts loading/playing the specified stream.
    func playStream(_ stream: Stream, preferLoudspeaker: Bool = false, reason: String = "Other") {
        self.stop(reason: "StartedPlaying")
        let interrupted = self.interruptedStream != nil
        self.interruptedStream = nil
        let chunksToPlay = stream.getPlayableChunks()
        if chunksToPlay.isEmpty {
            // There is nothing to play, so stop here.
            return
        }

        // Ensure we have a proper session
        guard self.updateAudioRoutes(preferLoudspeaker: preferLoudspeaker) else {
            return
        }

        self.currentStream = stream
        // Create the queue player which will play the audio, containing all known chunks.
        let player = Player(items: chunksToPlay)
        self.player = player
        self.state = .playing(ready: false)
        self.playingStateEntered = CACurrentMediaTime()
        // Only consider last play position of unheard streams.
        let savedPosition = SettingsManager.getPlayPosition(stream) ?? 0 - 1000
        let startPosition = interrupted ? savedPosition : max(stream.playedUntil, savedPosition)
        player.play(startPosition)
        // Report to the backend that the user is listening.
        let remainingDuration = player.getRemainingPlayDuration()
        stream.reportStatus(.Listening, estimatedDuration: Int(remainingDuration * 1000))

        // Clear any notifications related to the played stream, if the app is in the foreground
        if UIApplication.shared.applicationState == .active {
            Responder.clearStreamNotifications(stream.id)
        }

        // Log whenever streams are played.
        Answers.logCustomEvent(withName: "Start Playing", customAttributes: [
            "Duration": remainingDuration,
            "Reason": reason,
            "Stream": "Yes",
            "Unplayed": stream.unplayed ? "Yes" : "No",
        ])
    }

    func rewind() {
        guard let player = self.player , player.state == .playing else {
            return
        }
        player.rewind()
    }

    func cyclePlaybackRate() -> Float {
        guard let player = self.player, let rate = self.player?.currentRate , player.state == .playing else {
            return 0
        }

        var newRate: Float = 1.0
        if rate == 1 {
            newRate = 1.5
        } else if rate == 1.5 {
            newRate = 2
        }

        player.currentRate = newRate
        return newRate
    }

    func skipPrevious() {
        guard let player = self.player , player.state == .playing else {
            return
        }
        player.skipPrevious()
    }

    func skipNext() {
        guard let player = self.player , player.state == .playing else {
            return
        }
        player.skipNext()
    }

    func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    }

    /// Begins recording for the specified stream. Once asked to stop, the recording will be sent to the stream (unless cancelled).
    func startRecording(_ stream: Stream?, reason: String = "Other") {
        if case .playing = self.state {
            self.stopPlaying()
            self.interruptedStream = stream
        }

        if !self.canRecord {
            // TODO: Event?
            print("WARNING: Did not start recording because we don't have permission to do so")
            return
        }

        // Ensure we have a proper session
        guard self.updateAudioRoutes(isPlayback: false, preferLoudspeaker: true) else {
            return
        }

        // Play a sound to indicate that recording started.
        self.bleepSound.play()
        // Attempt to begin recording.
        if !self.recorder.record() {
            // TODO: Event?
            print("ERROR: Failed to begin recording")
            return
        }

        // Ensure mode is default for proper volume
        _ = try? AVAudioSession.sharedInstance().setMode(AVAudioSessionModeDefault)
        // Set up the new state now that we're recording.
        self.currentStream = stream
        self.recordingStarted = CACurrentMediaTime()
        self.state = .recording

        // Report to the backend that the user is talking.
        stream?.reportStatus(.Talking)
        // Log that recording started.
        Answers.logCustomEvent(withName: "Start Recording", customAttributes: [
            "Reason": reason,
            "HasStream": stream == nil,
            "StreamUnplayed": stream?.unplayed ?? false,
        ])
    }

    /// Requests recording permission from the user if necessary. If the user has previously declined permissions, this will send them to the Settings app.
    func requestRecordingPermission(_ callback: ((_ canRecord: Bool) -> Void)?) {
        if self.canRecord {
            // No need to do anything.
            callback?(true)
            return
        }
        let session = AVAudioSession.sharedInstance()
        if session.recordPermission() == .denied {
            // We can't ask for permission so send the user to the Settings app.
            // TODO: Pop an explanation dialog before we take them out of the app?
            callback?(false)
            UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
            Answers.logCustomEvent(withName: "User Sent To System Preferences", customAttributes: ["Reason": "Microphone", "Source": "AudioService"])
            return
        }
        session.requestRecordPermission() { granted in
            guard let callback = callback else {
                return
            }
            DispatchQueue.main.async {
                callback(true)
            }
        }
    }

    /// Stops either playback or recording, depending on which is active.
    func stop(reason: String = "Other") {
        self.stopPlaying(reason: reason)
        self.stopRecording(reason: reason)
    }

    /// Stops playback of any audio that is currently playing.
    func stopPlaying(interrupted: Bool = false, reason: String = "Other") {
        guard case .playing = self.state else {
            return
        }
        defer {
            self.resetState()
        }

        guard let stream = self.currentStream else {
            self.player?.stop()
            self.player = nil
            return
        }

        if interrupted {
            self.interruptedStream = stream
        }

        // Report to the backend that the user is no longer listening.
        stream.reportStatus(.Idle)

        // Mark the stream as played and report statistics regarding playback.
        let totalPlayed: Double
        if let player = self.player {
            // TODO: See if this can be encapsulated in AlexaStream class.
            if stream is AlexaStream {
                // Mark Alexa streams completely listened when stopping playback.
                if let end = stream.chunks.last?.end {
                    stream.setPlayedUntil(end)
                }
            } else {
                // Otherwise, set the play position and set playeduntil
                if let lastChunk = self.lastPlayedChunk as? Chunk, lastChunk.streamId == stream.id {
                    stream.setPlayedUntil(lastChunk.end)
                }

                // If played all the way through, clear saved position
                if player.state == .done {
                    SettingsManager.clearPlayPosition(stream)
                } else {
                    SettingsManager.setPlayPosition(stream, time: player.currentChunk.start + Int64(player.currentTime * 1000))
                }
            }
            totalPlayed = Double(player.playedChunksDuration) / 1000
            self.player = nil
            player.stop()
        } else {
            totalPlayed = 0
        }

        let timeSpent: Double
        if let startTime = self.playingStateEntered {
            self.playingStateEntered = nil
            timeSpent = CACurrentMediaTime() - startTime
        } else {
            timeSpent = totalPlayed
        }

        Answers.logCustomEvent(withName: "Playing Completed", customAttributes: [
            "Overhead": timeSpent - totalPlayed,
            "Time Spent": timeSpent,
            "Reason": reason,
        ])
    }

    /// Stops any recording currently active and sends it unless explicitly cancelled.
    func stopRecording(cancel: Bool = false, reason: String = "Other") {
        guard case .recording = self.state else {
            return
        }
        defer {
            self.resetState()
            if let stream = self.interruptedStream {
                // Resume playback
                self.playStream(stream, preferLoudspeaker: self.usingLoudspeaker, reason: "Interrupted")
            }
        }

        // Stop recorder
        self.recorder.stop()

        let duration = CACurrentMediaTime() - self.recordingStarted!
        if cancel {
            // TODO: Event?
            print("Recording was canceled")
            // Log that recording was canceled.
            Answers.logCustomEvent(withName: "Recording Canceled", customAttributes: [
                "Reason": reason,
            ])
            return
        }
        // Copy the recorded audio file to a new location so that it can safely be uploaded even if another recording is made.
        let audioURL = URL.temporaryFileURL("m4a")
        do {
            try FileManager.default.copyItem(at: self.recorder.url, to: audioURL)
            self.recorder.deleteRecording()
        } catch {
            print("ERROR: Failed to copy recorded audio: \(error)")
            return
        }

        // Log that recording completed.
        Answers.logCustomEvent(withName: "Recording Complete", customAttributes: [
            "Duration": duration,
            "Reason": reason,
        ])

        if UIAccessibilityIsVoiceOverRunning() {
            self.sentSound.play()
        }

        // Alert the UI that the chunk is ready
        guard let stream = self.currentStream else {
            return
        }

        // Include a public access chunk token if any participant is not active or if this is the share stream
        let chunk = Intent.Chunk(audioURL: audioURL, duration: Int(duration * 1000), token: nil)
        stream.sendChunk(chunk, callback: nil)
        stream.reportStatus(.Idle)
    }

    // MARK: Private

    // Sounds.
    private let bleepSound: AVAudioPlayer
    private let doneSound: AVAudioPlayer
    private let sentSound: AVAudioPlayer
    private let earpieceBleepSound: AVAudioPlayer
    private let loadingSound: AVAudioPlayer
    private let rogerNotificationSound: AVAudioPlayer

    // Cache related values.
    /// The file URL to the local directory where audio is cached.
    private let cacheDirectoryURL: URL
    /// How long (in hours) to keep files in the cache before removing them
    private let cacheLifetime = 48.0
    /// Set for keeping track of the URLs of downloads which are in flight.
    private var pendingDownloads = Set<URL>()

    // Recording stuff.
    private let recorder: AVAudioRecorder
    private var recordingStarted: CFTimeInterval!

    // Playback stuff.
    private var didSetupAudio = false
    /// The last completely played chunk, useful for reporting.
    private var lastPlayedChunk: PlayableChunk?
    private var otherAudioPlaying = false
    private var playbackLevel: Float = 0
    private var interruptedStream: Stream?

    /// The current player for playing back chunks.
    private var player: Player? {
        didSet {
            oldValue?.playedChunk.removeListener(self)
            oldValue?.stateChanged.removeListener(self)
            self.player?.playedChunk.addListener(self, method: AudioService.handlePlayedChunk)
            self.player?.stateChanged.addListener(self, method: AudioService.handlePlayerStateChange)
        }
    }

    private var playingStateEntered: CFTimeInterval?
    
    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectoryURL = caches.appendingPathComponent("RogerAudioCache")

        // Recording initialization.
        let settings = [
            AVSampleRateKey: NSNumber(value: 44100.0 as Float),
            AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC as UInt32),
            AVNumberOfChannelsKey: NSNumber(value: 1 as Int32),
            AVEncoderAudioQualityKey: NSNumber(value: AVAudioQuality.medium.rawValue as Int),
        ]
        self.recorder = try! AVAudioRecorder(url: URL.temporaryFileURL("m4a"), settings: settings)
        self.recorder.isMeteringEnabled = true

        // Set to .MixWithOthers to prevent music shutdown
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback, with: [.mixWithOthers])
        } catch {
            print("ERROR: Couldn't set audio session category")
        }

        let bleepSoundURL = Bundle.main.url(forResource: "bleep", withExtension: "mp3")!
        self.bleepSound = try! AVAudioPlayer(contentsOf: bleepSoundURL)
        self.bleepSound.prepareToPlay()

        let doneSoundURL = Bundle.main.url(forResource: "done", withExtension: "mp3")!
        self.doneSound = try! AVAudioPlayer(contentsOf: doneSoundURL)
        self.doneSound.prepareToPlay()

        let sentSoundURL = Bundle.main.url(forResource: "sent", withExtension: "mp3")!
        self.sentSound = try! AVAudioPlayer(contentsOf: sentSoundURL)
        self.sentSound.prepareToPlay()

        let earpieceBleepSoundURL = Bundle.main.url(forResource: "ear_beep", withExtension: "mp3")!
        self.earpieceBleepSound = try! AVAudioPlayer(contentsOf: earpieceBleepSoundURL)
        self.earpieceBleepSound.numberOfLoops = 0
        self.earpieceBleepSound.prepareToPlay()

        let loadingSoundURL = Bundle.main.url(forResource: "loading", withExtension: "mp3")!
        self.loadingSound = try! AVAudioPlayer(contentsOf: loadingSoundURL)
        self.loadingSound.prepareToPlay()

        let rogerNotificationSound = Bundle.main.url(forResource: "roger", withExtension: "mp3")
        self.rogerNotificationSound = try! AVAudioPlayer(contentsOf: rogerNotificationSound!)
        self.rogerNotificationSound.prepareToPlay()

        // Listen for interruptions (eg. phone calls)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(AudioService.handleAudioSessionInterruption(_:)),
            name: NSNotification.Name.AVAudioSessionInterruption,
            object: nil)

        // Listen for route changes
        NotificationCenter.default.addObserver(self, selector: #selector(AudioService.handleRouteChanged(_:)), name: NSNotification.Name.AVAudioSessionRouteChange, object: nil)

        self.setVolumes()

        // Ensure that the cache directory exists.
        let fs = FileManager.default
        if !fs.fileExists(atPath: self.cacheDirectoryURL.path) {
            try! fs.createDirectory(at: self.cacheDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }

        // Kick off a background worker to prune the caches directory of stale files.
        DispatchQueue.global(qos: .background).async {
            self.pruneCacheDirectories()
        }

        // Listen for changes to streams.
        StreamService.instance.changed.addListener(self, method: AudioService.streamsChanged)

        // Listen for screen lock event.
        Responder.userLockedScreen.addListener(self, method: AudioService.handleUserDidLockScreen)

        ProximityMonitor.instance.changed.addListener(self, method: AudioService.handleProximityChange)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Returns `true` if the audio URL exists cached locally on disk; otherwise, `false`.
    fileprivate func hasCachedAudioURL(_ url: URL) -> Bool {
        let path = self.getLocalAudioURL(url).path
        if FileManager.default.fileExists(atPath: path) {
            return true
        } else {
            return false
        }
    }

    /// Converts a potentially remote audio URL to what it should be for the cache.
    fileprivate func getLocalAudioURL(_ url: URL) -> URL {
        // If the url is "*.m4a.aac", look for just ".m4a"
        let targetURL = url.pathExtension == "aac" ? url.deletingPathExtension() : url
        return self.cacheDirectoryURL.appendingPathComponent(targetURL.lastPathComponent)
    }

    private func handlePlayerStateChange(_ oldState: Player.State) {
        guard case .playing = self.state else {
            print("ERROR: Got player state change in state \(self.state)")
            return
        }
        switch self.player!.state {
        case .loading:
            self.state = .playing(ready: false)
            if !self.usingLoudspeaker || UIAccessibilityIsVoiceOverRunning() {
                self.loadingSound.numberOfLoops = -1
                self.loadingSound.play()
            }
            break
        case .playing:
            self.state = .playing(ready: true)
            self.loadingSound.stop()
            self.loadingSound.currentTime = 0
            break
        case .done:
            if !self.usingLoudspeaker {
                self.doneSound.play()
            }
            self.stopPlaying(reason: "PlaybackCompleted")
            break
        }
    }

    dynamic private func handleAudioSessionInterruption(_ notification: Foundation.Notification) {
        guard let interruptionType =
            (notification as NSNotification).userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber else {
            return
        }

        switch (self.state, interruptionType.uintValue) {
        case (.playing, AVAudioSessionInterruptionType.began.rawValue):
            self.stopPlaying(interrupted: true)
        case (.playing, AVAudioSessionInterruptionType.ended.rawValue):
            if let stream = self.interruptedStream {
                self.playStream(stream)
            }
        case (.recording, AVAudioSessionInterruptionType.began.rawValue):
            self.stopRecording(reason: "Interrupted")
        default:
            break
        }
    }

    dynamic private func handleRouteChanged(_ notification: Foundation.Notification) {
        guard let raw = (notification as NSNotification).userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSessionRouteChangeReason(rawValue: raw) else {
                return
        }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            // This usually means headphones were connected or disconnected.
            self.updateAudioRoutes(preferLoudspeaker: true)
        default:
            return
        }

        self.routeChanged.emit()
    }

    private func handleProximityChange(_ againstEar: Bool) {
        guard case .playing = self.state, againstEar && self.usingLoudspeaker else {
            return
        }

        self.updateAudioRoutes(isPlayback: true, preferLoudspeaker: false)
    }

    /// Called when the user locks the screen.
    private func handleUserDidLockScreen() {
        self.stopRecording(reason: "ScreenLocked")
    }

    private func handlePlayedChunk(_ chunk: PlayableChunk) {
        self.lastPlayedChunk = chunk
        // Re-report listening status as remaining duration may have changed due to incoming chunks.
        if let player = self.player, let stream = self.currentStream {
            let remainingDuration = player.getRemainingPlayDuration()
            if remainingDuration > 0.5 {
                stream.reportStatus(.Listening, estimatedDuration: Int(remainingDuration * 1000))
            }
        }
    }

    /// Remove stale files from the Caches directory.
    private func pruneCacheDirectories() {
        let fileManager = FileManager.default

        let prune: (URL) -> Void = { directory in
            do {
                for cacheName in try fileManager.contentsOfDirectory(atPath: directory.path) {
                    let cacheFullPath = directory.appendingPathComponent(cacheName).path
                    guard let creationDate = try? fileManager.attributesOfItem(atPath: cacheFullPath)[FileAttributeKey.creationDate] as! Date else {
                        continue
                    }

                    if (creationDate as NSDate).hoursAgo() >= self.cacheLifetime {
                        NSLog("[AudioService] %@", "Pruning: \(cacheFullPath) (\(creationDate))")
                        try fileManager.removeItem(atPath: cacheFullPath)
                    }
                }
            } catch {
                NSLog("[AudioService] %@", "Failed to prune caches directory: \(error)")
            }
        }

        // Clear the Cache and Temporary directories
        prune(self.cacheDirectoryURL)
        prune(URL(fileURLWithPath: NSTemporaryDirectory()))
    }

    private func releaseAudioSession() {
        // TODO: Investigate if this is the best solution.
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(NSEC_PER_SEC)) / Double(NSEC_PER_SEC)) {
            guard case .idle = self.state else {
                // The audio service is not idle, so don't release the session.
                return
            }

            do {
                // Activating/deactivating the audio session results in lag when starting playback/recording.
                // Only release the audio session if another app needs it.
                if self.otherAudioPlaying {
                    try AVAudioSession.sharedInstance().setActive(false, with: .notifyOthersOnDeactivation)
                } else {
                    self.updateAudioRoutes(isPlayback: false, preferLoudspeaker: true)
                }
            } catch {
                print("ERROR: Could not release audio session")
            }
        }
    }

    /// Resets the state of the audio service.
    private func resetState() {
        self.loadingSound.stop()
        self.loadingSound.currentTime = 0
        self.loadingSound.prepareToPlay()

        self.currentStream = nil
        self.lastPlayedChunk = nil
        self.recordingStarted = nil
        self.state = .idle
        self.releaseAudioSession()
    }

    private func setVolumes() {
        if UIAccessibilityIsVoiceOverRunning() {
            self.bleepSound.volume = 1
            self.sentSound.volume = 0.5
        } else {
            self.bleepSound.volume = 0.3
            self.sentSound.volume = 0.3
        }
        self.earpieceBleepSound.volume = 1
        self.loadingSound.volume = 0.2
        self.rogerNotificationSound.volume = 0.3
    }

    /// Fired when the currently playing stream has a change applied to it.
    private func streamChanged() {
        if case .playing = self.state {
            guard let newChunk = self.currentStream?.getUnplayedChunks().last as? Chunk else {
                return
            }
            DispatchQueue.main.async {
                guard let queue = self.player?.queue else {
                    return
                }

                let hasChunk = queue.contains {
                    guard let chunk = $0 as? Chunk else {
                        return false
                    }
                    return chunk.id == newChunk.id
                }

                guard !hasChunk else {
                    return
                }
                self.player?.queue.append(newChunk)
            }
        }
    }

    /// Fired when the list of recent streams changes.
    private func streamsChanged() {
        // Ensure that all chunks are cached.
        for stream in StreamService.instance.streams.values {
            for chunk in stream.getPlayableChunks() {
                self.cacheRemoteAudioURL(chunk.audioURL as URL)
            }
        }
    }

    /// Sets up audio routes and activates the audio session.
    @discardableResult
    private func updateAudioRoutes(isPlayback: Bool = true, preferLoudspeaker: Bool = false) -> Bool {
        if case .recording = self.state {
            return true
        }

        let session = AVAudioSession.sharedInstance()
        let hfpBluetoothConnected = AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: {
            return $0.portType == AVAudioSessionPortBluetoothHFP
        })
        let a2dpBluetoothConnected = AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: {
            return $0.portType == AVAudioSessionPortBluetoothA2DP
        })

        // Use the loudspeaker as long as headphones are not connected and the phone is not against the user's ear.
        let useSpeaker = preferLoudspeaker &&
            !(self.deviceConnected || hfpBluetoothConnected || a2dpBluetoothConnected)
        // Don't update the loudspeaker status for the recording state
        if useSpeaker != self.usingLoudspeaker && isPlayback {
            self.usingLoudspeaker = useSpeaker
            self.loudspeakerChanged.emit()
        }

        self.otherAudioPlaying = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
        do {
            // Some bluetooth devices require the "playback" category for smooth playback
            // The play & record category is needed for earpiece use
            var category: String
            var options: AVAudioSessionCategoryOptions
            if isPlayback && a2dpBluetoothConnected {
                category = AVAudioSessionCategoryPlayback
                options = []
            } else {
                category = AVAudioSessionCategoryPlayAndRecord
                options = [.allowBluetooth]
            }
            // VoiceChat mode is necessary for background autoplay
            if UIApplication.shared.applicationState != .active {
                _ = try? AVAudioSession.sharedInstance().setMode(AVAudioSessionModeVoiceChat)
            }
            try session.setCategory(category, with: options)
            try session.overrideOutputAudioPort(useSpeaker ? .speaker : .none)
            try session.setInputGain(0.7)
            // Set session active asynchronously to prevent UI lag
            DispatchQueue.global(qos: .default).async {
                do {
                    try session.setActive(true)
                } catch {
                    print("ERROR: Could not activate session")
                }
            }
            self.didSetupAudio = true
            // Play the the loading beep as an acknowledgement of earpiece mode
            if !useSpeaker && !self.deviceConnected {
                self.earpieceBleepSound.play()
            }
            #if DEBUG
                let route = useSpeaker ? "Loudspeaker" : (self.deviceConnected ? "Headphones" : "Earpiece")
                print("Audio route: \(route)")
            #endif
        } catch {
            print("ERROR: Failed to set up audio session: \(error)")
            return false
        }

        return true
    }
}
