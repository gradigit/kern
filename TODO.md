# Kern — Task List

Persistent task tracker. Update this file as work progresses so new sessions can resume.

## Completed

- [x] **Phase 1: CoreEditor HTML** — Milkdown Crepe single-file HTML, tested in Safari
- [x] **Phase 2: Minimal Swift Shell** — WKWebView loading editor, bridge working both directions, pool of 3 pre-warmed WKWebViews
- [x] **Phase 3: NSDocument Integration** — EditorDocument, file open/save/autosave, `open -a Kern file.md` works, cold launch fixed via KernDocumentController subclass, `window.isRestorable = false` to prevent Synapse restoration
- [x] **Phase 4: File Watching + Auto-Reload** — `presentedItemDidChange()` with 300ms debounce, mod date check prevents autosave loops, `revert(toContentsOf:ofType:)` reloads content, scroll position preserved across reloads, toast notification on reload, debug NSLog statements cleaned up
- [x] **Phase 5: Tab Virtualization** — EditorReusePool rewritten to LRU-evicting with max 5 live WKWebViews, background tabs virtualized to stringValue + cachedScrollPosition, viewDidAppear triggers rehydration, windowWillClose releases WKWebView back to pool, scroll position tracked via JS scroll listener → scrollChanged bridge message
- [x] **Phase 6: Themes + Menus + Polish** — AppearanceManager observes system theme and broadcasts to all live editors, Format menu with Bold (⌘B) / Italic (⌘I) / Code (⌘E) via bridge.execCommand(), menu item validation, placeholder "K" app icon, responsive CSS polish with overflow protection for tables/code/images
- [x] **Phase 7: Bug Fixes** — 9 bugs fixed across 4 sub-phases:
  - **Phase 7A (Swift)**: Blank tabs fixed via `windowDidBecomeMain` rehydration, links open in browser via `decidePolicyForNavigationAction`, images load via `loadHTMLString` instead of `loadFileURL`
  - **Phase 7B (Web)**: Mermaid diagrams render via Crepe `renderPreview` API, block handle visible at narrow widths (3rem padding), nested list numbering (a/i), checklist strikethrough via `:has(.label.checked)`
  - **Phase 7C (Tests)**: 36 Playwright E2E tests (rendering, links, mermaid 12 types, themes, bridge API), stress test file with nested checklists
  - **Phase 7D (Benchmark)**: `scripts/benchmark.sh` comparing Kern vs MarkEdit (cold start, memory, file open latency)
- [x] **Phase 9: Bug Fixes + Polish** — 4 bugs fixed:
  - Auto-save false dirty flag: `suppressNativeNotify` in bridge.ts prevents Milkdown normalization from triggering `contentChanged` during `setMarkdown()`
  - Block handle clipping: Removed `overflow-x: clip` from `#editor`
  - Checklist strikethrough cascade: Split CSS into grey-out + strikethrough rules
  - Mermaid text labels: Marker-and-replace strategy in `mermaid.ts` bypasses DOMPurify's foreignObject stripping

