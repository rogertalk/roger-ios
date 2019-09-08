import Crashlytics
import MessageUI

/// A list of activity types that will only accept a URL.
private let linkOnlyActivityTypes = [
    UIActivityType.postToFacebook,
    UIActivityType(rawValue: "com.facebook.Messenger.ShareExtension"),
    UIActivityType(rawValue: "com.kik.chat.share-extension"),
    UIActivityType(rawValue: "com.skype.skype.sharingextension"),
    UIActivityType(rawValue: "com.tencent.xin.sharetimeline"),
    UIActivityType(rawValue: "ph.telegra.Telegraph.Share"),
]
private let linkRegex = try! NSRegularExpression(pattern: "https://rogertalk.com[^ ]*", options: [])

/// Takes a fallback value to be shared and a map values for specific activity types.
class DynamicActivityItem: NSObject, UIActivityItemSource {
    let activityTypeToValue: [UIActivityType: Any]
    let fallback: Any

    init(_ fallback: Any, specific: [UIActivityType: Any] = [:]) {
        self.activityTypeToValue = specific
        self.fallback = fallback
    }

    @objc func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return self.fallback
    }

    @objc func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivityType?) -> String {
        // This data type gets us the most possible share destinations.
        return "public.url"
    }

    @objc func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivityType) -> Any? {
        if let value = self.activityTypeToValue[activityType] {
            return value
        }
        guard linkOnlyActivityTypes.contains(activityType),
            let text = self.fallback as? NSString,
            let match = linkRegex.matches(in: text as String, options: [], range: NSMakeRange(0, text.length)).first,
            let url = URL(string: text.substring(with: match.range))
            else
        {
            return self.fallback
        }
        return url
    }
}

class Share {
    static func createMessageComposer(_ chunkToken: String? = nil, message: String? = nil, recipients: [String], delegate: MFMessageComposeViewControllerDelegate) -> MFMessageComposeViewController {
        let shareURL: URL
        let session = BackendClient.instance.session
        shareURL = (chunkToken == nil ? session?.profileURL : session?.profileURLWithChunkToken(chunkToken!)) ?? SettingsManager.baseURL

        let messageComposer = MFMessageComposeViewController()
        messageComposer.messageComposeDelegate = delegate
        messageComposer.recipients = recipients
        messageComposer.body = "\(message ?? NSLocalizedString("Talk with me on Roger!", comment: "Invite SMS"))\n\(shareURL)"
        return messageComposer
    }

    static func createGroupMessageComposer(_ groupInviteURL: URL?, recipients: [String], delegate: MFMessageComposeViewControllerDelegate) -> MFMessageComposeViewController {
        guard let inviteURL = groupInviteURL else {
            return self.createMessageComposer(recipients: recipients, delegate: delegate)
        }

        let messageComposer = MFMessageComposeViewController()
        messageComposer.recipients = recipients
        messageComposer.messageComposeDelegate = delegate
        messageComposer.body =
            String.localizedStringWithFormat(
                NSLocalizedString("I've added you to a group on the Roger app. Use this link to join our conversation! \n%@", comment: "Group invite message"),
                inviteURL.absoluteString)
        return messageComposer
    }

    static func createShareSheet(_ item: DynamicActivityItem, anchor: UIView, source: String, allowAirdrop: Bool = false, bubble: (String, String)? = nil, callback: ((Bool) -> Void)? = nil) -> UIActivityViewController {
        let vc = BubbleActivityViewController(activityItems: [item], applicationActivities: nil)
        vc.bubble = bubble
        // Provide an anchor for iPad.
        if let popoverPresenter = vc.popoverPresentationController {
            popoverPresenter.sourceView = anchor
            popoverPresenter.sourceRect = anchor.bounds.insetBy(dx: 0, dy: -5)
        }
        vc.excludedActivityTypes = [UIActivityType.addToReadingList]
        if !allowAirdrop {
            vc.excludedActivityTypes?.append(UIActivityType.airDrop)
        }
        // Assume that the share sheet is going to be shown.
        Answers.logCustomEvent(withName: "Share Sheet Shown", customAttributes: ["Source": source])
        // Log status when the share sheet is closed.
        vc.completionWithItemsHandler = { activityType, completed, _, _ in
            Answers.logCustomEvent(withName: completed ? "Share Complete" : "Share Cancelled", customAttributes: [
                "ActivityType": activityType?.rawValue ?? "Unknown",
                "Source": source,
            ])
            callback?(completed)
        }
        return vc
    }

    static func createShareSheetFallback(_ body: String?, name: String?, chunkURL: URL, anchor: UIView, source: String, bubble: (String, String)? = nil, callback: ((Bool) -> Void)? = nil) -> UIActivityViewController {
        let bubbleTitle: String
        let bubbleText: String
        if let bubble = bubble {
            bubbleTitle = bubble.0
            bubbleText = bubble.1
        } else {
            bubbleTitle = NSLocalizedString("Share voice link", comment: "Bubble above share sheet after SMS cancelled")
            if let name = name {
                bubbleText = String.localizedStringWithFormat(
                    NSLocalizedString("%@ can listen with it.", comment: "Bubble above share sheet after SMS cancelled"),
                    name)
            } else {
                bubbleText = NSLocalizedString("Your friend can listen with it.", comment: "Bubble above share sheet after SMS cancelled")
            }
        }

        return Share.createShareSheet(
            DynamicActivityItem(body ?? String.localizedStringWithFormat(
                NSLocalizedString("Talk with me on Roger! %@", comment: "Text for inviting a friend."),
                chunkURL as NSURL)),
            anchor: anchor,
            source: source,
            bubble: (
                bubbleTitle,
                bubbleText
            ),
            callback: callback
        )
    }

