import Foundation

class ShareStream: Stream {
    override var autoplayChangeable: Bool {
        return false
    }

    override var callToAction: String? {
        return NSLocalizedString("Talk to share your voice", comment: "Share bot call to action")
    }

    override var instructions: Instructions? {
        return ("", NSLocalizedString("Talk to share your voice\noutside of Roger", comment: "Share bot description"))
    }

    override var instructionsAction: String? {
        guard let chunk = self.lastChunk else {
            return nil
        }
        let duration = TimeInterval(ceil(Double(chunk.duration) / 1000))
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .short
        return String.localizedStringWithFormat(
            NSLocalizedString("Share %@", comment: "Share bot action"),
            formatter.string(from: duration)!)
    }

    override var statusText: String {
        return ""
    }

    override func instructionsActionTapped() -> InstructionsActionResult {
        guard let link = self.shareURL?.absoluteString else {
            return .nothing
        }
        return .showShareSheet(text: String.localizedStringWithFormat(
            NSLocalizedString("Talking on Roger! Listen here: %@ #TalkMore",
                comment: "Share bot share sheet description"),
            link))
    }

    override func sendChunk(_ chunk: SendableChunk, persist: Bool?, showInRecents: Bool?, callback: StreamServiceCallback? = nil) {
        let shareToken = chunk.token ?? RandomUtils.getRandomAlphanumericString()
        let shareableChunk = Intent.Chunk(audioURL: chunk.audioURL, duration: chunk.duration, token: shareToken)
        self.lastChunk = shareableChunk
        self.shareURL = BackendClient.instance.session?.profileURLWithChunkToken(shareToken)
        super.sendChunk(shareableChunk, persist: persist ?? true, showInRecents: showInRecents, callback: callback)
    }


    // MARK: - Private

    fileprivate var lastChunk: SendableChunk?
    fileprivate var shareURL: URL?
}
