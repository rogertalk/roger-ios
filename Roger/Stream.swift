import AlamofireImage
import Foundation
import Crashlytics

private let MAX_CHUNK_AGE = TimeInterval(48 * 60 * 60)

// TODO: Combine with Stream class implementation
class PublicStream {
    let imageURL: URL?
    let inviteToken: String
    let title: String

    var memberCount: Int {
        return (self.data["participants"] as? [Any])?.count ?? 0
    }

    init?(_ data: DataType) {
        guard let title = data["title"] as? String,
            let inviteToken = data["invite_token"] as? String else {
            return nil
        }
        self.title = title
        self.inviteToken = inviteToken
        if let url = data["image_url"] as? String {
            self.imageURL = URL(string: url)
        } else {
            self.imageURL = nil
        }

        self.data = data
    }

    private let data: DataType
}

class Stream {
    typealias Instructions = (title: String, body: String)

    /// The id that uniquely identifies this stream.
    let id: Int64

    var attachments = [String: Attachment]()

    /// Whether new chunks to this stream play automatically.
    var autoplay: Bool {
        get {
            return SettingsManager.isAutoplayStream(self)
        }
        set {
            SettingsManager.setAutoplayStream(self, autoplay: newValue)
            self.changed.emit()
        }
    }

    var autoplayChangeable: Bool {
        return true
    }

    var callToAction: String? {
        var greeting = NSLocalizedString("Hi", comment: "Default greeting when we don't know the country")
        if let other = self.otherParticipants.first, let identifier = ContactService.shared.identifierIndex[other.id] {
            for (countryCode, message) in Stream.greetings {
                if identifier.hasPrefix(countryCode) {
                    greeting = message
                    break
                }
            }
        }
        return String.localizedStringWithFormat(
            NSLocalizedString("“%@ %@”", comment: "Greeting; first value is local word for Hi, second value is name"),
            greeting,
            self.shortTitle)
    }

    /// Whether the current user may talk to this stream.
    var canTalk: Bool {
        return true
    }

    /// An event that notifies listeners that the stream changed.
    let changed = Event<Void>()

    /// The most recent chunks in the stream.
    var chunks: [PlayableChunk] {
        return self.allChunks.filter { $0.age < MAX_CHUNK_AGE }
    }

    /// Returns `true` if the current user was the last person to speak to this stream.
    var currentUserHasReplied: Bool {
        guard let lastChunk = self.chunks.last else {
            return false
        }
        return lastChunk.byCurrentUser
    }

    var currentlyActiveParticipant: Participant? {
        guard let first = self.otherParticipants.first else {
            return nil
        }
        let active = self.otherParticipants.reduce(
            first,
            { (currentActive, next) in
                return next.activityStatus > currentActive.activityStatus ? next : currentActive
        })
        return active.activityStatus == .Idle ? nil : active
    }

    /// The underlying data for this stream.
    private(set) var data: DataType {
        didSet {
            // TODO: This should probably be a little bit more intelligent.
            self.changed.emit()
        }
    }

    /// Whether the stream only has one other person (it's a 1:1).
    var duo: Bool {
        return self.otherParticipants.count == 1
    }

    /// Whether the stream is empty (except for the current user).
    var empty: Bool {
        return self.otherParticipants.count == 0
    }

    /// Whether the stream is a group.
    var group: Bool {
        return self.otherParticipants.count > 1
    }

    var groupInviteURL: URL? {
        guard let token = self.inviteToken else {
            return nil
        }
        return URL(string: "https://rogertalk.com/group/\(token)")
    }

    var hasCustomImage: Bool {
        return (self.data["image_url"] as? String) != nil
    }

