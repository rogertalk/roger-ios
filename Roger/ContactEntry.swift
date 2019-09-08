import Foundation

struct AccountEntry {
    var active: Bool
    var id: Int64
}

struct ContactEntry: Equatable {
    var id: String
    var identifierToLabel: [String: String]
    var imageData: Data?
    var name: String

    var identifiers: [String] {
        return Array(self.identifierToLabel.keys)
    }
}

func ==(left: ContactEntry, right: ContactEntry) -> Bool {
    return left.id == right.id
}

extension ContactEntry {
    class Coder: NSObject, NSCoding {
        let entry: ContactEntry

        init(entry: ContactEntry) {
            self.entry = entry
            super.init()
        }

        required init?(coder decoder: NSCoder) {
            guard
                decoder.decodeInteger(forKey: "v") == 1,
                let id = decoder.decodeObject(forKey: "c") as? String,
                let identifierToLabel = decoder.decodeObject(forKey: "a") as? [String: String],
                let name = decoder.decodeObject(forKey: "n") as? String
                else { return nil }
            let imageData = decoder.decodeObject(forKey: "i") as? Data
            self.entry = ContactEntry(id: id, identifierToLabel: identifierToLabel, imageData: imageData, name: name)
            super.init()
        }

        func encode(with coder: NSCoder) {
            coder.encode(1, forKey: "v")
            coder.encode(self.entry.id, forKey: "c")
            coder.encode(self.entry.identifierToLabel, forKey: "a")
            coder.encode(self.entry.imageData, forKey: "i")
            coder.encode(self.entry.name, forKey: "n")
        }
    }
}
