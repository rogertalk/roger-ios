import Crashlytics
import UIKit

protocol QuickInviteDelegate {
    func invite(_ contact: ContactEntry)
    func didReceiveFocus(_ quickInviteView: QuickInviteView)
    func dismissInvite()

    var contactsToInvite: [ContactEntry] { get }
}

class InviteViewController: UIViewController, QuickInviteDelegate {

    var contactsToInvite: [ContactEntry] {
        return ContactService.shared.uninvitedContacts
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        self.modalTransitionStyle = .crossDissolve
        self.modalPresentationStyle = .overCurrentContext
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        self.view.backgroundColor = UIColor.black.withAlphaComponent(0.6)

        // Tap the transluncent area to dismiss
        let dismissView = UIView(frame: self.view.frame)
        dismissView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(InviteViewController.dismissInvite)))
        self.view.addSubview(dismissView)

        self.quickInviteView = QuickInviteView(frame: CGRect(x: 0, y: self.view.frame.height, width: self.view.frame.width, height: 180))
        self.quickInviteView.delegate = self
        self.view.addSubview(self.quickInviteView)
    }

    override func viewWillAppear(_ animated: Bool) {
        UIView.animate(withDuration: 0.25, animations: {
            self.quickInviteView.transform = CGAffineTransform.identity.translatedBy(x: 0, y: -180)
        }) 
    }

    override var prefersStatusBarHidden : Bool {
        return true
    }

    // MARK: - QuickInviteDelegate

    func invite(_ contact: ContactEntry) {
        ContactService.shared.sendInvite(toContact: contact)
    }

    func dismissInvite() {
        UIView.animate(withDuration: 0.15, animations: {
            self.quickInviteView.transform = CGAffineTransform.identity
        }) 
        self.dismiss(animated: true, completion: nil)
    }

    func didReceiveFocus(_ quickInviteView: QuickInviteView) { }

    fileprivate var quickInviteView: QuickInviteView!
}

class QuickInviteView: UIView {

    @IBOutlet weak var findFriendsButton: MaterialButton!
    @IBOutlet weak var inviteUserLabel: UILabel!
    @IBOutlet weak var inviteOptionsView: UIView!
    @IBOutlet weak var allDoneLabel: UILabel!
    @IBOutlet weak var skipButton: MaterialButton!
    @IBOutlet weak var inviteButton: MaterialButton!
    @IBOutlet weak var previousButton: UIButton!
    @IBOutlet weak var inviteFriendsLabel: UILabel!
    @IBOutlet weak var closeButton: UIButton!

    var delegate: QuickInviteDelegate! {
        didSet {
            self.refresh()
        }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.initialize()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initialize()
    }

