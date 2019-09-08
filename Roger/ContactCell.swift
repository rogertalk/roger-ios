import UIKit

enum Mode { case selection, inspection }

class ContactCell: SeparatorCell {
    static let reuseIdentifier = "contactCell"

    @IBOutlet weak var avatarView: UIView!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var accountInfoLabel: UILabel!
    @IBOutlet weak var initialsLabel: UILabel!
    @IBOutlet weak var thumbnailImage: UIImageView!
    @IBOutlet weak var selectionToggleLabel: UILabel!
    @IBOutlet weak var loader: UIActivityIndicatorView!
    @IBOutlet weak var remindButton: MaterialButton!

    var mode: Mode = .inspection
    var selectable: Bool = true

    var contact: Contact? {
        didSet {
            self.refresh()
        }
    }

    // MARK: - Private

    fileprivate var activeCircle: UIView!
    fileprivate var activeCircleDot: UIView!

    // MARK: - UIView

    override func awakeFromNib() {
        super.awakeFromNib()
        self.selectionStyle = .none

        self.avatarView.layer.cornerRadius = self.avatarView.frame.width / 2
        self.avatarView.layer.borderColor = UIColor.lightGray.cgColor
        self.avatarView.layer.borderWidth = 1

        self.thumbnailImage.layer.cornerRadius = self.thumbnailImage.frame.width / 2

        // Active on Roger circle.
        let circleSize = 13.0
        let circleOrigin = self.avatarView.frame.origin
        let diagonalOffset = Double(self.avatarView.frame.width) * (1 + cos(M_PI / 4))
        let circleOffset = (diagonalOffset - circleSize) / 2 - 1
        let circleFrame = CGRect(x: circleOffset, y: circleOffset, width: circleSize, height: circleSize)
        self.activeCircle = UIView(frame: circleFrame.offsetBy(dx: circleOrigin.x, dy: circleOrigin.y))
        self.activeCircle.layer.backgroundColor = UIColor.white.cgColor
        self.activeCircle.layer.cornerRadius = CGFloat(circleSize / 2)
        self.addSubview(self.activeCircle)

        // Add the green dot inside the white circle.
        self.activeCircleDot = UIView(frame: self.activeCircle.bounds.insetBy(dx: 2.5, dy: 2.5))
        self.activeCircleDot.layer.backgroundColor = UIColor.rogerGreen?.cgColor
        self.activeCircleDot.layer.cornerRadius = self.activeCircleDot.frame.width / 2
        self.activeCircle.addSubview(self.activeCircleDot)
        self.activeCircle.isHidden = true
    }

    // MARK: - UITableViewCell

    override func prepareForReuse() {
        self.selectable = true
        self.thumbnailImage.af_cancelImageRequest()
        self.thumbnailImage.image = nil
        self.nameLabel.text = nil
        self.accountInfoLabel.text = nil
        self.accountInfoLabel.textColor = UIColor.lightGray
        self.selectionToggleLabel.isHidden = true
        self.selectionToggleLabel.text = "radio_button_unchecked"
        self.selectionToggleLabel.textColor = UIColor.lightGray
        self.loader.isHidden = true
        self.remindButton.isHidden = true
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        guard mode == .selection else {
            return
        }

        if !self.selectable {
            self.selectionToggleLabel.text = "radio_button_checked"
            self.selectionToggleLabel.textColor = UIColor.rogerGray
            return
        }

        // Show the appropriate icon depending on current state.
        if selected {
            self.selectionToggleLabel.text = "radio_button_checked"
            self.selectionToggleLabel.textColor = UIColor.rogerBlue
        } else {
            self.selectionToggleLabel.text = "radio_button_unchecked"
            self.selectionToggleLabel.textColor = UIColor.lightGray
        }
    }

    func refresh() {
        guard let contact = self.contact else {
            return
        }

        self.initialsLabel.text = contact.name.rogerInitials
        if let ownerName = (contact as? BotContact)?.ownerName {
            self.nameLabel.text = String.localizedStringWithFormat(
                NSLocalizedString("%1$@'s %2$@",
                    comment: "Specifies the owner of a service (i.e. John's Dropbox"),
                ownerName.rogerShortName, contact.name)
        } else {
            self.nameLabel.text = contact.name
        }

        let imageURL = (contact as? ProfileContact)?.imageURL ?? (contact as? AccountContact)?.imageURL
        if let imageURL = imageURL {
            self.thumbnailImage.af_setImage(withURL: imageURL, placeholderImage: AvatarView.singlePersonImage)
        } else {
            self.thumbnailImage.image = contact.image
        }

        self.accountInfoLabel.textColor = contact.active ? UIColor.rogerGreen : UIColor.lightGray
        self.accountInfoLabel.text = contact.description

        // Hide toggle for Conversation mode
        if self.mode == .inspection {
            self.selectionToggleLabel.isHidden = contact.active
            self.remindButton.isHidden = contact.active
        } else {
            self.selectionToggleLabel.isHidden = false
        }

        if contact is IdentifierContact {
            self.initialsLabel.text = "?"
            self.selectionToggleLabel.isHidden = true
        }
    }

    func flash() {
        self.backgroundColor = UIColor(white: 0.85, alpha: 1)
        UIView.animate(withDuration: 0.15, animations: {
            self.backgroundColor = UIColor.white
        }) 
        self.selectionToggleLabel.pulse()
    }
}
