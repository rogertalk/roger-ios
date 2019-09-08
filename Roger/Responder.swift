import AVFoundation
import ContactsUI
import CoreLocation
import Crashlytics
import Fabric
import FBSDKMessengerShareKit
import Google
import NotificationCenter
import PushKit

// TODO: Flesh this out a lot more to handle notification logic.
struct Notification {
    let type: String
    let data: [String: Any]
    let local: Bool
}

@UIApplicationMain
class Responder: UIResponder,
    GGLInstanceIDDelegate,
    CLLocationManagerDelegate,
    UIApplicationDelegate,
    FBSDKMessengerURLHandlerDelegate {

    // MARK: - Static

    /// Fired when the application changes between active/inactive states.
    static let applicationActiveStateChanged = Event<Bool>()
    /// Fired when the sign up process for a bot is completed.
    static let botSetupComplete = Event<URL>()
    /// Fired whenever a new chunk is received.
    static let newChunkReceived = Event<Stream>()
    /// Fired when a notification has been received. The second value will be true if the notification was swiped; otherwise, the notification was received in the app.
    static let notificationReceived = Event<(Notification, Bool)>()
    /// Fired whenever the user notification settings change.
    static let notificationSettingsChanged = Event<UIUserNotificationSettings>()
    /// Fired when the app is opened via rogertalk://v2/open.
    static let openedByLink = Event<(Profile?, String?)>()
    /// Fired when a 3D Touch shortcut for a stream is selected.
    static let streamShortcutSelected = Event<Stream>()
    /// Fired when the user locks the screen.
    static let userLockedScreen = Event<Void>()
    /// Fired when a user navigates to a stream from outside the app.
    static let userSelectedStream = Event<Stream>()
    /// Fired when a user taps an attachment notification.
    static let userSelectedAttachment = Event<Stream>()
    /// Fired when the user navigates to a URL on the website.
    static let websiteNavigated = Event<URL>()
    static var backgroundView: UIView? = nil

    static func updateLocation() {
        guard
            SettingsManager.hasLocationPermissions,
            let session = BackendClient.instance.session,
            session.shareLocation,
            let responder = UIApplication.shared.delegate as? Responder,
            (responder.lastLocationUpdate as NSDate).minutesAgo() > 1.0
        else {
            return
        }
        // Refresh user's current location.
        responder.locationManager.requestLocation()
    }

    // MARK: - Public instance

    var window: UIWindow?

    override init() {
        self.registry = PKPushRegistry(queue: DispatchQueue.main)
        super.init()

        self.mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
        AudioService.instance.currentChunkChanged.addListener(self, method: Responder.handleCurrentChunkChanged)
        BackendClient.instance.loggedIn.addListener(self, method: Responder.handleLogIn)
        BackendClient.instance.sessionChanged.addListener(self, method: Responder.handleSessionChange)
        StreamService.instance.recentStreamsChanged.addListener(self, method: Responder.handleRecentStreamsChange)

        // Ensure any muted streams are now unmuted.
        SettingsManager.updateMutedStreams()

        // Set up VoIP.
        self.registry.delegate = self
        self.registry.desiredPushTypes = [.voIP]

        // Re-register cached push token.
        if let token = self.registry.pushToken(forType: .voIP) {
            let hexToken = token.hex
            SettingsManager.pushKitToken = hexToken
            if BackendClient.instance.session != nil {
                registerDevice(hexToken, platform: "pushkit")
            }
        }
    }

    // MARK: - UIApplicationDelegate

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        Fabric.with([Crashlytics.self])

        // Initialize the Google Cloud Messaging configuration.
        var configureError: NSError?
        GGLContext.sharedInstance().configureWithError(&configureError)
        assert(configureError == nil, "Error configuring Google services: \(configureError)")
        self.gcmSenderId = GGLContext.sharedInstance().configuration.gcmSenderID

        // Let the app update every now and then.
        application.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalMinimum)

        // Emit an event when the screen is locked.
        let callback: CFNotificationCallback = {
            (center, observer, name, object, userInfo) in
            Responder.userLockedScreen.emit()
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            callback,
            "com.apple.springboard.lockcomplete" as CFString,
            nil,
            .deliverImmediately)

        Answers.logCustomEvent(withName: "App Launched", customAttributes: [
            "VoiceOver": UIAccessibilityIsVoiceOverRunning().description,
            "LivePlay": SettingsManager.autoplayAll.description
            ])
        if UIAccessibilityIsVoiceOverRunning() {
            SettingsManager.didListen = true
            SettingsManager.didTapToRecord = true
            Answers.logCustomEvent(withName: "VoiceOver User", customAttributes: nil)
        }

        if let session = BackendClient.instance.session {
            // Ask for a device token from APNS.
            application.registerForRemoteNotifications()
            if session.active {
                // Set up the stream service.
                StreamService.instance.loadStreamsAndIntegrationsFromCache()
            }
            self.setRootViewController(session.didSetDisplayName ? "Root" : "SetName")
        } else {
            self.setRootViewController("GetStarted")
        }

        // Set up notifications
        Responder.setupNotificationActions()
        self.pruneExpectedNotifs()

        // Configure FB Messenger URL handler for the "Reply" flow
        self.messengerURLHandler.delegate = self

        if !SettingsManager.didScheduleGroupPrimerNotif &&
            SettingsManager.hasNotificationsPermissions {
            SettingsManager.didScheduleGroupPrimerNotif = true
            let groupPrimerNotif = UILocalNotification()
            groupPrimerNotif.soundName = "roger.mp3"
            groupPrimerNotif.alertBody = NSLocalizedString("NOTIFICATION_GROUP_PRIMER", value: "😋 The best way to use Roger is in a group. Try making one now!", comment: "Group Primer notification")
            groupPrimerNotif.soundName = "roger.mp3"
            groupPrimerNotif.userInfo = ["type" : Responder.groupPrimerNotifIdentifier]
            groupPrimerNotif.fireDate = (Date() as NSDate).addingDays(2)
            UIApplication.shared.scheduleLocalNotification(groupPrimerNotif)
        }

        SettingsManager.updateScreenAutolockEnabled()

        // Note: Returning false here breaks the application shortcuts.
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // These are no longer needed
        self.cancelAllLocalNotif(Responder.secondPushNotifIdentifier)

        if Responder.backgroundView == nil && !UIAccessibilityIsVoiceOverRunning() {
            // Add gradients for the record button smile background
            // This size and positioning ensures it covers the size of the smile
            let view = UIView(frame: self.window!.frame)
            let gradient = CAGradientLayer()
            gradient.frame = view.frame
            gradient.colors = rogerGradientColors
            view.layer.addSublayer(gradient)
            self.window!.insertSubview(view, at: 0)
            Responder.backgroundView = view
        }

        Responder.applicationActiveStateChanged.emit(true)
        guard let session = BackendClient.instance.session else {
            // Nothing more to do if we're not logged in.
            return
        }
        if (Date() as NSDate).isLaterThan(session.expires as Date!), let token = session.refreshToken {
            // The access token expired, so refresh it.
            // TODO: This also needs to happen automatically when the token is about to expire.
            // TODO: Refresh session logic should be moved into BackendClient.
            // TODO: Refresh session should load services too
            self.refreshSession(token)
        } else {
            StreamService.instance.loadStreams()
            StreamService.instance.loadServices()
            StreamService.instance.loadBots()
            Intent.getOwnProfile().perform(BackendClient.instance)
        }
        self.lastLocationUpdate = Date.distantPast
        Responder.updateLocation()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        application.applicationIconBadgeNumber = StreamService.instance.unplayedCount
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Responder.applicationActiveStateChanged.emit(false)
    }

    func application(_ application: UIApplication, didReceive notification: UILocalNotification) {
        // TODO: Handle multiple types of notifications better.
        if let data = notification.userInfo as? [String: Any], let type = data["type"] as? String {
            let notif = Notification(type: type, data: data, local: true)
            Responder.notificationReceived.emit((notif, application.applicationState != .active))
            Answers.logCustomEvent(withName: "Notification swiped", customAttributes: ["type": type])
        }

        guard let
            streamId = (notification.userInfo?["stream_id"] as? NSNumber).flatMap({ $0.int64Value }),
            let stream = StreamService.instance.streams[streamId] else {
            return
        }

        Responder.clearStreamNotifications(stream.id)

        guard application.applicationState != .active else {
            return
        }

        if let type = notification.userInfo?["type"] as? String, type == Responder.attachmentNotifIdentifier {
            Responder.userSelectedAttachment.emit(stream)
        } else {
            Responder.userSelectedStream.emit(stream)
        }
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Report to GCM that we received this push notification.
        GCMService.sharedInstance().appDidReceiveMessage(userInfo)

        let alert = (userInfo["alert"] as? String) == "true"
        let apiVersion = (userInfo["api_version"] as? String) ?? "0"
        let notificationId = (userInfo["gcm.message_id"] as? String) ?? ""

        // Only handle recognized push notifications.
        guard let (type, data) = self.parsePushNotification(userInfo) else {
            completionHandler(.noData)
            // TODO: Create a reporting module that handles reporting to multiple places.
            let type = (userInfo["type"] as? String) ?? "unknown"
            Answers.logCustomEvent(withName: "Failed To Parse Push Notification", customAttributes: [
                "API Version": apiVersion,
                "Type": type,
            ])
            return
        }

        let notif = Notification(type: type, data: data, local: false)
        Responder.notificationReceived.emit((notif, application.applicationState != .active))

        // Reusable logic depending on if the app was in foreground or not when notif came in.
        let didEnterForeground = application.applicationState == .inactive
        func handleStreamNotification(_ stream: Stream, hasChunk: Bool = false, vibrateIfInApp: Bool = true) {
            if hasChunk {
                // Ensure that the stream is part of recents before we alert the user.
                StreamService.instance.includeStreamInRecents(stream: stream)
                Responder.newChunkReceived.emit(stream)
            }
            if !alert {
                // Don't take action in the UI if this is a background push.
                return
            }
            if didEnterForeground {
                // If the app was activated via push notif, set that as the selected stream.
                Responder.userSelectedStream.emit(stream)
                Answers.logCustomEvent(withName: "Opened From Notification", customAttributes: ["Type": type])
            } else if vibrateIfInApp {
                // The notification was received while the user was in the app.
                AudioService.instance.vibrate()
            }
        }

        switch type {
        case "account-change":
            if let accountData = data["account"] as? DataType {
                BackendClient.instance.updateAccountData(accountData)
            }
            completionHandler(.noData)
        case "stream-change":
            // Stream metadata changed (there are no chunks included in this data).
            if let
                streamData = data["stream"] as? DataType,
                let stream = StreamService.instance.updateWithStreamData(data: streamData)
            {
                handleStreamNotification(stream, vibrateIfInApp: false)
            }
            completionHandler(.noData)
        case "stream-chunk":
            // There is a new chunk in the stream. The data does not contain stream metadata.
            guard let chunk = data["chunk"] as? [String: Any] else {
                completionHandler(.noData)
                return
            }

            // Cache the audio file immediately and report to the system when it's done.
            AudioService.instance.cacheRemoteAudioURL(URL(string: chunk["audio_url"] as! String)!) {
                success in
                completionHandler(success ? .newData : .noData)
            }

            guard let streamIdString = data["stream_id"] as? String, let streamId = Int64(streamIdString) else {
                NSLog("%@", "WARNING: Failed to parse stream id from chunk update\n\(data)")
                return
            }

            guard let stream = StreamService.instance.updateWithStreamChunkData(id: streamId, chunkData: chunk) else {
                // We didn't have the stream locally, so get it from the backend.
                Intent.getStream(id: streamId).perform(BackendClient.instance) {
                    guard let data = $0.data , $0.successful else {
                        NSLog("%@", "WARNING: Failed to get stream with id \(streamId)")
                        return
                    }
                    let stream = StreamService.instance.updateWithStreamData(data: data)!
                    handleStreamNotification(stream, hasChunk: true)
                }
                Answers.logCustomEvent(withName: "Requested Stream Because Of Push", customAttributes: nil)
                return
            }
            // TODO: The notification should be scheduled even if we don't know the stream.
            // TODO: Move this elsewhere.
            if !alert && application.applicationState == .background {
                // Remove all visible and future local notifications.
                self.cancelAllLocalNotif(Responder.secondPushNotifIdentifier)
                self.scheduleSecondPushNotif(stream, chunkData: chunk)
            }

            handleStreamNotification(stream, hasChunk: true)
        case "stream-buzz":
            if let
                streamId = (data["stream_id"] as? String).flatMap({ Int64($0) }),
                let stream = StreamService.instance.streams[streamId]
            {
                handleStreamNotification(stream, vibrateIfInApp: false)
            }
            completionHandler(.noData)
        case "stream-status":
            guard let
                accountId = (data["sender_id"] as? String).flatMap({ Int64($0) }),
                let status = (data["status"] as? String).flatMap({ ActivityStatus(rawValue: $0) }),
                let streamId = (data["stream_id"] as? String).flatMap({ Int64($0) }),
                let stream = StreamService.instance.streams[streamId]
            else {
                NSLog("%@", "WARNING: Failed to update stream status\n\(data)")
                completionHandler(.noData)
                return
            }
            let estimatedDuration = (data["estimated_duration"] as? String).flatMap { Int($0) }
            stream.setStatusForParticipant(accountId, status: status, estimatedDuration: estimatedDuration)
            completionHandler(.noData)
        default:
            NSLog("%@", "WARNING: Unhandled notification type: \(type)")
            completionHandler(.noData)
        }
    }

    func application(_ application: UIApplication, handleActionWithIdentifier identifier: String?, forRemoteNotification userInfo: [AnyHashable: Any], completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func application(_ application: UIApplication, handleActionWithIdentifier identifier: String?, for notification: UILocalNotification, completionHandler: @escaping () -> Void) {
        defer {
            completionHandler()
        }

        guard let identifier = identifier,
            let userInfo = notification.userInfo,
            let streamId = (userInfo["stream_id"] as? NSNumber)?.int64Value else {
                return
        }

        switch identifier {
        case Responder.buzzActionIdentifier:
            Intent.buzz(streamId: streamId).perform(BackendClient.instance)
        case Responder.listenActionIdentifier:
            guard let stream = StreamService.instance.streams[streamId] else {
                return
            }
            AudioService.instance.playStream(stream, preferLoudspeaker: true)
        default:
            break
        }
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
        Answers.logCustomEvent(withName: "Activity Continuation", customAttributes: [
            "Type": userActivity.activityType,
        ])
        switch userActivity.activityType {
        case NSUserActivityTypeBrowsingWeb:
            guard let url = userActivity.webpageURL else {
                return false
            }
            Responder.websiteNavigated.emit(url)
            let pieces = url.path.components(separatedBy: "/")
            // TODO: Handle chunk tokens somehow.
            switch pieces[1] {
            case "about", "auth", "embed", "faq", "forward", "help", "legal", "login", "press", "services":
                return false
            case "group" where pieces.count == 3:
                Responder.openedByLink.emit((nil, pieces[2]))
            default:
                let profile = Profile(identifier: pieces[1])
                Responder.openedByLink.emit((profile, nil))
            }
            return true
        case "com.rogertalk.activity.JoinStream":
            guard let
                streamId = (userActivity.userInfo?["streamId"] as? NSNumber).flatMap({ $0.int64Value }),
                let token = userActivity.userInfo?["inviteToken"] as? String
            else {
                return false
            }
            if let stream = StreamService.instance.streams[streamId] {
                Responder.userSelectedStream.emit(stream)
            } else {
                Responder.openedByLink.emit((nil, token))
            }
            return true
        case "com.rogertalk.activity.SelectAccount":
            guard let identifier = userActivity.userInfo?["identifier"] as? String else {
                return false
            }
            Responder.openedByLink.emit((Profile(identifier: identifier), nil))
            return true
        case "com.rogertalk.activity.SelectStream":
            guard let
                streamId = (userActivity.userInfo?["streamId"] as? NSNumber).flatMap({ $0.int64Value }),
                let stream = StreamService.instance.streams[streamId]
            else {
                return false
            }
            Responder.userSelectedStream.emit(stream)
            return true
        case "com.rogertalk.activity.Talk":
            guard let accountId = (userActivity.userInfo?["account_id"] as? NSNumber)?.int64Value else {
                return false
            }

            if let stream = StreamService.instance.streams.values.first(where: { stream in
                stream.duo && stream.otherParticipants.first!.id == accountId
            }) {
                Responder.streamShortcutSelected.emit(stream)
            } else {
                // TODO: Move elsewhere
                StreamService.instance.getOrCreateStream(participants: [Intent.Participant(value: accountId.description)]) {stream, error in
                    guard let stream = stream, error == nil else {
                        return
                    }
                    Responder.streamShortcutSelected.emit(stream)
                }
            }
            return true
        default:
            return false
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Set up GCM to push notifications to this device.
        let config = GGLInstanceIDConfig.default()
        config?.delegate = self
        GGLInstanceID.sharedInstance().start(with: config)
        // TODO: Make the sandbox option dynamic.
        self.gcmOptions = [
            kGGLInstanceIDRegisterAPNSOption: deviceToken,
            kGGLInstanceIDAPNSServerTypeSandboxOption: false,
        ]
        GGLInstanceID.sharedInstance().token(withAuthorizedEntity: self.gcmSenderId, scope: kGGLInstanceIDScopeGCM, options: self.gcmOptions, handler: self.registrationHandler)
    }

    func application(_ application: UIApplication, didRegister notificationSettings: UIUserNotificationSettings) {
        Responder.notificationSettingsChanged.emit(notificationSettings)
    }

    func application(_ application: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey: Any]) -> Bool {
        // Check if this is a link from Facebook Messenger
        if let sourceApplication = options[UIApplicationOpenURLOptionsKey.sourceApplication] as? String ,
            self.messengerURLHandler.canOpen(url, sourceApplication: sourceApplication) {
                self.messengerURLHandler.open(url, sourceApplication: sourceApplication)
                return true
        }

        guard url.scheme == "rogertalk" else {
            if url.scheme == "rogerbot" {
                Responder.botSetupComplete.emit(url)
                return true
            }
            // TODO: Handle rogertalk.com links.
            return false
        }

        // Our app links have scheme rogertalk:// and the host will be a version (e.g., "v1")
        guard let version = url.host else {
            return false
        }
        let components = url.pathComponents
        switch version {
        case "v1":
            switch components[1] {
            case "refresh_token":
                if components.count > 2 {
                    self.refreshSession(components[2])
                    Answers.logCustomEvent(withName: "Opened By URI", customAttributes: ["Type": "RefreshToken"])
                }
            default:
                return false
            }
        case "v2":
            // Handle different types of actions.
            switch components[1] {
            case "open":
                guard let values = url.parseQueryString() else {
                    Responder.openedByLink.emit((nil, nil))
                    Answers.logCustomEvent(withName: "Opened By URI", customAttributes: ["Type": "NoData"])
                    return true
                }
                if let defaultIdentifier = values["default_identifier"]?.first {
                    ChallengeViewController.defaultIdentifier = defaultIdentifier
                }
                if let refreshToken = values["refresh_token"]?.first {
                    // If the link provides a refresh token, log the user in and use the first stream for public profile.
                    self.refreshSession(refreshToken) { _ in
                        let profile: Profile?
                        if let
                            (_, stream) = StreamService.instance.streams.first,
                            let other = stream.otherParticipants.first
                        {
                            profile = Profile(identifier: String(other.id), name: other.displayName.rogerShortName, imageURL: other.imageURL)
                        } else {
                            profile = nil
                        }
                        Responder.openedByLink.emit((profile, nil))
                    }
                    Answers.logCustomEvent(withName: "Opened By URI", customAttributes: ["Type": "RefreshToken"])
                    return true
                } else if let identifier = values["id"]?.first {
                    // Get a public profile out of the query string.
                    let profile = Profile(
                        identifier: identifier,
                        name: values["display_name"]?.first?.components(separatedBy: "+").first ?? "Someone",
                        imageURL: values["image_url"]?.first.flatMap { URL(string: $0) }
                    )
                    Answers.logCustomEvent(withName: "Opened By URI", customAttributes: ["Type": "PublicProfile"])
                    // Optionally there might be a chunk_token that we can use to join an open group
                    var groupInviteToken: String?
                    if let inviteToken = values["invite_token"]?.first , !inviteToken.isEmpty {
                        groupInviteToken = inviteToken
                    } else if let chunkToken = values["chunk_token"]?.first , !chunkToken.isEmpty {
                        groupInviteToken = "\(profile.id)/\(chunkToken)"
                    }
                    Responder.openedByLink.emit((profile, groupInviteToken))
                    return true
                } else {
                    NSLog("%@", "WARNING: Got an open request but failed to parse public profile data")
                    Responder.openedByLink.emit((nil, nil))
                    Answers.logCustomEvent(withName: "Opened By URI", customAttributes: ["Type": "Unknown"])
                    return true
                }
            default:
                return false
            }
        case "v3":
            // Handle different types of actions.
            switch components[1] {
            case "open":
                guard let values = url.parseQueryString() else {
                    Responder.openedByLink.emit((nil, nil))
                    Answers.logCustomEvent(withName: "Opened By URI", customAttributes: ["Type": "NoData"])
                    return true
                }

                if let defaultIdentifier = values["default_identifier"]?.first {
                    ChallengeViewController.defaultIdentifier = defaultIdentifier
                }

                // Check for a group invite token.
                var groupInviteToken: String?
                if let inviteToken = values["invite_token"]?.first , !inviteToken.isEmpty {
                    groupInviteToken = inviteToken
                }

                // Get the profile that invited this user.
                var profile: Profile?
                if let value = values["profile"]?.first,
                    let jsonData = value.data(using: String.Encoding.utf8),
                    let data = (try? JSONSerialization.jsonObject(with: jsonData, options: [])) as? [String: Any] {
                    profile = Profile(data)
                }

                if let refreshToken = values["refresh_token"]?.first {
                    // If the link provides a refresh token, log the user in and use the first stream for public profile.
                    self.refreshSession(refreshToken) { _ in
                        if let
                            (_, stream) = StreamService.instance.streams.first,
                            let other = stream.otherParticipants.first
                        {
                            profile = Profile(identifier: String(other.id), name: other.displayName.rogerShortName, imageURL: other.imageURL)
                        }
                        Responder.openedByLink.emit((profile, groupInviteToken))
                    }
                    Answers.logCustomEvent(withName: "Opened By URI", customAttributes: ["Type": "RefreshToken"])
                    return true
                }

                Responder.openedByLink.emit((profile, groupInviteToken))
                return true
            case "stream":
                guard let values = url.parseQueryString(), let streamId = values["id"]?.first.flatMap({ Int64($0) }) else {
                    return true
                }
                if let stream = StreamService.instance.streams[streamId] {
                    Responder.userSelectedStream.emit(stream)
                    return true
                }
                Intent.getStream(id: streamId).perform(BackendClient.instance) {
                    guard
                        let data = $0.data , $0.successful,
                        let stream = StreamService.instance.updateWithStreamData(data: data)
                        else
                    {
                        return
                    }
                    Responder.userSelectedStream.emit(stream)
                }
                return true
            default:
                return false
            }
        default:
            return false
        }
        return true
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        if let
            streamId = shortcutItem.userInfo?["streamId"] as? NSNumber,
            let stream = StreamService.instance.streams[streamId.int64Value]
        {
            Responder.streamShortcutSelected.emit(stream)
            Answers.logCustomEvent(withName: "Opened By 3D Touch", customAttributes: nil)
        }
        completionHandler(true)
    }

    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        StreamService.instance.loadStreams() { error in
            completionHandler(error == nil ? .newData : .failed)
        }
    }

    func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        if self.messengerURLHandler.canOpen(url, sourceApplication: sourceApplication) {
            self.messengerURLHandler.open(url, sourceApplication: sourceApplication)
        }

        return true
    }

    // MARK: - FBSDKMessengerURLHandlerDelegate

    func messengerURLHandler(_ messengerURLHandler: FBSDKMessengerURLHandler!, didHandleReplyWith context: FBSDKMessengerURLHandlerReplyContext!) {
        guard let participantId = context.metadata else {
            return
        }
        let identifiers: [Intent.Participant.Identifier] = [("", participantId)]
        StreamService.instance.getOrCreateStream(participants: [Intent.Participant(identifiers: identifiers)]) { stream, error in
            if error != nil {
                return
            }
            Responder.userSelectedStream.emit(stream!)
        }
    }

    // MARK: - GGLInstanceIDDelegate

    func onTokenRefresh() {
        GGLInstanceID.sharedInstance().token(withAuthorizedEntity: self.gcmSenderId, scope: kGGLInstanceIDScopeGCM, options: self.gcmOptions, handler: self.registrationHandler)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            NSLog("%@", "WARNING: Got invalid location")
            return
        }

        // We have valid coordinates, no need to keep updating.
        self.locationManager.stopUpdatingLocation()

        guard let session = BackendClient.instance.session , session.shareLocation else {
            print("Got location but not reporting it because user is not sharing location")
            return
        }

        // TODO: This can probably be removed.
        SettingsManager.lastKnownCoordinates = location.coordinate

        guard (self.lastLocationUpdate as NSDate).secondsAgo() > 1.0 else {
            // Update the location in the backend, but not more than once per second.
            return
        }
        // The timestamp is updated after the return so that an update every 0.9 seconds wouldn't hold off updates forever.
        self.lastLocationUpdate = Date()
        Intent.setLocation(location: location).perform(BackendClient.instance)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("%@", "WARNING: Location manager error: \(error)")
    }

    // MARK: - Private

    private static var didInitialSetupNotifications = false

    private let messengerURLHandler = FBSDKMessengerURLHandler()
    private let registry: PKPushRegistry

    /// Options for registering with GCM.
    private var gcmOptions = [String: Any]()
    /// The GCM sender id (project number).
    private var gcmSenderId: String?
    private var lastLocationUpdate = Date.distantPast
    private var mainStoryboard: UIStoryboard!

    lazy private var locationManager: CLLocationManager = {
        // Initialize location manager
        let location = CLLocationManager()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return location
    }()

    private func handleCurrentChunkChanged() {
        showListeningToChunkNotif()
    }

    private func handleLogIn(_ session: Session) {
        // Ask for a device token from APNS.
        UIApplication.shared.registerForRemoteNotifications()
        if let token = SettingsManager.pushKitToken {
            registerDevice(token, platform: "pushkit")
        }
    }

    private func handleRecentStreamsChange(_ newStreams: [Stream], diff: StreamService.StreamsDiff) {
        // Set up 3D Touch shortcuts.
        let store = CNContactStore()
        let type = "\(Bundle.main.bundleIdentifier).ApplicationShortcut.Record"
        let streams = newStreams.lazy.dropFirst().prefix(4)
        UIApplication.shared.shortcutItems = streams.map {
            let contact: CNContact
            if
                $0.duo,
                let identifier = $0.otherParticipants.first?.contact?.id,
                let result = try? store.unifiedContact(withIdentifier: identifier, keysToFetch: [])
            {
                contact = result
            } else {
                let fake = CNMutableContact()
                fake.givenName = $0.shortTitle
                contact = fake
            }
            return UIMutableApplicationShortcutItem(
                type: type,
                localizedTitle: String.localizedStringWithFormat(
                    NSLocalizedString("Talk to %@", comment: "3D Touch shortcut"),
                    $0.shortTitle),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(contact: contact),
                userInfo: ["streamId": NSNumber(value: $0.id)]
            )
        }
    }

    private func handleSessionChange() {
        Responder.updateLocation()
    }

    /// Request new session data from the backend using the provided refresh token.
    private func refreshSession(_ token: String, callback: ((Void) -> Void)? = nil) {
        Intent.refreshSession(refreshToken: token).perform(BackendClient.instance) { _ in
            callback?()
        }
    }

    /// Handle registration with GCM.
    private func registrationHandler(_ registrationToken: String?, error: Error?) {
        guard let token = registrationToken else {
            NSLog("%@", "WARNING: Registration to GCM failed with error: \(error?.localizedDescription)")
            return
        }
        registerDevice(token, platform: "gcm_ios")
    }

    func setRootViewController(_ identifier: String) {
        self.window?.rootViewController = self.mainStoryboard.instantiateViewController(withIdentifier: identifier)
    }

    //
    // MARK: Local Notifications
    //

    // Identifiers
    static let unlistenedNotifIdentifier = "unlistened"
    static let newChunkNotifIdentifier = "newChunk"
    static let secondPushNotifIdentifier = "secondPush"
    static let newStreamNotifIdentifier = "newStream"
    static let joinGroupNotifIdentifier = "joinGroup"
    static let participantsNotifIdentifier = "joinGroup"
    static let talkingNowNotifIdentifier = "talkingNow"
    static let listeningNowNotifIdentifier = "listeningNow"
    static let listeningToChunkNotifIdentifier = "listeningTo"
    static let groupPrimerNotifIdentifier = "groupPrimer"
    static let attachmentNotifIdentifier = "attachment"

    // Categories
    static let newChunkCategory = "CATEGORY_NEW_CHUNK"
    static let unlistenedNotifCategory = "CATEGORY_UNLISTENED_NOTIF"

    // Actions
    static let listenActionIdentifier = "listenAction"
    static let buzzActionIdentifier = "buzzAction"

    static func setUpNotifications() {
        let application = UIApplication.shared
        if !application.isRegisteredForRemoteNotifications {
            application.registerForRemoteNotifications()
        }

        Responder.setupNotificationActions()
    }

    private static func setupNotificationActions() {
        guard SettingsManager.hasNotificationsPermissions || Responder.didInitialSetupNotifications else {
            Responder.didInitialSetupNotifications = true
            return
        }

        let application = UIApplication.shared
        let listenAction = UIMutableUserNotificationAction()
        listenAction.identifier = Responder.listenActionIdentifier
        listenAction.title = NSLocalizedString("👂 listen", comment: "Notification action")
        listenAction.activationMode = .background

        let newChunkCategory = UIMutableUserNotificationCategory()
        newChunkCategory.identifier = Responder.newChunkCategory
        newChunkCategory.setActions([listenAction], for: .default)
        newChunkCategory.setActions([listenAction], for: .minimal)

        let notifSettings = UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: [newChunkCategory])
        application.registerUserNotificationSettings(notifSettings)
    }

    // TODO: Remove once we do away with remote notifs
    /// Parse the type and data of the push notification, validating everything along the way.
    private func parsePushNotification(_ userInfo: [AnyHashable: Any]) -> (type: String, data: [String: Any])? {
        // Every push notification should contain a type, a version and some data.
        guard let type = userInfo["type"] as? String else {
            NSLog("%@", "WARNING: Failed to get type of notification\n\(userInfo)")
            return nil
        }

        guard let versionString = userInfo["api_version"] as? String, let version = Int(versionString), version >= 10 else {
            NSLog("%@", "WARNING: Incompatible notification version\n\(userInfo)")
            return nil
        }

        // GCM converts all fields to strings, so we'll JSON parse anything that begins with "{".
        var data = [String: Any]()
        for (key, value) in userInfo {
            guard let key = key as? String else {
                continue
            }
            // Skip the non-data keys.
            if key == "api_version" || key == "aps" || key == "gcm.message_id" || key == "type" {
                continue
            }
            guard let value = value as? String else {
                NSLog("%@", "WARNING: Failed to treat notification data as [String: String]\n\(userInfo)")
                continue
            }
            if value.characters.first != "{" {
                data[key] = value
                continue
            }
            guard let jsonData = value.data(using: String.Encoding.utf8) else {
                NSLog("%@", "WARNING: JSON data contained invalid characters\n\(value)\n\(userInfo)")
                return nil
            }
            do {
                let object = try JSONSerialization.jsonObject(with: jsonData, options: [])
                data[key] = object
            } catch {
                NSLog("%@", "WARNING: Failed to parse JSON data\n\(userInfo)")
            }
        }

        return (type, data)
    }

    // MARK: - Local Notifs

    /// Schedule a second notif in case the user doesn't see the first one
    private func scheduleSecondPushNotif(_ stream: Stream, chunkData: [String: Any]) {
        guard let
            senderId = (chunkData["sender_id"] as? NSNumber).flatMap({ $0.int64Value }),
            let sender = stream.otherParticipants.filter({ $0.id == senderId }).first ,
            !UIAccessibilityIsVoiceOverRunning() else {
            return
        }
        // Schedule notification one minute after the chunk was sent.
        let localNotif = UILocalNotification()
        localNotif.alertBody = String.localizedStringWithFormat(
            NSLocalizedString("NOTIFICATION_TALKED_MINUTE_AGO", value: "😅 %@ talked a minute ago", comment: "Notification"),
            sender.remoteDisplayName.rogerShortName)
        let chunkEnd = (chunkData["end"] as? NSNumber).flatMap { TimeInterval($0.int64Value) / 1000 }!
        localNotif.fireDate = (Date(timeIntervalSince1970: chunkEnd) as NSDate).addingMinutes(1)
        localNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type": Responder.secondPushNotifIdentifier]
        UIApplication.shared.scheduleLocalNotification(localNotif)
    }

    private func cancelAllLocalNotif(_ type: String) {
        let application = UIApplication.shared
        guard let localNotifs = application.scheduledLocalNotifications else {
            return
        }
        localNotifs.filter({ $0.userInfo?["type"] as? String == type }).forEach {
            application.cancelLocalNotification($0)
        }
    }

    /// Walk through all expected notifs and get rid of any older than 1 day.
    private func pruneExpectedNotifs() {
        var notifsToKeep = [String: [Data]]()
        for (streamId, notifsData) in SettingsManager.expectedNotifs {
            var validNotifData = [Data]()
            for notifData in notifsData {
                let localNotif = NSKeyedUnarchiver.unarchiveObject(with: notifData) as! UILocalNotification
                // Only keep notifs that are less than a day old.
                if let date = localNotif.fireDate , (date as NSDate).hoursAgo() < 24 {
                    validNotifData.append(notifData)
                }
            }

            if notifsToKeep.count > 0 {
                notifsToKeep[streamId] = validNotifData
            }
        }

        SettingsManager.expectedNotifs = notifsToKeep
    }

    /// Merge the new notification with any others for the specified stream
    static func clearStreamNotifications(_ streamId: Int64) {
        let streamIdKey = String(streamId)

        // Track notifs that are currently shown
        if let allLaunchedNotifData = SettingsManager.expectedNotifs[streamIdKey] {
            // Cancel all other notifs shown or scheduled to be shown for this stream
            for notifData in allLaunchedNotifData {
                let notif = NSKeyedUnarchiver.unarchiveObject(with: notifData) as! UILocalNotification
                UIApplication.shared.cancelLocalNotification(notif)
            }

            SettingsManager.expectedNotifs.removeValue(forKey: streamIdKey)
        }
    }
}

