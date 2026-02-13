@preconcurrency import AppKit

/// NSDocument subclass for markdown files.
/// NOT @MainActor at class level — read/write methods are called on background threads.
/// @preconcurrency suppresses Swift 6 strict MainActor checks on NSDocument bridge thunks,
/// allowing NSDocumentController to call init(contentsOf:ofType:) from background threads.
final class EditorDocument: NSDocument {

    /// Current markdown content — updated by contentChanged callback
    var stringValue: String = ""

    /// Track the last known file modification date to prevent autosave↔file watching loops
    var lastKnownFileModDate: Date?

    // MARK: - Init (must be nonisolated for NSDocumentController background opening)

    nonisolated override init() {
        super.init()
    }

    // MARK: - Document Configuration

    override class var autosavesInPlace: Bool { true }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }

    // MARK: - Reading

    override func read(from data: Data, ofType typeName: String) throws {
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: unimpErr,
                userInfo: [NSLocalizedDescriptionKey: "Unable to read file as UTF-8 text"]
            )
        }
        stringValue = content
    }

    // MARK: - Writing

    override func data(ofType typeName: String) throws -> Data {
        guard let data = stringValue.data(using: .utf8) else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: unimpErr,
                userInfo: [NSLocalizedDescriptionKey: "Unable to encode content as UTF-8"]
            )
        }
        return data
    }

    // MARK: - Window Controllers

    @MainActor
    override func makeWindowControllers() {
        // Restore Dock icon and menu bar if app was hidden in background daemon mode
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        let windowController = EditorWindowController()
        addWindowController(windowController)

        // Connect the editor VC to this document
        if let editorVC = windowController.contentViewController as? EditorViewController {
            editorVC.stringValue = stringValue
            editorVC.onContentChanged = { [weak self] markdown in
                self?.stringValue = markdown
                self?.updateChangeCount(.changeDone)
            }
        } else if let editorVC = windowController.contentViewController as? NativeEditorViewController {
            editorVC.stringValue = stringValue
            editorVC.onContentChanged = { [weak self] markdown in
                self?.stringValue = markdown
            }
        }
    }

    // MARK: - Save Hooks

    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
        lastKnownFileModDate = Date()
    }

    // MARK: - File Watching

    private var reloadWorkItem: DispatchWorkItem?

    override func presentedItemDidChange() {
        // Called on NSFilePresenter queue — dispatch to main to avoid deadlock.
        // Never do file coordination inside presentedItemDidChange.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reloadWorkItem?.cancel()

            guard let fileURL = self.fileURL, let fileType = self.fileType else { return }

            // Debounce: 300ms batches rapid AI agent writes
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                    let modDate = attrs[.modificationDate] as? Date
                    guard let modDate,
                          modDate > (self.lastKnownFileModDate ?? .distantPast) else {
                        return
                    }
                    self.lastKnownFileModDate = modDate

                    try self.revert(toContentsOf: fileURL, ofType: fileType)

                    // Push reverted content to editor with scroll preservation
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let hostVC = self.hostViewController,
                           hostVC.hasFinishedLoading,
                           hostVC.bridge != nil {
                            let scrollPos = try? await hostVC.bridge?.getScrollPosition()
                            try? await hostVC.bridge?.setMarkdown(self.stringValue)
                            if let scrollPos {
                                try? await hostVC.bridge?.setScrollPosition(scrollPos)
                            }
                            hostVC.showReloadToast()
                        } else if let hostVC = self.hostNativeViewController {
                            hostVC.applyExternalMarkdownUpdate(self.stringValue)
                            hostVC.showReloadToast()
                        }
                    }
                } catch {
                    NSLog("[EditorDocument] File reload failed: %@", error.localizedDescription)
                }
            }
            self.reloadWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }
    }

    // MARK: - Helpers

    /// Find the EditorViewController from our window controllers
    @MainActor
    var hostViewController: EditorViewController? {
        windowControllers
            .compactMap { $0.contentViewController as? EditorViewController }
            .first
    }

    /// Find the NativeEditorViewController from our window controllers
    @MainActor
    var hostNativeViewController: NativeEditorViewController? {
        windowControllers
            .compactMap { $0.contentViewController as? NativeEditorViewController }
            .first
    }
}
