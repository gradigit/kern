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

    @MainActor
    func testTableWithPlainEmptyAndFormattedCellsRoundTrips() {
        let md = """
        | Name | Notes | Status |
        | --- | --- | --- |
        | Alpha |  | **Ready** |
        | Beta | plain text | `code` |
        """

        let attr = NativeMarkdownCodec.importMarkdown(md)
        let out = NativeMarkdownCodec.exportMarkdown(attr)

        XCTAssertFalse(attr.string.contains("|"))
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), md)
    }

    @MainActor
    func testRepeatedIdenticalTablesKeepDistinctTableIDsWhenCacheReusesAttributedBase() {
        let md = """
        | A | B |
        | --- | --- |
        | 1 | 2 |

        | A | B |
        | --- | --- |
        | 1 | 2 |
        """

        let attr = NativeMarkdownCodec.importMarkdown(md)
        let ns = attr.string as NSString

        var tableIDs: [Int] = []
        var paragraphStart = 0
        while paragraphStart < ns.length {
            let paragraphRange = ns.paragraphRange(for: NSRange(location: paragraphStart, length: 0))
            if let kindRaw = attr.attribute(.kernBlockKind, at: paragraphRange.location, effectiveRange: nil) as? Int,
               let kind = KernBlockKind(rawValue: kindRaw),
               kind == .tableCell,
               let tableID = attr.attribute(.kernTableID, at: paragraphRange.location, effectiveRange: nil) as? Int,
               tableIDs.last != tableID {
                tableIDs.append(tableID)
            }
            paragraphStart = paragraphRange.location + paragraphRange.length
        }

        XCTAssertEqual(tableIDs.count, 2)
        XCTAssertNotEqual(tableIDs[0], tableIDs[1])
    }
}
