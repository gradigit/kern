# Editor Benchmarking Methodology

Rigorous methodology for measuring and comparing Kern's performance against other editors.

## Target Editors

| Editor | Architecture | Install | Notes |
|---|---|---|---|
| **Kern** | Native Swift + WKWebView | Local build | Our app |
| **TextEdit** | Native AppKit | System | Baseline native editor |
| **Sublime Text** | Native C++ | `brew install --cask sublime-text` | Gold standard for startup speed |
| **VS Code** | Electron (Chromium + Node) | `brew install --cask visual-studio-code` | Dominant editor, Electron reference |
| **MarkText** | Electron | `brew install --cask mark-text` | Direct competitor (WYSIWYG markdown) |
| **Zed** | Native Rust + Metal | `brew install --cask zed` | Claims sub-100ms startup |

Optional: Obsidian (Electron markdown), Nova (native Panic), MacVim.

## Published Reference Numbers

Context for interpreting our results:

| Editor | Cold Start (published) | Memory (idle) | Source |
|---|---|---|---|
| Sublime Text | ~300-500ms | ~50-80MB | Multiple developer reports |
| Zed | ~120ms (claimed) / ~500ms-1s (real) | 150-250MB | zed.dev, GitHub issues |
| VS Code | ~1.2-4s (varies with extensions) | 300-500MB | VS Code wiki, thesgn.blog |
| MarkText | ~3s warm / ~12s+ cold | ~300MB+ | GitHub issue #3862 |
| TextEdit | ~100-200ms | ~20-30MB | System app baseline |
| Native macOS app (Apple target) | <400ms first frame | — | WWDC 2019 |

## What to Measure

### Tier 1: Cold Start (Primary — Kern's competitive advantage)

| Metric | Definition | Why It Matters |
|---|---|---|
| **Time to window visible** | Process start → window appears on screen | First visual response |
| **Time to content rendered** | Process start → file content is painted | When user sees their file |
| **Time to interactive** | Process start → editor accepts keystrokes | When user can start editing |

### Tier 2: Resource Usage

| Metric | Definition | Tool |
|---|---|---|
| **Memory (total)** | phys_footprint including child processes | `footprint -proc X -targetChildren` |
| **Memory (main process)** | Main process only | `footprint -proc X` |
| **CPU at idle** | CPU% with file loaded, no typing | `top -pid` sampled over 10s |

### Tier 3: Runtime Performance (future)

| Metric | Definition | Notes |
|---|---|---|
| **File open latency** | Running app → open new file → content visible | Measures hot path only |
| **Large file handling** | Open 1MB, 10MB, 100MB markdown files | Tests rendering limits |
| **Typing latency** | Keystroke → character appears | Requires hardware/software setup |

This document focuses on **Tier 1 and Tier 2**. Tier 3 is noted for future work.

## Measurement Approaches

### The Problem with `open -W`

`open -W -a "App" file.md` waits until the app **quits**, not until it's ready. Combined with `hyperfine`, this measures full process lifetime — not useful for "time to interactive" unless you auto-quit after detection.

### The Problem with AppleScript `activate`

`osascript -e 'tell application "X" to activate'` blocks until the Apple Event loop is ready, but the window may still be blank. Up to 10s overhead from the Apple Event mechanism itself.

### Approach 1: Window Detection via CGWindowListCopyWindowInfo

Poll the window server to detect when a new window appears for the target process. Works cross-app without accessibility permissions.

```swift
// Poll every 10ms after launch
// Record timestamp when: PID has on-screen window with non-trivial size
```

**Measures**: Time to window visible (T1).
**Limitation**: Window may be visible but empty (white flash, loading state).

### Approach 2: ScreenCaptureKit Frame Monitoring (Recommended)

Use `SCStream` at 60fps on the target window. Monitor `SCFrameStatus`:
- `.complete` = new frame rendered (content changed)
- `.idle` = no change since last frame (rendering stabilized)

