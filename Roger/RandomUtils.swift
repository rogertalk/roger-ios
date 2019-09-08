import UIKit

class RandomUtils {
    
    class func randomStartingPos() -> CGFloat {
        return CGFloat(Float(arc4random()) / 0xFFFFFFFF)
    }
    
    class func getRandomInt(_ lower: Int , upper: Int) -> Int {
        return lower + Int(arc4random_uniform(UInt32(upper - lower + 1)))
    }

    class func getRandomAlphanumericString(length: Int = 5) -> String {
        let characters: NSString = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomString = NSMutableString(capacity: length)

        for _ in 0..<length {
            let index = Int(arc4random_uniform(UInt32(characters.length)))
            randomString.appendFormat("%C", characters.character(at: index))
        }

        return randomString as String
    }
}
