import CoreGraphics
import Darwin
import Foundation

struct ReadinessSnapshotCaptureResult {
    let path: String?
    let elapsedMs: Double?
    let failureReason: String?
}

func captureWindowReadinessSnapshot(
    windowID: CGWindowID,
    rootDirectory: String,
    editorName: String,
    runIndex: Int,
    phase: String,
    launchNs: UInt64
) -> ReadinessSnapshotCaptureResult {
    let elapsedMs = Double(max(monotonicNowNs(), launchNs) - launchNs) / 1_000_000
    let rootURL = URL(fileURLWithPath: rootDirectory).standardizedFileURL

    do {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    } catch {
        return ReadinessSnapshotCaptureResult(
            path: nil,
            elapsedMs: elapsedMs,
            failureReason: "readiness_snapshot_mkdir_failed"
        )
    }

    let safeEditor = sanitizedReadinessSnapshotComponent(editorName)
    let safePhase = sanitizedReadinessSnapshotComponent(phase)
    let fileName = String(format: "%03d-%@-%@.png", runIndex, safeEditor, safePhase)
    let outputURL = rootURL.appendingPathComponent(fileName)

    try? FileManager.default.removeItem(at: outputURL)
    let status = runReadinessSnapshotProcess(
        path: "/usr/sbin/screencapture",
        args: ["-x", "-l\(windowID)", outputURL.path],
        timeoutSeconds: 3
    )
    guard status == 0 else {
        return ReadinessSnapshotCaptureResult(
            path: nil,
            elapsedMs: elapsedMs,
            failureReason: "readiness_snapshot_screencapture_failed:\(status)"
        )
    }

    guard let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
          let size = attrs[.size] as? NSNumber,
          size.intValue > 0 else {
        return ReadinessSnapshotCaptureResult(
            path: nil,
            elapsedMs: elapsedMs,
            failureReason: "readiness_snapshot_empty"
        )
    }

    return ReadinessSnapshotCaptureResult(
        path: outputURL.path,
        elapsedMs: elapsedMs,
        failureReason: nil
    )
}

private func sanitizedReadinessSnapshotComponent(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let mapped = value.unicodeScalars.map { scalar -> Character in
        allowed.contains(scalar) ? Character(scalar) : "-"
    }
    let raw = String(mapped)
        .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    return raw.isEmpty ? "snapshot" : raw
}

private func runReadinessSnapshotProcess(path: String, args: [String], timeoutSeconds: TimeInterval) -> Int32 {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = args
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
    } catch {
        return -1
    }

    let deadlineNs = DispatchTime.now().uptimeNanoseconds + UInt64(max(0.05, timeoutSeconds) * 1_000_000_000)
    while proc.isRunning, DispatchTime.now().uptimeNanoseconds < deadlineNs {
        usleep(2_000)
    }
    if proc.isRunning {
        proc.terminate()
        let terminateDeadlineNs = DispatchTime.now().uptimeNanoseconds + 100_000_000
        while proc.isRunning, DispatchTime.now().uptimeNanoseconds < terminateDeadlineNs {
            usleep(1_000)
        }
    }
    if proc.isRunning {
        Darwin.kill(proc.processIdentifier, SIGKILL)
        let killDeadlineNs = DispatchTime.now().uptimeNanoseconds + 100_000_000
        while proc.isRunning, DispatchTime.now().uptimeNanoseconds < killDeadlineNs {
            usleep(1_000)
        }
    }
    return proc.terminationStatus
}
