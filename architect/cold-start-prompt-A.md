# Cold Start Optimization — Phase A

Optimize Kern's cold start time from ~600-1200ms to ~200-500ms through Swift-side and JS-side changes. Also add background daemon mode (opt-in) so that once launched, Kern stays running for instant file opens.

Read `architect/cold-start-optimization.md` first — it has the verified research with timing data, MarkEdit reference patterns, and priority rankings.

## Pre-Implementation: Capture Baseline

Before making any changes, add timing instrumentation and capture baseline measurements.

### 1. Add OSSignposter markers (KernApp/Sources/)

Use `OSSignposter` (not `CFAbsoluteTimeGetCurrent` — not monotonic) to mark key lifecycle points. These appear in Instruments' Points of Interest track.

```swift
import os

private let signposter = OSSignposter(subsystem: "com.kern.app", category: "Launch")
```

Add markers at:
- `main.swift` — process start (`clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` stored as global)
- `AppDelegate.applicationDidFinishLaunching` — start/end of entire method
- `EditorReusePool.warmUp()` — start/end
- `EditorViewController.editorReady()` — timestamp
- `WebBridge.setMarkdown()` completion — timestamp

Also add `NSLog("[Perf] ...")` at each point with milliseconds since process start, so timing is visible in terminal output when running Kern from the command line.

### 2. Add JS-side timing (CoreEditor/src/main.ts)

Add `performance.now()` markers in `init()`:
- Before `new Crepe()` / `new CrepeBuilder()`
- After `crepe.create()`
- After all init complete
- Log via `console.log("[Kern Perf] ...")`

### 3. Capture baseline

Build Release, run from terminal 5 times, record median for each timing point. Save to `test-results/baseline-timing.txt`. This is the before comparison for verification.

## Implementation Items

### Item 1: Pre-load HTML into warm-up WKWebView (~300-600ms savings)

**The single biggest optimization.** Currently `warmUp()` creates 3 empty WKWebViews. HTML only loads when `viewDidLoad()` calls `loadEditorHTML()`. This means the expensive JS initialization (~300-600ms for HTML parse + Crepe create) happens AFTER the window appears.

**Change:** Load HTML into the first warm-up WKWebView so Crepe is already initialized when the first document opens.

**Files to modify:**
- `KernApp/Sources/Editor/EditorReusePool.swift` — `warmUp()` and `createWebView()`
- `KernApp/Sources/Editor/EditorViewController.swift` — `viewDidLoad()` and `editorReady()`

**The handshake problem:** If HTML is pre-loaded in `warmUp()`, JS fires `postMessage({type: "editorReady"})` but no `nativeBridge` message handler exists yet (registered in `attachWebView()`). The message is lost.

**Solution:** After `attachWebView()` in `viewDidLoad()`, check if the WKWebView is already initialized using the async/await variant of `callAsyncJavaScript` (required for Swift 6 strict concurrency — the completion handler variant would violate `@MainActor` isolation):

```swift
// EditorViewController.viewDidLoad()
override func viewDidLoad() {
    super.viewDidLoad()
    Task { @MainActor in
        await checkIfPreLoaded()
    }
}

private func checkIfPreLoaded() async {
    guard let webView else {
        loadEditorHTML()
        return
    }
    do {
        let result = try await webView.callAsyncJavaScript(
            "return typeof window.kern !== 'undefined' && window.kern.isReady()",
            arguments: [:],
            contentWorld: .page
        )
        if result as? Bool == true {
            // Pre-loaded — skip loadEditorHTML(), go straight to editorReady()
            editorReady()
        } else {
            loadEditorHTML()
        }
    } catch {
        // Error checking (e.g., page not loaded yet) — normal path
        loadEditorHTML()
    }
}
```

**Content timing issue:** In the pre-loaded path, `editorReady()` fires immediately — potentially before `EditorDocument.makeWindowControllers()` has set `stringValue`. In the normal path, there's a natural delay while HTML loads. To handle this, `editorReady()` should check if content is available, and if not, set a flag so content is pushed when `stringValue` is later assigned:

```swift
func editorReady() {
    hasFinishedLoading = true
    crashCount = 0
    bridge = WebBridge(webView: webView!)

    if !stringValue.isEmpty {
        Task {
            try? await bridge?.setMarkdown(stringValue)
            // ... scroll position, theme
        }
    }
    // If stringValue is empty, content will be set when the document assigns it.
    // See: add a didSet observer on stringValue that calls setMarkdown if hasFinishedLoading.
}

// Add to stringValue property:
var stringValue: String = "" {
    didSet {
        guard hasFinishedLoading, !stringValue.isEmpty, stringValue != oldValue else { return }
        Task {
            try? await bridge?.setMarkdown(stringValue)
        }
    }
}
```