    /// An image that should be shown for the stream.
    var image: UIImage? {
        // TODO: Cache all images on disk and load them as thumbnails.
        if self.cachedImage != nil {
            return self.cachedImage
        }

        guard let url = self.imageURL else {
            return nil
        }

        if url.scheme == "rogertalk" {
            // This is an internal image.
            switch url.host! {
            case "contact":
                // TODO: Look up the contact by id instead of assuming first participant.
                guard let data = self.otherParticipants.first?.contact?.imageData else {
                    return nil
                }
                let image = UIImage(data: data, scale: UIScreen.main.scale)
                self.cachedImage = image?.scaleToFitSize(CGSize(width: 130, height: 130))
                self.cachedImageURL = url
                return self.cachedImage
            default:
                print("ERROR: Unhandled internal image URL \(url)")
                return nil
            }
        }

        let request = URLRequest(url: url)
        Stream.imageDownloader.download(request, completion: {
            if let image = $0.result.value {
                self.cachedImage = image.scaleToFitSize(CGSize(width: 130, height: 130))
                self.cachedImageURL = url
                self.changed.emit()
            }
        })

        return nil
    }

    /// URL of the image that should be shown for the stream.
    var imageURL: URL? {
        if let address = self.data["image_url"] as? String {
            return URL(string: address)
        } else if self.group {
            // TODO: Auto-create a picture for the last few people that spoke.
            return nil
        } else {
            // Use the picture of the other person (or the user's own for monologs).
            return self.primaryAccount.id != BackendClient.instance.session?.id ? self.primaryAccount.imageURL : nil
        }
    }

    /// The initials of the stream title.
    var initials: String {
        return self.displayName.rogerInitials
    }

    /// Instructions to show on a card (e.g., how to set up an integration).
    var instructions: Instructions? {
        return nil
    }

    /// An action that can be performed, if the instructions card is being shown.
    var instructionsAction: String? {
        return nil
    }

    /// Invite token to allow others to join this stream
    var inviteToken: String? {
        return self.data["invite_token"] as? String
    }

    /// The timestamp (in milliseconds since 1970) of the last interaction with this stream.
    var lastInteraction: Int64 {
        return (self.data["last_interaction"] as! NSNumber).int64Value
    }

    /// The time of the last interaction in a stream.
    var lastInteractionTime: Date {
        return Date(timeIntervalSince1970: Double(self.lastInteraction) / 1000)
    }

    /// The timestamp (in milliseconds since 1970) of where in the stream the user's last play session began.
    var lastPlayedFrom: Int64 {
        return (self.data["last_played_from"] as! NSNumber).int64Value
    }

