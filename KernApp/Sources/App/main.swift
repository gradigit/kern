import AppKit
import os

/// Monotonic process start time (nanoseconds) for perf logging.
let processStartNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
private let signposter = OSSignposter(subsystem: "com.kern.app", category: "Launch")
let launchInterval = signposter.beginInterval("AppLaunch")

func msSinceStart() -> String {
    let elapsed = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - processStartNs
    return String(format: "%.1f", Double(elapsed) / 1_000_000)
}

NSLog("[Perf] Process start at 0.0ms")

// Allow forcing the native editor prototype (useful for UI tests / automation).
if ProcessInfo.processInfo.environment["KERN_USE_NATIVE_EDITOR"] == "1" {
    UserDefaults.standard.set(true, forKey: "useNativeEditorPrototype")
}

// Native editor preferences (UI tests / automation).
if let v = ProcessInfo.processInfo.environment["KERN_NATIVE_EXPORT_DIALECT"] {
    UserDefaults.standard.set(v, forKey: "nativeEditor.exportDialect") // gfm | kern
}
if let v = ProcessInfo.processInfo.environment["KERN_NATIVE_GFM_EXTENSION_EXPORT"] {
    UserDefaults.standard.set(v, forKey: "nativeEditor.gfmExtensionExportStrategy") // preserve | portable | lint
}
if let v = ProcessInfo.processInfo.environment["KERN_NATIVE_TASK_RENDERING"] {
    UserDefaults.standard.set(v, forKey: "nativeEditor.taskRendering") // gfm | kern
}
if let v = ProcessInfo.processInfo.environment["KERN_NATIVE_ORDERED_TASKS"] {
    UserDefaults.standard.set(v == "1", forKey: "nativeEditor.orderedTasksEnabled")
}
if let v = ProcessInfo.processInfo.environment["KERN_NATIVE_HEADING_CHECKBOXES"] {
    UserDefaults.standard.set(v == "1", forKey: "nativeEditor.headingCheckboxesEnabled")
}
if let v = ProcessInfo.processInfo.environment["KERN_NATIVE_ORDERED_NUMBERING"] {
    UserDefaults.standard.set(v, forKey: "nativeEditor.orderedListNumbering") // gfmDefault | preserveTyped
}
if let v = ProcessInfo.processInfo.environment["KERN_NATIVE_CHECKBOX_HIT_TARGET"] {
    UserDefaults.standard.set(v, forKey: "nativeEditor.checkboxHitTarget") // glyph | marker
}

// Swizzle AX bundle loading to background thread (saves 10-30ms on main thread)
_ = NSObject.swizzleAccessibilityBundlesOnce

// Instantiate KernDocumentController FIRST — the first NSDocumentController
// created becomes NSDocumentController.shared. This must happen before app.run()
// so Apple Event handling routes through our subclass.
let _ = KernDocumentController()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
