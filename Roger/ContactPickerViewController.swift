import Crashlytics
import FBSDKMessengerShareKit
import MessageUI

protocol ContactPickerDelegate {
    func didFinishPickingContacts(_ picker: ContactPickerViewController, contacts: [Contact])
}

enum SelectionMode { case conversation, addressBook, search }

class ContactPickerViewController:
    UIViewController,
    UITableViewDataSource,
    UITableViewDelegate,
    UITextFieldDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate,
    ServiceManager {

    @IBOutlet weak var accessibilityDoneButton: UIButton!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var contactsTableView: UITableView!
    @IBOutlet weak var conversationBarBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var conversationBarView: UIView!
    @IBOutlet weak var conversationButton: UIButton!
    @IBOutlet weak var conversationLoader: UIActivityIndicatorView!
    @IBOutlet weak var menuBarView: UIView!
    @IBOutlet weak var searchBarHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var searchField: MaterialTextField!
    @IBOutlet weak var selectedContactsCollectionView: UICollectionView!
    @IBOutlet weak var titleLabel: UILabel!

    var mode: SelectionMode = .conversation
    var delegate: ContactPickerDelegate!
    var unselectableContacts: [AccountContact]?

    var loading: Bool = false {
        didSet {
            self.conversationButton.isHidden = self.loading
            self.conversationLoader.isHidden = !self.loading
            self.contactsTableView.reloadData()
        }
    }
    var services: [Service] {
        return StreamService.instance.services
    }

    static func create(_ mode: SelectionMode, delegate: ContactPickerDelegate, unselectable: [AccountContact]? = nil) -> ContactPickerViewController {
        let picker = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "ContactPicker") as! ContactPickerViewController
        picker.mode = mode
        picker.delegate = delegate
        picker.unselectableContacts = unselectable
        return picker
    }

    override func viewDidLoad() {
        self.contactsTableView.register(UINib(nibName: "ContactCell", bundle: nil), forCellReuseIdentifier: ContactCell.reuseIdentifier)
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        self.view.addSubview(self.statusIndicatorView)

        // Set up the table view.
        self.contactsTableView.keyboardDismissMode = .onDrag
        self.contactsTableView.tableFooterView = UIView(frame: CGRect.zero)
        self.contactsTableView.dataSource = self
        self.contactsTableView.delegate = self
        self.contactsTableView.allowsSelection = true
        self.contactsTableView.allowsMultipleSelection = false
        self.contactsTableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))
        self.contactsTableView.reloadData()

        // Set up selected contacts bottom bar.
        self.selectedContactsCollectionView.delegate = self
        self.selectedContactsCollectionView.dataSource = self
        self.selectedContactsCollectionView.isAccessibilityElement = true
        self.selectedContactsCollectionView.accessibilityLabel = NSLocalizedString("Selected People Bar", comment: "Selected people preview bar")

        // Set up search field.
        self.searchField.delegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(ContactPickerViewController.handleKeyboardShown(_:)), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ContactPickerViewController.handleKeyboardHidden), name: NSNotification.Name.UIKeyboardWillHide, object: nil)

        self.searchField.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Remove keyboard
        self.view.endEditing(true)
        ContactService.shared.fetchingActiveContacts.removeListener(self)
        ContactService.shared.contactsChanged.removeListener(self)
        StreamService.instance.servicesChanged.removeListener(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        self.refreshContactsFromAddressBook()
        self.refreshRecentContacts()

        ContactService.shared.fetchingActiveContacts.addListener(self, method: ContactPickerViewController.handleFetchingActiveContacts)
        ContactService.shared.contactsChanged.addListener(self, method: ContactPickerViewController.refreshContactsFromAddressBook)
        StreamService.instance.servicesChanged.addListener(self, method: ContactPickerViewController.refreshServices)

        self.setupMode()

        if !SettingsManager.didUnderstandConversations && self.mode == .conversation {
            SettingsManager.didUnderstandConversations = true
            let alert = self.storyboard?.instantiateViewController(withIdentifier: "AlertCard") as! AlertCardController
            alert.icon = UIImage(named: "conversationsCard")
            alert.mainTitle = NSLocalizedString("Conversations", comment: "Tutorial popup title")
            alert.subtitle = NSLocalizedString("Start individual or group conversations with your friends.", comment: "Tutorial popup text")
            alert.modalTransitionStyle = .crossDissolve
            alert.modalPresentationStyle = .overFullScreen
            self.present(alert, animated: true, completion: nil)
        }
    }

    override var prefersStatusBarHidden : Bool {
        return true
    }

    func filterContacts() {
        // Reset search cell
        self.searchContact = nil

        let filter = self.searchField.text!.lowercased()
        if filter == "" {
            self.filteredAddressBook = self.addressBookContacts
        } else {
            // Kick off a search for any profile matching this identifier
            self.isSearching = true
            Intent.getProfile(identifier: filter).perform(BackendClient.instance) { result in
                self.isSearching = false

                // Ensure we are still searching (and that there is a valid row to reload)
                guard filter == self.searchField.text?.lowercased() &&
                    self.contactsTableView.numberOfRows(inSection: Section.Search) > 0 else {
                    return
                }

                var contact: ProfileContact?
                if let data = result.data, let profile = Profile(data) {
                    contact = ProfileContact(profile: profile)
                }

                self.searchContact = contact
                UIView.performWithoutAnimation {
                    self.contactsTableView.reloadRows(at: [IndexPath(item: 0, section: Section.Search)], with: .none)
                }
            }

            // Search locally
            let match: (String?) -> Bool = { text in
                return text?.lowercased().range(of: filter) != nil
            }

            self.filteredAddressBook = self.addressBookContacts.filter {
                // Match name or identifier to the search term.
                guard match($0.name) || match($0.identifier) else {
                    return false
                }
                return true
            }
        }

        self.contactsTableView.reloadData()
    }

    func loadAddressBook() {
        // TODO: Figure out a better system for detecting if the user has been authenticated.
        switch ContactService.shared.authorizationStatus {
        case .notDetermined:
            // Show challenge view controller if we have never asked for permission.
            ContactService.shared.importContacts(requestAccess: true)
        case .denied:
            let alert = UIAlertController(
                title: NSLocalizedString("Cannot access Contacts", comment: "Alert title"),
                message: NSLocalizedString("Permission to access your Contacts list must be granted via Settings->Roger.", comment: "Alert text"),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Okay", comment: "Alert action"), style: .default, handler: {
                (action: UIAlertAction!) -> Void in
                UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
                Answers.logCustomEvent(withName: "User Sent To System Preferences", customAttributes: ["Reason": "AddressBook", "Source": "Add Contact"])
            }))
            self.present(alert, animated: true, completion: nil)
            Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "ContactPicker", "Type": "AddressBookPermissionsDenied"])
        case .restricted:
            let alert = UIAlertController(
                title: NSLocalizedString("Cannot access Contacts", comment: "Alert title"),
                message: NSLocalizedString("Your Contacts list has been restricted.", comment: "Alert text"),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Okay", comment: "Alert action"), style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
            Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "ContactPicker", "Type": "AddressBookPermissionsRestricted"])
        default:
            print("Should not be seeing this: AddressBookPermission already granted.")
        }
    }

    func handleKeyboardShown(_ notification: Foundation.Notification) {
        let value = (notification as NSNotification).userInfo![UIKeyboardFrameEndUserInfoKey]!
        let keyboardFrame = self.view.convert((value as AnyObject).cgRectValue, from: nil)

        UIView.animate(withDuration: 1, delay: 0, options: .curveLinear, animations: {
            self.conversationBarBottomConstraint.constant = keyboardFrame.height
            self.view.layoutSubviews()
            }, completion: nil)
    }

    func handleKeyboardHidden() {
        UIView.animate(withDuration: 1, delay: 0, options: .curveLinear, animations: {
            self.conversationBarBottomConstraint.constant = 0
            self.view.layoutSubviews()
            }, completion: nil)
    }

    // MARK: - ServiceManager

    func serviceLongPressed() {
        // TODO
    }

    func serviceTapped(_ index: Int) {
        let service = self.services[index]
        // TODO: Remove this hack to call into the feedback logic.
        if service.identifier == "feedback" {
            self.delegate?.didFinishPickingContacts(self, contacts: [IdentifierContact(identifier: service.identifier)])
            return
        }
        // TODO: Remove this hack to call into the voicemail logic.
        if service.identifier == "voicemail" {
            let voicemail = VoicemailStream(data: ["id": NSNumber(value: 0), "chunks": NSArray(), "others": NSArray()])!
            guard case let .showAlert(title, message, action) = voicemail.instructionsActionTapped() else {
                return
            }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: action, style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
            return
        }
        let pickService = {
            if let url = service.connectURL, url.absoluteString.contains("ifttt") {
                Intent.pingIFTTT().perform(BackendClient.instance)
            }
            guard service.accountId != nil else {
                self.delegate?.didFinishPickingContacts(self, contacts: [])
                return
            }
            self.delegate?.didFinishPickingContacts(self, contacts: [ServiceContact(service: service)])
        }
        // Show connect UI in browser if the service is not connected.
        guard service.connected else {
            let browser = self.storyboard!.instantiateViewController(withIdentifier: "EmbeddedBrowser") as! EmbeddedBrowserController
            browser.urlToLoad = service.connectURL
            if let pattern = service.finishPattern {
                browser.finishPattern = pattern
            }
            browser.pageTitle = String.localizedStringWithFormat(
                NSLocalizedString("Connect to %@", comment: "Alert text"),
                service.title)
            browser.callback = { didFinish in
                guard didFinish else {
                    return
                }
                // Immediately exit and select the appropriate service stream.
                pickService()
            }
            self.present(browser, animated: true, completion: nil)
            Answers.logCustomEvent(withName: "Connect Service Shown", customAttributes: ["Source": "ContactPicker"])
            return
        }
        pickService()
    }

    // MARK: - Actions

    @IBAction func backTapped(_ sender: AnyObject) {
        _ = self.navigationController?.popViewController(animated: true)
    }

    @IBAction func accessibilityDoneButtonTapped(_ sender: AnyObject) {
        self.navigationController?.popToRootViewControllerModal()
    }

    /// Send selected content or start a new conversation
    @IBAction func conversationButtonTapped(_ sender: AnyObject) {
        self.view.endEditing(true)
        self.delegate.didFinishPickingContacts(self, contacts: self.selectedContacts)
    }

    @IBAction func shareHandleTapped(_ sender: AnyObject) {
        let vc = Share.createShareSheetOwnProfile(self.searchField, source: "ShareHandle")
        self.present(vc, animated: true, completion: nil)
    }

    @IBAction func inviteFriendsTapped(_ sender: AnyObject) {
        let vc = InviteViewController()
        self.present(vc, animated: true, completion: nil)
    }

    @IBAction func searchFieldEditingChanged(_ sender: AnyObject) {
        self.searchTimer?.invalidate()
        self.searchTimer =
            Timer.scheduledTimer(timeInterval: 0.1,
                                                   target: self,
                                                   selector: #selector(ContactPickerViewController.filterContacts),
                                                   userInfo: nil,
                                                   repeats: false)
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard (indexPath as NSIndexPath).section != Section.People else {
            return
        }

        guard let cell = tableView.cellForRow(at: indexPath) as? ContactCell else {
            return
        }

        cell.flash()
        guard let selectedIndex = self.selectedContacts.index(where: { $0.identifier == cell.contact?.identifier }) else {
            return
        }
        self.selectedContacts.remove(at: selectedIndex)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch (indexPath as NSIndexPath).section {
        case Section.People:
            tableView.deselectRow(at: indexPath, animated: true)
            if (indexPath as NSIndexPath).row == 0 {
                let vc = self.storyboard?.instantiateViewController(withIdentifier: "EditGroup")
                self.navigationController?.pushViewControllerModal(vc!)
                Answers.logCustomEvent(withName: "Create Group Tapped", customAttributes: ["Source": "ContactPicker"])
                return
            }
            self.inviteFriendsTapped(self)
            return
        default:
            break
        }

        let cell = tableView.cellForRow(at: indexPath) as! ContactCell
        cell.flash()

        // If there is text in the search field, select it for easy deletion.
        if self.contactsTableView.allowsMultipleSelection && !(self.searchField.text?.isEmpty ?? true) {
            self.searchField.selectAll(nil)
        }

        let contact = cell.contact!
        // Log selection
        switch (indexPath as NSIndexPath).section {
        case Section.Recents:
            Answers.logCustomEvent(withName: "Contact Selected", customAttributes: ["Type": "RecentStream", "Index": (indexPath as NSIndexPath).row])
        case Section.AddressBook:
            Answers.logCustomEvent(withName: "Contact Selected", customAttributes: ["Type": "AddressBook", "Index": (indexPath as NSIndexPath).row])
        case Section.Search:
            guard !self.selectedContacts.contains(where: { $0.identifier == contact.identifier }) else {
                // Already selected.
                self.contactsTableView.deselectRow(at: indexPath, animated: false)
                return
            }
            Answers.logCustomEvent(withName: "Contact Selected", customAttributes: ["Type": "Manual", "Index": (indexPath as NSIndexPath).row])
        default:
            // Unknown section.
            print("WARNING: Selected contact in unknown section")
            return
        }

        if self.mode == .conversation {
            cell.loader.isHidden = false
            tableView.allowsSelection = false
            self.delegate?.didFinishPickingContacts(self, contacts: [contact])
            return
        } else if self.mode == .search {
            self.selectedContacts.append(contact)
            self.conversationButtonTapped(self)
            return
        }

        // Prevent group selection of special contacts.
        // TODO: Add more special streams here
        guard !(self.mode == .addressBook && (contact as? StreamContact)?.stream is AlexaStream) else {
            self.contactsTableView.deselectRow(at: indexPath, animated: false)
            let alert = UIAlertController(
                title: NSLocalizedString("Oops!", comment: "Alert title"),
                message: String.localizedStringWithFormat(
                    NSLocalizedString("%@ cannot be added to conversations.", comment: "Alert text"),
                    contact.name),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert action"), style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
            return
        }

        self.selectedContacts.append(contact)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch (indexPath as NSIndexPath).section {
        case Section.Permissions:
            return 140
        case Section.Services:
            return 100
        case Section.InvitePeople:
            return 130
        default:
            return 70
        }
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch (indexPath as NSIndexPath).section {
        case Section.Services, Section.Permissions, Section.InvitePeople:
            return false
        case Section.Search:
            let cell = tableView.cellForRow(at: indexPath) as! ContactCell
            return cell.selectable && self.searchContact != nil
        case Section.AddressBook:
            // Allow selection only if the contact is not already a participant in the current group (if any)
            let cell = tableView.cellForRow(at: indexPath) as! ContactCell
            return cell.selectable
        default:
            return true
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if self.mode == .search {
            return section == Section.Search ? 40 : CGFloat.leastNormalMagnitude
        }

        let search = !(self.searchField.text?.isEmpty ?? true)
        switch section {
        case Section.Recents:
            return self.filteredRecents.count == 0 ? CGFloat.leastNormalMagnitude : 40
        case Section.Services:
            return search || self.mode == .addressBook || self.services.count == 0 ? CGFloat.leastNormalMagnitude  : 40
        case Section.People:
            return self.filteredAddressBook.count == 0 ? CGFloat.leastNormalMagnitude : 40
        case Section.Search:
            return search && self.mode != .addressBook ? 40 : CGFloat.leastNormalMagnitude
        case Section.Permissions:
            return ContactService.shared.authorized ? CGFloat.leastNormalMagnitude : 40
        default:
            return CGFloat.leastNormalMagnitude
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return CGFloat.leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        // TODO: Refactor logic to be more modular
        let search = !(self.searchField.text?.isEmpty ?? true)
        if self.mode == .search && section != Section.Search {
            return nil
        } else if section == Section.Permissions && ContactService.shared.authorizationStatus == .authorized ||
            (section == Section.Services && (search || self.mode == .addressBook || self.services.count == 0)) ||
            (section == Section.Recents && self.filteredRecents.count == 0) ||
            (section == Section.People && self.filteredAddressBook.count == 0) ||
            (section == Section.Search && (!search || self.mode == .addressBook)) {
            return nil
        }

        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 20))
        let sectionLabel = UILabel(frame: CGRect(x: 0, y: 0, width: headerView.bounds.width - 32, height: 20))
        sectionLabel.center = headerView.center
        sectionLabel.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        sectionLabel.font = UIFont.rogerFontOfSize(12)
        sectionLabel.textColor = UIColor.lightGray
        let label: String
        switch section {
        case Section.Services:
            label = NSLocalizedString("Services", comment: "Contact picker services section")
        case Section.Recents:
            label = NSLocalizedString("Recents", comment: "Contact picker section")
        case Section.People, Section.Permissions:
            label = NSLocalizedString("People", comment: "Contact picker section")
        case Section.Search:
            label = NSLocalizedString("Search", comment: "Contact picker section")
        default:
            label = ""
        }
        sectionLabel.accessibilityLabel = label
        sectionLabel.text = label.uppercased()
        headerView.addSubview(sectionLabel)
        return headerView
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return 7
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = (indexPath as NSIndexPath).section
        let row = (indexPath as NSIndexPath).row

        if section == Section.Permissions {
            // Big cell asking for permissions to the address book.
            let permissionCell = tableView.dequeueReusableCell(withIdentifier: ContactsPermissionCell.reuseIdentifier, for: indexPath) as! ContactsPermissionCell
            permissionCell.requestPermissionButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ContactPickerViewController.loadAddressBook)))
            return permissionCell
        } else if section == Section.People {
            return row == 0 ?
            tableView.dequeueReusableCell(withIdentifier: "createGroupCell", for: indexPath) :
            tableView.dequeueReusableCell(withIdentifier: "inviteFriendCell", for: indexPath)
        } else if section == Section.Services {
            let servicesCell = tableView.dequeueReusableCell(withIdentifier: ServicesCell.reuseIdentifier, for: indexPath) as! ServicesCell
            servicesCell.servicesCollectionView.serviceManager = self
            return servicesCell
        } else if section == Section.InvitePeople {
            return tableView.dequeueReusableCell(withIdentifier: "shareHandleCell", for: indexPath)
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: ContactCell.reuseIdentifier, for: indexPath) as! ContactCell
        cell.mode = .selection

        // Search results section.
        let contact: Contact
        if section == Section.Search {
            guard let searchResult = self.searchContact else {
                cell.contact = IdentifierContact(identifier: self.searchField.text!)
                cell.loader.isHidden = !self.isSearching
                return cell
            }
            contact = searchResult
            cell.selectable = !(self.unselectableContacts?.contains(where: { $0 == searchResult }) ?? false)
        } else if section == Section.Recents {
            contact = self.filteredRecents[row]
        } else {
            // Default to address book section.
            contact = self.filteredAddressBook[row]
            // Allow selection only if the contact is not already a participant in the current group (if any)
            cell.selectable =
                !(self.unselectableContacts?.contains(where: { $0 == contact as! AddressBookContact }) ?? false)
        }

        // Assign the appropariate contact for the cell
        cell.contact = contact

        // Set selection status.
        if self.selectedContacts.contains(where: { $0.identifier == contact.identifier }) {
            self.contactsTableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        }

        return cell
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let search = !(self.searchField.text?.isEmpty ?? true)
        // Existing streams should be available even without contacts permissions.
        switch section {
        case Section.Services:
            return search || self.mode != .conversation || self.services.count == 0 ? 0 : 1
        case Section.Recents:
            return self.filteredRecents.count
        case Section.Permissions:
            return (!ContactService.shared.authorized || SettingsManager.userIdentifier == nil) && self.mode != .search ? 1 : 0
        case Section.People:
            // TODO: Bring back mass inviter
            return !search && self.mode == .conversation ? 1 : 0
        case Section.AddressBook:
            return SettingsManager.userIdentifier == nil || self.mode == .search ? 0 : self.filteredAddressBook.count
        case Section.Search:
            return search && (self.mode == .conversation || self.mode == .search) ? 1 : 0
        case Section.InvitePeople:
            return self.mode == .addressBook ? 0 : 1
        default:
            return 0
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }

    // MARK: - Private

    fileprivate var statusIndicatorView: StatusIndicatorView!

    /// Contacts that have been interacted with recently.
    fileprivate var recentContacts = [Contact]() {
        didSet {
            self.refreshSelectedContacts()
            self.filterContacts()
        }
    }
    fileprivate var filteredRecents = [Contact]()

    /// Contacts from the address book.
    fileprivate var addressBookContacts = [Contact]() {
        didSet {
            self.refreshSelectedContacts()
            self.filterContacts()
        }
    }
    fileprivate var filteredAddressBook = [Contact]()

    /// Currently selected contacts.
    fileprivate var selectedContacts = [Contact]() {
        didSet {
            self.updateSelectionUI()
        }
    }   

    /// Search result contact
    fileprivate var searchContact: ProfileContact?

    fileprivate var searchTimer: Timer?
    fileprivate var isSearching: Bool = false

    fileprivate struct Section {
        static let Services = 0
        static let Recents = 1
        static let People = 2
        static let Permissions = 3
        static let AddressBook = 4
        static let Search = 5
        static let InvitePeople = 6
    }

    fileprivate func refreshSelectedContacts() {
        guard self.selectedContacts.count > 0 else {
            return
        }

        var selected = [Contact]()
        defer {
            self.selectedContacts = selected
            self.filterContacts()
        }

        // Refresh selection for recents.
        self.recentContacts.forEach { contact in
            if self.selectedContacts.contains(where: { $0.identifier == contact.identifier }) {
                selected.append(contact)
            }
        }

        // Check whether there are any more selected contacts to refresh.
        guard self.selectedContacts.count > selected.count else {
            return
        }

        // Refresh selection for address book contacts.
        self.addressBookContacts.forEach { contact in
            if self.selectedContacts.contains(where: { $0.identifier == contact.identifier }) {
                selected.append(contact)
            }
        }
    }

    fileprivate func refreshRecentContacts() {
        self.recentContacts = StreamService.instance.streams.values.flatMap {
            // TODO: Figure out a better way to exclude certain streams.
            if $0 is AlexaStream {
                return nil
            }
            let contact = StreamContact(stream: $0)
            guard contact.active else {
                return nil
            }
            return contact
        }
    }

    fileprivate func refreshContactsFromAddressBook() {
        var contacts = [Contact]()
        var activesCount = 0
        for contact in ContactService.shared.contacts {
            let image = contact.imageData.flatMap { UIImage(data: $0) }
            // Attempt to find one or more accounts for this contact's identifiers.
            var foundAccountIds = Set<Int64>()
            for (identifier, _) in contact.identifierToLabel {
                guard
                    let account = ContactService.shared.accountIndex[identifier],
                    account.active,
                    !foundAccountIds.contains(account.id)
                    else { continue }
                contacts.append(AddressBookContact(identifier: String(account.id), name: contact.name, account: account, image: image))
                activesCount += 1
                foundAccountIds.insert(account.id)
            }
            if foundAccountIds.count > 0 {
                continue
            }
            // Since no active account was found, print all the contact details.
            for (identifier, label) in contact.identifierToLabel {
                // Exclude anything that is not a phone number.
                if identifier.characters.first != "+" {
                    continue
                }
                let cleanLabel = label.trimmingCharacters(in: CharacterSet.letters.inverted)
                contacts.append(AddressBookContact(identifier: identifier, name: contact.name, image: image, label: cleanLabel))
            }
        }
        self.addressBookContacts = contacts
    }

    fileprivate func refreshServices() {
        self.contactsTableView.reloadData()
    }

    fileprivate func handleFetchingActiveContacts(_ isFetching: Bool) {
        guard !isFetching else {
            self.statusIndicatorView.showLoading()
            return
        }
        self.statusIndicatorView.hide()
    }

    fileprivate func updateSelectionUI() {
        // Append all selected contacst to the accessibility label for the selection bar
        let accessibilityHint = self.selectedContacts.count == 0 ?
            NSLocalizedString("No selected people", comment: "Selected contacts bar accessibility zero contacts") :
            NSLocalizedString("Selected people are", comment: "Selected contacts bar accessibility intro") +
            self.selectedContacts.map({ $0.name }).joined(separator: ", ")
        self.selectedContactsCollectionView.accessibilityHint = accessibilityHint
        self.accessibilityDoneButton.accessibilityHint = accessibilityHint

        // Reload selection bar UI and scroll to the end
        self.selectedContactsCollectionView.reloadData()
        if self.selectedContacts.count > 0 {
            self.selectedContactsCollectionView.scrollToItem(
                at: IndexPath(item: self.selectedContacts.count - 1, section: 0), at: .centeredHorizontally, animated: true)

            self.conversationButton.pulse()
        }
    }

    fileprivate func setupMode() {
        UIView.animate(withDuration: 0.2, animations: {
            self.conversationBarView.transform = CGAffineTransform.identity.translatedBy(x: 0.0, y: self.mode == .conversation ? self.conversationBarView.frame.height : 0)
        })

        switch self.mode {
        case .conversation:
            self.titleLabel.text = NSLocalizedString("Conversation", comment: "Contact picker title")
            self.selectedContacts = []
        case .addressBook:
            self.loadAddressBook()
            self.conversationBarView.isHidden = false
            self.titleLabel.text = NSLocalizedString("Add Members", comment: "Contact picker title")
            self.contactsTableView.allowsMultipleSelection = true
            if UIAccessibilityIsVoiceOverRunning() {
                self.accessibilityDoneButton.isHidden = false
            }
        case .search:
            self.titleLabel.text = NSLocalizedString("Search", comment: "Contact picker title")
            if UIAccessibilityIsVoiceOverRunning() {
                self.accessibilityDoneButton.isHidden = false
            }
            break
        }

        self.contactsTableView.reloadData()
    }
}

