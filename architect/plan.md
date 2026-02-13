# Kern Implementation Plan

Build a native macOS WYSIWYG markdown editor: Swift + AppKit + WKWebView + Milkdown Crepe.

---

## Phase 1: CoreEditor (PoC Gate 1)

Build standalone Milkdown Crepe HTML file. Test in Safari.

### Files to create

```
CoreEditor/
├── package.json
├── tsconfig.json
├── vite.config.mts
├── index.html
└── src/
    ├── main.ts
    ├── bridge.ts
    ├── mermaid.ts
    └── themes/
        └── kern.css
```

### Steps

1. Create `CoreEditor/package.json` — exact pins: `@milkdown/crepe@7.18.0`, `@milkdown/utils@7.18.0`, `mermaid@^11`. Dev: `vite@^6`, `vite-plugin-singlefile@^2`, `typescript@^5`. Type `"module"`, private.
2. Create `tsconfig.json` — ES2022, ESNext, strict, bundler moduleResolution, `skipLibCheck: true`
3. Create `vite.config.mts` — `viteSingleFile({ removeViteModuleLoader: true })`, target `safari17`
4. Create `index.html` — `<div id="editor">`, module script tag (Vite dev), `overflow: hidden` on body, `overflow-y: auto` on `#editor`
5. `npm install` → inspect `node_modules/@milkdown/crepe/lib/theme/` to determine actual CSS export paths. Try standard imports first: `@milkdown/crepe/theme/common/style.css` + `@milkdown/crepe/theme/crepe/style.css`. If imports fail, fall back to defining all theme variables in kern.css
6. Create `src/main.ts` — Crepe init, bridge setup, mermaid setup, SAMPLE_MARKDOWN for dev mode, error reporting to Swift. **Wrap in `async function init()` (no top-level await)**
7. Create `src/bridge.ts` — `window.kern.*` API. **Use 2-param `markdownUpdated` callback**: `(ctx, markdown)` (Crepe `on()` passes 2 args, not 3). Add manual dedup via closure variable
8. Create `src/mermaid.ts` — dynamic `import('mermaid')` on first mermaid block detected (lazy load). DOM observer + `mermaid.render()`. Wrap in try/catch for invalid syntax (show error inline)
9. Create `src/themes/kern.css` — macOS system fonts (SF Pro Text/Display/Mono), Notion-like spacing, light/dark color variables via `[data-theme]` selectors + `@media (prefers-color-scheme: dark)`, responsive at 640px
10. `npm run build` → verify `dist/index.html` works in Safari
11. **Verify actual scroll container**: inspect DOM to find which element scrolls (`.milkdown`, `.editor`, `#editor`, or `document.documentElement`). Update bridge scroll methods accordingly
12. **Test `replaceAll(md)` vs `replaceAll(md, true)`** (flush param): determine which one cleanly resets editor state for tab switching

### API corrections (from challenge review)

- **`markdownUpdated` uses 2 params with Crepe `on()`**: `listener.markdownUpdated((ctx, markdown) => ...)`. The 3-param version `(ctx, markdown, prevMarkdown)` is for the low-level listener plugin only. Using 3 params with Crepe `on()` would leave `prevMarkdown` as `undefined`
- **CSS imports**: Try the standard documented paths first. The claimed "7.18.0 CSS export bug" is unverified — it may be wrong. If standard imports work, use them. If not, define color variables manually in kern.css
- **No top-level await**: The vite-plugin-singlefile inlined output loses module semantics. Wrap in `async function init() { ... }; init()`
- **Mermaid via dynamic import**: Use `const mermaid = await import('mermaid')` to avoid bundling ~1MB eagerly. Note: vite-plugin-singlefile may inline it anyway — test this. If it does inline, accept the ~1MB cost (spec allows it)

### Sample markdown

Must exercise ALL features: H1-H6, bold/italic/strikethrough/inline code, bullet/ordered/task/mixed lists, code blocks (JS/Python/TypeScript), table, inline LaTeX `$E=mc^2$`, block LaTeX `$$`, image URL, blockquote, links, mermaid flowchart, Korean text paragraph

### Korean IME test procedure

