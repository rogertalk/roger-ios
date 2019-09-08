import Crashlytics
import UIKit

/// A callback that can be used to know when an operation as completed. Events are the preferred way to monitor state changes, however.
typealias StreamServiceCallback = (_ error: Error?) -> Void

class StreamService {
    typealias StreamsDiff = OrderedDictionary<Int64, Stream>.Difference

    static let instance = StreamService()

    static let specialStreamAccounts: [Int64: Stream.Type] = [
        61840001: AlexaStream.self,
        343460002: MessengerStream.self,
        24300006: StatusStream.self,
        355150003: ShareStream.self,
        348520002: VoicemailStream.self,
    ]

    var bots = [Service]() {
        didSet {
            self.cacheStreamsAndIntegrations()
            self.botsChanged.emit()
        }
    }

    var services = [Service]() {
        didSet {
            self.cacheStreamsAndIntegrations()
            self.servicesChanged.emit()
        }
    }

    var featured = [PublicStream]() {
        didSet {
            self.featuredChanged.emit()
        }
    }

    /// The number of unplayed streams.
    var unplayedCount = -1 {
        didSet {
            UIApplication.shared.applicationIconBadgeNumber = self.unplayedCount
        }
    }

    /// The current version of the cached stream data.
    static let cacheVersion = 4

    /// Triggers whenever anything changes (either single streams or the entire list of streams).
    let changed = Event<Void>()
    /// Triggers whenever the order of the recent streams changes.
    let recentStreamsChanged = Event<(newStreams: [Stream], diff: StreamsDiff)>()
    /// The `sentChunk` event is posted whenever a chunk is sent.
    /// The event value is the stream that the chunk was sent to and the related chunk token.
    let sentChunk = Event<(stream: Stream, chunk: SendableChunk)>()
    /// Triggers whenever the Bots collection changes
    let botsChanged = Event<Void>()
    /// Triggers whenever the Services collection changes
    let servicesChanged = Event<Void>()
    /// Triggers whenever the featured gorups collection changes
    let featuredChanged = Event<Void>()
    let streamsEndReached = Event<Void>()

    /// All the recent streams for the current user.
    private(set) var streams = OrderedDictionary<Int64, Stream>() {
        didSet {
            self.cacheStreamsAndIntegrations()
            self.updateUnplayedCount()
            for (_, stream) in self.streams {
                stream.preCacheImage()
            }
            // Emit that something changed.
            self.changed.emit()
            // Calculate a difference and potentially notify interested parties.
            let diff = oldValue.diff(self.streams)
            guard !diff.deleted.isEmpty || !diff.inserted.isEmpty || !diff.moved.isEmpty else {
                // The list of streams didn't change (note that individual streams may still have changed).
                return
            }
            self.recentStreamsChanged.emit(newStreams: self.streams.values, diff: diff)
        }
    }

    var nextPageCursor: String? {
        didSet {
            if self.nextPageCursor == nil {
                self.streamsEndReached.emit()
            }
        }
    }

    /// Searches for a stream with the current user and the provided participants. This is an asynchronous operation, so a callback is needed.
    func getOrCreateStream(participants: [Intent.Participant], showInRecents: Bool = false, title: String? = nil, callback: @escaping (_ stream: Stream?, _ error: Error?) -> Void) {
        if let title = title {
            self.createStream(participants: participants, title: title, image: nil, callback: callback)
            return
        }
        // TODO: Creating streams in this case is bad. We need the backend to support just searching.
        Intent.getOrCreateStream(participants: participants, showInRecents: showInRecents).perform(self.client) {
            guard $0.successful, let data = $0.data, let stream = self.updateWithStreamData(data: data) else {
                callback(nil, $0.error)
                return
            }
            if showInRecents {
                self.includeStreamInRecents(stream: stream)
            }
            callback(stream, nil)
        }
    }

    /// Creates a stream with the given participants, title, and image
    /// The stream is automatically a group if there is more than 1 participant specified
    func createStream(participants: [Intent.Participant] = [], title: String? = nil, image: Intent.Image? = nil, callback: @escaping (_ stream: Stream?, _ error: Error?) -> Void) {
        Intent.createStream(participants: participants, title: title, image: image).perform(self.client) {
            var stream: Stream?
            if $0.successful {
                stream = self.updateWithStreamData(data: $0.data!)
                self.includeStreamInRecents(stream: stream!)
                Responder.userSelectedStream.emit(stream!)
            }
            callback(stream, $0.error)
        }
    }