- [x] **Phase 10: Bug Fixes, Features & Test Improvements** — 8 items + follow-up fixes:
  - **Phase 1A**: Removed `scroll-behavior: smooth` from `#editor` (fixes blank areas on fast scroll), added `contain: layout style` to `.milkdown .editor`
  - **Phase 1B**: Block handle spacing tightened — gap 0, 24×24px buttons, left padding reduced from 5.5rem to 3.5rem, BlockEdit `getOffset: 8`
  - **Phase 1C**: Toast on link copy — `toast.ts` with `showToast()`, Crepe `LinkTooltip.onCopyLink` callback
  - **Phase 2A**: Links now clickable — tooltip URL click and Cmd+click post `openURL` to native bridge, WKUIDelegate `createWebViewWith` catches `target="_blank"` links, NativeBridge protocol extended with `openURL`
  - **Phase 3A**: Cmd+F conflict fixed — Full Screen moved to Ctrl+Cmd+F, Find (⌘F) / Find and Replace (⇧⌘H) / Use Selection for Find (⌘E) added to Edit menu, Code shortcut changed to ⌘`
  - **Phase 3B**: Search & Replace — full ProseMirror plugin with DecorationSet highlights, fixed search bar at top of viewport, case toggle, N of M counter, replace/replace-all, debounced input, Esc to close, JS keydown intercept for Cmd+F/Cmd+Shift+H/Cmd+E
  - **Phase 4A**: Test script uses `elements` mode in ax-scroll.swift — collects all AX content elements for fine-grained scrolling screenshots
  - **Phase 4B+4C**: Mega stress test updated with Table of Contents anchor links and 9 nested checklist permutation tests (1L–1T) including compact inline syntax (`1. - [x] text`)
  - **ToC fix**: `scrollToFragment` function with slugified fallback — Milkdown's heading IDs keep colons, our anchors use GitHub-style slugs, fallback scans headings by text content

- [x] **Phase 11: UX Improvements** — 2 items:
  - **Cmd+hold tooltip hiding**: keydown/keyup listeners on Meta key toggle `kern-cmd-held` CSS class, hiding `.milkdown-link-preview` — allows frictionless Cmd+click on links without tooltip blocking adjacent targets
  - **Inline nested checkboxes**: Two-part approach: (1) `inline-nested.ts` MutationObserver marks collapsible list items with `.kern-inline-nested`, CSS `display: contents` collapses intermediate wrappers onto one line. (2) Custom `renderLabel` in `main.ts` shows both list type indicator + checkbox for checked items (e.g., bullet dot + checkbox). CSS `.kern-type-ind` hides the extra indicator by default, shows it only in `.kern-inline-nested` context. Result: `1. - [x] text` → `1. • ☑ text`, `- 1. [x] text` → `• 1. ☑ text`. Recursive: `1. - 1. [x] text` → `1. • 1. ☑ text`. WebKit-compatible.

- [x] **Phase 12: Checkbox System + Cmd+N/Cmd+T** — Three-tier checkbox syntax, keyboard shortcuts:
  - **Standalone checkbox node** (`checkbox.ts`): Custom ProseMirror node for `[ ] text` syntax (Kern extension)
    - `$nodeSchema` with `checked` attr, `$inputRule` matching `^\\[( |x)\\] $`
    - `$remark` plugin: parse (`[ ] text` → `kern_checkbox` mdast) + serialize (`kern_checkbox` → `[ ] text`)
    - `$prose` click handler: toggle checked via `handleClickOn`
    - MutationObserver injects SVG icons into `toDOM` placeholder spans
    - Skips conversion inside list items (defers to GFM task list input rule)
  - **Bulleted tasks** (`- [ ] text`): Always show bullet + checkbox (`• ☐`). Changed `kern-type-ind` → `kern-indicator` in renderLabel.
  - **Ordered tasks** (`1. [ ] text`): Show number + checkbox (`1. ☐`). Unchanged from previous.
  - **Slash menu**: Disabled default "Task List" via `listGroup: { taskList: null }`. Three new items via `buildMenu`:
    - "Task List" → creates standalone checkbox node
    - "Bulleted Task" → creates `bullet_list > list_item[checked=false]`
    - "Ordered Task" → creates `ordered_list > list_item[checked=false]`
  - **Cmd+N / Cmd+T** (AppDelegate.swift): Custom `newWindow:` / `newTab:` actions. Cmd+N temporarily sets `tabbingMode = .disallowed` for standalone window. Cmd+T uses `addTabbedWindow:ordered:` for tab in current window.
  - **KERN-MARKDOWN.md**: Documents Kern's syntax extensions vs GFM spec

- [x] **Phase 13: Copy Feedback, Table Wrapping, Scrollbar Fixes, Cmd+Click Cursor** — 4 items:
  - **Code block copy feedback**: Click "Copy" button → shows "✓ Copied!" with green checkmark for 2 seconds. Uses document-level click handler (not Crepe's `onCopy` callback, which silently fails in WKWebView when `navigator.clipboard.writeText()` rejects). CSS `.kern-copied` class disables pointer-events during feedback.
  - **Table text wrapping**: Long text in table cells was overflowing into adjacent columns. Added `overflow-wrap: break-word` on th/td and `overflow-x: auto` on `.milkdown-table-block` wrapper.
  - **Code block scrollbar fix**: macOS overlay scrollbars were overlapping text in single-line code blocks. Added `padding-bottom: 10px` to `.cm-scroller` for space, plus `overflow-y: hidden` to prevent the padding from creating a spurious vertical scrollbar.
  - **Cmd+click pointer cursor**: Holding Cmd now shows pointer (hand) cursor on links, signaling they're clickable. CSS `.kern-cmd-held a { cursor: pointer }` — uses the existing `kern-cmd-held` class toggled by keydown/keyup listeners in bridge.ts.

- [x] **Phase 14: Cold Start Optimization — Phase A** — 10 items implemented:
  - **OSSignposter + NSLog timing**: Process start, applicationWillFinishLaunching/didFinishLaunching, warmUp start/end, editorReady, setMarkdown complete timestamps
  - **JS-side timing**: `performance.now()` markers before Crepe init, after create(), after init complete
  - **Pre-load HTML into warm-up WKWebView**: First WKWebView loads HTML in `warmUp()` (now in `applicationWillFinishLaunching`). Pool tracks pre-loaded WKWebViews via `ObjectIdentifier` set. `checkIfPreLoaded()` detects pre-loaded WKWebView and waits for load instead of reloading. FIFO dequeue order.
  - **Defer extra WKWebView creation**: Only 1 WKWebView created synchronously, remaining 2 deferred via `Task { @MainActor in ... }`
  - **`_drawsBackground = false`**: Eliminates white flash in dark mode. Private SPI via KVC.
  - **Shared WKProcessPool**: Single `WKProcessPool` instance shared across all WKWebViews
  - **Spell checker pre-warm**: `NSSpellChecker.shared.checkSpelling()` in warmUp to front-load dictionary loading
  - **Defer non-critical JS init**: `initSearch`, `initInlineNested`, `initCheckboxIcons` deferred via `setTimeout(…, 0)` after `editorReady` message posted
  - **CrepeBuilder migration**: Replaced `Crepe` with `CrepeBuilder` + explicit `addFeature()`. Dropped toolbar + placeholder features. Bundle reduced ~800KB (5.2MB from 6MB). Updated bridge.ts + search.ts types.
  - **Background daemon mode**: "Keep Running in Background" toggle in App menu with checkmark. Cmd+Q hides app (setActivationPolicy .accessory) instead of quitting. Re-activation via Dock click or file open restores regular policy. SMAppService.mainApp login item registration tied to toggle.
  - **Body CSS**: Added `body { background }` with dark mode media query to match theme when `_drawsBackground=false`
  - **stringValue didSet**: Handles pre-load timing edge case where editor is ready before document assigns content. Suppress flag prevents JS→Swift→JS loop via contentChanged.
  - **warmUp moved to applicationWillFinishLaunching**: macOS creates untitled document between willFinish and didFinish — pool must be warm before that.
  - **Measured result**: Debug build editorReady ~365ms (down from ~530-600ms), setMarkdown ~470ms. Pre-loaded WKWebView starts HTML load ~250ms earlier than without pre-loading.

- [x] **Phase 15: Cold Start Optimization — Phase B (Code Splitting)** — 4 items implemented:
  - **Vite code splitting**: Removed `vite-plugin-singlefile`, configured standard Vite build with `manualChunks` for mermaid. HTML reduced from ~5MB to 781 bytes. Total dist/ is 4.9MB (down from ~5.2MB, no base64 overhead).
  - **Extended EditorSchemeHandler**: Rewritten to serve all files from `CoreEditor/dist/` via `kern://` scheme. Supports JS, CSS, fonts, images, JSON with proper MIME types. `HTTPURLResponse` with CORS headers for ES module loading. Path traversal protection.
  - **Removed loadHTML()**: Scheme handler now reads files on demand from bundle (OS page cache). Removed `loadHTML()` method and `htmlData` property. Removed caller from `AppDelegate.applicationWillFinishLaunching`.
  - **ES modules verified**: `<script type="module">` works over `kern://` custom scheme in WKWebView. Mermaid and diagram sub-chunks lazy-load on demand via scheme handler.
  - **Build output**: `index.html` (781B) + `app-[hash].js` (1.3MB entry) + `chunks/` (104 files: mermaid core 534KB, diagram types, KaTeX fonts, CSS). Lazy chunks only load when needed.
  - **Debug timing**: editorReady 341ms (Phase A baseline was 396ms in Release).
  - **Release timing (5-run median, stress-test.md)**: editorReady 337ms, setMarkdown 450ms (Phase A baseline: 396ms / 586ms).

