import UIKit

enum Action {
    case nothing
    case createStream(identifier: String)
    case sms(phoneNumber: String)
    case addFromAddressBook
    case searchHandle
    case shareStreamLink
    case addBots
    case editParticipant(identifier: String)
}

protocol Section {
    var cellReuseIdentifier: String { get }
    var headerTitle: String? { get }
    var rowHeight: CGFloat { get }
    var count: Int { get }

    func canSelect(_ row: Int) -> Bool
    func populateCell(_ row: Int, cell: UITableViewCell)
    func handleSelect(_ row: Int) -> Action
    func handleAccessory(_ row: Int) -> Action
}

/// Default implementations of Section functionality
extension Section {
    func canSelect(_ row: Int) -> Bool {
        return true
    }

    func handleAccessory(_ row: Int) -> Action {
        return .nothing
    }

    func handleSelect(_ row: Int) -> Action {
        return .nothing
    }
}
