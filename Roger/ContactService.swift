import Contacts
import Foundation
import libPhoneNumber_iOS

extension AccountEntry {
    init(account: Account) {
        self.init(active: account.active, id: account.id)
    }
}

fileprivate let contactKeys = [
    CNContactEmailAddressesKey as CNKeyDescriptor,
    CNContactFamilyNameKey as CNKeyDescriptor,
    CNContactGivenNameKey as CNKeyDescriptor,
    CNContactImageDataKey as CNKeyDescriptor,
    CNContactNicknameKey as CNKeyDescriptor,
    CNContactOrganizationNameKey as CNKeyDescriptor,
    CNContactPhoneNumbersKey as CNKeyDescriptor,
]

fileprivate let batchSize = 500

fileprivate var cacheDir: URL? {
    // Try using the group container
    guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.im.rgr") else {
        // If the group container is unavailable, use local app cache directory
        return nil
    }
    return url.appendingPathComponent("Library", isDirectory:  true).appendingPathComponent("Caches", isDirectory: true)
}

fileprivate let accountIndexPath = cacheDir?.appendingPathComponent("IdentifierToAccount.cache")
fileprivate let contactsPath = cacheDir?.appendingPathComponent("Contacts.cache")

class ContactService {
    static let shared = ContactService()

    let contactsChanged = Event<Void>()
    let fetchingActiveContacts = Event<Bool>()

    var authorizationStatus: CNAuthorizationStatus {
        return CNContactStore.authorizationStatus(for: .contacts)
    }

    var authorized: Bool {
        return self.authorizationStatus == .authorized
    }

    var region: String {
        return self.util.countryCodeByCarrier().uppercased()
    }

    private(set) var accountIndex = [String: AccountEntry]() {
        didSet {
            self.rebuildIdentifierIndex()
            self.contactsChanged.emit()
        }
    }
    private(set) var contactIndex = [String: ContactEntry]()
    private(set) var contacts = [ContactEntry]() {
        didSet {
            self.rebuildContactIndex()
            self.rebuildIdentifierIndex()
            // Do this only once.
            if oldValue.isEmpty {
                self.buildUninvitedContacts()
            }
            self.contactsChanged.emit()
            // Update the account map at least once per 12 hours.
            guard Date().timeIntervalSince(self.accountIndexTimestamp) >= TimeInterval(43_200) else {
                return
            }
            self.updateAccountActiveState(forIdentifiers: self.contacts.flatMap { $0.identifiers }) {
                if $0 {
                    self.accountIndexTimestamp = Date()
                }
            }
        }
    }
    private(set) var identifierIndex = [Int64: String]()
    private(set) var uninvitedContacts = [ContactEntry]()

    func findContact(byAccountId accountId: Int64) -> ContactEntry? {
        guard let identifier = self.identifierIndex[accountId] else {
            return nil
        }
        return self.contactIndex[identifier]
    }

    func findContact(byIdentifiers identifiers: [String]) -> ContactEntry? {
        for identifier in identifiers {
            if let contact = self.contactIndex[identifier] {
                return contact
            }
        }
        return nil
    }

