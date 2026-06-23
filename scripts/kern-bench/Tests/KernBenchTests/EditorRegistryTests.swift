import XCTest
@testable import kern_bench

final class EditorRegistryTests: XCTestCase {
    func testKernLaunchDisablesStateRestoration() throws {
        let kern = try XCTUnwrap(findEditor(named: "Kern"))
        XCTAssertEqual(kern.cleanLaunchArgs, ["-ApplePersistenceIgnoreState", "YES"])
    }

    func testResolveKernAppURLPrefersExplicitOverride() {
        let resolved = resolveKernAppURL(
            environment: ["KERN_BENCH_KERN_APP": "~/Applications/Kern.app"],
            currentDirectoryPath: "/tmp/irrelevant",
            homeDirectoryPath: "/Users/tester",
            workspaceURLResolver: { _ in nil },
            fileExists: { path in
                path == "/Users/tester/Applications/Kern.app"
            }
        )

        XCTAssertEqual(resolved?.path, "/Users/tester/Applications/Kern.app")
    }

    func testResolveKernAppURLFallsBackToRepoDistWhenWorkspaceLookupFails() {
        let resolved = resolveKernAppURL(
            environment: [:],
            currentDirectoryPath: "/Users/tester/Projects/Kern-textkit/scripts/kern-bench",
            homeDirectoryPath: "/Users/tester",
            workspaceURLResolver: { _ in nil },
            fileExists: { path in
                path == "/Users/tester/Projects/Kern-textkit/dist/Kern.app"
            }
        )

        XCTAssertEqual(resolved?.path, "/Users/tester/Projects/Kern-textkit/dist/Kern.app")
    }

    func testResolveKernAppURLUsesWorkspaceWhenAvailable() {
        let workspaceURL = URL(fileURLWithPath: "/Applications/Kern.app", isDirectory: true)
        let resolved = resolveKernAppURL(
            environment: [:],
            currentDirectoryPath: "/tmp/irrelevant",
            homeDirectoryPath: "/Users/tester",
            workspaceURLResolver: { bundleID in
                XCTAssertEqual(bundleID, "com.gradigit.kern")
                return workspaceURL
            },
            fileExists: { _ in false }
        )

        XCTAssertEqual(resolved, workspaceURL)
    }

    func testResolveTextKitBenchEditorPrefersExplicitOverride() {
        let resolved = resolveTextKitBenchEditorCommand(
            environment: ["KERN_BENCH_TEXTKIT_EDITOR": "/tmp/TextKitBenchEditor"],
            currentDirectoryPath: "/tmp/irrelevant",
            isExecutable: { path in
                path == "/tmp/TextKitBenchEditor"
            }
        )

        XCTAssertEqual(resolved, ["/tmp/TextKitBenchEditor"])
    }

    func testResolveTextKitBenchEditorFindsRepoBuildProduct() {
        let resolved = resolveTextKitBenchEditorCommand(
            environment: [:],
            currentDirectoryPath: "/Users/tester/Projects/Kern-textkit",
            isExecutable: { path in
                path == "/Users/tester/Projects/Kern-textkit/scripts/kern-bench/.build/release/TextKitBenchEditor"
            }
        )

        XCTAssertEqual(
            resolved,
            ["/Users/tester/Projects/Kern-textkit/scripts/kern-bench/.build/release/TextKitBenchEditor"]
        )
    }
}
