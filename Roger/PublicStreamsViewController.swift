import UIKit

class PublicStreamsViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {

    @IBOutlet weak var publicStreamsCollectionView: UICollectionView!

    override func viewDidLoad() {
        self.publicStreamsCollectionView.delegate = self
        self.publicStreamsCollectionView.dataSource = self
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        self.view.addSubview(self.statusIndicatorView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        StreamService.instance.featuredChanged.addListener(self, method: PublicStreamsViewController.handleFeaturedChanged)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        StreamService.instance.featuredChanged.removeListener(self)
    }

    override var prefersStatusBarHidden : Bool {
        return true
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: IndexPath) -> CGSize {
        // Calculate width and height based on the device size + 16 px offsets on all sides
        // There should be 2 cells per row, so divide by 2
        let width = (collectionView.frame.width - 48) / 2
        let height = width / 0.7
        return CGSize(width: width, height: height)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.publicStreams.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let channel = self.publicStreams[(indexPath as NSIndexPath).row]

        // Populate the cell
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PublicStreamCell.reuseIdentifier, for: indexPath) as! PublicStreamCell
        if let url = channel.imageURL {
            cell.streamImageView.af_setImage(withURL: url)
        }
        cell.titleLabel.text = channel.title
        cell.memberCountLabel.text = String.localizedStringWithFormat(
            NSLocalizedString("%d Member(s)", comment: "Public Conversation member count"),
            channel.memberCount)
        cell.titleLabel.accessibilityLabel = "\(channel.title), \(cell.memberCountLabel.text)"
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        self.statusIndicatorView.showLoading()
        self.view.isUserInteractionEnabled = false
        StreamService.instance.joinGroup(inviteToken: self.publicStreams[(indexPath as NSIndexPath).row].inviteToken) { error in
            self.view.isUserInteractionEnabled = true
            self.statusIndicatorView.hide()
            guard error == nil else {
                return
            }
            self.navigationController?.popToRootViewControllerModal()
        }
    }

    @IBAction func backButton(_ sender: AnyObject) {
        self.navigationController?.popViewControllerModal()
    }

    // MARK: - Private

    private var statusIndicatorView: StatusIndicatorView!

    private var publicStreams: [PublicStream] {
        return StreamService.instance.featured
    }

    private func handleFeaturedChanged() {
        self.publicStreamsCollectionView.reloadData()
    }
}

class PublicStreamCell: UICollectionViewCell {
    static let reuseIdentifier = "publicStreamCell"
    @IBOutlet weak var streamImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var memberCountLabel: UILabel!
    @IBOutlet weak var containerView: UIView!

    override func layoutSubviews() {
        super.layoutSubviews()
        self.streamImageView.layer.cornerRadius = (self.frame.size.width - 36) / 2
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        animateScale(0.85)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        animateScale(1)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        animateScale(1)
    }

    override func prepareForReuse() {
        self.streamImageView.image = nil
        self.titleLabel.text = ""
        self.memberCountLabel.text = ""
    }

    // MARK: - Private

    private func animateScale(_ scale: CGFloat) {
        UIView.animate(withDuration: 0.6,
                                   delay: 0.0,
                                   usingSpringWithDamping: 0.3,
                                   initialSpringVelocity: 18,
                                   options: .allowUserInteraction,
                                   animations: {
                                    self.containerView.transform = scale == 1 ? CGAffineTransform.identity :
                                        CGAffineTransform(scaleX: 0.85, y: 0.85)
            },
                                   completion: nil
        )
    }
}