// MARK: - PKPushRegistryDelegate

extension Responder: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, forType type: PKPushType) {
        let hexToken = credentials.token.hex
        SettingsManager.pushKitToken = hexToken
        if BackendClient.instance.session != nil {
            registerDevice(hexToken, platform: "pushkit")
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, forType type: PKPushType) {
        guard let data = payload.dictionaryPayload as? [String: Any] else {
            return
        }

        // Ignore vestigial notifs with the "alert" flag
        if (data["alert"] as? Bool) ?? false {
            return
        }

        guard let type = data["type"] as? String else {
            return
        }

        switch type {
        case "account-change":
            self.handleAccountChangePush(data)
        case "stream-attachment":
            self.handleAttachmentPush(data)
        case "stream-buzz":
            self.handleStreamBuzzPush(data)
        case "stream-change", "stream-image", "stream-listen", "stream-shareable", "stream-title":
            self.handleStreamChangePush(data)
        case "stream-chunk":
            self.handleStreamChunkPush(data)
        case "stream-chunk-text":
            self.handleStreamChunkTextPush(data)
        case "stream-new":
            self.handleNewStreamPush(data)
        case "stream-join":
            self.handleStreamJoinPush(data)
        case "stream-hidden", "stream-leave":
            self.handleStreamHiddenPush(data)
        case "stream-participants":
            self.handleStreamParticipantsPush(data)
        case "stream-participant-change":
            self.handleStreamParticipantChangePush(data)
        case "stream-status":
            self.handleStreamStatusPush(data)
        case "top-talker":
            self.handleTopTalkerPush(data)
        default:
            NSLog("%@", "WARNING: Unhandled notification type: \(type)")
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenForType type: PKPushType) {
        // TODO: Unregister device token in backend.
        NSLog("%@", "\(type) push notification invalidated!")
    }

    // MARK: - Handle VOIP Push

    private func handleAccountChangePush(_ data: [String: Any]) {
        if let accountData = data["account"] as? [String: Any] {
            BackendClient.instance.updateAccountData(accountData)
        }
    }

    /// Show a notification when an attachment is added or changed (but none if it is removed)
    private func handleAttachmentPush(_ data: [String: Any]) {
        guard let
            attachmentId = data["attachment_id"] as? String,
            let streamId = data["stream_id"] as? NSNumber,
            let stream = StreamService.instance.streams[streamId.int64Value],
            let senderId = (data["sender_id"] as? NSNumber)?.int64Value,
            let sender = stream.getParticipant(senderId) as? Participant,
            let attachment = stream.updateWithAttachmentData(attachmentId, data: data["attachment"] as? [String: Any])
        else {
            return
        }
        showAttachmentNotif(stream, sender: sender, attachment: attachment)
    }

    private func handleStreamChangePush(_ data: [String: Any]) {
        // Stream metadata changed (there are no chunks included in this data).
        guard let streamData = data["stream"] as? [String: Any] else {
            return
        }
        if StreamService.instance.updateWithStreamData(data: streamData) != nil {
            return
        }
        // If we get here, the stream didn't exist locally so we have to fetch it.
        guard let streamId = streamData["id"] as? NSNumber else {
            return
        }
        self.loadStream(streamId.int64Value)
        //NSLocalizedString("NOTIFICATION_LISTENING_UNKNOWN", value: "👂 Your friend just listened to you", comment: "Notification, just listened to your public chunk")
    }

    private func handleStreamBuzzPush(_ data: [String: Any]) {
        guard let
            streamData = data["stream"] as? [String: Any],
            let stream = StreamService.instance.updateWithStreamData(data: streamData),
            let accountId = (data["sender_id"] as? NSNumber)?.int64Value else {
                NSLog("%@", "WARNING: Failed to get stream from buzz\n\(data)")
                return
        }

        showBuzzNotif(stream, senderId: accountId)
    }

    private func handleStreamChunkPush(_ data: [String: Any]) {
        // There is a new chunk in the stream. The data does not contain stream metadata.
        guard let chunk = data["chunk"] as? [String: Any] else {
            return
        }

        // Cache the audio file immediately
        AudioService.instance.cacheRemoteAudioURL(URL(string: chunk["audio_url"] as! String)!)

        guard let streamId = data["stream_id"] as? NSNumber,
            let senderId = chunk["sender_id"] as? NSNumber else {
            NSLog("%@", "WARNING: Failed to parse stream chunk data\n\(data)")
            return
        }

        let handleStreamUpdate: (Stream) -> Void = { stream in
            guard stream.visible else {
                return
            }
            Responder.newChunkReceived.emit(stream)
            showStreamChunkNotif(stream, senderId: senderId.int64Value)
        }

        guard let stream = StreamService.instance.updateWithStreamChunkData(id: streamId.int64Value, chunkData: chunk) else {
            self.loadStream(streamId.int64Value, callback: handleStreamUpdate)
            return
        }

        handleStreamUpdate(stream)
    }

    private func handleStreamChunkTextPush(_ data: [String: Any]) {
        guard let chunk = data["chunk"] as? [String: Any],
            let streamId = (data["stream_id"] as? NSNumber)?.int64Value else {
            return
        }

        StreamService.instance.updateWithStreamChunkData(id: streamId, chunkData: chunk)
    }

    private func handleStreamHiddenPush(_ data: [String: Any]) {
        guard let streamId = data["stream_id"] as? NSNumber, let stream = StreamService.instance.streams[streamId.int64Value] else {
            return
        }
        StreamService.instance.removeStreamFromRecents(stream: stream)
    }

    private func handleNewStreamPush(_ data: [String: Any]) {
        guard let
            streamData = data["stream"] as? [String: Any],
            let senderId = (data["sender_id"] as? NSNumber)?.int64Value else {
                NSLog("%@", "WARNING: Failed to get stream from Stream-New\n\(data)")
                return
        }

        if let stream = StreamService.instance.updateWithStreamData(data: streamData) {
            showNewStreamNotif(stream, senderId: senderId)
            return
        }

        guard let streamId = (streamData["id"] as? NSNumber)?.int64Value else {
            return
        }

        self.loadStream(streamId) { stream in
            showNewStreamNotif(stream, senderId: senderId)
        }
    }

    private func handleStreamJoinPush(_ data: [String: Any]) {
        guard let streamId = (data["stream_id"] as? NSNumber)?.int64Value,
            let senderId = (data["sender_id"] as? NSNumber)?.int64Value else {
            NSLog("%@", "WARNING: Failed to get stream id from Stream-Join\n\(data)")
            return
        }

        self.loadStream(streamId) { stream in
            guard senderId != BackendClient.instance.session?.id else {
                return
            }
            showStreamJoinNotif(senderId, stream: stream)
        }
    }

    private func handleStreamParticipantsPush(_ data: [String: Any]) {
        guard let streamId = (data["stream_id"] as? NSNumber)?.int64Value,
            let senderId = (data["sender_id"] as? NSNumber)?.int64Value,
            let added = (data["added"] as? [NSNumber])?.map({ return $0.int64Value }),
            let removed = (data["removed"] as? [NSNumber])?.map({ return $0.int64Value }) else {
                NSLog("%@", "WARNING: Failed to get stream id from Stream-Participants\n\(data)")
                return
        }

        self.loadStream(streamId) { stream in
            guard senderId != BackendClient.instance.session?.id else {
                return
            }
            showStreamParticipantsNotif(senderId, stream: stream, added: added, removed: removed)
        }
    }

    private func handleStreamParticipantChangePush(_ data: [String: Any]) {
        guard let streamId = (data["stream_id"] as? NSNumber)?.int64Value,
            let participantData = (data["participant"] as? [String: Any]) else {
                return
        }

        let participant = Participant(data: participantData)
        let showParticipantChange: (Stream) -> Void = { stream in
            stream.updateParticipant(participant)
            showStreamParticipantChangedNotif(participant, stream: stream)
        }

        if let stream = StreamService.instance.streams[streamId] {
            showParticipantChange(stream)
            return
        }

        self.loadStream(streamId) { stream in
            showParticipantChange(stream)
            return
        }
    }

    private func handleStreamStatusPush(_ data: DataType) {
        guard let
            accountId = (data["sender_id"] as? NSNumber).flatMap({ $0.int64Value }),
            let status = (data["status"] as? String).flatMap({ ActivityStatus(rawValue: $0) }),
            let streamId = (data["stream_id"] as? NSNumber).flatMap({ $0.int64Value }),
            let stream = StreamService.instance.streams[streamId]
            else {
                NSLog("%@", "WARNING: Failed to update stream status\n\(data)")
                return
        }

        // Considered a new status if either the status or the sender has changed
        let shouldNotify = status != .Idle &&
            (stream.status != status || stream.currentlyActiveParticipant?.id != accountId)

        // Update stream status
        let estimatedDuration = (data["estimated_duration"] as? String).flatMap { Int($0) }
        stream.setStatusForParticipant(accountId, status: status, estimatedDuration: estimatedDuration)

        // Show the appropriate notif if there is a change
        if shouldNotify {
            showStreamStatusNotif(stream)
        }
    }

    private func handleTopTalkerPush(_ data: [String: Any]) {
        guard let rank = data["rank"] as? Int else {
            return
        }
        let notif = UILocalNotification()
        notif.alertBody = String.localizedStringWithFormat(
            NSLocalizedString("NOTIFICATION_TOP_TALKER", value: "🏆 You ranked #%d on Roger’s top talkers this week! #TalkMore 🎉", comment: "Notification"),
            rank)
        notif.userInfo = data
        UIApplication.shared.presentLocalNotificationNow(notif)
    }

    private func loadStream(_ streamId: Int64, callback: ((Stream) -> Void)? = nil) {
        Intent.getStream(id: streamId).perform(BackendClient.instance) {
            guard let data = $0.data , $0.successful else {
                NSLog("%@", "WARNING: Failed to get stream with id \(streamId)")
                return
            }
            let stream = StreamService.instance.updateWithStreamData(data: data)!
            if stream.visible {
                StreamService.instance.includeStreamInRecents(stream: stream)
            }
            callback?(stream)
        }
        Answers.logCustomEvent(withName: "Requested Stream Because Of Push", customAttributes: nil)
    }
}

// MARK: - Private utility functions

// TODO: Correct this range.
private let emojiKiller = try! NSRegularExpression(pattern: "[\u{0001f300}-\u{0001f800}]", options: [])

private func registerDevice(_ token: String, platform: String) {
    let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
    Intent.registerDeviceForPush(deviceId: deviceId, token: token, platform: platform).perform(BackendClient.instance)
}

private func scheduleNotification(_ streamId: Int64, notification: UILocalNotification) {
    let streamIdKey = String(streamId)
    let localNotifData = NSKeyedArchiver.archivedData(withRootObject: notification)

    if (SettingsManager.expectedNotifs[streamIdKey] != nil) {
        SettingsManager.expectedNotifs[streamIdKey]!.append(localNotifData)
    } else {
        // Initialize the notif data collection for this stream if it doesn't exist
        SettingsManager.expectedNotifs[streamIdKey] = [localNotifData]
    }

    if UIAccessibilityIsVoiceOverRunning() {
        // Remove emoji from notification text for VoiceOver users.
        if let body = notification.alertBody {
            notification.alertBody = emojiKiller.stringByReplacingMatches(in: body, options: [], range: NSRange(location: 0, length: body.characters.count), withTemplate: "")
        }
    }

    let app = UIApplication.shared
    if notification.fireDate != nil {
        app.scheduleLocalNotification(notification)
    } else {
        if app.applicationState == .active {
            // Read out in-app notifications.
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, notification.alertBody)
        }
        app.presentLocalNotificationNow(notification)
    }
}