This ensures content is pushed regardless of which comes first — editor ready or content available.

In `EditorReusePool.warmUp()`, load HTML into the first WKWebView:

```swift
func warmUp() {
    // Create first WKWebView and pre-load editor HTML
    let first = createWebView()
    first.load(URLRequest(url: EditorSchemeHandler.editorURL))
    available.append(first)

    // Defer remaining WKWebViews to avoid blocking main thread (see Item 2)
    // Use Task instead of DispatchQueue.main.async to avoid Swift 6 concurrency warnings
    Task { @MainActor in
        for _ in 0..<2 {
            available.append(createWebView())
        }
    }
}
```

**Expected JS error during warm-up:** When the pre-loaded HTML finishes initializing, `main.ts` tries to post `editorReady` via `window.webkit.messageHandlers.nativeBridge`. Since no `nativeBridge` handler is registered on the warm-up WKWebView, this throws. The `try/catch` in main.ts catches it — this is expected and harmless. `window.kern` is still set up by `setupBridge()`, so `isReady()` returns true when Swift later checks.

**Important:** The `isReady()` check gracefully handles all edge cases:
- Pre-loaded WKWebView dequeued by first document → `isReady()` returns true → fast path
- Non-pre-loaded WKWebView (2nd, 3rd from pool) → `isReady()` returns false → normal path
- Recycled WKWebView (went through `enqueue()` which calls `stopLoading()`) → `isReady()` returns false → normal path

### Item 2: Defer extra WKWebView creation (~100-200ms savings)

Already shown in Item 1. Only create 1 WKWebView synchronously, defer the other 2 to `DispatchQueue.main.async`. Consider MarkEdit's approach of deferring by 1 full second — Kern can do the same since the first document uses the pre-loaded WKWebView from Item 1.

**File:** `KernApp/Sources/Editor/EditorReusePool.swift`

### Item 3: `_drawsBackground = false` (perceived speed)

Eliminates the white flash when WKWebView first appears, especially in dark mode.

**File:** `KernApp/Sources/Editor/EditorReusePool.swift` — in `createWebView()`

**Important:** `_drawsBackground` is a property on **WKWebView**, not WKWebViewConfiguration. Use KVC on the webview instance after creation:

```swift
func createWebView() -> WKWebView {
    let config = WKWebViewConfiguration()
    // ... existing config setup ...
    let webView = WKWebView(frame: .zero, configuration: config)
    // Disable background drawing to eliminate white flash in dark mode.
    // Private SPI — MarkEdit ships with this on the App Store.
    webView.setValue(false, forKey: "drawsBackground")
    // ... rest unchanged
    return webView
}
```

No new file needed — this is a one-line addition to the existing `createWebView()` method.

Also ensure the HTML has proper CSS for initial background:
```css
body { background: #ffffff; }
@media (prefers-color-scheme: dark) {
    body { background: #1e1e1e; }
}
```
This should already be in `kern.css` — verify and add if missing.

### Item 4: Defer non-critical JS init (~10-20ms savings)

Move search, inline-nested, and checkbox icon initialization to after `editorReady` is posted.

**File:** `CoreEditor/src/main.ts`

Currently (lines 340-347):
```typescript
await crepe.create();
initSearch(crepe);
initInlineNested();
initCheckboxIcons();
// ... then posts editorReady
```

Change to:
```typescript
await crepe.create();

// Post editorReady FIRST so Swift can start setMarkdown()
window.webkit?.messageHandlers.nativeBridge.postMessage({ type: "editorReady" });

// Then do non-critical init that can happen while content loads
requestIdleCallback(() => {
    initSearch(crepe);
    initInlineNested();
    initCheckboxIcons();
});
```

**Important:** `requestIdleCallback` is only available in Safari 17.4+ (macOS 14.4+). Kern's minimum target is macOS 14.0 (Safari 17.0), so use `setTimeout` as the primary approach:

```typescript
setTimeout(() => {
    initSearch(crepe);
    initInlineNested();
    initCheckboxIcons();
}, 0);
```

**Note:** `setupBridge(crepe)` must remain BEFORE `crepe.create()` (as it is currently) so that `window.kern` is available when Swift checks `isReady()` in the pre-load detection (Item 1).

### Item 5: Switch from Crepe to CrepeBuilder (~30-200ms bundle reduction)

**File:** `CoreEditor/src/main.ts`

Replace:
```typescript
import { Crepe, CrepeFeature } from "@milkdown/crepe";
```

