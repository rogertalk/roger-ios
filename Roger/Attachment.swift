import AlamofireImage

class Attachment {
    static var defaultAttachmentName = "attachment0"

    var id: String {
        return Attachment.defaultAttachmentName
    }

    var isImage: Bool {
        return self.type == "image"
    }

    var image: UIImage?
    
    var url: URL? {
        guard let urlString = self.data["url"] as? String else {
            return nil
        }
        return URL(string: urlString)
    }

    var senderId: Int64? {
        return (self.data["account_id"] as? NSNumber)?.int64Value
    }

    var type: String {
        return self.data["type"] as! String
    }

    init(data: DataType) {
        self.data = data
    }

    init(image: UIImage) {
        self.image = image
        self.data["type"] = "image"
        self.data["account_id"] = NSNumber(value: BackendClient.instance.session!.id)
    }

    init(url: URL) {
        self.data["type"] = "url"
        self.data["url"] = url.absoluteString
    }

    private(set) var data: DataType = [:]
}
