import AppKit

/// Observes system appearance changes and broadcasts theme updates to all live editors.
@MainActor
final class AppearanceManager {
    static let shared = AppearanceManager()

    private var observation: NSKeyValueObservation?

    private init() {}

    func startObserving() {
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.broadcastTheme()
            }
        }
    }

    func broadcastTheme() {
        let theme = currentTheme()
        let documents = NSDocumentController.shared.documents
        for document in documents {
            guard let editorDoc = document as? EditorDocument else { continue }
            guard let hostVC = editorDoc.hostViewController,
                  hostVC.hasFinishedLoading,
                  let bridge = hostVC.bridge else { continue }
            Task {
                try? await bridge.setTheme(theme)
            }
        }
    }

    func currentTheme() -> String {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
    }
}
