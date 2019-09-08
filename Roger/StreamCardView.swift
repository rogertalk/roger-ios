import Crashlytics
import DateTools
import FBSDKMessengerShareKit

protocol StreamCardDelegate {
    func cardLongPressed(_ point: CGPoint)
    func showTextPreview()
    func cardSwiped(_ direction: UISwipeGestureRecognizerDirection)
    func openStreamDetails()
    func showAttachment()
    // TODO: Kill?
    func instructionsActionTapped(_ result: InstructionsActionResult)
}

class StreamCardView: UIView, UITextFieldDelegate, AvatarViewDelegate {
    // Main avatar elements
    @IBOutlet weak var avatarView: AvatarView!
    @IBOutlet weak var earpieceHint: UILabel!
    @IBOutlet weak var playbackTimeHolderView: UIView!
    @IBOutlet weak var playbackTimeLabel: UILabel!
    @IBOutlet weak var timerOffsetConstraint: NSLayoutConstraint!
    @IBOutlet weak var titleField: UITextField!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var textPreviewButton: UIButton!
    @IBOutlet weak var attachButton: UIButton!
    @IBOutlet weak var newAttachmentIndicator: UIView!
    @IBOutlet weak var participantsCollectionView: StreamParticipantsCollectionView!
    @IBOutlet weak var createGroupLabel: UILabel!
    @IBOutlet weak var playbackControlsView: UIView!
    @IBOutlet weak var playbackRateButton: UIButton!
    @IBOutlet weak var streamControlsView: UIView!

    // Glimpses elements
    @IBOutlet weak var enableGlimpsesContainerView: UIView!
    @IBOutlet weak var glimpseInfoContainerView: UIView!
    @IBOutlet weak var temperatureLabel: UILabel!
    @IBOutlet weak var locationLabel: UILabel!
    @IBOutlet weak var weatherLabel: UILabel!
    @IBOutlet weak var localTimeLabel: UILabel!

    // Profile elements
    @IBOutlet weak var contactsContainerView: UIView!
    @IBOutlet weak var optionsContainerView: UIView!

    // Empty Group elements
    @IBOutlet weak var emptyGroupView: UIView!
    @IBOutlet weak var emptyGroupImageView: UIImageView!
    @IBOutlet weak var emptyGroupNameLabel: UILabel!

    var delegate: StreamCardDelegate?

    var stream: Stream? {
        didSet {
            if self.destroyed || oldValue === self.stream {
                return
            }
            // Listen for changes to the stream (and ignore changes to the previous stream, if any).
            oldValue?.changed.removeListener(self)
            self.stream?.changed.addListener(self, method: StreamCardView.refresh)
            // Make the view refresh itself with the new stream.
            self.refresh()
        }
    }

    var profile: Profile?

    // MARK: - Static

    static func create(_ stream: Stream, frame: CGRect, delegate: StreamCardDelegate?) -> StreamCardView {
        let view = Bundle.main.loadNibNamed("StreamCardView", owner: self, options: nil)?[0] as! StreamCardView
        view.frame = frame
        view.stream = stream
        view.delegate = delegate
        return view
    }

    static func create(_ profile: Profile, frame: CGRect, delegate: StreamCardDelegate?) -> StreamCardView {
        let view = Bundle.main.loadNibNamed("StreamCardView", owner: self, options: nil)?[0] as! StreamCardView
        view.avatarView.setImage(AvatarView.singlePersonImage)
        view.frame = frame
        view.profile = profile
        view.delegate = delegate
        view.refresh()
        return view
    }

    // MARK: -

    /// Retain count is borked, this at least avoids unnecessary performance hogging by unused cards.
    func destroy() {
        self.destroyed = true
        self.endEditing(true)
        self.removeFromSuperview()
        AudioService.instance.stateChanged.removeListener(self)
        WeatherService.instance.weatherChanged.removeListener(self)
        self.delegate = nil
        self.stream = nil
    }

