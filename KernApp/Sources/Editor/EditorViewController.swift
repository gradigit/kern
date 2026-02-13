import AppKit
import WebKit

/// Hosts a WKWebView running the Milkdown Crepe editor.
/// Supports virtualization: the WKWebView can be released to save memory
/// and rehydrated when the tab becomes active again.
@MainActor
final class EditorViewController: NSViewController, NativeBridgeDelegate {

    private(set) var webView: WKWebView?
    private(set) var bridge: WebBridge?
    private let nativeBridge = NativeBridge()

    /// Whether the editor has finished loading and is ready for bridge calls
    private(set) var hasFinishedLoading = false

    /// Whether this editor has been virtualized (no live WKWebView)
    private(set) var isVirtualized = false

    /// Cached scroll position — updated by JS scroll listener, used during virtualization
    var cachedScrollPosition: Double = 0

    /// Crash recovery counter to prevent infinite reload loops
    private var crashCount = 0
    private let maxCrashRetries = 3

    /// Suppress didSet during contentChanged to prevent JS→Swift→JS loop
    private var suppressStringValueDidSet = false

    /// Whether initial content was injected via __kern_initialContent
    /// (so editorReady doesn't need to call setMarkdown again)
    private var didInjectInitialContent = false

    /// Cached markdown value — updated on every contentChanged callback.
    /// Used as fallback when bridge is not ready, and as source during virtualization.
    /// The didSet handles two timing cases:
    /// 1. Editor already ready (pre-loaded WKWebView) — calls setMarkdown directly
    /// 2. Editor still loading — injects content as global var for JS to pick up during init
    var stringValue: String = "" {
        didSet {
            guard !suppressStringValueDidSet, !stringValue.isEmpty, stringValue != oldValue else { return }
            if hasFinishedLoading {
                // Editor already ready — normal bridge call
                Task {
                    try? await bridge?.setMarkdown(stringValue)
                }
            } else if let webView, webView.isLoading {
                // Editor still loading — inject content as global variable.
                // main.ts will check window.__kern_initialContent after Crepe init
                // and apply it immediately, skipping the editorReady→setMarkdown round-trip.
                didInjectInitialContent = true
                Task { @MainActor in
                    let _ = try? await webView.callAsyncJavaScript(
                        "window.__kern_initialContent = content;",
                        arguments: ["content": stringValue],
                        contentWorld: .page
                    )
                }
            }
        }
    }

    /// Called when content changes (for document integration)
    var onContentChanged: ((String) -> Void)?

