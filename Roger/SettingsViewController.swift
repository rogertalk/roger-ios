import CoreLocation
import Crashlytics
import libPhoneNumber_iOS
import MessageUI
import SafariServices

class WeatherSwitch: UISwitch {
    @IBOutlet weak var scrollView: UIScrollView!

    override func accessibilityElementDidBecomeFocused() {
        // TODO: This is a hack because the scroll view is bugged.
        let screen = UIScreen.main
        let point = self.convert(self.center, to: self.scrollView)
        self.scrollView.contentOffset = CGPoint(x: 0, y: point.y - screen.bounds.height / 2)
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil)
    }
}

class ServiceTableViewCell: UITableViewCell {
    static let reuseIdentifier = "serviceCell"

    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!

    override func prepareForReuse() {
        self.descriptionLabel.text = nil
        self.iconImageView.image = nil
        self.titleLabel.text = nil
    }
}

class ServicesTableView: UITableView, UITableViewDataSource, UITableViewDelegate {
    var serviceManager: ServiceManager!

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.dataSource = self
        self.delegate = self
        self.delaysContentTouches = false
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.deselectRow(at: indexPath, animated: true)
        self.serviceManager.serviceTapped((indexPath as NSIndexPath).row)
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.serviceManager.services.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let service = self.serviceManager.services[(indexPath as NSIndexPath).row]

        let cell = tableView.dequeueReusableCell(withIdentifier: ServiceTableViewCell.reuseIdentifier, for: indexPath) as! ServiceTableViewCell
        cell.descriptionLabel.text = service.description
        cell.titleLabel.text = service.title
        cell.iconImageView.clipsToBounds = true
        cell.iconImageView.layer.cornerRadius = cell.iconImageView.bounds.width / 2
        if let imageURL = service.imageURL {
            cell.iconImageView.af_setImage(withURL: imageURL)
        }
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = service.title
        cell.accessibilityHint = service.description
        return cell
    }
}

