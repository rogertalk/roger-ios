import QuartzCore
import UIKit

private let avatarBackgroundColor = UIColor(white: 0.13, alpha: 1)
private let nameLabelTextColor = UIColor.lightGray
private let nameLabelTextColorSelected = UIColor.white

class RecentStreamCell: UICollectionViewCell {
    @IBOutlet weak var avatarView: AvatarView!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var noTimestampView: UIView!
    @IBOutlet weak var phantomOverlay: UIView!
    @IBOutlet weak var selectionView: UIView!
    @IBOutlet weak var statusIconLabel: UILabel!
    @IBOutlet weak var timestampLabel: UILabel!
    @IBOutlet weak var timestampLabelCenter: NSLayoutConstraint!

    var isCurrentlySelected: Bool = false {
        didSet {
            if oldValue == self.isCurrentlySelected {
                return
            }
            if self.isCurrentlySelected {
                self.selectionView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                UIView.animate(withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 0.4,
                    initialSpringVelocity: 6,
                    options: .allowUserInteraction,
                    animations: {
                        self.selectionView.transform = CGAffineTransform.identity
                    },
                    completion: nil)
            }
            self.refresh()
        }
    }

    var isTemporary = false {
        didSet {
            if oldValue == self.isTemporary {
                return
            }
            self.refresh()
        }
    }

    var stream: Stream! {
        didSet {
            if oldValue === self.stream {
                return
            }
            oldValue?.changed.removeListener(self)
            self.stream?.changed.addListener(self, method: RecentStreamCell.streamChanged)
            self.refresh()
        }
    }

    // MARK: -

    func refresh() {
        self.resetCell()

        if self.isCurrentlySelected {
            self.nameLabel.textColor = nameLabelTextColorSelected
            self.selectionView.isHidden = false
        }

        guard let stream = self.stream else {
            return
        }

        self.nameLabel.text = stream.shortTitle
        self.timestampLabel.text = stream.lastInteractionTime.rogerShortTimeLabel

        if stream.unplayed {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .spellOut
            let duration = AudioService.instance.getPlayDuration(stream)
            self.accessibilityLabel = String.localizedStringWithFormat(
                NSLocalizedString("%@, %@ unheard", comment: "VoiceOver label for recents: <Name>, <1 minute> unheard"),
                stream.displayName,
                formatter.string(from: ceil(duration))!)
        } else {
            self.accessibilityLabel = stream.displayName
        }

        if stream.status != .Idle && !self.isCurrentlySelected {
            self.pulser.start(self.avatarView, reversed: stream.status == .Listening)
        } else {
            self.pulser.stop()
        }

        // Display/hide the "replied" indicator and shift the timestamp as necessary.
        if stream.currentUserHasReplied {
            self.timestampLabelCenter.constant = 7
            // Toggle icon depending on if the audio has been heard.
            self.statusIconLabel.text = stream.othersListenedTime == nil ? "call_made" : "done"
            if let listenedTime = stream.othersListenedTime {
                self.accessibilityHint = String.localizedStringWithFormat(
                    NSLocalizedString("Listened %@", comment: "Accessibility hint; value is a relative time (Listened <an hour ago>)"),
                    listenedTime.rogerShortTimeLabelAccessible)
            } else {
                self.accessibilityHint = String.localizedStringWithFormat(
                    NSLocalizedString("You spoke %@", comment: "Accessibility hint; value is a relative time (You spoke <an hour ago>)"),
                    stream.lastInteractionTime.rogerShortTimeLabelAccessible)
            }
        } else if !stream.getPlayableChunks().isEmpty {
            self.timestampLabelCenter.constant = 0
            self.statusIconLabel.isHidden = true
            self.accessibilityHint = String.localizedStringWithFormat(
                NSLocalizedString("Spoke %@", comment: "Accessibility hint; value is a relative time (Spoke <an hour ago>)"),
                stream.lastInteractionTime.rogerShortTimeLabelAccessible)
        } else {
            self.timestampLabelCenter.constant = 0
            self.statusIconLabel.isHidden = true
            self.accessibilityHint = nil
        }

        if stream.unplayed {
            self.selectionView.layer.borderColor = UIColor.rogerBlue!.cgColor
            self.unplayedCircleDot.isHidden = false
            if self.isCurrentlySelected {
                self.shaker.stop()
            } else {
                self.shaker.start(self.unplayedCircleDot)
            }
        } else {
            self.selectionView.layer.borderColor = UIColor.white.cgColor
            self.shaker.stop()
            self.unplayedCircleDot.isHidden = true
        }

        if self.isTemporary {
            self.statusIconLabel.isHidden = true
            self.timestampLabel.isHidden = true
            self.noTimestampView.isHidden = false
        }

        if let image = stream.image {
            self.avatarView.setImage(image)
            self.phantomOverlay.isHidden = !self.isTemporary
        } else if stream.activeParticipants.count == 0 {
            self.avatarView.setFont(UIFont.rogerFontOfSize(40))
            self.avatarView.setText("🎉")
        } else if stream.reachableParticipants.count > 0 {
            self.avatarView.setImagesWithURLs(stream.memberImageURLs,
                                              avatarCount: stream.reachableParticipants.count)
        } else {
            self.avatarView.setImage(AvatarView.singlePersonImage)
        }

        if !SettingsManager.autoplayAll && stream.autoplay && stream.autoplayChangeable {
            self.unplayedCircleDot.isHidden = false
            self.unplayedCircleDot.backgroundColor = UIColor.black
        } else {
            self.unplayedCircleDot.backgroundColor = UIColor.rogerBlue
        }

        self.layoutIfNeeded()
    }