```
T0 = launch command issued
T1 = first on-screen window detected (CGWindowListCopyWindowInfo)
T2 = first .complete frame after window appears (first paint)
T3 = first .idle after series of .complete frames (rendering done)
```

**Measures**: Time to first paint (T2), time to render complete (T3).
**Works for**: Any app (native, Electron, Qt) — captures from the compositor.
**Requires**: Screen Recording permission. macOS 12.3+.

### Approach 3: Accessibility Tree Content Detection

Poll `AXUIElement` for the target window's children. When text content appears in the accessibility tree, the editor has rendered content.

```swift
let axApp = AXUIElementCreateApplication(pid)
// Poll: AXWindow → AXWebArea (or AXTextArea) → AXStaticText children
// Content ready = non-empty text found
```

**Measures**: Time to content rendered (closer to T3).
**Caveat for Electron**: Electron disables accessibility by default. Enabling it with `AXEnhancedUserInterface` impacts the app's performance, skewing results. Not recommended for Electron benchmarks.
**Good for**: Kern (WKWebView exposes AXWebArea), TextEdit, Sublime Text, Zed.

### Approach 4: Internal Timing (Kern only)

Add monotonic timing markers at key lifecycle points. **Do NOT use `CFAbsoluteTimeGetCurrent()`** — it's not monotonic and can be affected by NTP adjustments. Use `clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` or `OSSignposter` instead (see `architect/cold-start-optimization.md` for detailed timing API comparison).

```swift
// main.swift
let processStartNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
// AppDelegate
let nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
NSLog("[Perf] didFinishLaunching: %.1f ms", Double(nowNs - processStartNs) / 1_000_000)
// EditorViewController.editorReady()
NSLog("[Perf] editorReady: %.1f ms", Double(nowNs - processStartNs) / 1_000_000)
// After setMarkdown completes
NSLog("[Perf] contentVisible: %.1f ms", Double(nowNs - processStartNs) / 1_000_000)
```

```typescript
// main.ts
const t0 = performance.now();
// after crepe.create()
console.log(`[Perf] crepe.create: ${performance.now() - t0}ms`);
// after editorReady posted
console.log(`[Perf] editorReady: ${performance.now() - t0}ms`);
```

**Measures**: Exact internal breakdown. Not comparable across apps, but invaluable for optimization.

### Recommended Combined Approach

For cross-editor comparison, use **Approach 1 + 2** (no accessibility interference):

1. Record T0 (launch command)
2. Poll CGWindowListCopyWindowInfo for window → T1
3. Start SCStream on that window
4. Monitor SCFrameStatus → T2 (first paint), T3 (render stable)
5. Kill app, record memory snapshot just before kill

For Kern internal optimization, additionally use **Approach 4**.

## Memory Measurement

### The Right Metric: `phys_footprint`

`phys_footprint` = dirty memory + compressed memory. This is what Activity Monitor shows as "Memory" and what macOS uses for memory pressure decisions.

**Critical for WKWebView and Electron**: Both run content in separate child processes. Measuring only the main process drastically underreports memory.

```bash
# Total memory including child processes (WebContent, GPU, etc.)
sudo footprint -proc "Kern" -targetChildren

# For Electron apps (multiple helper processes)
sudo footprint -proc "Code Helper" -proc "Code Helper (GPU)" -proc "Code Helper (Renderer)" -proc "Electron"

# Quick RSS check (less accurate but no sudo needed)
ps aux | grep -i "AppName" | grep -v grep | awk '{sum+=$6} END {printf "Total RSS: %.1f MB\n", sum/1024}'
```

### Memory Measurement Protocol

1. Launch app with test file
2. Wait 10 seconds for initialization to settle
3. Capture `footprint -targetChildren`
4. Capture `ps aux` RSS for cross-reference
5. Record both values

## Statistical Methodology

### Sample Size

- **Minimum**: 10 runs per editor per metric
- **Recommended**: 20 runs for publication-quality results
- **For quick A/B testing during development**: 5 runs

### Warm vs Cold

| Type | Definition | Preparation |
|---|---|---|
| **Cold** | Filesystem cache empty | `sudo purge; sleep 2` between runs |
| **Warm** | App binaries cached in RAM | 3 warmup runs before measuring |

