import UIKit

class Pulser {
    /// The initial color of the pulse, before it starts fading out.
    let color: UIColor
    /// How long (in seconds) the pulse should take from start to finish.
    let duration: TimeInterval
    /// The scale of the pulse when it's at its largest.
    let finalScale: CGFloat
    /// The width of the stroke that makes up the pulse.
    let strokeWidth: CGFloat

    init(color: UIColor,
         duration: TimeInterval = 1.3,
         finalScale: CGFloat = 1.5,
         strokeWidth: CGFloat = 3)
    {
        self.color = color
        self.duration = duration
        self.finalScale = finalScale
        self.strokeWidth = strokeWidth
    }

    deinit {
        self.stop()
    }

    /// Starts the pulse effect. The pulse will be placed centered as the bottom layer in the provided view.
    func start(_ view: UIView, diameter: CGFloat? = nil, reversed: Bool = false) {
        let layer = self.initLayer()
        // Update the size and position of the layer.
        let diameter = diameter ?? view.frame.width
        let radius = diameter / 2
        let origin = CGPoint(x: view.bounds.midX - radius, y: view.bounds.midY - radius)
        layer.frame = CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))
        layer.cornerRadius = radius
        // Insert the layer if necessary.
        if layer.superlayer !== view.layer {
            self.stop()
            view.layer.insertSublayer(layer, at: 0)
        } else if self.reversed == reversed {
            // No change, so don't touch the layer or the animation.
            return
        }
        self.reversed = reversed
        // Create all the individual animations for the pulse effect.
        let scaleX = CABasicAnimation(keyPath: "transform.scale.x")
        scaleX.fromValue = reversed ? self.finalScale : 1
        scaleX.toValue = reversed ? 1 : self.finalScale
        let scaleY = CABasicAnimation(keyPath: "transform.scale.y")
        scaleY.fromValue = scaleX.fromValue
        scaleY.toValue = scaleX.toValue
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = reversed ? 0 : 1
        opacity.toValue = reversed ? 1 : 0
        // Manage the animations as a group.
        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [scaleX, scaleY, opacity]
        animationGroup.duration = self.duration
        animationGroup.repeatCount = Float.infinity
        animationGroup.timingFunction = CAMediaTimingFunction(name: reversed ? kCAMediaTimingFunctionEaseIn : kCAMediaTimingFunctionEaseOut)
        // Clear any previous animations and add the new one to the pulse layer.
        layer.removeAllAnimations()
        layer.add(animationGroup, forKey: Pulser.animationKey)
    }

    func stop() {
        guard let layer = self.layer , layer.superlayer != nil else {
            return
        }
        layer.removeAllAnimations()
        layer.removeFromSuperlayer()
    }

    // MARK: - Private

    static fileprivate let animationKey = "pulse"

    fileprivate var layer: CALayer!
    fileprivate var reversed: Bool = false

    fileprivate func initLayer() -> CALayer {
        if let layer = self.layer {
            return layer
        }
        let layer = CALayer()
        layer.borderColor = self.color.cgColor
        layer.borderWidth = CGFloat(self.strokeWidth)
        self.layer = layer
        return layer
    }
}
