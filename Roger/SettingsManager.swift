import CoreLocation
import UIKit

private let didSendChunkKey = "didSendChunk"
private let didSetupNotificationsKey = "didSetupNotifications"
private let didCompleteTutorialKey = "didCompleteTutorial"
private let didUnderstandConversationsKey = "didUnderstandConversationsKey"
private let didUnderstandInviteKey = "didUnderstandInviteKey"
private let didListenKey = "didListen"
private let didTapToRecordKey = "didTapToRecord"
private let lastKnownLatitudeKey = "lastKnownLatitude"
private let lastKnownLongitudeKey = "lastKnownLongitude"
private let mutedStreamIdsKey = "mutedStreams"
private let presentedLocalNotifsKey = "presentedLocalNotifs"
private let pushKitTokenKey = "pushKitToken"
private let setUpVoicemailKey = "setUpVoicemail"
private let userDisplayNameKey = "userDisplayName"
private let userIdentifierKey = "userIdentifier"
private let streamPlayPositionsKey = "streamPlayPositions"
private let didScheduleGroupPrimerNotifKey = "didScheduleGroupPrimerNotif"
private let invitedContactsKey = "invitedContacts"
private let didCreateFriendsGroupKey = "didCreateFriendsGroup"
private let didCreateFamilyGroupKey = "didCreateFamilyGroup"
private let didCreateTeamGroupKey = "didCreateTeamGroup"
private let autoplayAllKey = "autoplayAll"
private let playbackRateKey = "playbackRate"
private let openedAttachmentsKey = "openedAttachments"
private let installationTimestampKey = "installationTimestamp"

private let userDefaults = UserDefaults.standard

class SettingsManager {
    fileprivate static var autoplayStreamIds = Set<Int64>()

    static let baseURL = URL(string: "https://rogertalk.com/")!

    fileprivate static var mutedStreams: [NSNumber: Date] {
        get {
            guard let data = userDefaults.object(forKey: mutedStreamIdsKey) as? Data else {
                return [:]
            }
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? [NSNumber: Date] ?? [:]
        }
        set {
            let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
            userDefaults.set(data, forKey: mutedStreamIdsKey)
            userDefaults.synchronize()
        }
    }

    fileprivate static var streamPlayPositions: [NSNumber: NSNumber] {
        get {
            guard let data = userDefaults.object(forKey: streamPlayPositionsKey) as? Data else {
                return [:]
            }
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? [NSNumber: NSNumber] ?? [:]
        }
        set {
            let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
            userDefaults.set(data, forKey: streamPlayPositionsKey)
            userDefaults.synchronize()
        }
    }

    static var expectedNotifs: [String: [Data]] {
        get {
            return userDefaults.dictionary(forKey: presentedLocalNotifsKey) as? [String: [Data]] ?? [String: [Data]]()
        }
        set {
            userDefaults.set(newValue, forKey: presentedLocalNotifsKey)
            userDefaults.synchronize()
        }
    }

    static var invitedContacts: [String] {
        get {
            return userDefaults.array(forKey: invitedContactsKey) as? [String] ?? [String]()
        } set {
            userDefaults.set(newValue, forKey: invitedContactsKey)
            userDefaults.synchronize()
        }
    }

