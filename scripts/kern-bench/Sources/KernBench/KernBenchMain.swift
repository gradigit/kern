import Foundation

// MARK: - Argument Parsing (minimal, no dependencies)

struct BenchConfig {
    var editors: [String] = []
    var allEditors = false
    var file = ""
    var runs = 30
    var warmupRuns = 3
    var cold = false
    var jsonPath: String?
    var markdownPath: String?
    var timeout: TimeInterval = 30
    var noScreenCapture = false
    var verbose = false
}

func parseArgs() -> BenchConfig {
    var config = BenchConfig()
    var args = Array(CommandLine.arguments.dropFirst())

    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--editor":
            guard !args.isEmpty else { exitUsage("--editor requires a value") }
            config.editors.append(args.removeFirst())
        case "--all":
            config.allEditors = true
        case "--file":
            guard !args.isEmpty else { exitUsage("--file requires a value") }
            config.file = args.removeFirst()
        case "--runs":
            guard !args.isEmpty, let n = Int(args.removeFirst()), n > 0 else { exitUsage("--runs requires a positive integer") }
            config.runs = n
        case "--warmup-runs":
            guard !args.isEmpty, let n = Int(args.removeFirst()), n >= 0 else { exitUsage("--warmup-runs requires a non-negative integer") }
            config.warmupRuns = n
        case "--cold":
            config.cold = true
        case "--warm":
            config.cold = false
        case "--json":
            guard !args.isEmpty else { exitUsage("--json requires a path") }
            config.jsonPath = args.removeFirst()
        case "--markdown":
            guard !args.isEmpty else { exitUsage("--markdown requires a path") }
            config.markdownPath = args.removeFirst()
        case "--timeout":
            guard !args.isEmpty, let t = Double(args.removeFirst()), t > 0 else { exitUsage("--timeout requires a positive number") }
            config.timeout = t
        case "--no-screencapture":
            config.noScreenCapture = true
        case "--verbose", "-v":
            config.verbose = true
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            // If it looks like a file path, treat it as the file argument.
            if config.file.isEmpty && !arg.hasPrefix("-") {
                config.file = arg
            } else {
                exitUsage("Unknown argument: \(arg)")
            }
        }
    }

    return config
}

func printUsage() {
    let usage = """
    kern-bench — Cross-editor performance benchmark tool

    USAGE:
      kern-bench [options] [file]

    OPTIONS:
      --editor <name>        Benchmark a specific editor (can repeat)
      --all                  Benchmark all detected editors (default if no --editor)
      --file <path>          Test file to open in each editor
      --runs <n>             Number of iterations (default: 30)
      --warmup-runs <n>      Number of warmup runs, discarded (default: 3)
      --cold                 Purge filesystem cache between runs (requires sudo)
      --warm                 Warmup runs before measuring (default)
      --json <path>          Write JSON results to file
      --markdown <path>      Write markdown table to file
      --timeout <seconds>    Per-run timeout (default: 30)
      --no-screencapture     Disable ScreenCaptureKit (window detection only)
      --verbose, -v          Print per-run details
      --help, -h             Show this help

    EXAMPLES:
      kern-bench --all --file test-fixtures/cross-editor-benchmark.md
      kern-bench --editor Kern --editor Zed --runs 20
      sudo kern-bench --all --cold --runs 30 --json results.json
    """
    print(usage)
}

func exitUsage(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    printUsage()
    exit(1)
}

// MARK: - Main

@main
struct KernBench {
    static func main() async {
        var config = parseArgs()

        // Default file: look for cross-editor-benchmark.md relative to script location.
        if config.file.isEmpty {
            let candidates = [
                "test-fixtures/cross-editor-benchmark.md",
                "../../test-fixtures/cross-editor-benchmark.md",
            ]
            for candidate in candidates {
                if FileManager.default.fileExists(atPath: candidate) {
                    config.file = candidate
                    break
                }
            }
            if config.file.isEmpty {
                exitUsage("No test file specified and default not found. Use --file <path>.")
            }
        }

        // Resolve to absolute path.
        let fileURL = URL(fileURLWithPath: config.file).standardizedFileURL
        config.file = fileURL.path

        guard FileManager.default.fileExists(atPath: config.file) else {
            exitUsage("File not found: \(config.file)")
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: config.file)[.size] as? Int) ?? 0
        let fileHash = sha256Hash(ofFile: config.file)

