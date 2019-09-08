import Foundation

protocol Account {
    var id: Int64 { get }
    var displayName: String { get }
    var imageURL: URL? { get }
    var location: String? { get }
    var remoteDisplayName: String { get }
    var sharingLocation: Bool { get }
    var timeZone: String? { get }
    var username: String? { get }
    var status: String { get }
}

extension Account {
    var active: Bool {
        return self.status == "active" || self.bot
    }

    var bot: Bool {
        return self.status == "bot"
    }

    var localTime: Date? {
        guard let name = self.timeZone else {
            return nil
        }
        return Date().forTimeZone(name)!
    }

    var profileURL: URL {
        let identifier = self.username ?? String(self.id)
        return SettingsManager.baseURL.appendingPathComponent(identifier)
    }

    var sharingLocation: Bool {
        return self.location != nil
    }

    func profileURLWithChunkToken(_ chunkToken: String) -> URL {
        return self.profileURL.appendingPathComponent(chunkToken)
    }
}
