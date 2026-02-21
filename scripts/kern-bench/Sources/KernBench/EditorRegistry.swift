import AppKit
import Foundation

struct EditorDefinition {
    let displayName: String
    let appName: String
    let bundleIdentifier: String
    let processName: String
    let architecture: String
    let isElectron: Bool
    /// CLI launch command (e.g., ["code"] for VS Code). Nil = use `open -a`.
    let cliLaunchCommand: [String]?
    /// Extra args for clean launch (suppress session restore).
    let cleanLaunchArgs: [String]
    /// Prefix for helper processes (e.g., "Code Helper" for VS Code Electron children).
    let helperProcessPrefix: String?
}

let knownEditors: [EditorDefinition] = [
    // --- Required editors ---
    .init(displayName: "Kern", appName: "Kern",
          bundleIdentifier: "com.gradigit.kern", processName: "Kern",
          architecture: "Native Swift + TextKit", isElectron: false,
          cliLaunchCommand: nil, cleanLaunchArgs: [],
          helperProcessPrefix: nil),
    .init(displayName: "VS Code", appName: "Visual Studio Code",
          bundleIdentifier: "com.microsoft.VSCode", processName: "Electron",
          architecture: "Electron (Chromium + Node)", isElectron: true,
          cliLaunchCommand: ["code"],
          cleanLaunchArgs: ["--new-window", "--user-data-dir", "/tmp/vscode-bench", "--disable-extensions"],
          helperProcessPrefix: "Code Helper"),
    .init(displayName: "Sublime Text", appName: "Sublime Text",
          bundleIdentifier: "com.sublimetext.4", processName: "sublime_text",
          architecture: "Native C++", isElectron: false,
          cliLaunchCommand: ["subl"],
          cleanLaunchArgs: ["--safe-mode", "--new-window"],
          helperProcessPrefix: nil),
    .init(displayName: "Zed", appName: "Zed",
          bundleIdentifier: "dev.zed.Zed", processName: "zed",
          architecture: "Native Rust + Metal", isElectron: false,
          cliLaunchCommand: ["zed"],
          cleanLaunchArgs: ["--new"],
          helperProcessPrefix: nil),
    .init(displayName: "TextEdit", appName: "TextEdit",
          bundleIdentifier: "com.apple.TextEdit", processName: "TextEdit",
          architecture: "Native AppKit", isElectron: false,
          cliLaunchCommand: nil, cleanLaunchArgs: [],
          helperProcessPrefix: nil),
    .init(displayName: "MarkText", appName: "MarkText",
          bundleIdentifier: "com.github.marktext.marktext", processName: "MarkText",
          architecture: "Electron", isElectron: true,
          cliLaunchCommand: nil, cleanLaunchArgs: [],
          helperProcessPrefix: nil),

    // --- Optional editors ---
    .init(displayName: "Typora", appName: "Typora",
          bundleIdentifier: "abnerworks.Typora", processName: "Typora",
          architecture: "Electron", isElectron: true,
          cliLaunchCommand: nil, cleanLaunchArgs: [],
          helperProcessPrefix: nil),
    .init(displayName: "iA Writer", appName: "iA Writer",
          bundleIdentifier: "pro.writer.mac", processName: "iA Writer",
          architecture: "Native AppKit", isElectron: false,
          cliLaunchCommand: nil, cleanLaunchArgs: [],
          helperProcessPrefix: nil),
    .init(displayName: "Nova", appName: "Nova",
          bundleIdentifier: "com.panic.Nova", processName: "Nova",
          architecture: "Native AppKit", isElectron: false,
          cliLaunchCommand: nil, cleanLaunchArgs: [],
          helperProcessPrefix: nil),
    .init(displayName: "BBEdit", appName: "BBEdit",
          bundleIdentifier: "com.barebones.bbedit", processName: "BBEdit",
          architecture: "Native AppKit", isElectron: false,
          cliLaunchCommand: nil, cleanLaunchArgs: [],
          helperProcessPrefix: nil),
    .init(displayName: "CotEditor", appName: "CotEditor",
          bundleIdentifier: "com.coteditor.CotEditor", processName: "CotEditor",
          architecture: "Native AppKit", isElectron: false,
          cliLaunchCommand: nil, cleanLaunchArgs: [],
          helperProcessPrefix: nil),
]

func isEditorInstalled(_ editor: EditorDefinition) -> Bool {
    // Use NSWorkspace for bundle ID lookup first (most reliable).
    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleIdentifier) != nil {
        return true
    }
    // Fallback: check common paths.
    let paths = [
        "/Applications/\(editor.appName).app",
        "/System/Applications/\(editor.appName).app",
        NSHomeDirectory() + "/Applications/\(editor.appName).app",
    ]
    return paths.contains { FileManager.default.fileExists(atPath: $0) }
}

func detectInstalledEditors() -> [EditorDefinition] {
    knownEditors.filter { isEditorInstalled($0) }
}

func findEditor(named name: String) -> EditorDefinition? {
    knownEditors.first { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }
}

/// Read the CFBundleShortVersionString from an editor's Info.plist.
func editorVersion(_ editor: EditorDefinition) -> String? {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleIdentifier) else {
        return nil
    }
    let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
    guard let dict = NSDictionary(contentsOf: plistURL) else { return nil }
    return dict["CFBundleShortVersionString"] as? String
}