    // MARK: - Lifecycle

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        let newWebView = EditorReusePool.shared.dequeue()
        attachWebView(newWebView, to: container)

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            await checkIfPreLoaded()
        }
    }

    /// Check if the dequeued WKWebView was pre-loaded with HTML in the pool.
    /// If so, the HTML is already loading — nativeBridge handler was registered
    /// in attachWebView(), so editorReady will fire when loading completes.
    /// If not, start a fresh load.
    private func checkIfPreLoaded() async {
        guard let webView else {
            loadEditorHTML()
            return
        }

        // Check pool flag — was this WKWebView pre-loaded in warmUp()?
        if EditorReusePool.shared.consumePreLoadedFlag(webView) {
            NSLog("[Perf] Pre-loaded WKWebView dequeued at %@ms, isLoading=%d",
                  msSinceStart(), webView.isLoading ? 1 : 0)

            if !webView.isLoading {
                // Loading already completed — check if JS is ready
                do {
                    let result = try await webView.callAsyncJavaScript(
                        "return typeof window.kern !== 'undefined' && window.kern.isReady()",
                        arguments: [:],
                        contentWorld: .page
                    )
                    if result as? Bool == true {
                        editorReady()
                        return
                    }
                } catch {
                    // JS not available — page was reset
                }
                // Pre-load completed but JS not ready — reload
                loadEditorHTML()
            }
            // else: isLoading=true, nativeBridge registered, editorReady will fire
            return
        }

        // Not pre-loaded — fresh WKWebView, load normally
        loadEditorHTML()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        if isVirtualized {
            rehydrate()
        }
        EditorReusePool.shared.markActive(self)
    }

    // MARK: - WebView Management

    private func attachWebView(_ newWebView: WKWebView, to container: NSView) {
        webView = newWebView

        let config = newWebView.configuration
        config.userContentController.removeAllScriptMessageHandlers()
        config.userContentController.add(nativeBridge, name: "nativeBridge")

        nativeBridge.delegate = self
        newWebView.navigationDelegate = self
        newWebView.uiDelegate = self

        newWebView.frame = container.bounds
        newWebView.autoresizingMask = [.width, .height]
        container.addSubview(newWebView)
    }

    // MARK: - HTML Loading

    func loadEditorHTML() {
        // Load via the kern:// custom scheme handler.
        // This gives the WKWebView a proper origin so it can make
        // outbound HTTPS requests for images and external resources.
        let request = URLRequest(url: EditorSchemeHandler.editorURL)
        webView?.load(request)
    }

    // MARK: - Virtualization

    /// Release WKWebView to save memory. Content is preserved in stringValue.
    func virtualize() {
        guard !isVirtualized, let webView else { return }

        isVirtualized = true
        hasFinishedLoading = false
        didInjectInitialContent = false

        webView.removeFromSuperview()
        EditorReusePool.shared.enqueue(webView)

        self.webView = nil
        bridge = nil
    }

    /// Restore a live WKWebView. Content is restored in editorReady().
    func rehydrate() {
        guard isVirtualized else { return }
        isVirtualized = false

        let newWebView = EditorReusePool.shared.dequeue()
        attachWebView(newWebView, to: view)
        loadEditorHTML()
    }

    /// Clean up when tab is closing — return WKWebView to pool
    func releaseWebView() {
        EditorReusePool.shared.remove(self)
        guard let webView, !isVirtualized else { return }
        webView.removeFromSuperview()
        EditorReusePool.shared.enqueue(webView)
        self.webView = nil
        bridge = nil
        hasFinishedLoading = false
    }

    // MARK: - NativeBridgeDelegate

    func editorReady() {
        NSLog("[Perf] editorReady at %@ms", msSinceStart())
        hasFinishedLoading = true
        crashCount = 0
        bridge = WebBridge(webView: webView!)

        // Restore content (from document or after rehydration)
        if !stringValue.isEmpty {
            if didInjectInitialContent {
                // Content was injected via __kern_initialContent and applied by JS during init.
                // No need to call setMarkdown again — just log and restore scroll.
                NSLog("[Perf] setMarkdown skipped (initial content injected) at %@ms", msSinceStart())
                didInjectInitialContent = false
                if cachedScrollPosition > 0 {
                    Task {
                        try? await bridge?.setScrollPosition(cachedScrollPosition)
                    }
                }
            } else {
                Task {
                    try? await bridge?.setMarkdown(stringValue)
                    NSLog("[Perf] setMarkdown complete at %@ms", msSinceStart())
                    if cachedScrollPosition > 0 {
                        try? await bridge?.setScrollPosition(cachedScrollPosition)
                    }
                }
            }
        }

        // Apply current system appearance
        Task {
            let theme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
            try? await bridge?.setTheme(theme)
        }
    }

    func contentChanged(markdown: String) {
        suppressStringValueDidSet = true
        stringValue = markdown
        suppressStringValueDidSet = false
        onContentChanged?(markdown)
    }

    func scrollChanged(position: Double) {
        cachedScrollPosition = position
    }

    func editorError(message: String, stack: String) {
        NSLog("[EditorVC] JS Error: %@", message)
        if !stack.isEmpty {
            NSLog("[EditorVC] Stack: %@", stack)
        }
    }

    func openURL(url urlString: String) {
        // Fragment-only → scroll within the document
        if urlString.hasPrefix("#") {
            let anchorID = String(urlString.dropFirst())
            Task {
                try? await bridge?.scrollToAnchor(anchorID)
            }
            return
        }
        // External URL → open in default browser
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Format Actions (responder chain targets for menu items)

    @objc func toggleBold(_ sender: Any?) {
        Task { let _ = try? await bridge?.execCommand("bold") }
    }

    @objc func toggleItalic(_ sender: Any?) {
        Task { let _ = try? await bridge?.execCommand("italic") }
    }

    @objc func toggleCode(_ sender: Any?) {
        Task { let _ = try? await bridge?.execCommand("code") }
    }

    // MARK: - Find Actions

    @objc func showFind(_ sender: Any?) {
        Task { try? await bridge?.showSearch(replace: false) }
    }

    @objc func showFindReplace(_ sender: Any?) {
        Task { try? await bridge?.showSearch(replace: true) }
    }

    @objc func useSelectionForFind(_ sender: Any?) {
        Task { try? await bridge?.useSelectionForFind() }
    }

    // MARK: - Toast

    private var toastView: NSView?

    func showReloadToast() {
        toastView?.removeFromSuperview()

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0, alpha: 0.7).cgColor
        container.layer?.cornerRadius = 8

        let label = NSTextField(labelWithString: "File reloaded from disk")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.sizeToFit()

        let hPad: CGFloat = 12
        let vPad: CGFloat = 6
        container.frame = NSRect(
            x: 0, y: 0,
            width: label.frame.width + hPad * 2,
            height: label.frame.height + vPad * 2
        )
        label.frame.origin = NSPoint(x: hPad, y: vPad)
        container.addSubview(label)

        container.frame.origin = NSPoint(
            x: (view.bounds.width - container.frame.width) / 2,
            y: view.bounds.height - container.frame.height - 12
        )
        container.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]

        view.addSubview(container)
        toastView = container

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            self.dismissToast()
        }
    }

    private func dismissToast() {
        guard let toast = toastView else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            toast.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.toastView?.removeFromSuperview()
                self?.toastView = nil
            }
        })
    }
}