    func addParticipants(streamId: Int64, participants: [Intent.Participant], callback: StreamServiceCallback? = nil) {
        Intent.addParticipants(streamId: streamId, participants: participants).perform(self.client) { result in
            guard result.successful, let data = result.data else {
                callback?(result.error)
                return
            }
            self.updateWithStreamData(data: data)
            callback?(nil)
        }
    }

    func removeParticipants(streamId: Int64, participants: [Intent.Participant], callback: StreamServiceCallback? = nil) {
        Intent.removeParticipants(streamId: streamId, participants: participants).perform(BackendClient.instance) { result in
            guard result.successful, let data = result.data else {
                callback?(result.error)
                return
            }
            self.updateWithStreamData(data: data)
            callback?(nil)
        }
    }

    /// Joins a group with the given invite token
    func joinGroup(inviteToken: String, callback: StreamServiceCallback? = nil) {
        Intent.joinStream(inviteToken: inviteToken).perform(BackendClient.instance) { result in
            guard let data = result.data, let stream = self.updateWithStreamData(data: data) else {
                callback?(result.error)
                return
            }
            self.includeStreamInRecents(stream: stream)
            Responder.userSelectedStream.emit(stream)
            callback?(nil)
        }
    }

    func leaveStream(streamId: Int64, callback: StreamServiceCallback? = nil) {
        Intent.leaveStream(streamId: streamId).perform(BackendClient.instance)
        if let stream = self.streams[streamId] {
            self.removeStreamFromRecents(stream: stream)
        }
    }

    /// Remove a stream from the main conversations list.
    func removeStreamFromRecents(stream: Stream) {
        var streams = self.streams
        streams.removeValueForKey(stream.id)
        self.streams = streams
    }

    /// Ensures that the stream is in the recent streams list.
    func includeStreamInRecents(stream: Stream) {
        if self.streams[stream.id] != nil {
            return
        }
        self.streams.append((stream.id, stream))
        self.updateStreamOrder()
    }

    /// Loads the next page of streams, if there is a "next page" cursor.
    func loadNextPage(callback: StreamServiceCallback? = nil) {
        Intent.getStreams(cursor: self.nextPageCursor).perform(self.client) {
            guard $0.successful else {
                callback?($0.error)
                return
            }
            let data = $0.data!
            self.setStreamsWithDataList(list: data["data"] as! [DataType])
            self.nextPageCursor = data["cursor"] as? String
            callback?(nil)
        }
    }

    func loadFeatured() {
        guard self.featured.isEmpty else {
            return
        }

        Intent.getFeatured().perform(BackendClient.instance) { result in
            guard result.successful, let data = result.data?["streams"] as? [DataType] else {
                return
            }

            var featuredList = [PublicStream]()
            for featuredData in data {
                guard let stream = PublicStream(featuredData) else {
                    continue
                }

                featuredList.append(stream)
            }
            self.featured = featuredList
        }
    }

    /// Requests an update of the list of recent streams
    func loadServices() {
        Intent.getServices().perform(BackendClient.instance) { result in
            guard result.successful, let data = result.data?["data"] as? [DataType] else {
                return
            }

            var serviceList = [Service]()
            for serviceData in data {
                guard let service = Service(serviceData) else {
                    continue
                }

                serviceList.append(service)
            }
            self.services = serviceList
        }
    }

    /// Requests an update of the list of recent streams
    func loadBots() {
        Intent.getBots().perform(BackendClient.instance) { result in
            guard result.successful, let data = result.data?["data"] as? [DataType] else {
                return
            }

            var botList = [Service]()
            for botData in data {
                guard let bot = Service(botData) else {
                    continue
                }
                botList.append(bot)
            }
            self.bots = botList
        }
    }

    /// Requests an update of the list of recent streams.
    func loadStreams(callback: StreamServiceCallback? = nil) {
        Intent.getStreams(cursor: nil).perform(self.client) {
            guard $0.successful else {
                callback?($0.error)
                return
            }
            let data = $0.data!
            self.setStreamsWithDataList(list: $0.data!["data"] as! [DataType], purge: true)
            if self.nextPageCursor == nil {
                self.nextPageCursor = data["cursor"] as? String
            }
            callback?(nil)
        }
    }

