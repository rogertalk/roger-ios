import Alamofire
import Foundation
import UIKit

/// The version of the API that we want to use.
private let API_VERSION = 22

typealias DataType = [String: Any]
typealias IntentCallback = (IntentResult) -> Void

/// The result from performing an intent.
struct IntentResult {
    let data: DataType?
    let error: Error?
    let code: Int

    init(data: DataType?, error: Error?, code: Int = -1) {
        self.data = data
        self.error = error
        self.code = code
    }

    var successful: Bool {
        return self.error == nil
    }
}

/// Anything that takes an intent, performs it, and returns the result in the provided callback.
protocol Performer {
    func performIntent(_ intent: Intent, callback: IntentCallback?)
}

/// Allows performing a request with a performer as a method on the intent.
extension Intent {
    func perform(_ performer: Performer, callback: IntentCallback? = nil) {
        performer.performIntent(self, callback: callback)
    }
}

/// A complete implementation of a performer (for making HTTP calls to the backend).
class BackendClient: Performer {
    // TODO: Support connecting to both development and production environment.
    static let instance = BackendClient("https://api.rogertalk.com")

    let baseURL: URL

    // TODO: Only use the session if it's for the current environment.
    var session: Session? {
        didSet {
            if let session = self.session {
                session.setUserDefaults()
                if session.id != oldValue?.id {
                    self.loggedIn.emit(session)
                }
            } else if oldValue != nil {
                Session.clearUserDefaults()
                self.loggedOut.emit()
            }
            self.sessionChanged.emit()
        }
    }

    let loggedIn = Event<Session>()
    let loggedOut = Event<Void>()
    let sessionChanged = Event<Void>()

    init(_ baseURLString: String) {
        self.baseURL = URL(string: baseURLString)!
        self.session = Session.fromUserDefaults()
        self.retryRequestQueue = [Intent]()
        self.manager = Alamofire.SessionManager()
        self.backgroundManager = Alamofire.SessionManager(configuration: URLSessionConfiguration.background(withIdentifier: "im.rgr.RogerApp.BackgroundManager"))
    }

