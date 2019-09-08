import UIKit

class MaterialCircleView: UICollectionViewCell {
    var hasBorder = false
    var hasShadow = false

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layoutSubviews() {
        self.layer.cornerRadius = self.frame.width / 2
        if self.hasBorder {
            self.layer.borderWidth = 2
            self.layer.borderColor = UIColor.lightGray.withAlphaComponent(0.3).cgColor
        }

        // Drop shadow on the avatar.
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOffset = CGSize(width: 0, height: 2)
        self.layer.shadowOpacity = self.hasShadow ? 0.4 : 0.0
    }
}