    /// Loads the streams from a local cache file for the current session.
    func loadStreamsAndIntegrationsFromCache() {
        guard let cachePath = self.cachePath else {
            return
        }

        if !FileManager.default.fileExists(atPath: cachePath) {
            return
        }

        guard let cache = NSKeyedUnarchiver.unarchiveObject(withFile: cachePath) as? [String: Any] else {
            return
        }

        guard let version = cache["version"] as? Int, version == StreamService.cacheVersion else {
            try! FileManager.default.removeItem(atPath: cachePath)
            return
        }

        if let streamsData = cache["streams"] as? [DataType] {
            let streamsList = streamsData.flatMap { self.updateWithStreamData(data: $0) }
            self.streams = OrderedDictionary(streamsList.map { ($0.id, $0) })
        }

        if let servicesData = cache["services"] as? [DataType] {
            let servicesList = servicesData.flatMap { Service($0) }
            self.services = servicesList
        }

        if let botsData = cache["bots"] as? [DataType] {
            let botsList = botsData.flatMap { Service($0) }
            self.bots = botsList
        }
    }

    /// Reports the current user's interaction status with a stream.
    func reportStatus(stream: Stream, status: ActivityStatus, estimatedDuration: Int? = nil, callback: StreamServiceCallback? = nil) {
        Intent.setStreamStatus(streamId: stream.id, status: status.rawValue, estimatedDuration: estimatedDuration).perform(self.client) {
            callback?($0.error)
        }
    }

    /// Sends the newly recorded chunk to the backend + cache and update related properties.
    func sendChunk(streamId: Int64, chunk: SendableChunk, persist: Bool? = nil, showInRecents: Bool? = nil, callback: StreamServiceCallback? = nil) {
        Intent.sendChunk(streamId: streamId, chunk: chunk, persist: persist, showInRecents: showInRecents).perform(self.client) {
            if $0.successful {
                self.updateWithStreamData(data: $0.data!)
            }
            callback?($0.error)
        }
        // Simulate the update locally.
        self.performBatchUpdates {
            // Unset others' listened state in anticipation of the backend response and push the end of the stream forward to include the new chunk.
            let newData: DataType = [
                "id": NSNumber(value: streamId),
                "last_interaction": NSNumber(value: Int64(Date().timeIntervalSince1970) * 1000),
                "others_listened": NSNull(),
            ]
            if let stream = self.updateWithStreamData(data: newData) {
                if showInRecents != false {
                    // Make sure the stream is included in the recents list.
                    self.includeStreamInRecents(stream: stream)
                }
                self.sentChunk.emit((stream, chunk))
            }
        }
    }

    func addAttachment(streamId: Int64, attachment: Attachment) {
        Intent.addAttachment(streamId: streamId, attachment: attachment).perform(BackendClient.instance) {
            guard $0.successful else {
                print("Failed to add attachments title: \($0.error)")
                return
            }
            self.updateWithStreamData(data: $0.data!)
        }

        guard let stream = streams[streamId] else {
            return
        }

        if let image = attachment.image {
            stream.attachments[attachment.id] = Attachment(image: image)
        } else if let url = attachment.url {
            stream.attachments[attachment.id] = Attachment(url: url)
        }
        stream.changed.emit()
    }

    func setImage(stream: Stream, image: Intent.Image?, callback: StreamServiceCallback? = nil) {
        Intent.changeStreamImage(streamId: stream.id, image: image).perform(self.client) {
            if $0.successful {
                self.updateWithStreamData(data: $0.data!)
            }
            callback?($0.error)
        }
    }

    func setTitle(stream: Stream, title: String?) {
        Intent.changeStreamTitle(streamId: stream.id, title: title).perform(BackendClient.instance) {
            guard $0.successful else {
                print("Failed to change stream title: \($0.error)")
                return
            }
            self.updateWithStreamData(data: $0.data!)
        }
    }

    func setShareable(stream: Stream, shareable: Bool, callback: StreamServiceCallback? = nil) {
        Intent.changeStreamShareable(id: stream.id, shareable: true).perform(BackendClient.instance) {
            guard $0.successful else {
                print("Failed to set shareable: \($0.error)")
                callback?($0.error)
                return
            }
            self.updateWithStreamData(data: $0.data!)
            callback?(nil)
        }
    }

