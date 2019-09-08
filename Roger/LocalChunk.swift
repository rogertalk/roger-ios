import Foundation

struct LocalChunk: PlayableChunk {
    let audioURL: URL
    let duration: Int
    let start: Int64
    let end: Int64
    let senderId: Int64
}
