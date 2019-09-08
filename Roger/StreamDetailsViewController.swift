import Crashlytics
import MessageUI

class StreamDetailsViewController :
    UIViewController,
    UITableViewDataSource,
    UITableViewDelegate,
    MFMessageComposeViewControllerDelegate,
    ContactPickerDelegate,
    BotPickerDelegate,
    QuickInviteDelegate {

    @IBOutlet weak var membersTableView: UITableView!
    @IBOutlet weak var titleLabel: UILabel!

    // Waiting pulse view
    @IBOutlet weak var waitingPulseView: UIView!
    @IBOutlet weak var waitingStatusLabel: UILabel!
    @IBOutlet weak var waitingPulseCircleView: UIView!
    @IBOutlet weak var waitingBackgroundImageView: UIImageView!
    @IBOutlet weak var waitingPulseViewHeightConstraint: NSLayoutConstraint!

    var stream: Stream? {
        didSet {
            oldValue?.changed.removeListener(self)
            self.stream?.changed.addListener(self, method: StreamDetailsViewController.refresh)

            guard self.isViewLoaded else {
                return
            }
            self.refresh()
        }
    }

    var presetTitle: String? = nil

    override func viewDidLoad() {
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        self.view.addSubview(self.statusIndicatorView)

        self.membersTableView.register(UINib(nibName: "ContactCell", bundle: nil), forCellReuseIdentifier: ContactCell.reuseIdentifier)
        self.membersTableView.delegate = self
        self.membersTableView.dataSource = self

        ContactService.shared.contactsChanged.addListener(self, method: StreamDetailsViewController.setupContactsToInvite)
        self.setupContactsToInvite()
        self.refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        self.view.layoutIfNeeded()

        self.updateWaitingPulseView()
        self.stream?.changed.addListener(self, method: StreamDetailsViewController.refresh)
    }

    override func viewWillDisappear(_ animated: Bool) {
        self.stream?.changed.removeListener(self)
    }

    override var prefersStatusBarHidden : Bool {
        return true
    }

    // MARK: - Actions

    @IBAction func backTapped(_ sender: AnyObject) {
        self.navigationController?.popViewControllerModal()
    }

    @IBAction func conversationOptionsTapped(_ sender: AnyObject) {
        guard let stream = self.stream , stream.activeParticipants.count > 0 else {
            let alert = UIAlertController(
                title: NSLocalizedString("Members needed", comment: "Alert title"),
                message: NSLocalizedString("Conversations need at least\none other active member before they\ncan be configured.\n\nTry adding someone! 😀", comment: "Group invite alert text"),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert action"), style: .default) { action in
                let picker = ContactPickerViewController.create(.addressBook, delegate: self)
                self.navigationController?.pushViewController(picker, animated: true)
                })
            self.present(alert, animated: true, completion: nil)
            return
        }

        guard let root = self.navigationController?.viewControllers.first as? StreamsViewController else {
            return
        }

        self.navigationController?.popToRootViewControllerModal()
        root.showStreamOptions(stream)
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.performAction(self.sections[(indexPath as NSIndexPath).section].handleSelect((indexPath as NSIndexPath).row))
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return self.sections[(indexPath as NSIndexPath).section].rowHeight
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return self.sections[(indexPath as NSIndexPath).section].canSelect((indexPath as NSIndexPath).row)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let sectionObject = self.sections[section]
        return sectionObject.count == 0 || sectionObject.headerTitle == nil ? CGFloat.leastNormalMagnitude : 40
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return CGFloat.leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sectionObject = self.sections[section]
        guard let header = sectionObject.headerTitle , sectionObject.count > 0 else {
            return nil
        }
        // Containing view for the section header label
        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 20))

        // Create section label with header text
        let sectionLabel = UILabel(frame: CGRect(x: 0, y: 0, width: headerView.bounds.width - 32, height: 20))
        sectionLabel.center = headerView.center
        sectionLabel.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        sectionLabel.font = UIFont.rogerFontOfSize(12)
        sectionLabel.textColor = UIColor.lightGray
        sectionLabel.accessibilityLabel = header
        sectionLabel.text = header.uppercased()

        headerView.addSubview(sectionLabel)
        return headerView
    }

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        self.performAction(self.sections[(indexPath as NSIndexPath).section].handleAccessory((indexPath as NSIndexPath).row))
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return self.sections.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = self.sections[(indexPath as NSIndexPath).section]
        let cell = self.membersTableView.dequeueReusableCell(withIdentifier: section.cellReuseIdentifier, for: indexPath)
        section.populateCell((indexPath as NSIndexPath).row, cell: cell)
        return cell
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.sections[section].count
    }

    // MARK: - MFMessageComposeViewControllerDelegate

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        // Dismiss the SMS UI.
        self.dismiss(animated: true, completion: nil)
        Answers.logCustomEvent(withName: "SMS Reminder Complete", customAttributes: ["Result": result.description])

        guard result != MessageComposeResult.cancelled else {
            // SMS was cancelled, show the share sheet.
            let vc = Share.createGroupInviteShareSheet(
                self.stream?.groupInviteURL,
                anchor: self.membersTableView,
                source: "StreamDetails")
            self.present(vc, animated: true, completion: nil)
            return
        }
        self.statusIndicatorView.showConfirmation()
    }

    // MARK: - ContactPickerDelegate

    func didFinishPickingContacts(_ picker: ContactPickerViewController, contacts: [Contact]) {
        _ = self.navigationController?.popViewController(animated: true)
        self.membersTableView.scrollToTop(true)
        self.addStreamParticipants(contacts)
    }

    // MARK: - BotPickerDelegate

    func didFinishPickingBot(_ picker: BotPickerViewController, bot: Service) {
        _ = self.navigationController?.popViewController(animated: true)
        self.addStreamParticipants([ServiceContact(service: bot)])
    }

    // MARK: - QuickInviteDelegate

    var contactsToInvite: [ContactEntry] = []

    func dismissInvite() { }

    func invite(_ contact: ContactEntry) {
        defer {
            if let index = self.contactsToInvite.index(of: contact) {
                self.contactsToInvite.remove(at: index)
            }
        }
        guard let identifier = contact.identifierToLabel.keys.first else {
            return
        }
        let contact = AddressBookContact(identifier: identifier, name: contact.name)
        self.addStreamParticipants([contact])
    }

    func didReceiveFocus(_ quickInviteView: QuickInviteView) {
        self.membersTableView.scrollToBottom(true)
    }

    // MARK: - Private

    private var statusIndicatorView: StatusIndicatorView!
    private var pulser: Pulser?

    private var sections: [Section] = []

    private func setupContactsToInvite() {
        guard !ContactService.shared.contacts.isEmpty else {
            return
        }
        // Setup QuickInviter
        self.contactsToInvite = ContactService.shared.contacts
        self.contactsToInvite.shuffle()
        // Only refresh the contacts list once.
        ContactService.shared.contactsChanged.removeListener(self)
    }

    private func refresh() {
        self.updateWaitingPulseView()
        self.refreshSections()
        guard let stream = self.stream else {
            self.titleLabel.text =
                self.presetTitle ?? NSLocalizedString("New Conversation", comment: "Streamd details title")
            return
        }
        self.titleLabel.text = stream.title ?? NSLocalizedString("Conversation", comment: "Stream details title")
    }

    /// Create and populate the Sections
    private func refreshSections() {
        // TODO: Support section diffing to prevent recreating sections each time and enable scrolling to whichever section changed.
        if let stream = self.stream {
            self.contactsToInvite = self.contactsToInvite.filter {
                guard
                    let identifier = $0.identifierToLabel.keys.first,
                    let accountId = ContactService.shared.accountIndex[identifier]?.id
                    else { return true }
                return accountId != BackendClient.instance.session?.id && !stream.otherParticipants.contains { $0.id == accountId }
            }
        }

        self.sections = []
        guard let stream = self.stream else {
            // Create the actives section with no other participants (user is included by default)
            self.sections.append(ActiveSection(participants: []))
            self.sections.append(AddMembersSection())
            // self.sections.append(quickInviteSection ?? QuickInviteSection(delegate: self))
            return
        }

        // Create sections
        self.sections.append(InvitedSection(participants: stream.invitedParticipants))
        self.sections.append(BotSection(participants: stream.botParticipants, stream: stream))
        self.sections.append(ActiveSection(participants: stream.activeParticipants.filter { !$0.bot }))
        self.sections.append(AddMembersSection())
        //self.sections.append(quickInviteSection ?? QuickInviteSection(delegate: self))

        // Stay at bottom if we were already near it
        let contentHeight = self.membersTableView.contentSize.height
        let contentOffset = self.membersTableView.contentOffset.y
        let wasNearBottom = contentHeight > 0 && contentOffset > 0 &&
            contentOffset > contentHeight - self.membersTableView.frame.height - 20
        // Update UI
        self.membersTableView.reloadData()
        if wasNearBottom {
            self.membersTableView.scrollToBottom()
        }
    }

    /// Update the WaitingPulseView visibility and state.
    private func updateWaitingPulseView() {
        let isEmptyStream = stream?.reachableParticipants.isEmpty ?? true
        let hasPendingInvites = self.stream?.invitedParticipants.count ?? 0 > 0
        // Only show the WaitingPulseView if there are no participants or if there are pending invites
        guard isEmptyStream || hasPendingInvites else {
            UIView.animate(withDuration: 0.2, animations: {
                self.waitingPulseViewHeightConstraint.constant = 0
                self.view.layoutIfNeeded()
            }, completion: { success in
                self.waitingPulseView.isHidden = true
            }) 
            self.pulser?.stop()
            self.pulser = nil
            return
        }

        self.waitingPulseView.isHidden = false
        UIView.animate(withDuration: 0.2, animations: {
            self.waitingPulseViewHeightConstraint.constant = 100
            self.view.layoutIfNeeded()
        }) 
        self.waitingBackgroundImageView.image = hasPendingInvites ?
            UIImage(named: "waitingPulseBlueBackground") : UIImage(named: "waitingPulseRedBackground")
        self.waitingStatusLabel.text = hasPendingInvites ?
            NSLocalizedString("Waiting for members to join", comment: "Stream Details waiting view") :
            NSLocalizedString("Your conversation is empty, add members!", comment: "Stream Details waiting view")
        self.pulser = Pulser(color: UIColor(white: 1, alpha: 0.6), finalScale: 2.3, strokeWidth: 10)
        self.pulser!.start(self.waitingPulseCircleView)
    }

    /// Send an invite to the given phone numbers if possible, otherwise show the share sheet.
    private func sendInvite(_ phoneNumbers: [String], inviteURL: URL?) {
        // Show share sheet if SMS is not possible
        guard MFMessageComposeViewController.canSendText() else {
            let vc = Share.createGroupInviteShareSheet(
                inviteURL,
                anchor: self.membersTableView,
                source: "StreamDetails")
            self.present(vc, animated: true, completion: nil)
            return
        }

        // Show invite SMS UI
        let messageComposer = Share.createGroupMessageComposer(inviteURL, recipients: phoneNumbers, delegate: self)
        self.present(messageComposer, animated: true, completion: nil)
        Answers.logCustomEvent(withName: "Group invite SMS Shown", customAttributes: nil)
    }

    private func performAction(_ action: Action) {
        switch action {
        case let .createStream(identifier):
            // Create a stream with the specified participant identifier
            self.statusIndicatorView.showLoading()
            self.membersTableView.allowsSelection = false
            StreamService.instance.getOrCreateStream(participants: [Intent.Participant(value: identifier)], title: self.presetTitle) {
                stream, error in
                guard let stream = stream else {
                    return
                }

                // TODO: Move this to a delegate?
                let oldestStreamInteractionTime =
                    StreamService.instance.streams.values.last?.lastInteractionTime ?? Date.distantPast
                if (stream.lastInteractionTime as NSDate).isLaterThan(oldestStreamInteractionTime) {
                    StreamService.instance.includeStreamInRecents(stream: stream)
                }
                Responder.userSelectedStream.emit(stream)
                self.navigationController?.popToRootViewControllerModal()
            }
            return
        case let .sms(phoneNumber):
            // Send an SMS invite to the specified number reminding them of the group invite
            self.sendInvite([phoneNumber], inviteURL: self.stream?.groupInviteURL)
            return
        case .addFromAddressBook:
            // Get current participants list to mark them as unselectable in the picker
            // Show contact picker in Address Book mode
            let picker = ContactPickerViewController.create(
                .addressBook,
                delegate: self,
                unselectable: self.stream?.otherParticipants.map { return AccountContact(account: $0) } )
            self.navigationController?.pushViewController(picker, animated: true)
            return
        case .addBots:
            let bots = BotPickerViewController.create(self)
            self.navigationController?.pushViewController(bots, animated: true)
            break
        case .searchHandle:
            // Show contact picker in Search mode
            let picker = ContactPickerViewController.create(
                .search,
                delegate: self,
                unselectable: self.stream?.otherParticipants.map { return AccountContact(account: $0) } )
            self.navigationController?.pushViewController(picker, animated: true)
            return
        case .shareStreamLink:
            // Share stream link to other apps
            guard let inviteURL = self.stream?.groupInviteURL else {
                self.statusIndicatorView.showLoading()
                guard let stream = self.stream else {
                    // There is no stream yet, so create it now
                    StreamService.instance.getOrCreateStream(participants: [], showInRecents: true, title: self.presetTitle) {
                        stream, error in
                        guard let stream = stream else {
                            return
                        }
                        self.stream = stream
                        Responder.userSelectedStream.emit(stream)
                        self.performAction(.shareStreamLink)
                    }
                    return
                }
                StreamService.instance.setShareable(stream: stream, shareable: true) { error in
                    guard error == nil else {
                        return
                    }
                    self.statusIndicatorView.hide()
                    self.performAction(.shareStreamLink)
                }
                return
            }
            let share = Share.createGroupInviteShareSheet(inviteURL, anchor: self.membersTableView, source: "AddMemberCell") { success in
                guard success else {
                    self.statusIndicatorView.hide()
                    return
                }
                self.statusIndicatorView.showConfirmation()
            }
            self.present(share, animated: true, completion: nil)
            break
        case let .editParticipant(identifier):
            guard let stream = self.stream,
                let id = Int64(identifier),
                let participant = self.stream?.getParticipant(id) as? Participant else {
                    return
            }

            let actionSheet = UIAlertController()
            actionSheet.addAction(
                UIAlertAction(title: NSLocalizedString("Share Profile", comment: "Sheet action"), style: .default) {
                    _ in
                    let vc = Share.createShareSheetProfile(participant, anchor: self.membersTableView!, source: "ParticipantSheet")
                    self.present(vc, animated: true, completion: nil)
                    Answers.logCustomEvent(withName: "Participant Sheet Option", customAttributes: ["Option": "ShareOtherAccount"])
                })
            actionSheet.addAction(
                UIAlertAction(title: NSLocalizedString("Start New Conversation", comment: "Sheet action"), style: .default) {
                    _ in
                    self.performAction(Action.createStream(identifier: String(id)))
                })
            actionSheet.addAction(
                UIAlertAction(title: NSLocalizedString("Remove from Conversation", comment: "Sheet action"), style: .destructive) {
                    _ in
                    StreamService.instance.removeParticipants(streamId: stream.id, participants: [Intent.Participant(value: String(id))])
                    // Update in-memory stream.
                    // TODO: Do this in StreamService
                    stream.otherParticipants = stream.otherParticipants.filter { $0.id != id }
                    self.refresh()
                    self.membersTableView.scrollToTop(true)
                    Answers.logCustomEvent(withName: "Delete Member",
                        customAttributes: ["Type": participant.bot ? "Bot" : participant.active ? "Member" : "Invited"])
                })
            actionSheet.addAction(
                UIAlertAction(title: NSLocalizedString("Cancel", comment: "Sheet action"), style: .cancel, handler: nil))
            self.present(actionSheet, animated: true, completion: nil)
        default:
            return
        }
    }

    private func addStreamParticipants(_ contacts: [Contact]) {
        guard !contacts.isEmpty else {
            return
        }

        // Invite inactive contacts via SMS
        let inviteInactives: (Stream) -> Void = { stream in
            let inactives = contacts.filter { !$0.active }.map { $0.phoneNumber ?? ""}
            guard !inactives.isEmpty else {
                return
            }
            // If they are inactive, send them an invite SMS.
            inactives.forEach {
                guard let contact = ContactService.shared.contactIndex[$0] else {
                    return
                }
                ContactService.shared.sendInvite(toContact: contact, inviteToken: nil)
            }
        }

        var participants = contacts.map { Intent.Participant(value: $0.identifier) }

        // Create a new stream if it doesn't exist or if it is an active duo
        guard let stream = self.stream, !(stream.duo && stream.totalDuration > 0) else {
                self.statusIndicatorView.showLoading()
                self.view.isUserInteractionEnabled = false
                participants.append(
                    contentsOf: self.stream?.otherParticipants.map { Intent.Participant(value: String($0.id)) } ?? [])
                // There is no stream yet, so create it now
                StreamService.instance.getOrCreateStream(participants: participants, showInRecents: true, title: self.presetTitle) {
                    stream, error in
                    self.view.isUserInteractionEnabled = true
                    self.statusIndicatorView.hide()
                    guard let stream = stream else {
                        return
                    }
                    self.stream = stream
                    inviteInactives(stream)
                    Responder.userSelectedStream.emit(stream)
                }
                return
        }

        inviteInactives(stream)
        let addParticipants = {
            StreamService.instance.addParticipants(
                streamId: stream.id,
                participants: participants) { error in
                    self.statusIndicatorView.hide()
                    guard error == nil else {
                        // TODO: Error handling
                        return
                    }
            }

            // Update in memory stream
            // TODO: Do this in StreamService
            contacts.forEach {
                if let localParticipant = LocalParticipant(contact: $0) {
                    stream.otherParticipants.append(localParticipant)
                }
            }
            self.refresh()
        }

        // Mark stream as shareable and convert into group if it is a 1:1
        if stream.inviteToken == nil {
            StreamService.instance.setShareable(stream: stream, shareable: true, callback: nil)
        }

        addParticipants()
    }
}

