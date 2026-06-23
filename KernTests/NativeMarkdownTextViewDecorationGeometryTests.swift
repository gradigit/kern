import AppKit
import XCTest
@testable import KernTextKit

@MainActor
final class NativeMarkdownTextViewDecorationGeometryTests: XCTestCase {
    func testCheckboxDecorationsCoverCheckedAndUncheckedTasksInLightAndDarkAppearances() {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let textView = makeTextView(markdown: "- [x] Done\n- [ ] Todo\n")
            textView.appearance = NSAppearance(named: appearanceName)
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)

            let decorations = textView._debugCheckboxDecorationsForTests(in: textView.bounds)

            XCTAssertEqual(decorations.count, 2, "Expected both task checkboxes under \(appearanceName.rawValue)")
            XCTAssertEqual(decorations.map(\.checked), [true, false])
            XCTAssertEqual(decorations.map(\.characterRange.length), [1, 1])
            for decoration in decorations {
                XCTAssertGreaterThanOrEqual(decoration.rect.width, 12)
                XCTAssertEqual(decoration.rect.width, decoration.rect.height, accuracy: 0.5)
                XCTAssertTrue(textView.bounds.insetBy(dx: -1, dy: -1).intersects(decoration.rect))
            }
        }
    }

    func testCalloutGroupCoversMultiLineCalloutAndStopsBeforeOrdinaryQuote() {
        let markdown = "> [!NOTE] Example allowlist status\n> Body line\n\n> ordinary quote\n"
        let textView = makeTextView(markdown: markdown)
        guard let storage = textView.textStorage else {
            XCTFail("Expected text storage")
            return
        }

        let ns = storage.string as NSString
        let titleRange = ns.range(of: "Example allowlist status")
        let bodyRange = ns.range(of: "Body line")
        let ordinaryRange = ns.range(of: "ordinary quote")
        XCTAssertNotEqual(titleRange.location, NSNotFound)
        XCTAssertNotEqual(bodyRange.location, NSNotFound)
        XCTAssertNotEqual(ordinaryRange.location, NSNotFound)

        guard let group = textView._debugCalloutGroupRangeForTests(containing: bodyRange.location) else {
            XCTFail("Expected body line to resolve to a callout group")
            return
        }

        XCTAssertTrue(NSLocationInRange(titleRange.location, group))
        XCTAssertTrue(NSLocationInRange(bodyRange.location, group))
        XCTAssertFalse(NSLocationInRange(ordinaryRange.location, group))
        XCTAssertNil(textView._debugCalloutGroupRangeForTests(containing: ordinaryRange.location))
    }

    private func makeTextView(markdown: String) -> NativeMarkdownTextView {
        let attributed = NativeMarkdownCodec.importMarkdown(markdown)
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NativeMarkdownTextView(
            frame: NSRect(x: 0, y: 0, width: 760, height: 480),
            textContainer: textContainer
        )
        textView.textContainerInset = NSSize(width: 32, height: 24)
        textView.isEditable = false
        textView.font = NativeEditorAppearance.baseFont()
        layoutManager.ensureLayout(for: textContainer)
        return textView
    }
}