With:
```typescript
import { CrepeBuilder } from "@milkdown/crepe/builder";
import { blockEdit } from "@milkdown/crepe/feature/block-edit";
import { codeMirror } from "@milkdown/crepe/feature/code-mirror";
import { cursor } from "@milkdown/crepe/feature/cursor";
import { imageBlock } from "@milkdown/crepe/feature/image-block";
import { latex } from "@milkdown/crepe/feature/latex";
import { linkTooltip } from "@milkdown/crepe/feature/link-tooltip";
import { listItem } from "@milkdown/crepe/feature/list-item";
import { table } from "@milkdown/crepe/feature/table";
// Dropped: toolbar (Kern uses native AppKit menu), placeholder
```

Change `new Crepe({...})` to:
```typescript
const crepe = new CrepeBuilder({
    root,
    defaultValue: isWKWebView ? "" : SAMPLE_MARKDOWN,
});

// Add features with configs
crepe.addFeature(codeMirror, { renderPreview });
crepe.addFeature(blockEdit, {
    blockHandle: { getOffset: () => 0, getPlacement: ... },
    listGroup: { taskList: null },
    buildMenu: (builder) => { ... },
});
crepe.addFeature(linkTooltip, { onCopyLink: () => showToast("Link copied") });
crepe.addFeature(listItem);  // renderLabel config applied via crepe.editor.config()
crepe.addFeature(cursor);
crepe.addFeature(imageBlock);
crepe.addFeature(table);
crepe.addFeature(latex);  // Keep LaTeX bundled for now — code splitting in Phase B handles lazy-loading
```

**Verify the `addFeature` API** by checking `CoreEditor/node_modules/@milkdown/crepe/lib/esm/builder.js`. The function signature is `addFeature(feature, config?)` where `feature` is a **named export** (not default) from each feature module — use `import { blockEdit }` not `import blockEdit`.

**Critical: Keep existing custom plugin registrations.** The following `crepe.editor.use()` and `crepe.editor.config()` calls in the current code (main.ts lines 299-332) must remain unchanged — they work identically on `CrepeBuilder` because `crepe.editor` returns the same `Editor` type:

```typescript
// These all stay as-is:
crepe.editor.config((ctx) => { ctx.update(listItemBlockConfig.key, ...) });  // renderLabel
crepe.editor.use(searchPlugin);
crepe.editor.use(remarkCheckbox);
crepe.editor.use(checkboxSchema.node);
crepe.editor.use(checkboxSchema.ctx);
crepe.editor.use(checkboxInputRule);
crepe.editor.use(checkboxClickPlugin);
const bridge = setupBridge(crepe);  // Must update bridge.ts type: Crepe → CrepeBuilder
```

**Also update bridge.ts:** Change the import from `type { Crepe }` to `type { CrepeBuilder }` and update the `setupBridge` parameter type accordingly. The `crepe.editor.action(...)` calls in bridge.ts work on both types — only the type annotation changes.

**After migration:** Run all 36 Playwright tests (`cd CoreEditor && npx playwright test`). All must pass. Also verify:
- Slash menu works (custom buildMenu items)
- Code block copy feedback works
- Mermaid rendering works
- Checkbox system works (standalone, bulleted, ordered)
- Search & replace works
- Link tooltips work
- Math rendering works (LaTeX)

**CSS:** CrepeBuilder may not auto-import all theme CSS. Verify that `@milkdown/crepe/theme/common/style.css` is still imported. Check if feature-specific CSS needs explicit import.

*Items 6-7 are deferred to Phase B (build system overhaul — see `architect/cold-start-prompt-B.md`).*

### Item 8: Shared WKProcessPool (~5-10ms savings)

Minor but clean. Each WKWebView currently gets a new default process pool.

**File:** `KernApp/Sources/Editor/EditorReusePool.swift`

Add a shared pool instance and assign it in `createWebView()`:

```swift
private let processPool = WKProcessPool()

func createWebView() -> WKWebView {
    let config = WKWebViewConfiguration()
    config.processPool = processPool  // ← shared pool
    // ... rest unchanged (including setValue for drawsBackground from Item 3)
}
```

Note: Since macOS 10.15, sharing a pool does NOT make WKWebViews share WebContent processes. The benefit is avoiding pool instantiation overhead (~5-10ms per pool) and sharing cookies/session storage.

### Item 9: Investigate AX framework loading (0-200ms potential)

MarkEdit swizzles `loadAXBundles` to move Accessibility framework initialization to a background thread (AppHacks.swift:14-64). This prevents a potential 50-200ms hang.

**Investigate first:** Profile a Release build with Instruments (App Launch template). Check if `loadAXBundles` or Accessibility framework loading appears in the main thread timeline during launch. If it does:
- Adapt MarkEdit's swizzle pattern for Kern
- Add to `main.swift` before `app.run()`

If it doesn't show up in profiling, skip this item.

### Item 10: Spell checker pre-warm (0-50ms savings)

**File:** `KernApp/Sources/Editor/EditorReusePool.swift`

