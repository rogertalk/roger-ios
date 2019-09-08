import Foundation

private func getAccountId(_ data: DataType) -> Int64? {
    guard let account = data["account"] as? DataType, let id = account["id"] as? NSNumber else {
        return nil
    }
    return id.int64Value
}

struct Session: Account {
    let data: DataType

    var accessToken: String {
        return self.data["access_token"] as! String
    }

    var account: [String: Any] {
        return self.data["account"] as! DataType
    }

    let id: Int64

    var active: Bool {
        return self.data["status"] as! String == "active"
    }

    var didSetDisplayName: Bool {
        return self.account["display_name_set"] as? Bool ?? true
    }

    var displayName: String {
        return self.remoteDisplayName
    }

    var expires: Date {
        let ttl = (self.data["expires_in"] as! NSNumber).intValue
        return (self.timestamp as NSDate).addingSeconds(ttl)
    }

    var greeting: Greeting? {
        guard let data = self.data["greeting"] as? DataType else {
            return nil
        }
        return Greeting(accountId: self.id, data: data)
    }

    var hasLocation: Bool {
        return self.shareLocation && self.location != nil
    }

    var identifiers: [String]? {
        if let identifiers = self.account["aliases"] as? [String] {
            return identifiers
        }
        return self.account["identifiers"] as? [String]
    }

    var imageURL: URL? {
        guard let urlString = self.account["image_url"] as? String else {
            return nil
        }
        return URL(string: urlString)
    }

    var location: String? {
        return self.account["location"] as? String
    }

    var refreshToken: String? {
        return self.data["refresh_token"] as? String
    }

    var remoteDisplayName: String {
        return self.account["display_name"] as! String
    }

    var shareLocation: Bool {
        return self.account["share_location"] as? Bool ?? false
    }

    var status: String {
        return self.data["status"] as! String
    }

    let timestamp: Date

    var timeZone: String? {
        // TODO: Ideally we'll make this value never nil.
        return self.account["timezone"] as? String
    }

    var username: String? {
        return self.account["username"] as? String
    }

    static func clearUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "session")
        defaults.removeObject(forKey: "sessionTimestamp")
        defaults.removeObject(forKey: "sessionRefreshToken")
        defaults.removeObject(forKey: "sessionVersion")
    }

    static func fromUserDefaults() -> Session? {
        // Attempt to get the session data out of the user defaults.
        // TODO: This should be deprecated in favor of Keychain Services.
        let defaults = UserDefaults.standard
        let session = defaults.object(forKey: "session")
        // Ensure the session is of a compatible version.
        let version = defaults.integer(forKey: "sessionVersion")
        switch version {
        case 0, 1:
            return nil
        case 2:
            // This is the current version.
            guard let archivedData = session as? Data else {
                return nil
            }
            let timestamp = defaults.object(forKey: "sessionTimestamp") as? Date
            let data = NSKeyedUnarchiver.unarchiveObject(with: archivedData) as! DataType
            return Session(data, timestamp: timestamp ?? Date())
        default:
            NSLog("WARNING: Tried to load session with unsupported defaults version")
            return nil
        }
    }

    init?(_ data: DataType, timestamp: Date) {
        self.data = data
        guard let id = getAccountId(data) else {
            self.id = -1
            return nil
        }
        self.id = id
        self.timestamp = timestamp
    }

    func setUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(NSKeyedArchiver.archivedData(withRootObject: self.data), forKey: "session")
        defaults.set(self.timestamp, forKey: "sessionTimestamp")
        if let refreshToken = self.refreshToken {
            defaults.set(refreshToken, forKey: "sessionRefreshToken")
        }
        defaults.set(2, forKey: "sessionVersion")
    }

    func withNewAccountData(_ accountData: DataType) -> Session? {
        var data = self.data
        data["account"] = accountData
        return Session(data, timestamp: self.timestamp)
    }
}
