import Foundation

// MARK: - Argument Parsing

struct BenchConfig {
    var suiteID: SuiteID = .wow
    var editors: [String] = []
    var allEditors = false
    var file = ""
    var runsOverride: Int?
    var warmupRunsOverride: Int?
    var startupProbeRuns: Int = 0
    var cold = false
    var jsonPath: String?
    var markdownPath: String?
    var timeout: TimeInterval = 30
    var runTimeout: TimeInterval = 45
    var suiteTimeout: TimeInterval = 7200
    var interEditorCooldownMs: Int = 0
    var saveDurable = false
    var noScreenCapture = false
    var enableFrameMonitor = false
    var verbose = false
}

func parseArgs() -> BenchConfig {
    var config = BenchConfig()
    var args = Array(CommandLine.arguments.dropFirst())

    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--suite":
            guard !args.isEmpty else { exitUsage("--suite requires a value") }
            let raw = args.removeFirst()
            guard let suite = SuiteID.parse(raw) else {
                exitUsage("Unknown suite: \(raw). Use wow.")
            }
            if raw.lowercased() != "wow" {
                print("Note: '--suite \(raw)' is deprecated; using 'wow' single-suite mode.")
            }
            config.suiteID = suite
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
            config.runsOverride = n
        case "--warmup-runs":
            guard !args.isEmpty, let n = Int(args.removeFirst()), n >= 0 else { exitUsage("--warmup-runs requires a non-negative integer") }
            config.warmupRunsOverride = n
        case "--startup-probes":
            guard !args.isEmpty, let n = Int(args.removeFirst()), n >= 0 else { exitUsage("--startup-probes requires a non-negative integer") }
            config.startupProbeRuns = n
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
        case "--run-timeout":
            guard !args.isEmpty, let t = Double(args.removeFirst()), t > 0 else { exitUsage("--run-timeout requires a positive number") }
            config.runTimeout = t
        case "--suite-timeout":
            guard !args.isEmpty, let t = Double(args.removeFirst()), t > 0 else { exitUsage("--suite-timeout requires a positive number") }
            config.suiteTimeout = t
        case "--inter-editor-delay-ms":
            guard !args.isEmpty, let ms = Int(args.removeFirst()), ms >= 0 else { exitUsage("--inter-editor-delay-ms requires a non-negative integer") }
            config.interEditorCooldownMs = ms
        case "--save-durable":
            config.saveDurable = true
        case "--no-screencapture":
            config.noScreenCapture = true
        case "--enable-frame-monitor":
            config.enableFrameMonitor = true
        case "--verbose", "-v":
            config.verbose = true
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
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
    kern-bench — Cross-editor benchmark tool

    USAGE:
      kern-bench [options] [file]

    OPTIONS:
      --suite <wow>            Benchmark suite (default: wow; real_use aliases to wow)
      --editor <name>          Benchmark a specific editor (can repeat)
      --all                    Benchmark all installed roster editors
      --file <path>            Test file to open in each editor
      --runs <n>               Number of measured runs (suite default if omitted)
      --warmup-runs <n>        Warmup runs (suite default if omitted)
      --startup-probes <n>     Cold+warm startup probe repetitions per editor (default: 0)
      --cold                   Purge filesystem cache between measured runs
      --warm                   Warm mode (default)
      --json <path>            Write JSON results to file
      --markdown <path>        Write markdown table to file
      --timeout <seconds>      Per-stage timeout (default: 30)
      --run-timeout <seconds>  Per editor-run timeout budget (default: 45)
      --suite-timeout <sec>    Overall suite timeout budget (default: 7200)
      --inter-editor-delay-ms  Delay between editors in a round (default: 0)
      --save-durable           Collect durable-save metric (disabled by default for speed)
      --no-screencapture       Disable ScreenCaptureKit
      --enable-frame-monitor   Enable optional first-paint/render-stable probes
      --verbose, -v            Print per-stage details
      --help, -h               Show this help

    EXAMPLES:
      kern-bench --suite wow --all
      sudo kern-bench --suite wow --all --cold --runs 30 --json results.json
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
        let suite = SuiteDefinition.forID(config.suiteID)
        let runs = config.runsOverride ?? suite.defaultRuns
        let warmupRuns = config.warmupRunsOverride ?? suite.defaultWarmupRuns

        if config.file.isEmpty {
            let candidates = [
                "test-fixtures/cross-editor-benchmark.md",
                "../../test-fixtures/cross-editor-benchmark.md",
            ]
            for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
                config.file = candidate
                break
            }
            if config.file.isEmpty {
                exitUsage("No test file specified and default not found. Use --file <path>.")
            }
        }

        let fileURL = URL(fileURLWithPath: config.file).standardizedFileURL
        config.file = fileURL.path

        guard FileManager.default.fileExists(atPath: config.file) else {
            exitUsage("File not found: \(config.file)")
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: config.file)[.size] as? Int) ?? 0
        let fileHash = sha256Hash(ofFile: config.file)

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
            print("No roster editors found. Install at least one roster target editor.")
            exit(1)
        }

        // Keep deterministic order for final reporting; measured rounds still shuffle.
        editors.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        var screencaptureAvailable = false
        if config.enableFrameMonitor && !config.noScreenCapture {
            screencaptureAvailable = await checkScreenCapturePermission()
            if !screencaptureAvailable {
                print("Note: Screen Recording permission not granted. Frame-monitor diagnostics disabled.")
                print("")
            }
        }

        let accessibilityAvailable = hasAccessibilityPermission()
        if !accessibilityAvailable {
            print("Note: Accessibility permission not granted. Save/quit automation may fail.")
            print("")
        }

        let env = detectEnvironment(
            screencaptureAvailable: config.enableFrameMonitor && !config.noScreenCapture ? screencaptureAvailable : false,
            accessibilityAvailable: accessibilityAvailable
        )

        let selectedNames = Set(editors.map(\.displayName))
        let requiredNames = Set(requiredRosterNames())
        let rosterComplete = selectedNames == requiredNames

        // Header
        print("=== kern-bench: Cross-Editor Benchmark ===")
        print("Suite:   \(suite.displayName) [\(suite.id.rawValue)]")
        print("Usage:   \(suite.intendedUsage)")
        print("Policy:  locked roster v1 (Kern, VS Code, Zed, Sublime Text, TextEdit)")
        print("Claims:  README/social headline claims require OFFICIAL runs only")
        print("File:    \(config.file) (\(fileSize) bytes)")
        print("SHA256:  \(fileHash)")
        print("Runs:    \(runs) (\(config.cold ? "cold" : "warm"), \(warmupRuns) warmup)")
        print("Timeout: stage=\(Int(config.timeout))s run=\(Int(config.runTimeout))s suite=\(Int(config.suiteTimeout))s")
        print("SaveDur: \(config.saveDurable ? "enabled" : "disabled")")
        print("Order:   shuffled (interleaved)")
        print("Chip:    \(env.chip)")
        print("macOS:   \(env.macos)")
        print("Power:   \(env.power)")
        print("Thermal: \(env.thermalPct)%")
        if let display = env.display {
            print("Display: \(display)")
        }
        print("Screen:  \(config.enableFrameMonitor ? (screencaptureAvailable ? "available" : "unavailable") : "disabled")")
        print("FrameMon:\(config.enableFrameMonitor ? " enabled" : " disabled")")
        print("AX:      \(accessibilityAvailable ? "available" : "missing")")
        print("Roster:  \(rosterComplete ? "complete" : "incomplete")")
        print("")

        let editorNames = editors.map { ed in
            let v = editorVersion(ed).map { " v\($0)" } ?? ""
            return "\(ed.displayName)\(v)"
        }
        print("Editors: \(editorNames.joined(separator: ", "))")
        print("")

        var launchers: [String: EditorLauncher] = [:]
        var collectors: [String: MetricCollector] = [:]
        var editorResults: [String: EditorResult] = [:]

        for editor in editors {
            launchers[editor.displayName] = EditorLauncher(editor: editor)
            collectors[editor.displayName] = MetricCollector()
            editorResults[editor.displayName] = EditorResult(
                editor: editor.displayName,
                architecture: editor.architecture,
                version: editorVersion(editor),
                runQuality: RunQuality.complete.rawValue,
                runClassification: RunClassification.official.rawValue,
                partialReasons: [],
                runs: [],
                stats: nil
            )
        }

        // Ensure clean baseline.
        for editor in editors {
            await launchers[editor.displayName]?.kill()
        }

        // Preflight startup probes for both cold and warm start latency metrics.
        let startupProbeRuns = config.startupProbeRuns
        if startupProbeRuns > 0 {
            print("Preflight startup probes (\(startupProbeRuns)x cold + \(startupProbeRuns)x warm per editor)...")
            for editor in editors {
                guard let launcher = launchers[editor.displayName], var collector = collectors[editor.displayName] else { continue }
                for _ in 0..<startupProbeRuns {
                    let coldProbe = await startupProbe(
                        launcher: launcher,
                        file: config.file,
                        timeout: suite.stageTimeouts["startup"] ?? config.timeout,
                        cold: true,
                        purgeFSCache: config.cold,
                        verbose: config.verbose,
                        editorName: editor.displayName
                    )
                    collector.record(metric: "cold_start_latency_ms", value: coldProbe.valueMs, failureReason: coldProbe.failureReason, timedOut: coldProbe.timedOut)
                }

                for _ in 0..<startupProbeRuns {
                    let warmProbe = await startupProbe(
                        launcher: launcher,
                        file: config.file,
                        timeout: suite.stageTimeouts["startup"] ?? config.timeout,
                        cold: false,
                        purgeFSCache: false,
                        verbose: config.verbose,
                        editorName: editor.displayName
                    )
                    collector.record(metric: "warm_start_latency_ms", value: warmProbe.valueMs, failureReason: warmProbe.failureReason, timedOut: warmProbe.timedOut)
                }
                collectors[editor.displayName] = collector
            }
            print("Preflight startup probes complete.")
            print("")
        } else {
            print("Preflight startup probes skipped (--startup-probes 0).")
            print("")
        }

        if !config.cold && warmupRuns > 0 {
            print("Warmup (\(warmupRuns) runs per editor)...")
            for _ in 0..<warmupRuns {
                for editor in editors {
                    let launcher = launchers[editor.displayName]!
                    await launcher.kill()
                    let runFile = prepareRunFixtureCopy(sourceFile: config.file, editorName: editor.displayName, runIndex: -1)
                    guard let result = try? await launcher.launch(file: runFile), result.pid > 0 else { continue }
                    _ = await waitForWindow(pid: result.pid, timeout: config.timeout)
                    await launcher.kill()
                    try? FileManager.default.removeItem(atPath: runFile)
                }
            }
            print("Warmup complete.")
            print("")
        }

        // Measured runs.
        var measuredThermals: [Int] = []
        let suiteStartNs = monotonicNowNs()
        let suiteDeadlineNs = suiteStartNs + UInt64(config.suiteTimeout * 1_000_000_000)
        var suiteTimedOut = false

        runLoop: for runIdx in 1...runs {
            if monotonicNowNs() >= suiteDeadlineNs {
                suiteTimedOut = true
                break
            }

            let shuffledEditors = editors.shuffled()
            print("Round \(runIdx)/\(runs): \(shuffledEditors.map(\.displayName).joined(separator: ", "))")

            for (editorIdx, editor) in shuffledEditors.enumerated() {
                if monotonicNowNs() >= suiteDeadlineNs {
                    suiteTimedOut = true
                    break runLoop
                }

                guard let launcher = launchers[editor.displayName],
                      var result = editorResults[editor.displayName],
                      var collector = collectors[editor.displayName]
                else { continue }

                await launcher.kill()
                if config.cold {
                    _ = runProcess(path: "/usr/sbin/purge", args: [])
                    try? await Task.sleep(for: .seconds(2))
                }

                let runStartNs = monotonicNowNs()
                let runDeadlineNs = runStartNs + UInt64(config.runTimeout * 1_000_000_000)
                let runFile = prepareRunFixtureCopy(sourceFile: config.file, editorName: editor.displayName, runIndex: runIdx)
                var failureReasons: [String: String] = [:]
                var timeoutCount = 0
                var failureCount = 0
                let runThermal = detectThermalPct()
                let runPower = detectPowerSource()
                measuredThermals.append(runThermal)
                let cycleMetrics = ["open_latency_ms", "typing_latency_ms", "save_ui_ack_latency_ms", "quit_latency_ms"]

                func stageBudget(stage: String) -> TimeInterval {
                    let defaultTimeout = suite.stageTimeouts[stage] ?? config.timeout
                    let now = monotonicNowNs()
                    if now >= runDeadlineNs || now >= suiteDeadlineNs {
                        return 0.05
                    }
                    let runRemaining = Double(runDeadlineNs - now) / 1_000_000_000
                    let suiteRemaining = Double(suiteDeadlineNs - now) / 1_000_000_000
                    return max(0.05, min(defaultTimeout, runRemaining, suiteRemaining))
                }

                func deadlineReason() -> String {
                    if monotonicNowNs() >= suiteDeadlineNs {
                        return "suite_timeout"
                    }
                    if monotonicNowNs() >= runDeadlineNs {
                        return "run_timeout"
                    }
                    return "run_budget_exhausted"
                }

                func appendRun(
                    openLatencyMs: Double?,
                    typingLatencyMs: Double?,
                    saveUiAckMs: Double?,
                    saveDurableMs: Double?,
                    quitLatencyMs: Double?,
                    windowVisibleMs: Double?,
                    firstPaintMs: Double?,
                    renderStableMs: Double?
                ) {
                    // Single source of truth: suite.requiredMetrics.
                    // Startup metrics are collected via preflight probes rather than each measured run.
                    let runRequiredMetrics = suite.requiredMetrics.filter {
                        $0 != "cold_start_latency_ms" && $0 != "warm_start_latency_ms"
                    }
                    let metricValueMap: [String: Double?] = [
                        "open_latency_ms": openLatencyMs,
                        "typing_latency_ms": typingLatencyMs,
                        "save_ui_ack_latency_ms": saveUiAckMs,
                        "quit_latency_ms": quitLatencyMs,
                    ]
                    let requiredMissing = runRequiredMetrics.contains { metricValueMap[$0] == nil }
                    let runQuality: RunQuality = requiredMissing ? .degraded : .complete

                    let run = RunResult(
                        runIndex: runIdx,
                        coldStartLatencyMs: nil,
                        warmStartLatencyMs: nil,
                        openLatencyMs: openLatencyMs,
                        saveUiAckLatencyMs: saveUiAckMs,
                        saveDurableLatencyMs: saveDurableMs,
                        quitLatencyMs: quitLatencyMs,
                        typingLatencyMs: typingLatencyMs,
                        findLatencyMs: nil,
                        scrollSettleLatencyMs: nil,
                        scrollEffectiveFPS: nil,
                        scrollP95FrameTimeMs: nil,
                        scrollP99FrameTimeMs: nil,
                        scrollHitchMsPerS: nil,
                        scrollJank33msCount: nil,
                        scrollJank50msCount: nil,
                        windowVisibleMs: windowVisibleMs,
                        firstPaintMs: firstPaintMs,
                        renderStableMs: renderStableMs,
                        memoryPhysMB: nil,
                        memoryRssMB: nil,
                        runQuality: runQuality.rawValue,
                        stageTimeoutCount: timeoutCount,
                        stageFailureCount: failureCount,
                        metricFailureReasons: failureReasons,
                        scrollMetricMode: nil,
                        thermalPct: runThermal,
                        power: runPower
                    )
                    result.runs.append(run)
                }

                func recordCycleFailure(reason: String, timedOut: Bool, includeWindowMetric: Bool = false) {
                    for metric in cycleMetrics {
                        collector.record(metric: metric, value: nil, failureReason: reason, timedOut: timedOut)
                        failureReasons[metric] = reason
                        failureCount += 1
                        if timedOut {
                            timeoutCount += 1
                        }
                    }
                    if includeWindowMetric {
                        collector.record(metric: "window_visible_ms", value: nil, failureReason: reason, timedOut: timedOut)
                    }
                    appendRun(
                        openLatencyMs: nil,
                        typingLatencyMs: nil,
                        saveUiAckMs: nil,
                        saveDurableMs: nil,
                        quitLatencyMs: nil,
                        windowVisibleMs: nil,
                        firstPaintMs: nil,
                        renderStableMs: nil
                    )
                }

                func markFailure(_ metric: String, _ stage: StageResult) {
                    if let reason = stage.failureReason {
                        failureReasons[metric] = reason
                        failureCount += 1
                    }
                    if stage.timedOut {
                        timeoutCount += 1
                    }
                }

                print("  [\(editor.displayName)] run \(runIdx): launch")
                guard let launchResult = try? await launcher.launch(file: runFile), launchResult.pid > 0 else {
                    print("  [\(editor.displayName)] run \(runIdx): launch failed")
                    recordCycleFailure(reason: "launch_failed", timedOut: false)
                    collectors[editor.displayName] = collector
                    editorResults[editor.displayName] = result
                    try? FileManager.default.removeItem(atPath: runFile)
                    continue
                }

                if monotonicNowNs() >= runDeadlineNs || monotonicNowNs() >= suiteDeadlineNs {
                    let reason = deadlineReason()
                    print("  [\(editor.displayName)] run \(runIdx): \(reason)")
                    await launcher.kill()
                    recordCycleFailure(reason: reason, timedOut: true)
                    collectors[editor.displayName] = collector
                    editorResults[editor.displayName] = result
                    try? FileManager.default.removeItem(atPath: runFile)
                    continue
                }

                let t0 = launchResult.launchNs
                let pid = launchResult.pid

                print("  [\(editor.displayName)] run \(runIdx): wait window")
                let windowTimeout = stageBudget(stage: "open")
                guard let window = await waitForWindow(pid: pid, timeout: windowTimeout) else {
                    let reason = monotonicNowNs() >= suiteDeadlineNs ? "suite_timeout" :
                        (monotonicNowNs() >= runDeadlineNs ? "run_timeout" : "open_timeout")
                    print("  [\(editor.displayName)] run \(runIdx): \(reason) waiting for window")
                    await launcher.kill()
                    recordCycleFailure(reason: reason, timedOut: true, includeWindowMetric: true)
                    collectors[editor.displayName] = collector
                    editorResults[editor.displayName] = result
                    try? FileManager.default.removeItem(atPath: runFile)
                    continue
                }

                let windowVisibleMs = Double(window.timestampNs - t0) / 1_000_000
                collector.record(metric: "window_visible_ms", value: windowVisibleMs)

                var firstPaintMs: Double?
                var renderStableMs: Double?

                if config.enableFrameMonitor && screencaptureAvailable && !config.noScreenCapture && !editor.isElectron {
                    print("  [\(editor.displayName)] run \(runIdx): frame monitor")
                    // Keep benchmark throughput high: frame monitor is diagnostic-only and
                    // should not consume full stage timeout when signals are unavailable.
                    let frameProbeTimeout = min(1.2, stageBudget(stage: "open"))
                    let monitor = FrameMonitor(timeout: frameProbeTimeout)
                    let timestamps = await monitor.monitor(windowID: window.windowID)
                    if let fp = timestamps.firstPaintNs {
                        firstPaintMs = Double(fp - t0) / 1_000_000
                        collector.record(metric: "first_paint_ms", value: firstPaintMs)
                    } else {
                        collector.record(metric: "first_paint_ms", value: nil, failureReason: "first_paint_unavailable")
                    }
                    if let rs = timestamps.renderStableNs {
                        renderStableMs = Double(rs - t0) / 1_000_000
                        collector.record(metric: "render_stable_ms", value: renderStableMs)
                    } else {
                        collector.record(metric: "render_stable_ms", value: nil, failureReason: "render_stable_unavailable")
                    }
                }

                let actionRunner = ActionRunner(
                    editor: editor,
                    pid: pid,
                    windowID: window.windowID,
                    accessibilityAvailable: accessibilityAvailable,
                    verbose: config.verbose
                )

                print("  [\(editor.displayName)] run \(runIdx): open readiness")
                let openReady = await actionRunner.runOpenReadiness(
                    timeout: stageBudget(stage: "open"),
                    expectedFileName: URL(fileURLWithPath: runFile).lastPathComponent,
                    expectedFilePath: runFile
                )
                let openLatencyMs = openReady.valueMs.map { windowVisibleMs + $0 }
                let openStage = StageResult(
                    valueMs: openLatencyMs,
                    failureReason: openReady.failureReason,
                    timedOut: openReady.timedOut
                )
                collector.record(
                    metric: "open_latency_ms",
                    value: openStage.valueMs,
                    failureReason: openStage.failureReason,
                    timedOut: openStage.timedOut
                )
                markFailure("open_latency_ms", openStage)

                print("  [\(editor.displayName)] run \(runIdx): type")
                let typing = await actionRunner.runTyping(
                    timeout: stageBudget(stage: "typing"),
                    payload: "bench-cycle"
                )
                collector.record(metric: "typing_latency_ms", value: typing.valueMs, failureReason: typing.failureReason, timedOut: typing.timedOut)
                markFailure("typing_latency_ms", typing)

                print("  [\(editor.displayName)] run \(runIdx): save")
                let saveDurableTimeout = config.saveDurable ? stageBudget(stage: "save_durable") : 0
                let (saveUIRaw, saveDurable) = await actionRunner.runSave(
                    timeoutUI: stageBudget(stage: "save_ui"),
                    timeoutDurable: saveDurableTimeout,
                    filePath: runFile
                )
                let saveUI = saveUIRaw
                collector.record(metric: "save_ui_ack_latency_ms", value: saveUI.valueMs, failureReason: saveUI.failureReason, timedOut: saveUI.timedOut)
                markFailure("save_ui_ack_latency_ms", saveUI)
                if config.saveDurable {
                    collector.record(metric: "save_durable_latency_ms", value: saveDurable.valueMs, failureReason: saveDurable.failureReason, timedOut: saveDurable.timedOut)
                    markFailure("save_durable_latency_ms", saveDurable)
                }

                print("  [\(editor.displayName)] run \(runIdx): quit")
                let quit = await actionRunner.runQuit(timeout: stageBudget(stage: "quit"))
                collector.record(metric: "quit_latency_ms", value: quit.valueMs, failureReason: quit.failureReason, timedOut: quit.timedOut)
                markFailure("quit_latency_ms", quit)

                appendRun(
                    openLatencyMs: openLatencyMs,
                    typingLatencyMs: typing.valueMs,
                    saveUiAckMs: saveUI.valueMs,
                    saveDurableMs: saveDurable.valueMs,
                    quitLatencyMs: quit.valueMs,
                    windowVisibleMs: windowVisibleMs,
                    firstPaintMs: firstPaintMs,
                    renderStableMs: renderStableMs
                )

                editorResults[editor.displayName] = result
                collectors[editor.displayName] = collector

                await launcher.kill()
                try? FileManager.default.removeItem(atPath: runFile)
                measuredThermals.append(detectThermalPct())

                if editorIdx < shuffledEditors.count - 1, config.interEditorCooldownMs > 0 {
                    try? await Task.sleep(for: .milliseconds(config.interEditorCooldownMs))
                }
            }
            print("")
        }

        // Build stats and editor classifications.
        var orderedResults: [EditorResult] = []

        let thermalEnd = detectThermalPct()
        let thermalThroughoutOK = measuredThermals.allSatisfy { $0 == 100 } && thermalEnd == 100

        let preflight = PreflightStatus(
            thermalAtStartOK: env.thermalPct == 100,
            thermalThroughoutOK: thermalThroughoutOK,
            rosterComplete: rosterComplete,
            screenCapturePermissionOK: config.enableFrameMonitor ? ((!config.noScreenCapture) && screencaptureAvailable) : true,
            accessibilityPermissionOK: accessibilityAvailable,
            fixtureHashRecorded: !fileHash.isEmpty,
            powerSource: env.power,
            thermalPctStart: env.thermalPct,
            thermalPctEnd: thermalEnd
        )

        for editor in editors {
            guard var result = editorResults[editor.displayName], let collector = collectors[editor.displayName] else { continue }

            let stats = RunStats(
                coldStartLatency: collector.stats(metric: "cold_start_latency_ms"),
                warmStartLatency: collector.stats(metric: "warm_start_latency_ms"),
                openLatency: collector.stats(metric: "open_latency_ms"),
                saveUiAckLatency: collector.stats(metric: "save_ui_ack_latency_ms"),
                saveDurableLatency: collector.stats(metric: "save_durable_latency_ms"),
                quitLatency: collector.stats(metric: "quit_latency_ms"),
                typingLatency: collector.stats(metric: "typing_latency_ms"),
                findLatency: collector.stats(metric: "find_latency_ms"),
                scrollSettleLatency: collector.stats(metric: "scroll_settle_latency_ms"),
                scrollEffectiveFPS: collector.stats(metric: "scroll_effective_fps"),
                scrollP95FrameTime: collector.stats(metric: "scroll_p95_frame_time_ms"),
                scrollP99FrameTime: collector.stats(metric: "scroll_p99_frame_time_ms"),
                scrollHitchMsPerS: collector.stats(metric: "scroll_hitch_ms_per_s"),
                scrollJank33msCount: collector.stats(metric: "scroll_jank_33ms_count"),
                scrollJank50msCount: collector.stats(metric: "scroll_jank_50ms_count"),
                windowVisible: collector.stats(metric: "window_visible_ms"),
                firstPaint: collector.stats(metric: "first_paint_ms"),
                renderStable: collector.stats(metric: "render_stable_ms"),
                memoryPhys: collector.stats(metric: "memory_phys_mb"),
                memoryRss: collector.stats(metric: "memory_rss_mb")
            )

            result.stats = stats
            let editorOutcome = classifyEditorResult(suite: suite, result: result, preflight: preflight)
            result.runQuality = editorOutcome.runQuality.rawValue
            result.runClassification = editorOutcome.runClassification.rawValue
            result.partialReasons = editorOutcome.partialReasons

            orderedResults.append(result)
        }

        let reportOutcome = classifyReport(
            suite: suite,
            preflight: preflight,
            editorResults: orderedResults,
            selectedEditors: editors
        )

        var report = BenchmarkReport(
            version: 4,
            tool: "kern-bench",
            timestamp: timestampISO8601(),
            suite: suite.id.rawValue,
            runClassification: reportOutcome.runClassification.rawValue,
            runQuality: reportOutcome.runQuality.rawValue,
            partialReasons: reportOutcome.partialReasons,
            environment: environmentWithEndThermal(env),
            preflight: preflight,
            config: BenchmarkConfig(
                suite: suite.id.rawValue,
                suiteIntendedUsage: suite.intendedUsage,
                rosterPolicy: "locked_roster_v1_official_claims_only",
                file: config.file,
                fileBytes: fileSize,
                fileHash: fileHash,
                mode: config.cold ? "cold" : "warm",
                runs: runs,
                warmupRuns: warmupRuns,
                editorOrder: "shuffled",
                requiredRoster: requiredRosterNames(),
                requiredMetrics: suite.requiredMetrics
            ),
            results: orderedResults
        )

        if suiteTimedOut,
           !report.partialReasons.contains("suite_timeout") {
            report.partialReasons.append("suite_timeout")
            report.runClassification = RunClassification.partial.rawValue
            report.runQuality = RunQuality.degraded.rawValue
        }

        // Ensure classification reflects end-of-run thermal state.
        if report.environment.thermalPctEnd ?? 100 < 100,
           !report.partialReasons.contains("thermal_throttle") {
            report.partialReasons.append("thermal_throttle")
            report.runClassification = RunClassification.partial.rawValue
            report.runQuality = RunQuality.degraded.rawValue
        }

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
            do {
                try markdownSummary(report: report).write(toFile: mdPath, atomically: true, encoding: .utf8)
                print("Markdown results written to: \(mdPath)")
            } catch {
                print("Error writing markdown: \(error)")
            }
        }

        print("Done.")
    }
}

