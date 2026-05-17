import AppKit
import XCTest
@testable import KernTextKit

final class CodeBlockChromeGeometryTests: XCTestCase {
    func testBackgroundRectKeepsVisibleBottomInset() {
        let glyphRect = NSRect(x: 40, y: 120, width: 420, height: 24)
        let lineRect = NSRect(x: 40, y: 120, width: 700, height: 24)
        for isFlipped in [true, false] {
            let bg = CodeBlockChromeGeometry.backgroundRect(
                forGlyphBoundingRect: glyphRect,
                lineFragmentRect: lineRect,
                isFlipped: isFlipped
            )

            let lowerInset = visualBottomInset(for: bg, glyphRect: glyphRect, isFlipped: isFlipped)
            XCTAssertGreaterThanOrEqual(
                lowerInset,
                6,
                "Code block should keep visible bottom breathing room in \(isFlipped ? "flipped" : "non-flipped") coordinates"
            )
        }
    }

    func testBackgroundRectReservesPersistentHeaderBandAboveFirstCodeLine() {
        let glyphRect = NSRect(x: 40, y: 120, width: 420, height: 24)
        let lineRect = NSRect(x: 40, y: 120, width: 700, height: 24)
        for isFlipped in [true, false] {
            let bg = CodeBlockChromeGeometry.backgroundRect(
                forGlyphBoundingRect: glyphRect,
                lineFragmentRect: lineRect,
                isFlipped: isFlipped
            )

            let upperInset = visualTopInset(for: bg, glyphRect: glyphRect, isFlipped: isFlipped)
            let lowerInset = visualBottomInset(for: bg, glyphRect: glyphRect, isFlipped: isFlipped)

            XCTAssertEqual(upperInset, CodeBlockChromeGeometry.backgroundInsetTop, accuracy: 0.01)
            XCTAssertEqual(lowerInset, CodeBlockChromeGeometry.backgroundInsetBottom, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(upperInset - lowerInset, 18)
            XCTAssertLessThanOrEqual(
                upperInset - lowerInset,
                20,
                "Code blocks should reserve only the compact chrome lane above the first code line in \(isFlipped ? "flipped" : "non-flipped") coordinates"
            )
        }
    }

    private func visualTopInset(for bg: NSRect, glyphRect: NSRect, isFlipped: Bool) -> CGFloat {
        if isFlipped {
            return glyphRect.minY - bg.minY
        }
        return bg.maxY - glyphRect.maxY
    }

    private func visualBottomInset(for bg: NSRect, glyphRect: NSRect, isFlipped: Bool) -> CGFloat {
        if isFlipped {
            return bg.maxY - glyphRect.maxY
        }
        return glyphRect.minY - bg.minY
    }
}