    func initialize() {
        // Load and add the QuickInvite view
        let quickInviteView = Bundle.main.loadNibNamed("QuickInviteView", owner: self, options: nil)?[0] as! UIView
        self.addSubview(quickInviteView)
        quickInviteView.frame = self.bounds

        self.layer.cornerRadius = 8
        self.skipButton.layer.borderColor = UIColor.lightGray.cgColor
        self.skipButton.layer.borderWidth = 1
        self.inviteFriendsLabel.isHidden = !UIAccessibilityIsVoiceOverRunning()
        self.closeButton.isHidden = !UIAccessibilityIsVoiceOverRunning()
        self.refresh()

        // Update contacts
        ContactService.shared.contactsChanged.addListener(self, method: QuickInviteView.handleContactsChanged)

        // Alert VoiceOver
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil)
    }

    @IBAction func findFriendsTapped(_ sender: AnyObject) {
        self.delegate.didReceiveFocus(self)
        ContactService.shared.importContacts(requestAccess: true)
    }

    @IBAction func previousTapped(_ sender: AnyObject) {
        self.delegate.didReceiveFocus(self)

        guard self.currentContactIndex > 0 else {
            return
        }
        self.currentContactIndex -= 1
        Answers.logCustomEvent(withName: "QuickInvite", customAttributes: ["Option": "Previous"])
    }

    @IBAction func skipTapped(_ sender: AnyObject) {
        self.delegate.didReceiveFocus(self)

        self.skipButton.pulse(1.03)
        self.currentContactIndex += 1
        Answers.logCustomEvent(withName: "QuickInvite", customAttributes: ["Option": "Skip"])
    }

    @IBAction func inviteTapped(_ sender: AnyObject) {
        self.delegate.didReceiveFocus(self)

        let contact = self.delegate.contactsToInvite[self.currentContactIndex]
        self.delegate.invite(contact)

        // Feedback on pulse button
        self.inviteButton.pulse(1.05)

        // Shoot the "reward" emoji straight up
        let rewardLabel = UILabel()
        rewardLabel.frame = self.inviteButton.bounds
        rewardLabel.textAlignment = .center
        rewardLabel.font = UIFont.rogerFontOfSize(25)
        rewardLabel.text = self.celebrationEmoji[Int(arc4random_uniform(UInt32(self.celebrationEmoji.count)))]
        self.inviteButton.insertSubview(rewardLabel, at: 0)
        UIView.animate(withDuration: 0.2, delay: 0.0, options: .curveEaseOut, animations: {
            rewardLabel.transform = CGAffineTransform.identity.translatedBy(x: 0.0, y: -70)
            }) { _ in
                UIView.animate(withDuration: 0.2, delay: 0.05, options: .curveEaseIn, animations: {
                    //self.rewardLabel.alpha = 0
                    rewardLabel.transform = CGAffineTransform.identity
                    }, completion: { _ in
                        rewardLabel.removeFromSuperview()
                })
        }
        self.refresh()
        Answers.logCustomEvent(withName: "QuickInvite", customAttributes: ["Option": "Invite"])
    }

    @IBAction func closeTapped(_ sender: AnyObject) {
        self.delegate.dismissInvite()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.delegate.didReceiveFocus(self)
        super.touchesBegan(touches, with: event)
    }

    fileprivate func refresh() {
        guard ContactService.shared.authorized else {
            self.findFriendsButton.isHidden = false
            self.inviteUserLabel.isHidden = true
            self.inviteOptionsView.isHidden = true
            self.allDoneLabel.isHidden = true
            return
        }

        guard
            let delegate = self.delegate,
            self.currentContactIndex < delegate.contactsToInvite.count
        else {
            self.inviteUserLabel.isHidden = true
            self.inviteOptionsView.isHidden = true
            self.findFriendsButton.isHidden = true
            self.allDoneLabel.isHidden = false
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.allDoneLabel);
            self.allDoneLabel.pulse(1.1)
            return
        }

        if self.currentContactIndex == 0 {
            self.previousButton.isHidden = true
        } else {
            self.previousButton.isHidden = false
            let previousContact = self.delegate.contactsToInvite[self.currentContactIndex - 1]
            self.previousButton.accessibilityLabel = String.localizedStringWithFormat(
                NSLocalizedString("Back to %@", comment: "Quick Invite option"), previousContact.name)
        }

        let contact = self.delegate.contactsToInvite[self.currentContactIndex]
        self.skipButton.accessibilityLabel = String.localizedStringWithFormat(
            NSLocalizedString("Skip %@", comment: "Quick Invite option"), contact.name)
        self.inviteButton.accessibilityLabel = String.localizedStringWithFormat(
            NSLocalizedString("Add %@", comment: "Quick Invite option"), contact.name)
        self.findFriendsButton.isHidden = true
        self.allDoneLabel.isHidden = true
        self.inviteUserLabel.isHidden = false
        self.inviteOptionsView.isHidden = false

        self.inviteUserLabel.pulse(1.01)

        let sentence = NSLocalizedString("%1$@ Invite %2$@\nto this conversation!", comment: "Quick invite header")
        let attributedText = NSMutableAttributedString(string: sentence, attributes: [
            NSForegroundColorAttributeName: UIColor.lightGray,
            ])
        attributedText.replaceCharacters(
            in: (attributedText.string as NSString).range(of: "%1$@", options: .literal),
            with: self.contactEmoji[Int(arc4random_uniform(UInt32(self.contactEmoji.count)))])
        attributedText.replaceCharacters(
            in: (attributedText.string as NSString).range(of: "%2$@", options: .literal),
            with: NSAttributedString(string: contact.name, attributes: [
            NSForegroundColorAttributeName: UIColor.black,
            ])
        )
        self.inviteUserLabel.attributedText = attributedText
    }

    fileprivate func handleContactsChanged() {
        self.refresh()
    }

    fileprivate var currentContactIndex = 0 {
        didSet {
            self.refresh()
        }
    }

    fileprivate let contactEmoji = ["😋", "😀", "😁", "😮", "☺️", "🙃", "😛", "😊", "😎", "🐔", "😜", "😉", "😆", "👶" ]
    fileprivate let celebrationEmoji = ["🎉", "🙌", "👏", "✌️", "👍", "🤘", "💪", "👌"]
}
