import WebKit
import AppKit

/// LRU-evicting pool of WKWebViews with tab virtualization.
/// Max 5 live WKWebViews at any time. Background tabs are virtualized to
/// markdown strings + scroll position, their WKWebViews recycled.
@MainActor
final class EditorReusePool {
    static let shared = EditorReusePool()

    private let maxLive = 5
    private let processPool = WKProcessPool()

    /// Available (recycled or pre-warmed) WKWebViews ready for use
    private var available: [WKWebView] = []

    /// WKWebViews that have been pre-loaded with HTML (awaiting editorReady)
    private var preLoaded: Set<ObjectIdentifier> = []

    /// Editors with live WKWebViews, in LRU order (most recent last)
    private var liveEditors: [EditorViewController] = []

    private init() {}

    /// Pre-warm pool with WKWebViews for fast first-open
    func warmUp() {
        NSLog("[Perf] warmUp start at %@ms", msSinceStart())

        // Create first WKWebView and pre-load editor HTML
        let first = createWebView()
        first.load(URLRequest(url: EditorSchemeHandler.editorURL))
        preLoaded.insert(ObjectIdentifier(first))
        available.append(first)

        // Pre-warm spell checker (first invocation loads dictionaries)
        NSSpellChecker.shared.checkSpelling(of: "warmup", startingAt: 0)

        // Defer remaining WKWebViews to avoid blocking main thread
        Task { @MainActor in
            for _ in 0..<2 {
                available.append(createWebView())
            }
        }

        NSLog("[Perf] warmUp end at %@ms", msSinceStart())
    }

    /// Get a WKWebView from the pool (or create one if empty).
    /// FIFO order: pre-loaded (first in) gets dequeued first.
    func dequeue() -> WKWebView {
        if !available.isEmpty {
            return available.removeFirst()
        }
        return createWebView()
    }

    /// Check if a WKWebView was pre-loaded with HTML in warmUp().
    /// Returns true once, then clears the flag.
    func consumePreLoadedFlag(_ webView: WKWebView) -> Bool {
        let id = ObjectIdentifier(webView)
        if preLoaded.contains(id) {
            preLoaded.remove(id)
            return true
        }
        return false
    }

    /// Return a WKWebView to the pool for reuse
    func enqueue(_ webView: WKWebView) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
        webView.stopLoading()
        available.append(webView)
    }

    /// Mark an editor as most recently used. Evicts LRU if over limit.
    func markActive(_ editor: EditorViewController) {
        liveEditors.removeAll { $0 === editor }
        liveEditors.append(editor)
        evictIfNeeded()
    }

    /// Remove an editor from tracking (tab closed)
    func remove(_ editor: EditorViewController) {
        liveEditors.removeAll { $0 === editor }
    }

    private func evictIfNeeded() {
        while liveEditors.count > maxLive {
            let evicted = liveEditors.removeFirst()
            evicted.virtualize()
        }
    }

    /// Shared scheme handler — serves editor HTML on kern:// scheme
    let schemeHandler = EditorSchemeHandler()

    func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = processPool

        let userContentController = WKUserContentController()
        config.userContentController = userContentController

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Register custom scheme so the WKWebView has a proper origin
        // and can make outbound HTTPS requests for images etc.
        config.setURLSchemeHandler(schemeHandler, forURLScheme: EditorSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true

        // Disable background drawing to eliminate white flash in dark mode.
        // Private SPI — MarkEdit ships with this on the App Store.
        webView.setValue(false, forKey: "drawsBackground")

        return webView
    }
}
