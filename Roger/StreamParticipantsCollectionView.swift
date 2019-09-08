import UIKit

class StreamParticipantsCollectionView: UICollectionView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.register(StreamParticipantCell.self, forCellWithReuseIdentifier: StreamParticipantCell.reuseIdentifier)
        self.register(ParticipantOverflowCell.self, forCellWithReuseIdentifier: ParticipantOverflowCell.reuseIdentifier)
        self.dataSource = self
        self.delegate = self
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return section == 0 ? -4 : 0
    }

    /// Diff the list of participants and animate any changes
    func setParticipants(_ participantsList: [Participant]) {
        self.totalParticipants = participantsList.count
//        let oldParticipants = self.participants
        self.participants = OrderedDictionary(participantsList.prefix(self.maxParticipants).map { ($0.id, $0) })

        // TODO: Have proper reload animations and update code
        self.reloadData()
//        // Reload all data if there are no prior participants
//        guard oldParticipants.count > 0 else {
//            self.performBatchUpdates({ self.reloadData() }, completion: nil)
//            return
//        }
//
//        let diff = oldParticipants.diff(self.participants)
//        guard !diff.deleted.isEmpty || !diff.inserted.isEmpty || !diff.moved.isEmpty else {
//            // The list of participants didn't change.
//            return
//        }
//
//        // Animate changes
//        self.performBatchUpdates(
//            {
//                self.deleteItemsAtIndexPaths(diff.deleted.map { NSIndexPath(forItem: $0, inSection: 0) })
//                self.insertItemsAtIndexPaths(diff.inserted.map { NSIndexPath(forItem: $0, inSection: 0) })
//                for (from, to) in diff.moved {
//                    self.moveItemAtIndexPath(NSIndexPath(forItem: from, inSection: 0), toIndexPath: NSIndexPath(forItem: to, inSection: 0))
//                }
//            },
//            completion: nil)
    }

    // MARK: - UICollectionViewDataSource

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return section == 0 ? min(self.participants.count, self.maxParticipants) : 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard (indexPath as NSIndexPath).section == 0 else {
            let cell = self.dequeueReusableCell(withReuseIdentifier: ParticipantOverflowCell.reuseIdentifier, for: indexPath) as! ParticipantOverflowCell
            cell.overflowCount = max(self.totalParticipants - self.maxParticipants, 0)
            return cell
        }

        let cell = self.dequeueReusableCell(withReuseIdentifier: StreamParticipantCell.reuseIdentifier, for: indexPath) as! StreamParticipantCell
        cell.participant = self.participants.values[(indexPath as NSIndexPath).row]
        return cell
    }

    // MARK: - UICollectionViewDelegateFlowLayout

    /// Set an inset relative to number of items to make the CollectionView right aligned
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let sectionInset: CGFloat = 8
        guard section == 0 else {
            return UIEdgeInsets(
                top: 20,
                left: sectionInset,
                bottom: 20,
                right: 0)
        }

        var contentWidth: CGFloat = 0
        for sectionIndex in 0..<self.numberOfSections {
            contentWidth += CGFloat(28 * self.numberOfItems(inSection: sectionIndex))
        }

        // Add 8 to account for inset in section 1
        let inset: CGFloat = self.frame.width - contentWidth - 16
        return UIEdgeInsets(top: 20, left: inset, bottom: 20, right: 0)
    }

    // MARK: - Private

    private let maxParticipants = 5
    private var participants = OrderedDictionary<Int64, Participant>()
    private var totalParticipants = 0
}

class StreamParticipantCell: UICollectionViewCell {
    fileprivate var avatarView: AvatarView!

    class var reuseIdentifier: String {
        return "streamParticipantCell"
    }

    var participant: Participant! {
        didSet {
            self.refresh()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.avatarView = AvatarView(frame: self.bounds)
        self.avatarView.layer.borderColor = UIColor.white.cgColor
        self.avatarView.layer.borderWidth = 1
        self.avatarView.setFont(UIFont.rogerFontOfSize(12))
        self.avatarView.setTextColor(UIColor.white)
        self.avatarView.hasDropShadow = false

        self.contentView.addSubview(self.avatarView)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    fileprivate func refresh() {
        self.avatarView.setText(self.participant.displayName.rogerInitials)
        if let url = self.participant.imageURL {
            self.avatarView.setImageWithURL(url)
        } else if let imageData = self.participant.contact?.imageData, let image = UIImage(data: imageData) {
            self.avatarView.setImage(image)
        }
    }

    override func prepareForReuse() {
        self.avatarView.setImage(nil)
    }
}

class ParticipantOverflowCell: StreamParticipantCell {
    var overflowCount = 0 {
        didSet {
            self.refresh()
        }
    }

    override class var reuseIdentifier: String {
        return "participantOverflowCell"
    }

    override fileprivate func refresh() {
        if self.overflowCount == 0 {
            self.avatarView.setFont(UIFont.materialFontOfSize(14))
            self.avatarView.setText("person_add")
        } else {
            self.avatarView.setFont(UIFont.rogerFontOfSize(10))
            self.avatarView.setText("+" + self.overflowCount.description)
        }
    }
}
