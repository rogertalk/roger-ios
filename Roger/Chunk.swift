import Foundation

struct Chunk: PlayableChunk {
    let streamId: Int64
    let id: Int64
    let audioURL: URL
    let duration: Int
    let start: Int64
    let end: Int64
    let senderId: Int64
    let text: String?

    init(streamId: Int64, data: DataType) {
        self.streamId = streamId
        self.id = (data["id"] as! NSNumber).int64Value
        self.audioURL = URL(string: data["audio_url"] as! String)!
        self.duration = data["duration"] as! Int
        self.start = (data["start"] as! NSNumber).int64Value
        self.end = (data["end"] as! NSNumber).int64Value
        self.senderId = (data["sender_id"] as! NSNumber).int64Value
        self.text = data["text"] as? String
    }
}

extension Chunk: Equatable {}
func ==(lhs: Chunk, rhs: Chunk) -> Bool {
    return lhs.streamId == rhs.streamId && lhs.id == rhs.id
}