// MARK: - NSMenuItemValidation

extension EditorViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleBold), #selector(toggleItalic), #selector(toggleCode),
             #selector(showFind), #selector(showFindReplace), #selector(useSelectionForFind):
            return hasFinishedLoading && bridge != nil
        default:
            return true
        }
    }
}

// MARK: - WKUIDelegate

extension EditorViewController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Links with target="_blank" (e.g. tooltip <a>) call this instead of navigation.
        // Open the URL in the default browser and return nil to prevent WKWebView creation.
        if let url = navigationAction.request.url {
            if url.fragment != nil && (url.scheme == nil || url.absoluteString.hasPrefix("#")) {
                Task { try? await bridge?.scrollToAnchor(url.fragment!) }
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }
}

// MARK: - WKNavigationDelegate

extension EditorViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Fragment-only link — scroll within the document
        if url.fragment != nil && (url.scheme == nil || url.absoluteString.hasPrefix("#")) {
            let anchorID = url.fragment!
            Task {
                try? await bridge?.scrollToAnchor(anchorID)
            }
            decisionHandler(.cancel)
            return
        }

        // External URL — open in default browser
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        NSLog("[EditorVC] Navigation failed: %@", error.localizedDescription)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        NSLog("[EditorVC] Provisional navigation failed: %@", error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        crashCount += 1
        NSLog("[EditorVC] WebContent process terminated (crash #%d)", crashCount)
        hasFinishedLoading = false
        bridge = nil

        guard crashCount <= maxCrashRetries else {
            NSLog("[EditorVC] Max crash retries exceeded, not reloading")
            return
        }

        // Reload — content restored from stringValue in editorReady()
        loadEditorHTML()
    }
}

