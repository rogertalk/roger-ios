import FBSDKMessengerShareKit

class MessengerStream: Stream {
    override var autoplayChangeable: Bool {
        return false
    }

    override var callToAction: String? {
        return "Talk to send on Messenger"
    }

    override var instructions: Instructions? {
        return ("", "Crystal-clear conversations with friends\non Facebook Messenger.")
    }

    override var statusText: String {
        return "Connected"
    }

    override func sendChunk(_ chunk: SendableChunk, persist: Bool?, showInRecents: Bool?, callback: StreamServiceCallback? = nil) {
        super.sendChunk(chunk, callback: callback)
        // Also share all chunks via Messenger.
        let messengerOptions = FBSDKMessengerShareOptions()
        messengerOptions.metadata = "\(BackendClient.instance.session!.id)"
        // TODO: Investigate context override (reply flow, broadcast flow, send flow).
        FBSDKMessengerSharer.shareAudio(try? Data(contentsOf: chunk.audioURL as URL), with: messengerOptions)
    }
}
