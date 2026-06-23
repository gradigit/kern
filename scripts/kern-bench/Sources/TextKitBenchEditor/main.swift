import AppKit
import Darwin
import Foundation

private struct BenchReadyPayload: Codable {
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

private struct ParsedArguments {
    var filePath: String?
    var readySignalPath: String?
    var readyMode: String = "textkit_text_assigned"
}

private func parseArguments(_ args: [String]) -> ParsedArguments {
    var parsed = ParsedArguments()
    var index = 1
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--bench-target-file":
            if index + 1 < args.count {
                parsed.filePath = args[index + 1]
                index += 2
            } else {
                index += 1
            }
        case "--bench-ready-signal":
            if index + 1 < args.count {
                parsed.readySignalPath = args[index + 1]
                index += 2
            } else {
                index += 1
            }
        case "--bench-ready-mode":
            if index + 1 < args.count {
                parsed.readyMode = args[index + 1]
                index += 2
            } else {
                index += 1
            }
        default:
            if !arg.hasPrefix("-") {
                parsed.filePath = arg
            }
            index += 1
        }
    }
    return parsed
}

@main
private final class TextKitBenchEditorApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var textView: NSTextView?
    private let args = parseArguments(CommandLine.arguments)

    static func main() {
        let app = NSApplication.shared
        let delegate = TextKitBenchEditorApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let filePath = args.filePath ?? ""
        let markdown = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
        let title = filePath.isEmpty ? "TextKitBenchEditor" : URL(fileURLWithPath: filePath).lastPathComponent

        let frame = NSRect(x: 120, y: 120, width: 1180, height: 820)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false

        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? frame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.isEditable = true
        textView.string = markdown

        scrollView.documentView = textView
        window.contentView = scrollView
        self.window = window
        self.textView = textView

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Let AppKit create and attach the backing window, then write the readiness
        // signal after the requested TextKit boundary is reached.
        DispatchQueue.main.async { [weak self] in
            self?.completeRequestedReadiness(mode: self?.args.readyMode ?? "textkit_text_assigned", filePath: filePath)
        }
    }

    private func completeRequestedReadiness(mode: String, filePath: String) {
        guard let textView, let window else { return }

        textView.layoutSubtreeIfNeeded()
        textView.displayIfNeeded()

        if mode == "textkit_full_layout",
           let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            let characterRange = NSRange(location: 0, length: (textView.string as NSString).length)
            layoutManager.ensureLayout(forCharacterRange: characterRange)
            layoutManager.ensureLayout(for: textContainer)
            textView.layoutSubtreeIfNeeded()
            textView.displayIfNeeded()
        }

        writeReadySignalIfNeeded(mode: mode, filePath: filePath, window: window)
    }

    private func writeReadySignalIfNeeded(mode: String, filePath: String, window: NSWindow) {
        guard let path = args.readySignalPath, !path.isEmpty else { return }

        let payload = BenchReadyPayload(
            event: "bench_ready",
            target: URL(fileURLWithPath: filePath).standardizedFileURL.path,
            mode: mode,
            timestampMonotonicNs: clock_gettime_nsec_np(CLOCK_UPTIME_RAW),
            pid: getpid(),
            windowID: UInt32(window.windowNumber)
        )

        do {
            let outputURL = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: outputURL, options: .atomic)
        } catch {
            // Benchmark harness will time out and report the failure. Keep stderr
            // quiet because benchmark runners redirect app output.
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
