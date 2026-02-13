# Forging Plans Transcript
## Project Context: New project — Kern, a native macOS WYSIWYG markdown editor
## Raw Input

Building a macOS-native markdown WYSIWYG editor called "Kern." Extensive prior research exists at `/Users/aaaaa/marktext-claude/` including:
- `research.md` — Full requirements, competitive analysis, architecture decisions
- `native-wysiwyg-editor-analysis.md` — Feasibility study on pure-native rendering (concluded infeasible for small team)
- `implementation-plan.md` — Previous 6-phase implementation plan (context only)
- `MarkEdit/` — Reference implementation (Swift + WKWebView + CodeMirror)

**Core vision:** The definitive markdown WYSIWYG editor for macOS. Native (no Electron), fast, frictionless. Target workflow: AI agent outputs file paths → Cmd-click in Ghostty → file opens instantly → view/edit with Notion-quality rendering → auto-saves → auto-reloads when agents modify → close without dialogs.

**Architecture decision (made):** Swift + AppKit + WKWebView + Milkdown Crepe. WKWebView is Apple's native WebKit (not bundled Chromium). Milkdown chosen for direct MD↔AST↔ProseMirror pipeline, MIT license, 1.8MB bundle, mixed bullet+checkbox support.

**Key decisions already made:**
- App name: Kern
- macOS 14+ (Sonoma)
- No cross-platform
- Swift + WKWebView (not Tauri, not pure native)
- Milkdown Crepe editor engine (not Tiptap, not BlockNote)
- Checkbox/bullet styling separate from themes

---

## Questionnaire

### Category 1: Core Vision

**Q: Audience — personal tool, community product, or personal→product?**
A: Personal → product. Build for my workflow first, architect so it can become a real product without major rewrites.

**Q: Success milestones?**
A: (1) Replaces MarkText for daily use, (2) Notion-quality UX, (3) Mac App Store ship eventually.

**Q: Single most important thing?**
A: Rendering quality. The rendered markdown must look as good as Notion.

### Category 2: Requirements & Constraints

**Q: Explicit exclusions (must NOT do)?**
A: All four confirmed:
- No vault/workspace mode (individual files only)
- No cloud sync
- No plugin system
- No split/preview pane (WYSIWYG only, always)

**Q: V1 scope — which nice-to-haves are must-haves?**
A: Must-haves only. Slash commands included since Crepe provides them by default (zero extra work).

**Q: Korean/CJK IME support for v1?**
A: Critical — types in Korean daily. Must work correctly in v1.

### Category 3: Prior Art & Context

**Q: MarkEdit familiarity?**
A: Just cloned it for reference. Haven't built or run it.

**Q: Swift/AppKit experience?**
A: New to Swift. This is first Swift project. AI agent will do most of the coding.

**Q: Milkdown/ProseMirror experience?**
A: Neither. First time with both. Research only.

### Category 4: Architecture & Structure

**Q: Build system preference?**
A: Whatever works and follows best practices. AI agent reliability is priority.

**Q: Swift ↔ JS bridge approach?**
A: Simple/manual. 4-6 hand-written bridge methods. Start simple, migrate to typed code-gen if bridge grows beyond ~10 methods.

**Q: Web build strategy?**
A: Commit built HTML to repo. Run npm build separately. Test JS in Safari independently. Simple Xcode builds.

### Category 5: Edge Cases & Error Handling

**Q: AI agent writes while user is editing?**
A: Warn if user has edits. Silent reload if no unsaved changes. Non-blocking notification if conflicts.

**Q: Typical file sizes?**
A: Medium (1-5k lines). Research docs, specs, meeting notes.

**Q: Invalid/broken files?**
A: Show error message in editor area. Don't try to render broken content.

**Q: Debounce delay for rapid file changes?**
A: 300ms. Fast enough to feel responsive, long enough to batch rapid AI writes.

**Q: Cmd-click 10 files from terminal?**
A: All in tabs, one window. Focus the last one opened.

### Category 6: Scale & Performance

**Q: Target file open speed?**
A: <200ms (Cmd-click to rendered content visible). Ambitious — requires aggressive pre-warming.

**Q: How many files open simultaneously?**
A: 20+. Rarely closes files. Memory efficiency matters.

*Note: 20+ files at <200ms open with WKWebView reuse pool of 3 creates a tension. Each tab with its own WKWebView at 20+ files means significant memory. Need to explore tab virtualization or WKWebView recycling.*

