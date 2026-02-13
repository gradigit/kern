import XCTest
import WebKit
@testable import Kern

@MainActor
final class EditorReusePoolTests: XCTestCase {

    // MARK: - WebView Creation

    func testCreateWebViewReturnsValidInstance() {
        let pool = EditorReusePool.shared
        let webView = pool.createWebView()

        XCTAssertNotNil(webView)
        XCTAssertTrue(webView.isInspectable)
    }

    func testCreateWebViewHasJavaScriptEnabled() {
        let pool = EditorReusePool.shared
        let webView = pool.createWebView()

        XCTAssertTrue(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    }

    func testCreateWebViewHasUserContentController() {
        let pool = EditorReusePool.shared
        let webView = pool.createWebView()

        XCTAssertNotNil(webView.configuration.userContentController)
    }

    // MARK: - Dequeue/Enqueue

    func testDequeueReturnsWebView() {
        let pool = EditorReusePool.shared
        let webView = pool.dequeue()

        XCTAssertNotNil(webView)
    }

    func testEnqueueAndDequeueRecyclesWebView() {
        let pool = EditorReusePool.shared

        // Create and enqueue a webView
        let webView = pool.createWebView()
        pool.enqueue(webView)

        // Pool may already contain other WKWebViews (warm-up or other tests), so we
        // only assert that the enqueued instance is eventually returned.
        var collected: [WKWebView] = []
        var found = false
        for _ in 0..<12 {
            let dequeued = pool.dequeue()
            collected.append(dequeued)
            if dequeued === webView {
                found = true
                break
            }
        }
        // Return everything we dequeued so other tests don't depend on ordering/state.
        for w in collected {
            pool.enqueue(w)
        }
        XCTAssertTrue(found)
    }

    func testEnqueueClearsMessageHandlers() {
        let pool = EditorReusePool.shared
        let webView = pool.createWebView()

        // Add a handler
        let handler = MockMessageHandler()
        webView.configuration.userContentController.add(handler, name: "test")

        // Enqueue should clear handlers
        pool.enqueue(webView)

        // Note: We can't directly verify handlers are removed without private API,
        // but enqueue calls removeAllScriptMessageHandlers which is tested by not crashing
        // when we add a new handler with the same name
        webView.configuration.userContentController.add(handler, name: "test")
    }

    func testEnqueueStopsLoading() {
        let pool = EditorReusePool.shared
        let webView = pool.createWebView()

        // Enqueue should call stopLoading — verified by no crash
        pool.enqueue(webView)
    }

    func testEnqueueClearsNavigationDelegate() {
        let pool = EditorReusePool.shared
        let webView = pool.createWebView()

        // Set a navigation delegate
        let mockDelegate = MockNavigationDelegate()
        webView.navigationDelegate = mockDelegate

        pool.enqueue(webView)

        XCTAssertNil(webView.navigationDelegate)
    }
}

// MARK: - Mocks

@MainActor
private final class MockMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {}
}

@MainActor
private final class MockNavigationDelegate: NSObject, WKNavigationDelegate {}
