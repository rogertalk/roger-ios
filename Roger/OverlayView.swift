import UIKit

class OverlayView: UIView {

    @IBInspectable var overlayColor: UIColor!

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.initialize()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initialize()
    }

    override func awakeFromNib() {
        self.backgroundColor = self.overlayColor
    }

    /// Only allow touches within the hole to be registered
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let hole = self.holeFrame , hole.contains(point) else {
            return true
        }
        return false
    }

    /// Set up the "hole" in the overlay
    func setupOverlay(_ holeFrame: CGRect) {
        self.holeFrame = holeFrame
        let outerPath = UIBezierPath(rect: self.frame)
        let circlePath = UIBezierPath(ovalIn: holeFrame)
        outerPath.usesEvenOddFillRule = true
        outerPath.append(circlePath)
        let maskLayer = CAShapeLayer()
        maskLayer.path = outerPath.cgPath
        maskLayer.fillRule = kCAFillRuleEvenOdd
        maskLayer.fillColor = UIColor.white.cgColor
        self.layer.mask = maskLayer
    }
    
    fileprivate var holeFrame: CGRect?

    fileprivate func initialize() {
        self.isHidden = true
        self.alpha = 0
    }
}