        // Resolve editors.
        var editors: [EditorDefinition]
        if config.allEditors || config.editors.isEmpty {
            editors = detectInstalledEditors()
        } else {
            editors = config.editors.compactMap { name in
                guard let ed = findEditor(named: name) else {
                    print("Warning: Editor '\(name)' not recognized. Skipping.")
                    return nil
                }
                guard isEditorInstalled(ed) else {
                    print("Warning: \(ed.displayName) not installed. Skipping.")
                    return nil
                }
                return ed
            }
        }

        guard !editors.isEmpty else {
            print("No editors found. Install at least one target editor or use --editor.")
            exit(1)
        }

        // Check ScreenCaptureKit availability.
        var screencaptureAvailable = false
        if !config.noScreenCapture {
            screencaptureAvailable = await checkScreenCapturePermission()
            if !screencaptureAvailable {
                print("Note: Screen Recording permission not granted. Falling back to window detection only.")
                print("      Grant permission in System Settings > Privacy & Security > Screen Recording.")
                print("")
            }
        }

        // Thermal check.
        let thermalPct = detectThermalPct()
        if thermalPct < 100 {
            print("WARNING: CPU thermal throttle detected (\(thermalPct)%). Results may be unreliable.")
            print("         Wait for the machine to cool down or plug in power.")
            print("")
        }

        // Header.
        let env = detectEnvironment(screencaptureAvailable: screencaptureAvailable)
        print("=== kern-bench: Cross-Editor Benchmark ===")
        print("File:    \(config.file) (\(fileSize) bytes)")
        print("SHA256:  \(fileHash)")
        print("Runs:    \(config.runs) (\(config.cold ? "cold" : "warm"), \(config.warmupRuns) warmup)")
        print("Order:   shuffled (interleaved)")
        print("Chip:    \(env.chip)")
        print("macOS:   \(env.macos)")
        print("Power:   \(env.power)")
        print("Thermal: \(thermalPct)%")
        if let display = env.display {
            print("Display: \(display)")
        }
        print("Screen:  \(screencaptureAvailable ? "available (T1+T2+T3)" : "unavailable (T1 only)")")
        print("")
        let editorNames = editors.map { ed in
            let v = editorVersion(ed).map { " v\($0)" } ?? ""
            return "\(ed.displayName)\(v)"
        }
        print("Editors: \(editorNames.joined(separator: ", "))")
        print("")

        // Build report.
        var report = BenchmarkReport(
            version: 3,
            tool: "kern-bench",
            timestamp: timestampISO8601(),
            environment: env,
            config: BenchmarkConfig(
                file: config.file,
                fileBytes: fileSize,
                fileHash: fileHash,
                mode: config.cold ? "cold" : "warm",
                runs: config.runs,
                warmupRuns: config.warmupRuns,
                editorOrder: "shuffled"
            ),
            results: []
        )

        // Initialize per-editor result containers.
        var editorResults: [String: EditorResult] = [:]
        var launchers: [String: EditorLauncher] = [:]
        for editor in editors {
            editorResults[editor.displayName] = EditorResult(
                editor: editor.displayName,
                architecture: editor.architecture,
                version: editorVersion(editor),
                runs: [],
                stats: nil
            )
            launchers[editor.displayName] = EditorLauncher(editor: editor)
        }

        // Kill all editors before starting.
        for editor in editors {
            await launchers[editor.displayName]?.kill()
        }

        // Warmup (warm mode only, not counted).
        if !config.cold && config.warmupRuns > 0 {
            print("Warmup (\(config.warmupRuns) runs per editor)...")
            for _ in 0..<config.warmupRuns {
                for editor in editors {
                    let launcher = launchers[editor.displayName]!
                    await launcher.kill()
                    guard let result = try? await launcher.launch(file: config.file), result.pid > 0 else { continue }
                    _ = await waitForWindow(pid: result.pid, timeout: config.timeout)
                    await launcher.kill()
                }
            }
            print("Warmup complete.\n")
        }

