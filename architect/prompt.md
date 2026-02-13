# Kern — Native macOS WYSIWYG Markdown Editor

Build Kern: a native macOS WYSIWYG markdown editor using Swift + AppKit + WKWebView + Milkdown Crepe.

**Important:** Code snippets in this document are illustrative patterns, not copy-paste implementations. Write complete implementations with proper imports, error handling, and types. Use the snippets to understand intent and structure.

## What This Is

A macOS-native app that opens `.md` files and renders them with Notion-quality WYSIWYG editing. No visible markdown syntax while editing — headings render as headings, code blocks render with syntax highlighting, checkboxes are interactive, LaTeX renders as math.

**Target workflow:** AI agent outputs file paths → user Cmd-clicks path in Ghostty terminal → file opens instantly in Kern (<200ms target) → view/edit with rich rendering → auto-saves → auto-reloads when agents modify the file → close without dialogs.

**Architecture:** Swift + AppKit wraps WKWebView (Apple's system WebKit engine). Milkdown Crepe (a ProseMirror-based WYSIWYG markdown editor) runs inside the WebView. The two halves communicate via a simple JSON message bridge. This is the same architecture as MarkEdit (3.6k GitHub stars), but with Milkdown Crepe replacing CodeMirror to get WYSIWYG rendering instead of source editing.

## Reference Implementation

The MarkEdit app source code is at `/Users/aaaaa/marktext-claude/MarkEdit/`. Use it as reference for Swift + WKWebView patterns. Key files:

| Pattern | MarkEdit File |
|---------|--------------|
| WKWebView reuse pool | `MarkEditMac/Sources/Editor/Models/EditorReusePool.swift` |
| NSDocument subclass | `MarkEditMac/Sources/Editor/Models/EditorDocument.swift` |
| EditorViewController | `MarkEditMac/Sources/Editor/Controllers/EditorViewController.swift` |
| Swift→JS bridge | `MarkEditKit/Sources/Extensions/WKWebView+Extension.swift` |
| JS→Swift bridge | `MarkEditKit/Sources/EditorMessageHandler.swift` |
| Bridge modules | `MarkEditKit/Sources/Bridge/Web/WebModuleBridge.swift` |
| WKWebView config | `MarkEditKit/Sources/Extensions/WKWebViewConfiguration+Extension.swift` |

**Do not copy MarkEdit code directly.** Use it to understand patterns, then implement Kern's versions adapted for Milkdown Crepe and Kern's simpler requirements.

## Proof-of-Concept Gates

This build has mandatory validation checkpoints. Do not proceed past a gate until it passes.

### PoC 1: Standalone Milkdown HTML (Gate 1)

Build a single HTML file with Milkdown Crepe that works in Safari.

**Deliverable:** `CoreEditor/dist/index.html` — open in Safari, verify WYSIWYG editing works.

**Validation criteria:**
- [ ] Headings (H1-H6) render with correct visual hierarchy
- [ ] Bold, italic, strikethrough, inline code render correctly
- [ ] Bullet lists, ordered lists, and task lists (checkboxes) render
- [ ] Mixed lists work: bullet points containing checkboxes in the same list
- [ ] Code blocks render with syntax highlighting (test: JavaScript, Python, TypeScript)
- [ ] Tables render and are editable (add/remove rows/columns)
- [ ] LaTeX/math renders (test: `$E = mc^2$` inline and `$$` block)
- [ ] Slash commands work (type `/` to see block insertion menu)
- [ ] Formatting toolbar appears on text selection
- [ ] Images display (test with a URL-referenced image in markdown)
- [ ] Blockquotes render with visual distinction
- [ ] Links are clickable and show tooltips
- [ ] Mermaid code blocks render as SVG diagrams (test with a simple flowchart)
- [ ] Light and dark theme both work (test both `prefers-color-scheme` and `data-theme` attribute toggle)
- [ ] Korean text input works (type Korean characters, verify composition works correctly)
- [ ] Content looks good at 640px width (quarter-screen)
- [ ] The overall rendering quality feels comparable to Notion

**If any of these fail, stop and fix before proceeding.** Rendering quality and reliability are the co-equal top priorities.

### PoC 2: Minimal Swift Shell (Gate 2)

Build a bare macOS app that shows the Milkdown editor in a WKWebView.

**Deliverable:** An Xcode project that builds, launches, and displays the editor.

**Validation criteria:**
- [ ] App launches and shows a window with the WYSIWYG editor
- [ ] Can type text in the editor
- [ ] Swift→JS bridge works: can call `window.kern.getMarkdown()` from Swift and get a string back
- [ ] JS→Swift bridge works: editor content changes trigger a callback in Swift
- [ ] Korean text input works in the WKWebView
- [ ] Window respects system dark/light mode
- [ ] Test with a 5000-line markdown file — verify bridge handles large content without truncation or performance issues

**If the bridge doesn't work, stop and fix before proceeding.**

---

## Project Structure

```
Kern/
├── CoreEditor/                     # TypeScript/Vite → single HTML file
│   ├── package.json
│   ├── tsconfig.json
│   ├── vite.config.mts
│   ├── index.html
│   ├── src/
│   │   ├── main.ts                 # Crepe init + bridge setup
│   │   ├── bridge.ts               # window.kern.* API for Swift
│   │   └── themes/
│   │       └── kern.css            # Custom styling overrides
│   └── dist/
│       └── index.html              # Built single-file output (committed to repo)
├── KernApp/                        # Main app target
│   ├── Sources/
│   │   ├── App/
│   │   │   └── AppDelegate.swift
│   │   ├── Editor/
│   │   │   ├── EditorDocument.swift          # NSDocument subclass
│   │   │   ├── EditorViewController.swift    # WKWebView host
│   │   │   ├── EditorWindowController.swift  # Window configuration
│   │   │   └── EditorReusePool.swift         # WKWebView pool + tab virtualization
│   │   ├── Bridge/
│   │   │   ├── WebBridge.swift               # Swift → JS calls
│   │   │   └── NativeBridge.swift            # JS → Swift message handler
│   │   └── Theme/
│   │       └── AppearanceManager.swift       # System theme observation
│   ├── Resources/
│   │   └── Assets.xcassets                   # App icon (placeholder "K" letter)
│   ├── Info.plist
│   └── Kern.entitlements
└── KernTests/                      # Unit tests
    └── Sources/
        ├── BridgeTests.swift
        └── FileWatchingTests.swift
```

**Note on editor.html:** The Xcode project references `CoreEditor/dist/index.html` directly as a resource (add it via Xcode's "Add Files" with "Create folder references"). Do NOT copy it to a separate location — reference the original to avoid stale copies.

## Build System

Use whatever Xcode project setup is most reliable for an AI agent to create and build. XcodeGen (`project.yml` → `.xcodeproj`) is a good option if you're familiar with it. A manually created Xcode project is also fine. The priority is that `xcodebuild` works on the first try.

**Target:** macOS 14.0+ (Sonoma). Swift 5.9+.

**Web build:** Requires Node.js 18+ and npm 9+. `CoreEditor/dist/index.html` is committed to the repo. Run `cd CoreEditor && npm run build` separately when changing the web layer.

## CoreEditor — Milkdown Crepe Web Layer

### Dependencies

```json
{
  "dependencies": {
    "@milkdown/crepe": "7.18.0",
    "@milkdown/utils": "7.18.0",
    "mermaid": "^11.0.0"
  },
  "devDependencies": {
    "vite": "^6.0.0",
    "vite-plugin-singlefile": "^2.0.0",
    "typescript": "^5.0.0"
  }
}
```

Pin `@milkdown/crepe` and `@milkdown/utils` to exact versions (no caret). Milkdown is pre-1.0 and may introduce breaking changes between minor versions. Test thoroughly before upgrading.

Mermaid is bundled as an npm dependency. Vite inlines it into the single HTML file at build time (~1MB addition). This means mermaid diagrams work offline with no internet connection. The app has **zero network requirements**.

### TypeScript Configuration

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "strict": true,
    "moduleResolution": "bundler",
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

### Vite Configuration

```typescript
// vite.config.mts
import { defineConfig } from 'vite'
import { viteSingleFile } from 'vite-plugin-singlefile'

export default defineConfig({
  plugins: [viteSingleFile({ removeViteModuleLoader: true })],
  build: {
    target: 'safari17',
    minify: true,
  },
})
```

**`target: safari17`** because WKWebView on macOS 14 uses the Safari 17 engine. `removeViteModuleLoader: true` strips Vite's module loader since everything is inlined (WKWebView does not support `type="module"` script tags).

### main.ts — Editor Initialization

```typescript
import { Crepe, CrepeFeature } from '@milkdown/crepe'
import '@milkdown/crepe/theme/common/style.css'
import '@milkdown/crepe/theme/crepe/style.css'
import './themes/kern.css'
import { setupBridge } from './bridge'

try {
  const crepe = new Crepe({
    root: '#editor',
    defaultValue: '',
    features: {
      [CrepeFeature.CodeMirror]: true,
      [CrepeFeature.ListItem]: true,
      [CrepeFeature.LinkTooltip]: true,
      [CrepeFeature.ImageBlock]: true,
      [CrepeFeature.BlockEdit]: true,    // Slash commands + block drag handle
      [CrepeFeature.Toolbar]: true,      // Selection formatting toolbar
      [CrepeFeature.Table]: true,
      [CrepeFeature.Latex]: true,
      [CrepeFeature.Placeholder]: true,
    },
    featureConfigs: {
      [CrepeFeature.Placeholder]: {
        text: 'Start writing, or type / for commands...',
      },
    },
  })

  await crepe.create()
  setupBridge(crepe)

  // Dev mode: load sample content when not in WKWebView
  if (!(window as any).webkit?.messageHandlers?.bridge) {
    const { replaceAll } = await import('@milkdown/utils')
    crepe.editor.action(replaceAll(SAMPLE_MARKDOWN))
  }
} catch (error) {
  // Notify Swift of initialization failure
  const msg = error instanceof Error ? error.message : String(error)
  if ((window as any).webkit?.messageHandlers?.bridge) {
    (window as any).webkit.messageHandlers.bridge.postMessage({
      event: 'loadFailed',
      error: msg,
    })
  }
  // Also show error in the editor area for dev mode
  const el = document.getElementById('editor')
  if (el) el.textContent = `Editor failed to load: ${msg}`
}
```

Include a comprehensive `SAMPLE_MARKDOWN` constant that exercises all features: H1-H6 headings, bullet/ordered/task lists, mixed lists, code blocks (JS, Python), a table, LaTeX (`$E=mc^2$` and `$$` block), an image URL, blockquote, bold/italic/strikethrough/inline code, and links.

### bridge.ts — Swift ↔ JS Interface

Expose a `window.kern` object that Swift calls via `callAsyncJavaScript`:

```typescript
import { Crepe } from '@milkdown/crepe'
import { replaceAll } from '@milkdown/utils'

export function setupBridge(crepe: Crepe) {
  const kern = {
    // Swift calls this to get current markdown
    getMarkdown(): string {
      return crepe.getMarkdown()
    },

    // Swift calls this to load/replace file content
    setMarkdown(md: string): void {
      crepe.editor.action(replaceAll(md))
    },

    // Swift calls this to switch theme
    setTheme(theme: 'light' | 'dark'): void {
      document.documentElement.setAttribute('data-theme', theme)
    },

    // Swift calls this to get scroll position before reload
    getScrollPosition(): number {
      return document.querySelector('.milkdown')?.scrollTop ?? 0
    },

    // Swift calls this to restore scroll position after reload
    setScrollPosition(pos: number): void {
      const el = document.querySelector('.milkdown')
      if (el) el.scrollTop = pos
    },

    // Swift calls this to execute editor commands (undo, redo, bold, italic, code)
    execCommand(command: string): void {
      // Forward to ProseMirror commands via Milkdown
      // Specific implementation depends on Milkdown's command API
      // Use: crepe.editor.action(callCommand(commandKey))
    },
  }

  ;(window as any).kern = kern

  // Notify Swift that editor is ready
  postToSwift('editorReady', {})

  // Listen for content changes
  crepe.on((listener) => {
    listener.markdownUpdated((_ctx, markdown, prevMarkdown) => {
      if (markdown !== prevMarkdown) {
        postToSwift('contentChanged', { markdown })
      }
    })
  })
}

function postToSwift(event: string, data: any): void {
  if ((window as any).webkit?.messageHandlers?.bridge) {
    (window as any).webkit.messageHandlers.bridge.postMessage({
      event,
      ...data,
    })
  }
}
```

### Theme CSS (`kern.css`)

Override Milkdown Crepe's default styles for a Notion-like look:

- **Font:** SF Pro Text for body, SF Pro Display for headings, SF Mono for code. Use system font stacks with fallbacks: `-apple-system, BlinkMacSystemFont, 'SF Pro Text', ...`
- **Spacing:** Comfortable block spacing (Notion-like, not cramped)
- **Colors:** Use `prefers-color-scheme` media query for automatic light/dark. ALSO support `[data-theme="dark"]` and `[data-theme="light"]` attribute selectors for manual toggle from Swift. Test both mechanisms — Milkdown Crepe's default theme CSS may only use `prefers-color-scheme`, in which case the `data-theme` attribute selectors need to override colors explicitly.
- **Code blocks:** Rounded corners, subtle background, good contrast
- **Checkboxes:** Custom styled (not browser default), visually distinct checked/unchecked states
- **CSS custom properties:** Use CSS variables for all colors, spacing, and font sizes. This architecture enables future custom themes to override just the variables without touching layout CSS.
- **Responsive:** Ensure toolbar and block controls work at 640px width (quarter-screen). Add media queries if needed to collapse non-essential UI at narrow widths.

### Mermaid Diagram Rendering

Mermaid is bundled into the HTML at build time via npm + Vite (no internet needed). Initialize mermaid on startup with `mermaid.initialize({ startOnLoad: false })`.

**Rendering approach:**
1. Configure Milkdown Crepe's CodeMirror feature to detect code blocks with language `mermaid`
2. When a mermaid block is found, call `mermaid.render()` to produce SVG
3. Display the rendered SVG below (or instead of) the code block source

This is a Phase 6 feature. The implementation likely requires a custom ProseMirror NodeView plugin that intercepts `mermaid`-language code blocks and renders SVG output. If the integration with Milkdown's CodeMirror feature proves too complex, implement it as a post-render pass that scans the DOM for `mermaid` code blocks and injects SVG siblings.

**No internet connection is required.** The mermaid library is fully bundled in the HTML file.

---

## Swift App Layer

### AppDelegate.swift

- Standard macOS document-based app delegate
- On `applicationDidFinishLaunching`: call `EditorReusePool.shared.warmUp()` to pre-create WKWebViews
- Observe system appearance changes (`NSApp.effectiveAppearance`) and broadcast theme updates to all active editors

### EditorReusePool.swift — WKWebView Pool + Tab Virtualization

This is the most performance-critical Swift component. It manages WKWebView lifecycle for 20+ tabs with bounded memory.

**Performance target:** <200ms from Cmd-click to rendered content visible. This requires pre-warmed WKWebView instances with the editor HTML already loaded. The first 3 file opens use pre-warmed instances (near-instant). Subsequent opens reuse recycled instances (~200-500ms depending on content size).

**Pool behavior:**
- On app launch, pre-warm 3 `EditorViewController` instances (HTML fully loaded in each WKWebView)
- All WKWebViews share one `WKProcessPool` (reduces per-process overhead)
- Keep max 5 live WKWebViews at any time (active tab + 4 most recently viewed)
- Each live WKWebView is a fully initialized `EditorViewController` with content displayed

**Virtualization:**
- When a new tab is activated and 5 WKWebViews are already live: virtualize the least-recently-used (LRU) tab
- Virtualizing a tab means: (1) call `getMarkdown()` to save current content to a Swift string, (2) call `getScrollPosition()` to save scroll offset, (3) detach the WKWebView from that tab and recycle it for the new tab
- When switching to a virtualized tab: (1) dequeue a live WKWebView from the pool (virtualizing its current tab if needed), (2) call `setMarkdown(savedContent)`, (3) call `setScrollPosition(savedOffset)`
- Track each tab's state: `live` (has WKWebView, content displayed) or `virtualized` (markdown + scroll position saved as Swift values, no WKWebView)

**WKWebView lifecycle state machine:**

| State | Trigger | Action |
|-------|---------|--------|
| **Fresh** (from pool, HTML loaded, no content) | Tab activated | Call `setMarkdown(content)`. Editor is ready immediately because HTML is already loaded. |
| **Recycled** (HTML loaded, has different content) | Tab switched | Call `setMarkdown(newContent)` + `setScrollPosition(pos)`. No need to reload HTML. |
| **Crashed** (WebContent process terminated) | `webViewWebContentProcessDidTerminate` callback | Reload the editor HTML string via `loadHTMLString()`. Wait for `editorReady` callback. Then call `setMarkdown(savedContent)` to restore from the document's `stringValue`. |

**Shared WKProcessPool:**
```swift
static let sharedProcessPool = WKProcessPool()

// Use in every WKWebViewConfiguration
let config = WKWebViewConfiguration()
config.processPool = Self.sharedProcessPool
```

**Dequeue algorithm (pseudocode):**
```
func dequeue() -> EditorViewController:
    // 1. Check pool for pre-warmed unused instance
    if let unused = pool.first(where: { $0.document == nil }):
        return unused

    // 2. If under max live count, create new
    if liveCount < maxLive:
        let new = createAndWarmViewController()
        return new

    // 3. Pool is full — virtualize LRU tab and recycle its WKWebView
    let lru = liveControllers.sorted(by: lastAccessTime).first!
    virtualize(lru)  // saves markdown + scroll, detaches from document
    return lru       // now available for reuse
```

### EditorDocument.swift — NSDocument Subclass

```swift
class EditorDocument: NSDocument {
    var stringValue: String = ""

    override class var autosavesInPlace: Bool { true }

    // Read file from disk
    override func read(from data: Data, ofType typeName: String) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Kern", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File is not valid UTF-8 text."])
        }
        stringValue = text
    }

    // Write file to disk
    override func data(ofType typeName: String) throws -> Data {
        guard let data = stringValue.data(using: .utf8) else {
            throw NSError(domain: "Kern", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode text as UTF-8."])
        }
        return data
    }

    // Create window + editor for this document
    override func makeWindowControllers() {
        let viewController = EditorReusePool.shared.dequeue()
        let windowController = EditorWindowController(viewController: viewController)
        addWindowController(windowController)
        viewController.loadDocument(self)
    }
}
```

**File > New behavior:** Creates an untitled document with empty `stringValue`. The Milkdown placeholder text ("Start writing, or type / for commands...") appears. On first save (Cmd+S or close), macOS shows a standard Save dialog asking where to save the `.md` file. Uses the same `EditorDocument` class.

**Autosave flow:**
1. Editor content changes → JS sends `contentChanged` to Swift → `EditorDocument.stringValue` is updated
2. NSDocument's autosave timer fires → calls `data(ofType:)` → writes `stringValue` to disk
3. No save dialog ever appears for existing files (`autosavesInPlace = true`)

**Async content retrieval before save:**
Override `autosave(withImplicitCancellability:)` to fetch the latest markdown from the WKWebView before saving. This handles the race where content changed in the editor but the `contentChanged` JS callback hasn't fired yet. Follow MarkEdit's pattern in `EditorDocument.swift` lines 348-365.

**NSFilePresenter note:** NSDocument automatically registers itself as an NSFilePresenter when `fileURL` is set. No manual `NSFileCoordinator.addFilePresenter()` call is needed. File watching only activates for saved documents (not untitled/new).

### File Watching (Auto-Reload)

Override `presentedItemDidChange()` in EditorDocument:

```swift
private var reloadWorkItem: DispatchWorkItem?

override func presentedItemDidChange() {
    guard let fileURL, let fileType else { return }

    // CRITICAL: Dispatch async from presenter queue to avoid deadlock.
    // Never do file coordination inside presentedItemDidChange.
    DispatchQueue.main.async { [weak self] in
        guard let self else { return }

        // Cancel any pending reload (debounce)
        self.reloadWorkItem?.cancel()

        // Schedule reload after 300ms delay (batches rapid AI agent writes)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let modDate = attrs[.modificationDate] as? Date

                // Only reload if file on disk is newer than our last known date
                guard let modDate, modDate > (self.fileModificationDate ?? .distantPast) else {
                    return
                }

                self.fileModificationDate = modDate
                try self.revert(toContentsOf: fileURL, ofType: fileType)

                // Show brief toast notification
                self.hostViewController?.showReloadToast()
            } catch {
                // Log error, never crash
            }
        }
        self.reloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
}
```

**Conflict handling:** Always revert to the file on disk. Show a brief dismissible toast ("File reloaded from disk") at the top of the editor for ~3 seconds. No user decision needed. Rationale: autosave means edits are saved within ~1 second of typing, so the window for data loss is minimal. The primary use case (watching AI agent output) benefits from immediate reloads without interruption.

**Scroll position preservation on reload:** Before calling `revert`, save the current scroll position via `bridge.getScrollPosition()`. After the revert triggers a new `setMarkdown` call, restore via `bridge.setScrollPosition()`. This prevents the editor from jumping to the top when an AI agent modifies the file.

### EditorViewController.swift — WKWebView Host

- Creates `WKWebView` with shared `WKProcessPool` and message handler registration
- Loads `editor.html` via `loadHTMLString(_:baseURL:)` — read the HTML from the app bundle into a string, pass `baseURL: URL(string: "http://localhost/")!` (required for relative resource loading; this is MarkEdit's pattern)
- Registers `bridge` message handler for JS→Swift communication
- On `editorReady` callback: loads document content via `bridge.setMarkdown()`
- On `contentChanged` callback: updates `EditorDocument.stringValue`
- On `loadFailed` callback: display the error message in the window (replace WebView content or show an alert)
- Handles theme switching via `bridge.setTheme()`
- Conforms to `WKNavigationDelegate` and implements `webViewWebContentProcessDidTerminate` to reload HTML and restore content

**WKWebView configuration:**
```swift
let config = WKWebViewConfiguration()
config.processPool = EditorReusePool.sharedProcessPool

let userContentController = WKUserContentController()
userContentController.add(self, name: "bridge")
config.userContentController = userContentController

// Do NOT use allowFileAccessFromFileURLs — it is a private WebKit API
// that may cause App Store rejection. Use baseURL: http://localhost/ instead.
```

**Do NOT use `evaluateJavaScript` with completion handlers.** There is a known memory leak (WebKit bug 215729). Use `callAsyncJavaScript(_:arguments:contentWorld:)` exclusively on macOS 14+. Pass data via the `arguments` dictionary — this handles escaping automatically, no manual JSON string interpolation needed.

### EditorWindowController.swift

- Programmatic `NSWindow` (no storyboard for windows — storyboard is used ONLY for the menu bar)
- `tabbingMode = .preferred` for native macOS tab support
- `titlebarAppearsTransparent = false` (standard title bar with document name)
- `windowFrameAutosaveName` for window position restoration
- Minimum window size: `NSSize(width: 640, height: 480)` (quarter-screen support)
- Window restoration (reopening tabs on app relaunch) is out of scope for v1

### WebBridge.swift — Swift → JS Calls

```swift
@MainActor
class WebBridge {
    private weak var webView: WKWebView?

    func getMarkdown() async throws -> String {
        guard let webView else { throw BridgeError.noWebView }
        let result = try await webView.callAsyncJavaScript(
            "return window.kern.getMarkdown()",
            contentWorld: .page
        )
        return result as? String ?? ""
    }

    func setMarkdown(_ markdown: String) async throws {
        guard let webView else { throw BridgeError.noWebView }
        try await webView.callAsyncJavaScript(
            "window.kern.setMarkdown(content)",
            arguments: ["content": markdown],
            contentWorld: .page
        )
    }

    func setTheme(_ theme: String) async throws {
        guard let webView else { throw BridgeError.noWebView }
        try await webView.callAsyncJavaScript(
            "window.kern.setTheme(theme)",
            arguments: ["theme": theme],
            contentWorld: .page
        )
    }

    func getScrollPosition() async throws -> Double {
        guard let webView else { throw BridgeError.noWebView }
        let result = try await webView.callAsyncJavaScript(
            "return window.kern.getScrollPosition()",
            contentWorld: .page
        )
        return result as? Double ?? 0
    }

    func setScrollPosition(_ position: Double) async throws {
        guard let webView else { throw BridgeError.noWebView }
        try await webView.callAsyncJavaScript(
            "window.kern.setScrollPosition(pos)",
            arguments: ["pos": position],
            contentWorld: .page
        )
    }

    func execCommand(_ command: String) async throws {
        guard let webView else { throw BridgeError.noWebView }
        try await webView.callAsyncJavaScript(
            "window.kern.execCommand(cmd)",
            arguments: ["cmd": command],
            contentWorld: .page
        )
    }
}
```

### NativeBridge.swift — JS → Swift Message Handler

```swift
class NativeBridge: NSObject, WKScriptMessageHandler {
    weak var delegate: NativeBridgeDelegate?

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let event = body["event"] as? String else { return }

        switch event {
        case "editorReady":
            delegate?.editorDidBecomeReady()
        case "contentChanged":
            if let markdown = body["markdown"] as? String {
                delegate?.editorContentDidChange(markdown: markdown)
            }
        case "loadFailed":
            if let error = body["error"] as? String {
                delegate?.editorDidFailToLoad(error: error)
            }
        default:
            break
        }
    }
}

protocol NativeBridgeDelegate: AnyObject {
    func editorDidBecomeReady()
    func editorContentDidChange(markdown: String)
    func editorDidFailToLoad(error: String)
}
```

### AppearanceManager.swift — Theme Observation

- Observe `NSApp.effectiveAppearance` for system dark/light mode changes
- When appearance changes, iterate all live `EditorViewController`s and call `bridge.setTheme("light"/"dark")`
- The JS side sets `data-theme` attribute on `<html>`, which CSS selectors use for theming

### Info.plist — File Type Registration

Register Kern as an editor for markdown files only:

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Markdown Document</string>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>net.daringfireball.markdown</string>
        </array>
        <key>CFBundleTypeExtensions</key>
        <array>
            <string>md</string>
            <string>markdown</string>
            <string>mdown</string>
            <string>mkd</string>
        </array>
        <key>NSDocumentClass</key>
        <string>$(PRODUCT_MODULE_NAME).EditorDocument</string>
    </dict>
</array>
```

**Do NOT include `public.plain-text`** in LSItemContentTypes — that would make Kern offer to open ALL text files (.txt, .json, .yaml, etc.), not just markdown.

Also declare the markdown UTI in `UTImportedTypeDeclarations` if needed for macOS 14.

### Kern.entitlements

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

- `app-sandbox`: Required for macOS apps
- `files.user-selected.read-write`: File picker access and opening files via `open` command

**No `network.client` entitlement.** Kern has zero internet requirements. All dependencies (Milkdown, mermaid) are bundled in the HTML file at build time.

**Note:** For v1 (direct Xcode build, no code signing), sandboxing may not be enforced. Include the entitlements anyway so the app is ready for future code signing and App Store submission.

### Native Menus

Create a `Main.storyboard` containing ONLY an NSMenu (Application menu bar). Do NOT add any Window Controller or View Controller scenes to the storyboard. Windows are created programmatically in `EditorDocument.makeWindowControllers()`.

Menu structure:

- **Kern:** About Kern, Quit Kern
- **File:** New (⌘N), Open (⌘O), Save (⌘S), Close (⌘W) — all wired to NSDocument first responder actions
- **Edit:** Undo (⌘Z), Redo (⇧⌘Z), Cut, Copy, Paste, Select All — **Undo and Redo must be forwarded to the JS editor via `bridge.execCommand("undo"/"redo")`**, NOT handled by NSDocument's built-in UndoManager. NSDocument's UndoManager does not know about ProseMirror's internal undo stack. Cut/Copy/Paste/Select All work natively via WKWebView.
- **Format:** Bold (⌘B), Italic (⌘I), Code (⌘E) — send commands to JS editor via `bridge.execCommand()`
- **View:** Toggle Dark Mode
- **Window:** Minimize, Zoom, standard window management

---

## Tab Behavior

- `NSWindow.tabbingMode = .preferred` enables native macOS tabs
- All files opened from terminal Cmd-clicks open as tabs in the same window (macOS routes `open -a Kern file.md` to the running instance via NSDocumentController automatically)
- When multiple files are opened rapidly, the **last file opened** receives focus
- Tab title shows the filename (from `NSDocument.displayName`)
- Closing the last tab closes the window
- Tab order follows open order

---

## Testing

### Unit Tests (KernTests)

Write unit tests for:

1. **Bridge serialization:** Verify JSON messages are correctly formed and parsed
2. **File watching debounce:** Verify rapid file changes are batched correctly (fire 5 changes in 100ms, verify only 1 reload)
3. **Virtualization state:** Verify tabs transition between `live` and `virtualized` states correctly
4. **Document encoding:** Verify UTF-8 read/write round-trips (including Korean 한글, emoji 🎉, CJK 中文)
5. **Dequeue algorithm:** Verify LRU eviction when pool is full

### Manual Verification Checklist

After the full build, verify:

- [ ] `open -a Kern /path/to/file.md` opens the file in WYSIWYG mode
- [ ] Editing content → close window → reopen → changes are preserved (autosave)
- [ ] No "save changes?" dialog on close
- [ ] Modify file externally (`echo "new" >> file.md`) → editor updates within ~500ms, brief toast appears
- [ ] Scroll position is preserved after external file reload
- [ ] System dark mode toggle → editor theme switches
- [ ] Korean text input works correctly (compose 한글, verify no character loss)
- [ ] Open 5+ files rapidly from terminal → all appear as tabs in one window, last one focused
- [ ] Cmd+Z/Shift+Cmd+Z performs undo/redo in the editor (not NSDocument undo)
- [ ] Cmd+B/I/E toggles bold/italic/code in the editor
- [ ] File > New creates untitled document with placeholder text
- [ ] File > Open shows file picker filtered to .md files
- [ ] Window size at 640px width → content reflows, no horizontal scrollbar on body text
- [ ] LaTeX, code blocks, tables, checklists all render correctly
- [ ] Memory usage with 5 live tabs + 15 virtualized tabs < 500MB total (app + WebKit processes)
- [ ] Cmd-click a non-markdown file in Finder → Kern does NOT offer to open it

---

## Build Phases

### Phase 1: CoreEditor (PoC Gate 1)
Build the standalone Milkdown Crepe HTML file. Test in Safari. Validate rendering quality.

### Phase 2: Swift Shell (PoC Gate 2)
Build minimal macOS app with one WKWebView loading the HTML. Verify bridge works both directions. Use a simple pool of 3 pre-warmed WKWebViews with no virtualization.

### Phase 3: NSDocument Integration
Add EditorDocument, file open/save/autosave. Register file types. This is when `open -a Kern file.md` starts working.

### Phase 4: File Watching + Auto-Reload
Add `presentedItemDidChange()` with 300ms debounce. Implement scroll-preserving reload. Add toast notification.

### Phase 5: Tab Virtualization
Upgrade EditorReusePool from simple pool (Phase 2) to virtualized pool with LRU eviction. Add shared WKProcessPool. Handle `webViewWebContentProcessDidTerminate`.

### Phase 6: Themes + Menus + Polish
System theme observation. Native menu bar with format and undo/redo commands forwarded to JS. Placeholder app icon. Quarter-screen responsive CSS. Mermaid lazy loading.

---

## Decisions Already Made (Do Not Revisit)

- **App name:** Kern
- **Platform:** macOS 14+ only. No cross-platform.
- **Architecture:** Swift + AppKit + WKWebView + Milkdown Crepe
- **Editor engine:** Milkdown Crepe (not Tiptap, not BlockNote, not CodeMirror)
- **No Electron, no Tauri** — pure Swift wrapper around system WKWebView
- **No vault/workspace mode** — individual files only
- **No cloud sync, no plugins, no split pane, no vim keybindings**
- **Bridge:** Simple manual (not typed code-gen). ~8 methods.
- **Web build:** Committed HTML file (not Xcode build phase)
- **Distribution (v1):** Direct Xcode build. No code signing.
- **Tab virtualization:** 5 live WKWebViews, background tabs hold markdown strings
- **Conflict handling:** Always revert + toast notification
- **Window restoration:** Out of scope for v1

## Constraints

- **Developer experience:** The person building this is new to both Swift and Milkdown. The AI agent writes most code. Every step should be small, testable, and produce visible results.
- **Korean IME is critical.** Must work for daily use. Test with Korean input at every stage.
- **Rendering quality and reliability are co-equal top priorities.** If something looks bad, fix it before moving on. If something can crash or lose data, fix it before moving on.
- **Performance target:** <200ms file open for pre-warmed instances. <500ms for recycled instances.
- **Memory target:** <500MB total (app + WebKit processes) with 5 live tabs + 15 virtualized tabs.
- **No over-engineering.** v1 must-haves only. Every feature should earn its place.
