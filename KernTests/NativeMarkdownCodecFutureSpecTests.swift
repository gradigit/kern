import XCTest
@testable import KernTextKit

/// Forward-looking spec tests for Markdown features not yet implemented by the native TextKit codec.
///
/// These are gated behind `KERN_ENABLE_EXHAUSTIVE_TESTS=1` and use `XCTExpectFailure` so they can
/// live in-tree without breaking the default test run. As features land, remove `XCTExpectFailure`
/// and/or the gate for that test.
final class NativeMarkdownCodecFutureSpecTests: XCTestCase {
    @MainActor
    func testBlockquoteRoundTrip() throws {
        try TestGates.skipUnlessExhaustive()
        XCTExpectFailure("Blockquotes not supported yet (spec placeholder)")

        let md = """
        > quote line 1
        > quote line 2
        """
        let attr = NativeMarkdownCodec.importMarkdown(md)

        // A true WYSIWYG import should hide the literal `> ` markers.
        XCTAssertEqual(attr.string.trimmingCharacters(in: .whitespacesAndNewlines), "quote line 1\nquote line 2")

        // Export should preserve blockquote syntax.
        let out = NativeMarkdownCodec.exportMarkdown(attr)
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), md)
    }

    @MainActor
    func testThematicBreakRoundTrip() throws {
        try TestGates.skipUnlessExhaustive()
        XCTExpectFailure("Thematic breaks not supported yet (spec placeholder)")

        let md = """
        Before

        ---

        After
        """
        let attr = NativeMarkdownCodec.importMarkdown(md)

        // WYSIWYG should render the rule without leaving the raw `---` in the visible text.
        XCTAssertFalse(attr.string.contains("---"))

        let out = NativeMarkdownCodec.exportMarkdown(attr)
        XCTAssertTrue(out.contains("---"))
    }

    @MainActor
    func testImagesRoundTrip() throws {
        try TestGates.skipUnlessExhaustive()
        XCTExpectFailure("Images not supported yet (spec placeholder)")

        let md = "![alt](https://example.com/image.png)"
        let attr = NativeMarkdownCodec.importMarkdown(md)

        // A native WYSIWYG import should not show the raw image syntax; it should create an attachment
        // or a non-syntax placeholder.
        XCTAssertFalse(attr.string.contains("![alt]("))
        var hasAttachment = false
        attr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attr.length), options: []) { value, _, stop in
            if value != nil {
                hasAttachment = true
                stop.pointee = true
            }
        }
        XCTAssertTrue(hasAttachment)

        let out = NativeMarkdownCodec.exportMarkdown(attr)
        XCTAssertTrue(out.contains("![alt]("))
    }

    @MainActor
    func testStrikethroughRoundTrip() throws {
        try TestGates.skipUnlessExhaustive()
        XCTExpectFailure("GFM strikethrough syntax not supported yet (spec placeholder)")

        let md = "This is ~~deleted~~ text."
        let attr = NativeMarkdownCodec.importMarkdown(md)
        let ns = attr.string as NSString
        let r = ns.range(of: "deleted")
        XCTAssertNotEqual(r.location, NSNotFound)

        // WYSIWYG should apply strikethrough style rather than showing `~~`.
        let style = attr.attribute(.strikethroughStyle, at: r.location, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)

        let out = NativeMarkdownCodec.exportMarkdown(attr)
        XCTAssertTrue(out.contains("~~deleted~~"))
    }

    @MainActor
    func testAutolinksRoundTrip() throws {
        try TestGates.skipUnlessExhaustive()
        XCTExpectFailure("Autolinks not supported yet (spec placeholder)")

        let md = "Visit <https://example.com>."
        let attr = NativeMarkdownCodec.importMarkdown(md)
        let ns = attr.string as NSString
        let r = ns.range(of: "https://example.com")
        XCTAssertNotEqual(r.location, NSNotFound)

        // WYSIWYG should apply a link attribute, not just leave literal `<` `>` markers.
        let link = attr.attribute(.link, at: r.location, effectiveRange: nil)
        XCTAssertNotNil(link)

        let out = NativeMarkdownCodec.exportMarkdown(attr)
        XCTAssertTrue(out.contains("<https://example.com>"))
    }

    @MainActor
    func testNestedListsRoundTrip() throws {
        try TestGates.skipUnlessExhaustive()
        XCTExpectFailure("Nested lists not supported yet (spec placeholder)")

        let md = """
        - one
          - nested
        - two
        """
        let attr = NativeMarkdownCodec.importMarkdown(md)

        // WYSIWYG should render nested list markers as bullets, not leave raw `- ` visible.
        XCTAssertFalse(attr.string.contains("- nested"))
        XCTAssertTrue(attr.string.contains("nested"))

        let out = NativeMarkdownCodec.exportMarkdown(attr)
        XCTAssertTrue(out.contains("nested"))
    }
}
