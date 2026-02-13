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
        let out = NativeMarkdownCodec.exportMarkdown(NativeMarkdownCodec.importMarkdown(md))
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
        let out = NativeMarkdownCodec.exportMarkdown(NativeMarkdownCodec.importMarkdown(md))
        XCTAssertTrue(out.contains("---"))
    }

    @MainActor
    func testImagesRoundTrip() throws {
        try TestGates.skipUnlessExhaustive()
        XCTExpectFailure("Images not supported yet (spec placeholder)")

        let md = "![alt](https://example.com/image.png)"
        let out = NativeMarkdownCodec.exportMarkdown(NativeMarkdownCodec.importMarkdown(md))
        XCTAssertTrue(out.contains("![alt]("))
    }

    @MainActor
    func testStrikethroughRoundTrip() throws {
        try TestGates.skipUnlessExhaustive()
        XCTExpectFailure("GFM strikethrough syntax not supported yet (spec placeholder)")

        let md = "This is ~~deleted~~ text."
        let out = NativeMarkdownCodec.exportMarkdown(NativeMarkdownCodec.importMarkdown(md))
        XCTAssertTrue(out.contains("~~deleted~~"))
    }

    @MainActor
    func testAutolinksRoundTrip() throws {
        try TestGates.skipUnlessExhaustive()
        XCTExpectFailure("Autolinks not supported yet (spec placeholder)")

        let md = "Visit <https://example.com>."
        let out = NativeMarkdownCodec.exportMarkdown(NativeMarkdownCodec.importMarkdown(md))
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
        let out = NativeMarkdownCodec.exportMarkdown(NativeMarkdownCodec.importMarkdown(md))
        XCTAssertTrue(out.contains("nested"))
    }
}