    /// Gets the necessary information for being able to perform a request.
    func getRequestInfo(_ intent: Intent) -> RequestInfo? {
        var info = RequestInfo(baseURL: self.baseURL)
        info.session = self.session

        switch intent {
        case let .addAttachment(streamId, attachment):
            info.endpoint = (.post, "/v\(API_VERSION)/streams/\(streamId)/attachments/\(attachment.id)")
            if let json = try? JSONSerialization.data(withJSONObject: attachment.data, options: []) {
                info.queryString["data"] = String(data: json, encoding: String.Encoding.utf8)
            }
            if let image = attachment.image, let imageData = UIImageJPEGRepresentation(image, 1) {
                info.form["url"] = FileData.fromImage(Intent.Image(format: .jpeg, data: imageData))
            }

        case let .addParticipants(streamId, participants):
            info.endpoint = (.post, "/v\(API_VERSION)/streams/\(streamId)/participants")
            info.form["participant"] = participants.map { $0.description }

        case let .batchGetOrCreateStreams(participants):
            info.endpoint = (.post, "/v\(API_VERSION)/batch")
            info.form["participant"] = participants.map { $0.description }

        case let .blockUser(identifier):
            info.endpoint = (.post, "/v\(API_VERSION)/profile/me/blocked")
            info.queryString["identifier"] = identifier

        case let .buzz(streamId):
            info.endpoint = (.post, "/v\(API_VERSION)/streams/\(streamId)/buzz")

        case let .changeDisplayName(name):
            info.endpoint = (.post, "/v\(API_VERSION)/profile/me")
            info.queryString["display_name"] = name

        case let .changeShareLocation(share):
            info.endpoint = (.post, "/v\(API_VERSION)/profile/me")
            info.queryString["share_location"] = share.description

        case let .changeStreamImage(id, image):
            guard let image = image else {
                info.endpoint = (.delete, "/v\(API_VERSION)/streams/\(id)/image")
                break
            }
            info.endpoint = (.post, "/v\(API_VERSION)/streams/\(id)")
            info.form["image"] = FileData.fromImage(image)

        case let .changeStreamShareable(id, shareable):
            info.endpoint = (.post, "/v\(API_VERSION)/streams/\(id)")
            info.queryString["shareable"] = shareable.description

        case let .changeStreamTitle(id, title):
            guard let title = title else {
                info.endpoint = (.delete, "/v\(API_VERSION)/streams/\(id)/title")
                break
            }
            info.endpoint = (.post, "/v\(API_VERSION)/streams/\(id)")
            info.queryString["title"] = title

        case let .changeUserImage(image):
            info.endpoint = (.post, "/v\(API_VERSION)/profile/me")
            info.form["image"] = FileData.fromImage(image)

        case let .changeUsername(username):
            info.endpoint = (.post, "/v\(API_VERSION)/profile/me")
            info.queryString["username"] = username

        case let .createStream(participants, title, image):
            info.endpoint = (.post, "/v\(API_VERSION)/streams")
            info.queryString["participant"] = participants.map { $0.description }
            if let title = title {
                info.queryString["title"] = title
            }
            if let image = image {
                info.form["image"] = FileData.fromImage(image)
            }
            info.queryString["show_in_recents"] = "true"
            info.queryString["shareable"] = "true"

        case .getAccessCode:
            info.endpoint = (.post, "/v\(API_VERSION)/code")
            info.queryString["client_id"] = "web"

        case let .getActiveContacts(identifiers):
            info.endpoint = (.post, "/v\(API_VERSION)/contacts")
            info.body = identifiers.joined(separator: "\n").data(using: String.Encoding.utf8, allowLossyConversion: false)

        case .getBots:
            info.endpoint = (.get, "/v\(API_VERSION)/bots")

        case let .getOrCreateStream(participants, showInRecents):
            info.endpoint = (.post, "/v\(API_VERSION)/streams")
            info.form["participant"] = participants.map { $0.description }
            info.queryString["show_in_recents"] = showInRecents.description
            info.queryString["shareable"] = (participants.count > 1).description

        case .getOwnProfile:
            info.endpoint = (.get, "/v\(API_VERSION)/profile/me")

        case let .getProfile(identifier):
            info.endpoint = (.get, "/v\(API_VERSION)/profile/\(identifier)")

        case .getFeatured:
            info.endpoint = (.get, "/v\(API_VERSION)/featured")

        case .getServices:
            info.endpoint = (.get, "/v\(API_VERSION)/services")

        case let .getStream(id):
            info.endpoint = (.get, "/v\(API_VERSION)/streams/\(id)")

        case let .getStreams(cursor):
            info.endpoint = (.get, "/v\(API_VERSION)/streams")
            info.queryString["cursor"] = cursor

        case let .getWeather(accountIds):
            info.endpoint = (.get, "/v\(API_VERSION)/weather")
            info.queryString["identifiers"] = accountIds.map(String.init).joined(separator: ",")

        case let .joinStream(inviteToken):
            info.endpoint = (.post, "/v\(API_VERSION)/streams")
            info.queryString["invite_token"] = inviteToken

        case let .leaveStream(streamId):
            info.endpoint = (.delete, "/v\(API_VERSION)/streams/\(streamId)")

        case let .logIn(username, password):
            info.authenticateClient = true
            info.endpoint = (.post, "/oauth2/token")
            info.queryString = [
                "grant_type": "password",
                "api_version": API_VERSION,
            ]
            info.form = [
                "username": username,
                "password": password,
            ]

        case .logOut:
            // No request should be made for logging out (at least not for now).
            return nil

        case .pingIFTTT:
            info.endpoint = (.post, "/v\(API_VERSION)/ifttt")

        case let .refreshSession(refreshToken):
            info.authenticateClient = true
            info.endpoint = (.post, "/oauth2/token")
            info.queryString = [
                "grant_type": "refresh_token",
                "api_version": API_VERSION,
            ]
            info.form["refresh_token"] = refreshToken

        case let .register(displayName, image, firstStreamParticipant):
            info.endpoint = (.post, "/v\(API_VERSION)/register")
            if let name = displayName {
                info.queryString["display_name"] = name
            }
            if let image = image {
                info.form["image"] = FileData.fromImage(image)
            }
            if let participant = firstStreamParticipant {
                info.form["stream_participant"] = participant
            }

        case let .registerDeviceForPush(deviceId, token, platform):
            info.endpoint = (.post, "/v\(API_VERSION)/device")
            info.queryString["platform"] = platform
            info.form["device_id"] = deviceId
            info.form["device_token"] = token

        case let .removeParticipants(streamId, participants):
            info.endpoint = (.delete, "/v\(API_VERSION)/streams/\(streamId)/participants")
            info.queryString["participant"] = participants.map { $0.description }

        case let .removeAttachment(streamId, attachmentId):
            info.endpoint = (.delete, "/v\(API_VERSION)/streams/\(streamId)/attachments/\(attachmentId)")

        case let .report(eventName, values):
            info.endpoint = (.post, "/v\(API_VERSION)/report/\(eventName)")
            for (key, value) in values {
                info.form[key] = String(describing: value)
            }

        case let .requestChallenge(identifier, preferPhoneCall):
            info.endpoint = (.post, "/v\(API_VERSION)/challenge")
            info.form["identifier"] = identifier
            info.form["call"] = preferPhoneCall.description

        case let .respondToChallenge(identifier, secret, firstStreamParticipant):
            info.endpoint = (.post, "/v\(API_VERSION)/challenge/respond")
            info.form = [
                "identifier": identifier,
                "secret": secret,
            ]
            if let participant = firstStreamParticipant {
                info.form["stream_participant"] = participant
            }

        case let .sendChunk(streamId, chunk, persist, showInRecents):
            info.endpoint = (.post, "/v\(API_VERSION)/streams/\(streamId)/chunks")
            info.queryString["chunk_token"] = chunk.token
            info.queryString["duration"] = String(chunk.duration)
            info.queryString["persist"] = persist?.description
            info.queryString["show_in_recents"] = showInRecents?.description
            info.form["audio"] = chunk.audioURL

        case let .sendInvite(identifiers, inviteToken, names):
            info.endpoint = (.post, "/v\(API_VERSION)/invite")
            info.queryString["identifier"] = identifiers
            if let token = inviteToken {
                info.queryString["invite_token"] = token
            }
            if let names = names {
                info.queryString["name"] = names
            }

        case let .setLocation(location):
            info.endpoint = (.post, "/v\(API_VERSION)/profile/me")
            info.queryString["location"] = "\(location.coordinate.latitude),\(location.coordinate.longitude)"

        case let .setPlayedUntil(streamId, playedUntil):
            info.endpoint = (.post, "/v\(API_VERSION)/streams/\(streamId)")
            info.queryString["played_until"] = String(playedUntil)

        case let .setStreamStatus(streamId, status, estimatedDuration):
            info.endpoint = (.post, "/v\(API_VERSION)/streams/\(streamId)")
            info.queryString["status"] = status
            if let duration = estimatedDuration {
                info.queryString["status_estimated_duration"] = duration
            }

        case let .showStream(id):
            info.endpoint = (.post, "/v\(API_VERSION)/streams/\(id)")
            info.queryString["visible"] = "true"

        case let .unregisterDeviceForPush(deviceToken):
            info.endpoint = (.delete, "/v\(API_VERSION)/device/\(deviceToken)")
        }
        
        return info
    }

