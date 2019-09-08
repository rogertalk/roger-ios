import UIKit

protocol Contact {
    var active: Bool { get }
    var description: String { get }
    var identifier: String { get }
    var image: UIImage? { get }
    var name: String { get }
    var phoneNumber: String? { get }
}

extension Contact {
    var shortName: String {
        return self.name.rogerShortName
    }
}

class AddressBookContact: Contact, CustomDebugStringConvertible {
    let account: AccountEntry?
    let identifier: String
    let image: UIImage?
    let label: String?
    let name: String

    lazy private(set) var phoneNumber: String? = self.identifier.hasPrefix("+") ? self.identifier : nil

    var active: Bool {
        return self.account?.active ?? false
    }

    var debugDescription: String {
        return "\(type(of: self))(identifier: \(self.identifier))"
    }

    var description: String {
        get {
            if self.active {
                return NSLocalizedString("on Roger", comment: "Active contact description")
            }
            return "\(self.label ?? ""), \(self.formattedIdentifier)"
        }
    }

    init(identifier: String, name: String, account: AccountEntry? = nil, image: UIImage? = nil, label: String? = nil) {
        self.account = account ?? ContactService.shared.accountIndex[identifier]
        self.identifier = identifier
        self.image = image
        self.label = label
        self.name = name
    }

    lazy private var formattedIdentifier: String = ContactService.shared.prettify(phoneNumber: self.identifier) ?? self.identifier
}

class AccountContact: Contact {
    var phoneNumber: String? {
        return ContactService.shared.identifierIndex[self.account.id]
    }

    var name: String {
        return self.account.displayName
    }

    var active: Bool {
        return (self.account as? Participant)?.active ?? true
    }

    var identifier: String {
        return String(self.account.id)
    }

    var image: UIImage? {
        return self.cachedImage
    }

    var imageURL: URL? {
        return self.account.imageURL as URL?
    }

    var description: String {
        if let username = self.account.username , self.active {
            return "@\(username)"
        }
        return NSLocalizedString("Hasn't joined yet", comment: "Active contact description")
    }

    init(account: Account) {
        self.account = account
        // TODO: Download the account's image from imageURL if possible
        if let data = ContactService.shared.findContact(byAccountId: account.id)?.imageData {
            let image = UIImage(data: data, scale: UIScreen.main.scale)
            self.cachedImage = image?.scaleToFitSize(CGSize(width: 80, height: 80))
        }
    }

    fileprivate let account: Account
    fileprivate var cachedImage: UIImage?
    lazy private var formattedIdentifier: String = ContactService.shared.prettify(phoneNumber: self.identifier) ?? self.identifier
}

class BotContact: AccountContact {
    let ownerName: String?
    init(account: Account, owner: String?) {
        self.ownerName = owner
        super.init(account: account)
    }
}

class IdentifierContact: Contact, CustomDebugStringConvertible {
    let active = false
    let description = ""
    let identifier: String
    let image: UIImage? = nil
    let name: String
    let phoneNumber: String?

    var debugDescription: String {
        return "\(type(of: self))(identifier: \(self.identifier))"
    }

    init(identifier: String) {
        let normalized = ContactService.shared.normalize(identifier: identifier)
        self.identifier = normalized
        self.name = ContactService.shared.prettify(phoneNumber: identifier) ?? identifier
        self.phoneNumber = normalized.hasPrefix("+") ? normalized : nil
    }
}

class ProfileContact: Contact {
    let active = true
    let image: UIImage? = AvatarView.singlePersonImage
    let phoneNumber: String? = nil

    var description: String {
        if let username = self.profile.username {
            return "@\(username)"
        }
        return NSLocalizedString("on Roger", comment: "Active contact description")
    }

    var name: String {
        return self.profile.displayName
    }

    var imageURL: URL? {
        return self.profile.imageURL as URL?
    }

    var identifier: String {
        return self.profile.identifier
    }

    init(profile: Profile) {
        self.profile = profile
    }

    let profile: Profile
}

func ==(left: AccountContact, right: AddressBookContact) -> Bool {
    return left.account.id == right.account?.id
}

func ==(left: AccountContact, right: ProfileContact) -> Bool {
    return left.account.id == right.profile.id
}

class StreamContact: Contact, CustomDebugStringConvertible {
    let stream: Stream

    var active: Bool {
        return self.stream.empty || self.stream.otherParticipants.contains { $0.active }
    }

    var debugDescription: String {
        return "\(type(of: self))(identifier: \(self.identifier))"
    }

    var description: String {
        guard self.active else {
            return self.stream.statusText
        }
        return NSLocalizedString("on Roger", comment: "Active contact description")
    }

    var identifier: String {
        return String(self.stream.id)
    }

    var image: UIImage? {
        return self.stream.image ?? AvatarView.singlePersonImage
    }

    var name: String {
        return self.stream.displayName
    }

    lazy fileprivate(set) var phoneNumber: String? = {
        guard !self.stream.group, let contact = ContactService.shared.findContact(byAccountId: self.stream.primaryAccount.id) else {
            return nil
        }
        return contact.identifiers.lazy.filter({ $0.hasPrefix("+") }).first
    }()

    var shortName: String {
        return self.stream.shortTitle
    }

    init(stream: Stream) {
        self.stream = stream
    }
}

class ServiceContact: Contact {
    let active = true
    let image: UIImage? = nil
    let phoneNumber: String? = nil

    var description: String {
        return self.service.description
    }

    var identifier: String {
        // TODO: This needs to be cleaned up.
        guard let id = self.service.accountId else {
            return self.service.identifier
        }
        return String(id)
    }

    var name: String {
        return self.service.title
    }

    var stream: Stream? {
        return self.service.stream
    }
    
    init(service: Service) {
        self.service = service
    }
    
    let service: Service
}