    /// Updates the backend and the cache with the new "played until" property for the specified stream.
    func setPlayedUntil(stream: Stream, playedUntil: Int64, callback: StreamServiceCallback? = nil) {
        if playedUntil > stream.playedUntil {
            // Update the "played until" value in memory if it's greater than the current one.
            stream.addStreamData([
                "last_played_from": NSNumber(value: stream.playedUntil),
                "played_until": NSNumber(value: playedUntil),
            ])
        }
        Intent.setPlayedUntil(streamId: stream.id, playedUntil: playedUntil).perform(self.client) {
            if $0.successful {
                self.updateWithStreamData(data: $0.data!)
            }
            callback?($0.error)
        }

        // The message has been heard, so cancel the unlistened notice
        if !stream.unplayed, let responder = UIApplication.shared.delegate as? Responder {
            responder.cancelStreamUnlistenedNotif(streamId: stream.id)
        }
    }

    /// Takes a list of stream JSON data objects and replaces the in-memory stream list.
    /// The "purge" flag specifies whether local streams NOT returned by this request are omitted.
    /// Purge applies only to the first 10 streams.
    func setStreamsWithDataList(list: [DataType], purge: Bool = false) {
        self.performBatchUpdates {
            var newStreams = OrderedDictionary<Int64, Stream>()
            for data in list {
                guard let stream = self.updateWithStreamData(data: data) else {
                    continue
                }
                newStreams.append((stream.id, stream))
            }
            // Merge local and server streams lists.
            for (id, stream) in self.streams.dropFirst(purge ? 10 : 0) {
                if !newStreams.keys.contains(id) {
                    newStreams.append((id, stream))
                }
            }
            self.streams = self.sortStreamsList(list: newStreams)
        }
    }

    /// Tries to look up the stream with the specified id and add the provided chunk data to it.
    @discardableResult
    func updateWithStreamChunkData(id: Int64, chunkData: DataType) -> Stream? {
        guard let stream = self.streamsLookup.object(forKey: NSNumber(value: id)) else {
            return nil
        }
        stream.addChunkData(chunkData)
        if self.streams[id] != nil {
            self.updateStreamOrder()
        }
        // Schedule a notice if the chunk was never listened to.
        if stream.duo && stream.unplayed, let responder = UIApplication.shared.delegate as? Responder {
            responder.scheduleStreamUnlistenedNotif(stream: stream)
        }
        return stream
    }

    /// Takes a dictionary for stream JSON data and updates or creates the in-memory stream.
    @discardableResult
    func updateWithStreamData(data: DataType) -> Stream? {
        // Get and update an existing instance of the stream or create one if it doesn't exist.
        // TODO: Try to ensure we don't need the if/else below.
        let id: Int64, boxedId: NSNumber
        if let value = data["id"] as? Int64 {
            id = value
            boxedId = NSNumber(value: id)
        } else {
            boxedId = data["id"] as! NSNumber
            id = boxedId.int64Value
        }

        if let stream = self.streamsLookup.object(forKey: boxedId) {
            stream.addStreamData(data)
            if self.streams[id] != nil {
                // Reorder the recent streams list if it contains the stream that was updated.
                self.updateStreamOrder()
            }
            return stream
        }
        // Before creating the new stream, check if the other participant is a special account.
        var streamType = Stream.self
        if
            let others = data["others"] as? [[String: Any]],
            others.count == 1,
            let otherId = others[0]["id"] as? Int64,
            let type = StreamService.specialStreamAccounts[otherId]
        {
            streamType = type
        }
        guard let stream = streamType.init(data: data) else {
            return nil
        }
        self.streamsLookup.setObject(stream, forKey: boxedId)
        return stream
    }

    func updateUnplayedCount() {
        self.unplayedCount = self.streams.values.reduce(0, { $0 + ($1.unplayed ? 1 : 0) })
    }

    // MARK: - Private

    private let client: BackendClient
    private var batchUpdates = Int32(0)

    /// A weak map of stream ids to stream objects that are still retained in memory.
    private var streamsLookup = NSMapTable<NSNumber, Stream>.strongToWeakObjects()

    /// The path where the in-memory data should be cached on disk. Only available while logged in.
    private var cachePath: String? {
        guard let accountId = self.client.session?.id else {
            return nil
        }
        let directory = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first! as NSString
        let filename = "StreamsService_\(accountId).cache"
        return directory.appendingPathComponent(filename)
    }

    private init() {
        self.client = BackendClient.instance
        self.client.loggedIn.addListener(self, method: StreamService.handleLogIn)
        self.client.loggedOut.addListener(self, method: StreamService.handleLogOut)
    }

