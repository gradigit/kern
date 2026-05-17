import AppKit

/// Shared geometry constants for code-block backgrounds + chrome placement.
/// Keep this in one place so hit-testing, drawing, and overlay controls stay aligned.
enum CodeBlockChromeGeometry {
    // Background padding around the glyph bounding rect (matches the visual design of the block).
    static let backgroundInsetX: CGFloat = 10
    static let backgroundInsetBottom: CGFloat = 6
    static let chromeOverlayInsetX: CGFloat = 10
    static let chromeOverlayInsetY: CGFloat = 4
    static let estimatedChromeHeight: CGFloat = 22
    static let chromeBandBottomGap: CGFloat = 0
    // Notion-style code blocks reserve a persistent header lane above the first code line so
    // the language + copy chrome never overlaps content.
    // Keep a stable header lane, but size it to the actual chrome so short code blocks
    // do not grow an oversized empty cap above the first line.
    static let backgroundInsetTop: CGFloat = chromeOverlayInsetY + estimatedChromeHeight + chromeBandBottomGap
    static let blockExternalVerticalGap: CGFloat = 4

    static let cornerRadius: CGFloat = 8

    static let paragraphSpacingBefore: CGFloat = backgroundInsetTop + blockExternalVerticalGap
    static let paragraphSpacingAfter: CGFloat = backgroundInsetBottom + blockExternalVerticalGap

    static func backgroundRect(
        forGlyphBoundingRect glyphRect: NSRect,
        lineFragmentRect: NSRect? = nil,
        isFlipped: Bool
    ) -> NSRect {
        var rect = glyphRect
        rect.origin.x -= backgroundInsetX
        rect.size.width += backgroundInsetX * 2
        if isFlipped {
            rect.origin.y -= backgroundInsetTop
        } else {
            rect.origin.y -= backgroundInsetBottom
        }
        rect.size.height += backgroundInsetTop + backgroundInsetBottom
        if let lineFragmentRect {
            // Stretch the block background to the full available line width (Notion-like).
            // This avoids "shrink-to-content" blocks that clip chrome (language + copy).
            rect.origin.x = lineFragmentRect.minX - backgroundInsetX
            rect.size.width = lineFragmentRect.width + backgroundInsetX * 2
        }
        return rect
    }
}
