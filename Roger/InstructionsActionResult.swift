import Foundation

enum InstructionsActionResult {
    case nothing
    case showAlert(title: String, message: String, action: String)
    case showShareSheet(text: String)
    case showWebView(title: String, url: URL)
}
