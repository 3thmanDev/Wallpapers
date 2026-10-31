import Foundation
import WebKit

/// The X page inside the app. The user signs in there once; `Harvest.txt` then hands
/// over the photos from the bookmarks and likes pages while it scrolls them.
@MainActor
final class ImportSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let loginURL = URL(string: "https://x.com/i/flow/login")!

    @Published private(set) var source: WallpaperSource = .bookmarks
    /// Unknown until the page has loaded once.
    @Published private(set) var isLoggedIn: Bool?
    @Published private(set) var isRunning = false
    @Published private(set) var reachedEnd = false
    @Published private(set) var isLoading = true
    @Published private(set) var found = 0
    @Published private(set) var added = 0

    let webView: WKWebView
    private let store: LibraryStore
    private var seen = Set<String>()
    private var startWhenLoaded = false
    private var nextDate = Date()

    init(store: LibraryStore) {
        self.store = store
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Without the Safari part of the user agent X may treat the page as an unsupported browser.
        configuration.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"
        // The script ships as .txt: Gmail refuses an attachment that has a .js file anywhere inside it.
        if let url = Bundle.main.url(forResource: "Harvest", withExtension: "txt"),
           let script = try? String(contentsOf: url, encoding: .utf8) {
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }
        let relay = MessageRelay()
        configuration.userContentController.add(relay, name: "harvest")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .black
        webView.isOpaque = false
        self.webView = webView
        super.init()
        relay.session = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    /// Opens the list straight away when X still remembers the user, the sign-in page otherwise.
    func begin() async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let signedIn = cookies.contains { $0.name == "auth_token" && $0.domain.hasSuffix("x.com") }
        webView.load(URLRequest(url: signedIn ? Self.listURL(source) : Self.loginURL))
    }

    func start() {
        reachedEnd = false
        startWhenLoaded = true
        webView.load(URLRequest(url: Self.listURL(source)))
    }

    func stop() {
        startWhenLoaded = false
        webView.evaluateJavaScript("window.__wpAuto && window.__wpAuto(false)")
    }

    func select(_ newSource: WallpaperSource, startNow: Bool = false) {
        guard newSource != source else {
            if startNow { start() }
            return
        }
        let wasRunning = isRunning
        stop()
        source = newSource
        seen = []
        found = 0
        added = 0
        reachedEnd = false
        if wasRunning || startNow {
            start()
        } else if isLoggedIn == true {
            webView.load(URLRequest(url: Self.listURL(newSource)))
        }
    }

    func reload() {
        webView.reload()
    }

    func signOut() async {
        stop()
        let dataStore = webView.configuration.websiteDataStore
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        isLoggedIn = false
        webView.load(URLRequest(url: Self.loginURL))
    }

    static func listURL(_ source: WallpaperSource) -> URL {
        // X keeps both lists under History; /i/bookmarks also redirects there.
        URL(string: source == .likes ? "https://x.com/i/history/likes" : "https://x.com/i/history")!
    }

    fileprivate func receive(_ text: String) {
        guard let message = HarvestMessage.decode(text) else { return }
        switch message.event {
        case "session":
            let loggedIn = message.loggedIn ?? false
            let justSignedIn = loggedIn && isLoggedIn == false
            isLoggedIn = loggedIn
            if justSignedIn {
                webView.load(URLRequest(url: Self.listURL(source)))
            }
        case "photos":
            let wallpapers = message.wallpapers(startingAt: nextDate)
            nextDate = nextDate.addingTimeInterval(-Double(wallpapers.count + 1) * 0.001)
            found += wallpapers.filter { seen.insert($0.id).inserted }.count
            added += store.add(wallpapers, reviveDeleted: false)
        case "running":
            isRunning = message.running ?? false
        case "end":
            isRunning = false
            reachedEnd = true
        default:
            break
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        guard startWhenLoaded else { return }
        startWhenLoaded = false
        webView.evaluateJavaScript("window.__wpAuto && window.__wpAuto(true)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    // MARK: - WKUIDelegate

    /// Pages that open a new window (some sign-in buttons do) load in the same view instead.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

/// The content controller keeps its handler alive, so it holds the session weakly.
private final class MessageRelay: NSObject, WKScriptMessageHandler {
    weak var session: ImportSession?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let text = message.body as? String else { return }
        let session = session
        Task { @MainActor in
            session?.receive(text)
        }
    }
}
