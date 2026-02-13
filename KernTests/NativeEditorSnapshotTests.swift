import AppKit
import SnapshotTesting
import XCTest
@testable import Kern

final class NativeEditorSnapshotTests: XCTestCase {
    @MainActor
    func testBasicFixture_GfmDefault_Light() throws {
        try TestGates.skipUnlessSnapshots()

        try withNativeEditorDefaults(profile: .gfmDefault) {
            try withSnapshotTesting(record: snapshotRecordMode) {
                let md = try loadFixtureMarkdown(name: "basic.in.md")
                let vc = NativeEditorViewController()
                _ = vc.view
                vc.stringValue = md

                let view = hostInWindow(vc: vc, size: NSSize(width: 900, height: 650), appearance: .init(named: .aqua))
                assertSnapshot(of: view, as: Snapshotting<NSView, NSImage>.image(size: view.bounds.size))
            }
        }
    }

    @MainActor
    func testExtensionsFixture_KernProfile_Dark() throws {
        try TestGates.skipUnlessSnapshots()

        try withNativeEditorDefaults(profile: .kernExtensions) {
            try withSnapshotTesting(record: snapshotRecordMode) {
                let md = try loadFixtureMarkdown(name: "extensions.in.md")
                let vc = NativeEditorViewController()
                _ = vc.view
                vc.stringValue = md

                let view = hostInWindow(vc: vc, size: NSSize(width: 900, height: 650), appearance: .init(named: .darkAqua))
                assertSnapshot(of: view, as: Snapshotting<NSView, NSImage>.image(size: view.bounds.size))
            }
        }
    }

    /// Exhaustive visual matrix. This is intentionally gated behind `KERN_ENABLE_EXHAUSTIVE_TESTS=1`
    /// since it produces many snapshots and can be slow.
    @MainActor
    func testSnapshotMatrix_Exhaustive() throws {
        try TestGates.skipUnlessSnapshots()
        try TestGates.skipUnlessExhaustive()

        let fixtures = [
            "basic.in.md",
            "extensions.in.md",
            "ordered-numbering.in.md",
            "soft-breaks.in.md",
            "tables.in.md",
        ]

        let profiles: [DefaultsProfile] = [.gfmDefault, .kernExtensions]
        let appearances: [(String, NSAppearance?)] = [
            ("light", .init(named: .aqua)),
            ("dark", .init(named: .darkAqua)),
        ]
        let sizes: [(String, NSSize)] = [
            ("sm", .init(width: 700, height: 520)),
            ("lg", .init(width: 900, height: 650)),
        ]

        for profile in profiles {
            try withNativeEditorDefaults(profile: profile) {
                try withSnapshotTesting(record: snapshotRecordMode) {
                    for fixture in fixtures {
                        let md = try loadFixtureMarkdown(name: fixture)

                        for (appearanceName, appearance) in appearances {
                            for (sizeName, size) in sizes {
                                let vc = NativeEditorViewController()
                                _ = vc.view
                                vc.stringValue = md

                                let view = hostInWindow(vc: vc, size: size, appearance: appearance)
                                assertSnapshot(
                                    of: view,
                                    as: Snapshotting<NSView, NSImage>.image(size: view.bounds.size),
                                    named: "\(profile)_\(fixture)_\(appearanceName)_\(sizeName)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Snapshot gating

    private var snapshotRecordMode: SnapshotTestingConfiguration.Record {
        TestGates.recordSnapshots ? .all : .never
    }

    // MARK: - Defaults profiles

    private enum DefaultsProfile {
        case gfmDefault
        case kernExtensions
    }

    private func withNativeEditorDefaults(profile: DefaultsProfile, _ f: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = [
            "nativeEditor.exportDialect",
            "nativeEditor.taskRendering",
            "nativeEditor.orderedTasksEnabled",
            "nativeEditor.headingCheckboxesEnabled",
            "nativeEditor.orderedListNumbering",
        ]

        let previous: [String: Any?] = keys.reduce(into: [:]) { acc, k in
            acc[k] = defaults.object(forKey: k)
        }
        defer {
            for k in keys {
                if let v = previous[k] {
                    defaults.set(v, forKey: k)
                } else {
                    defaults.removeObject(forKey: k)
                }
            }
        }

        switch profile {
        case .gfmDefault:
            defaults.set("gfm", forKey: "nativeEditor.exportDialect")
            defaults.set("gfm", forKey: "nativeEditor.taskRendering")
            defaults.set(false, forKey: "nativeEditor.orderedTasksEnabled")
            defaults.set(false, forKey: "nativeEditor.headingCheckboxesEnabled")
            defaults.set("gfmDefault", forKey: "nativeEditor.orderedListNumbering")
        case .kernExtensions:
            defaults.set("kern", forKey: "nativeEditor.exportDialect")
            defaults.set("kern", forKey: "nativeEditor.taskRendering")
            defaults.set(true, forKey: "nativeEditor.orderedTasksEnabled")
            defaults.set(true, forKey: "nativeEditor.headingCheckboxesEnabled")
            defaults.set("preserveTyped", forKey: "nativeEditor.orderedListNumbering")
        }

        try f()
    }

    // MARK: - Fixtures

    private func loadFixtureMarkdown(name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KernTests/
            .deletingLastPathComponent() // repo root
        let url = root.appendingPathComponent("test-fixtures/native-editor-golden", isDirectory: true)
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Hosting

    @MainActor
    private func hostInWindow(vc: NSViewController, size: NSSize, appearance: NSAppearance?) -> NSView {
        let rect = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.windowBackgroundColor
        window.appearance = appearance
        window.contentViewController = vc

        // Force layout.
        window.setFrame(rect, display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.displayIfNeeded()

        // Snapshot the window's content view (includes background + padding).
        let content = window.contentView ?? vc.view
        content.setFrameSize(size)
        content.layoutSubtreeIfNeeded()
        return content
    }
}