1. Focus editor, type "한글 테스트" — verify all syllables compose correctly
2. Move cursor to middle of a word, type more Korean
3. After `setMarkdown()` call (via console), immediately type Korean
4. Test composition at the very start of an empty document
5. Test in both Safari (Phase 1) and WKWebView (Phase 2)

### Gate 1 validation

Open `dist/index.html` in Safari. Verify all 17 criteria from `architect/prompt.md` PoC 1 checklist. **Stop and fix any failure before Phase 2.**

---

## Phase 2: Minimal Swift Shell (PoC Gate 2)

Build bare macOS app with WKWebView loading the HTML. Verify bidirectional bridge.

### Prerequisites

- Install XcodeGen: `brew install xcodegen`
- Fallback if XcodeGen fails: create `.xcodeproj` manually or use `swift package init --type executable` as scaffold

### Files to create

```
project.yml                          # XcodeGen config
KernApp/
├── Sources/
│   ├── App/
│   │   └── AppDelegate.swift        # @main, warmUp pool, temp test window
│   ├── Editor/
│   │   ├── EditorViewController.swift   # WKWebView host, NativeBridgeDelegate
│   │   └── EditorReusePool.swift        # Simple pool of 3, shared WKProcessPool
│   └── Bridge/
│       ├── WebBridge.swift              # Swift→JS via callAsyncJavaScript
│       └── NativeBridge.swift           # JS→Swift via WKScriptMessageHandler
├── Resources/
│   └── Assets.xcassets/                 # Placeholder app icon
├── Info.plist
└── Kern.entitlements
```

### Key implementation patterns

- **`@MainActor`**: AppDelegate, EditorViewController, EditorReusePool, WebBridge — all `@MainActor`. **NOT EditorDocument** (see Phase 3)
- **`callAsyncJavaScript` only**: No `evaluateJavaScript` (WebKit memory leak). Pass data via `arguments` dict, use `contentWorld: .page`
- **`NativeBridge`**: `nonisolated` callback. Extract String values from `message.body` immediately (before isolation boundary), then hop to `@MainActor` via Task
- **No private APIs**: `webView.isInspectable = true` (public on macOS 14+)
- **HTML loading**: `Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist")`, load via `loadHTMLString(_:baseURL: URL(string: "http://localhost/")!)`
- **Shared WKProcessPool**: `static let sharedProcessPool = WKProcessPool()`
- **Programmatic menu bar**: Build `NSApp.mainMenu` in code (AppDelegate). **No Main.storyboard** — avoids fragile hand-written XML. Set `NSMainNibFile` to empty or omit `NSMainStoryboardFile` from Info.plist
- **Ready-state guard**: All `WebBridge` calls guarded behind `EditorViewController.hasFinishedLoading`. Before ready, fall back to cached `stringValue`
- **Temp test window**: AppDelegate creates a programmatic NSWindow for Phase 2 testing (removed in Phase 3)

### project.yml key sections

```yaml
targets:
  Kern:
    type: application
    platform: macOS
    sources:
      - path: KernApp/Sources
    resources:
      - path: CoreEditor/dist
        type: folder           # folder reference, not group
      - path: KernApp/Resources/Assets.xcassets
    settings:
      base:
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        SWIFT_STRICT_CONCURRENCY: complete
        INFOPLIST_FILE: KernApp/Info.plist
        CODE_SIGN_ENTITLEMENTS: KernApp/Kern.entitlements
        CODE_SIGN_IDENTITY: "-"
```

### Steps

1. Create `project.yml` with complete config
2. Create all Swift source files
3. Create `Info.plist` (minimal — no `NSMainStoryboardFile`, no doc types yet)
4. Create `Kern.entitlements` (sandbox + user-selected files)
5. Create placeholder `Assets.xcassets`
6. `xcodegen generate && xcodebuild -project Kern.xcodeproj -scheme Kern -configuration Debug build`
7. Run app, verify editor appears, type text, check Xcode console for bridge messages

### Gate 2 validation

App launches with WYSIWYG editor. Type text. `getMarkdown()` returns string. Content changes trigger Swift callback. Korean input works. Dark/light follows system. 5000-line file works.

---

## Phase 3: NSDocument Integration

