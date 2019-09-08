import Foundation

class Service {
    let data: DataType
    let identifier: String
    var stream: Stream?

    var accountId: Int64? {
        return (self.data["account_id"] as? NSNumber).flatMap { $0.int64Value }
    }

    var connected: Bool {
        return self.data["connected"] as! Bool
    }

    var connectURL: URL? {
        guard let serviceURLString = self.data["connect_url"] as? String else {
            return nil
        }

        guard !serviceURLString.hasPrefix("https://rogertalk.com") else {
            return URL(string: serviceURLString)!
        }

        var components = URLComponents(string: "https://rogertalk.com/forward")!
        components.queryItems = [URLQueryItem(name: "to", value: serviceURLString)]
        return components.url!
    }

    var finishPattern: String? {
        return self.data["finish_pattern"] as? String
    }

    var imageURL: URL? {
        guard let urlString = self.data["image_url"] as? String else {
            return nil
        }
        return URL(string: urlString)
    }

    var title: String {
        return self.data["title"] as! String
    }

    var description: String {
        return self.data["description"] as! String
    }

    init?(_ data: DataType) {
        self.data = data
        guard let identifier = data["id"] as? String else {
            return nil
        }
        self.identifier = identifier

        if let accountId = self.accountId {
            StreamService.instance.getOrCreateStream(participants: [Intent.Participant(value: String(accountId))], showInRecents: false) {
                stream, _ in
                self.stream = stream
            }
        }
    }
}
