import XCTest
@testable import KernTextKit

final class NativeMarkdownCodecOptionsTests: XCTestCase {
    @MainActor
    func testTaskRenderingKernShowsBulletDotForBulletedTasks() {
        let md = "- [ ] todo"
        var opt = NativeMarkdownCodec.Options()
        opt.taskRendering = .kern

        let attr = NativeMarkdownCodec.importMarkdown(md, options: opt)
        XCTAssertTrue(attr.string.contains("• ☐ todo"))

        let out = NativeMarkdownCodec.exportMarkdown(attr, options: opt)
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "- [ ] todo")
    }

    @MainActor
    func testKernExportDialectPreservesStandaloneTaskSyntax() {
        let md = "[] todo"

        var opt = NativeMarkdownCodec.Options()
        opt.exportDialect = .kern

        let attr = NativeMarkdownCodec.importMarkdown(md, options: opt)
        let out = NativeMarkdownCodec.exportMarkdown(attr, options: opt)
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "[ ] todo")
    }

    @MainActor
    func testOrderedTasksDisabledDoesNotCreateCheckboxes() {
        let md = "1. [ ] one"
        let attr = NativeMarkdownCodec.importMarkdown(md) // defaults: orderedTasksEnabled=false

        XCTAssertFalse(containsCheckbox(attr))
    }

    @MainActor
    func testOrderedTasksEnabledParsesAsOrderedTask() {
        let md = """
        1. [ ] one
        2. [x] two
        """

        var opt = NativeMarkdownCodec.Options()
        opt.orderedTasksEnabled = true

        let attr = NativeMarkdownCodec.importMarkdown(md, options: opt)
        XCTAssertTrue(containsCheckbox(attr))

        // First paragraph should be marked as an ordered task.
        let kind = attr.attribute(.kernBlockKind, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(kind, KernBlockKind.ordered.rawValue)

        let isTask = (attr.attribute(.kernOrderedIsTask, at: 0, effectiveRange: nil) as? Bool) ?? false
        XCTAssertTrue(isTask)

        let out = NativeMarkdownCodec.exportMarkdown(attr, options: opt)
        XCTAssertTrue(out.contains("1. [ ] one"))
        XCTAssertTrue(out.contains("2. [x] two"))
    }

    @MainActor
    func testHeadingCheckboxesEnabledParsesAndExports() {
        let md = "## [ ] Heading"
        var opt = NativeMarkdownCodec.Options()
        opt.headingCheckboxesEnabled = true

        let attr = NativeMarkdownCodec.importMarkdown(md, options: opt)
        XCTAssertTrue(containsCheckbox(attr))

        let out = NativeMarkdownCodec.exportMarkdown(attr, options: opt)
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "## [ ] Heading")
    }

    @MainActor
    func testGfmPortableStrategyAvoidsKernExtensionSyntaxOnExport() {
        var opt = NativeMarkdownCodec.Options()
        opt.exportDialect = .gfm
        opt.gfmExtensionExportStrategy = .portable
        opt.orderedTasksEnabled = true
        opt.headingCheckboxesEnabled = true

        let md = """
        1. [ ] one
        2. [x] two

        ## [x] Heading
        """

        let attr = NativeMarkdownCodec.importMarkdown(md, options: opt)
        let out = NativeMarkdownCodec.exportMarkdown(attr, options: opt)

        XCTAssertTrue(out.contains("1. ☐ one"))
        XCTAssertTrue(out.contains("2. ☑ two"))
        XCTAssertTrue(out.contains("## ☑ Heading"))
    }

    @MainActor
    func testGfmLintStrategyRewritesHeadingCheckboxesAsTasks() {
        var opt = NativeMarkdownCodec.Options()
        opt.exportDialect = .gfm
        opt.gfmExtensionExportStrategy = .lint
        opt.headingCheckboxesEnabled = true

        let md = "## [x] Heading\n"
        let out = NativeMarkdownCodec.exportMarkdown(NativeMarkdownCodec.importMarkdown(md, options: opt), options: opt)
        XCTAssertTrue(out.contains("- [x] Heading"))
        XCTAssertFalse(out.contains("## [x] Heading"))
    }

    @MainActor
    func testOrderedListNumberingGfmDefaultNormalizesSequentially() {
        let md = """
        1. one
        5. five
        """

        var gfm = NativeMarkdownCodec.Options()
        gfm.orderedListNumbering = .gfmDefault
        let outGfm = NativeMarkdownCodec.exportMarkdown(NativeMarkdownCodec.importMarkdown(md, options: gfm), options: gfm)
        XCTAssertTrue(outGfm.contains("1. one"))
        XCTAssertTrue(outGfm.contains("2. five"))

        var preserve = NativeMarkdownCodec.Options()
        preserve.orderedListNumbering = .preserveTyped
        let outPreserve = NativeMarkdownCodec.exportMarkdown(NativeMarkdownCodec.importMarkdown(md, options: preserve), options: preserve)
        XCTAssertTrue(outPreserve.contains("5. five"))
    }

    private func containsCheckbox(_ attr: NSAttributedString) -> Bool {
        let full = NSRange(location: 0, length: attr.length)
        var found = false
        attr.enumerateAttribute(.kernCheckbox, in: full, options: []) { value, _, stop in
            if (value as? Bool) == true {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}
