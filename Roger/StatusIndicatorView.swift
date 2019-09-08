import UIKit

protocol StatusIndicatorViewDelegate {
    func stateChanged(_ statusIndiciatorView: StatusIndicatorView, visible: Bool)
}

class StatusIndicatorView: UIView {

    @IBOutlet weak var loader: UIActivityIndicatorView!
    @IBOutlet weak var confirmationLabel: UILabel!

    static func create(container: UIView, delegate: StatusIndicatorViewDelegate? = nil) -> StatusIndicatorView {
        let view = Bundle.main.loadNibNamed("StatusIndicatorView", owner: self, options: nil)?[0] as! StatusIndicatorView
        view.delegate = delegate
        view.frame.size = CGSize(width: 120,height: 120)
        view.center = container.center
        view.isHidden = true
        view.container = container
        return view
    }

    override func layoutSubviews() {
        self.center = self.container.center
        super.layoutSubviews()
    }

    func showConfirmation() {
        self.loader.stopAnimating()
        self.confirmationLabel.font = UIFont.materialFontOfSize(47)
        self.confirmationLabel.isHidden = false
        self.show(temporary: true)
    }

    func showLoading() {
        self.confirmationLabel.isHidden = true
        self.loader.startAnimating()
        self.show()
    }

    func showAutoplayStatus(_ on: Bool) {
        self.loader.stopAnimating()
        self.confirmationLabel.isHidden = false
        self.confirmationLabel.font = UIFont.rogerFontOfSize(18)
        self.frame.size = CGSize(width: 180, height: 120)
        self.confirmationLabel.numberOfLines = 2
        self.confirmationLabel.text = on ?
            NSLocalizedString("Live Playback On", comment: "Live mode status") :
            NSLocalizedString("Live Playback Off", comment: "Live mode status")
        self.frame.size = CGSize(width: 180, height: 120)
        self.show(temporary: true)
    }

    fileprivate func show(temporary: Bool = false) {
        self.delegate?.stateChanged(self, visible: true)
        self.isHidden = false
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 1
        }) 

        if temporary {
            // Automatically hide after a short delay
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(1400 * NSEC_PER_MSEC)) / Double(NSEC_PER_SEC)) {
                self.hide()
            }
        }
    }

    func hide() {
        self.delegate?.stateChanged(self, visible: false)
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
        }, completion: { success in
            self.loader.stopAnimating()
            self.confirmationLabel.isHidden = true
            self.isHidden = true
            self.frame.size = CGSize(width: 120, height: 120)
        }) 
    }

    fileprivate var delegate: StatusIndicatorViewDelegate?
    fileprivate var container: UIView!
}
