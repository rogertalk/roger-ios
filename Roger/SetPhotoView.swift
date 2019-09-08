import UIKit

protocol SetPhotoViewDelegate {
    func pickPhoto()
}

class SetPhotoView: UIView {
    var delegate: SetPhotoViewDelegate?

    override func awakeFromNib() {
        let color = self.backgroundColor
        self.backgroundColor = UIColor.clear
        self.layer.borderColor = color?.cgColor
        self.layer.borderWidth = 1

        // Placeholder text
        self.setPhotoLabel = UILabel(frame: self.bounds)
        self.setPhotoLabel.accessibilityLabel = NSLocalizedString("Add a photo", comment: "Text on top of empty avatar")
        self.setPhotoLabel.numberOfLines = 2
        self.setPhotoLabel.text = NSLocalizedString("ADD\nPHOTO", comment: "Text on top of empty avatar")
        self.setPhotoLabel.textAlignment = .center
        self.setPhotoLabel.font = UIFont.rogerFontOfSize(11)
        self.setPhotoLabel.textColor = color
        self.addSubview(self.setPhotoLabel)

        // Photo
        self.imageView = UIImageView(frame: self.bounds)
        self.imageView.clipsToBounds = true
        self.addSubview(self.imageView)

        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(SetPhotoView.setPhotoTapped)))
    }

    override func layoutSubviews() {
        self.layer.cornerRadius = self.frame.width / 2
        self.imageView.layer.cornerRadius = self.imageView.frame.width / 2
    }

    dynamic func setPhotoTapped() {
        self.delegate?.pickPhoto()
    }

    func setPhoto(_ image: UIImage) {
        self.imageView.image = image
    }

    fileprivate var imageView: UIImageView!
    fileprivate var setPhotoLabel: UILabel!
}