    /// Set whether screen autolock is enabled.
    static func updateScreenAutolockEnabled() {
        // Enable screen autolock if there is nothing playing/recording and there are no autoplay streams.
        if case .idle = AudioService.instance.state ,
            SettingsManager.autoplayStreamIds.isEmpty && !SettingsManager.autoplayAll {
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static var didUnderstandConversations: Bool {
        get { return userDefaults.bool(forKey: didUnderstandConversationsKey) }
        set {
            userDefaults.set(newValue, forKey: didUnderstandConversationsKey)
            userDefaults.synchronize()
        }
    }

    static var didUnderstandInvite: Bool {
        get { return userDefaults.bool(forKey: didUnderstandInviteKey) }
        set {
            userDefaults.set(newValue, forKey: didUnderstandInviteKey)
            userDefaults.synchronize()
        }
    }

    static var didCompleteTutorial: Bool {
        get { return userDefaults.bool(forKey: didCompleteTutorialKey) }
        set {
            userDefaults.set(newValue, forKey: didCompleteTutorialKey)
            userDefaults.synchronize()
        }
    }

    static var didListen: Bool {
        get { return userDefaults.bool(forKey: didListenKey) }
        set {
            userDefaults.set(newValue, forKey: didListenKey)
            userDefaults.synchronize()
        }
    }

    static var didScheduleGroupPrimerNotif: Bool {
        get { return userDefaults.bool(forKey: didScheduleGroupPrimerNotifKey) }
        set {
            userDefaults.setValue(newValue, forKey: didScheduleGroupPrimerNotifKey)
            userDefaults.synchronize()
        }
    }

    static var didSendChunk: Bool {
        get { return userDefaults.bool(forKey: didSendChunkKey) }
        set {
            userDefaults.set(newValue, forKey: didSendChunkKey)
            userDefaults.synchronize()
        }
    }

    static var didSetupNotifications: Bool {
        get {
            return SettingsManager.hasNotificationsPermissions || userDefaults.bool(forKey: didSetupNotificationsKey)
        }
        set {
            userDefaults.set(newValue, forKey: didSetupNotificationsKey)
            userDefaults.synchronize()
        }
    }

    static var didSetUpVoicemail: Bool {
        get { return userDefaults.bool(forKey: setUpVoicemailKey) }
        set {
            userDefaults.setValue(newValue, forKey: setUpVoicemailKey)
            userDefaults.synchronize()
        }
    }

    static var didTapToRecord: Bool {
        get { return userDefaults.bool(forKey: didTapToRecordKey) }
        set {
            userDefaults.set(newValue, forKey: didTapToRecordKey)
            userDefaults.synchronize()
        }
    }

    static var didCreateFriendsGroup: Bool {
        get { return userDefaults.bool(forKey: didCreateFriendsGroupKey) }
        set {
            userDefaults.set(newValue, forKey: didCreateFriendsGroupKey)
            userDefaults.synchronize()
        }
    }

    static var didCreateFamilyGroup: Bool {
        get { return userDefaults.bool(forKey: didCreateFamilyGroupKey) }
        set {
            userDefaults.set(newValue, forKey: didCreateFamilyGroupKey)
            userDefaults.synchronize()
        }
    }

    static var didCreateTeamGroup: Bool {
        get { return userDefaults.bool(forKey: didCreateTeamGroupKey) }
        set {
            userDefaults.set(newValue, forKey: didCreateTeamGroupKey)
            userDefaults.synchronize()
        }
    }

    static var installationTimestamp: Date {
        guard let timestamp = userDefaults.object(forKey: installationTimestampKey) as? Date else {
            let now = Date()
            userDefaults.set(now, forKey: installationTimestampKey)
            return now
        }
        return timestamp
    }

    static var playbackRate: Float {
        get {
            return max(userDefaults.float(forKey: playbackRateKey), 1)
        } set {
            userDefaults.set(newValue, forKey: playbackRateKey)
            userDefaults.synchronize()
        }
    }

    static var isGlimpsesEnabled: Bool {
        get {
            return SettingsManager.hasLocationPermissions && BackendClient.instance.session?.shareLocation ?? false
        }
    }

    static var hasLocationPermissions: Bool {
        get {
            let status = CLLocationManager.authorizationStatus()
            return status == .authorizedAlways || status == .authorizedWhenInUse
        }
    }

    static var hasNotificationsPermissions: Bool {
        get {
            return UIApplication.shared.currentUserNotificationSettings!.types != UIUserNotificationType()
        }
    }

    static var lastKnownCoordinates: CLLocationCoordinate2D? {
        get {
            let latitude = userDefaults.double(forKey: lastKnownLatitudeKey)
            let longitude = userDefaults.double(forKey: lastKnownLongitudeKey)
            if latitude.isZero && longitude.isZero {
                return nil
            }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        set {
            userDefaults.set(newValue?.latitude ?? 0, forKey: lastKnownLatitudeKey)
            userDefaults.set(newValue?.longitude ?? 0, forKey: lastKnownLongitudeKey)
            userDefaults.synchronize()
        }
    }

    static var pushKitToken: String? {
        get { return userDefaults.string(forKey: pushKitTokenKey) }
        set {
            userDefaults.setValue(newValue, forKey: pushKitTokenKey)
            userDefaults.synchronize()
        }
    }

    static var userDisplayName: String? {
        get { return userDefaults.value(forKey: userDisplayNameKey) as? String }
        set {
            userDefaults.setValue(newValue, forKey: userDisplayNameKey)
            userDefaults.synchronize()
        }
    }

    static var userIdentifier: String? {
        get {
            if let number = userDefaults.string(forKey: userIdentifierKey) {
                return number
            }

            guard let identifiers = BackendClient.instance.session?.identifiers else {
                return nil
            }

            // See if we can find an identifier for this session on the backend
            if let identifier = identifiers.filter({ $0.hasPrefix("+") }).first ??
                identifiers.filter({ $0.contains("@") }).first {
                // Save this identifier locally for future use
                self.userIdentifier = identifier
                return identifier
            }

            return nil
        }
        set {
            userDefaults.setValue(newValue, forKey: userIdentifierKey)
            userDefaults.synchronize()
        }
    }

    static func setPlayPosition(_ stream: Stream, time: Int64) {
        self.streamPlayPositions[NSNumber(value: stream.id as Int64)] = NSNumber(value: time as Int64)
    }

    static func getPlayPosition(_ stream: Stream) -> Int64? {
        return (self.streamPlayPositions[NSNumber(value: stream.id as Int64)])?.int64Value ?? nil
    }

    static func clearPlayPosition(_ stream: Stream) {
        self.streamPlayPositions.removeValue(forKey: NSNumber(value: stream.id as Int64))
    }

    static var autoplayAll: Bool {
        get {
            // If the key doesn't exist, set it to true
            if userDefaults.object(forKey: autoplayAllKey) == nil {
                self.autoplayAll = true
            }
            return userDefaults.bool(forKey: autoplayAllKey)
        } set {
            userDefaults.set(newValue, forKey: autoplayAllKey)
            userDefaults.synchronize()
        }
    }

    static func isAttachmentUnopened(_ attachment: Attachment) -> Bool {
        guard let url = attachment.url, let senderId = attachment.senderId, senderId != BackendClient.instance.session?.id else {
            return false
        }
        return !self.openedAttachments.values.contains(where: { $0 == url })
    }

    static func markAttachmentOpened(_ stream: Stream, attachment: Attachment) {
        guard let url = attachment.url else {
            return
        }
        self.openedAttachments[NSNumber(value: stream.id)] = url as URL
    }

    fileprivate static var openedAttachments: [NSNumber: URL] {
        get {
            guard let data = userDefaults.object(forKey: openedAttachmentsKey) as? Data else {
                return [:]
            }
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? [NSNumber: URL] ?? [:]
        }
        set {
            let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
            userDefaults.set(data, forKey: openedAttachmentsKey)
            userDefaults.synchronize()
        }
    }

    static func isAutoplayStream(_ stream: Stream) -> Bool {
        return SettingsManager.autoplayAll ? true : self.autoplayStreamIds.contains(stream.id)
    }

    static func setAutoplayStream(_ stream: Stream, autoplay: Bool) {
        if autoplay {
            self.autoplayStreamIds.insert(stream.id)
        } else {
            self.autoplayStreamIds.remove(stream.id)
        }
        self.updateScreenAutolockEnabled()
    }

    static func isMutedStream(_ stream: Stream) -> Bool {
        return self.mutedStreams.keys.contains(NSNumber(value: stream.id as Int64))
    }

    static func muteStream(_ stream: Stream, until: Date) {
        self.mutedStreams[NSNumber(value: stream.id as Int64)] = until
    }

    static func unmuteStream(_ stream: Stream) {
        self.mutedStreams.removeValue(forKey: NSNumber(value: stream.id as Int64))
    }

    static func updateMutedStreams() {
        let muted = SettingsManager.mutedStreams
        for (streamId, expiration) in muted {
            if (Date() as NSDate).isLaterThanOrEqual(to: expiration) {
                SettingsManager.mutedStreams.removeValue(forKey: streamId)
            }
        }
    }
}