    static func createShareSheetOwnProfile(_ anchor: UIView, source: String, bubble: (String, String)? = nil, callback: ((Bool) -> Void)? = nil) -> UIActivityViewController {
        let url = BackendClient.instance.session?.profileURL ?? SettingsManager.baseURL
        return Share.createShareSheet(
            DynamicActivityItem(
                String.localizedStringWithFormat(
                    NSLocalizedString("Talk with me on Roger! %@", comment: "Share text for own profile."),
                    url as NSURL),
                specific: [
                    UIActivityType.postToTwitter: String.localizedStringWithFormat(
                        NSLocalizedString("Talk with me on Roger! %@ #TalkMore", comment: "Share text for own profile (Twitter)."),
                        url as NSURL),
                    UIActivityType.airDrop: url,
                    UIActivityType.copyToPasteboard: url,
                ]
            ),
            anchor: anchor,
            source: source,
            allowAirdrop: true,
            bubble: bubble,
            callback: callback)
    }

    static func createShareSheetProfile(_ account: Account?, anchor: UIView, source: String) -> UIActivityViewController {
        guard let account = account else {
            return createShareSheetOwnProfile(anchor, source: source)
        }
        return Share.createShareSheet(
            DynamicActivityItem(
                String.localizedStringWithFormat(
                    NSLocalizedString("Talk with %@ on Roger! %@", comment: "Share text for someone else's profile."),
                    account.remoteDisplayName, account.profileURL as NSURL),
                specific: [
                    UIActivityType.postToTwitter: String.localizedStringWithFormat(
                        NSLocalizedString("Talk with %@ on Roger! %@ #TalkMore", comment: "Share text for someone else's profile (Twitter)."),
                        account.remoteDisplayName, account.profileURL as NSURL),
                    UIActivityType.airDrop: account.profileURL,
                    UIActivityType.copyToPasteboard: account.profileURL,
                ]
            ),
            anchor: anchor,
            source: source,
            allowAirdrop: true)
    }

    static func createGroupInviteShareSheet(_ groupInviteURL: URL?, anchor: UIView, source: String, callback: ((Bool) -> Void)? = nil) -> UIActivityViewController {
        guard let inviteURL = groupInviteURL else {
            return Share.createShareSheetOwnProfile(anchor, source: source)
        }

        return Share.createShareSheet(
            DynamicActivityItem(
                String.localizedStringWithFormat(
                    NSLocalizedString("I've added you to a group on the Roger app. Use this link to join our conversation! \n%@", comment: "Group invite message"),
                    inviteURL.absoluteString),
                specific: [
                    UIActivityType.postToTwitter: String.localizedStringWithFormat(
                        NSLocalizedString("Join my group on Roger! %@ #TalkMore", comment: "Share text for a group (Twitter)."),
                        inviteURL as NSURL),
                    UIActivityType.airDrop: inviteURL,
                    UIActivityType.copyToPasteboard: inviteURL
                ]
            ),
            anchor: anchor,
            source: source,
            allowAirdrop: true,
            bubble: (NSLocalizedString("Conversation invite link", comment: "Group invite bubble title"), inviteURL.absoluteString),
            callback: callback
        )
    }
}

class BubbleActivityViewController: UIActivityViewController {
    var bubble: (String, String)?

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let (title, subtitle) = self.bubble else {
            return
        }

        let sheetHeight = self.view.subviews.first?.bounds.height ?? 298
        // TODO: Support dynamic height.
        let blurViewHeight = CGFloat(60)

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
        blurView.alpha = 0
        let x = self.view.frame.origin.x + 10
        let y = self.view.frame.size.height - sheetHeight - (10 as CGFloat) - blurViewHeight - (10 as CGFloat) + (1 as CGFloat)
        blurView.frame = CGRect(x: x, y: y, width: self.view.frame.size.width - 20, height: blurViewHeight)
        blurView.layer.cornerRadius = 8
        blurView.layer.masksToBounds = true
        self.blurView = blurView

        self.view.addSubview(blurView)

        // Setup attributed text for the share label.
        let mainText = NSMutableAttributedString(string: title, attributes: [NSForegroundColorAttributeName: UIColor.black])
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3

        let subtitleAttributes = [NSForegroundColorAttributeName: UIColor.darkGray, NSParagraphStyleAttributeName: paragraphStyle]
        mainText.append(NSMutableAttributedString(string: "\n\(subtitle)", attributes: subtitleAttributes))

        let titleLabel = UILabel()
        titleLabel.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        titleLabel.font = UIFont.rogerFontOfSize(14)
        titleLabel.attributedText = mainText
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .center
        self.titleLabel = titleLabel

        blurView.addSubview(titleLabel)
    }

    override func viewWillAppear(_ animated: Bool) {
        guard let blurView = self.blurView else {
            return
        }
        UIView.animate(withDuration: 0.3, animations: {
            blurView.alpha = 1
        }) 
    }

    override func viewWillDisappear(_ animated: Bool) {
        guard let blurView = self.blurView else {
            return
        }
        UIView.animate(withDuration: 0.3, animations: {
            blurView.alpha = 0
        }) 
    }

    override func viewDidLayoutSubviews() {
        guard let blurView = self.blurView else {
            return
        }
        self.titleLabel?.frame = blurView.bounds
    }

    // MARK: - Private

    fileprivate var blurView: UIVisualEffectView?
    fileprivate var titleLabel: UILabel?
}