    func importContacts(requestAccess: Bool = false) {
        let auth = self.authorizationStatus
        guard auth == .authorized || (requestAccess && auth == .notDetermined) else {
            print("unable to import contacts (access is \(auth))")
            if auth == .denied {
                UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
            }
            return
        }
        let start = CFAbsoluteTimeGetCurrent()
        self.queue.async {
            let fetchRequest = CNContactFetchRequest(keysToFetch: contactKeys)
            fetchRequest.sortOrder = .userDefault
            do {
                var entries = [ContactEntry]()
                try CNContactStore().enumerateContacts(with: fetchRequest) { contact, _ in
                    var name = contact.nickname
                    if name == "" {
                        name = "\(contact.givenName) \(contact.familyName)"
                    }
                    if name == " " {
                        name = contact.organizationName
                    }
                    var identifierToLabel = [String: String]()
                    self.extract(labeledValues: contact.emailAddresses, map: &identifierToLabel)
                    self.extract(labeledValues: contact.phoneNumbers, map: &identifierToLabel)
                    let entry = ContactEntry(
                        id: contact.identifier,
                        identifierToLabel: identifierToLabel,
                        imageData: nil,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                    entries.append(entry)
                }
                self.contacts = entries
                self.saveContacts()
            } catch let error as NSError {
                print("Failed to import contacts: \(error)")
            }
            print("importContacts took \(CFAbsoluteTimeGetCurrent() - start) sec")
        }
    }

    func map(identifiers: [String], toAccount account: AccountEntry) {
        for identifier in identifiers {
            self.accountIndex[identifier] = account
        }
        self.rebuildIdentifierIndex()
        self.saveAccountIndex()
        self.contactsChanged.emit()
    }

    func normalize(identifier: String) -> String {
        if let e164 = self.validateAndNormalize(phoneNumber: identifier) {
            return e164
        }
        return identifier
    }

    func prettify(phoneNumber: String, forceInternational: Bool = false) -> String? {
        guard let number = self.parse(phoneNumber: phoneNumber, region: nil) else {
            return nil
        }
        let format: NBEPhoneNumberFormat
        if forceInternational || self.util.getRegionCode(for: number) != self.sessionRegion {
            format = .INTERNATIONAL
        } else {
            format = .NATIONAL
        }
        if let formatted = try? self.util.format(number, numberFormat: format) {
            return "\u{202A}\(formatted)\u{202C}"
        }
        return nil
    }

    func sendInvite(toContact contact: ContactEntry, inviteToken: String? = nil) {
        let identifiers = contact.identifiers.map(self.normalize)
        let names = [String](repeating: contact.name, count: identifiers.count)
        // Send invite SMS from the backend.
        Intent.sendInvite(identifiers: identifiers, inviteToken: inviteToken, names: names).perform(BackendClient.instance) {
            guard $0.successful, let map = $0.data?["map"] as? [String: [String: Any]] else {
                return
            }
            self.accountIndexTimestamp = Date()
            self.updateAccountIndex(map: map)
            self.saveAccountIndex()
            // Track already invited contacts.
            SettingsManager.invitedContacts.append(contact.id)
        }
        // Remove from uninvited list.
        if let index = self.uninvitedContacts.index(of: contact) {
            self.uninvitedContacts.remove(at: index)
        }
    }

    func updateAccountActiveState(forIdentifiers identifiers: [String], callback: ((Bool) -> Void)? = nil) {
        guard identifiers.count > 0 else {
            callback?(false)
            return
        }
        let divisions = 1 + identifiers.count / batchSize
        // Keep track of the number of pending requests.
        // TODO: Make this work if there are two calls to this method in parallel.
        var pendingRequests = Int32(divisions)
        self.fetchingActiveContacts.emit(true)
        var gotResults = false
        for i in 0..<divisions {
            // Build a list of contact details and request account ids from the backend.
            let batch = Array(identifiers[i * batchSize..<min((i + 1) * batchSize, identifiers.count)])
            Intent.getActiveContacts(identifiers: batch).perform(BackendClient.instance) {
                if $0.successful, let map = $0.data?["map"] as? [String: [String: Any]] {
                    if map.count > 0 {
                        gotResults = true
                    }
                    self.updateAccountIndex(map: map)
                }
                // Perform finalization logic only once for the entire set of batches.
                if OSAtomicDecrement32(&pendingRequests) == 0 {
                    self.saveAccountIndex()
                    // Create streams with all active contacts.
                    var participants: [Intent.Participant] = []
                    for (identifier, entry) in self.accountIndex {
                        guard entry.active else {
                            continue
                        }
                        participants.append(Intent.Participant(value: identifier))
                    }
                    Intent.batchGetOrCreateStreams(participants: participants).perform(BackendClient.instance)
                    // Notify interested parties that the update completed.
                    self.fetchingActiveContacts.emit(false)
                    callback?(gotResults)
                }
            }
        }
    }

    func validateAndNormalize(phoneNumber: String, region: String? = nil) -> String? {
        guard let number = self.parse(phoneNumber: phoneNumber, region: region) else {
            return nil
        }
        return try? self.util.format(number, numberFormat: .E164)
    }

    // MARK: Private

    private var accountIndexTimestamp = Date.distantPast
    private var contactStoreDidChangeToken: NSObjectProtocol? = nil
    private let queue = DispatchQueue(label: "im.rgr.RogerApp.ContactService", qos: .background)
    private let util = NBPhoneNumberUtil()

    // The region of the current session based on any registered phone number.
    private lazy var sessionRegion: String = {
        guard let identifiers = BackendClient.instance.session?.identifiers else {
            return "ZZ"
        }
        for identifier in identifiers {
            guard
                identifier.hasPrefix("+"),
                let number = try? self.util.parse(identifier, defaultRegion: "ZZ"),
                let region = self.util.getRegionCode(for: number)
                else { continue }
            return region
        }
        return "ZZ"
    }()

    deinit {
        NotificationCenter.default.removeObserver(self.contactStoreDidChangeToken)
    }

    private init() {
        NSKeyedArchiver.setClassName("RogerAddressBookContact", for: ContactEntry.Coder.self)
        NSKeyedUnarchiver.setClass(ContactEntry.Coder.self, forClassName: "RogerAddressBookContact")
        self.loadContacts()
        self.loadAccountIndex()
        self.contactStoreDidChangeToken = NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) {
            _ in
            self.importContacts()
        }
    }

