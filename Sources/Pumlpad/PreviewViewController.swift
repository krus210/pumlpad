import AppKit
import os
import WebKit

/// Shows the rendered SVG in WebKit: vector-sharp at any zoom, with pinch, ⌘-scroll and drag to pan.
///
/// The SVG comes from a document that may be someone else's, so the page is locked down: a
/// Content Security Policy runs only the page's own script and loads nothing from the network,
/// and only a click on a diagram link may open the browser.
@MainActor
final class PreviewViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    var onZoomChange: ((Double) -> Void)?

    private static let messageHandlerName = "pumlpad"
    private static let logger = Logger(subsystem: "com.sskorolev.pumlpad", category: "preview")
    private var webView: WKWebView!
    private var isPageLoaded = false
    /// Calls made before the page finished loading.
    private var queuedCalls: [(body: String, arguments: [String: Any])] = []
    /// The picture on screen; an unchanged render is not sent to the page again.
    private var shownSVG: Data?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakMessageHandler(self), name: Self.messageHandlerName)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 700), configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.setAccessibilityLabel("Diagram preview")
        self.webView = webView
        view = webView
        webView.loadHTMLString(PreviewPage.html, baseURL: nil)
    }

    func show(svg: Data) {
        guard svg != shownSVG else {
            setStale(false)
            return
        }
        shownSVG = svg
        call("pumlpad.setSVG(svg)", ["svg": String(decoding: svg, as: UTF8.self)])
    }

    /// Dims the picture while the source has an error, so an outdated diagram is not mistaken for the current one.
    func setStale(_ stale: Bool) {
        call("pumlpad.setStale(stale)", ["stale": stale])
    }

    func showMessage(_ message: String) {
        shownSVG = nil
        call("pumlpad.showMessage(message)", ["message": message])
    }

    func setDarkBackground(_ dark: Bool) {
        call("pumlpad.setDark(dark)", ["dark": dark])
    }

    func zoomIn() { call("pumlpad.zoomIn()") }
    func zoomOut() { call("pumlpad.zoomOut()") }
    func zoomToActualSize() { call("pumlpad.actualSize()") }
    func zoomToFit() { call("pumlpad.fit()") }

    /// `WKUserContentController` keeps its message handlers until they are removed.
    func tearDown() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
        webView.navigationDelegate = nil
    }

    private func call(_ body: String, _ arguments: [String: Any] = [:]) {
        guard isPageLoaded else {
            queuedCalls.append((body, arguments))
            return
        }
        webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
            if case .failure(let error) = result {
                Self.logger.error("Preview script \(body, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageLoaded = true
        let calls = queuedCalls
        queuedCalls.removeAll()
        calls.forEach { call($0.body, $0.arguments) }
    }

    /// Only the page itself loads, once, from `loadHTMLString` into the main frame. After that
    /// only a click on a diagram link (`[[https://…]]`) opens the browser; scripts, redirects,
    /// forms and frames cannot navigate anywhere.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if !isPageLoaded, navigationAction.targetFrame?.isMainFrame == true,
           navigationAction.request.url?.absoluteString == "about:blank" {
            return .allow
        }
        if navigationAction.navigationType == .linkActivated,
           navigationAction.sourceFrame.isMainFrame,
           let url = navigationAction.request.url,
           ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if let zoom = body["zoom"] as? Double { onZoomChange?(zoom) }
    }
}

/// `WKUserContentController` retains its handlers; this breaks the cycle with the view controller.
@MainActor
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