`open -a Kern file.md` starts working.

### Files to create/modify

- **Create** `EditorDocument.swift` — NSDocument subclass
- **Create** `EditorWindowController.swift` — programmatic NSWindow, `tabbingMode = .preferred`, `minSize: 640x480`, `isReleasedWhenClosed = false`
- **Modify** `EditorViewController.swift` — add `document` property, load content on `editorReady`, update `document.stringValue` on `contentChanged`
- **Modify** `AppDelegate.swift` — remove temp test window, keep programmatic menu
- **Modify** `Info.plist` — add `CFBundleDocumentTypes` + `UTImportedTypeDeclarations`

### EditorDocument concurrency model (critical)

**Do NOT use `@MainActor` at the class level.** NSDocument methods like `read(from:ofType:)` are called on background threads when `canConcurrentlyReadDocuments()` returns `true`. `presentedItemDidChange()` is called on the file presenter queue. Class-level `@MainActor` would break both.

Instead, use selective isolation:
- `stringValue` property: access from any thread (protected by NSDocument's internal serialization)
- `read(from:ofType:)` and `data(ofType:)`: no actor annotation (background-safe)
- `makeWindowControllers()`: `@MainActor` (creates UI)
- `autosave(withImplicitCancellability:)`: `@MainActor` (calls bridge)
- Bridge interactions: always wrap in `Task { @MainActor in ... }`

### Async save with crash resilience

```swift
override func autosave(withImplicitCancellability:) async throws {
    if let vc = hostViewController, vc.hasFinishedLoading {
        do {
            stringValue = try await vc.bridge.getMarkdown()
        } catch {
            // Bridge failed (crash, not ready, etc.) — save with existing stringValue
            // stringValue is kept up-to-date by contentChanged callback, so it's recent
        }
    }
    try await super.autosave(withImplicitCancellability:)
}
```

### Info.plist additions for Phase 3

`CFBundleDocumentTypes`: net.daringfireball.markdown, extensions md/markdown/mdown/mkd, role Editor. **NOT public.plain-text.**

`UTImportedTypeDeclarations`: Declare `net.daringfireball.markdown` UTI conforming to `public.text`, with tag `md` in `public.filename-extension`. Required for File > Open panel filtering on macOS 14+.

---

## Phase 4: File Watching + Auto-Reload

External file changes auto-reload with scroll preservation.

### Modify `EditorDocument.swift`

- Override `presentedItemDidChange()` — called on presenter queue (NOT main thread)
- Dispatch async to main queue, 300ms debounce via `DispatchWorkItem`
- Compare `fileModificationDate` to skip self-triggered reloads
- **After every successful save/autosave, set `fileModificationDate = .now`** to prevent the autosave→presentedItemDidChange→revert loop
- Call `revert(toContentsOf:ofType:)` only when file is genuinely newer

### Autosave ↔ file watching loop prevention

The cycle: type → contentChanged → stringValue updated → autosave writes to disk → presentedItemDidChange fires → revert → setMarkdown → contentChanged → repeat.

Break it with:
1. Update `fileModificationDate = .now` immediately after successful save
2. In `presentedItemDidChange`, skip if file mod date ≤ our tracked date
3. Optional: compare content hash before reverting (skip if unchanged)

### Modify `EditorViewController.swift`

- `handleFileReloaded()` — save scroll position, setMarkdown with new content, restore scroll position
- `showReloadToast()` — NSTextField overlay, fades out after 3 seconds
- **Note**: `replaceAll()` resets cursor position and undo history. This is the accepted trade-off per prompt decision "always revert + toast"

---

## Phase 5: Tab Virtualization

Upgrade pool from simple 3-instance to LRU-evicting 5-live + unlimited virtualized.

### Modify `EditorReusePool.swift` (significant rewrite)

- Track `TabState` per document: `.live(EditorViewController)` or `.virtualized(markdown, scrollPosition)`
- Max 5 live WKWebViews at any time
- **`dequeue()` stays synchronous**: virtualization uses `document.stringValue` + cached scroll position (not async `getMarkdown()` call). The `contentChanged` callback keeps `stringValue` fresh, so it's accurate enough
- Rehydration: `setMarkdown(savedContent)` + `setScrollPosition(savedOffset)` on recycled WKWebView. Use `replaceAll(md, true)` (flush=true) for clean state transition between documents

### Crash recovery

- `webViewWebContentProcessDidTerminate` → set `hasFinishedLoading = false` → reload HTML via `loadHTMLString()` → on `editorReady`, set `hasFinishedLoading = true` → restore from `document.stringValue`
- Guard against double `editorReady`: use a generation counter, ignore stale callbacks

---

## Phase 6: Themes + Menus + Polish

### Create `AppearanceManager.swift`

Observe `NSApp.effectiveAppearance`, call `bridge.setTheme()` on all live editors.

### Update programmatic menu bar

Add Format submenu (Bold ⌘B, Italic ⌘I, Code ⌘E), View submenu (Toggle Dark Mode). Wire Undo (⌘Z) and Redo (⇧⌘Z) to `bridge.execCommand("undo"/"redo")` — NOT NSDocument UndoManager. Override `undo:` and `redo:` in EditorViewController's responder chain.

### Implement `execCommand()` in bridge.ts

Map command names to Milkdown/ProseMirror commands:
```
undo → undoCommand.key (from @milkdown/kit/plugin/history or @milkdown/plugin-history)
redo → redoCommand.key
bold → toggleStrongCommand.key (from @milkdown/kit/preset/commonmark)
italic → toggleEmphasisCommand.key
code → toggleInlineCodeCommand.key
```
Use `crepe.editor.action(callCommand(key))`.

### Other polish

- Placeholder "K" app icon
- Responsive CSS tweaks at 640px
- Menu item validation (disable format/undo items when no editor active)
- WKNavigationDelegate failure handlers for HTML load errors

---

## Verification Plan

After each phase, run the corresponding gate/test. After Phase 6, full checklist:

1. `open -a Kern /path/to/file.md` → WYSIWYG mode
2. Edit → close → reopen → changes preserved (autosave)
3. No "save changes?" dialog on close
4. External file modification → editor updates within ~500ms, toast
5. Scroll position preserved after reload
6. System dark mode toggle → theme switches
7. Korean text input correct (full test procedure from Phase 1)
8. 5+ files from terminal → all tabs in one window, last focused
9. ⌘Z/⇧⌘Z undo/redo in editor
10. ⌘B/I/E toggle bold/italic/code
11. File > New → untitled with placeholder
12. 640px width → no horizontal scrollbar
13. LaTeX, code blocks, tables, checklists, mermaid all render
14. Memory < 500MB with 5 live + 15 virtualized tabs
15. Re-opening already-open file brings existing tab to front (NSDocumentController handles this)

---

## Key Risk Mitigations

| Risk | Mitigation |
|------|------------|
| CSS import paths broken in 7.18.0 | Try standard imports first. If broken, define theme variables in kern.css |
| Mermaid DOM selectors don't match CodeMirror structure | Inspect DOM at dev time. Fallback: parse markdown string for mermaid blocks |
| Swift 6 strict concurrency errors | `@MainActor` on VC/Pool/Bridge. EditorDocument uses selective isolation (NOT class-level @MainActor) |
| `callAsyncJavaScript` throws when editor not ready | Guard all bridge calls behind `hasFinishedLoading`, fall back to `stringValue` |
| Autosave ↔ file watching infinite loop | Update `fileModificationDate = .now` after every save. Skip revert if date ≤ tracked |
| WKWebView blank screen | Verify baseURL set, singlefile inlined everything, no module loader |
| XcodeGen fails | Fallback: manually create .xcodeproj or use swift package scaffold |
| `index.html` not found in bundle | XcodeGen `resources` with `type: folder` for `CoreEditor/dist` |
| WebContent crash during save | Autosave catches bridge error, falls back to `stringValue` |
| `replaceAll` leaves stale state on tab switch | Test with `flush: true` in Phase 1. Use flush for tab switches |
| Mermaid ~1MB bundle size hurts load time | Dynamic import. If singlefile forces inline, accept cost (spec allows) |
| Storyboard XML errors | Skip storyboard entirely. Build menu bar programmatically in AppDelegate |
