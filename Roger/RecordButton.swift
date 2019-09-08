import UIKit

protocol RecordButtonDelegate {
    func didTriggerAction()
    func didLongPressAction()
}

class RecordButtonView: UIView {
    var recordButton: UIButton!
    var audioVisualizerView: UIView!
    var delegate: RecordButtonDelegate?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        self.backgroundColor = UIColor.clear

        // Setup the actual record button.
        self.recordButton = UIButton()
        self.recordButton.adjustsImageWhenHighlighted = false
        self.recordButton.setImage(self.smileImage, for: .normal)
        self.recordButton.clipsToBounds = true
        self.recordButton.addTarget(self, action: #selector(RecordButtonView.recordTouchDown), for: .touchDown)
        self.recordButton.addTarget(self, action: #selector(RecordButtonView.recordTouchUpInside), for: .touchUpInside)
        self.recordButton.accessibilityTraits |= UIAccessibilityTraitButton
        self.recordButton.accessibilityTraits |= UIAccessibilityTraitPlaysSound
        self.recordButton.accessibilityTraits |= UIAccessibilityTraitStartsMediaSession
        self.addSubview(self.recordButton)

        // Add a disabled overlay indicator view
        self.disabledOverlay = UIView(frame: self.recordButton.bounds)
        self.disabledOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.6)
        self.recordButton.addSubview(self.disabledOverlay)

        self.recordButton.backgroundColor = UIColor.black

        // Set up the circle that visualizes recording sound.
        self.audioVisualizerView = UIView()
        self.audioVisualizerView.frame.size = CGSize(width: 130, height: 130)
        self.audioVisualizerView.center = self.center
        self.audioVisualizerView.isHidden = true
        self.audioVisualizerView.backgroundColor = UIColor.white.withAlphaComponent(0.4)
        self.audioVisualizerView.layer.cornerRadius = self.audioVisualizerView.frame.size.width / 2
        self.insertSubview(self.audioVisualizerView, belowSubview: self.recordButton)

        self.updateAccessibilityLabel()

        // Add audio listeners.
        AudioService.instance.stateChanged.addListener(self, method: RecordButtonView.handleAudioStateChange)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        super.layoutIfNeeded()

        // Add gradients for the record button smile background
        // This size and positioning ensures it covers the size of the smile
        let gradientRect = CGRect(x: 0, y: self.bounds.height / 2.8, width: self.bounds.width, height: self.bounds.height / 2.4)
        self.currentSkyGradient.frame = gradientRect
        self.currentSkyGradient.colors = rogerGradientColors
        self.recordButton.layer.insertSublayer(self.currentSkyGradient, below: self.recordButton.imageView?.layer)

        // Drop shadow
        self.layer.shadowColor = UIColor.black.withAlphaComponent(0.6).cgColor
        self.layer.shadowOffset = CGSize(width: 0, height: 8)
        self.layer.shadowOpacity = 0.2
        self.layer.shadowPath =
            UIBezierPath(roundedRect: self.bounds, cornerRadius: self.bounds.width / 2).cgPath
    }

    var once = false
    override func layoutSubviews() {
        super.layoutSubviews()

        self.layer.cornerRadius = self.frame.width / 2
        self.layer.shadowPath =
            UIBezierPath(roundedRect: self.bounds, cornerRadius: self.bounds.width / 2).cgPath

        self.recordButton.frame = self.bounds
        // Make the record button circular.
        self.recordButton.layer.cornerRadius = self.recordButton.frame.width / 2
        self.disabledOverlay.frame = self.recordButton.bounds
    }

    dynamic func updateAudioVisualizer() {
        let level = AudioService.instance.audioLevel
        let scale = CGFloat(1 + level / (pow(level, 0.5)))
        self.audioVisualizerView.transform = CGAffineTransform(scaleX: scale, y: scale)
        self.audioVisualizerView.center = self.recordButton.center
    }

    dynamic func setEnabled(_ enabled: Bool) {
        self.disabledOverlay.isUserInteractionEnabled = !enabled
        UIView.animate(withDuration: 0.2,
                                   delay: 0,
                                   options: .beginFromCurrentState,
                                   animations: {
                                    self.disabledOverlay.alpha = enabled ? 0 : 1
            }, completion: nil)
    }

    // MARK: - Actions

    dynamic func recordTouchDown() {
        defer {
            self.delegate?.didTriggerAction()
        }

        if case .recording = AudioService.instance.state {
            return
        }

        self.animateRecordButtonScale(0.8)
        self.longPressStartTimestamp = Date()
    }

    dynamic func recordTouchUpInside() {
        defer {
            self.longPressStartTimestamp = nil
        }

        guard let timestamp = self.longPressStartTimestamp , timestamp.timeIntervalSinceNow < -1 else {
            return
        }

        self.delegate?.didLongPressAction()
    }

    // MARK: - Private

    fileprivate let smileImage = UIImage(named: "smile")
    fileprivate let recordingSmileImage = UIImage(named: "recordingSmile")
    fileprivate let currentSkyGradient = CAGradientLayer()
    fileprivate var audioVisualizerUpdateTimer: CADisplayLink?
    fileprivate var longPressStartTimestamp: Date?
    fileprivate var disabledOverlay: UIView!

    fileprivate func handleAudioStateChange(_ oldState: AudioService.State) {
        self.updateAccessibilityLabel()

        let change = (oldState, AudioService.instance.state)
        switch change {
        case (.recording, _):
            // No longer recording.
            if let timer = self.audioVisualizerUpdateTimer {
                timer.invalidate()
                self.audioVisualizerUpdateTimer = nil
            }
            self.audioVisualizerView.isHidden = true
            self.recordButton.setImageWithAnimation(self.smileImage)
            self.animateRecordButtonScale(1)
        case (_, .recording):
            // Started recording.
            let timer = CADisplayLink(target: self, selector: #selector(RecordButtonView.updateAudioVisualizer))
            timer.add(to: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
            self.audioVisualizerUpdateTimer = timer
            self.audioVisualizerView.isHidden = false
            self.recordButton.setImageWithAnimation(self.recordingSmileImage)
        case (.playing, _):
            self.setEnabled(true)
        default:
            break
        }
    }

    fileprivate func updateAccessibilityLabel() {
        if case .recording = AudioService.instance.state {
            self.recordButton.accessibilityLabel = NSLocalizedString("Done", comment: "Accessibility label, microphone")
            self.recordButton.accessibilityHint = ""
        } else {
            self.recordButton.accessibilityLabel = NSLocalizedString("Microphone", comment: "Accessibility label, microphone")
            self.recordButton.accessibilityHint = NSLocalizedString("Starts recording, double tap again when done.", comment: "Accessibility hint, microphone")
        }
    }

    fileprivate func animateRecordButtonScale(_ scale: CGFloat) {
        UIView.animate(withDuration: 0.4, delay: 0,
            usingSpringWithDamping: 0.4,
            initialSpringVelocity: 18,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                self.transform = CGAffineTransform(scaleX: scale, y: scale)
            },
            completion: nil)
    }
}