Report both. Cold start matters for "first open after boot." Warm start matters for "re-open after quitting."

### Handling Outliers

Performance distributions are right-skewed (most runs fast, occasional slow outliers from GC, OS scheduling, spotlight indexing). Use the **IQR method**:

- Q1, Q3, IQR = Q3 - Q1
- Outliers: values outside [Q1 - 1.5*IQR, Q3 + 1.5*IQR]
- Report with and without outliers

### Primary Metric: Median

| Question | Use |
|---|---|
| "How fast does this typically feel?" | **Median** — robust against outliers |
| "Total cost over N launches?" | **Mean** |
| "Best possible?" | **Minimum** |

### What to Report

For each editor × metric:

| Stat | Purpose |
|---|---|
| **Median** | Primary comparison number |
| **Mean** | Secondary |
| **Std Dev** | Consistency |
| **Min / Max** | Range |
| **CV%** | Coefficient of variation (std dev / mean × 100). Below 10% = reliable |
| **n** | Number of runs |

### Presentation

Table format:

| Editor | Type | Median (ms) | Mean (ms) | Std Dev | Min | Max | CV% | n |
|---|---|---|---|---|---|---|---|---|
| Kern | Native+WKWebView | — | — | — | — | — | — | 20 |
| TextEdit | Native AppKit | — | — | — | — | — | — | 20 |
| Sublime Text | Native C++ | — | — | — | — | — | — | 20 |
| Zed | Native Rust | — | — | — | — | — | — | 20 |
| VS Code | Electron | — | — | — | — | — | — | 20 |
| MarkText | Electron | — | — | — | — | — | — | 20 |

Box plots (generated from JSON output) for visual comparison.

## Environment Control

### Before Benchmarking

- [ ] Plug in power (macOS throttles CPU on battery)
- [ ] Close all other apps (especially browsers, Spotlight-heavy apps)
- [ ] Disable Spotlight on test directory: `sudo mdutil -i off /path/to/test/dir`
- [ ] Disconnect network (prevents iCloud, update checks, telemetry)
- [ ] Disable notification banners (System Settings → Notifications → Do Not Disturb)
- [ ] Wait 10+ minutes after boot (let `warmd` finish pre-caching)
- [ ] Use same test file for all editors
- [ ] Run in Release build configuration (not Debug)

### Test File

Use a single canonical test file for all editors. Requirements:
- Pure markdown (no editor-specific extensions)
- Representative size: ~10KB (typical README/document)
- Contains: headings, paragraphs, lists, code blocks, links, bold/italic, table
- No mermaid/LaTeX (not all editors support these)
- Saved as UTF-8, LF line endings

The existing `test-fixtures/stress-test.md` may be too large. Create a `benchmark-test.md` at ~500 lines / ~10KB.

For large-file testing, separately use 1MB and 10MB generated markdown files.

## Benchmark Tool Design

### Architecture

A single Swift CLI tool that:
1. Accepts editor name/path and test file as arguments
2. Launches the editor
3. Detects window appearance (CGWindowListCopyWindowInfo)
4. Monitors frame rendering (ScreenCaptureKit)
5. Captures memory (footprint)
6. Kills the editor
7. Outputs JSON results

```
kern-bench --editor "Kern" --file benchmark-test.md --runs 20 --type warm
kern-bench --editor "Visual Studio Code" --file benchmark-test.md --runs 20 --type cold
kern-bench --compare-all --file benchmark-test.md --runs 20
```

### Output Format

