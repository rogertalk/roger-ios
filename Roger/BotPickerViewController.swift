import Crashlytics
import SafariServices

protocol BotPickerDelegate {
    func didFinishPickingBot(_ picker: BotPickerViewController, bot: Service)
}

class BotPickerViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {

    static func create(_ delegate: BotPickerDelegate) -> BotPickerViewController {
        let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "Bots")
            as! BotPickerViewController
        vc.delegate = delegate
        return vc
    }

    @IBOutlet weak var botsCollectionView: UICollectionView!

    override func viewDidLoad() {
        self.botsCollectionView.delegate = self
        self.botsCollectionView.dataSource = self
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        self.view.addSubview(self.statusIndicatorView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        StreamService.instance.botsChanged.addListener(self, method: BotPickerViewController.handleBotsChanged)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        StreamService.instance.botsChanged.removeListener(self)
    }

    override var prefersStatusBarHidden : Bool {
        return true
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: IndexPath) -> CGSize {
        // Calculate width and height based on the device size + 16 px offsets on all sides
        // There should be 2 cells per row, so divide by 2
        let width = (collectionView.frame.width - 48) / 2
        let height = width / 0.65
        return CGSize(width: width, height: height)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.bots.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let bot = self.bots[(indexPath as NSIndexPath).row]

        // Populate the cellbm
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BotCell.reuseIdentifier, for: indexPath) as! BotCell
        if let url = bot.imageURL {
            cell.botImageView.af_setImage(withURL: url)
        }
        cell.descriptionLabel.text = bot.description
        cell.titleLabel.text = bot.title
        cell.titleLabel.accessibilityLabel = "\(bot.title), \(cell.descriptionLabel.text)"
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let bot = self.bots[(indexPath as NSIndexPath).row]
        let pickBot = {
            if let url = bot.connectURL, url.absoluteString.contains("ifttt") {
                Intent.pingIFTTT().perform(BackendClient.instance)
            }
            guard bot.accountId != nil else {
                _ = self.navigationController?.popViewController(animated: true)
                return
            }
            self.delegate.didFinishPickingBot(self, bot: bot)
        }
        // Show connect UI in browser if the service is not connected.
        guard bot.connected else {
            guard let connectURL = bot.connectURL else {
                return
            }

            Responder.botSetupComplete.addListener(self, method: BotPickerViewController.handleBotSetupComplete)
            Responder.websiteNavigated.addListener(self, method: BotPickerViewController.handleRogertalkDotCom)

            self.safari = SFSafariViewController(url: connectURL)
            self.present(self.safari!, animated: true, completion: nil)
            return
        }
        pickBot()
    }

    @IBAction func backButton(_ sender: AnyObject) {
        _ = self.navigationController?.popViewController(animated: true)
    }

    // MARK: - Private

    fileprivate var delegate: BotPickerDelegate!
    fileprivate var statusIndicatorView: StatusIndicatorView!
    fileprivate var safari: UIViewController?

    fileprivate var bots: [Service] {
        return StreamService.instance.bots
    }

    fileprivate func handleBotsChanged() {
        self.botsCollectionView.reloadData()
    }

    fileprivate func handleBotSetupComplete(_ url: URL) {
        self.safari?.dismiss(animated: true, completion: nil)
        self.safari = nil
        Responder.websiteNavigated.removeListener(self)
    }

    private func handleRogertalkDotCom(url: URL) {
        guard let safari = self.safari else {
            return
        }
        // We need to do this to bypass Universal Link hijacking.
        safari.dismiss(animated: false, completion: nil)
        self.safari = SFSafariViewController(url: url)
        self.present(self.safari!, animated: false, completion: nil)
    }
}

class BotCell: UICollectionViewCell {
    static let reuseIdentifier = "botCell"

    @IBOutlet weak var botImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var containerView: UIView!

    override func layoutSubviews() {
        super.layoutSubviews()
        self.botImageView.layer.cornerRadius = (self.frame.size.width - 36) / 2
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
        self.botImageView.image = nil
        self.titleLabel.text = ""
        self.descriptionLabel.text = ""
    }

    // MARK: - Private

    fileprivate func animateScale(_ scale: CGFloat) {
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
