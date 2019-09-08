import UIKit

class TooltipView: UIView {
    convenience init(text: String, centerView: UIView) {
        self.init()

        // Tooltips generally point at visual cues and shouldn't be "seen" by voice over. Instead, use accessibilityHint on relevant elements.
        self.accessibilityElementsHidden = true

        self.centerView = centerView
        self.clipsToBounds = false
        self.shapeLayer.fillColor = UIColor.black.withAlphaComponent(0.9).cgColor

        // The tooltip text.
        self.label = UILabel()
        self.label.font = UIFont.rogerFontOfSize(15)
        self.label.textAlignment = .center
        self.label.textColor = UIColor.white
        self.addSubview(self.label)
        self.setText(text)

        self.alpha = 0
    }

    func setText(_ text: String) {
        self.label.text = text
        self.frame.size = CGSize(width: self.label.intrinsicContentSize.width + 40, height: 30)
        self.label.frame.size = self.frame.size
        self.updatePath()
    }

    func show() {
        UIView.animate(withDuration: 0.3, animations: {
            self.alpha = 1
        }) 
    }

    func hide() {
        UIView.animate(withDuration: 0.3, animations: {
            self.alpha = 0
        }) 
    }

    // MARK: - UIView

    override class var layerClass : AnyClass {
        return CAShapeLayer.self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.center = CGPoint(x: self.centerView.center.x, y: self.centerView.frame.origin.y - 30)
    }

    // MARK: - Private

    fileprivate func updatePath() {
        let tipRadius = CGFloat(1.5)
        let tipSize = CGSize(width: 12, height: 6)

        // Calculate the three points in the tooltip arrow and round the tip.
        let left = CGPoint(x: self.bounds.midX - tipSize.width / 2, y: self.bounds.maxY),
            tip = CGPoint(x: self.bounds.midX, y: self.bounds.maxY + tipSize.height),
            right = CGPoint(x: self.bounds.midX + tipSize.width / 2, y: self.bounds.maxY)
        let (center, start, end) = roundedCornerWithLinesFrom(right, via: tip, to: left, radius: tipRadius)

        let path = UIBezierPath(roundedRect: self.bounds, cornerRadius: 6)
        path.move(to: right)
        path.addArc(withCenter: center, radius: tipRadius, startAngle: start, endAngle: end, clockwise: true)
        path.addLine(to: left)
        path.close()

        self.shapeLayer.path = path.cgPath
    }

    fileprivate var centerView: UIView!
    fileprivate var label: UILabel!
    fileprivate var shapeLayer: CAShapeLayer {
        return self.layer as! CAShapeLayer
    }
}

private func roundedCornerWithLinesFrom(_ from: CGPoint, via: CGPoint, to: CGPoint, radius: CGFloat) -> (center: CGPoint, startAngle: CGFloat, endAngle: CGFloat) {
    let fromAngle = atan2(via.y - from.y, via.x - from.x)
    let toAngle = atan2(to.y - via.y, to.x - via.x)

    let dx1 = -sin(fromAngle) * radius, dy1 = cos(fromAngle) * radius,
        dx2 = -sin(toAngle) * radius, dy2 = cos(toAngle) * radius

    let x1 = from.x + dx1, y1 = from.y + dy1,
        x2 = via.x + dx1, y2 = via.y + dy1,
        x3 = via.x + dx2, y3 = via.y + dy2,
        x4 = to.x + dx2, y4 = to.y + dy2

    let intersectionX = ((x1*y2-y1*x2)*(x3-x4) - (x1-x2)*(x3*y4-y3*x4)) / ((x1-x2)*(y3-y4) - (y1-y2)*(x3-x4))
    let intersectionY = ((x1*y2-y1*x2)*(y3-y4) - (y1-y2)*(x3*y4-y3*x4)) / ((x1-x2)*(y3-y4) - (y1-y2)*(x3-x4))
    return (CGPoint(x: intersectionX, y: intersectionY), fromAngle - CGFloat(M_PI_2), toAngle - CGFloat(M_PI_2))
}
