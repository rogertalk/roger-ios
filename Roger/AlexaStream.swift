import Foundation

class AlexaStream: Stream {
    override var autoplay: Bool {
        get {
            return true
        }
        set {}
    }

    override var autoplayChangeable: Bool {
        return false
    }

    override var callToAction: String? {
        return NSLocalizedString("“What’s the weather?”", comment: "Alexa's call to action tooltip")
    }

    override var canTalk: Bool {
        return self.connected
    }

    override var instructions: Instructions? {
        guard !self.connected else {
            return nil
        }
        return (
            NSLocalizedString("Alexa by Amazon", comment: "Alexa title"),
            NSLocalizedString("Connect to your Amazon account\nto start talking with Alexa.", comment: "Alexa instructions")
        )
    }

    override var instructionsAction: String? {
        return NSLocalizedString("Connect", comment: "Alexa instructions button")
    }

    override var statusText: String {
        if self.connected {
            return NSLocalizedString("Connected", comment: "Alexa connect status")
        } else {
            return NSLocalizedString("Not Connected", comment: "Alexa connect status")
        }
    }

    override func instructionsActionTapped() -> InstructionsActionResult {
        // TODO: This should be an access token or authorization code.
        let token = BackendClient.instance.session?.refreshToken ?? ""
        let url = URL(string: "https://rogertalk.com/auth/alexa?refresh_token=\(token)")!
        return .showWebView(title: NSLocalizedString("Connect to Alexa", comment: "Browser title"), url: url)
    }

    // MARK: - Private

    private var connected: Bool {
        // TODO: Do this properly.
        return true
    }
}