    /// Perform an intent and report back when done.
    func performIntent(_ intent: Intent, callback: IntentCallback?) {
        guard let requestInfo = self.getRequestInfo(intent) else {
            // There was no HTTP request to make, but still report the completion of the request.
            self.reportResultForIntent(intent, result: IntentResult(data: nil, error: nil), callback: callback)
            return
        }

        // Wait until all other chunks in progress are sent before sending this one
        if case .sendChunk = intent {
            guard !self.sendingChunkInProgress else {
                self.sendChunkQueue.insert((intent, callback), at: 0)
                return
            }
            self.sendingChunkInProgress = true
        }

        let sessionManager = intent.retryable ? self.backgroundManager : self.manager

        #if DEBUG
        NSLog("%@", "\(requestInfo.method) \(requestInfo.path) \(requestInfo.queryString)")
        #endif

        // Branch depending on whether there is a file to upload.
        if requestInfo.hasFiles {
            sessionManager.upload(
                multipartFormData: {
                    requestInfo.applyMultipartFormData($0)
                },
                with: requestInfo,
                encodingCompletion: {
                    switch $0 {
                    case let .success(request, _, _):
                        self.handleRequestForIntent(intent, request: request, callback: callback)
                    case let .failure(error):
                        self.reportResultForIntent(intent, result: IntentResult(data: nil, error: error), callback: callback)
                    }
                }
            )
        } else {
            let request = sessionManager.request(requestInfo)
            self.handleRequestForIntent(intent, request: request, callback: callback)
        }
    }

    /// Replaces the current session's account data with new account data.
    func updateAccountData(_ data: DataType) {
        self.session = self.session?.withNewAccountData(data)
    }

    // MARK: - Private

    private let manager: Alamofire.SessionManager
    private let backgroundManager: Alamofire.SessionManager
    private var retryRequestQueue: [Intent]
    private var sendChunkQueue: [(Intent, IntentCallback?)] = []
    private var sendingChunkInProgress = false

