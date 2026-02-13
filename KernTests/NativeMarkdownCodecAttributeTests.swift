import AppKit
import XCTest
@testable import Kern

final class NativeMarkdownCodecAttributeTests: XCTestCase {
    @MainActor
    func testCheckboxAttributesAndCheckedStyle() {
        let md = "[x] done"
        let attr = NativeMarkdownCodec.importMarkdown(md)

        // Find the checkbox glyph.
        let ns = attr.string as NSString
        var checkboxIndex: Int?
        for i in 0..<ns.length {
            if (attr.attribute(.kernCheckbox, at: i, effectiveRange: nil) as? Bool) == true {
                checkboxIndex = i
                break
            }
        }
        guard let checkboxIndex else {
            XCTFail("No checkbox glyph found")
            return
        }

        XCTAssertEqual(ns.substring(with: NSRange(location: checkboxIndex, length: 1)), "☑")

        let checked = (attr.attribute(.kernCheckboxChecked, at: checkboxIndex, effectiveRange: nil) as? Bool) ?? false
        XCTAssertTrue(checked)

        // Checkbox should be slightly larger for visibility.
        let font = attr.attribute(.font, at: checkboxIndex, effectiveRange: nil) as? NSFont
        XCTAssertEqual(Double(font?.pointSize ?? 0), 20, accuracy: 0.01)

        let baseline = attr.attribute(.baselineOffset, at: checkboxIndex, effectiveRange: nil) as? NSNumber
        XCTAssertEqual(baseline?.doubleValue ?? 0, -1, accuracy: 0.01)

        // Body should be struck through when checked.
        var sawStrike = false
        attr.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: attr.length), options: []) { value, range, _ in
            guard let value else { return }
            if range.length > 0, (value as? Int) == NSUnderlineStyle.single.rawValue {
                sawStrike = true
            }
        }
        XCTAssertTrue(sawStrike)
    }
}