// MARK: - Helpers

private func monotonicNowNs() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
}

private func startupProbe(
    launcher: EditorLauncher,
    file: String,
    timeout: TimeInterval,
    cold: Bool,
    purgeFSCache: Bool,
    verbose: Bool,
    editorName: String
) async -> StageResult {
    await launcher.kill()
    if cold && purgeFSCache {
        _ = runProcess(path: "/usr/sbin/purge", args: [])
        try? await Task.sleep(for: .seconds(2))
    }

    let runFile = prepareRunFixtureCopy(sourceFile: file, editorName: editorName, runIndex: cold ? -100 : -101)
    defer { try? FileManager.default.removeItem(atPath: runFile) }

    let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    guard let launchResult = try? await launcher.launch(file: runFile), launchResult.pid > 0 else {
        return StageResult(valueMs: nil, failureReason: cold ? "cold_launch_failed" : "warm_launch_failed", timedOut: false)
    }

    guard let window = await waitForWindow(pid: launchResult.pid, timeout: timeout) else {
        await launcher.kill()
        return StageResult(valueMs: nil, failureReason: cold ? "cold_start_timeout" : "warm_start_timeout", timedOut: true)
    }

    await launcher.kill()

    let elapsed = Double(window.timestampNs - launchResult.launchNs) / 1_000_000
    if verbose {
        let mode = cold ? "cold" : "warm"
        print("  [\(editorName)] preflight \(mode) startup: \(String(format: "%.0f", elapsed))ms")
    }
    // Use t0 to avoid unused variable warning in case launch timestamp is unavailable in future changes.
    _ = t0
    return StageResult(valueMs: elapsed, failureReason: nil, timedOut: false)
}