    /// Performs the provided request and reports the result.
    private func handleRequestForIntent(_ intent: Intent, request: DataRequest, callback: IntentCallback?) {
        request.responseJSON {
            let statusCode = $0.response?.statusCode ?? -1

            // Technically an array would be valid JSON but we only care about dictionaries.
            let data = $0.result.value as? DataType

            // Look for several error cases and ensure error is set if they have occurred.
            var finalError = $0.result.error
            if let errorInfo = data?["error"] as? DataType {
                finalError = BackendError(statusCode: statusCode, info: errorInfo)
            }
            if finalError == nil && !(200...299 ~= statusCode) {
                finalError = NSError(
                    domain: "com.rogertalk.api",
                    code: statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP code \(statusCode)"]
                )
            }

            if statusCode != -1 {
                // The request reached the backend. Attempt to send anything that is pending.
                self.attemptFlushRetryQueue()
            } else if intent.retryable {
                // The request failed and is retryable, add it to the retry queue.
                self.retryRequestQueue.append(intent)
            }

            // Report the result of the request.
            self.reportResultForIntent(intent, result: IntentResult(data: data, error: finalError, code: statusCode), callback: callback)
        }
    }

    /// Reports the result of performing an intent by calling the callback. Also updates internal state.
    private func reportResultForIntent(_ intent: Intent, result: IntentResult, callback: IntentCallback?) {
        if case .sendChunk = intent {
            self.sendingChunkInProgress = false
            // Perform any other pending requests
            if let request = self.sendChunkQueue.popLast() {
                self.performIntent(request.0, callback: request.1)
            }
        }

        if result.code == 401 {
            // Clear the session when requests fail.
            self.session = nil
        }

        // Perform internal state updates based on intents and their outcomes.
        switch intent {
        case let .getOrCreateStream(participants, _):
            // We can only guarantee 1:1 mapping for streams with one other participant.
            if participants.count != 1 {
                break
            }
            // Make sure that newly discovered accounts are in the identifier -> account id map.
            guard result.successful, let data = result.data else {
                break
            }
            guard let stream = StreamService.instance.updateWithStreamData(data: data), stream.otherParticipants.count == 1 else {
                break
            }

            // Add the identifier (phone/e-mail only) -> account id mappings to the address book service.
            let identifiers = participants[0].identifiers
                .map { $0.identifier }
                .filter { $0.hasPrefix("+") || $0.contains("@") }
            let account = stream.otherParticipants[0]
            ContactService.shared.map(identifiers: identifiers, toAccount: AccountEntry(account: account))
        case let .createStream(participants, _, _):
            let identifiers = participants.flatMap { $0.identifiers.map { $0.identifier } }
            ContactService.shared.updateAccountActiveState(forIdentifiers: identifiers)
        case let .addParticipants(_, participants):
            let identifiers = participants.flatMap { $0.identifiers.map { $0.identifier } }
            ContactService.shared.updateAccountActiveState(forIdentifiers: identifiers)
        case .batchGetOrCreateStreams:
            guard result.successful else {
                break
            }
            StreamService.instance.loadStreams()
        case .logIn, .refreshSession, .register:
            // Update the session for intents that result in new session data.
            guard result.successful, let data = result.data else {
                break
            }
            self.session = Session(data, timestamp: Date())
            // Session responses may contain streams data; pass it on to the streams service.
            if let list = data["streams"] as? [DataType] {
                StreamService.instance.setStreamsWithDataList(list: list)
                StreamService.instance.nextPageCursor = data["cursor"] as? String
            }
        case .logOut:
            // Clear the session for the log out intent.
            self.session = nil
        case .changeDisplayName, .changeShareLocation, .changeUserImage, .changeUsername, .getOwnProfile, .setLocation:
            // Update the current session's account data when we get or update the user's profile.
            guard result.successful, let data = result.data else {
                break
            }
            self.updateAccountData(data)
        default:
            break
        }

        // Finally call the callback (if any) with the result.
        callback?(result)
    }

    private func attemptFlushRetryQueue() {
        let taskId = UIApplication.shared.beginBackgroundTask (expirationHandler: {
            // We have run out of time.
        })

        let retries = self.retryRequestQueue
        self.retryRequestQueue.removeAll()
        for intent in retries {
            intent.perform(BackendClient.instance)
        }

        if taskId != UIBackgroundTaskInvalid {
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }
}

class BackendError: NSError {
    override var localizedDescription: String {
        guard let message = self.userInfo["message"] as? String else {
            return super.localizedDescription
        }
        return message
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    init(statusCode: Int, info: [String: Any]) {
        var code = info["code"] as? Int ?? -1
        if code == -1 {
            // Fall back to the status code for undefined error codes.
            code = statusCode
        }
        super.init(domain: "com.rogertalk.api", code: code, userInfo: info)
    }
}

private class FileData {
    let data: Data
    let name: String
    let mimeType: String

