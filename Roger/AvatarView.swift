import AlamofireImage

protocol AvatarViewDelegate {
    func accessibilityFocusChanged(_ avatarView: AvatarView, focused: Bool)
    func didEndTouch(_ avatarView: AvatarView)
}

class AvatarView: UIView {
    static let singlePersonImage = UIImage(named: "single")!

    var delegate: AvatarViewDelegate?
    var shouldAnimate = true

    var hasDropShadow: Bool = true {
        didSet {
            self.refreshDropShadow()
        }
    }

    func setAvatarBackgroundColor(_ color: UIColor) {
        self.button.backgroundColor = color
    }

    func setFont(_ font: UIFont) {
        self.button.titleLabel!.font = font
    }

    func setImage(_ image: UIImage?) {
        self.button.setTitle(nil, for: .normal)
        self.leftImageView.image = image
        self.avatarCount = 1
        self.layoutSubviews()
    }

    func setImageWithURL(_ url: URL) {
        self.setImagesWithURLs([url], avatarCount: 1)
    }

    private var avatarCount: Int = 0

    func setImagesWithURLs(_ urls: [URL], avatarCount: Int) {
        self.avatarCount = avatarCount

        if urls.count > 0 {
            self.leftImageView.af_setImage(withURL: urls[0])
        }

        if urls.count == 2 {
            self.rightTopImageView.af_setImage(withURL: urls[1])
        } else if urls.count > 2 {
            self.rightTopImageView.af_setImage(withURL: urls[1])
            self.rightBottomImageView.af_setImage(withURL: urls[2])
        }
        self.layoutSubviews()
    }

    func setText(_ text: String?) {
        self.button.contentHorizontalAlignment = .center
        self.leftImageView.image = nil
        self.button.setTitle(text, for: .normal)
    }

    func setTextColor(_ color: UIColor) {
        self.button.setTitleColor(color, for: .normal)
    }

    // MARK: - UIAccessibityFocus

    override func accessibilityElementDidBecomeFocused() {
        self.delegate?.accessibilityFocusChanged(self, focused: true)
    }

    override func accessibilityElementDidLoseFocus() {
        self.delegate?.accessibilityFocusChanged(self, focused: false)
    }

    // MARK: - UIView

    required override init(frame: CGRect) {
        super.init(frame: frame)
        self.initialize()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.initialize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.refreshDropShadow()

        self.button.frame = self.bounds
        self.button.layer.cornerRadius = self.button.frame.width / 2
        let halfWidth = self.button.bounds.width / 2
        let halfHeight = self.button.bounds.height / 2

        guard self.avatarCount > 0 else {
            self.leftImageView.isHidden = true
            self.rightTopImageView.isHidden = true
            self.rightBottomImageView.isHidden = true
            return
        }

        self.leftImageView.isHidden = false
        guard self.avatarCount > 1 else {
            self.leftImageView.frame = CGRect(x: -2, y: -2, width: self.bounds.width + 4, height: self.bounds.height + 4)
            self.rightTopImageView.isHidden = true
            self.rightBottomImageView.isHidden = true
            return
        }

        self.leftImageView.frame = CGRect(x: -2, y: -2, width: halfWidth + 4, height: self.bounds.height + 4)
        self.rightTopImageView.isHidden = false
        guard self.avatarCount > 2 else {
            self.rightTopImageView.frame = CGRect(x: halfWidth, y: -2, width: halfWidth + 2, height: self.button.bounds.height + 4)
            self.rightBottomImageView.isHidden = true
            return
        }

        self.rightBottomImageView.isHidden = false
        self.rightTopImageView.frame = CGRect(x: halfWidth, y: -2, width: halfWidth + 2, height: halfHeight + 4)
        self.rightBottomImageView.frame = CGRect(x: halfWidth, y: halfHeight, width: halfWidth + 2, height: halfHeight + 4)
    }

    // MARK: - UIResponder

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard self.shouldAnimate else {
            return
        }

