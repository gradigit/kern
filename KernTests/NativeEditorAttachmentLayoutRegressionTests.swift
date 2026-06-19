import AppKit
import XCTest
@testable import KernTextKit

final class NativeEditorAttachmentLayoutRegressionTests: XCTestCase {
    @MainActor
    func testImagesFixtureAttachmentLineFragmentsStayOrderedAndDistinct() throws {
        let fixtureURL = fixture(path: "test-fixtures/native-editor-golden/images.fixture.md")
        let markdown = try String(contentsOf: fixtureURL, encoding: .utf8)

        try withImageFixtureDefaults {
            let vc = NativeEditorViewController()
            _ = vc.view
            vc.documentURL = fixtureURL
            vc.stringValue = markdown

            let window = hostInWindow(vc: vc, size: NSSize(width: 960, height: 760), appearance: .init(named: .aqua))
            window.displayIfNeeded()

            guard
                let textView = findSubview(withAXIdentifier: "NativeEditor.TextView", in: vc.view) as? NSTextView,
                let storage = textView.textStorage,
                let lm = textView.layoutManager,
                let tc = textView.textContainer
            else {
                XCTFail("Missing TextKit stack")
                return
            }

            waitForLocalImageAttachments(in: textView)
            lm.ensureLayout(for: tc)

            struct ImageLayout {
                let altText: String
                let characterIndex: Int
                let lineMinY: CGFloat
                let lineHeight: CGFloat
                let attachmentHeight: CGFloat
                let hasCell: Bool
            }

            var layouts: [ImageLayout] = []
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
                guard let image = value as? MarkdownImageAttachment else { return }
                let glyphRange = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard glyphRange.length > 0 else { return }
                let lineFragment = lm.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
                let bounds = image.attachmentBounds(
                    for: tc,
                    proposedLineFragment: lineFragment,
                    glyphPosition: .zero,
                    characterIndex: range.location
                )
                layouts.append(ImageLayout(
                    altText: image.altText,
                    characterIndex: range.location,
                    lineMinY: lineFragment.minY,
                    lineHeight: lineFragment.height,
                    attachmentHeight: bounds.height,
                    hasCell: image.attachmentCell != nil
                ))
            }

            XCTAssertEqual(layouts.map(\.altText), [
                "Local sample",
                "Broken local image",
                "Remote sample 1",
                "Remote sample 2",
            ])
            XCTAssertEqual(Set(layouts.map(\.characterIndex)).count, 4, "Expected four distinct image attachment character ranges")
            XCTAssertTrue(layouts.allSatisfy(\.hasCell), "Each image attachment should keep a custom TextKit cell")

            let lineOrigins = layouts.map(\.lineMinY)
            XCTAssertEqual(lineOrigins, lineOrigins.sorted(), "Image attachment line fragments should stay in document order")
            for index in layouts.indices.dropFirst() {
                XCTAssertGreaterThan(
                    layouts[index].lineMinY,
                    layouts[index - 1].lineMinY + 24,
                    "Image attachment line fragments should not collapse onto the same vertical position"
                )
            }

            for layout in layouts {
                XCTAssertGreaterThanOrEqual(layout.lineHeight, layout.attachmentHeight - 12, "Image line fragment should reserve enough vertical space for \(layout.altText)")
            }

            func lineMinY(containing substring: String) -> CGFloat? {
                let nsString = storage.string as NSString
                let range = nsString.range(of: substring)
                guard range.location != NSNotFound else { return nil }
                let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
                guard glyphRange.length > 0 else { return nil }
                return lm.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil).minY
            }