    func refresh() {
        self.updateLocationAndWeather()

        guard let stream = self.stream else {
            self.updateHomeCard()
            return
        }
        self.updateStreamStatusUI()

        // TODO: Find a better way to determine if a stream is a Service
        if let _ = stream.instructions {
            self.enableGlimpsesContainerView.isHidden = true
            self.glimpseInfoContainerView.isHidden = true
        }

        // Set the avatar image
        if
            stream.group,
            let chunk = AudioService.instance.currentChunk,
            let participant = stream.getParticipant(chunk.senderId)
        {
            if let imageURL = participant.imageURL {
                self.avatarView.setImageWithURL(imageURL)
            } else {
                self.avatarView.setImage(AvatarView.singlePersonImage)
            }
        } else if let image = stream.image {
            self.avatarView.setImage(image)
        } else if stream.group {
            self.avatarView.setImagesWithURLs(
                stream.memberImageURLs, avatarCount: max(1, stream.reachableParticipants.count))
        } else {
            self.avatarView.setImage(AvatarView.singlePersonImage)
        }

        // TODO: Do user testing on the "create group"/"add participants" UI
        let emptyStream = stream.reachableParticipants.isEmpty
        self.participantsCollectionView.isHidden = emptyStream
        self.createGroupLabel.isHidden = !emptyStream

        if emptyStream {
            self.emptyGroupView.isHidden = false
            self.emptyGroupImageView.image = StreamCardView.groupImage
            self.emptyGroupNameLabel.text = stream.displayName
            self.avatarView.isHidden = true
            self.titleField.isHidden = true
            self.statusLabel.isHidden = true
            self.streamControlsView.isHidden = true
        } else {
            // Do not update title in the middle of an edit
            if !self.titleField.isEditing {
                self.titleField.text = stream.displayName
            }
            self.emptyGroupView.isHidden = true
            self.avatarView.isHidden = false
            self.titleField.isHidden = false
            self.statusLabel.isHidden = false
            self.streamControlsView.isHidden = false
            if let text = (stream.getPlayableChunks().last as? Chunk)?.text , text != "..." && !UIAccessibilityIsVoiceOverRunning() {
                self.textPreviewButton.isHidden = false
            } else {
                self.textPreviewButton.isHidden = true
            }
        }

        // Collection of participants
        self.participantsCollectionView.setParticipants(stream.reachableParticipants)

        // Indicate whether this stream has an attachment
        if let attachment = self.stream?.attachments[Attachment.defaultAttachmentName] {
            self.attachButton.imageView?.contentMode = .scaleAspectFill
            if let url = attachment.url, attachment.isImage {
                self.attachButton.af_setImage(for: .normal, url: url, placeholderImage: attachment.image)
                self.attachButton.af_setImage(for: .highlighted, url: url, placeholderImage: attachment.image)
            } else {
                self.attachButton.setImage(attachment.image, for: .normal)
            }
            self.attachButton.setTitleWithoutAnimation(attachment.isImage ? "photo" : "link")
            self.attachButton.backgroundColor = UIColor.white.withAlphaComponent(0.4)
            self.newAttachmentIndicator.isHidden = !SettingsManager.isAttachmentUnopened(attachment)
        } else {
            self.attachButton.setTitleWithoutAnimation("attach_file")
            self.attachButton.setTitleColor(UIColor.white, for: .normal)
            self.attachButton.backgroundColor = UIColor.clear
            self.newAttachmentIndicator.isHidden = true
        }

        // Only update visuals if the audio service is idle.
        guard case .idle = AudioService.instance.state else {
            return
        }

        // Make the play timer shake if there's something new.
        if stream.unplayed && !emptyStream {
            self.layoutIfNeeded()
            self.toggleUnplayedUI(true)
        } else {
            self.toggleUnplayedUI(false)
        }

        let duration = AudioService.instance.getPlayDuration(stream)
        self.setPlayTimerValue(stream.unplayed ? duration : 0)

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .spellOut
        self.avatarView.accessibilityLabel = String.localizedStringWithFormat(
            NSLocalizedString("Listen, %@", comment: "Accessibility hint, value is a duration (ex: 7 seconds)"),
            formatter.string(from: ceil(duration))!)
        self.avatarView.alpha = 1
    }