private func showAttachmentNotif(_ stream: Stream, sender: Participant, attachment: Attachment) {
    guard UIApplication.shared.applicationState != .active else {
        // The notification was received while the user was in the app.
        AudioService.instance.vibrate()
        return
    }

    let attachmentType = attachment.isImage ?
        NSLocalizedString("photo", comment: "Attachment type") :
        NSLocalizedString("link", comment: "Attachment type")

    // Show attachment notification
    let localNotif = UILocalNotification()
    if let title = stream.title , stream.group {
        localNotif.alertBody = String.localizedStringWithFormat(
            NSLocalizedString("NOTIFICATION_ATTACHMENT_GROUP", value: "🖼 %1$@ shared a %2$@ with %3$@", comment: "Buzz notification, group"),
            sender.displayName,
            attachmentType,
            title
        )
    } else {
        localNotif.alertBody = String.localizedStringWithFormat(
            NSLocalizedString("NOTIFICATION_ATTACHMENT", value: "🖼 %1$@ shared a %2$@ with you", comment: "Buzz notification"),
            sender.displayName,
            attachmentType
        )
    }
    localNotif.soundName = "roger.mp3"
    localNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type": Responder.attachmentNotifIdentifier]
    scheduleNotification(stream.id, notification: localNotif)
}