class AddMemberCell : UITableViewCell {
    static let reuseIdentifier = "addMemberCell"

    @IBOutlet weak var iconLabel: UILabel!
    @IBOutlet weak var iconBackgroundImageView: UIImageView!
    @IBOutlet weak var addSourceLabel: UILabel!

    override func awakeFromNib() {
        self.separator = CALayer()
        self.separator.backgroundColor = UIColor.lightGray.cgColor
        self.layer.addSublayer(self.separator)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.separator.frame = CGRect(x: 0, y: self.frame.height - 1, width: self.frame.width, height: 0.5)
    }

    override func prepareForReuse() {
        self.iconLabel.text = nil
        self.iconLabel.font = UIFont.materialFontOfSize(22)
        self.iconBackgroundImageView.image = nil
        self.iconBackgroundImageView.backgroundColor = UIColor.clear
        self.iconBackgroundImageView.contentMode = .scaleAspectFill
        self.addSourceLabel.text = nil
    }

    private var separator: CALayer!
}

class QuickInviteCell: UITableViewCell {
    static let reuseIdentifier = "quickInviteCell"

    @IBOutlet weak var quickInviteView: QuickInviteView!

    override func awakeFromNib() {
        self.quickInviteView.closeButton.isHidden = true
    }
}

/// Protocol for stream participant sections
protocol ParticipantSection : Section {
    init(participants: [Participant])
    var participantContacts: [AccountContact] { get }
}