        // Measured runs — interleaved and shuffled editor order per round.
        for runIdx in 1...config.runs {
            let shuffledEditors = editors.shuffled()
            if config.verbose {
                let order = shuffledEditors.map(\.displayName).joined(separator: ", ")
                print("Round \(runIdx)/\(config.runs): [\(order)]")
            }

            for (editorIdx, editor) in shuffledEditors.enumerated() {
                let launcher = launchers[editor.displayName]!

                // Kill any existing instance.
                await launcher.kill()

                // Cold mode: purge filesystem cache.
                if config.cold {
                    let purge = Process()
                    purge.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
                    try? purge.run()
                    purge.waitUntilExit()
                    try? await Task.sleep(for: .seconds(2))
                }

                // Capture per-run environment snapshot.
                let runThermal = detectThermalPct()
                let runPower = detectPowerSource()

                // launch() returns the PID and the exact monotonic timestamp of exec(2).
                // This t0 is captured inside launch() immediately before Process.run(),
                // not inflated by postLaunchDelay or PID polling.
                guard let launchResult = try? await launcher.launch(file: config.file), launchResult.pid > 0 else {
                    if config.verbose {
                        print("  \(editor.displayName) run \(runIdx): LAUNCH FAILED")
                    }
                    continue
                }
                let t0 = launchResult.launchNs
                let pid = launchResult.pid

                // T1: Window visible.
                guard let window = await waitForWindow(pid: pid, timeout: config.timeout) else {
                    if config.verbose {
                        print("  \(editor.displayName) run \(runIdx): TIMEOUT (no window)")
                    }
                    await launcher.kill()
                    continue
                }

                let windowVisibleMs = Double(window.timestampNs - t0) / 1_000_000

                // T2/T3: ScreenCaptureKit frame monitoring.
                var firstPaintMs: Double?
                var renderStableMs: Double?

                if screencaptureAvailable && !config.noScreenCapture {
                    let monitor = FrameMonitor(timeout: config.timeout)
                    let timestamps = await monitor.monitor(windowID: window.windowID)

                    if let fp = timestamps.firstPaintNs {
                        firstPaintMs = Double(fp - t0) / 1_000_000
                    }
                    if let rs = timestamps.renderStableNs {
                        renderStableMs = Double(rs - t0) / 1_000_000
                    }
                } else {
                    // Without ScreenCaptureKit, wait a fixed settle time for memory.
                    try? await Task.sleep(for: .seconds(3))
                }

                // Standardized memory sampling: wait for render stable + 5s settle,
                // or 10s total from launch, whichever comes first.
                let elapsed = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0) / 1_000_000_000
                let additionalSettle = max(0, 10.0 - elapsed)
                if additionalSettle > 0 {
                    try? await Task.sleep(for: .seconds(additionalSettle))
                }

                // Memory snapshot.
                let memory = measureMemory(pid: pid, editor: editor)

                let run = RunResult(
                    windowVisibleMs: windowVisibleMs,
                    firstPaintMs: firstPaintMs,
                    renderStableMs: renderStableMs,
                    memoryPhysMB: memory.physFootprintMB,
                    memoryRssMB: memory.rssMB,
                    thermalPct: runThermal,
                    power: runPower
                )
                editorResults[editor.displayName]?.runs.append(run)

                if config.verbose {
                    var parts = ["\(editor.displayName): window=\(String(format: "%.0f", windowVisibleMs))ms"]
                    if let fp = firstPaintMs { parts.append("paint=\(String(format: "%.0f", fp))ms") }
                    if let rs = renderStableMs { parts.append("stable=\(String(format: "%.0f", rs))ms") }
                    if let phys = memory.physFootprintMB { parts.append("phys=\(String(format: "%.1f", phys))MB") }
                    parts.append("rss=\(String(format: "%.1f", memory.rssMB))MB")
                    print("  \(parts.joined(separator: "  "))")
                } else {
                    print("  \(editor.displayName) run \(runIdx): \(String(format: "%.0f", windowVisibleMs))ms")
                }

                // Cleanup.
                await launcher.kill()

                // 5-second cooldown between editors within each round.
                if editorIdx < shuffledEditors.count - 1 {
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            print("")
        }

        // Compute stats and build final results (preserve original editor order).
        for editor in editors {
            guard var result = editorResults[editor.displayName] else { continue }

            let wvValues = result.runs.compactMap(\.windowVisibleMs)
            let fpValues = result.runs.compactMap(\.firstPaintMs)
            let rsValues = result.runs.compactMap(\.renderStableMs)
            let physValues = result.runs.compactMap(\.memoryPhysMB)
            let rssValues = result.runs.compactMap(\.memoryRssMB)

            result.stats = RunStats(
                windowVisible: wvValues.isEmpty ? nil : computeStats(wvValues),
                firstPaint: fpValues.isEmpty ? nil : computeStats(fpValues),
                renderStable: rsValues.isEmpty ? nil : computeStats(rsValues),
                memoryPhys: physValues.isEmpty ? nil : computeStats(physValues),
                memoryRss: rssValues.isEmpty ? nil : computeStats(rssValues)
            )

            report.results.append(result)
        }

        // Capture end-of-run thermal.
        report = BenchmarkReport(
            version: report.version,
            tool: report.tool,
            timestamp: report.timestamp,
            environment: environmentWithEndThermal(report.environment),
            config: report.config,
            results: report.results
        )

        // Output.
        printMarkdownTable(report)
        printDetailedStats(report)

        if let jsonPath = config.jsonPath {
            do {
                try writeJSONReport(report, to: jsonPath)
                print("JSON results written to: \(jsonPath)")
            } catch {
                print("Error writing JSON: \(error)")
            }
        }

        if let mdPath = config.markdownPath {
            var mdContent = "# Cross-Editor Benchmark Results\n\n"
            mdContent += "Date: \(report.timestamp)\n"
            mdContent += "File: \(report.config.file) (\(report.config.fileBytes) bytes)\n"
            mdContent += "SHA256: \(report.config.fileHash)\n"
            mdContent += "Mode: \(report.config.mode), \(report.config.runs) runs, \(report.config.warmupRuns) warmup\n"
            mdContent += "Chip: \(report.environment.chip), macOS \(report.environment.macos)\n\n"

            let hasScreenCapture = report.results.contains { $0.stats?.firstPaint != nil }

            if hasScreenCapture {
                mdContent += "| Editor | Architecture | Window (ms) | Paint (ms) | Stable (ms) | Phys (MB) | RSS (MB) |\n"
                mdContent += "| --- | --- | ---: | ---: | ---: | ---: | ---: |\n"
            } else {
                mdContent += "| Editor | Architecture | Window (ms) | Phys (MB) | RSS (MB) |\n"
                mdContent += "| --- | --- | ---: | ---: | ---: |\n"
            }

            for result in report.results {
                let wv = result.stats?.windowVisible.map { String(format: "%.0f", $0.median) } ?? "—"
                let phys = result.stats?.memoryPhys.map { String(format: "%.1f", $0.median) } ?? "—"
                let rss = result.stats?.memoryRss.map { String(format: "%.1f", $0.median) } ?? "—"

                if hasScreenCapture {
                    let fp = result.stats?.firstPaint.map { String(format: "%.0f", $0.median) } ?? "—"
                    let rs = result.stats?.renderStable.map { String(format: "%.0f", $0.median) } ?? "—"
                    mdContent += "| \(result.editor) | \(result.architecture) | \(wv) | \(fp) | \(rs) | \(phys) | \(rss) |\n"
                } else {
                    mdContent += "| \(result.editor) | \(result.architecture) | \(wv) | \(phys) | \(rss) |\n"
                }
            }

            do {
                try mdContent.write(toFile: mdPath, atomically: true, encoding: .utf8)
                print("Markdown results written to: \(mdPath)")
            } catch {
                print("Error writing markdown: \(error)")
            }
        }

        print("Done.")
    }
}