### Category 7: Security & Privacy
Skipped — Local-only file editor with no network, no auth, no sensitive data. Standard app sandbox only.

### Category 8: Integration & Dependencies

**Q: Milkdown risk tolerance?**
A: Fork and fix. Willing to maintain a fork with patches if Milkdown has blocking bugs.

**Q: Mermaid diagrams in v1?**
A: Yes, but lazy-load. Include in v1 but only load Mermaid JS when a mermaid code block is detected.

**Q: Node.js version?**
A: Will install whatever's needed.

### Category 9: Testing & Verification

**Q: Testing strategy?**
A: Manual testing + key unit tests for the bridge layer and file-watching logic.

**Q: Definition of done for v1?**
A: MarkText replacement — can set Kern as default .md handler and never open MarkText again.

### Category 10: Deployment & Operations

**Q: Distribution for v1?**
A: Direct build from Xcode. No Apple Developer account for v1. Run locally only. Distribution (Homebrew, App Store) comes later with Developer account.

### Category 11: Trade-offs & Priorities

**Q: Top 2 priorities for v1?**
A: (1) Reliability — never crashes, never loses data, auto-save always works. (2) Rendering quality — the visual experience.

**Q: Quality bar?**
A: PoC-gated approach. Full comprehensive prompt with mandatory PoC validation checkpoints before proceeding to later phases. Each PoC must pass before the full build continues.

### Category 12: Scope & Boundaries

**Q: Out of scope confirmations?**
A: All confirmed: No vault mode, no cloud sync, no plugins, no split pane, no vim keys, no custom themes beyond light/dark, no folder opening.

**Q: Extensibility design?**
A: Theme system only. Design CSS architecture so custom themes can be added later. Don't over-engineer the rest.

---

## Prior-Art Research

### Existing Solutions
| Solution | URL | Relevance | Quality | Notes |
|----------|-----|-----------|---------|-------|
| MarkEdit | github.com/MarkEdit-app/MarkEdit | High | Accepted | Swift+WKWebView+CodeMirror. Same architecture minus WYSIWYG. Reference for pool, bridge, NSDocument. |
| Milkdown Crepe | milkdown.dev | High | Accepted | Editor engine. API confirmed via docs. |
| vite-plugin-singlefile | github.com/richardtallent/vite-plugin-singlefile | High | Accepted | 86k weekly downloads. Solves WKWebView type="module" issue. |
| Typora | typora.io | Medium | Accepted | Gold standard WYSIWYG UX reference. Electron-based, closed source. |

### Key Findings

#### 1. Milkdown Crepe API (confirmed via official docs)
- **Init:** `new Crepe({root, defaultValue, features, featureConfigs})`
- **Mount:** `await crepe.create()`
- **Get content:** `crepe.getMarkdown()`
- **Set content:** `crepe.editor.action(replaceAll(markdown))` — uses `replaceAll` from `@milkdown/utils` on the inner Editor instance
- **Change listener:** `crepe.on(l => l.markdownUpdated((ctx, md, prevMd) => {...}))`
- **Other events:** `.focus()`, `.blur()`, `.mounted()`
- **CSS imports required:** `@milkdown/crepe/theme/common/style.css` and `@milkdown/crepe/theme/crepe/style.css`
- **Features enum:** `CrepeFeature.CodeMirror`, `.ListItem`, `.LinkTooltip`, `.ImageBlock`, `.BlockEdit`, `.Toolbar`, `.Table`, `.Latex`
- **Crepe does NOT have a direct `setMarkdown()` method** — must go through `crepe.editor.action(replaceAll(md))`

#### 2. WKWebView Memory with 20+ Tabs (cross-referenced: Apple Forums, Embrace blog, Capacitor issues)
- Each WKWebView runs out-of-process; memory accounted separately from app
- Per-WKWebView overhead: ~30-80MB in the WebContent process
- 20+ tabs = 600-1600MB of WebKit process memory — significant on 8GB Macs
- **Shared WKProcessPool is critical** — reduces per-process overhead substantially
- Must handle `webViewWebContentProcessDidTerminate` for graceful recovery when WebKit kills content process
- Known memory leak with `evaluateJavaScript` completion handlers (WebKit bug 215729)
- **Key mitigation: Tab virtualization** — only visible/active tabs keep WKWebViews loaded; background tabs hold serialized markdown
- MarkEdit's pool of 3 is designed for sequential opens, not 20+ simultaneous