    func shakeAvatar() {
        self.avatarShaker.stop()
        self.avatarShaker.start(self.avatarView, repeats: false)
    }

    // MARK: - Event handlers

    func streamChanged() {
        self.refresh()
    }

    // MARK: - UIView

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        super.layoutIfNeeded()

        // Make the avatar round.
        self.avatarView.hasDropShadow = false
        self.avatarView.setFont(UIFont.rogerFontOfSize(28))
        self.avatarView.setTextColor(UIColor.white)
        self.phantomOverlay.layer.cornerRadius = self.phantomOverlay.frame.width / 2
        // Rounded corners on the selection box.
        self.selectionView.layer.cornerRadius = self.selectionView.frame.width / 2
        self.selectionView.layer.borderWidth = 2
        // Let the avatar render outside the container (when shaking).
        self.clipsToBounds = false
        // Enable accessibility.
        self.isAccessibilityElement = true
        // Create the little circle that shows up for unplayed streams.
        let circleSize = 15.0
        let diagonalOffset = Double(self.selectionView.frame.width) * (1 + cos(M_PI / 4))
        let circleOffset = (diagonalOffset - circleSize) / 2 - 1
        let circleOrigin = self.selectionView.frame.origin
        let circleFrame = CGRect(x: circleOffset, y: circleOffset, width: circleSize, height: circleSize)
        // Add the blue dot inside the white circle.
        self.unplayedCircleDot = UIView(frame: circleFrame.offsetBy(dx: circleOrigin.x, dy: circleOrigin.y))
        self.unplayedCircleDot.layer.backgroundColor = UIColor.rogerBlue!.cgColor
        self.unplayedCircleDot.layer.cornerRadius = self.unplayedCircleDot.frame.width / 2
        self.unplayedCircleDot.layer.borderWidth = 2
        self.unplayedCircleDot.layer.borderColor = UIColor.white.cgColor
        self.addSubview(self.unplayedCircleDot)
        // Set up dynamic styles for the first time.
        self.resetCell()
    }

    // MARK: - UICollectionReusableView

    override func prepareForReuse() {
        super.prepareForReuse()
        self.isCurrentlySelected = false
        self.isTemporary = false
        self.resetCell()
    }

    // MARK: - Private

    fileprivate static let newConversationImage = UIImage(named: "newConversationIcon")

    fileprivate let pulser = Pulser(color: UIColor.rogerBlue!, duration: 1, finalScale: 1.15, strokeWidth: 2)
    fileprivate let shaker = Shaker(distance: 1.5, duration: 1, shakes: 8)
    fileprivate let avatarShaker = Shaker(distance: 4, duration: 0.5)
    fileprivate var toggleShakeTimer: Timer?
    fileprivate var unplayedCircleDot: UIView!

    fileprivate func resetCell() {
        self.avatarView.setImage(nil)
        self.nameLabel.textColor = nameLabelTextColor
        self.nameLabel.textColor = nameLabelTextColor
        self.noTimestampView.isHidden = true
        self.phantomOverlay.isHidden = true
        self.selectionView.isHidden = true
        self.selectionView.layer.borderColor = UIColor.white.cgColor
        self.shaker.stop()
        self.unplayedCircleDot.isHidden = true
        self.shaker.stop()
        self.avatarShaker.stop()
        self.statusIconLabel.isHidden = false
        self.timestampLabel.isHidden = false
    }
}
