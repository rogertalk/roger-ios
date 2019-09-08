import Foundation

struct Greeting: PlayableChunk {
    let accountId: Int64
    let audioURL: URL
    let duration: Int

    var end: Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }

    var senderId: Int64 {
        return self.accountId
    }

    var start: Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000) - self.duration
    }

    init(accountId: Int64, audioURL: URL, duration: Int) {
        self.accountId = accountId
        self.audioURL = audioURL
        self.duration = duration
    }

    init?(accountId: Int64, data: DataType) {
        if let urlString = data["audio_url"] as? String,
            let url = URL(string: urlString),
            let duration = data["duration"] as? NSNumber {
            self.accountId = accountId
            self.audioURL = url
            self.duration = duration.intValue
            return
        }

        if let greeting = data["greeting"] as? [String: Any],
            let urlString = greeting["audio_url"] as? String,
            let url = URL(string: urlString),
            let duration = greeting["duration"] as? NSNumber {
            self.accountId = accountId
            self.audioURL = url
            self.duration = duration.intValue
            return
        }

        return nil
    }
}
