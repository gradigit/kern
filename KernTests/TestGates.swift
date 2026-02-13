import Foundation
import XCTest

enum TestGates {
    static var exhaustive: Bool {
        ProcessInfo.processInfo.environment["KERN_ENABLE_EXHAUSTIVE_TESTS"] == "1"
    }

    static var snapshots: Bool {
        ProcessInfo.processInfo.environment["KERN_ENABLE_SNAPSHOT_TESTS"] == "1"
    }

    static var recordSnapshots: Bool {
        ProcessInfo.processInfo.environment["KERN_RECORD_SNAPSHOTS"] == "1"
    }

    static func skipUnlessExhaustive(_ message: String = "Set KERN_ENABLE_EXHAUSTIVE_TESTS=1 to run exhaustive tests") throws {
        try XCTSkipUnless(exhaustive, message)
    }

    static func skipUnlessSnapshots(_ message: String = "Set KERN_ENABLE_SNAPSHOT_TESTS=1 to run snapshot tests") throws {
        try XCTSkipUnless(snapshots, message)
    }
}