    /// The time when someone last talked.
    var lastTalkedTime: Date? {
        guard let chunk = self.getPlayableChunks().last else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(chunk.end) / 1000)
    }

    var memberImageURLs: [URL] {
        return self.reachableParticipants.filter { $0.imageURL != nil }.map { ($0.imageURL! as URL) }
    }

    /// Whether to mute notifications for this stream.
    var muted: Bool {
        get {
            return SettingsManager.isMutedStream(self)
        }
    }

    /// The other people in the stream (usually just one other person, but can also be empty or a group of people).
    var otherParticipants = [Participant]()
    var reachableParticipants: [Participant] {
        return self.otherParticipants.filter {
            $0.active || ContactService.shared.identifierIndex[$0.id] != nil
        }
    }

    var botParticipants: [Participant] {
        return self.otherParticipants.filter { $0.bot }
    }

    var invitedParticipants: [Participant] {
        return self.reachableParticipants.filter { !$0.active }
    }

    var activeParticipants: [Participant] {
        return self.reachableParticipants.filter { $0.active }
    }

    var othersListenedTime: Date? {
        guard let listenedUntil = self.data["others_listened"] as? NSNumber else {
            return nil
        }
        return Date(timeIntervalSince1970: listenedUntil.doubleValue / 1000)
    }

    /// The timestamp (in milliseconds since 1970) of the time up until which the current user has played this stream.
    var playedUntil: Int64 {
        return (self.data["played_until"] as! NSNumber).int64Value
    }

    /// The account that should be used for image and weather.
    var primaryAccount: Account {
        return self.otherParticipants.first ?? BackendClient.instance.session!
    }

    /// A short version of the stream's displayName (e.g., the first name of a person).
    var shortTitle: String {
        if self.data["title"] is NSNull && self.reachableParticipants.count > 1 {
            return "\(self.displayName.rogerShortName) + \(self.otherParticipants.count - 1)"
        } else {
            return self.displayName.rogerShortName
        }
    }

    /// The current status of the other participant. For groups, this will be the most important status (talking > listening > idle).
    var status: ActivityStatus {
        return self.currentlyActiveParticipant?.activityStatus ?? .Idle
    }

    var statusText: String {
        // Handle realtime status.
        switch self.status {
        case .Listening:
            if let participant = self.currentlyActiveParticipant , self.group {
                return String.localizedStringWithFormat(
                    NSLocalizedString("%@ is listening right now", comment: "Stream status"),
                    participant.displayName.rogerShortName)
            }
            return NSLocalizedString("listening right now", comment: "Stream status")
        case .Talking:
            if let participant = self.currentlyActiveParticipant , self.group {
                return String.localizedStringWithFormat(
                    NSLocalizedString("%@ is talking right now", comment: "Stream status"),
                    participant.displayName.rogerShortName)
            }
            return NSLocalizedString("talking right now", comment: "Stream status")
        default:
            break
        }
        // Handle empty conversations.
        if self.chunks.isEmpty {
            if self.group {
                return ""
            }
            // TODO: Handle groups better.
            if let other = self.otherParticipants.first , !other.active {
                // This user will receive a text message, show something like "via +12345".
                if let identifier = ContactService.shared.identifierIndex[other.id] {
                    return String.localizedStringWithFormat(
                        NSLocalizedString("via %@", comment: "Stream status"),
                        ContactService.shared.prettify(phoneNumber: identifier) ?? identifier)
                } else {
                    return NSLocalizedString("unreachable", comment: "Stream status")
                }
            }
            // There is no audio content, so just show "Active on Roger".
            return NSLocalizedString("Active on Roger", comment: "Stream status")
        }
        // Other user was the last to send a message.
        if let time = self.lastTalkedTime , !self.currentUserHasReplied {
            guard let senderId = self.chunks.last?.senderId,
                let participant = self.getParticipant(senderId) , self.group else {
                    return String.localizedStringWithFormat(
                        NSLocalizedString("talked %@", comment: "Stream status"),
                        time.rogerTimeLabel)
            }

            return String.localizedStringWithFormat(
                NSLocalizedString("%@ talked %@", comment: "Stream status"),
                participant.displayName.rogerShortName,
                time.rogerTimeLabel)
        }
        // Current user sent the last message.
        if let time = self.othersListenedTime {
            return String.localizedStringWithFormat(
                NSLocalizedString("listened %@", comment: "Stream status"),
                time.rogerTimeLabel)
        }
        return self.group ?
            NSLocalizedString("nobody has listened yet", comment: "Stream status") :
            NSLocalizedString("hasn't listened yet", comment: "Stream status")
    }

    /// The full title of the stream, taking into consideration local contact names.
    var title: String? {
        return self.data["title"] as? String
    }

    var displayName: String {
        // Return title if there is one
        if let title = self.title {
            return title
        }

        // Get a list of names for all of the participants.
        let mapper: (Participant) -> String
        if self.reachableParticipants.count > 1 {
            mapper = { $0.displayName.rogerShortName }
        } else {
            mapper = { $0.displayName }
        }
        let names = self.reachableParticipants.map(mapper)
        if names.isEmpty {
            // Assume that no other participants means the stream only contains the current user.
            return NSLocalizedString("New Conversation", comment: "User name to display when unknown")
        }
        return names.localizedJoin()
    }

    var totalDuration: TimeInterval {
        return (self.data["total_duration"] as! Double) / 1000
    }

    /// Indicates whether any chunks in this stream are unplayed.
    var unplayed: Bool {
        guard let lastChunk = self.getPlayableChunks().last else {
            return false
        }
        return lastChunk.end > self.playedUntil
    }

    /// Whether the stream should be considered visible.
    var visible: Bool {
        return self.data["visible"] as! Bool
    }

    // MARK: - Initializers

    required init?(data: DataType) {
        self.data = data
        guard let id = (data["id"] as? NSNumber)?.int64Value else {
            self.id = -1
            return nil
        }
        self.id = id
        if data["chunks"] == nil || data["others"] == nil {
            // We can't create a new stream from the data provided.
            return nil
        }
        self.updateComputedFields()
    }

    // MARK: - Methods

    /// Adds an attachment to the stream
    func addAttachment(_ attachment: Attachment) {
        StreamService.instance.addAttachment(streamId: self.id, attachment: attachment)
    }

    /// Adds a single chunk data object to the stream.
    func addChunkData(_ chunk: DataType) {
        var newData = self.data
        if
            let end = chunk["end"] as? NSNumber,
            end.compare(self.data["last_interaction"] as! NSNumber) == .orderedDescending
        {
            newData["last_interaction"] = end
        }
        newData["chunks"] = mergeChunks(self.data["chunks"] as! [DataType], withChunks: [chunk])
        self.data = newData
        self.updateComputedFields(participants: false)
    }

    /// Updates the stream's data with the provided data.
    func addStreamData(_ data: DataType) {
        var newData = data
        // If the local timestamps are more recent than the new ones (because backend updates are pending), keep them.
        func maxNumberValueForKey(_ key: String, dicts: [String: Any]...) -> Any {
            return dicts.flatMap { $0[key] as? NSNumber }.max { (a, b) in a.compare(b) == .orderedAscending } ?? NSNull()
        }
        newData["last_interaction"] = maxNumberValueForKey("last_interaction", dicts: self.data, data)
        newData["last_played_from"] = maxNumberValueForKey("last_played_from", dicts: self.data, data)
        newData["played_until"] = maxNumberValueForKey("played_until", dicts: self.data, data)
        // Merge the old and new chunks.
        if let oldChunks = self.data["chunks"] as? [[String: Any]], let newChunks = data["chunks"] as? [[String: Any]] {
            newData["chunks"] = mergeChunks(oldChunks, withChunks: newChunks)
        }
        // Keep any fields that didn't exist in the new data (because data may be partial).
        for (key, value) in self.data {
            if newData[key] == nil {
                newData[key] = value
            }
        }
        self.data = newData
        self.updateComputedFields(chunks: newData["chunks"] != nil, participants: newData["others"] != nil)
    }

    func clearImage() {
        StreamService.instance.setImage(stream: self, image: nil)
    }

    func clearTitle() {
        StreamService.instance.setTitle(stream: self, title: nil)
    }

    func getParticipant(_ participantId: Int64) -> Account? {
        if let account = BackendClient.instance.session , account.id == participantId {
            return account
        }
        return self.otherParticipants.lazy.filter({ $0.id == participantId }).first
    }

    func updateParticipant(_ participant: Participant) {
        guard let index = self.otherParticipants.index(where: { $0.id == participant.id }) else {
            return
        }
        self.otherParticipants.remove(at: index)
        self.otherParticipants.insert(participant, at: index)
        self.changed.emit()
    }

    /// Gets an array of chunks that can be played (i.e., they were not by the current user).
    func getPlayableChunks() -> [PlayableChunk] {
        return self.chunks.filter { !$0.byCurrentUser }
    }

    /// Gets the chunks that haven't been played yet.
    func getUnplayedChunks() -> [PlayableChunk] {
        let chunks = self.getPlayableChunks()
        var numPlayed = 0
        while numPlayed < chunks.endIndex && chunks[numPlayed].end <= self.playedUntil {
            numPlayed += 1
        }
        return Array(chunks.dropFirst(numPlayed))
    }

    /// Disables push  notifications for this stream
    func mute(until: Date) {
        SettingsManager.muteStream(self, until: until)
    }

    /// Enables push notifications for this stream
    func unmute() {
        SettingsManager.unmuteStream(self)
    }

    /// Called when the user taps the instructions action button for this stream.
    func instructionsActionTapped() -> InstructionsActionResult {
        // To be implemented by subclasses.
        return .nothing
    }

    func preCacheImage() {
        // Access the image property to begin loading it.
        _ = self.image
    }

    /// Reports a status for the current user and stream, such as "listening" or "talking".
    func reportStatus(_ status: ActivityStatus, estimatedDuration: Int? = nil) {
        StreamService.instance.reportStatus(stream: self, status: status, estimatedDuration: estimatedDuration)
    }

    func sendBuzz() {
        Intent.buzz(streamId: self.id).perform(BackendClient.instance)
        Answers.logCustomEvent(withName: "Buzz", customAttributes: nil)
    }

    /// Send a chunk of audio to the other participants in the stream.
    func sendChunk(_ chunk: SendableChunk, persist: Bool? = nil, showInRecents: Bool? = nil, callback: StreamServiceCallback? = nil) {
        StreamService.instance.sendChunk(streamId: self.id, chunk: chunk, persist: persist, showInRecents: showInRecents, callback: callback)
        // Insert a local chunk so the UI can update properly until we get a response from the server.
        guard let senderId = BackendClient.instance.session?.id else {
            return
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let chunk = LocalChunk(audioURL: chunk.audioURL, duration: chunk.duration, start: now - chunk.duration, end: now, senderId: senderId)
        self.allChunks.append(chunk)
    }

    func setImage(_ image: Intent.Image) {
        StreamService.instance.setImage(stream: self, image: image)
    }

    func setTitle(_ title: String) {
        StreamService.instance.setTitle(stream: self, title: title)
    }

    /// Update the played until value in the backend.
    func setPlayedUntil(_ playedUntil: Int64) {
        StreamService.instance.setPlayedUntil(stream: self, playedUntil: playedUntil)
    }

    /// Updates the current status for the provided participant in the stream. Only for internal use.
    func setStatusForParticipant(_ participantId: Int64, status: ActivityStatus, estimatedDuration: Int? = nil) {
        guard let index = self.otherParticipants.index(where: { $0.id == participantId }) else {
            return
        }
        let duration: Int
        switch (self.otherParticipants[index].activityStatus, status) {
        case let (from, .Idle) where from == .Listening || from == .Talking:
            // Delay the status change since we can expect another update to arrive any second.
            duration = 2000
            self.otherParticipants[index].updateActivityStatus(from, duration: duration)
        case let (oldStatus, status):
            // Use the estimated duration but add on extra time to account for lag. If the duration is unknown, use a high value.
            duration = estimatedDuration.flatMap({ $0 + 3000 }) ?? 120000
            self.otherParticipants[index].updateActivityStatus(status, duration: duration)
            if oldStatus != status {
                self.changed.emit()
            }
        }
        if self.status != .Idle {
            // Expire the status after the duration (if it's not idle).
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(duration) * Int64(NSEC_PER_MSEC)) / Double(NSEC_PER_SEC)) {
                self.expireStatuses()
            }
        }
    }

    func updateWithAttachmentData(_ id: String, data: DataType?) -> Attachment? {
        var attachments = (self.data["attachments"] as? DataType) ?? [:]
        attachments[id] = data
        self.data["attachments"] = attachments
        self.updateComputedFields(chunks: false, participants: false, attachments: true)
        self.changed.emit()
        return self.attachments[id]
    }

    // MARK: - Private

    private static let greetings = [
        "+1": "Hi",
        "+31": "Hoi",
        "+33": "Salut",
        "+34": "Hola",
        "+39": "Ciao",
        "+43": "Hallo",
        "+44": "Hello",
        "+45": "Hej",
        "+46": "Hej",
        "+47": "Hei",
        "+48": "Cześć",
        "+49": "Hallo",
        "+51": "Hola",
        "+52": "Hola",
        "+53": "Hola",
        "+54": "Hola",
        "+55": "Oi",
        "+56": "Hola",
        "+57": "Hola",
        "+58": "Hola",
        "+61": "Hey",
        "+86": "Ni hao",
        "+238": "Oi",
        "+239": "Oi",
        "+244": "Oi",
        "+258": "Oi",
        "+351": "Olá",
        "+358": "Moi",
        "+376": "Hola",
        "+377": "Salut",
        "+420": "Ahoj",
        "+502": "Hola",
        "+503": "Hola",
        "+505": "Hola",
        "+506": "Hola",
        "+507": "Hola",
        "+591": "Hola",
        "+593": "Hola",
        "+594": "Salut",
        "+596": "Salut",
        "+598": "Hola",
        "+689": "Salut",
    ]

    private var allChunks = [PlayableChunk]()
    private var cachedImage: UIImage?
    private var cachedImageURL: URL?

    private static let imageDownloader = ImageDownloader()

    private func expireStatuses() {
        var somethingChanged = false
        let now = Date()
        for (index, participant) in self.otherParticipants.enumerated() {
            if participant.activityStatus != .Idle && (participant.activityStatusEnd as NSDate).isEarlierThan(now) {
                // The status has expired, so set it to idle.
                self.otherParticipants[index].updateActivityStatus(.Idle, duration: 0)
                somethingChanged = true
            }
        }
        if somethingChanged {
            self.changed.emit()
        }
    }

    private func updateComputedFields(chunks: Bool = true, participants: Bool = true, attachments: Bool = true) {
        // Clear the cached image if the URL changed.
        if self.cachedImageURL != self.imageURL {
            self.cachedImage = nil
        }
        if chunks {
            let chunksArray = self.data["chunks"] as! [[String: Any]]
            self.allChunks = chunksArray.map { Chunk(streamId: self.id, data: $0) }
        }
        if participants {
            let othersArray = self.data["others"] as! [[String: Any]]
            self.otherParticipants = othersArray.map(Participant.init)
        }
        if attachments {
            let attachmentsData =
                self.data["attachments"] as? [String: Any] ?? [:]
            var newAttachments = [String: Attachment]()
            for (key, value) in attachmentsData {
                if let attachmentData = value as? [String: Any] {
                    newAttachments[key] = Attachment(data: attachmentData)
                }
            }
            self.attachments = newAttachments
        }
    }
}

// MARK: - Private functions

private func mergeChunks(_ oldChunks: [[String: Any]], withChunks newChunks: [[String: Any]]) -> [[String: Any]] {
    var chunks = oldChunks
    // Merge the new data chunks with the existing chunks.
    var changed = false
    for chunk in newChunks {
        let chunkId = chunk["id"] as! NSNumber
        if let index = chunks.index(where: { ($0["id"] as! NSNumber).compare(chunkId) == .orderedSame }) {
            // Replace chunks that are already in the array
            chunks.remove(at: index)
            chunks.insert(chunk, at: index)
            continue
        }
        chunks.append(chunk)
        changed = true
    }
    if !changed {
        // Don't sort if nothing changed.
        return chunks
    }
    // Resort the chunks array by timestamps ascending.
    chunks.sort { ($0["start"] as! NSNumber).compare($1["start"] as! NSNumber) == .orderedAscending }
    return chunks
}

// MARK: - Stream Equatable

extension Stream: Equatable {}
func ==(lhs: Stream, rhs: Stream) -> Bool {
    return lhs.id == rhs.id
}