/// Default implementations of Participant sections
extension ParticipantSection {
    var rowHeight: CGFloat {
        return 70
    }

    var cellReuseIdentifier: String {
        return ContactCell.reuseIdentifier
    }

    var count: Int {
        return self.participantContacts.count
    }

    func populateCell(_ row: Int, cell: UITableViewCell) {
        guard let participantCell = cell as? ContactCell else {
            return
        }
        // Search results section.
        let contact = self.participantContacts[row]
        participantCell.contact = contact
        participantCell.mode = .inspection
        participantCell.accessoryType =
            Int64(contact.identifier) == BackendClient.instance.session?.id ? .none : .detailButton
    }

    func canSelect(_ row: Int) -> Bool {
        return Int64(self.participantContacts[row].identifier) != BackendClient.instance.session?.id
    }

    func handleAccessory(_ row: Int) -> Action {
        return .editParticipant(identifier: self.participantContacts[row].identifier)
    }
}

/// Active stream participants
class ActiveSection : ParticipantSection {
    var participantContacts: [AccountContact] = []

    var headerTitle: String? {
        return String.localizedStringWithFormat(
            NSLocalizedString("%d Member(s)", comment: "StreamDetails section title"),
            self.participantContacts.count)
    }

    func handleSelect(_ row: Int) -> Action {
        Answers.logCustomEvent(withName: "Group Member Selected", customAttributes: ["Type": "Active"])
        return .createStream(identifier: self.participantContacts[row].identifier)
    }

