import CoreLocation
import Crashlytics
import UIKit

class EnableGlimpsesViewController : UIViewController, CLLocationManagerDelegate {

    let locationManager = CLLocationManager()

    @IBOutlet weak var introContainerView: UIView!

    override func viewDidLoad() {
        self.view.backgroundColor = "fafafa".hexColor
        self.introContainerView.alpha = 0

        Responder.applicationActiveStateChanged.addListener(self, method: EnableGlimpsesViewController.handleApplicationActiveStateChanged)
    }

    override func viewDidAppear(_ animated: Bool) {
        UIView.animate(withDuration: 0.6, animations: {
            self.view.backgroundColor = UIColor.clear
            self.introContainerView.alpha = 1
        }) 
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    @IBAction func enableLocationTapped(_ sender: AnyObject) {
        // Enable glimpses location sharing on backend
        Intent.changeShareLocation(share: true).perform(BackendClient.instance) {
            if !$0.successful {
                NSLog("WARNING: Failed to enable location sharing")
            }
        }

        if SettingsManager.hasLocationPermissions {
            self.completeSetup()
            Answers.logCustomEvent(withName: "Onboarding Glimpses", customAttributes: ["Status": "AlreadyEnabled"])
        } else {
            if CLLocationManager.authorizationStatus() == .denied {
                let alert = UIAlertController(
                    title: NSLocalizedString("Enable Location", comment: "Alert title"),
                    message: NSLocalizedString("Permission to enable location for Weather must be granted via Settings->Roger.", comment: "Alert text"),
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("Okay", comment: "Alert action"), style: .default, handler: {
                    (action: UIAlertAction!) -> Void in
                    UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
                    Answers.logCustomEvent(withName: "User Sent To System Preferences", customAttributes: ["Reason": "Location", "Source": "Settings"])
                }))
                self.present(alert, animated: true, completion: nil)
                Answers.logCustomEvent(withName: "Alert", customAttributes: ["Source": "Settings", "Type": "EnableLocationError"])
            } else {
                self.locationManager.delegate = self
                self.locationManager.requestWhenInUseAuthorization()
            }
        }
    }

    @IBAction func turnOnLaterTapped(_ sender: AnyObject) {
        self.completeSetup()
        Answers.logCustomEvent(withName: "Onboarding Glimpses", customAttributes: ["Status": "Skipped"])
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Responder.updateLocation()
        self.completeSetup()
        Answers.logCustomEvent(withName: "Onboarding Glimpses", customAttributes: ["Status": String(describing: status)])
    }

    private func completeSetup() {
        self.dismiss(animated: true, completion: nil)
    }

    private func handleApplicationActiveStateChanged(_ active: Bool) {
        if active && SettingsManager.isGlimpsesEnabled {
            self.completeSetup()
        }
    }
}
