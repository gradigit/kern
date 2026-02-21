import AppKit
import CommonCrypto
import Foundation

// MARK: - Output Models (v3 schema)

struct BenchmarkReport: Codable {
    let version: Int
    let tool: String
    let timestamp: String
    let environment: EnvironmentInfo
    let config: BenchmarkConfig
    var results: [EditorResult]
}

struct EnvironmentInfo: Codable {
    let chip: String
    let macos: String
    let ramGB: Int
    let power: String
    let thermalPct: Int
    let thermalPctEnd: Int?
    let screencaptureAvailable: Bool
    let display: String?

    enum CodingKeys: String, CodingKey {
        case chip, macos, power, display
        case ramGB = "ram_gb"
        case thermalPct = "thermal_pct"
        case thermalPctEnd = "thermal_pct_end"
        case screencaptureAvailable = "screencapture_available"
    }
}

struct BenchmarkConfig: Codable {
    let file: String
    let fileBytes: Int
    let fileHash: String
    let mode: String
    let runs: Int
    let warmupRuns: Int
    let editorOrder: String

    enum CodingKeys: String, CodingKey {
        case file, mode, runs
        case fileBytes = "file_bytes"
        case fileHash = "file_hash"
        case warmupRuns = "warmup_runs"
        case editorOrder = "editor_order"
    }
}

struct EditorResult: Codable {
    let editor: String
    let architecture: String
    let version: String?
    var runs: [RunResult]
    var stats: RunStats?
}

struct RunResult: Codable {
    let windowVisibleMs: Double?
    let firstPaintMs: Double?
    let renderStableMs: Double?
    let memoryPhysMB: Double?
    let memoryRssMB: Double?
    let thermalPct: Int?
    let power: String?

    enum CodingKeys: String, CodingKey {
        case windowVisibleMs = "window_visible_ms"
        case firstPaintMs = "first_paint_ms"
        case renderStableMs = "render_stable_ms"
        case memoryPhysMB = "memory_phys_mb"
        case memoryRssMB = "memory_rss_mb"
        case thermalPct = "thermal_pct"
        case power
    }
}

struct RunStats: Codable {
    let windowVisible: Stats?
    let firstPaint: Stats?
    let renderStable: Stats?
    let memoryPhys: Stats?
    let memoryRss: Stats?

    enum CodingKeys: String, CodingKey {
        case windowVisible = "window_visible"
        case firstPaint = "first_paint"
        case renderStable = "render_stable"
        case memoryPhys = "memory_phys"
        case memoryRss = "memory_rss"
    }
}

// MARK: - Environment Detection

func detectEnvironment(screencaptureAvailable: Bool) -> EnvironmentInfo {
    EnvironmentInfo(
        chip: shellOutput("/usr/sbin/sysctl", args: ["-n", "machdep.cpu.brand_string"]) ?? "Unknown",
        macos: shellOutput("/usr/bin/sw_vers", args: ["-productVersion"]) ?? "Unknown",
        ramGB: detectRAMGB(),
        power: detectPowerSource(),
        thermalPct: detectThermalPct(),
        thermalPctEnd: nil,
        screencaptureAvailable: screencaptureAvailable,
        display: detectDisplay()
    )
}

/// Create an updated environment with end-of-run thermal reading.
func environmentWithEndThermal(_ env: EnvironmentInfo) -> EnvironmentInfo {
    EnvironmentInfo(
        chip: env.chip,
        macos: env.macos,
        ramGB: env.ramGB,
        power: env.power,
        thermalPct: env.thermalPct,
        thermalPctEnd: detectThermalPct(),
        screencaptureAvailable: env.screencaptureAvailable,
        display: env.display
    )
}

/// Detect primary display: resolution, scale factor, and refresh rate.
private func detectDisplay() -> String? {
    guard let screen = NSScreen.main else { return nil }
    let w = Int(screen.frame.width * screen.backingScaleFactor)
    let h = Int(screen.frame.height * screen.backingScaleFactor)
    let scale = Int(screen.backingScaleFactor)
    // Try to get refresh rate from Core Graphics display mode.
    let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
    let refreshHz: Int
    if let mode = CGDisplayCopyDisplayMode(displayID) {
        refreshHz = Int(mode.refreshRate)
    } else {
        refreshHz = 0
    }
    if refreshHz > 0 {
        return "\(w)x\(h)@\(scale)x \(refreshHz)Hz"
    }
    return "\(w)x\(h)@\(scale)x"
}

/// Detect an editor's version from its app bundle's Info.plist.
func detectEditorVersion(bundleIdentifier: String) -> String? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
          let bundle = Bundle(url: url),
          let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String else {
        return nil
    }
    return version
}