    init(data: Data, name: String, mimeType: String) {
        self.data = data
        self.name = name
        self.mimeType = mimeType
    }

    static func fromImage(_ image: Intent.Image) -> FileData {
        let filename, mimetype: String
        switch image.format {
        case .jpeg:
            filename = "image.jpg"
            mimetype = "image/jpeg"
        case .png:
            filename = "image.png"
            mimetype = "image/png"
        }
        return FileData(data: image.data as Data, name: filename, mimeType: mimetype)
    }
}

/// Represents information needed to make an HTTP request to the API.
struct RequestInfo: URLRequestConvertible {
    private let baseURL: URL
    var authenticateClient = false
    var method = HTTPMethod.get
    var path = "/"
    var session: Session?
    /// Query string parameters to put in the URL.
    var queryString = [String: Any]()
    /// Form data that should go in the HTTP body (only for POST).
    var form = [String: Any]()
    /// The HTTP Body
    var body: Data?

    /// Convenience property for assigning method and path at the same time as a tuple.
    var endpoint: (method: HTTPMethod, path: String) {
        get {
            return (self.method, self.path)
        }
        set {
            self.method = newValue.method
            self.path = newValue.path
        }
    }

    /// Checks if any fields point at local file URLs or NSData objects.
    var hasFiles: Bool {
        return self.form.values.contains { $0 is FileData || $0 is Data || $0 is URL }
    }

    /// The URL for the request (note: without the query string values).
    var url: URL {
        return self.baseURL.appendingPathComponent(self.path)
    }

    static var userAgentPieces: [(String, String)] = {
        let os = ProcessInfo().operatingSystemVersion
        return [
            ("Roger", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "UNKNOWN"),
            ("VoiceOver", UIAccessibilityIsVoiceOverRunning() ? "1" : "0"),
            ("Darwin", String(format: "%i.%i.%i", os.majorVersion, os.minorVersion, os.patchVersion)),
            ("Model", UIDevice.current.modelIdentifier),
        ]
    }()

    static var userAgent: String = {
        return RequestInfo.userAgentPieces.map { (key, value) in "\(key)/\(value)" }.joined(separator: " ")
    }()

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func applyMultipartFormData(_ multipart: MultipartFormData) {
        func append(_ name: String, value: Any) {
            switch value {
            case let data as Data:
                multipart.append(data, withName: name)
            case let file as FileData:
                multipart.append(file.data, withName: name, fileName: file.name, mimeType: file.mimeType)
            case let url as URL:
                multipart.append(url, withName: name)
            default:
                let data = String(describing: value).data(using: .utf8)!
                multipart.append(data, withName: name)
            }
        }

        for (fieldName, value) in self.form {
            if let array = value as? [Any] {
                array.forEach {
                    append(fieldName, value: $0)
                }
            } else {
                append(fieldName, value: value)
            }
        }
    }

    // MARK: URLRequestConvertible

    func asURLRequest() -> URLRequest {
        var request = URLRequest(url: self.url)

        if self.authenticateClient {
            // Basic client auth.
            request.setValue("Basic aW9zOlY5MWpuOEVFOEdzUEVUZFFId1NPNDRQT0FaUjFDRENDSUF0YlFqM00=", forHTTPHeaderField: "Authorization")
        } else if let token = self.session?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.setValue(RequestInfo.userAgent, forHTTPHeaderField: "User-Agent")

        if let language = Locale.preferredLanguages.first {
            request.setValue(language, forHTTPHeaderField: "Accept-Language")
        }

        // Add the query string parameters to the path.
        if self.queryString.count > 0 {
            if let r = try? URLEncoding.default.encode(request, with: self.queryString) {
                request = r
            }
        }

        // Apply method after query string so that Alamofire doesn't put it in the HTTP body.
        request.httpMethod = self.method.rawValue
        if let httpBody = self.body {
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            request.httpBody = httpBody
        }

        // Apply form data here if there are no files to upload. Files are added in applyMultipartFormData.
        if self.form.count > 0 && !self.hasFiles {
            precondition(self.method == .post, "Form data can only be added to POST requests")
            if let r = try? URLEncoding.default.encode(request, with: self.form) {
                request = r
            }
        }

        return request
    }
}
