import Foundation

protocol PlayableChunk: SendableChunk {
    var end: Int64 { get }
    var senderId: Int64 { get }
    var start: Int64 { get }
}

extension PlayableChunk {
    var age: TimeInterval {
        return Date().timeIntervalSince1970 - TimeInterval(self.end) / 1000
    }

    var byCurrentUser: Bool {
        return self.senderId == BackendClient.instance.session?.id
    }
}
