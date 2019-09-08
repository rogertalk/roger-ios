import Crashlytics
import UIKit

class AutoplayIndicatorView : UIView {

    @IBOutlet weak var autoplaySwitch: UISwitch!
    @IBOutlet weak var autoplayStatusLabel: UILabel!
    @IBOutlet weak var pulseView: UIView!
    var pulser: Pulser!

    static func create(container: UIView) -> AutoplayIndicatorView {
        let view = Bundle.main.loadNibNamed("AutoplayIndicatorView", owner: nil, options: nil)?[0] as! AutoplayIndicatorView
        view.frame = CGRect(x: 0, y: -170, width: container.frame.width, height: 220)
        view.autoresizingMask = .flexibleWidth
        return view
    }

    override func awakeFromNib() {
        self.pulser = Pulser(
            color: UIColor.rogerGreen!.withAlphaComponent(0.6),
            finalScale: 3,
            strokeWidth: 10)
        self.autoplaySwitch.isOn = SettingsManager.autoplayAll
        self.refresh()
    }

    @IBAction func autoplaySwitchValueChanged(_ sender: AnyObject) {
        SettingsManager.autoplayAll = self.autoplaySwitch.isOn
        self.refresh()
        Answers.logCustomEvent(withName: "LivePlay Toggled", customAttributes: ["Status": SettingsManager.autoplayAll.description])
    }

    func show() {
        UIView.animate(withDuration: 0.3, animations: {
            self.transform = CGAffineTransform.identity.translatedBy(x: 0, y: 170)
        }, completion: { success in
            self.autoplaySwitch.setOn(true, animated: true)
            SettingsManager.autoplayAll = true
            self.refresh()
        }) 
    }

    func hide() {
        UIView.animate(withDuration: 0.3, animations: {
            self.transform = CGAffineTransform.identity
        }) 
    }

    func refresh() {
        guard SettingsManager.autoplayAll else {
            self.backgroundColor = UIColor.lightGray
            self.pulseView.backgroundColor = UIColor.lightGray
            self.pulser.stop()
            self.autoplayStatusLabel.text =
                NSLocalizedString("Tap for Walkie-Talkie mode", comment: "AutoPlay status indicator")
            return
        }

        self.pulseView.backgroundColor = UIColor.rogerGreen
        self.pulser.start(self.pulseView)
        self.backgroundColor = UIColor.black
        self.autoplayStatusLabel.text =
            NSLocalizedString("Walkie-Talkie on", comment: "AutoPlay status indicator")
    }
}