    required init(participants: [Participant]) {
        self.participantContacts.append(AccountContact(account: BackendClient.instance.session!))
        self.participantContacts.append(contentsOf: participants.map { AccountContact(account: $0) })
    }
}

/// Invited stream participants
class InvitedSection : ParticipantSection {
    var participantContacts: [AccountContact] = []

    var headerTitle: String? {
        return String.localizedStringWithFormat(
            NSLocalizedString("%d Invited", comment: "StreamDetails section title"),
            self.participantContacts.count)
    }

    required init(participants: [Participant]) {
        self.participantContacts = participants.map { AccountContact(account: $0) }
    }

    func handleSelect(_ row: Int) -> Action {
        guard let phoneNumber = self.participantContacts[row].phoneNumber else {
            return .nothing
        }
        Answers.logCustomEvent(withName: "Group Member Selected", customAttributes: ["Type": "Invited"])
        return .sms(phoneNumber: phoneNumber)
    }
}

/// Bot stream participants
class BotSection : ParticipantSection {
    var participantContacts: [AccountContact] = []

    var headerTitle: String? {
        return NSLocalizedString("Bots", comment: "StreamDetails section title")
    }

    required convenience init(participants: [Participant]) {
        self.init(participants: participants, stream: nil)
    }

    init(participants: [Participant], stream: Stream? = nil) {
        self.participantContacts = participants.map {
            var ownerName: String? = nil
            if let stream = stream, let ownerId = $0.ownerId {
                ownerName = stream.getParticipant(ownerId)?.displayName
            }
            return BotContact(account: $0, owner: ownerName)
        }
    }

