import UIKit

class HoverLabel: UILabel {
    override func layoutSubviews() {
        self.hover(true)
        super.layoutSubviews()
    }
}