private func showBuzzNotif(_ stream: Stream, senderId: Int64) {
    guard UIApplication.shared.applicationState != .active else {
        // The notification was received while the user was in the app.
        AudioService.instance.vibrate()
        return
    }

    guard let sender = stream.getParticipant(senderId) else {
        return
    }

    let localNotif = UILocalNotification()
    if let title = stream.title {
        localNotif.alertBody = String.localizedStringWithFormat(
            NSLocalizedString("NOTIFICATION_BUZZ_GROUP", value: "🐝 %@ buzzed %@", comment: "Buzz notification, group"),
            sender.displayName.rogerShortName,
            title)
    } else {
        localNotif.alertBody = String.localizedStringWithFormat(
            NSLocalizedString("NOTIFICATION_BUZZ", value: "🐝 %@ buzzed you", comment: "Buzz notification"),
            sender.displayName.rogerShortName)
    }
    localNotif.soundName = "buzz.mp3"
    localNotif.userInfo = ["stream_id": NSNumber(value: stream.id)]

    Responder.clearStreamNotifications(stream.id)
    scheduleNotification(stream.id, notification: localNotif)
}

private func showListeningToChunkNotif() {
    guard UIApplication.shared.applicationState != .active else {
        return
    }

    guard let stream = AudioService.instance.currentStream,
        let chunk = AudioService.instance.currentChunk,
        let participant = stream.getParticipant(chunk.senderId) else {
            return
    }

    let localNotif = UILocalNotification()
    localNotif.alertBody = String.localizedStringWithFormat(
        NSLocalizedString("NOTIFICATION_LISTENING_TO_NAME", value: "👂 Listening to %@", comment: "Notification, listening to name"),
        participant.displayName.rogerShortName)
    localNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type": Responder.listeningToChunkNotifIdentifier]
    Responder.clearStreamNotifications(stream.id)
    scheduleNotification(stream.id, notification: localNotif)
}