Add to `warmUp()`:
```swift
NSSpellChecker.shared.checkSpelling(of: "warmup", startingAt: 0)
```

First `NSSpellChecker` invocation is expensive (loads dictionaries). This trades launch latency for typing latency — the dictionary loading happens at launch instead of first keystroke. If profiling shows this adds noticeable launch delay, defer it to after the first document opens instead.

### Item 11: OSSignposter instrumentation (tooling)

Already covered in Pre-Implementation section above. Keep the instrumentation in the code permanently — it's zero-cost when not profiling.

## Background Daemon Mode

### Opt-in "Keep Running in Background"

When enabled, Cmd+Q closes all windows and hides the app instead of quitting. The app stays running with warm WKWebViews. Next `open -a Kern file.md` is instant.

**Files to modify:**
- `KernApp/Sources/App/AppDelegate.swift` — menu item, quit override
- `KernApp/Sources/App/AppDelegate.swift` — `buildMenuBar()` for toggle

**Implementation:**

1. Add a UserDefaults key:
```swift
private var keepRunning: Bool {
    get { UserDefaults.standard.bool(forKey: "keepRunningInBackground") }
    set { UserDefaults.standard.set(newValue, forKey: "keepRunningInBackground") }
}
```

2. Add a menu item to the App menu (between "About Kern" and "Quit Kern"):
```swift
let keepRunningItem = NSMenuItem(
    title: "Keep Running in Background",
    action: #selector(toggleKeepRunning(_:)),
    keyEquivalent: ""
)
appMenu.addItem(keepRunningItem)
```

3. Implement the toggle:
```swift
@objc func toggleKeepRunning(_ sender: NSMenuItem) {
    keepRunning.toggle()
}
```

4. Add menu validation to show checkmark:
```swift
// In NSMenuItemValidation
case #selector(toggleKeepRunning(_:)):
    menuItem.state = keepRunning ? .on : .off
    return true
```

5. Override quit behavior via `applicationShouldTerminate` (preserves the standard `terminate:` selector on the Quit menu item — don't change the Quit menu item's action):

```swift
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if keepRunning {
        // Close all windows, hide app
        for window in NSApp.windows where window.isVisible {
            window.close()
        }
        // Defer activation policy change to after window close animations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.setActivationPolicy(.accessory)
        }
        NSApp.hide(nil)
        return .terminateCancel  // Don't actually quit
    }
    return .terminateNow
}
```

6. Handle re-activation (user clicks Dock icon or opens a file while hidden):

```swift
func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    if !flag {
        // No visible windows — create new untitled document
        openUntitledIfNeeded()
    }
    return true
}
```

Also ensure `setActivationPolicy(.regular)` is called in `makeWindowControllers()` or wherever new documents are opened, so the Dock icon reappears when a file is opened via `open -a Kern`.

**Note:** When `activationPolicy` is `.accessory`, the app has no Dock icon and no menu bar. It's fully invisible until a new document opens.

### Login Item (optional)

Add `SMAppService.loginItem` registration so Kern auto-starts at boot. This should be tied to the "Keep Running in Background" setting — only register as login item when the setting is enabled.

```swift
import ServiceManagement

// When keepRunning is toggled ON:
do {
    try SMAppService.loginItem.register()
} catch {
    NSLog("[AppDelegate] Failed to register login item: %@", error.localizedDescription)
}

// When toggled OFF:
do {
    try SMAppService.loginItem.unregister()
} catch {
    NSLog("[AppDelegate] Failed to unregister login item: %@", error.localizedDescription)
}
```

Requires macOS 13+. Kern targets 14+ — no issue. First registration shows a system notification to the user. If denied, `register()` throws — the error is logged so the failure isn't silent.

## Post-Implementation: Verify

1. **Build CoreEditor first** (if any JS/TS files changed): `cd CoreEditor && npm run build`
2. Build Xcode project: `xcodegen && xcodebuild -project Kern.xcodeproj -scheme Kern -configuration Release build`
3. Run all 36 Playwright tests: `cd CoreEditor && npx playwright test`
4. Run from terminal 5 times, record timing at each NSLog marker
5. Compare against baseline in `test-results/baseline-timing.txt`
6. Run integration test: `./scripts/test-kern-app.sh --skip-build`
7. Test background daemon: enable "Keep Running in Background", Cmd+Q, verify app hides, open a .md file, verify instant open, verify Dock icon disappears/reappears correctly

## Success Criteria

- Cold start time reduced by at least 200ms (median across 5 runs)
- All 36 Playwright E2E tests pass
- Background daemon mode works: Cmd+Q hides, next file open is instant
- No regressions: file open, save, autosave, tab virtualization, themes, search all work
- CrepeBuilder migration: all existing features still work (verify each: mermaid, checkboxes, slash menu, code blocks, tables, links, search)
