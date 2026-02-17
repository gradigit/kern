import AppKit

/// Lightweight placeholder attachment for semantic blocks/runs that should not display raw Markdown.
@MainActor
final class MarkdownPlaceholderAttachment: NSTextAttachment {
    private let text: String

    init(text: String) {
        self.text = text
        super.init(data: nil, ofType: nil)
        self.attachmentCell = MarkdownPlaceholderAttachmentCell(text: text)
    }

    required init?(coder: NSCoder) {
        self.text = "placeholder"
        super.init(coder: coder)
        self.attachmentCell = MarkdownPlaceholderAttachmentCell(text: text)
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let width = ceil(textSize.width + 14)
        return NSRect(x: 0, y: -2, width: max(32, width), height: 18)
    }
}

@MainActor
private final class MarkdownPlaceholderAttachmentCell: NSTextAttachmentCell {
    private let text: String

    init(text: String) {
        self.text = text
        super.init(textCell: "")
    }

    required init(coder: NSCoder) {
        self.text = "placeholder"
        super.init(coder: coder)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let bg = NSColor(white: 0, alpha: 0.08)
        let fg = NSColor.secondaryLabelColor

        let path = NSBezierPath(roundedRect: cellFrame, xRadius: 6, yRadius: 6)
        bg.setFill()
        path.fill()

        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fg,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let textRect = NSRect(
            x: cellFrame.midX - (textSize.width / 2),
            y: cellFrame.midY - (textSize.height / 2),
            width: textSize.width,
            height: textSize.height
        ).integral
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }
}
