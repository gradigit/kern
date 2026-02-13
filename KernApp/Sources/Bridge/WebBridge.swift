import WebKit

/// Handles Swift→JS communication via callAsyncJavaScript
@MainActor
final class WebBridge {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - Markdown

    func getMarkdown() async throws -> String {
        let result = try await callJS("return window.kern.getMarkdown();")
        return result as? String ?? ""
    }

    func setMarkdown(_ markdown: String) async throws {
        try await callJS(
            "window.kern.setMarkdown(markdown);",
            arguments: ["markdown": markdown]
        )
    }

    // MARK: - Theme

    func setTheme(_ theme: String) async throws {
        try await callJS(
            "window.kern.setTheme(theme);",
            arguments: ["theme": theme]
        )
    }

    // MARK: - Scroll

    func getScrollPosition() async throws -> Double {
        let result = try await callJS("return window.kern.getScrollPosition();")
        return result as? Double ?? 0
    }

    func setScrollPosition(_ position: Double) async throws {
        try await callJS(
            "window.kern.setScrollPosition(position);",
            arguments: ["position": position]
        )
    }

    // MARK: - Commands

    func execCommand(_ command: String) async throws -> Bool {
        let result = try await callJS(
            "return window.kern.execCommand(command);",
            arguments: ["command": command]
        )
        return result as? Bool ?? false
    }

    // MARK: - Navigation

    func scrollToAnchor(_ id: String) async throws {
        try await callJS(
            """
            (function() {
                var el = document.getElementById(id);
                if (el) { el.scrollIntoView({ behavior: 'smooth' }); return; }
                var target = id.toLowerCase().trim().replace(/[^\\w\\s-]/g, '').replace(/\\s+/g, '-').replace(/-+/g, '-');
                var editor = document.querySelector('.milkdown .editor');
                if (!editor) return;
                var headings = editor.querySelectorAll('h1, h2, h3, h4, h5, h6');
                for (var i = 0; i < headings.length; i++) {
                    var h = headings[i];
                    var hSlug = (h.textContent || '').toLowerCase().trim().replace(/[^\\w\\s-]/g, '').replace(/\\s+/g, '-').replace(/-+/g, '-');
                    if (hSlug === target) { h.scrollIntoView({ behavior: 'smooth' }); return; }
                    var hId = h.getAttribute('id');
                    if (hId) {
                        var idSlug = hId.toLowerCase().trim().replace(/[^\\w\\s-]/g, '').replace(/\\s+/g, '-').replace(/-+/g, '-');
                        if (idSlug === target) { h.scrollIntoView({ behavior: 'smooth' }); return; }
                    }
                }
            })();
            """,
            arguments: ["id": id]
        )
    }

    // MARK: - Search

    func showSearch(replace: Bool) async throws {
        try await callJS(
            "window.kern.showSearch(replace);",
            arguments: ["replace": replace]
        )
    }

    func hideSearch() async throws {
        try await callJS("window.kern.hideSearch();")
    }

    func useSelectionForFind() async throws {
        try await callJS("window.kern.useSelectionForFind();")
    }

    // MARK: - Ready check

    func isReady() async throws -> Bool {
        let result = try await callJS("return window.kern?.isReady() ?? false;")
        return result as? Bool ?? false
    }

    // MARK: - Private

    @discardableResult
    private func callJS(
        _ script: String,
        arguments: [String: Any] = [:]
    ) async throws -> Any? {
        guard let webView else {
            throw WebBridgeError.webViewDeallocated
        }
        return try await webView.callAsyncJavaScript(
            script,
            arguments: arguments,
            contentWorld: .page
        )
    }
}

enum WebBridgeError: Error, LocalizedError {
    case webViewDeallocated

    var errorDescription: String? {
        switch self {
        case .webViewDeallocated:
            return "WKWebView has been deallocated"
        }
    }
}
