import MMMaterialDesignSpinner

class MaterialButton: UIButton {
    fileprivate var spinner: MMMaterialDesignSpinner?

    @IBInspectable var cornerRadius: CGFloat = 23 {
        didSet {
            self.layer.cornerRadius = self.cornerRadius
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        super.layoutIfNeeded()

        self.setTitleColor(UIColor.clear, for: .disabled)

        self.layer.cornerRadius = self.cornerRadius

        // Drop shadow
        self.layer.shadowOffset = CGSize(width: 0, height: 0)
        self.layer.shadowRadius = 0
        self.layer.shadowOpacity = 0
    }

    func startLoadingAnimation() {
        self.isEnabled = false
        self.spinner = MMMaterialDesignSpinner(frame: CGRect(x: self.bounds.origin.x + 8, y: self.bounds.origin.y + 8, width: self.bounds.width - 16, height: self.bounds.height - 16))
        self.spinner?.backgroundColor = UIColor.clear
        self.spinner!.lineWidth = 2
        self.addSubview(self.spinner!)
        self.spinner!.startAnimating()
    }

    func stopLoadingAnimation() {
        self.isEnabled = true
        self.spinner?.removeFromSuperview()
        self.spinner = nil
    }
}