    func handleSelect(_ row: Int) -> Action {
        Answers.logCustomEvent(withName: "Group Member Selected", customAttributes: ["Type": "Bot"])
        return .createStream(identifier: self.participantContacts[row].identifier)
    }
}

/// Add or Invite stream participants section
class AddMembersSection : Section {
    let count = 4
    let rowHeight: CGFloat = 70

    var cellReuseIdentifier: String {
        return AddMemberCell.reuseIdentifier
    }

    var headerTitle: String? {
        return NSLocalizedString("Add Members via...", comment: "StreamDetails section title")
    }

    func populateCell(_ row: Int, cell: UITableViewCell) {
        guard let addMemberCell = cell as? AddMemberCell else {
            return
        }

        // Populate addMemberCell
        switch row {
        case 0:
            addMemberCell.addSourceLabel.text = NSLocalizedString("Address Book", comment: "Add member option")
            addMemberCell.iconBackgroundImageView.image = UIImage(named: "addressBookBackground")
            addMemberCell.iconLabel.text = "contacts"
        case 1:
            addMemberCell.addSourceLabel.text = NSLocalizedString("Handle", comment: "Add member option")
            addMemberCell.iconBackgroundImageView.image = UIImage(named: "handleBackground")
            addMemberCell.iconLabel.font = UIFont.rogerFontOfSize(21)
            addMemberCell.iconLabel.text = "@"
        case 2:
            addMemberCell.addSourceLabel.text = NSLocalizedString("Share Conversation Link", comment: "Add member option")
            addMemberCell.iconBackgroundImageView.image = UIImage(named: "shareLinkBackground")
            addMemberCell.iconLabel.text = "link"
        default:
            addMemberCell.addSourceLabel.text = NSLocalizedString("Bots", comment: "Add member option")
            addMemberCell.iconBackgroundImageView.image = UIImage(named: "botsBackground")
            addMemberCell.iconBackgroundImageView.contentMode = .center
            addMemberCell.iconBackgroundImageView.backgroundColor = UIColor.black
            addMemberCell.iconLabel.text = nil
        }
    }

