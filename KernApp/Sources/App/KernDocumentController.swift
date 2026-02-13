import AppKit

/// Custom NSDocumentController that tracks when documents are opened via Apple Events.
/// Instantiated in main.swift before app.run() so it becomes NSDocumentController.shared.
/// This lets AppDelegate reliably detect pending file opens and skip creating untitled docs.
@MainActor
final class KernDocumentController: NSDocumentController {

    /// Set synchronously on main thread the moment a document open begins.
    /// Checked by AppDelegate.openUntitledIfNeeded() to avoid creating
    /// an unwanted untitled document during cold launch with a file argument.
    private(set) var hasOpenedDocument = false

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        hasOpenedDocument = true
        super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
    }
}
