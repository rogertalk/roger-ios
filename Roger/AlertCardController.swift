import UIKit

class AlertCardController: UIViewController {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var mainImageView: UIImageView!
    @IBOutlet weak var imageTopLayoutConstraint: NSLayoutConstraint!
    @IBOutlet weak var imageBottomLayoutConstraint: NSLayoutConstraint!

    var mainTitle: String?
    var subtitle: String?
    var icon: UIImage?
    var image: UIImage?
    var onClose: (() -> Void)?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        self.titleLabel.text = self.mainTitle
        self.descriptionLabel.text = self.subtitle
        self.iconImageView.image = self.icon
        self.mainImageView.image = self.image
        if self.image == nil {
            self.imageTopLayoutConstraint.constant = 10
            self.imageBottomLayoutConstraint.constant = 10
        }
    }

    @IBAction func confirmTapped(_ sender: AnyObject) {
        self.dismiss(animated: true) {
            self.onClose?()
        }
    }
}