- [x] **Phase 16: Cold Start Optimization — Phase C (Deep Optimization)** — 4 items implemented:
  - **Initial content injection**: EditorViewController injects markdown via `window.__kern_initialContent` while WKWebView is still loading. main.ts applies it during Crepe init, eliminating the editorReady→setMarkdown round-trip. `editorReady` = `document rendered` — no separate setMarkdown step.
  - **AX framework swizzle**: `AppHacks.swift` swizzles `loadAXBundles` to move AccessibilityBundles loading to background thread (saves 10-30ms on main thread). VoiceOver-safe: loads synchronously if VoiceOver is active. Adapted from MarkEdit (App Store approved).
  - **CSS inlining**: Custom Vite plugin inlines CSS `<link>` into `<style>` block in HTML, saving one scheme handler round-trip during initial load. CSS file kept in bundle for mermaid's lazy chunk dependency maps.
  - **Cache-Control headers**: EditorSchemeHandler returns `Cache-Control: max-age=31536000, immutable` for hash-named files (JS, CSS, fonts) to enable JSC bytecode caching. `no-cache` for index.html.
  - **Release timing (5-run median, stress-test.md)**: editorReady = document rendered at **339ms** (was 450ms total in Phase B). Process-to-rendered improved **42%** vs pre-optimization baseline of 586ms.