        // Make the avatar shrink while it's being touched.
        UIView.animate(withDuration: 0.6,
            delay: 0.0,
            usingSpringWithDamping: 0.3,
            initialSpringVelocity: 18,
            options: .allowUserInteraction,
            animations: {
                self.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            },
            completion: nil
        )
        self.layer.shadowOpacity = 0.1
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        // Restore the avatar size when touches end.
        UIView.animate(withDuration: 0.6,
            delay: 0.0,
            usingSpringWithDamping: 0.3,
            initialSpringVelocity: 18,
            options: .allowUserInteraction,
            animations: {
                self.transform = CGAffineTransform.identity
            },
            completion: nil
        )
        self.layer.shadowOpacity = 0.4
        self.delegate?.didEndTouch(self)
    }

    func startSpin() {
        guard self.button.layer.animation(forKey: "rotation") == nil else {
            return
        }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = NSNumber(value: Float(M_PI * 2.0) as Float)
        rotation.duration = 1
        rotation.repeatCount = Float.infinity
        rotation.fillMode = kCAFillModeForwards
        rotation.isRemovedOnCompletion = false
        self.button.layer.add(rotation, forKey: "rotation")
    }

    func stopSpin() {
        guard let layer = self.button.layer.presentation() , self.button.layer.animation(forKey: "rotation") != nil else {
            return
        }
        self.button.layer.transform = layer.transform
        self.button.layer.removeAnimation(forKey: "rotation")
        UIView.animate(withDuration: 0.3, animations: {
            self.button.transform = CGAffineTransform.identity
        }) 
    }

    // MARK: - Private
    
    private static var downloader = ImageDownloader()

    private var button: UIButton!
    private var leftImageView: UIImageView!
    private var rightTopImageView: UIImageView!
    private var rightBottomImageView: UIImageView!

    private func initialize() {
        self.button = UIButton(type: .custom)
        self.button.clipsToBounds = true
        self.button.isUserInteractionEnabled = false
        self.button.contentHorizontalAlignment = .center
        self.button.contentVerticalAlignment = .fill
        self.button.imageView!.contentMode = .center
        self.button.backgroundColor = UIColor.clear
        self.button.setTitleColor(UIColor.clear, for: .normal)
        self.button.titleLabel?.font = UIFont.rogerFontOfSize(36)
        self.button.titleLabel?.numberOfLines = 2
        self.button.titleLabel?.textAlignment = .center
        self.addSubview(self.button)

        // Setup group member image previews
        self.leftImageView = UIImageView(image: AvatarView.singlePersonImage)
        self.leftImageView.isHidden = true
        self.leftImageView.contentMode = .scaleAspectFill
        self.leftImageView.layer.borderColor = UIColor.white.cgColor
        self.leftImageView.layer.borderWidth = 1
        self.leftImageView.clipsToBounds = true
        self.button.addSubview(self.leftImageView)

        self.rightTopImageView = UIImageView(image: AvatarView.singlePersonImage)
        self.rightTopImageView.contentMode = .scaleAspectFill
        self.rightTopImageView.layer.borderColor = UIColor.white.cgColor
        self.rightTopImageView.layer.borderWidth = 1
        self.rightTopImageView.isHidden = true
        self.rightTopImageView.clipsToBounds = true
        self.button.addSubview(self.rightTopImageView)

        self.rightBottomImageView = UIImageView(image: AvatarView.singlePersonImage)
        self.rightBottomImageView.contentMode = .scaleAspectFill
        self.rightBottomImageView.layer.borderColor = UIColor.white.cgColor
        self.rightBottomImageView.layer.borderWidth = 1
        self.rightBottomImageView.isHidden = true
        self.rightBottomImageView.clipsToBounds = true
        self.button.addSubview(self.rightBottomImageView)

        self.layer.cornerRadius = self.frame.width / 2
    }

    private func refreshDropShadow() {
        if !self.hasDropShadow {
            self.layer.shadowOffset = CGSize(width: 0, height: 0)
            self.layer.shadowRadius = 0
            self.layer.shadowPath = nil
            return
        }
        // Drop shadow on the avatar.
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOffset = CGSize(width: 0, height: 2)
        self.layer.shadowOpacity = 0.4
        self.layer.shadowRadius = 2
        self.layer.shadowPath =
            UIBezierPath(roundedRect: self.bounds, cornerRadius: self.bounds.width / 2).cgPath
    }
}
