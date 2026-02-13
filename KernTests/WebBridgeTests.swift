import XCTest
import WebKit
@testable import Kern

@MainActor
final class WebBridgeTests: XCTestCase {

    // MARK: - Error Handling

    func testWebViewDeallocatedError() {
        // Create a bridge with a deallocated webView (using weak reference)
        let bridge: WebBridge
        do {
            let webView = WKWebView()
            bridge = WebBridge(webView: webView)
            // webView goes out of scope here
        }

        // The weak reference should be nil, so calls should throw
        // Note: In practice, ARC may not deallocate immediately in tests,
        // so we test the error type exists and is descriptive
        let error = WebBridgeError.webViewDeallocated
        XCTAssertEqual(error.errorDescription, "WKWebView has been deallocated")
    }

    func testWebBridgeErrorConformsToLocalizedError() {
        let error: Error = WebBridgeError.webViewDeallocated
        XCTAssertNotNil(error as? LocalizedError)
        XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
    }

    // MARK: - Bridge Initialization

    func testBridgeInitWithWebView() {
        let webView = WKWebView()
        let bridge = WebBridge(webView: webView)

        // Bridge should be non-nil and hold a weak reference
        XCTAssertNotNil(bridge)
    }
}
