import Foundation

struct Profile: Account {
    static let rogerAccountId: Int64 = 512180002

    let data: DataType
    let id: Int64

    var bot: Bool {
        return self.status == "bot"
    }

    var isRogerProfile: Bool {
        return self.id == Profile.rogerAccountId
    }
    
    var contact: ContactEntry? {
        return ContactService.shared.findContact(byAccountId: self.id)
    }

    var displayName: String {
        // Use names in this order:
        // 1) Address book name.
        // 2) Account display name.
        if !self.participants.isEmpty {
            let names = self.participants.map({ $0.displayName.replacingOccurrences(of: "+", with: " ").rogerShortName }).localizedJoin()
            return self.participants.count <= 3 ? names :
                "\(names.rogerShortName) + \(self.participants.count - 1)"
        } else if let name = self.contact?.name {
            return name
        } else {
            return self.remoteDisplayName
        }
    }

    var greeting: Greeting? {
        return self.participants.isEmpty ? Greeting(accountId: self.id, data: self.data) : nil
    }

    var identifier: String {
        return String(self.id)
    }

    var imageURL: URL? {
        guard let urlString = data["image_url"] as? String else {
            return nil
        }
        return URL(string: urlString)
    }

    var location: String? {
        return nil
    }

    var participants: [Participant] = []

    var remoteDisplayName: String {
        return (self.data["display_name"] as! String)
            .replacingOccurrences(of: "+", with: " ")
    }

    var status: String {
        return self.data["status"] as? String ?? "bot"
    }

    var timeZone: String? {
        return nil
    }

    var unplayed: Bool {
        return self.greeting != nil
    }

    var username: String? {
        return self.data["username"] as? String
    }

    init?(_ data: DataType) {
        self.data = data
        guard let id = data["id"] as? NSNumber else {
            self.id = -1
            return nil
        }
        self.id = id.int64Value
        if let audioURL = self.greeting?.audioURL {
            // Cache the greeting immediately
            AudioService.instance.cacheRemoteAudioURL(audioURL)
        }

        if let participantsArray = self.data["participants"] as? [DataType] {
            self.participants = participantsArray.map(Participant.init)
        }
    }

    init(identifier: String) {
        var profileData = DataType()
        if let id = Int64(identifier) {
            profileData["id"] = NSNumber(value: id)
        } else {
            profileData["id"] = NSNumber(value: Int64(-1))
            profileData["username"] = identifier
        }
        profileData["display_name"] = NSLocalizedString("Someone", comment: "Name fallback")
        self.init(profileData)!
    }

    init(identifier: String, name: String, imageURL: URL?) {
        var profileData = DataType()
        if let id = Int64(identifier) {
            profileData["id"] = NSNumber(value: id)
        } else {
            profileData["id"] = NSNumber(value: Int64(-1))
            profileData["username"] = identifier
        }
        profileData["display_name"] = name
        profileData["image_url"] = imageURL?.absoluteString
        self.init(profileData)!
    }
}
