import Darwin
import MessageUI
import DateTools

private let base62Alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".characters

var rogerGradientColors: [CGColor] {
    return [
        (color: "7f96b7".hexColor!, location: 0),
        (color: "405b81".hexColor!, location: 0.45),
        (color: "1b273d".hexColor!, location: 1),
        ].reversed().map { $0.color.cgColor }
}

extension Integer {
    var base62: String {
        var result = ""
        var quotient = self.toIntMax()
        while (quotient > 0) {
            let remainder = Int(quotient % 62)
            quotient = quotient / 62
            result.insert(base62Alphabet[base62Alphabet.index(base62Alphabet.startIndex, offsetBy: remainder)], at: result.startIndex)
        }
        return result
    }
}

extension MessageComposeResult: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Failed"
        case .sent:
            return "Sent"
        }
    }
}

extension Data {
    var hex: String {
        let pointer = (self as NSData).bytes.bindMemory(to: UInt8.self, capacity: self.count)
        var hex = ""
        for i in 0..<self.count {
            hex += String(format: "%02x", pointer[i])
        }
        return hex
    }
}

extension Date {
    // TODO: Delete these methods because there is no static way to tell day/night.
    var isDaytime: Bool {
        return ((self as NSDate).hour() >= 8 && (self as NSDate).hour() < 18)
    }

    var isNight: Bool {
        return ((self as NSDate).hour() >= 20 || (self as NSDate).hour() < 6)
    }

    var isDawn: Bool {
        return ((self as NSDate).hour() >= 6 && (self as NSDate).hour() < 8)
    }

    var isDusk: Bool {
        return ((self as NSDate).hour() >= 18 && (self as NSDate).hour() < 20)
    }

    /// Returns something along the lines of "7 PM".
    fileprivate func formattedHour() -> String {
        // TODO: This is
        let hour = min((self as NSDate).hour() + ((self as NSDate).minute() >= 30 ? 1 : 0), 23)
        let ampm = hour < 12 ? "AM" : "PM"
        let hour12 = hour % 12
        return "\(hour12 > 0 ? hour12 : 12) \(ampm)"
    }

    /// Get a new NSDate adjusted for the given timezone. Note that NSDate does not contain timezone information so this method is NOT idempotent.
    func forTimeZone(_ name: String) -> Date? {
        guard let timeZone = TimeZone(identifier: name) else {
            return nil
        }
        let seconds = timeZone.secondsFromGMT(for: self) - TimeZone.autoupdatingCurrent.secondsFromGMT(for: self)
        return Date(timeInterval: TimeInterval(seconds), since: self)
    }

    var rogerFormattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    /// Displays Roger short date format.
    var rogerShortTimeLabel: String {
        switch self.wholeDaysAgo() {
        case 0:
            return self.rogerFormattedTime
        case 1...6:
            return (self as NSDate).formattedDate(withFormat: "EEE")
        default:
            return (self as NSDate).formattedDate(withFormat: "MMM d")
        }
    }

    var rogerShortTimeLabelAccessible: String {
        switch self.wholeDaysAgo() {
        case 0:
            return String.localizedStringWithFormat(
                NSLocalizedString("at %@", comment: "Time status; value is a time"),
                self.rogerFormattedTime)
        case 1...6:
            return (self as NSDate).formattedDate(withFormat: "EEEE")
        default:
            return (self as NSDate).formattedDate(withFormat: "MMMM d")
        }
    }

    var rogerTimeLabel: String {
        let morningHours = 5..<12
        let eveningHours = 18..<24

        let minutesAgo = (self as NSDate).minutesAgo()
        if minutesAgo < 0.2 {
            return NSLocalizedString("just now", comment: "Time status")
        } else if minutesAgo < 2 {
            return NSLocalizedString("a minute ago", comment: "Time status")
        } else if minutesAgo < 20 {
            return NSLocalizedString("a few minutes ago", comment: "Time status")
        } else if minutesAgo < 40 {
            return NSLocalizedString("half an hour ago", comment: "Time status")
        } else if minutesAgo < 100 {
            return NSLocalizedString("about an hour ago", comment: "Time status")
        } else if minutesAgo < 300 {
            return NSLocalizedString("a few hours ago", comment: "Time status")
        } else if (self as NSDate).isToday() {
            if morningHours ~= (self as NSDate).hour() {
                return NSLocalizedString("this morning", comment: "Time status")
            } else {
                return String.localizedStringWithFormat(
                    NSLocalizedString("today around %@", comment: "Time status; value is the hour"),
                    self.formattedHour())
            }
        } else if (self as NSDate).isYesterday() {
            switch (self as NSDate).hour() {
            case morningHours:
                return NSLocalizedString("yesterday morning", comment: "Time status")
            case eveningHours:
                return NSLocalizedString("last night", comment: "Time status")
            default:
                return String.localizedStringWithFormat(
                    NSLocalizedString("yesterday around %@", comment: "Time status"),
                    self.formattedHour())
            }
        } else if self.wholeDaysAgo() < 7 {
            return (self as NSDate).formattedDate(withFormat: NSLocalizedString("'on' EEEE", comment: "Time status; on a day (leave EEEE format)"))
        } else {
            return (self as NSDate).formattedDate(withFormat: NSLocalizedString("'on' MMMM d", comment: "Time status; on a date (leave MMMM d format)"))
        }
    }