```json
{
  "editor": "Kern",
  "file": "benchmark-test.md",
  "file_size_bytes": 10240,
  "type": "warm",
  "machine": {
    "model": "MacBook Pro (M2 Pro)",
    "macos": "14.5",
    "ram_gb": 16,
    "cpu": "Apple M2 Pro"
  },
  "runs": [
    {
      "window_visible_ms": 145,
      "first_paint_ms": 210,
      "render_complete_ms": 380,
      "memory_footprint_mb": 85.2,
      "memory_rss_mb": 92.1
    }
  ],
  "stats": {
    "window_visible": { "median": 148, "mean": 152, "std": 12, "min": 135, "max": 190, "cv_pct": 7.9 },
    "first_paint": { "median": 215, "mean": 220, "std": 18, "min": 195, "max": 280, "cv_pct": 8.2 },
    "render_complete": { "median": 385, "mean": 392, "std": 25, "min": 350, "max": 450, "cv_pct": 6.4 },
    "memory_footprint": { "median": 85.5, "mean": 86.1, "std": 2.1 },
    "memory_rss": { "median": 92.0, "mean": 93.2, "std": 3.5 }
  }
}
```

### Simpler Shell-Based Alternative

Before building the Swift CLI tool, a bash script can provide useful (if less precise) measurements:

```bash
#!/bin/bash
# Simple launch-time measurement using window detection via osascript
measure_launch() {
    local app="$1"
    local file="$2"
    local process_name="$3"

    killall "$process_name" 2>/dev/null
    sleep 2

    local start=$(perl -MTime::HiRes=time -e 'printf "%.3f\n", time')
    open -a "$app" "$file"

    # Poll for window via System Events
    while ! osascript -e "tell application \"System Events\" to exists window 1 of process \"$process_name\"" 2>/dev/null | grep -q "true"; do
        sleep 0.05
    done

    local end=$(perl -MTime::HiRes=time -e 'printf "%.3f\n", time')
    echo "scale=0; ($end - $start) * 1000 / 1" | bc
}
```

This measures "time to window visible" (T1) with ~50ms resolution. Good enough for comparing 200ms vs 3000ms differences, not precise enough for 200ms vs 250ms.

## Existing Kern Benchmarks: Gap Analysis

Kern already has `scripts/benchmark.sh` and `scripts/comprehensive-benchmark.sh`. These measure:

| What's Covered | Script |
|---|---|
| Cold start (3 runs averaged) | benchmark.sh |
| Large file open | benchmark.sh |
| Multi-tab scaling (10-55 tabs) | comprehensive-benchmark.sh |
| Memory at various tab counts | Both |
| Tab switch latency | benchmark.sh |
| File watcher debounce | comprehensive-benchmark.sh |

| What's Missing | Impact |
|---|---|
| Cross-editor comparison protocol | Can't claim "Xms faster than Y" |
| Statistical rigor (>3 runs, std dev) | Results unreliable for small differences |
| "Time to content rendered" (not just window) | Overstates speed if window appears blank |
| Memory including child processes | Underreports WKWebView memory |
| Cold vs warm distinction | Mixes scenarios |
| Reproducible environment checklist | Results vary between runs |
| Machine-readable output (JSON) | Can't automate regression tracking |
| Render frame monitoring | Can't detect actual content appearance |

## Implementation Plan

### Phase 1: Quick Measurements (shell script)

Extend `scripts/benchmark.sh` with:
- Cross-editor launch comparison (osascript window polling)
- 10+ runs per editor with statistical reporting
- Memory via `footprint -targetChildren`
- Cold/warm separation with `sudo purge`
- JSON output alongside markdown

### Phase 2: Precise Tool (Swift CLI)

Build `scripts/kern-bench` as a compiled Swift tool:
- CGWindowListCopyWindowInfo for window detection (~10ms resolution)
- ScreenCaptureKit SCStream for render detection (~16ms resolution)
- `footprint` subprocess for memory
- JSON output with full statistics
- `--compare-all` mode for multi-editor runs

### Phase 3: Regression Tracking

- Run Phase 1 or 2 after each build
- Store results in `test-fixtures/benchmark-history/`
- Simple Python/shell script to detect >10% regressions
- Optional: XCTApplicationLaunchMetric for Kern-only CI

## How Other Editors Measure Themselves

### VS Code

