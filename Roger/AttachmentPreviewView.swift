import UIKit

protocol AttachmentPreviewDelegate {
    func attachNew(_ preview: AttachmentPreviewView)
    func close(_ preview: AttachmentPreviewView)
}

class AttachmentPreviewView : UIView {

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var attachButton: UIButton!
    @IBOutlet weak var senderImageView: UIImageView!
    @IBOutlet weak var senderLabel: UILabel!
    @IBOutlet weak var imageHolderView: UIView!

    static func create(_ attachment: Attachment, stream: Stream, frame: CGRect, delegate: AttachmentPreviewDelegate) -> AttachmentPreviewView {
        let view = Bundle.main.loadNibNamed("AttachmentPreviewView", owner: self, options: nil)?[0] as! AttachmentPreviewView
        view.frame = frame
        view.stream = stream
        view.attachment = attachment
        view.delegate = delegate
        view.alpha = 0
        return view
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func awakeFromNib() {
        self.closeButton.titleLabel?.layer.shadowColor = UIColor.black.cgColor
        self.closeButton.titleLabel?.layer.shadowOffset = CGSize(width: 0, height: 1)
        self.closeButton.titleLabel?.layer.shadowOpacity = 0.8

        self.attachButton?.layer.shadowColor = UIColor.black.cgColor
        self.attachButton?.layer.shadowOffset = CGSize(width: 0, height: 1)
        self.attachButton?.layer.shadowOpacity = 0.6

        self.senderLabel?.layer.shadowColor = UIColor.black.cgColor
        self.senderLabel?.layer.shadowOffset = CGSize(width: 0, height: 1)
        self.senderLabel?.layer.shadowOpacity = 0.6

        self.imageHolderView?.layer.shadowColor = UIColor.black.cgColor
        self.imageHolderView?.layer.shadowOffset = CGSize(width: 0, height: 1)
        self.imageHolderView?.layer.shadowOpacity = 0.6

        let downSwipe = UISwipeGestureRecognizer(target: self, action: #selector(AttachmentPreviewView.handleSwipe(_:)))
        downSwipe.direction = .down
        self.addGestureRecognizer(downSwipe)
    }

    @IBAction func closeTapped(_ sender: AnyObject) {
        self.delegate.close(self)
    }

    @IBAction func shareNewTapped(_ sender: AnyObject) {
        self.delegate.attachNew(self)
    }

    override func showAnimated() {
        self.isHidden = false
        self.transform = CGAffineTransform.identity.scaledBy(x: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.2, animations: {
            self.transform = CGAffineTransform.identity
            self.alpha = 1
        }) 
    }

    override func hideAnimated(_ callback: (() -> Void)?) {
        UIView.animate(withDuration: 0.2, animations: {
            self.transform = CGAffineTransform.identity.scaledBy(x: 0.7, y: 0.7)
            self.alpha = 0
        }, completion: { success in
            self.isHidden = true
            callback?()
        }) 
    }

    private var stream: Stream?
    private var delegate: AttachmentPreviewDelegate!
    private var attachment: Attachment! {
        didSet {
            guard self.attachment.isImage else {
                return
            }
            if let image = self.attachment.image {
                self.imageView.image = image
            } else if let url = self.attachment.url {
                self.imageView.af_setImage(withURL: url)
            }
            if let senderId = self.attachment.senderId,
                let sender = self.stream?.getParticipant(senderId) {
                self.senderLabel.text = sender.displayName
                if let imageURL = sender.imageURL {
                    self.senderImageView.af_setImage(withURL: imageURL)
                }
            }
        }
    }

    dynamic private func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
        self.delegate.close(self)
    }
}