## Current State: All Phases Complete — Testing & Polish

### Test Suites

#### Playwright E2E Tests (36 tests, 0 failures)

Run: `cd CoreEditor && npx playwright test`

| Suite | Tests | Status |
|-------|-------|--------|
| rendering.spec.ts | 9 | PASS |
| links.spec.ts | 2 | PASS |
| mermaid.spec.ts | 16 | PASS |
| theme.spec.ts | 3 | PASS |
| bridge.spec.ts | 6 | PASS |

Mermaid tests cover all 12 diagram types: flowchart, sequenceDiagram, classDiagram, stateDiagram-v2, erDiagram, gantt, pie, gitGraph, mindmap, timeline, journey, sankey-beta. Plus error handling and multi-block tests.

**Important**: Playwright uses **WebKit** browser (`browserName: "webkit"` in playwright.config.ts), matching the WKWebView engine used in Kern.app.

#### Kern.app Integration Test

Run: `./scripts/test-kern-app.sh [--skip-build] [--screenshots]`

Tests: xcodegen + xcodebuild, launch with mega-stress-test.md, stability for 15s, optional scrolling screenshots.

**Not yet run** — run this after context restore to verify.

### Pending Manual Tests
- [ ] Test copy/paste in and out of editor
- [ ] Test window resizing and minimum size behavior (min is 640x480)
- [ ] Investigate table resizing
- [ ] Test inline local images and remote image links
- [ ] **Run full scroll-to-bottom screenshot test**: `./scripts/test-kern-app.sh --screenshots` — review all screenshots for visual correctness
- [ ] **Benchmarks: Kern vs VSCode vs MarkText** — need to create benchmark methodology:
  - Cold start time (time from launch to first render)
  - Memory usage with mega-stress-test.md loaded
  - File open latency (time to open and render file)
  - Method: Use `time` + `ps` for Kern (CLI launch), need to figure out scripted benchmarking for VSCode (`code --wait`) and MarkText (`open -a MarkText`)
  - Compare using same test file across all three editors

## Bugs to Fix

