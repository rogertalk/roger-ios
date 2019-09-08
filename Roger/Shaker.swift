import UIKit

class Shaker: NSObject {
    static fileprivate let animationKey = "shaking"

    fileprivate var timer: Timer?
    fileprivate var view: UIView?

    /// The amount (in radians) that the shake can be angled from horizontal, in both directions.
    let angleVariance: Double
    /// The amount of distance that the view will move away from its center.
    let distance: Double
    /// How long (in seconds) the view should shake.
    let duration: Double
    /// How often (in seconds) that the shake will occur.
    let frequency: Double
    /// How many times the view should move back and forth for each shake.
    let shakes: Int

    init(distance: Double,
        duration: Double = 0.7,
        frequency: Double = 2,
        shakes: Int = 7,
        angleVariance: Double = 0.5) {
        self.angleVariance = angleVariance
        self.distance = distance
        self.duration = duration
        self.frequency = frequency
        self.shakes = shakes
    }

    deinit {
        self.stop()
    }

    func start(_ view: UIView, repeats: Bool = true) {
        if view === self.view {
            return
        }
        self.stop()
        self.timer = Timer.scheduledTimer(timeInterval: self.frequency, target: self, selector: #selector(Shaker.performShakeAnimation), userInfo: nil, repeats: repeats)
        self.view = view
        // Set off the first shake almost immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            self.timer?.fire()
        }
    }

    func stop() {
        guard let view = self.view else {
            return
        }
        view.layer.removeAnimation(forKey: Shaker.animationKey)
        if let timer = self.timer {
            timer.invalidate()
            self.timer = nil
        }
        self.view = nil
    }

    // MARK: - Private

    dynamic fileprivate func performShakeAnimation() {
        let animation = CABasicAnimation(keyPath: "position")
        animation.isAdditive = true
        animation.duration = self.duration / Double(self.shakes * 2)
        animation.repeatDuration = self.duration
        animation.autoreverses = true
        animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)

        // Shake at a random angle.
        let angle = self.angleVariance * (Double(arc4random()) / Double(UInt32.max) * 2 - 1)
        // Shake at the specified distance from the center.
        let dx = CGFloat(cos(angle) * self.distance)
        let dy = CGFloat(sin(angle) * self.distance)
        animation.fromValue = NSValue(cgPoint: CGPoint(x: -dx, y: -dy))
        animation.toValue = NSValue(cgPoint: CGPoint(x: dx, y: dy))

        self.view!.layer.add(animation, forKey: Shaker.animationKey)
    }
}
