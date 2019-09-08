import UIKit

class EmbeddedBrowserController: UIViewController, UIWebViewDelegate {

    @IBOutlet weak var webview: UIWebView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var failedRequestLabel: UILabel!
    @IBOutlet weak var loaderView: UIActivityIndicatorView!

    var urlToLoad: URL?
    var finishPattern = "rogertalk://"
    var pageTitle: String?
    var callback: ((_ didFinish: Bool) -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.titleLabel.text = self.pageTitle
        guard let url = self.urlToLoad, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "embed", value: "true"))
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        if
            url.absoluteString.hasPrefix("https://rogertalk.com/"),
            let refreshToken = BackendClient.instance.session?.refreshToken
        {
            request.httpMethod = "POST"
            request.httpBody = "refresh_token=\(refreshToken)".data(using: String.Encoding.utf8)
        }
        self.webview.loadRequest(request)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.titleLabel.text = self.pageTitle
        self.failedRequestLabel.isHidden = true
        self.webview.delegate = self
    }

    func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
        self.failedRequestLabel.isHidden = false
        self.loaderView.stopAnimating()
    }

    func webViewDidStartLoad(_ webView: UIWebView) {
        self.failedRequestLabel.isHidden = true
        self.loaderView.startAnimating()
    }

    func webView(_ webView: UIWebView, shouldStartLoadWith request: URLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        // Dismiss the web view if there is a match for the finish trigger.
        if let urlString = request.url?.absoluteString, urlString.contains(self.finishPattern) {
            self.dismiss(animated: true, completion: nil)
            self.callback?(true)
        }
        return true
    }

    func webViewDidFinishLoad(_ webView: UIWebView) {
        self.failedRequestLabel.isHidden = true
        self.loaderView.stopAnimating()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    @IBAction func backButton(_ sender: AnyObject) {
        self.dismissKeyboard()
        self.callback?(false)
        self.dismiss(animated: true, completion: nil)
    }

    func dismissKeyboard() {
        self.view.endEditing(true)
    }
}