private func showNewStreamNotif(_ stream: Stream, senderId: Int64) {
    guard senderId != BackendClient.instance.session?.id else {
        return
    }

    guard UIApplication.shared.applicationState != .active else {
        // The notification was received while the user was in the app.
        AudioService.instance.vibrate()
        return
    }

    guard let sender = stream.getParticipant(senderId) else {
        return
    }

    let localNotif = UILocalNotification()
    localNotif.alertBody = String.localizedStringWithFormat(
        NSLocalizedString("🎉 %@ just started a conversation with you!", comment: "New stream notification"),
        sender.displayName)
    localNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type": Responder.newStreamNotifIdentifier]

    scheduleNotification(stream.id, notification: localNotif)
}

private func showStreamChunkNotif(_ stream: Stream, senderId: Int64) {
    guard !stream.muted else {
        return
    }

    guard UIApplication.shared.applicationState != .active else {
        // The notification was received while the user was in the app.
        AudioService.instance.vibrate()
        return
    }

    guard let sender = stream.getParticipant(senderId) else {
        return
    }

    // Commented out for localizations to be picked up (these are remote notifs).
    // NSLocalizedString("NOTIFICATION_TALKING_UNKNOWN", value: "😀 Someone is talking to you", comment: "Notification")
    // NSLocalizedString("NOTIFICATION_TALKING_UNKNOWN_GROUP", value: "😀 Someone is talking to %@", comment: "Notification")

    let localNotif = UILocalNotification()
    if let title = stream.title {
        localNotif.alertBody = String.localizedStringWithFormat(
            NSLocalizedString("NOTIFICATION_TALKED_GROUP", value: "😀 %@ talked to %@", comment: "Notification, name talking to group"),
            sender.displayName.rogerShortName, title)
    } else {
        localNotif.alertBody = String.localizedStringWithFormat(
            NSLocalizedString("NOTIFICATION_TALKED", value: "😀 %@ talked to you", comment: "Notification, name talking to user"),
            sender.displayName.rogerShortName)
    }
    localNotif.soundName = SettingsManager.autoplayAll && AudioService.instance.deviceConnected ? nil : "roger.mp3"
    localNotif.category = Responder.newChunkCategory
    localNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type": Responder.newChunkNotifIdentifier]

    // Merge this newly scheduled notif with any others for this stream.
    Responder.clearStreamNotifications(stream.id)
    scheduleNotification(stream.id, notification: localNotif)

    // Schedule notification 10 minutes after the chunk was sent if this is a 1:1.
    // Do not schedule for VoiceOver users.
    guard stream.duo && !UIAccessibilityIsVoiceOverRunning() else {
        return
    }
    let secondPushNotif = UILocalNotification()
    secondPushNotif.alertBody = String.localizedStringWithFormat(
        NSLocalizedString("NOTIFICATION_TALKED_HOURS_AGO", value: "😅 %@ talked an hour ago", comment: "Reminder notification"),
        sender.displayName.rogerShortName)
    secondPushNotif.soundName = "roger.mp3"
    secondPushNotif.fireDate = (Date() as NSDate).addingHours(1)
    secondPushNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type": Responder.secondPushNotifIdentifier]
    scheduleNotification(stream.id, notification: secondPushNotif)
}