    func handleSelect(_ row: Int) -> Action {
        switch row {
        case 0:
            Answers.logCustomEvent(withName: "Add Group Member", customAttributes: ["Option": "AddressBook"])
            return .addFromAddressBook
        case 1:
            Answers.logCustomEvent(withName: "Add Group Member", customAttributes: ["Option": "Handle"])
            return .searchHandle
        case 2:
            Answers.logCustomEvent(withName: "Add Group Member", customAttributes: ["Option": "Share"])
            return .shareStreamLink
        default:
            Answers.logCustomEvent(withName: "Add Group Member", customAttributes: ["Option": "Bots"])
            return .addBots
        }
    }
}

class QuickInviteSection : Section {
    let count = 1
    let headerTitle: String? = nil
    let rowHeight: CGFloat = 200

    required init(delegate: QuickInviteDelegate) {
        self.quickInviteDelegate = delegate
    }

    var cellReuseIdentifier: String {
        return "quickInviteCell"
    }

    func populateCell(_ row: Int, cell: UITableViewCell) {
        guard let quickInviteCell = cell as? QuickInviteCell else {
            return
        }

        quickInviteCell.quickInviteView.delegate = self.quickInviteDelegate
    }

    func canSelect(_ row: Int) -> Bool {
        return false
    }

    private let quickInviteDelegate: QuickInviteDelegate
}
