import XCTest
@testable import KernTextKit

final class NativeMarkdownCodecProfilingTests: XCTestCase {
    func testImportMarkdownProfiledCapturesPhaseMetadata() {
        let markdown = """
        # Heading

        Paragraph with **bold** and [link](https://example.com).

        | A | B |
        | --- | --- |
        | 1 | 2 |

        ```swift
        print("hello")
        ```
        """

        var options = NativeMarkdownCodec.Options()
        options.syntaxHighlightingEnabled = false

        let profiled = NativeMarkdownCodec.importMarkdownProfiled(markdown, options: options)
        let normalized = NativeMarkdownCodec.normalizeLineEndings(markdown)

        XCTAssertGreaterThan(profiled.attributed.length, 0)
        XCTAssertEqual(profiled.profile.markdownUTF16Count, normalized.utf16.count)
        XCTAssertGreaterThan(profiled.profile.lineCount, 0)
        XCTAssertGreaterThan(profiled.profile.phaseCounts[NativeMarkdownCodec.ImportProfilePhase.lineSplit.rawValue] ?? 0, 0)
        XCTAssertGreaterThan(profiled.profile.phaseCounts[NativeMarkdownCodec.ImportProfilePhase.referenceDefinitionScan.rawValue] ?? 0, 0)
        XCTAssertGreaterThan(profiled.profile.phaseCounts[NativeMarkdownCodec.ImportProfilePhase.inlineParse.rawValue] ?? 0, 0)
        XCTAssertGreaterThan(profiled.profile.phaseCounts[NativeMarkdownCodec.ImportProfilePhase.makeCodeBlockAttributed.rawValue] ?? 0, 0)
        XCTAssertGreaterThan(profiled.profile.phaseCounts[NativeMarkdownCodec.ImportProfilePhase.makeGfmTableAttributed.rawValue] ?? 0, 0)
        XCTAssertGreaterThan(profiled.profile.phaseDurationsMs[NativeMarkdownCodec.ImportProfilePhase.importLoop.rawValue] ?? -1, 0)
        XCTAssertGreaterThan(profiled.profile.totalInlineUTF16, 0)
        XCTAssertGreaterThan(profiled.profile.maxInlineUTF16, 0)
    }

    func testImportMarkdownProfiledCountsOnlyOutermostInlineUTF16() {
        let markdown = "**bold [link](https://example.com) text**"

        let profiled = NativeMarkdownCodec.importMarkdownProfiled(markdown)

        XCTAssertEqual(
            profiled.profile.totalInlineUTF16,
            markdown.utf16.count,
            "Nested inline recursion should not inflate the UTF-16 workload metric"
        )
        XCTAssertEqual(
            profiled.profile.phaseCounts[NativeMarkdownCodec.ImportProfilePhase.inlineParse.rawValue],
            1,
            "A single paragraph should report one outermost inline parse phase"
        )
    }

    func testImportMarkdownProfiledDoesNotCountSpeculativeTableLookaheadAsTableParse() {
        let markdown = """
        Intro paragraph
        | A | B |
        | --- | --- |
        | 1 | 2 |
        """

        let profiled = NativeMarkdownCodec.importMarkdownProfiled(markdown)

        XCTAssertEqual(
            profiled.profile.phaseCounts[NativeMarkdownCodec.ImportProfilePhase.parseGfmTable.rawValue],
            1,
            "Only the actual table parse should be counted, not speculative lookahead"
        )
        XCTAssertEqual(
            profiled.profile.phaseCounts[NativeMarkdownCodec.ImportProfilePhase.gfmTableBlock.rawValue],
            1
        )
    }
}