private func showStreamJoinNotif(_ senderId: Int64, stream: Stream) {
    guard let title = stream.title else {
        return
    }
    let sender = stream.getParticipant(senderId)?.displayName ?? NSLocalizedString("Someone", comment: "Notification default sender name")

    let localNotif = UILocalNotification()
    localNotif.soundName = "roger.mp3"
    localNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type": Responder.joinGroupNotifIdentifier]
    localNotif.alertBody = String.localizedStringWithFormat(
        NSLocalizedString("NOTIFICATION_JOIN_GROUP", value: "🎉 %@ added you to %@", comment: "Notification, add to group"),
        sender, title
    )

    // Merge this newly scheduled notif with any others for this stream
    scheduleNotification(stream.id, notification: localNotif)
}

private func showStreamParticipantsNotif(_ senderId: Int64, stream: Stream, added: [Int64], removed: [Int64]) {
    guard !stream.muted else {
        return
    }

    guard !added.isEmpty else {
        return
    }

    let title = stream.title ?? NSLocalizedString("your conversation", comment: "Stream default name")
    let sender = stream.getParticipant(senderId)?.displayName ?? NSLocalizedString("Someone", comment: "Notification default sender name")
    var notifBody: String = ""

    // If the sender is the only member, indicate whether they joined or left the group
    if added.count == 1 && senderId == added.first {
        notifBody = String.localizedStringWithFormat(NSLocalizedString("🙌 %@ joined %@", comment: "Participants notification body"), sender, title)
    } else {
        // Otherwise, show who performed the operation and what they did (add/remove and on whom)
        let memberNames = added.map({
            stream.getParticipant($0)?.displayName ?? NSLocalizedString("someone else", comment: "Participants notification default member name")
        }).localizedJoin()

        // Combine the performed opereation and who it was performed on
        notifBody = String.localizedStringWithFormat(NSLocalizedString("🙌 %@ added %@ to %@", comment: "Participants notification body"), sender, memberNames, title)
    }

    let localNotif = UILocalNotification()
    localNotif.soundName = "roger.mp3"
    localNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type": Responder.participantsNotifIdentifier]
    localNotif.alertBody = notifBody
    scheduleNotification(stream.id, notification: localNotif)
}

