import XCTest
@testable import KernTextKit

final class NativeMarkdownCodecTableParsingTests: XCTestCase {
    @MainActor
    func testMinimalTwoColumnGfmTableParsesToTableCells() {
        let md = """
        | H1 | H2 |
        | --- | --- |
        | r1c1 | r1c2 |
        """

        let attr = NativeMarkdownCodec.importMarkdown(md)

        // In WYSIWYG mode we should not retain the literal pipe syntax in the attributed string.
        XCTAssertFalse(attr.string.contains("|"))

        let kRaw = attr.attribute(.kernBlockKind, at: 0, effectiveRange: nil) as? Int
        let kind = KernBlockKind(rawValue: kRaw ?? KernBlockKind.paragraph.rawValue) ?? .paragraph
        XCTAssertEqual(kind, .tableCell)
    }

    @MainActor
    func testMinimalTwoColumnGfmTableWithTrailingNewlineParsesToTableCells() {
        let md = """
        | A | B |
        | --- | --- |
        | c | d |

        """

        let attr = NativeMarkdownCodec.importMarkdown(md)
        XCTAssertFalse(attr.string.contains("|"))

        let kRaw = attr.attribute(.kernBlockKind, at: 0, effectiveRange: nil) as? Int
        let kind = KernBlockKind(rawValue: kRaw ?? KernBlockKind.paragraph.rawValue) ?? .paragraph
        XCTAssertEqual(kind, .tableCell)
    }
}
