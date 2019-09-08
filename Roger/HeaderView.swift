import UIKit

class HeaderView: UIView {
    let gradient = CAGradientLayer()
    let line = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setUpLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setUpLayers()
    }

    override func layoutSubviews() {
        self.gradient.frame = self.bounds
        self.line.frame = CGRect(x: self.bounds.minX, y: self.bounds.maxY - 1, width: self.bounds.width, height: 1)
    }

    fileprivate func setUpLayers() {
        self.gradient.colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.1).cgColor]
        self.layer.addSublayer(self.gradient)
        self.line.backgroundColor = UIColor(white: 1, alpha: 0.1).cgColor
        self.layer.addSublayer(self.line)
    }
}
