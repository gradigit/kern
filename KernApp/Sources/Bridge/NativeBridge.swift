import WebKit

/// Protocol for receiving messages from JavaScript
@MainActor
protocol NativeBridgeDelegate: AnyObject {
    func editorReady()
    func contentChanged(markdown: String)
    func scrollChanged(position: Double)
    func editorError(message: String, stack: String)
    func openURL(url: String)
}

/// Handles JS→Swift communication via WKScriptMessageHandler.
/// WKScriptMessageHandler callbacks are always dispatched on the main thread,
/// so @MainActor is safe here.
@MainActor
final class NativeBridge: NSObject, WKScriptMessageHandler {
    weak var delegate: NativeBridgeDelegate?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else { return }

        switch type {
        case "editorReady":
            delegate?.editorReady()
        case "contentChanged":
            if let markdown = body["markdown"] as? String {
                delegate?.contentChanged(markdown: markdown)
            }
        case "scrollChanged":
            if let position = body["position"] as? Double {
                delegate?.scrollChanged(position: position)
            }
        case "openURL":
            if let urlString = body["url"] as? String {
                delegate?.openURL(url: urlString)
            }
        case "error":
            let errorMessage = body["message"] as? String ?? "Unknown error"
            let stack = body["stack"] as? String ?? ""
            delegate?.editorError(message: errorMessage, stack: stack)
        default:
            break
        }
    }
}