- [ ] **"File reloaded from disk" toast on first open** — The NSFilePresenter `presentedItemDidChange()` fires when first opening a file, showing the reload toast even though no external change occurred. Likely a race condition between `read(from:ofType:)` and file presenter registration. Fix: add a flag in EditorDocument to suppress the first `presentedItemDidChange` after open, or check if the content actually differs from what's already in the editor.
- [ ] **Toast styling** — Currently a plain dark rectangle. Could use `NSVisualEffectView` for a translucent frosted-glass look (macOS native). Keep it lightweight — no animation framework, just the vibrancy material. The JS-side toast (toast.ts) should match.
- [ ] **Block handle vertical alignment with regular text** — Buttons still sit slightly above regular paragraph text. Headings are fine (centered `left` placement works). The `left-start` + 3px padding-top approach gets close but isn't pixel-perfect. May need per-block-type offset via Floating UI middleware, or a CSS `transform: translateY()` conditional on sibling block type. Low priority — cosmetic only.

## Pending Investigation / Future Features

- [ ] **Persistent undo/redo across sessions** — Can Cmd+Z undo changes days/months later? Not built into NSUndoManager or ProseMirror's history plugin. Would require serializing the full undo+redo stack to a sidecar file (like Vim's `undodir` or Emacs `undo-fu-session`). Sublime Text and VS Code both support this. Non-trivial but technically feasible. ProseMirror's history plugin stores steps that could be serialized to JSON. Storage location: `~/Library/Application Support/Kern/undo/<file-hash>.json` or a `.kern-undo` sidecar next to the file. Must preserve redo stack alongside undo. More research needed before implementing.
- [ ] **Smart dirty tracking / original state restoration** — If all changes are undone (Cmd+Z back to original), mark document as clean so autosave doesn't write. This would preserve the original modification date. ProseMirror can compare current doc to a "clean" snapshot. **Caveat**: autosave fires frequently, so the window for "undo back to original" may be too narrow to be useful in practice. May not be worth implementing.
- [ ] **Settings page** — Needed for production readiness. If added: font size, font family, theme override (light/dark/system), default new file template. Consider a simple SwiftUI Settings scene. **Priority: after core editing is fully polished.** Focus on code quality and optimization first before adding new features.
- [ ] **Quick Look Preview Extension** — Bundle a `.appex` in Kern that provides Finder spacebar previews for `.md` files. Uses `QLPreviewProvider` (data-based HTML, macOS 12+) with `cmark-gfm` or `swift-markdown` parser + static CSS matching Kern's theme. Cannot use Milkdown (too heavy for extension). **Note**: window size/position is system-controlled — no Quick Look extension can remember it (same limitation as QLmarkdown). See `architect/quicklook-research.md` for full research.
- [ ] **App logo** — Need a distinctive icon. Current placeholder is "K". Design direction: typography-focused (kern = typographic term for letter spacing). Consider hiring a designer or using a tool like Figma/Sketch. The icon needs 1024×1024px master + all required sizes for macOS.
- [x] **Cold start optimization Phase A** — DONE (Phase 14). See completed section above.
- [x] **Cold start optimization Phase B** — DONE (Phase 15). See completed section above.
- [x] **AX framework swizzle** — DONE (Phase 16). AppHacks.swift swizzles loadAXBundles to background thread. Profile with Instruments to verify impact.
- [ ] **Benchmarking tool** — Methodology documented in `architect/benchmarking-methodology.md`. Cross-editor comparison (Kern vs TextEdit, Sublime, VS Code, Zed, MarkText) using CGWindowListCopyWindowInfo + ScreenCaptureKit frame monitoring. Existing `scripts/benchmark.sh` lacks statistical rigor and cross-editor protocol. Implementation not started.
- [ ] **Zoom (Cmd+Plus / Cmd+Minus / Cmd+0)** — Use WKWebView's native `magnification` property (no JS bridge or CSS needed). MarkEdit uses the same approach in `EditorViewController+Menu.swift`. Implementation:
  - Add `zoomIn`, `zoomOut`, `actualSize` methods to `EditorViewController.swift` — adjust `webView.magnification` by ±0.1, clamped to 1.0–3.0 range
  - Add menu items to the existing View menu in `AppDelegate.swift` — Cmd+Plus, Cmd+Minus, Cmd+0
  - Add `NSMenuItemValidation` cases — disable Zoom In at max (3.0), Zoom Out at min (1.0), Actual Size when already at 1.0
  - CSS is compatible: base font 16px, headings use em multipliers — magnification scales everything proportionally
  - **Not persisted**: zoom resets on document reopen (same as MarkEdit). Could store in UserDefaults later if needed
  - **Virtualization note**: zoom level is per-WKWebView instance, so virtualized tabs lose zoom on rehydrate — store on EditorViewController if persistence is added