    func wholeDaysAgo() -> Int {
        // TODO: Not sure this is entirely timezone safe.
        let beginningOfDay = NSDate(year: (self as NSDate).year(), month: (self as NSDate).month(), day: (self as NSDate).day())
        return beginningOfDay!.daysAgo()
    }
}

extension URL {
    /// Parses a query string and returns a dictionary that contains all the key/value pairs.
    func parseQueryString() -> [String: [String]]? {
        guard let items = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        var data = [String: [String]]()
        for item in items {
            var list = data[item.name] ?? [String]()
            if let value = item.value {
                list.append(value)
            }
            data[item.name] = list
        }
        return data
    }

    /// Creates a random file path to a file in the temporary directory.
    static func temporaryFileURL(_ fileExtension: String) -> URL {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let randomId = ProcessInfo.processInfo.globallyUniqueString
        return temp.appendingPathComponent(randomId).appendingPathExtension(fileExtension)
    }
}

extension Sequence where Iterator.Element == String {
    func localizedJoin() -> String {
        var g = self.makeIterator()
        guard let first = g.next() else {
            return ""
        }
        guard let second = g.next() else {
            return first
        }
        guard var last = g.next() else {
            return String.localizedStringWithFormat(
                NSLocalizedString("LIST_TWO", value: "%@ and %@", comment: "List; only two items"), first, second)
        }
        var middle = second
        while let piece = g.next() {
            middle = String.localizedStringWithFormat(
                NSLocalizedString("LIST_MIDDLE", value: "%@, %@", comment: "List; more than three items, middle items"), middle, last)
            last = piece
        }
        return String.localizedStringWithFormat(
            NSLocalizedString("LIST_END", value: "%@ and %@", comment: "List; more than two items, last items"),
            String.localizedStringWithFormat(
                NSLocalizedString("LIST_START", value: "%@, %@", comment: "List; more than two items, first items"), first, middle),
            last)
    }
}

private let initialsRegex = try! NSRegularExpression(pattern: "\\b[^\\W\\d_]", options: [])

extension UIColor {
    static var rogerGray: UIColor? {
        return "727272".hexColor
    }

    static var rogerBlue: UIColor? {
        return "4285F4".hexColor
    }

    static var rogerRed: UIColor? {
        return "FF3A3A".hexColor
    }

    static var rogerGreen: UIColor? {
        return "0b0".hexColor
    }
}

extension String {
    var hasLetters: Bool {
        let letters = CharacterSet.letters
        return self.rangeOfCharacter(from: letters) != nil
    }

    var hexColor: UIColor? {
        let hex = self.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt32()
        guard Scanner(string: hex).scanHexInt32(&int) else {
            return nil
        }
        let a, r, g, b: UInt32
        switch hex.characters.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    var rogerInitials: String {
        let range = NSMakeRange(0, self.characters.count)
        let matches = initialsRegex.matches(in: self, options: [], range: range)
        let nsTitle = self as NSString
        switch matches.count {
        case 0:
            return "#"
        default:
            return nsTitle.substring(with: matches[0].range).uppercased()
        }
    }

    var rogerShortName: String {
        let words = self.characters.split(separator: " ").map(String.init)
        // Build a short name, ensuring that there's at least one word with letters.
        var shortName = ""
        for word in words {
            shortName = shortName.characters.count > 0 ? "\(shortName) \(word)" : word
            if word.hasLetters {
                break
            }
        }
        guard shortName.characters.count > 0 else {
            return ""
        }
        // Remove any comma at the end of the string.
        let index = shortName.characters.index(before: shortName.endIndex)
        if shortName[index] == "," {
            shortName = shortName.substring(to: index)
        }
        return shortName
    }
}

extension Array {
    mutating func shuffle() {
        if count < 2 { return }
        for i in 0..<(count - 1) {
            let j = Int(arc4random_uniform(UInt32(count - i))) + i
            guard j != i else {
                continue
            }
            swap(&self[i], &self[j])
        }
    }
}

extension UIButton {
    func setTitleWithoutAnimation(_ title: String) {
        UIView.performWithoutAnimation {
            self.setTitle(title, for: .normal)
            self.layoutIfNeeded()
        }
    }

