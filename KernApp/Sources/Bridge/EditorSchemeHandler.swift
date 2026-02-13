import WebKit
import UniformTypeIdentifiers

/// Custom URL scheme handler that serves editor files from the app bundle.
/// Using a custom scheme (kern://) gives the WKWebView a proper origin,
/// allowing it to make outbound HTTPS requests for images and resources.
/// Serves all files from CoreEditor/dist/ to support Vite code splitting.
final class EditorSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {

    static let scheme = "kern"
    static let editorURL = URL(string: "kern://editor/index.html")!

    /// Base directory for editor files in the app bundle
    private let distURL: URL? = Bundle.main.url(forResource: "dist", withExtension: nil)

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let distURL = distURL else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        // url.path returns the path component (e.g., "/app-ABC.js", "/chunks/mermaid-XYZ.js")
        // Default to index.html for empty path or root
        var filePath = url.path
        if filePath.isEmpty || filePath == "/" {
            filePath = "/index.html"
        }

        // Strip leading slash for file lookup
        let relativePath = String(filePath.dropFirst())
        let fileURL = distURL.appendingPathComponent(relativePath)

        // Security: ensure the resolved path is within dist/
        let resolvedPath = fileURL.standardizedFileURL.path
        let distPrefix = distURL.standardizedFileURL.path
        guard resolvedPath == distPrefix || resolvedPath.hasPrefix(distPrefix + "/") else {
            NSLog("[SchemeHandler] Path traversal blocked: %@", filePath)
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            NSLog("[SchemeHandler] File not found: %@", relativePath)
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let mimeType = Self.mimeType(for: fileURL)

        // Hash-based filenames (app-HASH.js, chunks/name-HASH.js) never change.
        // Cache-Control: immutable signals JSC to cache compiled bytecode.
        // index.html has no hash — use no-cache so it always gets the latest.
        let cacheControl = relativePath.contains("-") && !relativePath.hasSuffix(".html")
            ? "max-age=31536000, immutable"
            : "no-cache"

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": "\(data.count)",
                "Cache-Control": cacheControl,
                "Access-Control-Allow-Origin": "*",
            ]
        ) else {
            urlSchemeTask.didFailWithError(URLError(.unknown))
            return
        }

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // Nothing to cancel — all responses are synchronous
    }

    // MARK: - MIME Types

    private static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "html": return "text/html"
        case "js", "mjs": return "application/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default:
            if let utType = UTType(filenameExtension: ext) {
                return utType.preferredMIMEType ?? "application/octet-stream"
            }
            return "application/octet-stream"
        }
    }
}
