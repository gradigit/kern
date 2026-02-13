import XCTest
import WebKit
@testable import Kern

@MainActor
final class EditorViewControllerTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let vc = EditorViewController()

        XCTAssertFalse(vc.hasFinishedLoading)
        XCTAssertFalse(vc.isVirtualized)
        XCTAssertEqual(vc.cachedScrollPosition, 0)
        XCTAssertEqual(vc.stringValue, "")
    }

    // MARK: - Content Changed

    func testContentChangedUpdatesStringValue() {
        let vc = EditorViewController()
        vc.contentChanged(markdown: "# Updated")

        XCTAssertEqual(vc.stringValue, "# Updated")
    }

    func testContentChangedCallsCallback() {
        let vc = EditorViewController()
        var received: String?
        vc.onContentChanged = { md in received = md }

        vc.contentChanged(markdown: "# Test")

        XCTAssertEqual(received, "# Test")
    }

    // MARK: - Scroll Changed

    func testScrollChangedUpdatesCachedPosition() {
        let vc = EditorViewController()
        vc.scrollChanged(position: 256.5)

        XCTAssertEqual(vc.cachedScrollPosition, 256.5)
    }

    func testScrollChangedMultipleUpdates() {
        let vc = EditorViewController()
        vc.scrollChanged(position: 100)
        vc.scrollChanged(position: 200)
        vc.scrollChanged(position: 300)

        XCTAssertEqual(vc.cachedScrollPosition, 300)
    }

    // MARK: - String Value

    func testStringValuePreservedForVirtualization() {
        let vc = EditorViewController()
        vc.stringValue = "# Important Content"
        vc.contentChanged(markdown: "# Updated Content")

        XCTAssertEqual(vc.stringValue, "# Updated Content")
    }

    // MARK: - Menu Validation

    func testMenuValidationWhenNotReady() {
        let vc = EditorViewController()
        // hasFinishedLoading is false, bridge is nil

        let menuItem = NSMenuItem(title: "Bold", action: #selector(EditorViewController.toggleBold(_:)), keyEquivalent: "b")
        let isValid = vc.validateMenuItem(menuItem)

        XCTAssertFalse(isValid, "Format items should be disabled when editor not ready")
    }

    func testMenuValidationForNonFormatItem() {
        let vc = EditorViewController()
        // Unknown action should return true
        let menuItem = NSMenuItem(title: "Something", action: #selector(NSObject.description), keyEquivalent: "")
        let isValid = vc.validateMenuItem(menuItem)

        XCTAssertTrue(isValid, "Non-format menu items should always be enabled")
    }
}