            let beforeParagraphLineY = try XCTUnwrap(lineMinY(containing: "Before image paragraph."))
            let afterParagraphLineY = try XCTUnwrap(lineMinY(containing: "After image paragraph."))
            let firstImage = try XCTUnwrap(layouts.first)
            XCTAssertLessThan(beforeParagraphLineY, firstImage.lineMinY, "Text before the first image should lay out before the first attachment")
            XCTAssertGreaterThan(
                afterParagraphLineY,
                firstImage.lineMinY + firstImage.attachmentHeight,
                "Text after the first image should lay out below the first attachment, not overlap the preceding paragraph (before=\(beforeParagraphLineY), imageY=\(firstImage.lineMinY), imageLineH=\(firstImage.lineHeight), imageAttachH=\(firstImage.attachmentHeight), after=\(afterParagraphLineY))"
            )
        }
    }

    @MainActor
    func testStressFixtureAttachmentLineHeightsStayWithinReasonableBounds() throws {
        let fixtureURL = fixture(path: "test-fixtures/stress-test.md")
        let markdown = try String(contentsOf: fixtureURL, encoding: .utf8)

        let vc = NativeEditorViewController()
        _ = vc.view
        vc.documentURL = fixtureURL
        vc.stringValue = markdown

        let window = hostInWindow(vc: vc, size: NSSize(width: 1000, height: 740), appearance: .init(named: .darkAqua))
        window.displayIfNeeded()

        guard
            let textView = findSubview(withAXIdentifier: "NativeEditor.TextView", in: vc.view) as? NSTextView,
            let storage = textView.textStorage,
            let lm = textView.layoutManager,
            let tc = textView.textContainer
        else {
            XCTFail("Missing TextKit stack")
            return
        }

        lm.ensureLayout(for: tc)

        struct Stats {
            var count = 0
            var maxLineHeight: CGFloat = 0
            var maxAttachmentHeight: CGFloat = 0
            var maxAttachmentWidth: CGFloat = 0
        }
        var image = Stats()
        var math = Stats()
        var mermaid = Stats()
        var thematicBreak = Stats()

        var idx = 0
        while idx < storage.length {
            guard let attachment = storage.attribute(.attachment, at: idx, effectiveRange: nil) as? NSTextAttachment else {
                idx += 1
                continue
            }

            let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: idx, length: 1), actualCharacterRange: nil)
            if glyphRange.length == 0 {
                idx += 1
                continue
            }

            var lineRange = NSRange(location: 0, length: 0)
            let lineFrag = lm.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: &lineRange)
            let bounds = attachment.attachmentBounds(for: tc, proposedLineFragment: lineFrag, glyphPosition: .zero, characterIndex: idx)

            func apply(_ bounds: NSRect, _ lineFrag: NSRect, to stats: inout Stats) {
                stats.count += 1
                stats.maxLineHeight = max(stats.maxLineHeight, lineFrag.height)
                stats.maxAttachmentHeight = max(stats.maxAttachmentHeight, bounds.height)
                stats.maxAttachmentWidth = max(stats.maxAttachmentWidth, bounds.width)
            }

            if attachment is MarkdownImageAttachment {
                apply(bounds, lineFrag, to: &image)
            } else if attachment is MarkdownMathBlockAttachment {
                apply(bounds, lineFrag, to: &math)
            } else if attachment is MarkdownMermaidAttachment {
                apply(bounds, lineFrag, to: &mermaid)
            } else if attachment is ThematicBreakAttachment {
                apply(bounds, lineFrag, to: &thematicBreak)
            }

            idx += 1
        }

        XCTAssertGreaterThanOrEqual(image.count, 1, "Expected at least one image attachment in stress fixture")
        XCTAssertGreaterThanOrEqual(math.count, 1, "Expected at least one block math attachment in stress fixture")
        XCTAssertGreaterThanOrEqual(mermaid.count, 1, "Expected at least one mermaid attachment in stress fixture")
        XCTAssertGreaterThanOrEqual(thematicBreak.count, 1, "Expected at least one thematic break attachment in stress fixture")

        // Hard guards against "single giant line" regressions that create pages of blank space.
        XCTAssertLessThanOrEqual(image.maxLineHeight, 1200, "Image line fragment is unexpectedly tall: \(image.maxLineHeight)")
        XCTAssertLessThanOrEqual(math.maxLineHeight, 260, "Math line fragment is unexpectedly tall: \(math.maxLineHeight)")
        XCTAssertLessThanOrEqual(mermaid.maxLineHeight, 640, "Mermaid line fragment is unexpectedly tall: \(mermaid.maxLineHeight)")
        XCTAssertLessThanOrEqual(thematicBreak.maxLineHeight, 80, "Thematic break line fragment is unexpectedly tall: \(thematicBreak.maxLineHeight)")

        XCTAssertLessThanOrEqual(math.maxAttachmentHeight, 220, "Math attachment bounds too tall: \(math.maxAttachmentHeight)")
        XCTAssertLessThanOrEqual(thematicBreak.maxAttachmentHeight, 32, "Thematic break attachment bounds too tall: \(thematicBreak.maxAttachmentHeight)")
    }

    @MainActor
    private func hostInWindow(vc: NSViewController, size: NSSize, appearance: NSAppearance?) -> NSWindow {
        let rect = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.windowBackgroundColor
        window.appearance = appearance
        window.contentViewController = vc
        window.setFrame(rect, display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    @MainActor
    private func findSubview(withAXIdentifier id: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == id { return view }
        for sub in view.subviews {
            if let found = findSubview(withAXIdentifier: id, in: sub) { return found }
        }
        return nil
    }

    private func fixture(path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KernTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent(path)
    }

    @MainActor
    private func waitForLocalImageAttachments(in textView: NSTextView) {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            guard let storage = textView.textStorage else { return }
            var pendingLocalImages = 0
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length), options: []) { value, _, _ in
                guard let image = value as? MarkdownImageAttachment,
                      image.resolvedURL?.isFileURL == true,
                      image.loadState == .loading
                else { return }
                pendingLocalImages += 1
            }
            if pendingLocalImages == 0 { return }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func withImageFixtureDefaults(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = [
            NativeEditorSyntaxVisibilityMode.userDefaultsKey,
            MarkdownImageAttachment.remoteImageLoadingUserDefaultsKey,
        ]
        let previous = keys.reduce(into: [String: Any?]()) { values, key in
            values[key] = defaults.object(forKey: key)
        }
        defer {
            for key in keys {
                if let value = previous[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        defaults.set(NativeEditorSyntaxVisibilityMode.wysiwyg.rawValue, forKey: NativeEditorSyntaxVisibilityMode.userDefaultsKey)
        defaults.set(false, forKey: MarkdownImageAttachment.remoteImageLoadingUserDefaultsKey)
        try body()
    }
}