extension ContactPickerViewController : UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.selectedContacts.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SelectedContactCell.reuseIdentifier, for: indexPath) as! SelectedContactCell
        cell.nameLabel.text = self.getTextForSelectedContact((indexPath as NSIndexPath).row)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let text = self.getTextForSelectedContact((indexPath as NSIndexPath).row)
        let textSize = text.size(attributes: [NSFontAttributeName: UIFont.rogerFontOfSize(16)])
        return CGSize(width: textSize.width, height: self.conversationBarView.frame.height)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        self.searchField.text = self.selectedContacts[(indexPath as NSIndexPath).row].name
        self.searchField.sendActions(for: .editingChanged)
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionElementKindSectionFooter {
            return collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionElementKindSectionFooter, withReuseIdentifier: "addMoreFooter", for: indexPath)
        }

        return collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionElementKindSectionHeader, withReuseIdentifier: "selectPeopleHeader", for: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        return self.selectedContacts.count > 0 ? CGSize.zero : CGSize(width: 180, height: collectionView.frame.height)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
        return self.selectedContacts.count > 0 ? CGSize(width: 50, height: collectionView.frame.height) : CGSize.zero
    }

    fileprivate func getTextForSelectedContact(_ index: Int) -> String {
        return self.selectedContacts[index].shortName + (index == self.selectedContacts.count - 1 ? "" : ",")
    }
}

