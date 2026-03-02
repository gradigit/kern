import AppKit
import XCTest
@testable import KernTextKit

final class NativeEditorTypographySpacingTests: XCTestCase {
    @MainActor
    func testParagraphAndListBlocksUseReadableParagraphSpacing() {
        let markdown = """
        First paragraph line.

        Second paragraph line.

        - list item
        """

        let attributed = NativeMarkdownCodec.importMarkdown(markdown)
        let ns = attributed.string as NSString

        var paragraphSpacingChecks = 0
        var listSpacingChecks = 0

        var idx = 0
        while idx < ns.length {
            let paraRange = ns.paragraphRange(for: NSRange(location: idx, length: 0))
            guard paraRange.length > 0 else { break }

            let kindRaw = attributed.attribute(.kernBlockKind, at: paraRange.location, effectiveRange: nil) as? Int
            let kind = KernBlockKind(rawValue: kindRaw ?? KernBlockKind.paragraph.rawValue) ?? .paragraph

            guard let style = attributed.attribute(.paragraphStyle, at: paraRange.location, effectiveRange: nil) as? NSParagraphStyle else {
                idx = paraRange.location + paraRange.length
                continue
            }

            switch kind {
            case .paragraph:
                paragraphSpacingChecks += 1
                XCTAssertEqual(style.paragraphSpacingBefore, 2, accuracy: 0.01)
                XCTAssertEqual(style.paragraphSpacing, 2, accuracy: 0.01)
            case .bullet, .task, .ordered:
                listSpacingChecks += 1
                XCTAssertEqual(style.paragraphSpacingBefore, 2, accuracy: 0.01)
                XCTAssertEqual(style.paragraphSpacing, 2, accuracy: 0.01)
            default:
                break
            }

            idx = paraRange.location + paraRange.length
        }

        XCTAssertGreaterThan(paragraphSpacingChecks, 0)
        XCTAssertGreaterThan(listSpacingChecks, 0)
    }
}
