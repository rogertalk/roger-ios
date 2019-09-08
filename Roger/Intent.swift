import CoreLocation

/// The representation of an intent to request something of the API.
enum Intent {
    /// Adds an attachment to a stream.
    case addAttachment(streamId: Int64, attachment: Attachment)
    /// Add participants to an existing stream.
    case addParticipants(streamId: Int64, participants: [Participant])
    /// Batch request streams.
    case batchGetOrCreateStreams(participants: [Participant])
    /// Blocks a user with the specified identifier.
    case blockUser(identifier: String)
    /// Sends an empty alert notification to the specified stream purely to get participants' attention.
    case buzz(streamId: Int64)
    /// Changes the display name of the current user.
    case changeDisplayName(newDisplayName: String)
    /// Change location sharing privacy setting.
    case changeShareLocation(share: Bool)
    /// Changes the image shown for a stream.
    case changeStreamImage(streamId: Int64, image: Image?)
    /// Changes whether the stream is shareable via an invite link.
    case changeStreamShareable(id: Int64, shareable: Bool)
    /// Changes the title of the stream.
    case changeStreamTitle(streamId: Int64, title: String?)
    /// Changes the profile image of the current user.
    case changeUserImage(image: Image)
    /// Changes the username of the current user.
    case changeUsername(username: String)
    /// Creates a new titled stream with the provided participants.
    case createStream(participants: [Participant], title: String?, image: Image?)
    /// Requests an access code for logging into a service.
    case getAccessCode()
    /// Sends the user's contacts list and gets back active users.
    case getActiveContacts(identifiers: [String])
    /// Gets a list of available bots that can be added to conversations.
    case getBots()
    /// Gets or creates an untitled stream with the given participants.
    case getOrCreateStream(participants: [Participant], showInRecents: Bool)
    /// Gets the current user's profile.
    case getOwnProfile()
    /// Gets the profile of a user with the specified identifier.
    case getProfile(identifier: String)
    /// Requests featured streams.
    case getFeatured()
    /// Gets a list of available services.
    case getServices()
    /// Returns information for a single stream.
    case getStream(id: Int64)
    /// Requests the streams that have been most interactly interacted with (paginated).
    case getStreams(cursor: String?)
    /// Gets the current weather for the provided list of account ids.
    case getWeather(accountIds: [Int64])
    /// Join a stream using the provided invite token.
    case joinStream(inviteToken: String)
    /// Leave a stream.
    case leaveStream(streamId: Int64)
    /// Logs the user in with a username and password.
    case logIn(username: String, password: String)
    /// Logs the user out.
    case logOut()
    /// Pings IFTTT to kick off new recipe triggers.
    case pingIFTTT()
    /// Gets a new access token using a refresh token.
    case refreshSession(refreshToken: String)
    /// Registers an anonymous account.
    case register(displayName: String?, image: Image?, firstStreamParticipant: String?)
    /// Registers the device for push notifications.
    case registerDeviceForPush(deviceId: String, token: String, platform: String)
    /// Removes an attachment from a stream.
    case removeAttachment(streamId: Int64, attachmentId: String)
    /// Remove participants from an existing stream.
    case removeParticipants(streamId: Int64, participants: [Participant])
    /// Reports an event to the Roger reporting pipeline.
    case report(eventName: String, values: [String: Any])
    /// Requests a secret to the specified identifier (usually a phone number).
    case requestChallenge(identifier: String, preferPhoneCall: Bool)
    /// Responds with a secret that was previously requested to prove ownership. Also creates a preliminary stream, if corresponding participant info is specified.
    case respondToChallenge(identifier: String, secret: String, firstStreamParticipant: String?)
    /// Sends a chunk of audio data to the specified stream. Providing a token makes the chunk accessible on the web.
    case sendChunk(streamId: Int64, chunk: SendableChunk, persist: Bool?, showInRecents: Bool?)
    /// Request an invite to be sent to this number.
    case sendInvite(identifiers: [String], inviteToken: String?, names: [String]?)
    /// Sets the coordinates for the current user.
    case setLocation(location: CLLocation)
    /// Sets the "played until" timestamp in the stream for the current user.
    case setPlayedUntil(streamId: Int64, playedUntil: Int64)
    /// Sets a status for the stream, such as "listening" or "talking".
    case setStreamStatus(streamId: Int64, status: String, estimatedDuration: Int?)
    /// Unhides a stream that was previously hidden from the conversations list.
    case showStream(id: Int64)
    /// Stop sending push notifications to the provided token.
    case unregisterDeviceForPush(token: String)

    var retryable: Bool {
        switch self {
        case .registerDeviceForPush, .report, .sendChunk:
            return true
        default:
            return false
        }
    }

    /// Represents a chunk to be uploaded (the file URL is to a local file).
    struct Chunk: SendableChunk {
        let audioURL: URL
        let duration: Int
        let token: String?
    }

    struct Image {
        enum Format {
            case jpeg, png
        }
        let format: Format
        let data: Data
    }

    /// Represents a single participant in a stream.
    struct Participant: CustomStringConvertible {
        typealias Identifier = (label: String?, identifier: String)
        let identifiers: [Identifier]

        init(identifiers: [Identifier]) {
            self.identifiers = identifiers
        }

        init(value: String) {
            let pieces = value.characters.split(separator: ",").map(String.init)

            var identifiers = [Identifier]()
            for piece in pieces {
                let labelAndValue = piece.characters.split(separator: ":", maxSplits: 2).map(String.init)
                if labelAndValue.count == 2 {
                    identifiers.append((label: labelAndValue[0], identifier: labelAndValue[1]))
                } else {
                    identifiers.append((label: nil, identifier: labelAndValue[0]))
                }
            }
            self.identifiers = identifiers
        }

        var description: String {
            return self.identifiers.map {
                if let label = $0.label {
                    return "\(label):\($0.identifier)"
                }
                return $0.identifier
            }.joined(separator: ",")
        }
    }
}
