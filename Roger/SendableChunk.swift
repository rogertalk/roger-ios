import Foundation

protocol SendableChunk {
    var audioURL: URL { get }
    var duration: Int { get }
    var token: String? { get }
}

extension SendableChunk {
    var token: String? {
        return nil
    }
}
