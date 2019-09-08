import UIKit

class SidewaysTransition: NSObject, UIViewControllerTransitioningDelegate {
    static let instance = SidewaysTransition()

    class Animator: NSObject, UIViewControllerAnimatedTransitioning {
        let duration = 0.25

        func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
            return duration
        }

        func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
            let containerView = transitionContext.containerView
            let fromView = transitionContext.view(forKey: UITransitionContextViewKey.from)!
            let toView = transitionContext.view(forKey: UITransitionContextViewKey.to)!
            let width = UIScreen.main.bounds.width
            toView.frame = fromView.frame.offsetBy(dx: width, dy: 0)
            containerView.addSubview(toView)
            UIView.animate(withDuration: self.duration,
                delay: 0,
                options: [.curveEaseOut],
                animations: {
                    fromView.frame = fromView.frame.offsetBy(dx: -width, dy: 0)
                    toView.frame = toView.frame.offsetBy(dx: -width, dy: 0)
                },
                completion: { _ in
                    transitionContext.completeTransition(true)
                }
            )
        }
    }
    
    let animator = Animator()

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return self.animator
    }
}