    func beginEditStreamTitle() {
        // Tap anywhere to dismiss keyboard if stream title is being edited.
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(StreamCardView.dismissKeyboard)))

        self.titleField.text = self.stream?.data["title"] as? String
        self.titleField.delegate = self
        self.titleField.becomeFirstResponder()
    }

    dynamic func dismissKeyboard() {
        self.titleField.resignFirstResponder()
    }

    // MARK: - Event handlers

    func updateAudioState() {
        let audio = AudioService.instance
        switch audio.state {
        case .playing:
            self.setPlayTimerValue(audio.remainingPlayDuration)
            let level = AudioService.instance.audioLevel
            let scale = CGFloat(1 + level / pow(level, 0.5))
            self.audioVisualizerView.transform = CGAffineTransform(scaleX: scale, y: scale)
            self.audioVisualizerView.center = self.avatarView.center
        default:
            return
        }
    }

    dynamic func enableWeatherTapped() {
        guard !SettingsManager.isGlimpsesEnabled else {
            return
        }
        NotificationCenter.default.post(name: Foundation.Notification.Name(rawValue: "presentEnableGlimpsesRequested"), object: nil)
        Answers.logCustomEvent(withName: "Show Weather Pressed", customAttributes: nil)
    }

    dynamic func cardLongPressed(_ sender: UILongPressGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
        let location = sender.location(ofTouch: 0, in: self)
        sender.isEnabled = false
        sender.isEnabled = true
        self.delegate?.cardLongPressed(location)
    }

    dynamic func cardSwiped(_ sender: UISwipeGestureRecognizer) {
        self.delegate?.cardSwiped(sender.direction)
    }

    @IBAction func openMembersTapped(_ sender: AnyObject) {
        self.delegate?.openStreamDetails()
    }

    @IBAction func textPreviewTapped(_ sender: AnyObject) {
        self.delegate?.showTextPreview()
    }

    @IBAction func rewindTapped(_ sender: AnyObject) {
        guard let stream = self.stream else {
            return
        }
        AudioService.instance.rewind()
        Answers.logCustomEvent(withName: "Rewind", customAttributes: ["Group": stream.group.description])
    }

    @IBAction func playbackRateTapped(_ sender: AnyObject) {
        let newRate = AudioService.instance.cyclePlaybackRate()
        SettingsManager.playbackRate = newRate
        self.playbackRateButton.setTitle("\(newRate.description)x", for: .normal)
        Answers.logCustomEvent(withName: "Set Playback Rate", customAttributes: ["Rate": newRate])
    }

    @IBAction func skipPreviousTapped(_ sender: AnyObject) {
        guard let stream = self.stream else {
            return
        }
        AudioService.instance.skipPrevious()
        Answers.logCustomEvent(withName: "Skip Previous", customAttributes: ["Group": stream.group.description])
    }

    @IBAction func skipNextTapped(_ sender: AnyObject) {
        guard let stream = self.stream else {
            return
        }
        AudioService.instance.skipNext()
        Answers.logCustomEvent(withName: "Skip Next", customAttributes: ["Group": stream.group.description])
    }

    @IBAction func buzzTapped(_ sender: AnyObject) {
        self.avatarShaker.stop()
        self.avatarShaker.start(self.avatarView, repeats: false)
        self.stream?.sendBuzz()
        AudioService.instance.vibrate()
    }

    @IBAction func attachTapped(_ sender: AnyObject) {
        if let stream = self.stream, let attachment = stream.attachments[Attachment.defaultAttachmentName] {
            SettingsManager.markAttachmentOpened(stream, attachment: attachment)
            self.newAttachmentIndicator.isHidden = true
        }
        self.delegate?.showAttachment()
    }

    // MARK: - UIView

    deinit {
        // TODO: This never happens!
        self.destroy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func awakeFromNib() {
        self.backgroundColor = UIColor.clear
        self.playbackControlsView.backgroundColor = UIColor.clear

        let contactsTap = UITapGestureRecognizer(target: self, action: #selector(self.openMembersTapped))
        self.contactsContainerView.addGestureRecognizer(contactsTap)
        let enableWeatherTap = UITapGestureRecognizer(target: self, action: #selector(self.enableWeatherTapped))
        self.enableGlimpsesContainerView.addGestureRecognizer(enableWeatherTap)

        // Tap/Raise to listen hint
        self.updateTooltip()

        // Swipe gesture to navigate between cards
        let rightSwipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(self.cardSwiped(_:)))
        rightSwipeGesture.direction = .right
        self.addGestureRecognizer(rightSwipeGesture)

        let leftSwipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(self.cardSwiped(_:)))
        leftSwipeGesture.direction = .left
        self.addGestureRecognizer(leftSwipeGesture)

        // Long press gesture recognizer on the card.
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(self.cardLongPressed(_:)))
        self.addGestureRecognizer(longPressGesture)

        // Setup playback timer view.
        self.playbackTimeHolderView.isHidden = true
//        self.playbackTimeHolderView.layer.borderColor = UIColor.whiteColor().CGColor
//        self.playbackTimeHolderView.layer.borderWidth = 2
//        self.playbackTimeHolderView.layer.shadowColor = UIColor.blackColor().CGColor
//        self.playbackTimeHolderView.layer.shadowOffset = CGSizeMake(0, 2)
//        self.playbackTimeHolderView.layer.shadowOpacity = 0.4
//        self.playbackTimeHolderView.layer.shadowRadius = 2
//        self.playbackTimeHolderView.layer.shadowPath =
//            UIBezierPath(roundedRect: self.playbackTimeHolderView.bounds, cornerRadius: self.playbackTimeHolderView.bounds.width / 2).CGPath

        self.playbackTimeLabel.font = UIFont.monospacedDigitsRogerFontOfSize(22)

        // Receive touch events
        self.avatarView.delegate = self

        // Set up the circle that visualizes playing sound.
        self.audioVisualizerView = UIView()
        self.audioVisualizerView.frame.size = CGSize(width: 130, height: 130)
        self.audioVisualizerView.center = self.avatarView.center
        self.audioVisualizerView.isHidden = true
        self.audioVisualizerView.backgroundColor = UIColor.white.withAlphaComponent(0.4)
        self.audioVisualizerView.layer.cornerRadius = self.audioVisualizerView.frame.size.width / 2
        self.insertSubview(self.audioVisualizerView, belowSubview: self.avatarView)

        // Rasterize the card since it contains a lot of text that would otherwise be rerendered due to underlying weather.
        self.layer.rasterizationScale = UIScreen.main.scale
        self.layer.shouldRasterize = true

        AudioService.instance.stateChanged.addListener(self, method: StreamCardView.handleAudioStateChange)
        AudioService.instance.currentChunkChanged.addListener(self, method: StreamCardView.handleCurrentChunkChange)
        WeatherService.instance.weatherChanged.addListener(self, method: StreamCardView.handleWeatherChange)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.audioVisualizerView.center = self.avatarView.center
        self.playbackTimeHolderView.layer.cornerRadius = self.playbackTimeHolderView.frame.width / 2
    }

    // MARK: AvatarViewDelegate

    func didEndTouch(_ avatarView: AvatarView) {
        // If this is the main avatarView, play/stop stream
        if avatarView == self.avatarView {
            switch AudioService.instance.state {
            case .idle:
                guard let stream = self.stream , !stream.getPlayableChunks().isEmpty else {
                    if let profile = self.profile {
                        DispatchQueue.main.async {
                            AudioService.instance.playProfile(profile, preferLoudspeaker: true)
                            SettingsManager.didListen = true
                        }
                    }
                    return
                }

                DispatchQueue.main.async {
                    AudioService.instance.playStream(stream, preferLoudspeaker: true, reason: "TappedAvatar")
                    SettingsManager.didListen = true
                }
            case .playing:
                DispatchQueue.main.async {
                    AudioService.instance.stopPlaying(reason: "TappedAvatar")
                }
            default:
                break
            }
        }
    }

    func accessibilityFocusChanged(_ avatarView: AvatarView, focused: Bool) {
        guard avatarView == self.avatarView else {
            return
        }

        ProximityMonitor.instance.active = focused
    }

    // MARK: UITextFieldDelegate

    func textFieldDidEndEditing(_ textField: UITextField) {
        guard let title = textField.text , title.characters.count > 0 else {
            return
        }

        self.stream?.setTitle(title)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.dismissKeyboard()
        return true
    }

    // MARK: - Private

    private typealias StateChange = (old: AudioService.State, new: AudioService.State)

    private static let groupImage = UIImage(named: "group")!

    private let playTimerShaker = Shaker(distance: 4)
    private let avatarShaker = Shaker(distance: 8)
    private let pulser = Pulser(color: UIColor(white: 1, alpha: 0.4))

    private var listenTooltip: TooltipView!
    private var audioStateTimer: CADisplayLink? {
        didSet {
            if let timer = oldValue {
                timer.invalidate()
            }
        }
    }
    private var audioVisualizerView: UIView!
    private var destroyed = false

    private func startAlexaSpin() {
        guard let stream = self.stream, stream is AlexaStream else {
            return
        }
        self.avatarView.startSpin()
    }

    private func stopAlexaSpin() {
        guard let stream = self.stream, stream is AlexaStream else {
            return
        }
        self.avatarView.stopSpin()
    }

    private func handleCurrentChunkChange() {
        self.refresh()
    }

    private func handleAudioStateChange(_ oldState: AudioService.State) {
        let change = StateChange(old: oldState, new: AudioService.instance.state)
        // General state changes.
        switch change {
        case (.idle, .playing):
            // Don't shake while something else is happening.
            self.toggleUnplayedUI(false)
            self.playbackRateButton.setTitleWithoutAnimation("\(SettingsManager.playbackRate.description)x")
            if self.stream != nil {
                self.playbackControlsView.showAnimated()
                self.streamControlsView.hideAnimated()
            }
        case (.idle, .recording):
            self.toggleUnplayedUI(false)
        case (.recording, .idle):
            self.refresh()
        case (.playing, .idle):
            if self.stream != nil {
                self.playbackControlsView.hideAnimated()
                self.streamControlsView.showAnimated()
            }
            self.refresh()
        default:
            break
        }
        // Update every component in their own method.
        self.updateDisplayLink(change)
        self.updateLoadingUI(change)
        self.updatePlaybackUI(change)
    }

    private func handleWeatherChange(_ weather: Weather?) {
        self.updateLocationAndWeather()
    }

    private func setPlayTimerValue(_ totalSeconds: Double) {
        // Update the timer without animating.
        let wholeSeconds = Int(ceil(totalSeconds))
        self.playbackTimeLabel.text = String(wholeSeconds)
    }

    private func toggleUnplayedUI(_ show: Bool) {
        // Do not show the tooltip until the user has listened at least oncel
        self.playbackTimeHolderView.isHidden = !show
        if !show {
            self.playTimerShaker.stop()
            self.updateTooltip()
            return
        }
        // Shake the playback timer.
        self.playTimerShaker.start(self.playbackTimeHolderView)
        self.updateTooltip()
    }

    private func updateDisplayLink(_ change: StateChange) {
        switch change {
        case (.idle, _ ):
            // Started playing or recording.
            let timer = CADisplayLink(target: self, selector: #selector(StreamCardView.updateAudioState))
            timer.add(to: RunLoop.main, forMode: .defaultRunLoopMode)
            self.audioStateTimer = timer
        case (_, .idle):
            // Done with playing or recording.
            self.audioStateTimer = nil
        default:
            break
        }
    }

    private var onboardingShownOnce = false
    private func updateHomeCard() {
        guard let profile = self.profile else {
            return
        }

        if !self.onboardingShownOnce {
            self.onboardingShownOnce = true
            self.alpha = 0
            self.titleField.isHidden = true
            self.statusLabel.isHidden = true
            self.titleField.isHidden = true
            self.statusLabel.isHidden = true
            self.optionsContainerView.isHidden = true
            self.glimpseInfoContainerView.isHidden = true
            self.enableGlimpsesContainerView.isHidden = true
            self.streamControlsView.isHidden = true
            UIView.animate(withDuration: 1, animations: {
                self.alpha = 1
            }) 
        }

        if let url = profile.imageURL {
            self.avatarView.setImageWithURL(url)
        } else if StreamsViewController.groupInviteToken != nil {
            self.avatarView.setImagesWithURLs(profile.participants.filter { $0.imageURL != nil }.map { $0.imageURL! }, avatarCount: profile.participants.count)
        } else {
            self.avatarView.setImage(AvatarView.singlePersonImage)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 4
        self.setPlayTimerValue(AudioService.instance.getPlayDuration(profile))
        if profile.unplayed && profile.participants.isEmpty {
            self.toggleUnplayedUI(true)
            self.listenTooltip.show()
        } else {
            // TODO: Super hacky way to deal with no audio.
            let sentence = profile.participants.count > 1 ? NSLocalizedString("%@ are talking to you.\nJoin the conversation.", comment: "Intro screen") : NSLocalizedString("%@ is talking to you.\nJoin the conversation.", comment: "Intro screen")
            let text = NSMutableAttributedString(string: sentence, attributes: [
                NSForegroundColorAttributeName: UIColor.white.withAlphaComponent(0.6),
                ])
            // There appears to be cases where display name has 0 characters.
            var displayName = profile.displayName
            if displayName.characters.count == 0 {
                displayName = NSLocalizedString("Someone", comment: "Text to show if we don't know the name of a person.")
            }
            text.replaceCharacters(
                in: (sentence as NSString).range(of: "%@"),
                with: NSAttributedString(string: displayName, attributes: [
                    NSForegroundColorAttributeName: UIColor.white,
                    ])
            )
            text.addAttribute(NSParagraphStyleAttributeName, value: paragraphStyle, range: NSMakeRange(0, text.length))
            self.earpieceHint.attributedText = text
            self.earpieceHint.isHidden = false
        }
    }

    private func updateLocationAndWeather() {
        let primaryAccount: Account? = stream?.otherParticipants.first ?? BackendClient.instance.session
        guard let account = primaryAccount else {
            self.glimpseInfoContainerView.isHidden = true
            self.enableGlimpsesContainerView.isHidden = true
            return
        }

        guard SettingsManager.isGlimpsesEnabled else {
            self.glimpseInfoContainerView.isHidden = true
            self.enableGlimpsesContainerView.isHidden = false
            return
        }

        self.enableGlimpsesContainerView.isHidden = true
        guard let location = account.location,
            let localTime = account.localTime else {
            self.glimpseInfoContainerView.isHidden = true
            return
        }

        // Local time and city UI.
        self.glimpseInfoContainerView.isHidden = false
        self.locationLabel.text = location
        self.localTimeLabel.text = localTime.rogerFormattedTime

        // Set the accessibility label in a deferred block since we may return before adding on the weather.
        self.glimpseInfoContainerView.accessibilityLabel = String.localizedStringWithFormat(
            NSLocalizedString("It's %@ in %@", comment: "Accessibility label; first value is time, second value is city"),
            localTime.rogerFormattedTime,
            location)

        // Weather UI.
        guard let weather = WeatherService.instance.weather[account.id] else {
            self.weatherLabel.isHidden = true
            self.temperatureLabel.isHidden = true
            return
        }

        self.weatherLabel.isHidden = false
        self.temperatureLabel.isHidden = false
        let temperature: Int
        // TODO: Localize temperature properly.
        if Locale.current.usesMetricSystem {
            temperature = Int(weather.temperature)
            self.temperatureLabel.text = "\(temperature)° C"
        } else {
            temperature = Int(weather.temperature * 1.8 + 32)
            self.temperatureLabel.text = "\(temperature)° F"
        }
        self.glimpseInfoContainerView.accessibilityLabel = String.localizedStringWithFormat(
            NSLocalizedString("It's %@ in %@ where it's %d degrees and %@", comment: "Accessibility label; first value is time, second value is city, third value is temperature, fourth value is weather"),
            localTime.rogerFormattedTime,
            location,
            temperature,
            // TODO: Translate this.
            String(describing: weather.phenomenon))

        // Find appropriate letter for the icon font.
        var weatherIconText = "A"
        switch weather.phenomenon {
        case .Cloudy: weatherIconText = "C"
        case .Fog: weatherIconText = "O"
        case .PartlyCloudy: weatherIconText = localTime.isNight ? "J" : "C"
        case .Rain: weatherIconText = localTime.isNight ? "K" : "R"
        case .Sleet: weatherIconText = "X"
        case .Snow: weatherIconText = "W"
        case .Wind: weatherIconText = "b"
        default:
            // Clear
            weatherIconText = localTime.isNight ? "J" : "A"
        }

        self.weatherLabel.text = weatherIconText
    }

    private func updateLoadingUI(_ change: StateChange) {
        if case .playing(let ready) = change.new, !ready {
            let blink = CABasicAnimation(keyPath: "opacity")
            blink.duration = 0.5
            blink.repeatCount = Float.infinity
            blink.autoreverses = true
            blink.fromValue = 1.0
            blink.toValue = 0.2
            self.playbackTimeLabel.layer.add(blink, forKey: "blink")
        } else {
            self.playbackTimeLabel.layer.removeAnimation(forKey: "blink")
        }
    }

    private func updateStreamStatusUI() {
        guard let stream = self.stream else {
            return
        }
        if let chunk = AudioService.instance.currentChunk,
            let participant = stream.getParticipant(chunk.senderId), stream.group && stream.status == .Idle {
            self.statusLabel.text = String.localizedStringWithFormat(
                NSLocalizedString("Listening to %@", comment: "Listening stream status text"),
                participant.displayName.rogerShortName)
            return
        }

        self.statusLabel.text = stream.statusText
        if stream.status != .Idle && stream.status != .ViewingAttachment {
            self.startAlexaSpin()
            self.pulser.start(self.avatarView, reversed: stream.status == .Listening)
        } else {
            self.stopAlexaSpin()
            self.pulser.stop()
        }
    }

    private func updatePlaybackUI(_ change: StateChange) {
        // Update the scale of the play timer.
        switch change {
        case (_, .playing(let ready)):
            // Started playing.
            self.avatarView.accessibilityLabel = self.stream?.unplayed ?? false ?
                NSLocalizedString("Pause", comment: "Accessibility label to Pause playback") :
                NSLocalizedString("Stop", comment: "Accessibility label to Stop playback")
            self.playbackTimeHolderView.isHidden = false
            self.audioVisualizerView.isHidden = !ready
            self.startAlexaSpin()
        case (.playing, .idle):
            // Stopped playing.
            self.playbackTimeHolderView.isHidden = !(self.stream?.unplayed ?? true)
            self.audioVisualizerView.isHidden = true
            self.stopAlexaSpin()
        case (.playing, .recording):
            self.audioVisualizerView.isHidden = true
        case (.idle, .recording):
            self.playbackTimeHolderView.isHidden = true
        default:
            break
        }
    }

    private func updateTooltip() {
        let canRaise = ProximityMonitor.instance.supported
        let listenHint = canRaise ?
            NSLocalizedString("Tap or raise to listen", comment: "Stream card listen hint") :
            NSLocalizedString("Tap to listen", comment: "Stream card listen hint")
        if self.listenTooltip == nil {
            self.listenTooltip = TooltipView(text: listenHint, centerView: self.avatarView)
            self.addSubview(self.listenTooltip)
        }

        guard let stream = self.stream else {
            return
        }

        var hint: String!
        if case .idle = AudioService.instance.state, stream.unplayed && SettingsManager.didListen {
            // Do not show "raise to ear" if the device does not contain a proximity monitor
            hint = listenHint
        } else if case .playing = AudioService.instance.state, canRaise {
            hint = NSLocalizedString("Raise to listen privately", comment: "Stream card raise hint")
        } else {
            self.listenTooltip.hide()
            return
        }

        self.listenTooltip.setText(hint)
        self.listenTooltip.show()
    }
}
