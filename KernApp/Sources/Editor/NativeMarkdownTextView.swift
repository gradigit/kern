import AppKit

@MainActor
protocol NativeMarkdownTextViewDelegate: AnyObject {
    func nativeTextViewToggleCheckbox(at characterIndex: Int)
}

/// NSTextView subclass for the native editor prototype.
/// Handles hit-testing for checkboxes.
@MainActor
final class NativeMarkdownTextView: NSTextView {
    weak var nativeDelegate: NativeMarkdownTextViewDelegate?
    var suppressNextAutoNewlineContinuation = false

    private enum CheckboxHitTarget: String {
        /// Toggle only when clicking directly on the checkbox glyph (Notion/GitHub-like).
        case glyph
        /// Toggle when clicking anywhere in the marker prefix (Kern preference).
        case marker
    }

    private func checkboxHitTarget() -> CheckboxHitTarget {
        let raw = UserDefaults.standard.string(forKey: "nativeEditor.checkboxHitTarget") ?? "glyph"
        return CheckboxHitTarget(rawValue: raw) ?? .glyph
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCodeBlockBackgrounds(in: dirtyRect)
        super.draw(dirtyRect)
    }

    override func insertNewline(_ sender: Any?) {
        if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift) {
            suppressNextAutoNewlineContinuation = true
            // Notion/GitHub-style: Shift+Enter inserts a soft line break (not a new list item).
            super.insertLineBreak(sender)
            return
        }
        super.insertNewline(sender)
    }

    override func insertLineBreak(_ sender: Any?) {
        suppressNextAutoNewlineContinuation = true
        super.insertLineBreak(sender)
    }

    override func mouseDown(with event: NSEvent) {
        let pointInWindow = event.locationInWindow
        let point = convert(pointInWindow, from: nil)

        if let idx = characterIndex(at: point), let storage = textStorage {
            let attrs = storage.attributes(at: idx, effectiveRange: nil)
            let target = checkboxHitTarget()

            // Always allow direct checkbox clicks to toggle.
            if (attrs[.kernCheckbox] as? Bool) == true {
                nativeDelegate?.nativeTextViewToggleCheckbox(at: idx)
                return
            }

            // Optional: marker-prefix click toggles (bullet dot / ordered marker / space prefix).
            if target == .marker, (attrs[.kernMarker] as? Bool) == true {
                let ns = storage.string as NSString
                let paraRange = ns.paragraphRange(for: NSRange(location: idx, length: 0))
                if paraRange.location < storage.length {
                    let searchLen = min(paraRange.length, 64)
                    let searchRange = NSRange(location: paraRange.location, length: searchLen)
                    var checkboxIndex: Int?
                    storage.enumerateAttribute(.kernCheckbox, in: searchRange, options: []) { value, range, stop in
                        guard (value as? Bool) == true else { return }
                        checkboxIndex = range.location
                        stop.pointee = true
                    }
                    if let checkboxIndex {
                        nativeDelegate?.nativeTextViewToggleCheckbox(at: checkboxIndex)
                        return
                    }
                }
            }
        }

        super.mouseDown(with: event)
    }

    private func drawCodeBlockBackgrounds(in dirtyRect: NSRect) {
        guard let storage = textStorage, let lm = layoutManager, let tc = textContainer else { return }
        let ns = storage.string as NSString

        let bg = NSColor(white: 0, alpha: 0.08)
        let stroke = NSColor(white: 0, alpha: 0.10)

        // Only scan paragraphs that intersect the dirty rect (TextKit coordinates).
        let containerRect = dirtyRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let dirtyGlyphs = lm.glyphRange(forBoundingRect: containerRect, in: tc)
        let dirtyChars = lm.characterRange(forGlyphRange: dirtyGlyphs, actualGlyphRange: nil)

        let startLimit = max(0, dirtyChars.location)
        let endLimit = min(ns.length, dirtyChars.location + dirtyChars.length)

        var idx = startLimit
        while idx < endLimit {
            let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
            guard para.length > 0 else { break }

            let kindRaw = storage.attribute(.kernBlockKind, at: para.location, effectiveRange: nil) as? Int
            let kind = KernBlockKind(rawValue: kindRaw ?? KernBlockKind.paragraph.rawValue) ?? .paragraph

            if kind == .codeBlock {
                // Group consecutive codeBlock paragraphs (represents one fenced block).
                var start = para.location
                var end = para.location + para.length
                var scan = end
                while scan < ns.length {
                    let next = ns.paragraphRange(for: NSRange(location: scan, length: 0))
                    if next.length == 0 { break }
                    let kRaw = storage.attribute(.kernBlockKind, at: next.location, effectiveRange: nil) as? Int
                    let k = KernBlockKind(rawValue: kRaw ?? KernBlockKind.paragraph.rawValue) ?? .paragraph
                    if k != .codeBlock { break }
                    end = next.location + next.length
                    scan = end
                }

                let charRange = NSRange(location: start, length: max(0, end - start))
                let glyphRange = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
                var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
                rect.origin.x += textContainerOrigin.x
                rect.origin.y += textContainerOrigin.y

                // Expand for padding and rounded corners.
                rect = rect.insetBy(dx: -10, dy: -6)

                if rect.intersects(dirtyRect) {
                    let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
                    bg.setFill()
                    path.fill()

                    stroke.setStroke()
                    path.lineWidth = 1
                    path.stroke()
                }

                idx = end
                continue
            }

            idx = para.location + para.length
        }
    }

    private func characterIndex(at point: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        // TextKit uses textContainerOrigin offsets for padding/insets.
        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyphIndex = lm.glyphIndex(for: containerPoint, in: tc)
        let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
        guard charIndex >= 0, let storage = textStorage, charIndex < storage.length else { return nil }
        return charIndex
    }
}
