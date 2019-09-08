import Crashlytics
import SafariServices
import UIKit

class GetStartedViewController: UIViewController {

    @IBOutlet weak var streamCardContainerView: UIView!
    @IBOutlet weak var getStartedButton: MaterialButton!
    @IBOutlet weak var joinConversationView: UIView!

    // MARK: - UIViewController

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidAppear(_ animated: Bool) {
        ProximityMonitor.instance.changed.addListener(self, method: GetStartedViewController.handleProximityChange)
        ProximityMonitor.instance.active = true

        if let safari = self.safari {
            self.present(safari, animated: false, completion: nil)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        ProximityMonitor.instance.changed.removeListener(self)
        ProximityMonitor.instance.active = false
    }

    override func viewDidLoad() {
        self.view.backgroundColor = UIColor.clear

        // Listen to this event for deep linking
        Responder.openedByLink.addListener(self, method: GetStartedViewController.openedByLink)

        // Deep linking
        self.setupSafariViewController()
    }

    // MARK: - Actions

    @IBAction func termsAndConditionsTapped(_ sender: AnyObject) {
        let controller = self.storyboard!.instantiateViewController(withIdentifier: "EmbeddedBrowser") as! EmbeddedBrowserController
        controller.urlToLoad = SettingsManager.baseURL.appendingPathComponent("legal")
        controller.pageTitle = NSLocalizedString("Terms of Service", comment: "Browser title")
        self.present(controller, animated: true, completion: nil)
        Answers.logCustomEvent(withName: "Legal Page Shown", customAttributes: ["Source": "GetStarted"])
    }

    @IBAction func getStartedTapped(_ sender: AnyObject) {
        if let identifier = self.onboardingProfile?.identifier , identifier != "-1" {
            StreamsViewController.firstStreamParticipant = identifier
        }

        // Present the next setup page
        let vc = self.storyboard?.instantiateViewController(withIdentifier: BackendClient.instance.session == nil ? "Challenge" : "SetName")
        self.present(vc!, animated: true, completion: nil)
    }

    // MARK: - Private

    fileprivate var safari: UIViewController?
    fileprivate var closeSafariTimer: Timer?
    fileprivate let termsOfServiceURL = SettingsManager.baseURL.appendingPathComponent("legal")
    fileprivate var onboardingProfile: Profile?
    fileprivate var currentProfileCard: StreamCardView?

    fileprivate func displayOnboardingProfile(_ profile: Profile? = nil) {
        self.closeSafariTimer?.invalidate()

        let displayProfileCard: (Profile) -> Void = { profile in
            self.onboardingProfile = profile
            let card = StreamCardView.create(profile, frame: self.streamCardContainerView.frame, delegate: nil)
            if let previousCard = self.currentProfileCard {
                UIView.transition(from: previousCard, to: card, duration: 0.17, options: .transitionCrossDissolve) {
                    _ in
                    previousCard.destroy()
                }
            } else {
                // Insert the card at the bottom so it does not cover anything (i.e. the network issue view).
                self.streamCardContainerView.addSubview(card)
            }
            self.currentProfileCard = card
            if StreamsViewController.groupInviteToken != nil {
                self.getStartedButton.setTitle(
                    NSLocalizedString("Join", comment: "Onboarding get started button title"),
                    for: .normal)
            }
        }

        guard let profile = profile, !profile.isRogerProfile else {
            UIView.animate(withDuration: 0.4, animations: {
                self.joinConversationView.alpha = 1
            }) 
//            Intent.GetProfile(identifier: String(Profile.rogerAccountId)).perform(BackendClient.instance) {
//                result in
//                guard let data = result.data, profile = Profile(data) else {
//                    // TODO: Display something we cannot load any profile
//                    return
//                }
//
//                displayProfileCard(profile)
//            }
            return
        }

        displayProfileCard(profile)
    }

    // MARK: - Events

    private func handleProximityChange(_ againstEar: Bool) {
        guard case .idle = AudioService.instance.state , againstEar else {
            return
        }
        guard let profile = self.onboardingProfile else {
            return
        }
        AudioService.instance.playProfile(profile, reason: "RaisedToEar")
        SettingsManager.didListen = true
    }

    private func openedByLink(_ profile: Profile?, inviteToken: String?) {
        StreamsViewController.groupInviteToken = inviteToken
        self.displayOnboardingProfile(profile)
    }
}

extension GetStartedViewController: SFSafariViewControllerDelegate {

    func requestTimedOut() {
        self.closeSafariViewController()
        self.displayOnboardingProfile()
    }

    // MARK: SFSafariViewControllerDelegate

    func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
        self.closeSafariTimer?.invalidate()
        self.closeSafariViewController()
        if !didLoadSuccessfully {
            self.displayOnboardingProfile()
        }
    }

    // MARK: Private

    fileprivate func closeSafariViewController() {
        self.safari?.dismiss(animated: false, completion: nil)
        self.safari = nil
        self.toggleLoadingUI(false)
    }

    fileprivate func setupSafariViewController() {
        let safari = SafariViewController(url: URL(string: "https://rogertalk.com/?open_app=3")!)
        safari.delegate = self
        safari.modalPresentationStyle = .overCurrentContext
        safari.view.alpha = 0.0
        self.safari = safari

        self.toggleLoadingUI(true)
        self.closeSafariTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(GetStartedViewController.requestTimedOut), userInfo: nil, repeats: false)
    }

    fileprivate func toggleLoadingUI(_ isLoading: Bool) {
        if isLoading {
            self.getStartedButton.startLoadingAnimation()
        } else {
            self.getStartedButton.stopLoadingAnimation()
        }
    }
}

class SafariViewController: SFSafariViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}
