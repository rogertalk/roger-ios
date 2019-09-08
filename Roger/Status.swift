enum ActivityStatus: String {
    case Idle = "idle"
    case Listening = "listening"
    case Talking = "talking"
    case ViewingAttachment = "viewing-attachment"
}

// The order in which statuses take precendence (for display purposes).
private let statusPriority: [ActivityStatus] = [.Idle, .ViewingAttachment, .Listening, .Talking]
extension ActivityStatus: Comparable {}
func <(a: ActivityStatus, b: ActivityStatus) -> Bool {
    return statusPriority.index(of: a)! < statusPriority.index(of: b)!
}
