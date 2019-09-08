import Crashlytics
import libPhoneNumber_iOS
import UIKit

class ChallengeViewController: UIViewController, UITextFieldDelegate {

    enum IdentifierType {
        case phoneNumber, email
    }

    enum State {
        case enterIdentifier, enterSecret, done
    }

    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var centerXConstraint: NSLayoutConstraint!
    @IBOutlet weak var confirmIdentifierButton: MaterialButton!
    @IBOutlet weak var confirmSecretButton: MaterialButton!
    @IBOutlet weak var identifierField: InsetTextField!
    @IBOutlet weak var secretField: EnterCodeTextField!
    @IBOutlet weak var secretLabel: UILabel!
    @IBOutlet weak var sentSecretLabel: UILabel!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var waitTimeLabel: UILabel!
    @IBOutlet weak var callMeButton: UIButton!
    @IBOutlet weak var switchSignUpModeButton: UIButton!

    static var defaultIdentifier: String?

    var allowBackButton = true
    var identifierType: IdentifierType = .phoneNumber

    // MARK: UIViewController

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.backButton.isHidden = !self.allowBackButton

        self.secretField.delegate = self
        self.secretField.addTarget(self, action: #selector(ChallengeViewController.updateSecretTextLabel), for: .editingChanged)

        self.secretLabel.font = UIFont.monospacedDigitsRogerFontOfSize(30)
        self.updateSecretTextLabel()

        self.identifierField.delegate = self
        self.waitTimeLabel.font = UIFont.monospacedDigitsRogerFontOfSize(14)

        self.setupSignupMode()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.state = .enterIdentifier
        self.identifierField.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.state = .done
        // Hide the keyboard.
        self.view.endEditing(true)
    }

    func updateWaitTimeLabel() {
        guard let referenceDate = self.startCountdownDate else {
            print("Countdown reference date should not be nil.")
            return
        }

        let secondsElapsed = Int(floor(Date().timeIntervalSince(referenceDate)))
        if secondsElapsed > self.waitTime {
            self.countdownTimer?.invalidate()
            self.countdownTimer = nil
            UIView.animate(withDuration: 0.2, animations: {
                self.waitTimeLabel.alpha = 0
                }, completion: { _ in
                    UIView.animate(withDuration: 0.3, animations: {
                        self.waitTimeLabel.text = NSLocalizedString("Still no code? Get it via phone call instead.", comment: "Verify phone number")
                        self.waitTimeLabel.alpha = 1
                        self.callMeButton.alpha = 1
                    }) 
            }) 
            return
        }

        if secondsElapsed > 10 {
            let formatter = DateComponentsFormatter()
            self.waitTimeLabel.text = String.localizedStringWithFormat(
                NSLocalizedString("Your code should arrive within %@", comment: "Verify phone number"),
                formatter.string(from: TimeInterval(self.waitTime - secondsElapsed))!)
            if self.identifierType == .phoneNumber {
                self.callMeButton.isHidden = false
            }
        } else {
            self.waitTimeLabel.text = NSLocalizedString("Your code should arrive soon.", comment: "Verify phone number")
            self.callMeButton.isHidden = true
        }
    }

    func updateSecretTextLabel() {
        guard var text = self.secretField.text else {
            return
        }

        self.confirmSecretButton.backgroundColor = text.characters.count == 3 ? UIColor.rogerBlue : UIColor.rogerGray
        let codeText = NSMutableAttributedString()
        for _ in 1...3 {
            let digit = text.characters.popFirst() ?? "•"
            codeText.append(NSAttributedString(string: " \(digit) "))
        }

        self.secretLabel.attributedText = codeText
    }

    // MARK: Actions

    @IBAction func switchSignupModeTapped(_ sender: AnyObject) {
        if self.identifierType == .phoneNumber {
            self.identifierType = .email
        } else {
            self.identifierType = .phoneNumber
        }

        self.setupSignupMode()
    }

    @IBAction func backFromEnterSecretTapped(_ sender: AnyObject) {
        self.state = .enterIdentifier
    }

