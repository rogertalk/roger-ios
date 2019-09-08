import Crashlytics
import UIKit

class SetNameViewController: UIViewController,
    UITextFieldDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate,
    AvatarViewDelegate {

    @IBOutlet weak var confirmButton: MaterialButton!
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var avatarView: AvatarView!

    private var didRequestPhoto = false

    override func viewDidLoad() {
        super.viewDidLoad()

        self.avatarView.hasDropShadow = false
        self.avatarView.delegate = self
        self.avatarView.setText(NSLocalizedString("ADD\nPHOTO", comment: "Text on top of avatar with no photo in Settings"))
        self.avatarView.setTextColor(UIColor.black)
        self.avatarView.setFont(UIFont.rogerFontOfSize(11))
        self.avatarView.layer.borderColor = UIColor.darkGray.cgColor
        self.avatarView.layer.borderWidth = 2
        self.avatarView.shouldAnimate = false

        self.imagePicker.allowsEditing = true
        self.imagePicker.delegate = self

        self.nameTextField.delegate = self
        self.nameTextField.becomeFirstResponder()

        // Prefill image if this is an existing account
        if let imageURL = BackendClient.instance.session?.imageURL {
            self.avatarView.setImageWithURL(imageURL)
        }
        // Prefill name from an existing session or from the AddressBook
        if let session = BackendClient.instance.session, session.didSetDisplayName {
            self.nameTextField.text = session.displayName
        } else {
            // Prioritize the number they have entered, and  then any identifiers in the backend.
            var identifiers: [String]?
            if let identifier = SettingsManager.userIdentifier {
                identifiers = [identifier]
            } else {
                identifiers = BackendClient.instance.session?.identifiers
            }

            // If this user has themselves as a contact, use the corresponding name.
            if let identifiers = identifiers, let displayName = ContactService.shared.findContact(byIdentifiers: identifiers)?.name {
                self.nameTextField.text = displayName
            } else {
                // Fall back to the device name.
                var deviceName = UIDevice.current.name
                let exclude = ["iphone de", "iphone", "ipod", "ipad", "'s", "’s"]
                exclude.forEach {
                    deviceName = deviceName.replacingOccurrences(of: $0, with: "", options: .caseInsensitive, range: nil)
                }
                self.nameTextField.text = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        Responder.notificationSettingsChanged.addListener(self, method: SetNameViewController.handleNotificationSettingsChanged)
        Answers.logCustomEvent(withName: "Onboarding Enter Name Shown", customAttributes: [
            "Name Prefilled": self.nameTextField.text?.isEmpty ?? false ? "No" : "Yes",
        ])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.view.endEditing(true)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    @IBAction func confirmTapped(_ sender: AnyObject) {
        guard let text = self.nameTextField.text , !text.isEmpty else {
            self.showAlert(
                NSLocalizedString("Uh oh!", comment: "Alert title"),
                message: NSLocalizedString("That doesn't look like your name.", comment: "Alert text"),
                cancelTitle: NSLocalizedString("Try again", comment: "Alert action"),
                actionTitle: nil,
                tappedActionCallback: nil)
            Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "EnableNotifications", "Type": "OnboardingInvalidDisplayName"])
            return
        }

        guard self.didRequestPhoto else {
            self.showAlert("Update Photo", message: NSLocalizedString("Do you want to update your profile picture?", comment: "Alert description"), cancelTitle: NSLocalizedString("Later", comment: "Alert action"), actionTitle: NSLocalizedString("Yes", comment: "Alert action")) { result in
                self.didRequestPhoto = true
                guard result else {
                    // Move forward with the original intent
                    self.confirmTapped(self)
                    return
                }
                self.present(self.imagePicker, animated: true, completion: nil)
            }
            return
        }

        var image: Intent.Image?
        if let data = self.userPhotoData {
            image = Intent.Image(format: .jpeg, data: data)
        }

        // Show loading UI
        self.confirmButton.isEnabled = false
        self.confirmButton.startLoadingAnimation()

        let showError = {
            self.showAlert(
                NSLocalizedString("Uh oh!", comment: "Alert title"),
                message: NSLocalizedString("Something went wrong. Please try again!", comment: "Alert text"),
                cancelTitle: NSLocalizedString("Okay", comment: "Alert action"),
                actionTitle: nil,
                tappedActionCallback: nil)
        }

        let ensureNotificationPermissions = {
            guard !SettingsManager.hasNotificationsPermissions else {
                self.finish()
                return
            }

            self.showAlert(NSLocalizedString("😀 Notifications", comment: "Alert title"),
                           message: NSLocalizedString("Turn on notifications to get notified when your friends talk to you!", comment: "Alert text"), cancelTitle: NSLocalizedString("Later", comment: "Alert action"), actionTitle: NSLocalizedString("Allow", comment: "Alert action")) { result in
                            guard result else {
                                self.finish()
                                return
                            }
                            Responder.setUpNotifications()
            }
        }

        // The user already has a session, so set name and image on their existing account
        if let image = image {
            Intent.changeUserImage(image: image).perform(BackendClient.instance)
        }
        Intent.changeDisplayName(newDisplayName: text).perform(BackendClient.instance) { result in
            self.confirmButton.stopLoadingAnimation()
            self.confirmButton.isEnabled = true
            guard result.successful else {
                showError()
                return
            }

            // Join a group if there was a relevant invite
            if let token = StreamsViewController.groupInviteToken {
                StreamService.instance.joinGroup(inviteToken: token)
            }

            ensureNotificationPermissions()
        }
    }

    private func handleNotificationSettingsChanged(_ settings: UIUserNotificationSettings) {
        self.finish()
    }

    private func finish() {
        let vc = self.storyboard!.instantiateViewController(withIdentifier: "Root")
        vc.transitioningDelegate = SidewaysTransition.instance
        // Try to join a group if there was a chunk token
        guard let token = StreamsViewController.groupInviteToken else {
            self.present(vc, animated: true, completion: nil)
            return
        }

        StreamService.instance.joinGroup(inviteToken: token) { _ in
            self.present(vc, animated: true, completion: nil)
        }
    }

    // MARK: - AvatarViewDelegate

    func didEndTouch(_ avatarView: AvatarView) {
        self.present(self.imagePicker, animated: true, completion: nil)
    }

    func accessibilityFocusChanged(_ avatarView: AvatarView, focused: Bool) { }

    // MARK: - UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        defer {
            picker.dismiss(animated: true, completion: nil)
        }

        guard let image = info[UIImagePickerControllerEditedImage] as? UIImage, let imageData = UIImageJPEGRepresentation(image, 0.8) else {
            Answers.logCustomEvent(withName: "Profile Image Picker", customAttributes: ["Result": "Cancel"])
            return
        }

        self.didRequestPhoto = true
        self.userPhotoData = imageData
        self.avatarView.setImage(image)

        Answers.logCustomEvent(withName: "Profile Image Picker", customAttributes: ["Result": "PickedImage"])
    }

    // MARK: UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case self.nameTextField:
            if self.confirmButton.isEnabled {
                self.confirmTapped(self.confirmButton)
            }
        default:
            return true
        }
        return false
    }

    // MARK: Private

    private let imagePicker = UIImagePickerController()
    private var userPhotoData: Data?

    private func showAlert(_ title: String, message: String, cancelTitle: String, actionTitle: String?, tappedActionCallback: ((Bool) -> Void)?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if let action = actionTitle {
            let positiveAction = UIAlertAction(title: action, style: .default) { action in
                tappedActionCallback?(true) }
            alert.addAction(positiveAction)
            if #available(iOS 9.0, *) {
                alert.preferredAction = positiveAction
            }
        }
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { action in
            tappedActionCallback?(false) })

        self.present(alert, animated: true, completion: nil)
    }
}