- Custom `performance.mark` with `code/willXYZ` / `code/didXYZ` prefix pairs
- `--prof-startup` flag captures CPU profiles across main/renderer/extension host
- Automated perf bots (Windows/macOS/Linux) running "best of N" with Slack alerts
- Azure Data Explorer + PowerBI dashboards for trend tracking
- `Developer: Startup Performance` command shows internal perf-mark timelines
- Extension bisect: binary search to isolate perf-regressing extensions

### Zed

- `ZED_MEASUREMENTS` env var enables frame timing output to stderr
- `script/histogram` generates visual comparisons between versions
- Tracy Profiler integration via `ZTRACING=1 cargo r --features tracy --release`
- `#[perf]` test attribute with `cargo perf-test`
- Metal HUD (`MTL_HUD_ENABLED=1`) for GPU frame analysis

### Apple (XCTest)

- `XCTApplicationLaunchMetric` / `XCTOSSignpostMetric.applicationLaunch`
- Measures process start → first frame committed to display server
- 6 launches, discards first, averages last 5
- Built-in baseline comparison and regression detection

## Quick-Start: First Benchmark Run

Before building any tooling, get a rough baseline:

```bash
# Install hyperfine
brew install hyperfine

# Create test file
cat > /tmp/benchmark.md << 'EOF'
# Test Document

## Section 1

This is a paragraph with **bold** and *italic* text.

- Item 1
- Item 2
- Item 3

## Section 2

```python
def hello():
    print("Hello, World!")
```

| Col A | Col B |
|-------|-------|
| 1     | 2     |

> A blockquote for testing.

[A link](https://example.com)

EOF

# Quick warm-start comparison (measures process lifetime, not TTI)
# You must manually Cmd+Q each app after it opens
hyperfine \
  --runs 5 \
  --prepare 'killall "Kern" "Sublime Text" "Code" "TextEdit" 2>/dev/null; sleep 2' \
  -n "Kern" 'open -a Kern /tmp/benchmark.md && sleep 3 && killall Kern' \
  -n "Sublime" 'open -a "Sublime Text" /tmp/benchmark.md && sleep 3 && killall "Sublime Text"' \
  -n "VS Code" 'open -a "Visual Studio Code" /tmp/benchmark.md && sleep 3 && killall "Electron"' \
  -n "TextEdit" 'open -a TextEdit /tmp/benchmark.md && sleep 3 && killall TextEdit'

# Memory snapshot (run each app separately, wait 5s, then measure)
for app in "Kern" "Sublime Text" "Code" "TextEdit"; do
    open -a "$app" /tmp/benchmark.md
    sleep 5
    echo "=== $app ==="
    ps aux | grep -i "$app" | grep -v grep | awk '{sum+=$6} END {printf "  RSS: %.1f MB\n", sum/1024}'
    killall "$app" 2>/dev/null
    sleep 2
done
```

This gives a rough directional comparison. The proper tool (Phase 2) will give precise, per-frame measurements.

## References

- [hyperfine](https://github.com/sharkdp/hyperfine) — CLI benchmarking tool
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) — Frame-level capture with status
- [SCFrameStatus.idle](https://developer.apple.com/documentation/screencapturekit/scframestatus/idle) — Render stability detection
- [footprint](https://developer.apple.com/documentation/os/logging) — macOS memory measurement
- [WWDC19 Session 423](https://developer.apple.com/videos/play/wwdc2019/423/) — Optimizing App Launch
- [XCTApplicationLaunchMetric](https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric)
- [VS Code Perf Tools Wiki](https://github.com/microsoft/vscode/wiki/%5BDEV%5D-Perf-Tools-for-VS-Code-Development)
- [Zed Performance Docs](https://zed.dev/docs/performance)
- [editor-perf benchmark suite](https://github.com/jhallen/joes-sandbox/tree/master/editor-perf)
- [thesgn.blog: VS Code vs Zed](https://www.thesgn.blog/blog/vscode_zed)
- [Thorsten Ball: Benchmarking Process Startup](https://thorstenball.com/benchmarking-process-startup-time/)
- [WebKit Memory Inspection](https://docs.webkit.org/Infrastructure/MemoryInspection.html)