    private func buildUninvitedContacts() {
        let invited = SettingsManager.invitedContacts
        var contacts = self.contacts.filter {
            // Filter out already active or already invited contacts.
            return !invited.contains($0.id) && !$0.identifiers.contains { self.accountIndex[$0]?.active ?? false }
        }
        contacts.shuffle()
        self.uninvitedContacts = contacts
    }

    private func extract(labeledValues: [CNLabeledValue<CNPhoneNumber>], map: inout [String: String]) {
        for item in labeledValues {
            guard
                let region = (item.value.value(forKey: "countryCode") as? String)?.uppercased(),
                let digits = item.value.value(forKey: "digits") as? String,
                let identifier = self.validateAndNormalize(phoneNumber: digits, region: region)
                else { continue }
            map[identifier] = self.localized(label: item.label)
        }
    }

    private func extract(labeledValues: [CNLabeledValue<NSString>], map: inout [String: String]) {
        for item in labeledValues {
            map[item.value as String] = self.localized(label: item.label)
        }
    }

    private func loadAccountIndex() {
        guard let path = accountIndexPath else {
            return
        }

        self.queue.async {
            NSFileCoordinator().coordinate(readingItemAt: path, options: .withoutChanges, error: nil) { url in
                guard let object = NSKeyedUnarchiver.unarchiveObject(withFile: url.path) as? [String: Any],
                    let version = object["version"] as? Int,
                    version == 1,
                    let timestamp = object["timestamp"] as? Date,
                    let map = object["map"] as? [String: [String: Any]]
                    else { return }
                self.accountIndexTimestamp = timestamp
                self.updateAccountIndex(map: map)
            }
        }
    }

    private func loadContacts() {
        // Do not load from cache if permissions have not been granted.
        guard let path = contactsPath, self.authorized else { return }
        self.queue.async {
            NSFileCoordinator().coordinate(readingItemAt: path, options: .withoutChanges, error: nil) { url in
                // TODO: Handle versioning of the cached data.
                guard let contacts = NSKeyedUnarchiver.unarchiveObject(withFile: url.path) as? [ContactEntry.Coder] else {
                    return
                }
                self.contacts = contacts.map { $0.entry }
                self.rebuildContactIndex()
            }
        }
    }

    private func localized(label: String?) -> String {
        guard let label = label else { return "" }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }

    private func parse(phoneNumber: String, region: String?) -> NBPhoneNumber? {
        if region == nil, let number = try? self.util.parse(withPhoneCarrierRegion: phoneNumber) {
            return number
        }
        return try? self.util.parse(phoneNumber, defaultRegion: region ?? self.sessionRegion)
    }

    private func rebuildContactIndex() {
        var index = [String: ContactEntry]()
        for contact in self.contacts {
            contact.identifiers.forEach { index[$0] = contact }
        }
        self.contactIndex = index
    }

    private func rebuildIdentifierIndex() {
        var index = [Int64: String]()
        for (identifier, entry) in self.accountIndex {
            index[entry.id] = identifier
        }
        self.identifierIndex = index
    }

    private func saveAccountIndex() {
        guard let path = accountIndexPath else {
            return
        }

        NSFileCoordinator().coordinate(writingItemAt: path, options: .forReplacing, error: nil)  { url in
            self.queue.async {
                var object = [String: Any]()
                object["timestamp"] = self.accountIndexTimestamp
                object["version"] = 1
                var map = [String: [String: Any]]()
                for (identifier, entry) in self.accountIndex {
                    map[identifier] = ["id": NSNumber(value: entry.id), "active": entry.active]
                }
                object["map"] = map
                NSKeyedArchiver.archiveRootObject(object, toFile: url.path)
            }
        }
    }

    private func saveContacts() {
        guard let path = contactsPath else {
            return
        }

        self.queue.async {
            let data = self.contacts.map { ContactEntry.Coder(entry: $0) }
            NSFileCoordinator().coordinate(writingItemAt: path, options: .forReplacing, error: nil) { url in
                NSKeyedArchiver.archiveRootObject(data, toFile: url.path)
            }
        }
    }

    private func updateAccountIndex(map: [String: [String: Any]]) {
        for (identifier, info) in map {
            self.accountIndex[identifier] = AccountEntry(
                active: info["active"] as! Bool,
                id: (info["id"] as! NSNumber).int64Value)
        }
    }
}
