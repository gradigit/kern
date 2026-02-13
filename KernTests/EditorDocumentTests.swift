import XCTest
@testable import Kern

final class EditorDocumentTests: XCTestCase {

    // MARK: - Read

    func testReadUTF8Content() throws {
        let doc = EditorDocument()
        let content = "# Hello World\n\nSome **bold** text."
        let data = content.data(using: .utf8)!

        try doc.read(from: data, ofType: "net.daringfireball.markdown")

        XCTAssertEqual(doc.stringValue, content)
    }

    func testReadEmptyContent() throws {
        let doc = EditorDocument()
        let data = Data()

        // Empty string is valid UTF-8
        try doc.read(from: data, ofType: "net.daringfireball.markdown")
        XCTAssertEqual(doc.stringValue, "")
    }

    func testReadUnicodeContent() throws {
        let doc = EditorDocument()
        let content = "한국어 테스트\n日本語テスト\n中文测试\nEmoji: 🎉🚀"
        let data = content.data(using: .utf8)!

        try doc.read(from: data, ofType: "net.daringfireball.markdown")

        XCTAssertEqual(doc.stringValue, content)
    }

    func testReadInvalidUTF8Throws() {
        let doc = EditorDocument()
        // Create invalid UTF-8 bytes
        let data = Data([0xFF, 0xFE, 0x80, 0x81])

        XCTAssertThrowsError(try doc.read(from: data, ofType: "net.daringfireball.markdown"))
    }

    // MARK: - Write

    func testDataOfTypeReturnsUTF8() throws {
        let doc = EditorDocument()
        let content = "# Test Document\n\nWith content."
        doc.stringValue = content

        let data = try doc.data(ofType: "net.daringfireball.markdown")

        let decoded = String(data: data, encoding: .utf8)
        XCTAssertEqual(decoded, content)
    }

    func testDataOfTypeWithUnicode() throws {
        let doc = EditorDocument()
        doc.stringValue = "가나다라마바사\n$$\\frac{1}{2}$$"

        let data = try doc.data(ofType: "net.daringfireball.markdown")
        let decoded = String(data: data, encoding: .utf8)

        XCTAssertEqual(decoded, doc.stringValue)
    }

    func testDataOfTypeEmptyContent() throws {
        let doc = EditorDocument()
        doc.stringValue = ""

        let data = try doc.data(ofType: "net.daringfireball.markdown")

        XCTAssertEqual(data.count, 0)
    }

    // MARK: - Round-trip

    func testReadWriteRoundTrip() throws {
        let original = """
        # Heading

        Paragraph with **bold** and *italic*.

        ```swift
        let x = 42
        ```

        - [ ] Task 1
        - [x] Task 2
        """

        let doc = EditorDocument()
        let inputData = original.data(using: .utf8)!

        try doc.read(from: inputData, ofType: "net.daringfireball.markdown")
        let outputData = try doc.data(ofType: "net.daringfireball.markdown")

        XCTAssertEqual(inputData, outputData)
    }

    func testLargeDocumentRoundTrip() throws {
        // Simulate a large document (50KB+)
        var content = "# Large Document\n\n"
        for i in 1...500 {
            content += "Paragraph \(i): Lorem ipsum dolor sit amet, consectetur adipiscing elit.\n\n"
        }

        let doc = EditorDocument()
        let data = content.data(using: .utf8)!
        try doc.read(from: data, ofType: "net.daringfireball.markdown")

        XCTAssertEqual(doc.stringValue, content)

        let outputData = try doc.data(ofType: "net.daringfireball.markdown")
        XCTAssertEqual(data, outputData)
    }

    // MARK: - Class Properties

    func testAutosavesInPlace() {
        XCTAssertTrue(EditorDocument.autosavesInPlace)
    }

    func testCanConcurrentlyRead() {
        XCTAssertTrue(EditorDocument.canConcurrentlyReadDocuments(ofType: "net.daringfireball.markdown"))
    }

    // MARK: - Mod Date Tracking

    func testLastKnownFileModDateInitiallyNil() {
        let doc = EditorDocument()
        XCTAssertNil(doc.lastKnownFileModDate)
    }
}
