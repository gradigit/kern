import XCTest
import AppKit
@testable import Kern

@MainActor
final class AppearanceManagerTests: XCTestCase {

    // MARK: - Theme Detection

    func testCurrentThemeReturnsString() {
        let theme = AppearanceManager.shared.currentTheme()
        XCTAssertTrue(theme == "dark" || theme == "light",
                      "Theme should be 'dark' or 'light', got '\(theme)'")
    }

    func testCurrentThemeMatchesSystemAppearance() {
        let manager = AppearanceManager.shared
        let theme = manager.currentTheme()

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let expected = isDark ? "dark" : "light"

        XCTAssertEqual(theme, expected)
    }

    // MARK: - Singleton

    func testSharedIsSingleton() {
        let a = AppearanceManager.shared
        let b = AppearanceManager.shared
        XCTAssertTrue(a === b)
    }

    // MARK: - Broadcast (no-crash test)

    func testBroadcastThemeDoesNotCrashWithNoDocuments() {
        // With no open documents, broadcastTheme should just be a no-op
        AppearanceManager.shared.broadcastTheme()
    }
}
