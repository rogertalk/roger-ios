import UIKit

protocol RecentStreamsManager {
    var selectedStreamIndex: Int? { get }
    var streams: [Stream] { get }
    var temporaryStream: Stream? { get }

    func streamLongPressed(_ index: Int)
    func streamTapped(_ index: Int)
    func addTapped()
    func createPrimerStream(_ title: String)
}

class RecentStreamsCollectionView: UICollectionView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    /// The cell view for the currently selected stream (if any).
    var selectedCell: RecentStreamCell? {
        guard let indexPath = self.selectedStreamIndexPath else {
            return nil
        }
        return self.cellForItem(at: indexPath) as? RecentStreamCell
    }

    /// The index path of the currently selected stream (if any).
    var selectedStreamIndexPath: IndexPath? {
        if let index = self.streamsManager.selectedStreamIndex {
            return IndexPath(item: index, section: Section.Recents)
        } else if self.streamsManager.temporaryStream != nil {
            return IndexPath(item: 0, section: Section.TemporaryStream)
        }
        return nil
    }

    /// The object that manages the list of streams and which one is selected.
    var streamsManager: RecentStreamsManager!

    // MARK: -

    func applyDiff(_ diff: StreamService.StreamsDiff) {
        self.performBatchUpdates(
            {
                self.deleteItems(at: diff.deleted.map { IndexPath(item: $0, section: Section.Recents) })
                self.insertItems(at: diff.inserted.map { IndexPath(item: $0, section: Section.Recents) })
                for (from, to) in diff.moved {
                    self.moveItem(at: IndexPath(item: from, section: Section.Recents), to: IndexPath(item: to, section: Section.Recents))
                }
                self.reloadSections(IndexSet(integer: Section.Placeholders))
                self.reloadSections(IndexSet(integer: Section.Primers))
            },
            completion: { success in
                // Scroll to beginning if there was a change at the front.
                if diff.inserted.contains(where: { return $0 == 0 }) || diff.moved.contains(where: { return $0.to == 0 }) {
                    self.scrollToBeginningIfIdle()
                }
            }
        )
    }

    func updateTemporaryCell() {
        self.performBatchUpdates({
            self.reloadSections(IndexSet(integer: Section.TemporaryStream))
        }) { success in
            if self.streamsManager.temporaryStream != nil {
                self.scrollToItem(at: IndexPath(item: 0, section: Section.TemporaryStream), at: .centeredHorizontally, animated: false)
            }
        }
    }

    /// Reload data with animation. This does not make a backend request.
    func refresh() {
        self.performBatchUpdates({
            self.reloadSections(IndexSet(integer: Section.Recents))
            self.reloadSections(IndexSet(integer: Section.Primers))
            self.reloadSections(IndexSet(integer: Section.Placeholders))
        }, completion: nil)
    }

    func scrollToSelectedStream(_ animated: Bool = true) {
        guard let index = self.selectedStreamIndexPath , self.numberOfItems(inSection: (index as NSIndexPath).section) > 0 else {
            return
        }
        self.selectItem(at: index, animated: animated, scrollPosition: .centeredHorizontally)
    }

    func scrollToBeginningIfIdle() {
        guard let timestamp = self.lastTouchTimestamp , timestamp.timeIntervalSinceNow < -1 && self.streamsManager.streams.count > 0 else {
            return
        }
        self.scrollToItem(at: IndexPath(item: 0, section: Section.Recents), at: .centeredHorizontally, animated: true)
    }

    // MARK: - UICollectionViewDataSource

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 96, height: self.frame.height)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch section {
        case Section.Primers:
            return self.shouldShowPrimers ? self.primers.count : 0
        case Section.Placeholders:
            return self.streamsManager.streams.isEmpty ? 10 : 0
        case Section.Add:
            return 1
        case Section.TemporaryStream:
            return self.streamsManager.temporaryStream == nil ? 0 : 1
        case Section.Recents:
            return self.streamsManager.streams.count
        case Section.Loader:
            return self.isLoading ? 1 : 0
        default:
            return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        return self.dequeueReusableSupplementaryView(ofKind: UICollectionElementKindSectionFooter, withReuseIdentifier: "profileFooter", for: indexPath)
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 6
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch (indexPath as NSIndexPath).section {
        case Section.Primers:
            let primerCell = self.dequeueReusableCell(withReuseIdentifier: "primerCell", for: indexPath) as! PrimerCell
            switch self.primers[(indexPath as NSIndexPath).row] {
            case .friends:
                primerCell.primerImageView.image = RecentStreamsCollectionView.friendsPrimerImage
                primerCell.groupNameLabel.text = NSLocalizedString("Friends", comment: "Group Primer label")
                primerCell.accessibilityLabel = NSLocalizedString("Add Friends", comment: "Group Primer Label")
                primerCell.accessibilityHint = NSLocalizedString("Create a group for friends.", comment: "Group Primer Hint")
            case .family:
                primerCell.primerImageView.image = RecentStreamsCollectionView.familyPrimerImage
                primerCell.groupNameLabel.text = NSLocalizedString("Family", comment: "Group Primer label")
                primerCell.accessibilityLabel = NSLocalizedString("Add Family", comment: "Group Primer Label")
                primerCell.accessibilityHint = NSLocalizedString("Create a group for family.", comment: "Group Primer Hint")
            default:
                primerCell.primerImageView.image = RecentStreamsCollectionView.teamPrimerImage
                primerCell.groupNameLabel.text = NSLocalizedString("Team", comment: "Group Primer label")
                primerCell.accessibilityLabel = NSLocalizedString("Add Team", comment: "Group Primer Label")
                primerCell.accessibilityHint = NSLocalizedString("Create a group for a team.", comment: "Group Primer Hint")
            }
            return primerCell
        case Section.Placeholders:
            return self.dequeueReusableCell(withReuseIdentifier: "placeholderCell", for: indexPath)
        case Section.Add:
            let actionCell = self.dequeueReusableCell(withReuseIdentifier: "actionCell", for: indexPath) as! ActionCell
            actionCell.iconLabel.text = "add"
            actionCell.iconLabel.font = UIFont.materialFontOfSize(44)
            actionCell.iconLabel.textColor = UIColor.white
            actionCell.circleView.backgroundColor = UIColor.rogerBlue
            actionCell.circleView.hasBorder = false
            actionCell.descriptionLabel.text = NSLocalizedString("New", comment: "New conversation cell title")
            actionCell.accessibilityLabel = NSLocalizedString("Add Conversation", comment: "VoiceOver label for Add cell")
            actionCell.accessibilityHint = NSLocalizedString("Start a new conversation", comment: "VoiceOver hint for Add cell")
            actionCell.alertIcon.isHidden = true
            actionCell.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.addTapped)))
            return actionCell
        case Section.Loader:
            return self.dequeueReusableCell(withReuseIdentifier: "loaderCell", for: indexPath)
        default: // Recent stream cell
            let cell = self.dequeueReusableCell(withReuseIdentifier: "recentStreamCell", for: indexPath) as! RecentStreamCell
            if (indexPath as NSIndexPath).section == Section.TemporaryStream {
                cell.stream = self.streamsManager.temporaryStream
                cell.isTemporary = true
                cell.isCurrentlySelected = true
            } else {
                let stream = self.streamsManager.streams[(indexPath as NSIndexPath).item]
                cell.stream = stream
                cell.isCurrentlySelected = indexPath == self.selectedStreamIndexPath
            }
            cell.refresh()
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        guard let cell = self.cellForItem(at: indexPath), let circle = cell.viewWithTag(1) else {
            return
        }
        circle.isHidden = false
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let section = (indexPath as NSIndexPath).section
        if section == Section.Recents {
            self.streamsManager.streamTapped((indexPath as NSIndexPath).item)
            return
        }

        guard section == Section.Primers else {
            return
        }

        switch self.primers[(indexPath as NSIndexPath).row] {
        case .family:
            SettingsManager.didCreateFamilyGroup = true
            self.streamsManager.createPrimerStream(NSLocalizedString("Family", comment: "Stream primer"))
        case .friends:
            SettingsManager.didCreateFriendsGroup = true
            self.streamsManager.createPrimerStream(NSLocalizedString("Friends", comment: "Stream primer"))
        default:
            SettingsManager.didCreateTeamGroup = true
            self.streamsManager.createPrimerStream(NSLocalizedString("Team", comment: "Stream primer"))
        }
    }

    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        guard let cell = self.cellForItem(at: indexPath), let circle = cell.viewWithTag(1) else {
            return
        }
        circle.isHidden = true
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return (indexPath as NSIndexPath).section == Section.Recents || (indexPath as NSIndexPath).section == Section.Primers
    }

    // MARK: - UICollectionViewDelegateFlowLayout

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let inset: CGFloat = 10
        let flip = collectionView.layoutDirection == .rightToLeft
        switch section {
        case Section.Add:
            return UIEdgeInsets(top: 0, left: flip ? 0 : inset, bottom: 0, right: flip ? inset : 0)
        case Section.Primers:
            return UIEdgeInsets(top: 0, left: flip ? inset : 0, bottom: 0, right: flip ? 0 : inset)
        default:
            return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }
    }

    // MARK: - UIView

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.dataSource = self
        self.delegate = self
        self.delaysContentTouches = false
        // The collection view is currently too buggy for RTL.
        if #available(iOS 9.0, *) {
            self.semanticContentAttribute = .forceLeftToRight
        }
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(self.longPressed(_:)))
        self.addGestureRecognizer(recognizer)
        StreamService.instance.streamsEndReached.addListener(self, method: RecentStreamsCollectionView.handleStreamsEndReached)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !self.isLoading && StreamService.instance.nextPageCursor != nil else {
            return
        }
        let scrollViewWidth = scrollView.frame.size.width
        if scrollView.contentOffset.x > (scrollView.contentSize.width - scrollViewWidth * 1.5) {
            self.isLoading = true
            StreamService.instance.loadNextPage() { _ in
                self.isLoading = false
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        self.lastTouchTimestamp = Date()
    }

    // MARK: - Selector callbacks

    func addTapped() {
        self.streamsManager.addTapped()
    }

    func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state != .began {
            return
        }
        guard let indexPath = self.indexPathForItem(at: recognizer.location(in: self)) else {
            return
        }

        if (indexPath as NSIndexPath).section == Section.Recents {
            self.streamsManager.streamLongPressed((indexPath as NSIndexPath).item)
        }
    }

    // MARK: - Private

    fileprivate struct Section {
        static let Add = 0
        static let Placeholders = 1
        static let TemporaryStream = 2
        static let Recents = 3
        static let Loader = 4
        static let Primers = 5
    }

    fileprivate var lastTouchTimestamp: Date?
    fileprivate var longPressRecognizer: UILongPressGestureRecognizer?

    fileprivate var isLoading: Bool = false {
        didSet {
            self.performBatchUpdates({ self.reloadSections(IndexSet(integer: Section.Loader)) }, completion: nil)
        }
    }

    fileprivate func handleStreamsEndReached() {
        // TODO: Show something interesting at the end of the streams list
        self.shouldShowPrimers = true
    }

    fileprivate var shouldShowPrimers = false {
        didSet {
            self.performBatchUpdates({ self.reloadSections(IndexSet(integer: Section.Primers)) }, completion: nil)
        }
    }

    fileprivate enum Primer { case friends, family, team }
    fileprivate var primers: [Primer] {
        var primerList: [Primer] = []
        if !SettingsManager.didCreateFriendsGroup { primerList.append(.friends) }
        if !SettingsManager.didCreateFamilyGroup { primerList.append(.family) }
        if !SettingsManager.didCreateTeamGroup { primerList.append(.team) }
        return primerList
    }

    fileprivate static var friendsPrimerImage = UIImage(named: "friendsPrimerIcon")
    fileprivate static var familyPrimerImage = UIImage(named: "familyPrimerIcon")
    fileprivate static var teamPrimerImage = UIImage(named: "teamPrimerIcon")
}

class ActionCell: UICollectionViewCell {
    @IBOutlet weak var iconLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var alertIcon: UILabel!
    @IBOutlet weak var circleView: MaterialCircleView!

    override func awakeFromNib() {
        self.isAccessibilityElement = true
    }

    override func prepareForReuse() {
        self.gestureRecognizers?.removeAll()
    }
}

class PrimerCell: UICollectionViewCell {
    @IBOutlet weak var primerImageView: UIImageView!
    @IBOutlet weak var groupNameLabel: UILabel!

    override func awakeFromNib() {
        self.isAccessibilityElement = true
    }

    override func prepareForReuse() {
        self.primerImageView.image = nil
    }
}