private func detectRAMGB() -> Int {
    if let str = shellOutput("/usr/sbin/sysctl", args: ["-n", "hw.memsize"]),
       let bytes = UInt64(str) {
        return Int(bytes / (1024 * 1024 * 1024))
    }
    return 0
}

func detectPowerSource() -> String {
    guard let output = shellOutput("/usr/bin/pmset", args: ["-g", "batt"]) else { return "Unknown" }
    if output.contains("AC Power") { return "AC" }
    if output.contains("Battery Power") { return "Battery" }
    return "Unknown"
}

func detectThermalPct() -> Int {
    guard let output = shellOutput("/usr/bin/pmset", args: ["-g", "therm"]) else { return 100 }
    // Look for "CPU_Speed_Limit = 100"
    for line in output.components(separatedBy: "\n") {
        if line.contains("CPU_Speed_Limit") {
            let parts = line.components(separatedBy: "=")
            if parts.count >= 2, let val = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                return val
            }
        }
    }
    return 100
}

func shellOutput(_ executable: String, args: [String]) -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: executable)
    proc.arguments = args
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - File Hashing

func sha256Hash(ofFile path: String) -> String {
    guard let data = FileManager.default.contents(atPath: path) else { return "unknown" }
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes {
        _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Formatting

func writeJSONReport(_ report: BenchmarkReport, to path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    try data.write(to: URL(fileURLWithPath: path))
}

func printMarkdownTable(_ report: BenchmarkReport) {
    print("")
    print("## Results")
    print("")

    let hasScreenCapture = report.results.contains { $0.stats?.firstPaint != nil }

    if hasScreenCapture {
        print("| Editor | Architecture | Window (ms) | Paint (ms) | Stable (ms) | Phys (MB) | RSS (MB) |")
        print("| --- | --- | ---: | ---: | ---: | ---: | ---: |")
    } else {
        print("| Editor | Architecture | Window (ms) | Phys (MB) | RSS (MB) |")
        print("| --- | --- | ---: | ---: | ---: |")
    }

    for result in report.results {
        let wv = result.stats?.windowVisible.map { String(format: "%.0f", $0.median) } ?? "—"
        let phys = result.stats?.memoryPhys.map { String(format: "%.1f", $0.median) } ?? "—"
        let rss = result.stats?.memoryRss.map { String(format: "%.1f", $0.median) } ?? "—"

        if hasScreenCapture {
            let fp = result.stats?.firstPaint.map { String(format: "%.0f", $0.median) } ?? "—"
            let rs = result.stats?.renderStable.map { String(format: "%.0f", $0.median) } ?? "—"
            print("| \(result.editor) | \(result.architecture) | \(wv) | \(fp) | \(rs) | \(phys) | \(rss) |")
        } else {
            print("| \(result.editor) | \(result.architecture) | \(wv) | \(phys) | \(rss) |")
        }
    }
    print("")
}

func printDetailedStats(_ report: BenchmarkReport) {
    for result in report.results {
        let versionStr = result.version.map { " v\($0)" } ?? ""
        print("--- \(result.editor)\(versionStr) ---")
        if let wv = result.stats?.windowVisible {
            print("  Window visible: median=\(wv.median)ms  p25=\(wv.p25)ms  p75=\(wv.p75)ms  p95=\(wv.p95)ms  CI=[\(wv.ciLower), \(wv.ciUpper)]  CV=\(wv.cvPct)%  n=\(wv.n)")
        }
        if let fp = result.stats?.firstPaint {
            print("  First paint:    median=\(fp.median)ms  p25=\(fp.p25)ms  p75=\(fp.p75)ms  p95=\(fp.p95)ms  CI=[\(fp.ciLower), \(fp.ciUpper)]  CV=\(fp.cvPct)%  n=\(fp.n)")
        }
        if let rs = result.stats?.renderStable {
            print("  Render stable:  median=\(rs.median)ms  p25=\(rs.p25)ms  p75=\(rs.p75)ms  p95=\(rs.p95)ms  CI=[\(rs.ciLower), \(rs.ciUpper)]  CV=\(rs.cvPct)%  n=\(rs.n)")
        }
        if let phys = result.stats?.memoryPhys {
            print("  Memory (phys):  median=\(phys.median)MB  p25=\(phys.p25)MB  p75=\(phys.p75)MB")
        }
        if let rss = result.stats?.memoryRss {
            print("  Memory (RSS):   median=\(rss.median)MB  p25=\(rss.p25)MB  p75=\(rss.p75)MB")
        }
        print("")
    }
}

func timestampISO8601() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: Date())
}
