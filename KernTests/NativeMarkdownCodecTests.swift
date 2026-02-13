import XCTest
@testable import KernTextKit

final class NativeMarkdownCodecTests: XCTestCase {
    @MainActor
    func testRoundTripBasic() {
        let md = """
        # Title

        - [x] done
        - [ ] todo

        Paragraph with **bold** and *italic* and `code`.

        ```js
        console.log("hi")
        ```
        """

        let attr = NativeMarkdownCodec.importMarkdown(md)
        let out = NativeMarkdownCodec.exportMarkdown(attr)

        XCTAssertTrue(out.contains("# Title"))
        XCTAssertTrue(out.contains("- [x] done"))
        XCTAssertTrue(out.contains("- [ ] todo"))
        XCTAssertTrue(out.contains("**bold**"))
        XCTAssertTrue(out.contains("*italic*"))
        XCTAssertTrue(out.contains("`code`"))
        XCTAssertTrue(out.contains("```js"))
        XCTAssertTrue(out.contains("console.log(\"hi\")"))
        XCTAssertTrue(out.contains("```"))
    }

    @MainActor
    func testTodoShortcutExportsAsGfmTaskList() {
        let md = """
        [] first
        [x] second
        """

        let attr = NativeMarkdownCodec.importMarkdown(md)
        let out = NativeMarkdownCodec.exportMarkdown(attr)

        XCTAssertTrue(out.contains("- [ ] first"))
        XCTAssertTrue(out.contains("- [x] second"))
    }

    @MainActor
    func testOrderedListRoundTrip() {
        let md = """
        1. one
        2. two

        10. ten
        """

        let attr = NativeMarkdownCodec.importMarkdown(md)
        let out = NativeMarkdownCodec.exportMarkdown(attr)

        XCTAssertTrue(out.contains("1. one"))
        XCTAssertTrue(out.contains("2. two"))
        XCTAssertTrue(out.contains("10. ten"))
    }

    @MainActor
    func testTablesRoundTrip_Gfm() {
        let md = """
        | Left | Center | Right |
        | :--- | :---: | ---: |
        | a | b | c |
        | escaped \\| pipe | `code|span` | **bold** |
        """

        let attr = NativeMarkdownCodec.importMarkdown(md)
        let out = NativeMarkdownCodec.exportMarkdown(attr)

        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), md)
    }
}