private func showStreamParticipantChangedNotif(_ participant: Participant, stream: Stream) {
    guard participant.active else {
        return
    }

    let notifBody = String.localizedStringWithFormat(
        NSLocalizedString("🙌 %@ joined your conversation", comment: "Participants notification body"), participant.displayName)
    let localNotif = UILocalNotification()
    localNotif.soundName = "roger.mp3"
    localNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type": Responder.participantsNotifIdentifier]
    localNotif.alertBody = notifBody
    scheduleNotification(stream.id, notification: localNotif)
}

private func showStreamStatusNotif(_ stream: Stream) {
    guard UIApplication.shared.applicationState != .active &&
        !UIAccessibilityIsVoiceOverRunning() else {
            return
    }

    guard !stream.muted && stream.otherParticipants.count < 10, let sender = stream.currentlyActiveParticipant else {
        return
    }

    let localNotif = UILocalNotification()

    switch stream.status {
    case .Talking:
        if let title = stream.title {
            localNotif.alertBody = String.localizedStringWithFormat(
                NSLocalizedString("NOTIFICATION_TALKING_NOW_GROUP", value: "😮 %@ is talking to %@...", comment: "Notification, name talking to group"),
                sender.displayName.rogerShortName, title)
        } else {
            localNotif.alertBody = String.localizedStringWithFormat(
                NSLocalizedString("NOTIFICATION_TALKING_NOW", value: "😮 %@ is talking...", comment: "Notification, name talking to user"),
                sender.displayName.rogerShortName)
        }
        localNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type": Responder.talkingNowNotifIdentifier]
    case .Listening:
        if let title = stream.title {
            localNotif.alertBody = String.localizedStringWithFormat(
                NSLocalizedString("NOTIFICATION_LISTENING_NOW_GROUP", value: "😌 %@ is listening to %@...", comment: "Notification, name listening to group"),
                sender.displayName.rogerShortName, title)
        } else {
            // Is the other person re-listening to your Roger

            if stream.othersListenedTime != nil {
                localNotif.alertBody = String.localizedStringWithFormat(
                    NSLocalizedString("NOTIFICATION_RELISTENING_NOW", value: "☺️ %@ is relistening to you...", comment: "Notification, name listening to user"),
                    sender.displayName.rogerShortName)
            } else {
                localNotif.alertBody = String.localizedStringWithFormat(
                    NSLocalizedString("NOTIFICATION_LISTENING_NOW", value: "😌 %@ is listening to you...", comment: "Notification, name listening to user"),
                    sender.displayName.rogerShortName)
            }
        }
        localNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type": Responder.listeningNowNotifIdentifier]
    case .ViewingAttachment:
        if let title = stream.title {
            localNotif.alertBody = String.localizedStringWithFormat(
                NSLocalizedString("NOTIFICATION_VIEWINGATTACHMENT_TITLED_GROUP", value: "👀 %@ just saw the photo in %@", comment: "Notification, name talking to group"),
                sender.displayName.rogerShortName, title)
        } else if sender.id == BackendClient.instance.session?.id {
            localNotif.alertBody = String.localizedStringWithFormat(
                NSLocalizedString("NOTIFICATION_VIEWINGATTACHMENT", value: "👀 %@ just saw your photo", comment: "Notification, name talking to user"),
                sender.displayName.rogerShortName)
        } else {
            localNotif.alertBody = String.localizedStringWithFormat(
                NSLocalizedString("NOTIFICATION_VIEWINGATTACHMENT_GROUP", value: "👀 %@ just saw your group photo", comment: "Notification, name talking to user"),
                sender.displayName.rogerShortName)
        }
        localNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type": Responder.attachmentNotifIdentifier]
    default:
        return
    }

    // Merge this newly scheduled notif with any others for this stream.
    Responder.clearStreamNotifications(stream.id)
    scheduleNotification(stream.id, notification: localNotif)
}