    @IBAction func backTapped(_ sender: AnyObject) {
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func confirmIdentifierTapped(_ sender: AnyObject) {
        self.requestChallenge()
        self.state = .enterSecret
    }

    @IBAction func confirmSecretTapped(_ sender: AnyObject) {
        guard let secret = self.secretField.text else {
            self.showAlert(
                NSLocalizedString("Oops!", comment: "Alert title"),
                message: NSLocalizedString("You must enter a valid code.", comment: "Alert text"),
                cancelTitle: NSLocalizedString("Try again", comment: "Alert action"))
            Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Challenge", "Type": "CodeEmpty"])
            return
        }

        guard secret.characters.count == 3 else {
            self.shaker.stop()
            self.shaker.start(self.secretLabel, repeats: false)
            return
        }
        
        self.confirmSecretButton.startLoadingAnimation()

        let identifier: String
        if self.identifierType == .phoneNumber {
            identifier = ContactService.shared.normalize(identifier: self.identifierField.text!)
        } else {
            identifier = self.identifierField.text!
        }

        Intent.respondToChallenge(identifier: identifier, secret: secret, firstStreamParticipant: StreamsViewController.firstStreamParticipant).perform(BackendClient.instance) {
            guard $0.successful else {
                let message: String
                if $0.code == 400 {
                    self.shaker.stop()
                    self.shaker.start(self.secretLabel, repeats: false)
                    message = NSLocalizedString("That doesn't look like the code we sent.", comment: "Alert text")
                    Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Challenge", "Type": "InvalidCode"])
                } else if $0.code == 409 {
                    message = NSLocalizedString("An account with that identifier already exists.", comment: "Alert text")
                    Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Challenge", "Type": "AccountAlreadyExists"])
                } else {
                    message = NSLocalizedString("We failed to validate your code at this time.", comment: "Alert text")
                    Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Challenge", "Type": "FailedToValidateCode_HTTP\($0.code)"])
                }
                self.confirmSecretButton.stopLoadingAnimation()
                self.showAlert(
                    NSLocalizedString("Uh oh!", comment: "Alert title"),
                    message: message,
                    cancelTitle: NSLocalizedString("Try again", comment: "Alert action"))
                return
            }

            guard let data = $0.data, let session = Session(data, timestamp: Date()) else {
                print("WARNING: Did not get a session")
                self.confirmSecretButton.stopLoadingAnimation()
                self.showAlert(
                    NSLocalizedString("Uh oh!", comment: "Alert title"),
                    message: NSLocalizedString("Something went wrong on our side. Sorry about that!", comment: "Alert text"),
                    cancelTitle: NSLocalizedString("Try again", comment: "Alert action"))
                Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Challenge", "Type": "ChallengeMissingSession"])
                return
            }

            guard session.active else {
                print("WARNING: Session is not active")
                self.confirmSecretButton.stopLoadingAnimation()
                self.showAlertAndGoBack(
                    NSLocalizedString("Uh oh!", comment: "Alert title"),
                    message: NSLocalizedString("The account you logged in with is not active.", comment: "Alert text"),
                    cancelTitle: NSLocalizedString("Go back", comment: "Alert action"))
                Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Challenge", "Type": "ChallengeInactiveAccount"])
                return
            }

            // Reset the default identifier
            ChallengeViewController.defaultIdentifier = nil

            let setNewSession = {
                // Set the new session
                BackendClient.instance.session = session
                // Session responses may contain streams data; pass it on to the streams service.
                if let list = data["streams"] as? [DataType] {
                    StreamService.instance.setStreamsWithDataList(list: list)
                    StreamService.instance.nextPageCursor = data["cursor"] as? String
                }

                // Save onboarding status.
                SettingsManager.userIdentifier = identifier
                
                if self.presentingViewController is GetStartedViewController {
                    // Go to the Name and Notifications setup page.
                    DispatchQueue.main.async {
                        let controller = self.storyboard!.instantiateViewController(withIdentifier: "SetName")
                        controller.transitioningDelegate = SidewaysTransition.instance
                        self.present(controller, animated: true, completion: nil)
                    }
                    return
                } else if self.presentingViewController is UINavigationController {
                    // TODO: Kill this code once enough old clients have updated as we no longer allow onboarding without authentication
                    ContactService.shared.importContacts(requestAccess: true)
                }

                self.dismiss(animated: true, completion: nil)
            }

            if let currentSession = BackendClient.instance.session, currentSession.id != session.id {
                let alert = UIAlertController(
                    title: NSLocalizedString("Confirm", comment: "Confirm switching accounts alert title"),
                    message: NSLocalizedString("An account with this identifier already exists. Switch to that account?", comment: "Description for switching accounts"), preferredStyle: .alert)
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("Cancel", comment: "Cancel switching accounts action"),
                    style: .default) { action in
                        self.dismiss(animated: true, completion: nil)
                })
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("Switch", comment:"Confirm switching accounts action"),
                    style: .destructive) { action in
                        setNewSession()
                    })
                self.present(alert, animated: true, completion: nil)
            } else {
                setNewSession()
            }
        }
    }

    @IBAction func infoTapped(_ sender: AnyObject) {
        let controller = self.storyboard!.instantiateViewController(withIdentifier: "EmbeddedBrowser") as! EmbeddedBrowserController
        controller.urlToLoad = SettingsManager.baseURL.appendingPathComponent("help")
        controller.pageTitle = NSLocalizedString("Help", comment: "Browser title")
        self.present(controller, animated: true, completion: nil)
        Answers.logCustomEvent(withName: "Help Page Shown", customAttributes: ["Source": "Challenge"])
    }

    @IBAction func callMeTapped(_ sender: AnyObject) {
        guard let referenceDate = self.startCountdownDate,
            Int(Date().timeIntervalSince(referenceDate)) > self.waitTime else {
            self.showAlert(
                NSLocalizedString("Hold on", comment: "Alert title"),
                message: NSLocalizedString("This is exciting, we know. But please wait until the timer runs out before trying the phone call option.", comment: "Alert text"),
                cancelTitle: NSLocalizedString("Okay", comment: "Alert action"))
            return
        }

        self.requestChallenge(preferPhoneCall: true)
        self.callMeButton.isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.1, animations: {
            self.callMeButton.alpha = 0
            self.waitTimeLabel.alpha = 0
            }, completion: { _ in
                UIView.animate(withDuration: 0.3, animations: {
                    self.waitTimeLabel.text = NSLocalizedString("You'll get a phone call momentarily.", comment: "Verify phone number")
                    self.waitTimeLabel.alpha = 1
                }) 
        }) 
    }

    // MARK: - Private

    private let waitTime = 300
    private let shaker = Shaker(distance: 6, duration: 0.4, frequency: 1, shakes: 4)

    private var asYouTypeFormatter: NBAsYouTypeFormatter!
    private var countryCodePrefix: String = "+1"
    private var startCountdownDate: Date?
    private var countdownTimer: Timer?

    private var state: State = .enterIdentifier {
        didSet {
            var offset: CGFloat = 0
            switch self.state {
            case .enterIdentifier:
                self.identifierField?.becomeFirstResponder()
            case .enterSecret:
                self.secretField.text = ""
                self.updateSecretTextLabel()
                self.secretField.becomeFirstResponder()
                self.sentSecretLabel.text = String.localizedStringWithFormat(
                    NSLocalizedString("We sent you a code\nat %@.", comment: "E-mail/phone verification step"),
                    "\u{202A}\(self.identifierField.text!)\u{202C}")
                offset = -self.view.frame.width
                self.setupCountdownTimer()
            case .done:
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                return
            }

            // Transition between identifier and secret views.
            UIView.animate(withDuration: 0.25,
                delay: 0,
                options: [.curveEaseInOut],
                animations: {
                    self.centerXConstraint.constant = offset
                    self.view.layoutSubviews()
                },
                completion: nil
            )
        }
    }

    private func requestChallenge(preferPhoneCall shouldCall: Bool = false) {
        let input = self.identifierField.text!

        let identifier: String
        switch self.identifierType {
        case .email:
            guard input.contains("@") else {
                self.showAlert(
                    NSLocalizedString("Oops!", comment: "Alert title"),
                    message: NSLocalizedString("That doesn't look like an e-mail.", comment: "Alert text"),
                    cancelTitle: NSLocalizedString("Try again", comment: "Alert action"))
                Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Challenge", "Type": "InvalidEmail"])
                return
            }
            identifier = input
        case .phoneNumber:
            guard let number = ContactService.shared.validateAndNormalize(phoneNumber: input) else {
                self.showAlert(
                    NSLocalizedString("Oops!", comment: "Alert title"),
                    message: NSLocalizedString("That doesn't look like a phone number.", comment: "Alert text"),
                    cancelTitle: NSLocalizedString("Try again", comment: "Alert action"))
                Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Challenge", "Type": "InvalidNumber"])
                return
            }
            identifier = number
        }

        // Send activation code SMS or e-mail.
        Intent.requestChallenge(identifier: identifier, preferPhoneCall: shouldCall).perform(BackendClient.instance) {
            guard $0.successful else {
                self.confirmSecretButton.stopLoadingAnimation()
                self.showAlertAndGoBack(
                    NSLocalizedString("Uh oh!", comment: "Alert title"),
                    message: NSLocalizedString("Please check your phone number and internet connection.", comment: "Alert text"),
                    cancelTitle: NSLocalizedString("Okay", comment: "Alert action"))
                Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Challenge", "Type": "RequestCodeFailed"])
                return
            }
        }
    }

    private func setupCountdownTimer() {
        // Invalidate any previously running timer and start a new one
        self.countdownTimer?.invalidate()
        self.startCountdownDate = Date()
        self.updateWaitTimeLabel()
        self.countdownTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(ChallengeViewController.updateWaitTimeLabel), userInfo: nil, repeats: true)
    }

    private func setupSignupMode() {
        self.identifierField.delegate = nil
        self.secretField.delegate = nil
        self.view.endEditing(true)

        switch self.identifierType {
        case .email:
            self.titleLabel.text = NSLocalizedString("What's your email?", comment: "Verify e-mail")
            self.confirmIdentifierButton.setTitle(NSLocalizedString("CONFIRM EMAIL", comment: "Verify e-mail; button"), for: .normal)

            self.identifierField.text = ChallengeViewController.defaultIdentifier ?? ""
            self.identifierField.keyboardType = .emailAddress

            self.switchSignUpModeButton.setTitle("Use a phone number instead", for: .normal)
            self.callMeButton.isHidden = true
            self.waitTimeLabel.isHidden = true
        case .phoneNumber:
            self.titleLabel.text = NSLocalizedString("What's your number?", comment: "Verify phone number")
            self.confirmIdentifierButton.setTitle(NSLocalizedString("CONFIRM NUMBER", comment: "Verify phone number; button"), for: .normal)

            // Set up phone number formatter.
            var countryCode = ContactService.shared.region
            if countryCode == "ZZ" {
                // Default to USA.
                countryCode = "US"
            }
            self.asYouTypeFormatter = NBAsYouTypeFormatter(regionCode: countryCode)

            // Figure out the country code.
            CLSLogv("Got country %@ from SIM", getVaList([countryCode]))
            if let code = NBMetadataHelper().countryCode(fromRegionCode: countryCode) {
                CLSLogv("Using country code prefix +%@", getVaList([code]))
                self.countryCodePrefix = String(format:"+%@", code)
            } else {
                CLSLogv("Failed to deduce country code prefix", getVaList([]))
                self.countryCodePrefix = "+"
            }

            // Set up the default identifier field value.
            self.identifierField.keyboardType = .phonePad
            if let identifier = ChallengeViewController.defaultIdentifier {
                self.identifierField.text = self.asYouTypeFormatter.inputString(identifier)
            } else {
                self.identifierField.text = self.asYouTypeFormatter.inputString(self.countryCodePrefix)
            }

            self.switchSignUpModeButton.setTitle("Use an email address instead", for: .normal)
            self.callMeButton.isHidden = false
            self.waitTimeLabel.isHidden = false
        }

        self.identifierField.becomeFirstResponder()
        self.identifierField.delegate = self
        self.secretField.delegate = self
    }

    /// Shows an alert with an optional completion handler.
    private func showAlert(_ title: String, message: String, cancelTitle: String, actionHandler: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in actionHandler?() })
        self.present(alert, animated: true, completion: nil)
    }

    /// Shows an alert message and goes back to identifier screen.
    private func showAlertAndGoBack(_ title: String, message: String, cancelTitle: String) {
        self.showAlert(title, message: message, cancelTitle: cancelTitle) {
            self.state = .enterIdentifier
        }
    }

    // MARK: - UITextFieldDelegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField == self.secretField {
            let currentCharacterCount = textField.text?.characters.count ?? 0
            return currentCharacterCount + string.characters.count <= 3
        }

        guard self.identifierType == .phoneNumber else {
            return true
        }

        // Whether the text field changed at the end of the string.
        let changedAtEnd = (range.location + range.length == textField.text!.characters.count)
        if range.length == 0 && changedAtEnd && string.characters.count == 1 {
            // The most common case: the user typed another character.
            textField.text = self.asYouTypeFormatter.inputDigit(string)
        } else if range.length == 1 && changedAtEnd {
            // The second most common case: the user deleted the last character.
            textField.text = self.asYouTypeFormatter.removeLastDigit()
        } else {
            // All other cases (e.g., the user pasted something).
            self.asYouTypeFormatter.clear()

            let newText = (textField.text! as NSString).replacingCharacters(in: range, with: string)
            textField.text = self.asYouTypeFormatter.inputString(newText)
            if let cursor = textField.position(from: textField.beginningOfDocument, offset: range.location + string.characters.count) {
                textField.selectedTextRange = textField.textRange(from: cursor, to: cursor)
            }
        }

        return false
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        if textField == self.identifierField && self.identifierType == .phoneNumber {
            self.asYouTypeFormatter.clear()
        }
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case self.identifierField:
            self.confirmIdentifierTapped(self.confirmIdentifierButton)
        case self.secretField:
            self.confirmSecretTapped(self.confirmSecretButton)
        default:
            return true
        }
        return false
    }

    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return (textField == self.identifierField && self.state != .enterIdentifier) ||
            (textField == self.secretField && self.state != .enterSecret) ||
            self.state == .done
    }
}

class InsetTextField: UITextField {
    // Placeholder position.
    override func textRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.insetBy(dx: 5, dy: 5)
    }

    // Text position.
    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.insetBy(dx: 5, dy: 5)
    }
}

class EnterCodeTextField: UITextField {
    // Hide the caret
    override func caretRect(for position: UITextPosition) -> CGRect {
        return CGRect.zero
    }
}