## Known Issues

- **Inline ordered checkboxes need manual verification** — see `MANUAL-TESTING.md` for checklist
- EditorDocument Swift 6 warnings for nonisolated init and background-thread property access — intentional, required for NSDocumentController compatibility
- Undo/Redo (⌘Z/⇧⌘Z) handled natively by WKWebView → ProseMirror history plugin (no explicit Swift wiring needed)
- Since macOS 10.15, each WKWebView gets its own WebContent process regardless of WKProcessPool sharing. A shared pool only provides shared cookies/session storage and avoids pool instantiation overhead (~5-10ms). See `architect/cold-start-optimization.md` for details.
- Nested list numbering CSS is best-effort — Milkdown's list-item component doesn't expose depth info, so we use `ol ol` and `ol ol ol` nesting selectors

## Key Fixes Applied (reference for future sessions)

- **Auto-save false dirty flag**: `suppressNativeNotify` in bridge.ts prevents Milkdown's markdown normalization from triggering `contentChanged` during programmatic `setMarkdown()` calls
- **Block handle clipping**: Removed `overflow-x: clip` from `#editor` — block handle uses Floating UI absolute positioning that was being clipped
- **Mermaid text labels**: DOMPurify strips foreignObject children. Fix: marker-and-replace strategy — pass marker div through `applyPreview` (survives DOMPurify), use MutationObserver to replace with correctly-parsed SVG (foreignObject intact)
- **Swift 6 crash on document open**: `nonisolated override init()` + `@preconcurrency import AppKit` in EditorDocument prevents `dispatch_assert_queue_fail` when NSDocumentController opens documents from background threads
- **Cold launch extra untitled**: `KernDocumentController` (NSDocumentController subclass) sets `hasOpenedDocument` flag synchronously when Apple Event opens a file, checked by `AppDelegate.openUntitledIfNeeded()`
- **macOS Synapse state restoration**: `window.isRestorable = false` in EditorWindowController prevents macOS 14+ from restoring previous documents
- **File watching revert loop**: `lastKnownFileModDate` set in `writeSafely` prevents autosave from triggering file reload; `revert` triggers its own `presentedItemDidChange` which is correctly filtered by mod date comparison
- **Blank tabs on tab switch**: `windowDidBecomeMain` in EditorWindowController triggers `rehydrate()` + `markActive()` — `viewDidAppear` doesn't fire on NSWindow tab switches
- **Links blocked**: Added `decidePolicyForNavigationAction` to WKNavigationDelegate — `.linkActivated` opens external URLs in browser, fragment-only URLs scroll via `scrollToAnchor`
- **Images blocked by file:// origin**: Switched from `loadFileURL` to `loadHTMLString` with `http://localhost/` baseURL so HTTPS requests aren't blocked
- **Mermaid DOM mismatch**: Old MutationObserver approach used selectors that didn't match Crepe's CodeMirror code block DOM. Replaced with Crepe's `renderPreview` API in `featureConfigs[CodeMirror]`
- **WKWebView copy button feedback**: Crepe's `onCopy` callback depends on `navigator.clipboard.writeText()` promise resolving — silently fails in WKWebView. Replaced with document-level click handler that fires feedback on any `.copy-button` click, independent of clipboard API
- **Code block scrollbar overlap**: macOS overlay scrollbars (~8px) cover text in single-line code blocks. Fix: `padding-bottom: 10px` + `overflow-y: hidden` on `.cm-scroller` — padding gives scrollbar space, overflow-y prevents the padding from creating a vertical scrollbar
- **Table cell text overflow**: Long text in table cells was bleeding into adjacent columns. ProseMirror uses `table-layout: fixed` (required for column resize), so added `overflow-wrap: break-word` on th/td to force wrapping within cell boundaries
