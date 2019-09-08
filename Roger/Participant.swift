import Foundation

class Participant: Account {
    let id: Int64
    private(set) var activityStatus: ActivityStatus = .Idle
    private(set) var activityStatusEnd = Date()

    var contact: ContactEntry? {
        return ContactService.shared.findContact(byAccountId: self.id)
    }

    var displayName: String {
        // Prefer to use address book name.
        if let name = self.contact?.name {
            return name
        } else {
            return self.remoteDisplayName
        }
    }

    var imageURL: URL? {
        if let url = self.data["image_url"] as? String {
            return URL(string: url)
        }
        return nil
    }

    var location: String? {
        return self.data["location"] as? String
    }

    var ownerId: Int64? {
        return (self.data["owner_id"] as? NSNumber)?.int64Value
    }

    var remoteDisplayName: String {
        return self.data["display_name"] as! String
    }

    var status: String {
        return self.data["status"] as! String
    }

    var timeZone: String? {
        return self.data["timezone"] as? String
    }

    var username: String? {
        return self.data["username"] as? String
    }

    init(data: DataType) {
        self.data = data
        self.id = (data["id"] as! NSNumber).int64Value
    }

    /// Sets the status with an estimated duration.
    func updateActivityStatus(_ activityStatus: ActivityStatus, duration: Int) {
        self.activityStatus = activityStatus
        self.activityStatusEnd = Date(timeIntervalSinceNow: Double(duration) / 1000)
    }

    // MARK: Private

    private let data: DataType
}

class LocalParticipant: Participant {
    init?(contact: Contact) {
        guard let sessionId = BackendClient.instance.session?.id else {
            return nil
        }
        var participantData: DataType
        if let contact = contact as? AddressBookContact {
            participantData = [
                "display_name": contact.name,
                "id": NSNumber(value: contact.account?.id ?? -1),
                "status": contact.account?.active ?? false ? "active" : "invited",
            ]
        } else if let contact = contact as? ProfileContact {
            participantData = contact.profile.data
            participantData["status"] = contact.profile.status
            if contact.profile.bot {
                participantData["owner_id"] = NSNumber(value: sessionId)
            }
        } else if let contact = contact as? ServiceContact {
            let service = contact.service
            participantData = [
                "id": NSNumber(value: service.accountId ?? -1),
                "display_name": service.title,
                "owner_id": NSNumber(value: sessionId),
                "status": "bot",
                "username": service.identifier,
            ]
        } else {
            return nil
        }

        super.init(data: participantData)
    }
}
