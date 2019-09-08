import Foundation

class StatusStream: Stream {
    override var autoplayChangeable: Bool {
        return false
    }

    override var callToAction: String? {
        return nil
    }

    override var chunks: [PlayableChunk] {
        guard let session = BackendClient.instance.session, let greeting = session.greeting else {
            return []
        }
        let end = Int64(Date().timeIntervalSince1970 * 1000), start = end - greeting.duration
        return [LocalChunk(audioURL: greeting.audioURL, duration: greeting.duration, start: start, end: end, senderId: session.id)]
    }

    override var instructions: Instructions? {
        return ("Set a public status", "People will hear this status\nwhen visiting your profile.")
    }

    override var instructionsAction: String? {
        return "Share my profile"
    }

    override var statusText: String {
        return ""
    }

    override func instructionsActionTapped() -> InstructionsActionResult {
        guard let session = BackendClient.instance.session else {
            return .nothing
        }
        return .showShareSheet(text: "Talk with me on Roger 👉 \(session.profileURL) #TalkMore")
    }

    override func sendChunk(_ chunk: SendableChunk, persist: Bool?, showInRecents: Bool?, callback: StreamServiceCallback?) {
        super.sendChunk(chunk, persist: persist, showInRecents: showInRecents ?? false, callback: callback)
    }
}