#### 3. MarkEdit Reference Implementation (source code analysis)
- **Pool:** 2 warm-up, 3 keep-alive max (`EditorReusePool.swift`)
- **HTML loading:** `loadHTMLString()` with `baseURL: http://localhost/`
- **WKProcessPool:** Not explicitly shared (uses WebKit defaults — each config gets default pool)
- **Autosave:** Async override that fetches text from WKWebView before save. `autosavesInPlace = true` as class method.
- **File watching:** `presentedItemDidChange()` with modification date comparison. Dispatches to main queue.
- **Bridge:** JSON message-passing. Swift→JS via `evaluateJavaScript`. JS→Swift via `WKScriptMessageHandlerWithReply`. All `@MainActor` enforced.
- **Memory:** Weak references to prevent retain cycles. `isReleasedWhenClosed = true` on windows.
- **Bridge structure:** Modular — `WebModuleBridge` groups sub-bridges (core, history, selection, format, search, etc.)

#### 4. NSDocument File Watching (Apple docs, developer forums)
- NSDocument already conforms to `NSFilePresenter` — monitors its file automatically
- `presentedItemDidChange()` fires on both content and attribute changes — must check modification dates
- **Deadlock risk:** Never do file coordination inside the presenter queue. Always dispatch async.
- `autosavesInPlace` is a class method, not instance method — complicates per-document control (but fine for Kern since all docs are the same type)
- Swift initializer constraint: `init(contentsOf:ofType:)` is marked convenience in Swift, cannot be overridden directly

#### 5. Korean IME in WKWebView (Apple forums, Mozilla Bugzilla, Qt bug reports)
- WKWebView uses WebKit's native text input via `contenteditable` — generally handles Korean composition well
- **Known macOS-level bugs:** First Hangul character loss after certain events, syllable dropping (reported in Mozilla Bugzilla 1233998, Qt QTBUG-136128)
- These bugs are at the OS/IME level, not the app level — "we can do nothing here" (Mozilla)
- ProseMirror handles `compositionstart`/`compositionupdate`/`compositionend` events properly
- **Risk level: Low for Kern.** WKWebView + contenteditable + ProseMirror is the standard web editor stack. Korean works in Notion (also ProseMirror-based). Test thoroughly but don't expect app-level fixes to be needed.

#### 6. vite-plugin-singlefile for WKWebView (npm docs, GitHub README, Vite discussions)
- **Key option:** `removeViteModuleLoader: true` — removes Vite's module loader since everything is inlined
- **Solves WKWebView `type="module"` issue** — WKWebView doesn't support `type="module"` script tags; inlining bypasses this
- **Single entry point only** — fine for Kern's use case
- **`deleteInlinedFiles: true`** (default) — removes source files after inlining
- `useRecommendedBuildConfig: true` (default) — auto-adjusts Vite config for single-file output

### Unverified Claims
- Milkdown Crepe's `replaceAll` with `flush: true` parameter recreates editor state — only one source (Context7 docs). Should be tested in PoC.
- MarkEdit uses WebKit default WKProcessPool rather than an explicit shared pool — verified from source but unclear if this is intentional or an oversight.

### Conflicts
- **Pool size vs. 20+ tabs:** MarkEdit keeps max 3 WKWebViews, but user needs 20+. No existing reference implementation handles 20+ WKWebView tabs. The standard advice (Apple Forums) is to virtualize background tabs.