    /// Cache streams as an array of JSON dictionaries.
    private func cacheStreamsAndIntegrations() {
        // TODO: Make this method called implicitly after a state change instead of manually everywhere.
        // TODO: Handle batch cache operations (i.e., cache only once per 5 seconds).
        guard let cachePath = self.cachePath else {
            return
        }
        let streams = self.streams.values.prefix(10)
        let streamsData = streams.map { $0.data }
        let servicesData = self.services.map { $0.data }
        let botsData = self.bots.map { $0.data }
        let cache: [String: Any] = [
            "version": StreamService.cacheVersion,
            "streams": streamsData,
            "services": servicesData,
            "bots": botsData,
        ]
        NSKeyedArchiver.archiveRootObject(cache, toFile: cachePath)
    }

    /// Takes a list of stream JSON data objects and returns a list of Stream objects.
    private func getStreamsListFromData(data: [DataType]) -> [Stream] {
        return data.flatMap { self.updateWithStreamData(data: $0) }
    }

    private func handleLogIn(session: Session) {
        self.loadServices()
        self.loadBots()
        // Use the stream data from the session to fill the streams list.
        guard let list = session.data["streams"] as? [DataType] else {
            NSLog("WARNING: Failed to get a list of stream data from session")
            self.streams = OrderedDictionary<Int64, Stream>()
            return
        }
        self.setStreamsWithDataList(list: list)
    }

    private func handleLogOut() {
        // Reset the list of streams whenever the user logs out.
        self.streams = OrderedDictionary<Int64, Stream>()
    }

    /// Used to perform multiple updates to individual streams without reordering the list every time.
    private func performBatchUpdates(closure: () -> ()) {
        OSAtomicIncrement32(&self.batchUpdates)
        closure()
        OSAtomicDecrement32(&self.batchUpdates)
        self.updateStreamOrder()
    }

    /// Updates the internal state of the stream service.
    private func updateStreamOrder() {
        if self.batchUpdates > 0 {
            return
        }
        // Create a sorted copy of the streams list and switch to it.
        self.streams = self.sortStreamsList(list: self.streams)
    }

    // TODO: Investigate how to make this an extension on OrderedDictionary<Int64, Stream>
    private func sortStreamsList(list: OrderedDictionary<Int64, Stream>) -> OrderedDictionary<Int64,Stream> {
        let sorted = list.sorted {
            return $0.value.lastInteractionTime > $1.value.lastInteractionTime
        }
        return OrderedDictionary(sorted)
    }
}

extension Responder {
    /// Schedule a notification in 24 hours if the stream hasn't been listened to.
    fileprivate func scheduleStreamUnlistenedNotif(stream: Stream) {
        // Cancel any previously existing notifs for this stream
        self.cancelStreamUnlistenedNotif(streamId: stream.id)

        let localNotif = UILocalNotification()
        let talkerName = stream.duo ? stream.otherParticipants.first!.displayName : stream.displayName
        localNotif.alertBody = String.localizedStringWithFormat(
            NSLocalizedString("😳 Psst...%@ talked to you yesterday. Listen before it expires!", comment: "Notification"),
            talkerName)
        localNotif.category = Responder.unlistenedNotifCategory
        localNotif.fireDate = NSDate().addingDays(1)
        localNotif.userInfo = ["stream_id": NSNumber(value: stream.id), "type" : Responder.unlistenedNotifIdentifier]
        UIApplication.shared.scheduleLocalNotification(localNotif)
    }

    /// Cancel local notification alerting the sender that the stream is unlistened
    fileprivate func cancelStreamUnlistenedNotif(streamId: Int64) {
        guard let notif = self.getStreamUnlistenedNotif(streamId: streamId) else {
            return
        }
        UIApplication.shared.cancelLocalNotification(notif)
    }

    /// Find an existing "unlistened" notif for this stream, if one exists.
    private func getStreamUnlistenedNotif(streamId: Int64) -> UILocalNotification? {
        guard let localNotifs = UIApplication.shared.scheduledLocalNotifications else {
            return nil
        }

        for notif in localNotifs {
            let isMatchingStream = (notif.userInfo?["stream_id"] as? NSNumber)?.int64Value == streamId
            let isUnlistenedNotice = notif.userInfo?["type"] as? String == Responder.unlistenedNotifIdentifier
            if isMatchingStream && isUnlistenedNotice {
                return notif
            }
        }
        return nil
    }
}