class SettingsViewController: UIViewController, UIScrollViewDelegate,
    UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate,
    UIImagePickerControllerDelegate, UINavigationControllerDelegate,
    MFMailComposeViewControllerDelegate, CLLocationManagerDelegate,
    ServiceManager {

    @IBOutlet weak var accountsTableView: UITableView!
    @IBOutlet weak var accountsTableViewHeight: NSLayoutConstraint!
    @IBOutlet weak var appVersionButton: UIButton!
    @IBOutlet weak var avatarView: AvatarView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var displayNameField: UITextField!
    @IBOutlet weak var displayNameLabelBottomSpacing: NSLayoutConstraint!
    @IBOutlet weak var headerHeight: NSLayoutConstraint!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var notificationsViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var servicesTableView: ServicesTableView!
    @IBOutlet weak var servicesTableViewHeight: NSLayoutConstraint!
    @IBOutlet weak var turnOnNotificationsButton: UIButton!
    @IBOutlet weak var usernameField: UITextField!
    @IBOutlet weak var usernameHintLabel: UILabel!
    @IBOutlet weak var usernameLabel: UILabel!
    @IBOutlet weak var weatherSwitch: UISwitch!
    @IBOutlet weak var autoplaySwitch: UISwitch!

    var safariController: UIViewController?

    var services: [Service] {
        return StreamService.instance.services
    }

    func dismissKeyboard() {
        self.view.endEditing(true)
    }

    func editHeaderInfo() {
        if self.displayNameField.isFirstResponder {
            self.dismissKeyboard()
            return
        }

        if self.headerHeight.constant < 100 {
            self.toggleHeaderView(true)
        } else {
            let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Choose Photo", comment: "Sheet action"), style: .default, handler: { action in
                self.imagePicker.sourceType = .photoLibrary
                self.present(self.imagePicker, animated: true, completion: {
                    sheet.dismiss(animated: true, completion: nil)
                })
                Answers.logCustomEvent(withName: "Edit Profile Sheet Option", customAttributes: ["Option": "ChoosePhoto"])
            }))
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Take New Photo", comment: "Sheet action"), style: .default, handler: { action in
                self.imagePicker.sourceType = .camera
                self.imagePicker.cameraCaptureMode = .photo
                self.present(self.imagePicker, animated: true, completion: {
                    sheet.dismiss(animated: true, completion: nil)
                })
                Answers.logCustomEvent(withName: "Edit Profile Sheet Option", customAttributes: ["Option": "TakePhoto"])
            }))
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Edit Name", comment: "Sheet action"), style: .default, handler: { action in
                self.displayNameField.isUserInteractionEnabled = true
                self.displayNameField.becomeFirstResponder()
                Answers.logCustomEvent(withName: "Edit Profile Sheet Option", customAttributes: ["Option": "EditName"])
            }))
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Sheet action"), style: .cancel, handler: { action in
                sheet.dismiss(animated: true, completion: nil)
                Answers.logCustomEvent(withName: "Edit Profile Sheet Option", customAttributes: ["Option": "Cancel"])
            }))
            // Provide an anchor for iPad.
            if let popoverPresenter = sheet.popoverPresentationController {
                popoverPresenter.sourceView = self.headerView
                popoverPresenter.sourceRect = self.headerView.bounds.insetBy(dx: 0, dy: 5)
            }
            self.present(sheet, animated: true, completion: nil)
            Answers.logCustomEvent(withName: "Edit Profile Sheet Shown", customAttributes: nil)
        }
    }

    // MARK: - UIViewController

    required init?(coder: NSCoder) {
        // Setup phone number formatter
        self.phoneNumberUtil = NBPhoneNumberUtil()
        super.init(coder: coder)
    }

    override var preferredStatusBarStyle : UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        self.accountsTableView.delegate = self
        self.accountsTableView.dataSource = self

        self.servicesTableView.serviceManager = self

        self.avatarView.hasDropShadow = false
        self.avatarView.setText(NSLocalizedString("ADD\nPHOTO", comment: "Text on top of avatar with no photo in Settings"))
        self.avatarView.setTextColor(UIColor.white)
        self.avatarView.setFont(UIFont.rogerFontOfSize(11))
        self.avatarView.layer.borderColor = UIColor.white.cgColor
        self.avatarView.layer.borderWidth = 2
        self.avatarView.isUserInteractionEnabled = false

        self.darkOverlayView = UIView()
        self.darkOverlayView.alpha = 0
        self.darkOverlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.darkOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        self.view.addSubview(self.darkOverlayView)

        self.headerView.backgroundColor = UIColor.clear

        self.scrollView.delegate = self

        self.darkOverlayView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(SettingsViewController.dismissKeyboard)))
        self.headerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(SettingsViewController.editHeaderInfo)))

        self.displayNameField.delegate = self
        self.usernameField.delegate = self
        self.imagePicker.allowsEditing = true
        self.imagePicker.delegate = self

        // Set placeholder
        self.displayNameField.attributedPlaceholder = NSAttributedString(string: NSLocalizedString("Set name", comment: "Settings add name placeholder text"), attributes: [NSForegroundColorAttributeName: UIColor.white.withAlphaComponent(0.6)])

        // Support Arabic.
        if self.turnOnNotificationsButton.layoutDirection == .rightToLeft {
            self.turnOnNotificationsButton.contentHorizontalAlignment = .right
        }

        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                self.appVersionButton.setTitle("Roger \(version) (\(buildVersion))", for: .normal)
                self.appVersionButton.accessibilityLabel = "Roger version \(version), build \(buildVersion)"
        }

        BackendClient.instance.sessionChanged.addListener(self, method: SettingsViewController.refreshUserInfo)
        StreamService.instance.servicesChanged.addListener(self, method: SettingsViewController.refreshServices)
        Responder.applicationActiveStateChanged.addListener(self, method: SettingsViewController.handleApplicationStateChanged)
        Responder.botSetupComplete.addListener(self, method: SettingsViewController.serviceSetupComplete)

        self.refreshUserInfo()
    }

    override func viewDidAppear(_ animated: Bool) {
        if self.presentingViewController is StreamsViewController &&
            !(BackendClient.instance.session?.didSetDisplayName ?? false) {
            self.displayNameField.isUserInteractionEnabled = true
            self.displayNameField.becomeFirstResponder()
        }
        self.refreshUserInfo()
    }

    override func viewWillDisappear(_ animated: Bool) {
        Responder.applicationActiveStateChanged.removeListener(self)
        BackendClient.instance.sessionChanged.removeListener(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.accountsTableViewHeight.constant = self.accountsTableView.contentSize.height
        self.servicesTableViewHeight.constant = self.servicesTableView.contentSize.height
        self.darkOverlayView.frame = self.scrollView.frame
        // TODO: Make the scrollview more dynamic and remove this hack
        let sizeOffset: CGFloat = SettingsManager.hasNotificationsPermissions ? 275 : 375
        self.scrollView.contentSize = CGSize(width: self.view.frame.width, height: self.contentView.frame.height + self.servicesTableViewHeight.constant + self.accountsTableViewHeight.constant + sizeOffset)
    }

    // MARK: - Actions

    @IBAction func appVersionTapped(_ sender: AnyObject) {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
                return
        }
        self.copyToClipboard("Roger \(version) (\(buildVersion))", title: NSLocalizedString("Roger Version", comment: "Alert title"))
        Answers.logCustomEvent(withName: "Version Pressed", customAttributes: ["Source": "Settings"])
    }

    @IBAction func backTapped(_ sender: AnyObject) {
        self.dismissKeyboard()
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func infoTapped(_ sender: AnyObject) {
        let controller = self.storyboard!.instantiateViewController(withIdentifier: "EmbeddedBrowser") as! EmbeddedBrowserController
        controller.urlToLoad = self.faqURL
        controller.pageTitle = NSLocalizedString("Help", comment: "Browser title")
        self.present(controller, animated: true, completion: nil)
        Answers.logCustomEvent(withName: "Help Page Shown", customAttributes: ["Source": "Settings"])
    }

    @IBAction func displayNameFieldTapped(_ sender: AnyObject) {
        self.editHeaderInfo()
    }

    @IBAction func displayNameEditingDidBegin(_ sender: AnyObject) {
        self.toggleHeaderView(true)
        UIView.animate(withDuration: 0.2, animations: {
            self.darkOverlayView.alpha = 1
        }) 
    }

    @IBAction func displayNameEdited(_ sender: AnyObject) {
        self.displayNameField.isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.2, animations: {
            self.darkOverlayView.alpha = 0
        }) 

        let originalDisplayName = BackendClient.instance.session?.displayName
        guard let displayName = self.displayNameField.text , displayName != "" && displayName != originalDisplayName else {
            self.displayNameField.text =
                originalDisplayName == BackendClient.instance.session?.username ? nil : originalDisplayName
            return
        }

        Intent.changeDisplayName(newDisplayName: displayName).perform(BackendClient.instance) {
            if $0.successful {
                return
            }
            let alert = UIAlertController(
                title: NSLocalizedString("Uh oh!", comment: "Alert title"),
                message: NSLocalizedString("We failed to set your name at this time.", comment: "Alert text"),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
            Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Settings", "Type": "ChangeDisplayNameError"])
        }
    }

    @IBAction func shareTapped(_ sender: UIButton) {
        let vc = Share.createShareSheetOwnProfile(sender, source: "Settings")
        self.present(vc, animated: true, completion: nil)
    }

    @IBAction func toggleAutoplay(_ sender: UISwitch) {
        SettingsManager.autoplayAll = sender.isOn
    }

    @IBAction func toggleWeather(_ sender: UISwitch) {
        sender.isEnabled = false
        // Update backend with user choice.
        Intent.changeShareLocation(share: sender.isOn).perform(BackendClient.instance) {
            sender.isEnabled = true
            guard $0.successful else {
                sender.isOn = SettingsManager.isGlimpsesEnabled
                return
            }
            // Request recents streams, so that cache is renewed.
            StreamService.instance.loadStreams()
        }

        if CLLocationManager.authorizationStatus() == .denied {
            let alert = UIAlertController(
                title: NSLocalizedString("Enable Location", comment: "Alert title"),
                message: NSLocalizedString("Permission to enable location for weather must be granted via Settings->Roger.", comment: "Alert text"),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .default, handler: {
                (action: UIAlertAction!) -> Void in
                UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
                Answers.logCustomEvent(withName: "User Sent To System Preferences", customAttributes: ["Reason": "Location", "Source": "Settings"])
            }))
            self.present(alert, animated: true, completion: nil)
            Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Settings", "Type": "EnableLocationError"])
        } else {
            self.locationManager = CLLocationManager()
            self.locationManager!.delegate = self
            self.locationManager!.requestWhenInUseAuthorization()
        }

        Answers.logCustomEvent(withName: "Glimpses Toggle", customAttributes: ["On": sender.isOn ? "Yes" : "No"])
    }

    @IBAction func usernameEdited(_ sender: AnyObject) {
        // Reset insets
        UIView.animate(withDuration: 0.2, animations: {
            self.scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }) 

        guard let newUsername = self.usernameField.text , newUsername != "" && newUsername != self.username else {
            self.usernameField.text = self.username
            return
        }

        Intent.changeUsername(username: newUsername).perform(BackendClient.instance) {
            if $0.successful {
                return
            }
            let alert: UIAlertController
            if $0.code == 400 {
                alert = UIAlertController(
                    title: NSLocalizedString("Invalid handle", comment: "Alert title"),
                    message: NSLocalizedString("Handles must start with a letter and may only contain letters, numbers, or dashes.", comment: "Alert text"),
                    preferredStyle: .alert)
            } else if $0.code == 409 {
                alert = UIAlertController(
                    title: NSLocalizedString("Already taken", comment: "Alert title"),
                    message: NSLocalizedString("Sorry, that handle is unavailable.", comment: "Alert text"),
                    preferredStyle: .alert)
            } else {
                alert = UIAlertController(
                    title: NSLocalizedString("Uh oh!", comment: "Alert title"),
                    message: NSLocalizedString("We failed to set your handle at this time.", comment: "Alert text"),
                    preferredStyle: .alert)
            }
            alert.addAction(UIAlertAction(title: NSLocalizedString("Okay", comment: "Alert action"), style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
            self.refreshUserInfo()
            Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Settings", "Type": "ChangeUsernameError"])
        }
    }

    @IBAction func usernameEditingDidBegin(_ sender: AnyObject) {
        // TODO: Get actual keyboard height via keyboardDidShow
        self.scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 120, right: 0)
        self.scrollView.setContentOffset(CGPoint(x: 0, y: self.usernameField.center.y + 50), animated: true)
    }

    @IBAction func rateUsTapped(_ sender: AnyObject) {
        UIApplication.shared.openURL(URL(string: "itms-apps://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?id=943662312&onlyLatestVersion=true&pageNumber=0&sortOrdering=1&type=Purple+Software")!)
        Answers.logCustomEvent(withName: "Rate Us Pressed", customAttributes: ["Source": "Settings"])
    }
    
    @IBAction func talkWithUsTapped(_ sender: AnyObject) {
        var identifiers: [Intent.Participant.Identifier] = []
        // TODO: Duplicate from ContactPickerViewController.
        identifiers.append(("", "feedback"))
        StreamService.instance.getOrCreateStream(participants: [Intent.Participant(identifiers: identifiers)]) {
            if let stream = $0 {
                // A stream was found, so make the streams view controller select it.
                Responder.userSelectedStream.emit(stream)
                self.dismiss(animated: true, completion: nil)
            } else if let error = $1 as? NSError {
                let alert = UIAlertController(
                    title: NSLocalizedString("Error!", comment: "Alert title"),
                    message: String.localizedStringWithFormat(
                        NSLocalizedString("Sorry, that person could not be added.\n\nThe error we got was: %@", comment: "Alert text"),
                        error.localizedDescription),
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("Okay", comment: "Alert action"), style: .cancel, handler: nil))
                self.present(alert, animated: true, completion: nil)
                Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Settings", "Type": "TalkWithUsError"])
            }
        }
        Answers.logCustomEvent(withName: "Talk With Us Pressed", customAttributes: ["Source": "Settings"])
    }

    @IBAction func emailUsTapped(_ sender: AnyObject) {
        let alert = UIAlertController(title: NSLocalizedString("Support", comment: "Alert title"), message: NSLocalizedString("Please note that Roger Support is done by volunteers. We try to respond as quickly as possible, but it may take a while.\n\nPlease look at the Roger Help section: It has important troubleshooting tips and answers to most questions.", comment: "Email support alert message"), preferredStyle: .alert)
        // Take user directly to help page
        alert.addAction(UIAlertAction(title: NSLocalizedString("Open Help", comment: "Alert action"), style: .cancel) { action in
            self.infoTapped(self)
        })
        // Proceed with email
        alert.addAction(UIAlertAction(title: NSLocalizedString("Email", comment: "Alert action"), style: .default) { action in
            if MFMailComposeViewController.canSendMail() {
                var emailText = "\n\n\n\n"
                emailText += "--"
                emailText += "\nOS Version: \(UIDevice.current.systemVersion)"
                emailText += "\nModel: \(UIDevice.current.modelName)"

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    emailText += "\nApp Version: \(version)"
                    if let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String{
                        emailText += " (\(buildVersion))"
                    }
                }

                if let accountId = BackendClient.instance.session?.id {
                    emailText += "\nAccount Id: \(accountId)"
                }

                // Present email UI
                let vc = MFMailComposeViewController()
                vc.mailComposeDelegate = self
                vc.setToRecipients(["hello@rogertalk.com"])
                vc.setSubject(NSLocalizedString("Hello", comment: "Feedback e-mail subject"))
                vc.setMessageBody(emailText, isHTML: false)
                self.present(vc, animated: true, completion: nil)
                Answers.logCustomEvent(withName: "Email Us Pressed", customAttributes: ["Source": "Settings", "EmailClient": true])
            } else {
                self.copyToClipboard("hello@rogertalk.com", title: "Email Us")
                Answers.logCustomEvent(withName: "Email Us Pressed", customAttributes: ["Source": "Settings", "EmailClient": false])
            }
        })
        self.present(alert, animated: true, completion: nil)
    }

    @IBAction func enableNotificationsTapped(_ sender: AnyObject) {
        Responder.setUpNotifications()
        Answers.logCustomEvent(withName: "Enable Notifications", customAttributes: ["Source": "Settings"])
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Responder.updateLocation()
    }

    // MARK: - MFMailComposeViewControllerDelegate

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil)
    }

    // MARK: - ServiceManger

    func serviceLongPressed() {
    }

    func serviceSetupComplete(_ url: URL) {
        self.safariController?.dismiss(animated: true, completion: nil)
        if url.absoluteString.contains("ifttt") {
            Intent.pingIFTTT().perform(BackendClient.instance)
        }
    }

    func serviceTapped(_ index: Int) {
        let service = self.services[index]
        // TODO: Remove this hack to call into the voicemail logic.
        if service.identifier == "voicemail" {
            let voicemail = VoicemailStream(data: ["id": NSNumber(value: 0 as Int64), "chunks": NSArray(), "others": NSArray()])!
            guard case let .showAlert(title, message, action) = voicemail.instructionsActionTapped() else {
                return
            }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: action, style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
            return
        }
        // Show service UI in browser.
        guard let url = service.connectURL else {
            return
        }
        if #available(iOS 9.0, *) {
            let controller = SFSafariViewController(url: url as URL)
            self.safariController = controller
            self.present(controller, animated: true, completion: nil)
        } else {
            UIApplication.shared.openURL(url as URL)
        }
        Answers.logCustomEvent(withName: "Connect Service Shown", customAttributes: ["Source": "Settings"])
    }

    // MARK: - UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        defer {
            picker.dismiss(animated: true, completion: nil)
        }

        guard let image = info[UIImagePickerControllerEditedImage] as? UIImage, let imageData = UIImageJPEGRepresentation(image, 0.8) else {
            Answers.logCustomEvent(withName: "Profile Image Picker", customAttributes: ["Result": "Cancel"])
            return
        }

        Intent.changeUserImage(image: Intent.Image(format: .jpeg, data: imageData)).perform(BackendClient.instance) {
            if $0.successful {
                return
            }
            let alert = UIAlertController(
                title: NSLocalizedString("Uh oh!", comment: "Alert title"),
                message: NSLocalizedString("We failed to change your photo at this time.", comment: "Alert text"),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
            Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Settings", "Type": "ChangeProfileImageError"])
        }

        Answers.logCustomEvent(withName: "Profile Image Picker", customAttributes: ["Result": "PickedImage"])
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.toggleHeaderView()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            self.toggleHeaderView()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let maxHeight: CGFloat = 200
        let minHeight: CGFloat = 70
        let spacing = self.headerHeight.constant - scrollView.contentOffset.y

        // Remove x offset
        let yOffset = spacing >= minHeight && spacing <= maxHeight ? 0 : scrollView.contentOffset.y
        scrollView.contentOffset = CGPoint(x: 0, y: yOffset)

        // Allow the label to move with the scroll offset to give it a "bouncy" effect
        let labelDistance = scrollView.contentOffset.y + 40
        self.displayNameLabelBottomSpacing.constant = spacing > maxHeight ? labelDistance : max(10, labelDistance)

        // Set the height of the header view
        self.headerHeight.constant = min(maxHeight, max(minHeight, spacing))
        let scrollingOpacity = (spacing - minHeight) / (maxHeight - minHeight)
        self.usernameLabel.alpha = scrollingOpacity
        self.avatarView.alpha = scrollingOpacity
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        return indexPath
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cellIdentifier = tableView.cellForRow(at: indexPath)?.reuseIdentifier else {
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)

        switch cellIdentifier {
        case "addIdentifierCell":
            let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Add Phone Number", comment: "Sheet action"), style: .default) { action in
                let viewController = self.storyboard?.instantiateViewController(withIdentifier: "Challenge") as! ChallengeViewController
                viewController.identifierType = .phoneNumber
                self.present(viewController, animated: true, completion: {
                    sheet.dismiss(animated: true, completion: nil)
                })
                Answers.logCustomEvent(withName: "Add Identifier Sheet Option", customAttributes: ["Option": "AddPhoneNumber"])
            })
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Add Email Address", comment: "Sheet action"), style: .default) { action in
                let viewController = self.storyboard?.instantiateViewController(withIdentifier: "Challenge") as! ChallengeViewController
                viewController.identifierType = .email
                self.present(viewController, animated: true, completion: {
                    sheet.dismiss(animated: true, completion: nil)
                })
                Answers.logCustomEvent(withName: "Add Identifier Sheet Option", customAttributes: ["Option": "AddEmail"])
            })
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Get Web Access Code", comment: "sheet action"), style: .default) { action in
                sheet.dismiss(animated: true, completion: nil)
                Intent.getAccessCode().perform(BackendClient.instance) { result in
                    guard let data = result.data, let code = data["code"] as? String , result.successful else {
                        return
                    }
                    // NSLocalizedString("Use this access code to connect to services in Roger", comment: "Roger access code alert title")
                    let codeAlert = UIAlertController(
                            title: NSLocalizedString("Access Code", comment: "Roger access code alert title"),
                        message: String.localizedStringWithFormat(
                            NSLocalizedString("You can use this code to access your account on the web.\n\n%@", comment: "Roger access code alert message"),
                            code),
                            preferredStyle: .alert)
                        codeAlert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                    self.present(codeAlert, animated: true, completion: nil)
                }
            })
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Sheet action"), style: .cancel) { action in
                sheet.dismiss(animated: true, completion: nil)
                Answers.logCustomEvent(withName: "Add Identifier Sheet Option", customAttributes: ["Option": "Cancel"])
            })
            // Provide an anchor for iPad.
            if let popoverPresenter = sheet.popoverPresentationController, let cell = tableView.cellForRow(at: indexPath) {
                popoverPresenter.sourceView = cell
                popoverPresenter.sourceRect = cell.bounds.insetBy(dx: 0, dy: -5)
            }
            self.present(sheet, animated: true, completion: nil)
            Answers.logCustomEvent(withName: "Add Identifier Sheet Shown", customAttributes: nil)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return (indexPath as NSIndexPath).row == tableView.numberOfRows(inSection: 0) - 1
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.userContactInfo.count + 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // The last cell should be "add additional contact info"
        if (indexPath as NSIndexPath).row == tableView.numberOfRows(inSection: 0) - 1 {
            return tableView.dequeueReusableCell(withIdentifier: "addIdentifierCell")!
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "identifierCell") as! IdentifierCell
        cell.identifier.text = self.userContactInfo[(indexPath as NSIndexPath).row]
        return cell
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.dismissKeyboard()
        return false
    }

    // MARK: - Private

    fileprivate struct Section {
        static let Account = 0
        static let Username = 1
        static let Notifications = 2
    }

    fileprivate var darkOverlayView: UIView!
    fileprivate let faqURL = SettingsManager.baseURL.appendingPathComponent("help")
    fileprivate let imagePicker = UIImagePickerController()
    fileprivate var locationManager: CLLocationManager?
    fileprivate let phoneNumberUtil: NBPhoneNumberUtil

    fileprivate var userContactInfo: [String] = [] {
        didSet {
            self.accountsTableView.reloadData()
        }
    }

    fileprivate var username: String? {
        didSet {
            guard let username = self.username else {
                self.usernameField.text = ""
                self.usernameLabel.text = ""
                self.usernameHintLabel.text = NSLocalizedString("A handle lets you be reached via rogertalk.com/handle", comment: "Username hint")
                return
            }
            self.usernameField.text = username.hasPrefix("+") ? "" : username
            self.usernameLabel.text = "@\(username)"
            self.usernameHintLabel.text = String.localizedStringWithFormat(
                NSLocalizedString("Friends can reach you via rogertalk.com/%@", comment: "Username hint"),
                username)
        }
    }

    fileprivate func copyToClipboard(_ value: String, title: String) {
        UIPasteboard.general.string = value
        let alert = UIAlertController(
            title: title,
            message: String.localizedStringWithFormat(
                NSLocalizedString("%@ has been copied to your clipboard.", comment: "Alert text"),
                value),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Okay", comment: "Alert action"), style: .cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }

    fileprivate func handleApplicationStateChanged(_ active: Bool) {
        guard active else {
            return
        }
        self.refreshUserInfo()
    }

    fileprivate func refreshServices() {
        self.servicesTableView.reloadData()
        self.view.layoutIfNeeded()
    }

    fileprivate func refreshUserInfo() {
        guard let session = BackendClient.instance.session else {
            return
        }

        self.userContactInfo = []
        if let identifiers = session.identifiers {
            for identifier in identifiers {
                // Phone number identifiers start with "+".
                if identifier.characters.first == "+" {
                    var formattedIdentifier = identifier
                    if let
                        phoneNumber = try? self.phoneNumberUtil.parse(identifier, defaultRegion: "US"),
                        let formattedNumber = try? self.phoneNumberUtil.format(phoneNumber, numberFormat: .NATIONAL)
                    {
                        formattedIdentifier = formattedNumber
                    }
                    self.userContactInfo.append(formattedIdentifier)
                } else if identifier.contains("@") {
                    // This is an email identifier.
                    self.userContactInfo.append(identifier)
                }
            }
        }

        self.username = session.username
        if session.displayName.characters.first == "+" || session.displayName == session.username {
            self.displayNameField.text = nil
        } else {
            self.displayNameField.text = session.displayName
        }

        if let imageURL = session.imageURL {
            self.avatarView.setImageWithURL(imageURL)
        }

        self.weatherSwitch.isEnabled = true
        self.weatherSwitch.isOn = SettingsManager.isGlimpsesEnabled
        self.autoplaySwitch.isOn = SettingsManager.autoplayAll
        self.notificationsViewHeightConstraint.constant =
            SettingsManager.hasNotificationsPermissions ? 0 : 100

        self.view.layoutIfNeeded()
    }

    fileprivate func toggleHeaderView(_ expand: Bool? = nil) {
        let shouldExpand = expand ?? (self.headerHeight.constant >= 140)

        let height, alpha: CGFloat
        if shouldExpand {
            height = 200
            alpha = 1
        } else {
            height = 70
            alpha = 0
        }

        UIView.animate(withDuration: 0.2, animations: {
            if shouldExpand {
                self.scrollView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
            }
            self.headerHeight.constant = height
            self.usernameLabel.alpha = alpha
            self.avatarView.alpha = alpha
            self.view.layoutIfNeeded()
        }) 
    }
}

class IdentifierCell: UITableViewCell {
    @IBOutlet weak var identifier: UILabel!
}
