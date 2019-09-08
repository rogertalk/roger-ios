import UIKit

class MaterialView: UIView {
    let shadowRadius: CGFloat = 1.0
    let shadowOpacity: Float = 0.2
    let shadowOffset: CGSize = CGSize(width: 0, height: 2)

    override func layoutSubviews() {
        super.layoutSubviews()

        let bottomBorder = CALayer()
        bottomBorder.frame = CGRect(x: 0, y: self.frame.height, width: self.frame.width, height: 0.5)
        bottomBorder.backgroundColor = UIColor.lightGray.cgColor
        self.layer.addSublayer(bottomBorder)
    }
}
