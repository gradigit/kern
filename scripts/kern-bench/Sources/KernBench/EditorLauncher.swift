import AppKit
import Foundation

/// Result of launching an editor: PID and the exact monotonic timestamp of exec.
struct LaunchResult {
    let pid: pid_t
    /// Monotonic nanosecond timestamp captured immediately before exec(2).
    let launchNs: UInt64
}

struct EditorLauncher {
    let editor: EditorDefinition

    /// Maximum time to wait for the app to register with NSRunningApplication after launch.
    private let pidLookupTimeout: TimeInterval = 5.0

    /// Launch the editor with the given file and return the PID + exact launch timestamp.
    /// Tries CLI launch first (if configured), falls back to `open -a`.
    func launch(file: String) async throws -> LaunchResult {
        if let cli = editor.cliLaunchCommand, !cli.isEmpty {
            if let result = try? await launchViaCLI(cli: cli, file: file), result.pid > 0 {
                return result
            }
            // CLI failed — fall back to open -a with clean args via --args.
            return try await launchViaOpen(file: file, useCleanArgs: true)
        } else {
            return try await launchViaOpen(file: file, useCleanArgs: true)
        }
    }

    /// Launch using CLI command (e.g., `code --new-window ...`).
    private func launchViaCLI(cli: [String], file: String) async throws -> LaunchResult {
        guard let cliPath = findInPath(cli[0]) else {
            throw LaunchError.cliNotFound(cli[0])
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cliPath)
        proc.arguments = Array(cli.dropFirst()) + editor.cleanLaunchArgs + [file]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        // Capture t0 immediately before exec — this is the true launch timestamp.
        let launchNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        try proc.run()

        // Poll for PID registration with retry (up to pidLookupTimeout).
        let pid = try await waitForPID()
        return LaunchResult(pid: pid, launchNs: launchNs)
    }

    /// Launch using NSWorkspace — targets the exact app matching our bundle ID
    /// and returns the PID directly (no polling needed).
    private func launchViaOpen(file: String, useCleanArgs: Bool) async throws -> LaunchResult {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleIdentifier) else {
            // Bundle not found — fall back to open -a by name.
            return try await launchViaOpenCommand(file: file, useCleanArgs: useCleanArgs)
        }

        let fileURL = URL(fileURLWithPath: file)
        let config = NSWorkspace.OpenConfiguration()
        if useCleanArgs && !editor.cleanLaunchArgs.isEmpty {
            config.arguments = editor.cleanLaunchArgs
        }

        // Capture t0 immediately before launch.
        let launchNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let app = try await NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config)
        return LaunchResult(pid: app.processIdentifier, launchNs: launchNs)
    }

    /// Fallback: launch via `open -a` when NSWorkspace bundle lookup fails.
    private func launchViaOpenCommand(file: String, useCleanArgs: Bool) async throws -> LaunchResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var args = ["-a", editor.appName]
        if useCleanArgs && !editor.cleanLaunchArgs.isEmpty {
            args += ["--args"] + editor.cleanLaunchArgs
        }
        args += [file]
        proc.arguments = args

        let launchNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        try proc.run()
        proc.waitUntilExit()

        let pid = try await waitForPID()
        return LaunchResult(pid: pid, launchNs: launchNs)
    }

    /// Poll NSRunningApplication until the editor's bundle ID appears, with exponential backoff.
    private func waitForPID() async throws -> pid_t {
        let startTime = CFAbsoluteTimeGetCurrent()
        var delay: UInt64 = 100 // Start at 100ms

        while CFAbsoluteTimeGetCurrent() - startTime < pidLookupTimeout {
            if let pid = findPIDByBundleIdentifier(editor.bundleIdentifier) {
                return pid
            }
            try? await Task.sleep(for: .milliseconds(Int(delay)))
            delay = min(delay + 100, 500) // Ramp up to 500ms
        }
        return 0
    }

    // MARK: - Kill

    /// Kill the editor and all its child processes. Hard-bounded to ~3 seconds.
    ///
    /// 1. Snapshot all child/helper PIDs while process tree is intact.
    /// 2. Graceful quit via NSRunningApplication.terminate() (2 s grace).
    /// 3. SIGKILL everything (main + children) and verify death.
    func kill() async {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: editor.bundleIdentifier)
            .filter { !$0.isTerminated }
        guard !apps.isEmpty else { return }

        // Snapshot ALL PIDs while the process tree is still intact.
        let ownPID = getpid()
        var allPIDs: [pid_t] = []
        for app in apps {
            let mainPID = app.processIdentifier
            allPIDs += findAllDescendantPIDs(of: mainPID)
            allPIDs.append(mainPID)
        }
        if let prefix = editor.helperProcessPrefix {
            allPIDs += findHelperPIDs(prefix: prefix)
        }
        allPIDs = Array(Set(allPIDs)).filter { $0 != ownPID && $0 > 0 }

        // Phase 1: Graceful quit (2 seconds).
        for app in apps { app.terminate() }

        let deadline = CFAbsoluteTimeGetCurrent() + 2.0
        while CFAbsoluteTimeGetCurrent() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            let alive = NSRunningApplication.runningApplications(withBundleIdentifier: editor.bundleIdentifier)
                .filter { !$0.isTerminated }
            if alive.isEmpty { break }
        }

        // Phase 2: SIGKILL everything — forceTerminate + raw kill for robustness.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: editor.bundleIdentifier) {
            if !app.isTerminated { app.forceTerminate() }
        }
        for pid in allPIDs {
            Foundation.kill(pid, SIGKILL)
        }

        // Wait for process table cleanup and verify.
        try? await Task.sleep(for: .milliseconds(500))
    }

    /// Check if the editor process is currently running (non-terminated).
    func isRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: editor.bundleIdentifier)
            .contains { !$0.isTerminated }
    }
}

enum LaunchError: Error {
    case cliNotFound(String)
}

/// Search PATH for a command, return its absolute path or nil.
private func findInPath(_ command: String) -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    proc.arguments = [command]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !path.isEmpty else { return nil }
    return path
}

// MARK: - PID Detection

/// Find PID using NSRunningApplication bundle identifier (eliminates Electron ambiguity).
func findPIDByBundleIdentifier(_ bundleID: String) -> pid_t? {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    return apps.first?.processIdentifier
}

/// BFS traversal of process tree. Finds all descendant PIDs (children, grandchildren, etc.).
/// Result is ordered parent→child (BFS level order).
func findAllDescendantPIDs(of parentPID: pid_t) -> [pid_t] {
    var result: [pid_t] = []
    var frontier: [pid_t] = [parentPID]

    while !frontier.isEmpty {
        var nextFrontier: [pid_t] = []
        for pid in frontier {
            let children = directChildPIDs(of: pid)
            result.append(contentsOf: children)
            nextFrontier.append(contentsOf: children)
        }
        frontier = nextFrontier
    }
    return result
}

/// Find direct child PIDs of a given parent via `pgrep -P`.
private func directChildPIDs(of parentPID: pid_t) -> [pid_t] {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    proc.arguments = ["-P", "\(parentPID)"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
    proc.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [] }
    return output.components(separatedBy: "\n").compactMap { pid_t($0) }
}

/// Find PIDs matching a helper process prefix via `pgrep -f`.
/// Excludes the current process (kern-bench itself) to avoid self-kill.
func findHelperPIDs(prefix: String) -> [pid_t] {
    let ownPID = getpid()
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    proc.arguments = ["-f", prefix]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
    proc.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [] }
    return output.components(separatedBy: "\n")
        .compactMap { pid_t($0) }
        .filter { $0 != ownPID }
}