class ServicesCell : UITableViewCell {
    static let reuseIdentifier = "servicesCell"

    @IBOutlet weak var servicesCollectionView: ServicesCollectionView!
}

class SelectedContactCell : UICollectionViewCell {
    static let reuseIdentifier = "selectedContactCell"

    @IBOutlet weak var nameLabel: UILabel!
}

class ContactsPermissionCell: SeparatorCell {
    static let reuseIdentifier = "contactsPermissionCell"

    weak var requestPermissionButton: MaterialButton!

    @IBOutlet weak var contactsIconView: UIView!
    @IBOutlet weak var descriptionLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        switch ContactService.shared.authorizationStatus {
        case .denied, .restricted:
            self.descriptionLabel.text = NSLocalizedString("Enable access to your contacts in settings", comment: "Contacts permission supercell description")
            self.requestPermissionButton.setTitle(
                NSLocalizedString("SETTINGS", comment: "Contacts permission supercell action"),
                for: .normal)
        default:
            self.requestPermissionButton.setTitle(
                NSLocalizedString("ACCESS", comment: "Contacts permission supercell action"),
                for: .normal)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.contactsIconView.layer.borderColor = UIColor.rogerBlue?.cgColor
    }
}

class CreateGroupCell: SeparatorCell {
    static let reuseIdentifier = "createGroupCell"

    @IBOutlet weak var plusLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.plusLabel.layer.borderColor = UIColor.rogerBlue?.cgColor
        self.plusLabel.layer.borderWidth = 1
    }
}

class SeparatorCell: UITableViewCell {
    override func awakeFromNib() {
        self.separator = CALayer()
        self.separator.backgroundColor = UIColor.lightGray.cgColor
        self.layer.addSublayer(self.separator)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.separator.frame = CGRect(x: 16, y: self.frame.height - 1, width: self.frame.width - 32, height: 0.5)
    }

    fileprivate var separator: CALayer!
}

class ShareHandleCell: UITableViewCell {
    @IBOutlet weak var handleLabel: UILabel!

    override func awakeFromNib() {
        guard let username = BackendClient.instance.session?.username else {
            return
        }
        self.handleLabel.text = String.localizedStringWithFormat(
            NSLocalizedString("Your handle is: @%@", comment: "Share handle label"), username)
    }
}
