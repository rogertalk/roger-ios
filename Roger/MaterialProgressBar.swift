import UIKit

class MaterialProgressBar: UIView {

    var primaryColor: UIColor

    required init?(coder aDecoder: NSCoder) {
        self.primaryColor = UIColor.blue
        super.init(coder: aDecoder)
    }

    func startProgressAnimation() {
        if progressLayer != nil {
            return
        }

        CATransaction.begin()
        self.progressLayer = CALayer()
        self.progressLayer!.frame.size = CGSize(width: 100, height: self.bounds.size.height)

        // Default to blue if no color is provided
        self.progressLayer!.backgroundColor = self.primaryColor.cgColor

        // Progress animation
        let fromValue = NSValue(cgPoint: CGPoint(x: -self.progressLayer!.frame.size.width, y: self.bounds.size.height / 2))
        let toValue = NSValue(cgPoint: CGPoint(x: self.progressLayer!.frame.size.width / 2 + self.bounds.size.width, y: self.bounds.size.height / 2))

        let animation = CABasicAnimation(keyPath: "position")
        animation.beginTime = 0.0
        animation.fromValue = fromValue
        animation.toValue = toValue

        // TODO: Add additional animations for a more material design effect

        let group = CAAnimationGroup()
        group.animations = [animation]
        group.repeatCount = Float.infinity
        group.duration = 0.8

        self.progressLayer!.add(group, forKey: "progressAnimation")

        self.layer.addSublayer(self.progressLayer!)
        CATransaction.commit()
    }

    func stopProgressAnimation() {
        self.progressLayer?.removeFromSuperlayer()
        self.progressLayer = nil
    }

    fileprivate var progressLayer: CALayer?
}
