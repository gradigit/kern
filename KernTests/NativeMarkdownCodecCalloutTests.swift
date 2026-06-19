import XCTest
@testable import KernTextKit

final class NativeMarkdownCodecCalloutTests: XCTestCase {
    func testBlockquoteCalloutHidesMarkerAndRoundTrips() {
        let markdown = "> [!NOTE] API key allowlist status\n> Status: `5.60.133.248/29` has been added."
        let attr = NativeMarkdownCodec.importMarkdown(markdown)

        XCTAssertFalse(attr.string.contains("[!NOTE]"), "WYSIWYG import should hide callout marker syntax")
        XCTAssertTrue(attr.string.contains("API key allowlist status"))

        guard attr.length > 0 else {
            XCTFail("Expected attributed callout content")
            return
        }
        XCTAssertEqual(attr.attribute(.kernCalloutKind, at: 0, effectiveRange: nil) as? String, KernCalloutKind.note.rawValue)
        XCTAssertEqual(attr.attribute(.kernQuoteDepth, at: 0, effectiveRange: nil) as? Int, 1)

        let exported = NativeMarkdownCodec.exportMarkdown(attr)
        XCTAssertEqual(exported, markdown)
    }

    func testStrictConformanceKeepsCalloutSyntaxLiteral() {
        var options = NativeMarkdownCodec.Options()
        options.strictConformanceRoundTripMode = true
        options.exportDialect = .gfm
        options.gfmExtensionExportStrategy = .portable

        let markdown = "> [!NOTE] Literal marker\n> Body"
        let attr = NativeMarkdownCodec.importMarkdown(markdown, options: options)

        XCTAssertTrue(attr.string.contains("[!NOTE] Literal marker"))
        XCTAssertNil(attr.attribute(.kernCalloutKind, at: 0, effectiveRange: nil))
        XCTAssertEqual(NativeMarkdownCodec.exportMarkdown(attr, options: options), markdown)
    }

    func testPortableAndLintExportDropCalloutMarkerButKeepBlockquoteText() {
        let markdown = "> [!NOTE] API key allowlist status\n> Status: `5.60.133.248/29` has been added."
        let attr = NativeMarkdownCodec.importMarkdown(markdown)
        let expected = "> API key allowlist status\n> Status: `5.60.133.248/29` has been added."

        var portable = NativeMarkdownCodec.Options()
        portable.exportDialect = .gfm
        portable.gfmExtensionExportStrategy = .portable
        XCTAssertEqual(NativeMarkdownCodec.exportMarkdown(attr, options: portable), expected)

        var lint = portable
        lint.gfmExtensionExportStrategy = .lint
        XCTAssertEqual(NativeMarkdownCodec.exportMarkdown(attr, options: lint), expected)
    }

    func testCalloutFoldSuffixRoundTripsWhenPreservingExtensions() {
        let markdown = "> [!NOTE]+ Collapsible\n> Body"
        let attr = NativeMarkdownCodec.importMarkdown(markdown)

        XCTAssertEqual(attr.attribute(.kernCalloutFoldSuffix, at: 0, effectiveRange: nil) as? String, "+")
        XCTAssertEqual(NativeMarkdownCodec.exportMarkdown(attr), markdown)
    }

    func testCalloutKindAliasesNormalizeForExport() {
        let markdown = "> [!danger] Stop\n> Do not continue."
        let attr = NativeMarkdownCodec.importMarkdown(markdown)

        XCTAssertEqual(attr.attribute(.kernCalloutKind, at: 0, effectiveRange: nil) as? String, KernCalloutKind.caution.rawValue)
        XCTAssertEqual(NativeMarkdownCodec.exportMarkdown(attr), "> [!CAUTION] Stop\n> Do not continue.")
    }
}