private func prepareRunFixtureCopy(sourceFile: String, editorName: String, runIndex: Int) -> String {
    let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kern-bench-runs", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let filename = "\(editorName.replacingOccurrences(of: " ", with: "-").lowercased())-run\(runIndex).md"
    let dst = tmpDir.appendingPathComponent(filename)
    try? FileManager.default.removeItem(at: dst)
    do {
        try FileManager.default.copyItem(at: URL(fileURLWithPath: sourceFile), to: dst)
        return dst.path
    } catch {
        // Never mutate the source fixture. Fallback: manual write copy.
        if let data = FileManager.default.contents(atPath: sourceFile) {
            do {
                try data.write(to: dst)
                return dst.path
            } catch {
                // Last resort: unique in-memory dump path.
                let fallback = tmpDir.appendingPathComponent(UUID().uuidString + ".md")
                do {
                    try data.write(to: fallback)
                    return fallback.path
                } catch {
                    let emptyFallback = tmpDir.appendingPathComponent(UUID().uuidString + "-empty.md")
                    try? Data().write(to: emptyFallback)
                    return emptyFallback.path
                }
            }
        }
        let emptyFallback = tmpDir.appendingPathComponent(UUID().uuidString + "-empty.md")
        try? Data().write(to: emptyFallback)
        return emptyFallback.path
    }
}