    func setImageWithAnimation(_ image: UIImage?) {
        guard let imageView = self.imageView else {
            return
        }

        if let newImage = image, let oldImage = imageView.image {
            let crossFade = CABasicAnimation(keyPath: "contents")
            crossFade.duration = 0.1;
            crossFade.fromValue = oldImage.cgImage;
            crossFade.toValue = newImage.cgImage;
            crossFade.isRemovedOnCompletion = true;
            crossFade.fillMode = kCAFillModeForwards;
            self.imageView?.layer.add(crossFade, forKey:"animateContents");
        }

        self.setImage(image, for: .normal)
    }
}

extension UIView {
    /// A quick size pulse animation for UI feedback
    func pulse(_ scale: Double = 1.3) {
        let s = CGFloat(scale)
        UIView.animate(withDuration: 0.1, delay: 0.0, options: .allowUserInteraction, animations: {
            self.transform = CGAffineTransform(scaleX: s, y: s)
            }, completion: { success in
                UIView.animate(withDuration: 0.1, delay: 0.0, options: .allowUserInteraction, animations: {
                    self.transform = CGAffineTransform.identity
                    }, completion: nil)
        })
    }

    /// Hover up and down
    func hover(_ repeats: Bool = true) {
        UIView.animate(withDuration: 0.5, delay: 0.0, options: [.repeat, .autoreverse], animations: {
            self.transform = CGAffineTransform.identity.translatedBy(x: 0, y: 6)
            }, completion: nil)
    }

    func showAnimated() {
        self.isHidden = false
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 1
        }) 
    }

    func hideAnimated(_ callback: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
        }, completion: { success in
            self.isHidden = true
            callback?()
        }) 
    }
}

extension UITableView {
    func scrollToTop(_ animated: Bool = false) {
        let offset = CGPoint(x: 0, y: 0)
        guard animated else {
            self.contentOffset = offset
            return
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.contentOffset = offset
        }) 
    }

    func scrollToBottom(_ animated: Bool = false) {
        let offset = CGPoint(x: 0, y: self.contentSize.height - self.frame.height)
        guard animated else {
            self.contentOffset = offset
            return
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.contentOffset = offset
        }) 
    }
}

extension UIFont {
    class func rogerFontOfSize(_ size: CGFloat) -> UIFont {
        return UIFont(name: "SFUIText-Regular", size: size) ?? UIFont.systemFont(ofSize: size)
    }

    class func monospacedDigitsRogerFontOfSize(_ size: CGFloat) -> UIFont {
        let feature = [
            UIFontFeatureTypeIdentifierKey: kNumberSpacingType,
            UIFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector,
        ]
        let baseDescriptor = UIFont.rogerFontOfSize(size).fontDescriptor
        let attributes = [UIFontDescriptorFeatureSettingsAttribute: [feature]]
        return UIFont(descriptor: baseDescriptor.addingAttributes(attributes), size: size)
    }

    class func materialFontOfSize(_ size: CGFloat) -> UIFont {
        return UIFont(name: "MaterialIcons-Regular", size: size)!
    }
}

extension UIImage {
    func scaleToFitSize(_ size: CGSize) -> UIImage? {
        guard let image = self.cgImage else {
            return nil
        }
        // Get the largest dimension and convert it from points to pixels.
        let screenScale = UIScreen.main.scale
        let major = max(size.width, size.height) * screenScale
        // Calculate new dimensions for the image so that its smallest dimension fits within the specified size.
        let originalWidth = CGFloat(image.width), originalHeight = CGFloat(image.height)
        let minor = min(originalWidth, originalHeight)
        let scale = major / minor
        let width = originalWidth * scale, height = originalHeight * scale
        // Render and return a resampled image.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: CGPoint.zero, size: CGSize(width: width, height: height)))
        return context.makeImage().flatMap { UIImage(cgImage: $0, scale: screenScale, orientation: .up) }
    }
}

extension UIView {
    var layoutDirection: UIUserInterfaceLayoutDirection {
        if #available(iOS 9.0, *) {
            return UIView.userInterfaceLayoutDirection(for: self.semanticContentAttribute)
        } else {
            return .leftToRight
        }
    }

    @IBInspectable var borderWidth: CGFloat {
        get {
            return self.layer.borderWidth
        }
        set {
            self.layer.borderWidth = newValue
        }
    }

    @IBInspectable var borderColor: UIColor? {
        get {
            return UIColor(cgColor: self.layer.borderColor!)
        }
        set {
            self.layer.borderColor = newValue?.cgColor
        }
    }
}

extension UINavigationController {
    func pushViewControllerModal(_ controller: UIViewController) {
        let transition = CATransition()
        transition.duration = 0.4
        transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionDefault)
        transition.type = kCATransitionMoveIn
        transition.subtype = kCATransitionFromTop
        self.view.layer.add(transition, forKey: kCATransition)
        self.pushViewController(controller, animated: false)
    }

    func popViewControllerModal() {
        let transition = CATransition()
        transition.duration = 0.4
        transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionDefault)
        transition.type = kCATransitionReveal
        transition.subtype = kCATransitionFromBottom
        self.view.layer.add(transition, forKey: kCATransition)
        self.popViewController(animated: false)
    }

    func popToRootViewControllerModal() {
        let transition = CATransition()
        transition.duration = 0.4
        transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionDefault)
        transition.type = kCATransitionReveal
        transition.subtype = kCATransitionFromBottom
        self.view.layer.add(transition, forKey: kCATransition)
        self.popToRootViewController(animated: false)
    }
}
