import XCTest
import WebKit
@testable import Kern

/// Mock delegate to capture NativeBridge callbacks
@MainActor
final class MockNativeBridgeDelegate: NativeBridgeDelegate {
    var editorReadyCalled = false
    var lastMarkdown: String?
    var lastScrollPosition: Double?
    var lastErrorMessage: String?
    var lastErrorStack: String?
    var lastOpenedURL: String?

    func editorReady() {
        editorReadyCalled = true
    }

    func contentChanged(markdown: String) {
        lastMarkdown = markdown
    }

    func scrollChanged(position: Double) {
        lastScrollPosition = position
    }

    func editorError(message: String, stack: String) {
        lastErrorMessage = message
        lastErrorStack = stack
    }

    func openURL(url urlString: String) {
        lastOpenedURL = urlString
    }
}

/// Mock WKScriptMessage for testing
/// We can't directly instantiate WKScriptMessage, so we test the delegate protocol instead.
@MainActor
final class NativeBridgeMessageParsingTests: XCTestCase {

    var delegate: MockNativeBridgeDelegate!

    override func setUp() {
        super.setUp()
        delegate = MockNativeBridgeDelegate()
    }

    // MARK: - Delegate Protocol Tests

    func testEditorReadyCallback() {
        delegate.editorReady()
        XCTAssertTrue(delegate.editorReadyCalled)
    }

    func testContentChangedCallback() {
        let markdown = "# Hello\n\nWorld"
        delegate.contentChanged(markdown: markdown)
        XCTAssertEqual(delegate.lastMarkdown, markdown)
    }

    func testScrollChangedCallback() {
        delegate.scrollChanged(position: 142.5)
        XCTAssertEqual(delegate.lastScrollPosition, 142.5)
    }

    func testErrorCallback() {
        delegate.editorError(message: "Test error", stack: "at line 1")
        XCTAssertEqual(delegate.lastErrorMessage, "Test error")
        XCTAssertEqual(delegate.lastErrorStack, "at line 1")
    }

    func testErrorCallbackEmptyStack() {
        delegate.editorError(message: "Error", stack: "")
        XCTAssertEqual(delegate.lastErrorMessage, "Error")
        XCTAssertEqual(delegate.lastErrorStack, "")
    }

    // MARK: - Message Body Parsing Tests

    /// Simulate parsing message bodies as NativeBridge would
    func testParseEditorReadyMessage() {
        let body: [String: Any] = ["type": "editorReady"]
        processMessage(body)
        XCTAssertTrue(delegate.editorReadyCalled)
    }

    func testParseContentChangedMessage() {
        let body: [String: Any] = [
            "type": "contentChanged",
            "markdown": "# Updated Content"
        ]
        processMessage(body)
        XCTAssertEqual(delegate.lastMarkdown, "# Updated Content")
    }

    func testParseScrollChangedMessage() {
        let body: [String: Any] = [
            "type": "scrollChanged",
            "position": 350.75
        ]
        processMessage(body)
        XCTAssertEqual(delegate.lastScrollPosition, 350.75)
    }

    func testParseErrorMessage() {
        let body: [String: Any] = [
            "type": "error",
            "message": "ReferenceError: x is not defined",
            "stack": "at eval:1:1"
        ]
        processMessage(body)
        XCTAssertEqual(delegate.lastErrorMessage, "ReferenceError: x is not defined")
        XCTAssertEqual(delegate.lastErrorStack, "at eval:1:1")
    }

    func testParseErrorMessageMissingFields() {
        let body: [String: Any] = ["type": "error"]
        processMessage(body)
        XCTAssertEqual(delegate.lastErrorMessage, "Unknown error")
        XCTAssertEqual(delegate.lastErrorStack, "")
    }

    func testParseUnknownMessageType() {
        let body: [String: Any] = ["type": "unknownEvent"]
        processMessage(body)
        // Should not crash, nothing should be set
        XCTAssertFalse(delegate.editorReadyCalled)
        XCTAssertNil(delegate.lastMarkdown)
        XCTAssertNil(delegate.lastScrollPosition)
    }

    func testParseInvalidMessageBody() {
        // Non-dictionary body — NativeBridge should silently ignore
        let body = "not a dictionary"
        processInvalidMessage(body)
        XCTAssertFalse(delegate.editorReadyCalled)
    }

    func testParseMissingTypeField() {
        let body: [String: Any] = ["markdown": "no type field"]
        processMessage(body)
        XCTAssertFalse(delegate.editorReadyCalled)
        XCTAssertNil(delegate.lastMarkdown)
    }

    func testParseContentChangedMissingMarkdown() {
        let body: [String: Any] = ["type": "contentChanged"]
        processMessage(body)
        // Should not call contentChanged without markdown field
        XCTAssertNil(delegate.lastMarkdown)
    }

    func testParseScrollChangedMissingPosition() {
        let body: [String: Any] = ["type": "scrollChanged"]
        processMessage(body)
        XCTAssertNil(delegate.lastScrollPosition)
    }

    // MARK: - Helpers

    /// Simulates NativeBridge message parsing logic
    private func processMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }

        switch type {
        case "editorReady":
            delegate.editorReady()
        case "contentChanged":
            if let markdown = body["markdown"] as? String {
                delegate.contentChanged(markdown: markdown)
            }
        case "scrollChanged":
            if let position = body["position"] as? Double {
                delegate.scrollChanged(position: position)
            }
        case "error":
            let errorMessage = body["message"] as? String ?? "Unknown error"
            let stack = body["stack"] as? String ?? ""
            delegate.editorError(message: errorMessage, stack: stack)
        default:
            break
        }
    }

    private func processInvalidMessage(_ body: Any) {
        guard let dict = body as? [String: Any],
              let _ = dict["type"] as? String
        else { return }
        // Would not proceed
    }
}