private func runProcess(path: String, args: [String]) -> Int32 {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = args
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    } catch {
        return -1
    }
}

private func markdownSummary(report: BenchmarkReport) -> String {
    var out = "# Cross-Editor Benchmark Results\n\n"
    out += "Suite: \(report.suite)\n"
    out += "Intended usage: \(report.config.suiteIntendedUsage)\n"
    out += "Classification: \(report.runClassification)\n"
    out += "Run quality: \(report.runQuality)\n"
    if !report.partialReasons.isEmpty {
        out += "Partial reasons: \(report.partialReasons.joined(separator: "; "))\n"
    }
    out += "\n"
    out += "| Editor | Class | Open p50 | Save UI p50 | Quit p50 |\n"
    out += "| --- | --- | ---: | ---: | ---: |\n"
    for result in report.results {
        let open = result.stats?.openLatency.map { String(format: "%.0f", $0.median) } ?? "—"
        let saveUI = result.stats?.saveUiAckLatency.map { String(format: "%.0f", $0.median) } ?? "—"
        let quit = result.stats?.quitLatency.map { String(format: "%.0f", $0.median) } ?? "—"
        out += "| \(result.editor) | \(result.runClassification) | \(open) | \(saveUI) | \(quit) |\n"
    }
    out += "\n"
    out += "Policy: README/social headline claims require OFFICIAL runs only.\n"
    return out
}
