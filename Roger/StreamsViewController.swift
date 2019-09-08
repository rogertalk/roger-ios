import CoreSpotlight
import Crashlytics
import Foundation
import MessageUI
import MobileCoreServices
import SafariServices

private let recordingMinimumDuration = 0.4

class StreamsViewController: UIViewController,
    MFMessageComposeViewControllerDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate,
    ContactPickerDelegate,
    RecentStreamsManager,
    RecordButtonDelegate,
    StreamCardDelegate,
    AttachmentPreviewDelegate {

    weak var recents: RecentStreamsCollectionView!

    @IBOutlet weak var streamCardContainerView: UIView!
    @IBOutlet weak var recordButtonView: RecordButtonView!
    @IBOutlet weak var talkingHintLabel: UILabel!
    @IBOutlet weak var tapToTalkTutorialView: OverlayView!
    @IBOutlet weak var tapToListenTutorialView: OverlayView!
    @IBOutlet weak var darkOverlayView: OverlayView!
    @IBOutlet weak var recordingOverlayView: OverlayView!
    @IBOutlet weak var unplayedCountLabel: UILabel!
    @IBOutlet weak var closeDarkOverlayButton: UIButton!
    @IBOutlet weak var sentLabel: UILabel!
    @IBOutlet weak var talkingToHintView: UIView!

    /// The index in the list of streams that is currently selected. Can be nil if the selected stream is not in the recent streams list.
    var selectedStreamIndex: Int? {
        guard let stream = self.selectedStream else {
            return nil
        }
        return self.streams.index(of: stream)
    }

    /// The currently selected stream (if any).
    var selectedStream: Stream? {
        didSet {
            oldValue?.changed.removeListener(self)
            self.selectedStream?.changed.addListener(self, method: StreamsViewController.handleStreamChanged)
            self.refreshActiveStream(self.selectedStream?.id != oldValue?.id)
            self.updateProximityMonitor()
            // If this is an empty group, immediately pop up the add members view
            if let stream = self.selectedStream, stream.group && stream.activeParticipants.isEmpty && self.viewInForeground {
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(200 * NSEC_PER_MSEC)) / Double(NSEC_PER_SEC)) {
                    self.openStreamDetails()
                }
            }
        }
        willSet {
            // TODO: This should probably be set from RecentStreamsCollectionView via an event.
            self.recents?.selectedCell?.isCurrentlySelected = false
        }
    }

    /// The list of recent streams. Only update this in events from the stream service.
    var streams = [Stream]()

    /// A contact that has been selected but nothing has been sent to them yet.
    private(set) var temporaryStream: Stream? {
        didSet {
            if self.temporaryStream == oldValue {
                return
            }
            self.recents.updateTemporaryCell()
        }
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        self.view.backgroundColor = UIColor.clear
        self.closeDarkOverlayButton.isHidden = !UIAccessibilityIsVoiceOverRunning()

        // Prep the placeholder view
        self.placeholder = PlaceholderCardView.create(self.streamCardContainerView.bounds)
        self.streamCardContainerView.insertSubview(self.placeholder, at: 0)
        self.placeholder.isHidden = true

        self.darkOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        self.darkOverlayView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(StreamsViewController.darkOverlayTapped)))

        // Set autoplay status
        self.autoplayIndicatorView = AutoplayIndicatorView.create(container: self.view)
        self.autoplayIndicatorView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(StreamsViewController.showAutoplayIndicator)))
        //self.view.addSubview(self.autoplayIndicatorView)

        self.recents.streamsManager = self
        self.streams = StreamService.instance.streams.values
        self.selectedStream = self.streams.first
        self.refreshActiveStream(true)

        StreamService.instance.sentChunk.addListener(self, method: StreamsViewController.handleChunkSent)

        // Listen for changes to audio state.
        AudioService.instance.stateChanged.addListener(self, method: StreamsViewController.handleAudioStateChange)

        // Subscribe to notification for presenting "EnableGlimpses".
        NotificationCenter.default.addObserver(self, selector: #selector(StreamsViewController.presentEnableGlimpses), name: NSNotification.Name(rawValue: "presentEnableGlimpsesRequested"), object: nil)

        Responder.notificationReceived.addListener(self, method: StreamsViewController.notificationReceived)
        Responder.notificationSettingsChanged.addListener(self, method: StreamsViewController.handleNotificationSettingsChanged)
        Responder.openedByLink.addListener(self, method: StreamsViewController.openedByLink)
        Responder.streamShortcutSelected.addListener(self, method: StreamsViewController.streamShortcutSelected)
        Responder.userSelectedStream.addListener(self, method: StreamsViewController.streamSelected)
        Responder.userSelectedAttachment.addListener(self, method: StreamsViewController.handleAttachmentSelected)
        Responder.newChunkReceived.addListener(self, method: StreamsViewController.handleNewChunkReceived)

        // Listen for changes to proximity.
        ProximityMonitor.instance.changed.addListener(self, method: StreamsViewController.handleProximityChange)

        // Listen for hardware changes
        AudioService.instance.routeChanged.addListener(self, method: StreamsViewController.updateProximityMonitor)

        // Start loading contacts in the background now to save time when the user navigates to the search page.
        ContactService.shared.importContacts()

        // Monitor network changes and display the network issue view when necessary.
        self.networkMonitor = NetworkMonitor(container: self.view)

        // Set up the image pickers.
        self.conversationPhotoImagePicker.allowsEditing = true
        self.conversationPhotoImagePicker.delegate = self
        self.attachmentImagePicker.delegate = self

        // Setup recording button.
        self.recordButtonView.delegate = self

        WeatherService.instance.updateWeatherData()
        self.resetStreamCardRefreshTimer()

        // Fixes strange constraint error with recents CollectionView on iOS 8 devices.
        self.view.updateConstraints()

        if SettingsManager.didCompleteTutorial {
            Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(StreamsViewController.ensureNotificationPermissions), userInfo: nil, repeats: false)
        }

        // Create loader/confirmation box
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        self.view.addSubview(self.statusIndicatorView)

        self.setNeedsStatusBarAppearanceUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Setup Listen tutorial overlay
        self.setupTutorialOverlay(self.tapToListenTutorialView,
                           holeFrame: CGRect(x: self.streamCardContainerView.center.x - 86, y: (self.streamCardContainerView.center.y - 106) * 0.7, width: 172, height: 172))

        // Setup Talk tutorial overlay
        let recordButtonFrame = self.recordButtonView.frame
        self.setupTutorialOverlay(self.tapToTalkTutorialView,
                           holeFrame: CGRect(x: recordButtonFrame.origin.x - 16,
                            y: recordButtonFrame.origin.y - 16,
                            width: recordButtonFrame.size.width + 32,
                            height: recordButtonFrame.size.height + 32))
    }

    override func viewWillAppear(_ animated: Bool) {
        // Start listening for the app going into the foreground.
        Responder.applicationActiveStateChanged.addListener(self, method: StreamsViewController.handleApplicationActive)
        // Listen for changes to streams.
        StreamService.instance.recentStreamsChanged.addListener(self, method: StreamsViewController.recentStreamsChanged)

        self.knownActiveState = UIApplication.shared.applicationState == .active
        self.viewInForeground = true

        self.refreshActiveStream(true)
        self.recents.refresh()
        self.autoplayIndicatorView.refresh()

        UIView.animate(withDuration: 0.3, animations: {
            self.view.alpha = 1
        })

        let alert = UIAlertController(title: "Roger will be shut down on March 15th, 2017.", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Read the Announcement", style:
            .default) { _ in
                UIApplication.shared.openURL(URL(string: "http://tinyurl.com/roger2017")!)
        })
        self.present(alert, animated: true, completion: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        // Disable certain monitoring while the streams view is not visible.
        Responder.applicationActiveStateChanged.removeListener(self)
        StreamService.instance.recentStreamsChanged.removeListener(self)

        self.viewInForeground = false

        // TODO: Have an "in call" UI to display when recording is in progress.
        // Stop any recording currently in progress (to prevent continuing from other screens).
        AudioService.instance.stopRecording(cancel: true, reason: "LeavingStreamsView")

        self.streamCardRefreshTimer?.invalidate()

        // Fade out the stream card to make transitions more pleasant.
        UIView.animate(withDuration: 0.3, animations: {
            self.view.alpha = 0
        }) 
    }

    override var preferredStatusBarUpdateAnimation : UIStatusBarAnimation {
        return .slide
    }

    override var prefersStatusBarHidden : Bool {
        return self.view.subviews.contains { $0 is AttachmentPreviewView }
    }

    override var preferredStatusBarStyle : UIStatusBarStyle {
        return .lightContent
    }

    override func updateUserActivityState(_ activity: NSUserActivity) {
        activity.addUserInfoEntries(from: self.getUserActivityInfo())
    }

    dynamic func ensureNotificationPermissions() {
        guard !SettingsManager.hasNotificationsPermissions else {
            return
        }

        let alert = UIAlertController(
            title: NSLocalizedString("😀 Notifications", comment: "Alert title"),
            message: NSLocalizedString("Turn on notifications to get notified when your friends talk to you!", comment: "Alert text"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Don't Allow", comment: "Alert dialog action"), style: .default, handler: nil))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Allow", comment: "Alert dialog action"), style: .default) { _ in
            Responder.setUpNotifications()
            })
        self.present(alert, animated: true, completion: nil)
    }

    override func accessibilityPerformMagicTap() -> Bool {
        guard let stream = self.selectedStream else {
            return true
        }
        switch AudioService.instance.state {
        case .idle:
            AudioService.instance.playStream(stream, preferLoudspeaker: true)
        default:
            AudioService.instance.stop()
        }

        return true
    }

    // MARK: - Actions

    @IBAction func skipTutorialStepTapped(_ sender: UIButton) {
        SettingsManager.didTapToRecord = true
        self.tapToTalkTutorialView.hideAnimated()
    }

    @IBAction func settingsTapped(_ sender: AnyObject) {
        let controller = self.storyboard!.instantiateViewController(withIdentifier: "Settings") as! SettingsViewController
        self.present(controller, animated: true, completion: nil)
        Answers.logCustomEvent(withName: "Settings Shown", customAttributes: ["Source": "Streams"])
    }

    @IBAction func conversationsTapped(_ sender: AnyObject) {
        self.toggleRecents(true)
    }

    @IBAction func closeDarkOverlayTapped(_ sender: AnyObject) {
        self.darkOverlayTapped()
    }

    // MARK: - RecordButtonDelegate

    private func startRecording() {
        AudioService.instance.startRecording(self.selectedStream, reason: "TappedMic")
        SettingsManager.didTapToRecord = true
        self.updateHintTooltip()
    }

    private func stopRecording(reason: String) {
        AudioService.instance.stopRecording(reason: reason)
        SettingsManager.didCompleteTutorial = true
    }

    internal func didTriggerAction() {
        let audio = AudioService.instance
        if case .recording = audio.state {
            self.stopRecording(reason: "TappedMic")
            return
        }

        guard audio.canRecord else {
            // We need to ask for permission.
            audio.requestRecordingPermission() { granted in
                if granted {
                    // Begin recording immediately.
                    self.startRecording()
                }
            }
            return
        }

        self.startRecording()
    }

    internal func didLongPressAction() {
        let audio = AudioService.instance
        // Return unless we've been recording for at least 1 second.
        guard case .recording = audio.state , audio.recordedDuration > 1 else {
            return
        }
        // Complete the recording if the user lets go inside the mic button after 1 second or more.
        self.stopRecording(reason: "LongPressReleased")
    }

    // MARK: - AttachmentPreviewDelegate

    func attachNew(_ preview: AttachmentPreviewView) {
        self.close(preview)
        self.attachNewItem()
    }

    func close(_ preview: AttachmentPreviewView) {
        preview.hideAnimated() {
            preview.removeFromSuperview()
            self.setNeedsStatusBarAppearanceUpdate()
        }
        self.autoplayIndicatorView.showAnimated()
    }

    // MARK: - StreamCardDelegate

    func instructionsActionTapped(_ result: InstructionsActionResult) {
        switch result {
        case .nothing:
            break
        case let .showAlert(title, message, action):
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: action, style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
        case let .showShareSheet(text):
            let vc = Share.createShareSheet(DynamicActivityItem(text), anchor: self.recordButtonView, source: "InstructionsCard")
            self.present(vc, animated: true, completion: nil)
        case let .showWebView(title, url):
            guard let browser = self.storyboard?.instantiateViewController(withIdentifier: "EmbeddedBrowser") as? EmbeddedBrowserController else {
                return
            }
            browser.urlToLoad = url
            browser.pageTitle = title
            self.present(browser, animated: true, completion: nil)
        }
    }

    func openStreamDetails() {
        guard let stream = self.selectedStream else {
            return
        }

        // Open StreamDetails
        let streamDetails = self.storyboard?.instantiateViewController(withIdentifier: "StreamDetails") as! StreamDetailsViewController
        streamDetails.stream = stream
        self.navigationController?.pushViewControllerModal(streamDetails)
    }

    func showTextPreview() {
        guard let chunk = self.selectedStream?.getPlayableChunks().last as? Chunk,
            let sender = self.selectedStream?.getParticipant(chunk.senderId),
            let text = chunk.text else {
            return
        }

        let alert = UIAlertController(title: NSLocalizedString("Text Preview", comment: "Stream transcription alert title"), message: String(format: "%@: %@", sender.displayName.rogerShortName, text), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Done", comment: "Alert action"), style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }

    func cardLongPressed(_ point: CGPoint) { }

    func cardSwiped(_ direction: UISwipeGestureRecognizerDirection) {
        // Only swipe between cards if there is nothing playing/recording
        guard case .idle = AudioService.instance.state else {
            return
        }

        if direction == .left {
            if let streamIndex = self.selectedStreamIndex {
                if streamIndex < self.streams.count - 1 {
                    self.selectedStream = self.streams[streamIndex + 1]
                }
            } else {
                self.selectedStream = self.streams.first
            }
            self.recents.scrollToSelectedStream()
        } else if direction == .right {
            guard let streamIndex = self.selectedStreamIndex else {
                return
            }

            if streamIndex > 0 {
                self.selectedStream = self.streams[streamIndex - 1]
            }

            self.recents.scrollToSelectedStream()
        }
    }

    func showAttachment() {
        guard let stream = self.selectedStream,
            let attachment = stream.attachments[Attachment.defaultAttachmentName] else {
                self.attachNewItem()
            return
        }

        guard let url = attachment.url , !attachment.isImage else {
            let preview = AttachmentPreviewView.create(
                attachment, stream: stream, frame: self.view.bounds, delegate: self)
            self.view.insertSubview(preview, belowSubview: self.recordButtonView)
            self.setNeedsStatusBarAppearanceUpdate()
            self.autoplayIndicatorView.hideAnimated()
            preview.showAnimated()
            stream.reportStatus(.ViewingAttachment)
            Answers.logCustomEvent(withName: "AttachmentPreviewView Shown", customAttributes: nil)
            return
        }

        let alert = UIAlertController(title: NSLocalizedString("Shared Link", comment: "Alert title"), message: url.absoluteString, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Open link", comment: "Alert action"), style: .default) { _ in
            UIApplication.shared.openURL(url as URL)
            })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Share new", comment: "Alert action"), style: .default) { _ in
            self.attachNewItem()
            })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }

    // MARK: - RecentStreamsManager

    func addTapped() {
        self.toggleRecents(false)
        
        let streamDetails = self.storyboard?.instantiateViewController(withIdentifier: "StreamDetails") as! StreamDetailsViewController
        self.navigationController?.pushViewControllerModal(streamDetails)
        Answers.logCustomEvent(withName: "Create Conversation", customAttributes: ["Source": "Streams"])
    }

    func streamLongPressed(_ index: Int) {
        let stream = streams[index]
        self.showStreamOptions(stream)
    }

    func streamTapped(_ index: Int) {
        // Destroy the temporary stream (if any).
        self.temporaryStream = nil

        // Select the tapped stream.
        let previousStream = self.selectedStream
        let stream = self.streams[index]

        // If a new stream is selected, cancel multi-tap action.
        if stream !== previousStream {
            self.selectedStream = stream
        }

        self.toggleRecents(false)
    }

    func createPrimerStream(_ title: String) {
        let streamDetails = self.storyboard?.instantiateViewController(withIdentifier: "StreamDetails") as! StreamDetailsViewController
        streamDetails.presetTitle = title
        self.navigationController?.pushViewControllerModal(streamDetails)
        Answers.logCustomEvent(withName: "Create Conversation", customAttributes: ["Source": "Streams"])
    }

    func darkOverlayTapped() {
        self.toggleRecents(false)
        self.autoplayIndicatorView.hide()
    }

    // MARK: - ContactPickerDelegate

    func didFinishPickingContacts(_ picker: ContactPickerViewController, contacts: [Contact]) {
        // Create and select a new stream with the given contacts as participants
        let selectStream: (Stream?) -> Void = { stream in
            guard let stream = stream else {
                return
            }

            let oldestStreamInteractionTime =
                StreamService.instance.streams.values.last?.lastInteractionTime ?? Date.distantPast
            if (stream.lastInteractionTime as NSDate).isLaterThan(oldestStreamInteractionTime) {
                StreamService.instance.includeStreamInRecents(stream: stream)
            }

            // A stream was found, so make the streams view controller select it.
            self.selectedStream = stream
            self.recents.scrollToSelectedStream()

            self.navigationController?.popToRootViewControllerModal()
        }

        // Aliases to search to find a stream on the backend.
        var participants: [Intent.Participant] = []
        for contact in contacts {
            if let stream = (contact as? StreamContact)?.stream {
                if contacts.count == 1 {
                    selectStream(stream)
                    return
                } else {
                    let streamParticipants = stream.otherParticipants
                        .map { Intent.Participant.Identifier(nil, String($0.id)) }
                        .map { Intent.Participant(identifiers: [$0]) }
                    participants.append(contentsOf: streamParticipants)
                }
            } else if let serviceStream = (contact as? ServiceContact)?.stream {
                selectStream(serviceStream)
                return
            } else {
                participants.append(Intent.Participant(identifiers: [("", contact.identifier)]))
            }
        }

        StreamService.instance.getOrCreateStream(participants: participants, showInRecents: true) { stream, error in
            picker.loading = false
            if let stream = stream {
                selectStream(stream)
                return
            }

            picker.contactsTableView.allowsSelection = true
            if error != nil {
                let message: String
                if let alias = participants.first?.identifiers.first?.identifier {
                    message = String.localizedStringWithFormat(
                        NSLocalizedString("Could not start a conversation with %@.", comment: "Alert text"),
                        alias)
                } else {
                    message = NSLocalizedString("Could not start a conversation.", comment: "Alert text")
                }
                let alert = UIAlertController(title: NSLocalizedString("Oops!", comment: "Alert title"), message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("Okay", comment: "Alert action"), style: .cancel, handler: nil))
                picker.present(alert, animated: true, completion: nil)
                Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "ContactPicker", "Type": "AddPersonFailed"])
            }
        }
    }

    // MARK: - UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingImage image: UIImage, editingInfo: [String : AnyObject]?) {
        defer {
            picker.dismiss(animated: true, completion: nil)
        }

        if picker == self.conversationPhotoImagePicker {
            guard let imageData = UIImageJPEGRepresentation(image, 0.8) else {
                Answers.logCustomEvent(withName: "Stream Image Picker", customAttributes: ["Result": "Cancel"])
                return
            }
            self.selectedStream?.setImage(Intent.Image(format: .jpeg, data: imageData))
        } else if picker == self.attachmentImagePicker {
            self.selectedStream?.addAttachment(Attachment(image: image))
        }
        Answers.logCustomEvent(withName: "Stream Image Picker", customAttributes: ["Result": "PickedImage"])
    }

    // MARK: - Notification handlers

    /// Refreshes any UI elements that may have gone stale.
    func refreshUI() {
        self.selectedStreamCard?.refresh()
        self.resetStreamCardRefreshTimer()
    }

    func presentEnableGlimpses() {
        let enableGlimpses = self.storyboard?.instantiateViewController(withIdentifier: "EnableGlimpses")
        self.present(enableGlimpses!, animated: true, completion: nil)
    }

    func showStreamOptions(_ stream: Stream) {
        self.selectedStream = stream

        // Provide an anchor for iPad.
        let sourceView = self.recents.selectedCell?.avatarView
        let sourceRect = self.recents.selectedCell?.avatarView.bounds.insetBy(dx: -10, dy: -10) ?? CGRect.zero

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.popoverPresentationController?.sourceView = sourceView
        sheet.popoverPresentationController?.sourceRect = sourceRect

        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .full
        sheet.title = "💬 \(formatter.string(from: stream.totalDuration)!)"
        // This is a group. Allow changing the group name.
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Set Conversation Title", comment: "Sheet action"), style: .default) { _ in
            self.toggleRecents(false)
            self.selectedStreamCard?.beginEditStreamTitle()
            })
        Answers.logCustomEvent(withName: "Stream Sheet Option", customAttributes: ["Option": "ChangeStreamTitle"])
        // Set converstation photo.
        let setPhotoOption = NSLocalizedString("Set Conversation Photo", comment: "Sheet action")
        sheet.addAction(UIAlertAction(title: setPhotoOption, style: .default) { _ in
            self.toggleRecents(false)
            self.conversationPhotoImagePicker.sourceType = .photoLibrary
            self.present(self.conversationPhotoImagePicker, animated: true) {
                sheet.dismiss(animated: true, completion: nil)
            }
            Answers.logCustomEvent(withName: "Stream Sheet Option", customAttributes: ["Option": "ChangeStreamImage"])
            })
        //        // Autoplay.
        //        if stream.autoplayChangeable && !SettingsManager.autoplayAll {
        //            let autoplayOption = stream.autoplay ?
        //                NSLocalizedString("Turn off Autoplay", comment: "Sheet action") :
        //                NSLocalizedString("Turn on Autoplay", comment: "Sheet action")
        //            sheet.addAction(UIAlertAction(title: autoplayOption, style: .Default) { _ in
        //                stream.autoplay = !stream.autoplay
        //                })
        //        }
        // Share friends' profiles.
        if stream.duo {
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Share This Profile", comment: "Sheet action"), style: .default) { _ in
                let vc = Share.createShareSheetProfile(stream.primaryAccount, anchor: self.recents.selectedCell!, source: "StreamSheet")
                self.present(vc, animated: true, completion: nil)
                Answers.logCustomEvent(withName: "Stream Sheet Option", customAttributes: ["Option": "ShareOtherAccount"])
                })
        }

        // More...
        sheet.addAction(UIAlertAction(title: NSLocalizedString("More...", comment: "Sheet action"), style: .default) { _ in
            Answers.logCustomEvent(withName: "Stream Sheet Option", customAttributes: ["Option": "More"])
            let moreSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            moreSheet.popoverPresentationController?.sourceView = sourceView
            moreSheet.popoverPresentationController?.sourceRect = sourceRect
            // Mute.
            let muteOption = stream.muted ?
                NSLocalizedString("Unmute Notifications", comment: "Sheet action") :
                NSLocalizedString("Mute Notifications", comment: "Sheet action")
            moreSheet.addAction(UIAlertAction(title: muteOption, style: .default) { _ in
                guard !stream.muted else {
                    stream.unmute()
                    return
                }
                // Show additional options for how long this stream should be muted
                let muteSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
                muteSheet.popoverPresentationController?.sourceView = sourceView
                muteSheet.popoverPresentationController?.sourceRect = sourceRect
                muteSheet.addAction(
                    UIAlertAction(title: NSLocalizedString("8 hours", comment: "Sheet Action"), style: .default) { _ in
                        stream.mute(until: (Date() as NSDate).addingHours(8))
                    })
                muteSheet.addAction(
                    UIAlertAction(title: NSLocalizedString("1 week", comment: "Sheet Action"), style: .default) { _ in
                        stream.mute(until: (Date() as NSDate).addingWeeks(1))
                    })
                muteSheet.addAction(
                    UIAlertAction(title: NSLocalizedString("Cancel", comment: "Sheet Action"), style: .cancel, handler: nil))
                self.present(muteSheet, animated: true, completion: nil)
                })
            // Clear conversation photo
            if stream.hasCustomImage {
                moreSheet.addAction(UIAlertAction(title: NSLocalizedString("Clear Conversation Photo", comment: "Sheet action"), style: .default) { _ in
                    stream.clearImage()
                    })
                Answers.logCustomEvent(withName: "Stream Sheet Option", customAttributes: ["Option": "ResetStreamImage"])
            }
            if stream.duo {
                // Block a user.
                let blockAccount = stream.primaryAccount
                moreSheet.addAction(UIAlertAction(title: NSLocalizedString("Report & Block", comment: "Sheet action"), style: .destructive) { _ in
                    let alert = UIAlertController(
                        title: String.localizedStringWithFormat(
                            NSLocalizedString("Report & Block %@?", comment: "Text for block user confirmation dialog"),
                            blockAccount.displayName),
                        message: NSLocalizedString("Blocked contacts will not be able to talk to any conversation you are a part of. This is IRREVERSIBLE.", comment: "Alert title"),
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(
                        title: NSLocalizedString("Report & Block", comment: "Alert action"),
                        style: .destructive,
                        handler: { _ in
                            Intent.blockUser(identifier: String(blockAccount.id)).perform(BackendClient.instance)
                            StreamService.instance.removeStreamFromRecents(stream: stream)
                            self.selectedStream = self.streams.filter({ $0 != stream }).first
                            Answers.logCustomEvent(withName: "Stream Sheet Option", customAttributes: ["Option": "BlockConfirm"])
                    }))
                    alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: { _ in
                        Answers.logCustomEvent(withName: "Stream Sheet Option", customAttributes: ["Option": "BlockCancel"])
                    }))
                    self.present(alert, animated: true, completion: nil)
                    })
            }
            // Leave/Hide stream
            moreSheet.addAction(UIAlertAction(title: NSLocalizedString("Leave Conversation", comment: "Sheet action"), style: .destructive) { _ in
                StreamService.instance.leaveStream(streamId: stream.id)
                Answers.logCustomEvent(withName: "Stream Sheet Option", customAttributes: ["Option": "LeaveStream"])
                })
            // More... - Cancel.
            moreSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Sheet action"), style: .cancel, handler: nil))
            self.present(moreSheet, animated: true, completion: nil)
            })
        // Cancel.
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Sheet action"), style: .cancel) { _ in
            sheet.dismiss(animated: true, completion: nil)
            Answers.logCustomEvent(withName: "Stream Sheet Option", customAttributes: ["Option": "Cancel"])
            })
        self.present(sheet, animated: true, completion: nil)
        Answers.logCustomEvent(withName: "Stream Sheet Shown", customAttributes: nil)
    }

    // MARK: - MFMessageComposeViewControllerDelegate

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        // Dismiss the SMS UI.
        self.dismiss(animated: true, completion: nil)
        Answers.logCustomEvent(withName: "Chunk In SMS Complete", customAttributes: ["Result": result.description])

        guard result != MessageComposeResult.cancelled else {
            let vc = Share.createShareSheetFallback(
                controller.body,
                name: self.selectedStream?.otherParticipants.first?.contact?.name.rogerShortName,
                // TODO: This needs to be the actual chunk link.
                chunkURL: BackendClient.instance.session?.profileURL ?? SettingsManager.baseURL,
                anchor: self.recordButtonView,
                source: "StreamsViewController") { completed in
                    self.ensureNotificationPermissions()
            }
            self.present(vc, animated: true, completion: nil)
            return
        }
        self.ensureNotificationPermissions()
    }

    // MARK: - Private

    private var hintTooltip: TooltipView!
    private let conversationPhotoImagePicker = UIImagePickerController()
    private let attachmentImagePicker = UIImagePickerController()
    /// Tracks the app's active state so that appActive and appInactive are always called appropriately.
    private var knownActiveState = true {
        didSet {
            if oldValue == self.knownActiveState {
                return
            }
            if self.knownActiveState {
                self.appActive()
            } else {
                self.appInactive()
            }
            self.updateProximityMonitor()
        }
    }

    private var autoplayIndicatorView: AutoplayIndicatorView!
    private var statusIndicatorView: StatusIndicatorView!
    private var networkMonitor: NetworkMonitor!
    private var selectedStreamCard: StreamCardView?
    private var streamCardRefreshTimer: Timer?
    private var placeholder: PlaceholderCardView!
    private var viewInForeground = false {
        didSet {
            self.updateProximityMonitor()
        }
    }

    // Invite flow
    static var firstStreamParticipant: String?
    static var groupInviteToken: String?

    private func setupTutorialOverlay(_ tutorialView: OverlayView, holeFrame: CGRect) {
        //  Tap to listen tutorial view
        self.view.bringSubview(toFront: tutorialView)
        tutorialView.setupOverlay(holeFrame)
    }

    private func appActive() {
        self.refreshUI()
        // Refresh weather data when app is brought to foreground.
        WeatherService.instance.updateWeatherData()
    }

    private func appInactive() {
        // Don't attempt to update the UI in the background.
        self.streamCardRefreshTimer?.invalidate()
    }

    private func getUserActivityInfo() -> [AnyHashable: Any] {
        guard let stream = self.selectedStream else {
            return [:]
        }
        if let token = stream.inviteToken {
            return [
                "inviteToken": token,
                "streamId": NSNumber(value: stream.id as Int64),
            ]
        } else if stream.duo {
            let account = stream.primaryAccount
            return ["identifier": account.username ?? String(account.id)]
        } else {
            return ["streamId": NSNumber(value: stream.id as Int64)]
        }
    }

    private func refreshActiveStream(_ didChange: Bool) {
        defer {
            // Either ask for mic access, show a mic tutorial, or show a greeting message.
            self.updateHintTooltip()
            // Update unplayed streams counter
            self.updateUnplayedHint()
        }
        self.updateUserActivity()

        // TODO: This should probably be set from RecentStreamsCollectionView via an event.
        self.recents?.selectedCell?.isCurrentlySelected = true

        if let stream = self.selectedStream {
            self.recordButtonView.setEnabled(stream.canTalk)
            // Update the current temporary stream.
            self.temporaryStream = !self.streams.contains(stream) ? stream : nil
        }

        // TODO: WTF?
        if case .idle = AudioService.instance.state {
        } else if self.selectedStreamCard != nil {
            return
        }

        // Reset stream timer.
        self.resetStreamCardRefreshTimer()

        if !didChange, let card = self.selectedStreamCard {
            // Don't rebuild the entire contact card if the stream id didn't change.
            card.stream = self.selectedStream
            card.refresh()
            return
        }

        if let stream = self.selectedStream {
            let card = StreamCardView.create(stream, frame: self.streamCardContainerView.bounds, delegate: self)
            self.showNewCard(card)
        }
    }

    /// Create a group stream with the provided list of identifiers as participants
    private func createGroupStream(_ identifiers: [String]? = nil) {
        let participants: [Intent.Participant] = identifiers?.map { Intent.Participant(value: $0) } ?? []

        self.statusIndicatorView.showLoading()
        StreamService.instance.createStream(
            participants: participants,
            title: NSLocalizedString("Group", comment: "Default group name"),
            image: nil) { stream, error in
                self.statusIndicatorView.hide()
                guard let stream = stream , error == nil else {
                    let alert = UIAlertController(title: NSLocalizedString("Oops!", comment: "Alert title"),
                                                  message: NSLocalizedString("Something went wrong. Please try again!", comment: "Alert text"), preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("Okay", comment: "Alert action"), style: .cancel, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                    return
                }

                let streamDetails = self.storyboard?.instantiateViewController(withIdentifier: "StreamDetails") as! StreamDetailsViewController
                streamDetails.stream = stream
                self.navigationController?.pushViewControllerModal(streamDetails)
        }
    }
    
    private func resetStreamCardRefreshTimer() {
        self.streamCardRefreshTimer?.invalidate()
        self.streamCardRefreshTimer = Timer.scheduledTimer(timeInterval: 45.0, target: self, selector: #selector(StreamsViewController.refreshUI), userInfo: nil, repeats: false)
    }

    private func showNewCard(_ streamCard: StreamCardView) {
        if let previousCard = self.selectedStreamCard {
            UIView.transition(from: previousCard, to: streamCard, duration: 0.17, options: .transitionCrossDissolve) {
                _ in
                previousCard.destroy()
            }
        } else {
            // Insert the card at the bottom so it does not cover anything (i.e. the network issue view).
            self.streamCardContainerView.addSubview(streamCard)
        }
        self.selectedStreamCard = streamCard
    }

    private func showQuickInvite() {
        let vc = InviteViewController()
        self.present(vc, animated: true, completion: nil)
        Answers.logCustomEvent(withName: "Add Cell Tapped", customAttributes: nil)
    }

    private func streamSelected(_ stream: Stream) {
        guard self.selectedStream != stream else {
            return
        }

        // Stop anything that is playing/recording
        AudioService.instance.stop()

        // Select the new stream
        self.selectedStream = stream
        self.recents.scrollToSelectedStream()
        if self.presentedViewController is ContactPickerViewController ||
            self.presentedViewController is SettingsViewController {
            self.dismiss(animated: true, completion: nil)
        }
    }

    private func handleAttachmentSelected(_ stream: Stream) {
        self.streamSelected(stream)
        self.showAttachment()
    }

    private func streamShortcutSelected(_ stream: Stream) {
        self.selectedStream = stream
        self.recents.scrollToSelectedStream()
        AudioService.instance.startRecording(stream, reason: "3DTouchShortcut")
    }

    private func updateHintTooltip() {
        let toggleTalkTutorial: (Bool) -> Void = { show in
            if show {
                self.hintTooltip.hide()
                self.tapToTalkTutorialView.showAnimated()
            } else {
                self.tapToTalkTutorialView.hideAnimated()
            }
        }

        if self.hintTooltip == nil {
            self.hintTooltip = TooltipView(text: "", centerView: self.recordButtonView)
            self.view.insertSubview(self.hintTooltip, belowSubview: self.recordButtonView)
            self.hintTooltip.alpha = 0
        }

        // Reposition the tooltip to account for tutorial animations
        self.hintTooltip.layoutSubviews()

        // Show placeholder data and primer if there is no stream
        guard let stream = self.selectedStream else {
            self.placeholder.isHidden = false
            self.selectedStreamCard?.destroy()
            self.selectedStreamCard = nil
            self.hintTooltip.hide()
            self.toggleRecents(true)
            return
        }
        self.placeholder.isHidden = true

        if case .idle = AudioService.instance.state {
            if stream.unplayed {
                if !SettingsManager.didListen {
                    self.hintTooltip.hide()
                    self.tapToListenTutorialView.showAnimated()
                }
                toggleTalkTutorial(false)
                self.hintTooltip.hide()
                return
            }

            if !SettingsManager.didTapToRecord {
                toggleTalkTutorial(true)
                return
            }
        } else {
            self.tapToListenTutorialView.hideAnimated()
        }

        if case .recording = AudioService.instance.state , !SettingsManager.didSendChunk {
            self.hintTooltip.setText(NSLocalizedString("Tap to finish talking", comment: "Tooltip"))
            self.hintTooltip.show()
            return
        }

        // If there is a valid conversation, do not show a CTA.
        if !stream.getPlayableChunks().isEmpty || stream.currentUserHasReplied || stream.reachableParticipants.isEmpty {
            self.hintTooltip.hide()
            return
        }

        // There are no playable chunks, show the CTA.
        guard let cta = stream.callToAction else {
            self.hintTooltip.hide()
            return
        }

        self.hintTooltip.setText(cta)
        self.hintTooltip.show()
    }

    private func updateUnplayedHint() {
        let unplayedCount = StreamService.instance.unplayedCount
        self.unplayedCountLabel.text = unplayedCount.description
        self.unplayedCountLabel.isHidden = unplayedCount <= 0
    }

    private func updateProximityMonitor() {
        guard !UIAccessibilityIsVoiceOverRunning() else {
            return
        }
        
        ProximityMonitor.instance.active = (
            self.selectedStream != nil &&
            self.knownActiveState &&
            self.viewInForeground &&
            !AudioService.instance.deviceConnected
        )
    }

    private func updateUserActivity() {
        guard let stream = self.selectedStream else {
            return
        }
        let activity: NSUserActivity
        if let token = stream.inviteToken {
            activity = NSUserActivity(activityType: "com.rogertalk.activity.JoinStream")
            activity.title = stream.displayName
            activity.webpageURL = URL(string: "https://rogertalk.com/group/\(token)")
            if #available(iOS 9.0, *) {
                activity.keywords = Set(stream.otherParticipants.map { $0.displayName })
                activity.requiredUserInfoKeys = ["inviteToken", "streamId"]
            }
        } else if stream.duo {
            activity = NSUserActivity(activityType: "com.rogertalk.activity.SelectAccount")
            let account = stream.primaryAccount
            if #available(iOS 9.0, *) {
                activity.isEligibleForPublicIndexing = (account.username != nil)
            }
            activity.title = account.displayName
            activity.webpageURL = account.profileURL as URL
            if #available(iOS 9.0, *) {
                activity.requiredUserInfoKeys = ["identifier"]
            }
        } else {
            activity = NSUserActivity(activityType: "com.rogertalk.activity.SelectStream")
            activity.title = stream.displayName
            //activity.webpageURL = NSURL(string: "https://client.rogertalk.com/\(stream.id)")
            if #available(iOS 9.0, *) {
                activity.keywords = Set(stream.otherParticipants.map { $0.displayName })
                activity.requiredUserInfoKeys = ["streamId"]
            }
        }
        activity.userInfo = self.getUserActivityInfo()
        if #available(iOS 9.0, *) {
            let attribs = CSSearchableItemAttributeSet(itemContentType: kUTTypeData as String)
            attribs.title = activity.title
            // TODO: Cache!
            if let image = stream.image?.af_imageAspectScaled(toFill: CGSize(width: 300, height: 300)).af_imageRoundedIntoCircle() {
                attribs.thumbnailData = UIImagePNGRepresentation(image)
            }
            activity.contentAttributeSet = attribs
            activity.isEligibleForSearch = true
        }
        self.userActivity = activity
    }

    private func toggleRecents(_ show: Bool = false) {
        guard show else {
            UIView.animate(withDuration: 0.3, animations: {
                self.recents.transform = CGAffineTransform.identity
            }) 
            self.darkOverlayView.hideAnimated()
            return
        }

        self.recents.setContentOffset(CGPoint.zero, animated: false)
        UIView.animate(withDuration: 0.3, animations: {
            self.recents.transform = CGAffineTransform.identity.translatedBy(x: 0, y: -174)
        }) 
        self.darkOverlayView.showAnimated()

        guard let cell = self.recents.visibleCells.first , UIAccessibilityIsVoiceOverRunning() else {
            return
        }

        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, cell)
    }

    dynamic private func showAutoplayIndicator() {
        self.autoplayIndicatorView.show()
        self.darkOverlayView.showAnimated()
    }

    private func attachNewItem() {
        guard let stream = self.selectedStream else {
            return
        }

        // Attachment options
        let sheet = UIAlertController(title: "",
                                      message: NSLocalizedString("Attach a photo or a web link to the conversation.", comment: "Attach item alert title"),
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Take Photo", comment: "Alert action"), style: .default) { _ in
            // Handle image attachment
            self.attachmentImagePicker.sourceType = .camera
            self.present(self.attachmentImagePicker, animated: true) {
                sheet.dismiss(animated: true, completion: nil)
            }
            Answers.logCustomEvent(withName: "Attach New Shown", customAttributes: ["Action": "Take Photo"])
            })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Choose Photo", comment: "Alert action"), style: .default) { _ in
            // Handle image attachment
            self.attachmentImagePicker.sourceType = .photoLibrary
            self.present(self.attachmentImagePicker, animated: true) {
                sheet.dismiss(animated: true, completion: nil)
            }
            Answers.logCustomEvent(withName: "Attach New Shown", customAttributes: ["Action": "Choose Photo"])
            })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Link from Clipboard", comment: "Alert action"), style: .default) { _ in
            // Handle link attachment
            guard let urlString = UIPasteboard.general.string,
                let url = URL(string: urlString) else {
                    return
            }
            stream.addAttachment(Attachment(url: url))
            Answers.logCustomEvent(withName: "Attach New Shown", customAttributes: ["Action": "Link"])
            })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel) { _ in
            Answers.logCustomEvent(withName: "Attach New Shown", customAttributes: ["Action": "Cancel"])
            })
        self.present(sheet, animated: true, completion: nil)
    }

    // MARK: - Event Handlers

    private func openedByLink(_ profile: Profile?, inviteToken: String?) {
        _ = self.navigationController?.popToRootViewController(animated: false)

        self.statusIndicatorView.showLoading()
        // Join group if there was an invite token
        if let token = inviteToken {
            StreamService.instance.joinGroup(inviteToken: token) { _ in
                self.statusIndicatorView.hide()
            }
        }

        guard let profile = profile else {
            return
        }

        StreamService.instance.getOrCreateStream(participants: [Intent.Participant(value: profile.identifier)], showInRecents: true) {
            self.statusIndicatorView.hide()
            if let stream = $0 {
                // Stop any playback/recording and select the new stream
                AudioService.instance.stop()
                self.selectedStream = stream
                self.recents.scrollToSelectedStream()
            } else if let error = $1 {
                print("WARNING: Failed to select stream (\(error))")
            }
        }
    }

    private func handleNotificationSettingsChanged(_ notificationSettings: UIUserNotificationSettings) {
        guard notificationSettings.types == UIUserNotificationType() else {
            // Nothing to do.
            return
        }

        UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
    }

    private func recentStreamsChanged(_ newStreams: [Stream], diff: StreamService.StreamsDiff) {
        self.streams = newStreams
        self.updateUnplayedHint()

        // TODO: Different logic for push notifications?
        self.recents.applyDiff(diff)
 
        if let stream = self.temporaryStream , self.streams.contains(stream) {
            // The temporary stream is now an actual recent stream.
            self.temporaryStream = nil
        } else if self.temporaryStream == nil &&
            (self.selectedStream == nil || !self.streams.contains(self.selectedStream!)) {
            // If there is no selection, select the first new stream
            self.selectedStream = self.streams.first
        }

        self.updateHintTooltip()
    }

    private func handleApplicationActive(_ active: Bool) {
        self.knownActiveState = active
        if active {
            self.toggleRecents(false)
        }
    }

    private func handleNewChunkReceived(_ stream: Stream) {
        // Scroll to the front to show that there is a new stream, but do not select it.
        self.recents.scrollToBeginningIfIdle()
        // Play immediately if it is an autoplay stream.
        guard case .idle = AudioService.instance.state
            , SettingsManager.autoplayAll &&
                (self.knownActiveState || AudioService.instance.deviceConnected) else {
            return
        }
        self.selectedStream = stream
        AudioService.instance.playStream(stream, preferLoudspeaker: true, reason: "Autoplay")
    }

    private func handleAudioStateChange(_ oldState: AudioService.State) {
        switch (oldState, AudioService.instance.state) {
        case (.idle, .playing):
            self.hideTutorialViews()
        case (_, .recording):
            if let stream = self.selectedStream {
                self.talkingHintLabel.text = String.localizedStringWithFormat(
                    NSLocalizedString("Talking to %@...", comment: "Info shown while recording"),
                    stream.shortTitle)
            } else {
                self.talkingHintLabel.text = NSLocalizedString("Talking...", comment: "Info shown while recording")
            }
            self.toggleRecordingOverlay(true)
            self.hideTutorialViews()
        case (.recording, _):
            self.toggleRecordingOverlay(false)
            self.refreshActiveStream(true)
        case (.playing, _):
            StreamService.instance.updateUnplayedCount()
        default:
            break
        }
    }

    // TODO: Move the RecordingOverlay into a separate UI component
    private func toggleRecordingOverlay(_ show: Bool) {
        guard show else {
            self.talkingToHintView.isHidden = true
            self.sentLabel.isHidden = false
            self.sentLabel.pulse(1.2)
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(500 * NSEC_PER_MSEC)) / Double(NSEC_PER_SEC)) {
                self.recordingOverlayView.hideAnimated()
            }
            return
        }

        self.talkingToHintView.isHidden = false
        self.sentLabel.isHidden = true
        self.recordingOverlayView.showAnimated()
    }

    private func hideTutorialViews() {
        self.tapToTalkTutorialView.hideAnimated()
        self.tapToListenTutorialView.hideAnimated()
    }

    /// If any of the participants cannot be reached, invite via SMS
    private func handleChunkSent(_ stream: Stream, chunk: SendableChunk) {
        SettingsManager.didSendChunk = true
        self.updateHintTooltip()

        if let token = chunk.token , stream is ShareStream {
            let vc = Share.createShareSheetFallback(nil, name: nil, chunkURL: BackendClient.instance.session!.profileURLWithChunkToken(token), anchor: self.recordButtonView, source: "Share stream")
            self.present(vc, animated: true, completion: nil)
            return
        }

        if stream.group && !stream.otherParticipants.contains(where: { $0.active }) {
            let vc = UIAlertController(title: "Oops!", message: "There are no users on this group that are active on Roger. Follow up with your invites!", preferredStyle: .alert)
            vc.addAction(UIAlertAction(title: "Okay", style: .default, handler: { _ in
                self.openStreamDetails()
            }))
            self.present(vc, animated: true, completion: nil)
        }
    }

    private func inviteUsers(_ identifiers: [String], token: String, message: String? = nil) {
        guard MFMessageComposeViewController.canSendText() else {
            let name = identifiers.count == 1 ? ContactService.shared.contactIndex[identifiers[0]]?.name.rogerShortName : nil
            let vc = Share.createShareSheetFallback(
                nil,
                name: name,
                chunkURL: BackendClient.instance.session!.profileURLWithChunkToken(token),
                anchor: self.recordButtonView,
                source: "Streams")
            self.present(vc, animated: true, completion: nil)
            return
        }

        let messageComposer = Share.createMessageComposer(token, message: message, recipients: identifiers, delegate: self)
        messageComposer.messageComposeDelegate = self
        self.present(messageComposer, animated: true, completion: nil)
        Answers.logCustomEvent(withName: "Send Chunk In SMS Shown", customAttributes: nil)
    }

    private func handleStreamChanged() {
        self.updateHintTooltip()
        self.updateUnplayedHint()
    }

    private func handleProximityChange(_ againstEar: Bool) {
        guard case .idle = AudioService.instance.state , againstEar else {
            return
        }

        guard let stream = self.selectedStream else {
            return
        }
        AudioService.instance.playStream(stream, reason: "RaisedToEar")
        SettingsManager.didListen = true
    }

    private func notificationReceived(_ notif: Notification, swiped: Bool) {
        // TODO: Handle different notification types better.
        // TODO: When switching to VoIP, don't treat rank as a string.
        let rankValue = notif.data["rank"] as? Int ?? (notif.data["rank"] as? String).flatMap({ Int($0) })
        guard let rank = rankValue , notif.type == "top-talker" && swiped else {
            return
        }
        let url = BackendClient.instance.session?.profileURL ?? SettingsManager.baseURL
        let vc = Share.createShareSheet(
            DynamicActivityItem(
                String.localizedStringWithFormat(
                    NSLocalizedString("I ranked #%d on Roger’s top talkers this week! 🏆 %@", comment: "Top talker share text"),
                    rank, url as NSURL),
                specific: [
                    UIActivityType.postToTwitter: String.localizedStringWithFormat(
                        NSLocalizedString("🏆 Ranked #%d on @helloRoger top talkers this week! 🎉 %@ #TalkMore", comment: "Top talker Twitter share text"),
                        rank, url as NSURL),
                ]),
            anchor: self.recordButtonView,
            source: "TopTalkerNotification",
            bubble: (
                NSLocalizedString("You're a Top Talker!", comment: "Bubble above top talker share sheet"),
                String.localizedStringWithFormat(
                    NSLocalizedString("🏆 Ranked #%d on Roger’s top talkers this week!", comment: "Bubble above top talker share sheet"),
                    rank)
            )
        )
        self.present(vc, animated: true, completion: nil)
    }
}

class PlaceholderCardView : UIView {
    static func create(_ frame: CGRect) -> PlaceholderCardView {
        let card =
            Bundle.main.loadNibNamed("PlaceholderCardView", owner: self, options: nil)?[0] as! PlaceholderCardView
        card.frame = frame
        return card
    }

    override func awakeFromNib() {
        self.backgroundColor = UIColor.clear
    }
}
