import Foundation

struct MemorySnapshot {
    let physFootprintMB: Double?
    let rssMB: Double
}

/// Measure memory for a process (and all descendants for multi-process apps).
func measureMemory(pid: pid_t, editor: EditorDefinition) -> MemorySnapshot {
    let rss = rssMB(pid: pid, editor: editor)
    let phys = physFootprintMB(pid: pid, includeChildren: editor.isElectron)
    return MemorySnapshot(physFootprintMB: phys, rssMB: rss)
}

/// Collect all PIDs belonging to this editor (main + descendants + helper processes).
private func allEditorPIDs(pid: pid_t, editor: EditorDefinition) -> [pid_t] {
    var pids = [pid]
    // Recursive BFS for all descendant processes.
    pids += findAllDescendantPIDs(of: pid)
    // Additionally match helper processes by prefix (catches re-parented Electron children).
    if let prefix = editor.helperProcessPrefix {
        let helpers = findHelperPIDs(prefix: prefix)
        for h in helpers where !pids.contains(h) {
            pids.append(h)
        }
    }
    return pids
}

/// Get RSS in MB by summing all matching PIDs (main + all descendants).
private func rssMB(pid: pid_t, editor: EditorDefinition) -> Double {
    let pids = editor.isElectron ? allEditorPIDs(pid: pid, editor: editor) : [pid]

    var totalKB: Int = 0
    for p in pids {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-o", "rss=", "-p", "\(p)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let kb = Int(str) {
            totalKB += kb
        }
    }

    return Double(totalKB) / 1024.0
}

/// Try to get phys_footprint via the `footprint` command.
/// Uses `-p <pid> --targetChildren` for multi-process editors.
/// Returns nil if `footprint` fails (e.g., needs sudo for other users' processes).
private func physFootprintMB(pid: pid_t, includeChildren: Bool) -> Double? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/footprint")

    var args = ["-p", "\(pid)"]
    if includeChildren {
        args.append("--targetChildren")
    }
    proc.arguments = args

    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
    proc.waitUntilExit()

    guard proc.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return nil }

    // Parse footprint output. Look for the "phys_footprint" line or the total summary.
    // Typical output: "phys_footprint:  85123456 bytes (81.2M)"
    // Or total: "total: 85123456 bytes (81.2M)"
    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Match lines like "phys_footprint: 85123456" or "total: 85123456"
        if trimmed.hasPrefix("phys_footprint") || (includeChildren && trimmed.hasPrefix("total")) {
            // Try to extract bytes
            let parts = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted)
            for part in parts {
                if let bytes = UInt64(part), bytes > 1_000_000 {
                    return Double(bytes) / (1024.0 * 1024.0)
                }
            }

            // Try to extract the parenthesized MB value like "(81.2M)"
            if let range = trimmed.range(of: #"\(([0-9.]+)M\)"#, options: .regularExpression) {
                let match = trimmed[range]
                let numStr = match.dropFirst().dropLast(2) // Remove "(" and "M)"
                if let mb = Double(numStr) {
                    return mb
                }
            }
        }
    }

    return nil
}
