import Alamofire
import UIKit

class NetworkMonitor: NSObject {

    var networkIssueView: NetworkIssueView
    var refreshedStreams: Bool = false

    var issueText: String = NSLocalizedString("Connecting", comment: "Network connectivity bar") {
        didSet {
            self.networkIssueView.statusLabel.text = self.issueText
        }
    }

    init(container: UIView) {
        self.networkIssueView = NetworkIssueView.create(container)
        super.init()

        // Monitor the app's active state (whether it's in focus).
        Responder.applicationActiveStateChanged.addListener(self, method: NetworkMonitor.handleAppStateChange)

        // Listen for streams changed events to detect when the app has refreshed.
        StreamService.instance.changed.addListener(self, method: NetworkMonitor.handleStreamsChanged)

        // Monitor for changes to network status.
        self.manager?.listener = { status in
            if status != .notReachable {
                StreamService.instance.loadStreams()
            }
            self.update()
        }
        self.manager?.startListening()
    }

    func showNetworkIssueView() {
        self.networkIssueView.shouldShow = true
    }

    /// Attempt to establish a connection and update data
    func reconnect() {
        StreamService.instance.loadStreams()
    }

    // MARK: - Private

    fileprivate var showIssueViewTimer: Timer?
    fileprivate var reconnectTimer: Timer?

    fileprivate func handleAppStateChange(_ active: Bool) {
        if !active {
            // When the app becomes inactive, indicate that streams need to be refreshed.
            self.refreshedStreams = false
        } else {
            self.update()
        }
    }

    fileprivate func handleStreamsChanged() {
        self.refreshedStreams = true
        self.update()
    }

    fileprivate func update() {
        var shouldShowNetworkIssueView = true
        var secondsToWait = 0.0
        defer {
            if shouldShowNetworkIssueView {
                if !(self.showIssueViewTimer?.isValid ?? false) {
                    self.showIssueViewTimer = Timer(fireAt: Date().addingTimeInterval(secondsToWait), interval: 0, target: self, selector: #selector(NetworkMonitor.showNetworkIssueView), userInfo: true, repeats: false)
                    RunLoop.current.add(self.showIssueViewTimer!, forMode: RunLoopMode.commonModes)
                }
            } else {
                self.showIssueViewTimer?.invalidate()
                self.showIssueViewTimer = nil
                self.networkIssueView.shouldShow = false
            }
        }

        guard let _ = BackendClient.instance.session else {
            shouldShowNetworkIssueView = false
            return
        }

        if self.manager?.isReachable == false {
            self.issueText = NSLocalizedString("You can still talk while offline", comment: "Network connectivity bar")
            self.networkIssueView.activityIndicator.stopAnimating()
            secondsToWait = 0.0
        } else if !self.refreshedStreams {
            self.issueText = NSLocalizedString("Connecting", comment: "Network connectivity bar")
            self.networkIssueView.activityIndicator.startAnimating()
            // Keep trying to connect every 5 seconds while the app is active.
            self.reconnectTimer?.invalidate()
            self.reconnectTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(NetworkMonitor.reconnect), userInfo: nil, repeats: true)
            secondsToWait = 2.5
        } else {
            // We've established connection, so stop the reconnect timer.
            self.reconnectTimer?.invalidate()
            self.reconnectTimer = nil
            shouldShowNetworkIssueView = false
        }
    }

    private let manager = NetworkReachabilityManager()
}

class NetworkIssueView : UIView {
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!

    fileprivate var showDate: Date?

    static func create(_ container: UIView) -> NetworkIssueView {
        let view = Bundle.main.loadNibNamed("NetworkIssueView", owner: nil, options: nil)?[0] as! NetworkIssueView
        container.addSubview(view)
        view.frame = CGRect(x: 0, y: -50, width: container.frame.width, height: 50)
        view.autoresizingMask = .flexibleWidth
        view.isHidden = true
        return view
    }

    var shouldShow: Bool = false {
        didSet {
            if oldValue == self.shouldShow {
                return
            }

            // Do not allow changes until at least 1 second has passed in the "show" state.
            if let date = self.showDate , (date as NSDate).secondsAgo() < 1 {
                return
            }

            if self.shouldShow {
                self.showDate = Date()
                self.show()
                // Start the timer to ensure it is in the "show" state for at least a second
                Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(NetworkIssueView.update), userInfo: nil, repeats: false)
            } else {
                self.hide()
            }
        }
    }

    func update() {
        if self.shouldShow {
            self.show()
        } else {
            self.hide()
        }
    }

    fileprivate func show() {
        self.superview?.bringSubview(toFront: self)
        self.isHidden = false
        UIView.animate(withDuration: 0.2, animations: {
            self.frame.origin = CGPoint(x: 0, y: 0)
        }) 
    }

    fileprivate func hide() {
        UIView.animate(withDuration: 0.2, animations: {
            self.frame.origin = CGPoint(x: 0, y: -self.frame.size.height)
            }, completion: { success in
                self.isHidden = true
        })
    }
}