### Sources
- [Milkdown Crepe API Docs](https://milkdown.dev) — Quality: High — Accessed: 2026-02-01
- [Milkdown Utils (replaceAll)](https://context7.com/milkdown/milkdown) — Quality: High — Accessed: 2026-02-01
- [MarkEdit Source Code](https://github.com/MarkEdit-app/MarkEdit) — Quality: High — Accessed: 2026-02-01
- [Apple: WKWebView Memory Budget](https://developer.apple.com/forums/thread/133449) — Quality: High — Accessed: 2026-02-01
- [WKWebView Memory Leaks (Embrace)](https://embrace.io/blog/wkwebview-memory-leaks/) — Quality: High — Accessed: 2026-02-01
- [Capacitor WKProcessPool Issue](https://github.com/ionic-team/capacitor/issues/6887) — Quality: Medium — Accessed: 2026-02-01
- [Apple: NSDocument autosavesInPlace](https://developer.apple.com/documentation/appkit/nsdocument/1515106-autosavesinplace) — Quality: High — Accessed: 2026-02-01
- [Apple: NSFilePresenter](https://developer.apple.com/documentation/foundation/nsfilepresenter) — Quality: High — Accessed: 2026-02-01
- [Mozilla Bugzilla: Hangul syllable loss](https://bugzilla.mozilla.org/show_bug.cgi?id=1233998) — Quality: High — Accessed: 2026-02-01
- [Qt Bug: macOS Korean IME first character](https://bugreports.qt.io/browse/QTBUG-136128) — Quality: Medium — Accessed: 2026-02-01
- [vite-plugin-singlefile README](https://github.com/richardtallent/vite-plugin-singlefile) — Quality: High — Accessed: 2026-02-01
- [Vite Discussion: WKWebView type="module"](https://github.com/vitejs/vite/discussions/14485) — Quality: Medium — Accessed: 2026-02-01
- [NSDocument autosave file types (Michael Tsai)](https://mjtsai.com/blog/2025/02/13/nsdocument-auto-saving-and-file-types/) — Quality: High — Accessed: 2026-02-01

---

## Gap Analysis

### Gap 1: 20+ Tabs Memory Strategy (Critical)
**Issue:** 20+ WKWebViews = 600-1600MB WebKit process memory. No reference implementation handles this.
**Resolution:** Virtualize background tabs. Keep 3-5 live WKWebViews (active + recent). Background tabs hold markdown strings in Swift memory (~KB each). Switching to cold tab loads markdown into recycled WKWebView (~300ms).

### Gap 2: Milkdown `setMarkdown` API
**Issue:** Crepe has no direct `setMarkdown()`. Must use `crepe.editor.action(replaceAll(md))`.
**Resolution:** Bridge JS wraps this: `window.kern.setMarkdown(md)` calls `replaceAll` internally. No user decision needed.

### Gap 3: Shared WKProcessPool
**Issue:** MarkEdit doesn't explicitly share. Apple recommends sharing for multi-tab.
**Resolution:** Explicitly share one WKProcessPool across all WKWebViewConfigurations. One line of code, saves memory.

### Gap 4: Minimum Window Size
**Issue:** Responsive layout at narrow widths?
**Resolution:** Support quarter-screen (~640px). May need 2-3 CSS tweaks for toolbar at narrow widths.

### Gap 5: Implementation Notes (no user decision needed)
- Milkdown dark theme: Import both CSS files, toggle via `data-theme` attribute
- WKWebView `evaluateJavaScript` leak: Use `callAsyncJavaScript` on macOS 14+ where possible
- NSDocument `autosavesInPlace` class method: Not an issue (single document type)
- `presentedItemDidChange` deadlock: Always dispatch async to main queue
- Mermaid lazy loading: Dynamic import on first `mermaid` code block detection

---

## Challenge Results

### Self-Critique (10 issues found)
Key issues: dead code in bridge snippet, missing baseURL, no performance target in prompt, Crepe init error handling, memory target unrealistic, missing debounce implementation, undefined lifecycle states, vague build system guidance.

### Sub-Agent Review (27 issues found)
Critical new findings not caught by self-critique:
1. Priority ordering contradiction (transcript vs prompt) — resolved: co-equal
2. No cursor/scroll preservation on reload — added bridge methods
3. Undo/Redo must go through JS bridge, not NSDocument UndoManager — fixed
4. public.plain-text UTI would make Kern open ALL text files — removed
5. No baseURL for loadHTMLString — added http://localhost/
6. allowFileAccessFromFileURLs is private API — removed
7. No error handling for Crepe initialization failure — added loadFailed event
8. Missing entitlements specification — added
9. Storyboard confusion (menu vs window) — clarified
10. New document behavior undefined — added
11. Window restoration noted as out of scope for v1

### User Decisions from Challenge
- **Priorities:** Rendering quality and reliability are co-equal #1
- **Cursor on reload:** Preserve scroll position
- **Conflict handling:** Always revert + show brief toast ("File reloaded from disk")

### Fixes Applied to Prompt v2
All 20 identified fixes applied. See prompt.md for final version.

### Post-Challenge Iteration
- User confirmed macOS 14 (Sonoma) target — no longer arbitrary, justified as current-1 covering ~95% of Mac users
- Mermaid changed from CDN lazy-load to bundled npm dependency (no internet)
- Removed `network.client` entitlement — app has zero internet requirements
- Added mermaid to PoC 1 validation criteria
- User approved final prompt

---

## Final Artifacts (Original Project Forge)
- `architect/prompt.md` — Perfected prompt (final version, v2 with all challenge fixes + mermaid/network changes)
- `architect/transcript.md` — Full Q&A log, research, challenge results
- `architect/STATE.md` — Resumable state file, key decisions summary

---

## Cold Start Optimization Forge (Feb 2026)

### Raw Input
Implement cold start optimizations based on verified research in architect/cold-start-optimization.md. All 11 optimization items + background daemon behavior + login item.

### Questionnaire

**Q: Scope — which optimization items?**
A: Everything (items 1-11). Full optimization suite.

**Q: Phasing?**
A: Two prompts. Phase A: All Swift + JS changes (items 1-5, 8-11, daemon, login item). Phase B: Build system overhaul (items 6-7, code splitting).

**Q: `_drawsBackground` private SPI — use it?**
A: Yes. Use MarkEdit's WKWebViewConfiguration subclass pattern.

**Q: KaTeX handling in CrepeBuilder migration?**
A: Schema stub + lazy-load rendering. Register math node types at creation (tiny), dynamically import KaTeX library (~300KB JS + 1.2MB fonts) only when a math node is first rendered. Similar to mermaid pattern.

**Q: Background daemon — how should Cmd+Q work?**
A: Cmd+Q closes all windows, app stays running in background (hidden). Dock icon disappears when no windows open. Next `open -a Kern file.md` is instant. Right-click Dock > Quit for real quit.

**Q: Daemon behavior opt-in or default?**
A: Opt-in via setting. Since settings page doesn't exist yet, use a menu item or UserDefaults key initially.

**Q: Verification approach?**
A: OSSignposter + NSLog + before/after comparison. Capture baseline before optimization, compare after each phase.

### Gap Analysis

#### Gap 1: Pre-load Handshake Problem (Critical)
**Issue:** If HTML is pre-loaded into a warm-up WKWebView during `warmUp()`, JS will call `postMessage({type: "editorReady"})` but the `nativeBridge` message handler isn't registered yet (only happens in `attachWebView()`). The message is lost. When the ViewController later dequeues and attaches, `editorReady` never fires.
**Solution:** After `attachWebView()`, call `callAsyncJavaScript("return window.kern?.isReady?.() ?? false")`. If true (HTML pre-loaded and Crepe initialized), skip `loadEditorHTML()` and call `editorReady()` directly. If false, fall back to current behavior. `window.kern.isReady()` already exists in bridge.ts:159, always returns true after Crepe init.

#### Gap 2: enqueue() Clears Pre-loaded State
**Issue:** `enqueue()` calls `removeAllScriptMessageHandlers()` and `stopLoading()`. If a pre-loaded WKWebView gets recycled before use, the pre-loaded state is lost.
**Resolution:** Acceptable — the `isReady()` check handles this gracefully. If the webview was recycled, `isReady()` returns false, and normal load path runs.

#### Gap 3: KaTeX Lazy-Loading Complexity
**Issue:** User wants "schema stub + lazy render" but the Milkdown LaTeX feature has a static `import katex from 'katex'` (line 2) and uses KaTeX directly in `toDOM` (synchronous, line 123). Can't lazy-load without writing a custom NodeView.
**Revised recommendation:** Phase A: Import LaTeX feature as-is (keep KaTeX bundled). CrepeBuilder still saves by dropping Toolbar + Placeholder. Phase B: Code splitting naturally moves KaTeX to a lazy chunk. Net result is the same — KaTeX lazy-loads — just happens via build system, not custom code.

#### Gap 4: Hide on Cmd+Q Implementation
**Issue:** macOS doesn't distinguish Cmd+Q from Dock > Quit at the `applicationShouldTerminate` level. Both go through the same path.
**Solution:** Override the Quit menu item's action. When "keep running" is enabled, Cmd+Q calls `NSApp.hide(nil)` + close all windows instead of `NSApp.terminate(nil)`. Dock > Quit sends `terminate:` which goes through normal quit path. Store setting in UserDefaults.

#### Gap 5: Login Item API
**Issue:** SMAppService requires macOS 13+.
**Resolution:** Kern targets macOS 14+ — no compatibility concern.

#### Gap 6: Settings Storage Without Settings Page
**Issue:** Settings page doesn't exist yet. Where does "keep running in background" toggle live?
**Resolution:** Add a "Keep Running in Background" menu item to the Kern menu (with checkmark toggle). Stores in UserDefaults. Settings page can consolidate this later.

#### Gap 7: OSSignposter Import
**Issue:** Needs `import os` for OSSignposter. Available macOS 12+.
**Resolution:** No issue — Kern targets macOS 14+.

#### Gap 8: KaTeX in CrepeBuilder (Updated)
**Issue:** User wanted "schema stub + lazy render" but static `import katex` in LaTeX feature makes lazy-loading require custom NodeView (~50-80 lines).
**Resolution:** User approved: keep LaTeX bundled in Phase A (drop Toolbar + Placeholder only). Phase B code splitting handles KaTeX lazy-loading automatically via Vite chunking.

### Prior-Art Research

Extensive prior art already documented in `architect/cold-start-optimization.md` (verified Feb 2026). Key references:
- MarkEdit source: warm-up delay, EditorChunkLoader, AX swizzle, `_drawsBackground`, spell checker pre-warm (all verified against source at /Users/aaaaa/marktext-claude/MarkEdit/)
- WebKit internals: WKProcessPool behavior (each WKWebView gets own process since macOS 10.15), JSC bytecode caching (external scripts cached, inline not), `_drawsBackground` status (private SPI, MarkEdit ships with it)
- Milkdown: CrepeBuilder (4.2KB, selective imports) vs Crepe (103KB, all features static)
- Case studies: VSCode lazy loading, Tauri <200ms startup, DoorDash 60% reduction
- Measurement: OSSignposter > CFAbsoluteTimeGetCurrent (monotonic), performance.now() reduced precision in WKWebView

No additional research needed — the cold-start-optimization.md is comprehensive and verified.

### Challenge Results

#### Prompt A — Sub-Agent Review (23 issues found, all fixed)
- **Critical:** `_drawsBackground` was on WKWebViewConfiguration (wrong) — fixed to `webView.setValue(false, forKey: "drawsBackground")` on WKWebView instance
- **High:** Swift 6 concurrency — completion handler `callAsyncJavaScript` violates `@MainActor`. Fixed to async/await variant
- **High:** Pre-load content race — `editorReady()` fires before `stringValue` set. Fixed with `didSet` observer on `stringValue`
- **High:** Missing custom plugin migration — `crepe.editor.use()` and `crepe.editor.config()` calls must be preserved. Added explicit instructions
- **High:** Verification order — `npm run build` must come before `xcodebuild`. Reordered
- **Medium:** `requestIdleCallback` unavailable on Safari 17.0 (macOS 14.0). Changed to `setTimeout`
- **Medium:** Daemon quit — replaced menu action (breaks convention). Changed to `applicationShouldTerminate` returning `.terminateCancel`
- **Medium:** `DispatchQueue.main.async` in `@MainActor` context. Changed to `Task { @MainActor in }`
- **Medium:** `applicationShouldHandleReopen` missing for daemon re-activation. Added
- **Medium:** Login item error handling — `try?` swallows errors. Changed to `do/catch` with NSLog

#### Prompt B — Sub-Agent Review (20 issues found, all fixed)
- **Critical:** ES module support via custom scheme is unverified — made it a go/no-go gate (Step 1) before all other work
- **High:** `base: "/kern-editor/"` introduces unnecessary path stripping complexity. Changed to `base: "/"` (eliminates 5 related issues)
- **High:** `URLResponse` lacks status codes — changed to `HTTPURLResponse` for WebKit ES module CORS compatibility
- **High:** Path traversal check — `hasPrefix` without trailing `/` on distURL allows `dist-evil/` bypass. Fixed with `+ "/"`
- **Medium:** `vite.config.ts` → `vite.config.mts` throughout (file is already `.mts`)
- **Medium:** Missing `manualChunks` — mermaid splits into 100+ chunks without it. Added `manualChunks: { mermaid: ["mermaid"] }`
- **Medium:** Missing `@unchecked Sendable` — current code has it, prompt dropped it. Restored
- **Medium:** Missing `.mjs` MIME type — added to switch case
- **Medium:** Missing prerequisite verification gate — added checklist at top of prompt
- **Low:** `loadHTML()` removal instructions clarified
- **Low:** `import UniformTypeIdentifiers` added (needed for UTType fallback)
- **Low:** File count verification step added to Build and Test section

### Final Artifacts

- `architect/cold-start-prompt-A.md` — Phase A prompt (Swift + JS changes, items 1-5, 8-11, background daemon). All challenge fixes applied.
- `architect/cold-start-prompt-B.md` — Phase B prompt (build system overhaul, items 6-7, code splitting). All challenge fixes applied.
- `architect/transcript.md` — Full Q&A log, gap analysis, challenge results
- `architect/STATE.md` — Updated with cold start forge completion
