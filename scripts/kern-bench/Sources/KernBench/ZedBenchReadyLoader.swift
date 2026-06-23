import Darwin
import Foundation

struct ZedBenchReadyPayload: Codable {
    let event: String
    let target: String
    let mode: String
    let timestampMonotonicNs: UInt64
    let pid: Int32?
    let windowID: UInt32?

    enum CodingKeys: String, CodingKey {
        case event
        case target
        case mode
        case timestampMonotonicNs = "timestamp_monotonic_ns"
        case pid
        case windowID = "window_id"
    }
}

struct ZedBenchReadyWaitResult {
    let payload: ZedBenchReadyPayload?
    let failureReason: String?
}

func loadZedBenchReadyPayload(from path: String) -> ZedBenchReadyPayload? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(ZedBenchReadyPayload.self, from: data)
    } catch {
        return nil
    }
}

func validateZedBenchReadyPayload(
    _ payload: ZedBenchReadyPayload,
    expectedTargetPath: String,
    expectedMode: String,
    expectedPID: pid_t?
) -> String? {
    validateBenchReadyPayload(
        payload,
        expectedTargetPath: expectedTargetPath,
        expectedMode: expectedMode,
        expectedPID: expectedPID,
        reasonPrefix: "zed_bench_hook"
    )
}

func validateBenchReadyPayload(
    _ payload: ZedBenchReadyPayload,
    expectedTargetPath: String,
    expectedMode: String,
    expectedPID: pid_t?,
    reasonPrefix: String
) -> String? {
    guard payload.event == "bench_ready" else {
        return "\(reasonPrefix)_event_mismatch"
    }

    let normalizedMode = payload.mode.trimmingCharacters(in: .whitespacesAndNewlines)
    if !expectedMode.isEmpty, normalizedMode != expectedMode {
        return "\(reasonPrefix)_mode_mismatch"
    }

    let expectedPath = URL(fileURLWithPath: expectedTargetPath).standardizedFileURL.path.lowercased()
    let payloadPath = URL(fileURLWithPath: payload.target).standardizedFileURL.path.lowercased()
    if payloadPath != expectedPath {
        return "\(reasonPrefix)_target_mismatch"
    }

    guard payload.timestampMonotonicNs > 0 else {
        return "\(reasonPrefix)_timestamp_invalid"
    }

    // The forked Zed bench-ready signal is emitted from the process that handles the
    // open-listener request, which can differ from the PID the harness observes for
    // the visible window. The signal path and target file are already unique per run,
    // so PID equality is not a reliable validity check here.
    return nil
}

func waitForZedBenchReady(
    path: String,
    timeout: TimeInterval,
    expectedTargetPath: String,
    expectedMode: String,
    expectedPID: pid_t?
) async -> ZedBenchReadyWaitResult {
    await waitForBenchReady(
        path: path,
        timeout: timeout,
        expectedTargetPath: expectedTargetPath,
        expectedMode: expectedMode,
        expectedPID: expectedPID,
        reasonPrefix: "zed_bench_hook"
    )
}

func waitForBenchReady(
    path: String,
    timeout: TimeInterval,
    expectedTargetPath: String,
    expectedMode: String,
    expectedPID: pid_t?,
    reasonPrefix: String
) async -> ZedBenchReadyWaitResult {
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(0.05, timeout) * 1_000_000_000)
    var lastFailureReason: String?

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if let payload = loadZedBenchReadyPayload(from: path) {
            if let failureReason = validateBenchReadyPayload(
                payload,
                expectedTargetPath: expectedTargetPath,
                expectedMode: expectedMode,
                expectedPID: expectedPID,
                reasonPrefix: reasonPrefix
            ) {
                lastFailureReason = failureReason
            } else {
                return ZedBenchReadyWaitResult(payload: payload, failureReason: nil)
            }
        }
        try? await Task.sleep(for: .milliseconds(15))
    }

    return ZedBenchReadyWaitResult(
        payload: nil,
        failureReason: lastFailureReason ?? "\(reasonPrefix)_timeout"
    )
}
