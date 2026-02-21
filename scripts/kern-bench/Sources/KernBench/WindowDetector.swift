import CoreGraphics
import Foundation

struct DetectedWindow {
    let windowID: CGWindowID
    let timestampNs: UInt64
    let bounds: CGRect
}

/// Polls CGWindowListCopyWindowInfo until the target PID has an on-screen window.
/// Uses async Task.sleep for safe cooperative scheduling.
func waitForWindow(pid: pid_t, timeout: TimeInterval = 30) async -> DetectedWindow? {
    let startNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    let timeoutNs = UInt64(timeout * 1_000_000_000)

    while true {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        if now - startNs > timeoutNs { return nil }

        if let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] {
            for info in windowList {
                guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                      ownerPID == pid,
                      let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                      let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                      let x = boundsDict["X"] as? CGFloat,
                      let y = boundsDict["Y"] as? CGFloat,
                      let width = boundsDict["Width"] as? CGFloat,
                      let height = boundsDict["Height"] as? CGFloat,
                      width > 50, height > 50 // Ignore tiny/splash windows
                else { continue }

                let detectNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                return DetectedWindow(
                    windowID: windowID,
                    timestampNs: detectNs,
                    bounds: CGRect(x: x, y: y, width: width, height: height)
                )
            }
        }

        try? await Task.sleep(for: .milliseconds(10))
    }
}

