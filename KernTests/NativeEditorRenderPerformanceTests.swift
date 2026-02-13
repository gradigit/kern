import AppKit
import Foundation
import XCTest
@testable import Kern

final class NativeEditorRenderPerformanceTests: XCTestCase {
    @MainActor
    func testRenderBenchmarkFilePerformance() throws {
        guard ProcessInfo.processInfo.environment["KERN_ENABLE_PERF_TESTS"] == "1" else {
            throw XCTSkip("Set KERN_ENABLE_PERF_TESTS=1 to run performance tests")
        }

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KernTests/
            .deletingLastPathComponent() // repo root

        let url = root.appendingPathComponent("test-fixtures/native-editor-benchmark.md")
        let md = try String(contentsOf: url, encoding: .utf8)

        // Measure end-to-end render in TextKit (import + view layout).
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let vc = NativeEditorViewController()
            _ = vc.view
            vc.stringValue = md
            vc.view.layoutSubtreeIfNeeded()
            vc.view.displayIfNeeded()
        }
    }
}

