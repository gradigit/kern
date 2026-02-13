# Kern

A native macOS markdown editor. Opens `.md` files and renders them as rich text — no visible syntax while you type. Built with Swift and WKWebView on top of [Milkdown](https://milkdown.dev).

The idea: an AI agent writes a markdown file, you Cmd-click the path in your terminal, and the file opens instantly in a clean WYSIWYG editor. No Electron, no web app, no project/vault/workspace setup.

<!-- TODO: add screenshot here when one exists -->

## What it does

* Opens any `.md` file with Notion-style rich rendering

* WYSIWYG editing — bold, italic, code, links, tables, math, mermaid diagrams

* Native macOS tabs and windows (Cmd+N, Cmd+T)

* Dark mode follows your system appearance

* Autosave and file watching — external changes reload automatically

* Search and replace (Cmd+F, Cmd+Shift+H)

* Three kinds of checkboxes: standalone `[ ]`, bulleted `- [ ]`, and ordered `1. [ ]`

* Mermaid diagram rendering for all 12 diagram types

* LaTeX math (inline and block)

* Tab virtualization — keeps up to 5 editors live, the rest save to memory

## Requirements

* macOS 14.0 or later

* Xcode 16+ (to build from source)

* [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

* Node.js 18+ (only if you're modifying the web editor layer)

## Building from source

The project has two layers: a Swift app shell and a web editor built with Vite. The web layer compiles to `CoreEditor/dist/` (a small HTML shell + code-split JS chunks, \~5MB total) that ships inside the app bundle. The compiled output is checked into the repo, so you only need Node.js if you're changing the TypeScript/CSS.

### Build the app

```bash
# Generate Xcode project (uses XcodeGen)
xcodegen

# Build
xcodebuild -project Kern.xcodeproj -scheme Kern build

# Run
open ~/Library/Developer/Xcode/DerivedData/Kern-*/Build/Products/Debug/Kern.app
```

### Open a file

```bash
open -a Kern /path/to/file.md
```

### Modify the web editor (optional)

```bash
cd CoreEditor
npm install
npm run dev        # dev server at localhost:5173
npm run build      # compile to dist/
```

After `npm run build`, rebuild the Xcode project to pick up the new output.

## Testing

```bash
# 36 Playwright E2E tests (runs against WebKit to match the WKWebView runtime)
cd CoreEditor && npx playwright test

# App integration test
./scripts/test-kern-app.sh [--skip-build] [--screenshots]
```

There's also a manual testing checklist in `MANUAL-TESTING.md` for things that need a human eye (checkbox interactions, theme switching, keyboard shortcuts).

## Architecture

Two layers talk over a JSON bridge:

**Swift** (`KernApp/Sources/`) handles the app lifecycle, file I/O, autosave, native tabs, and WKWebView hosting. NSDocument manages each file. An LRU pool keeps at most 5 WKWebViews alive and virtualizes the rest to plain strings.

**Web** (`CoreEditor/src/`) runs the actual editor. Milkdown Crepe (a ProseMirror wrapper) does the heavy lifting. Custom plugins handle mermaid rendering, search/replace, standalone checkboxes, and inline-nested list collapsing.

The bridge is simple: Swift calls `window.kern.*` methods via `callAsyncJavaScript`, and JS posts messages to `window.webkit.messageHandlers.nativeBridge`. About 8 methods total (`getMarkdown`, `setMarkdown`, `setTheme`, etc.).

```
KernApp/Sources/
├── App/              # AppDelegate, menu bar, theme manager
├── Bridge/           # Swift↔JS message passing
└── Editor/           # NSDocument, WKWebView host, reuse pool

CoreEditor/src/
├── main.ts           # Editor init, slash menu config
├── bridge.ts         # window.kern API
├── checkbox.ts       # Standalone checkbox node ([ ] syntax)
├── search.ts         # Find & replace plugin
├── mermaid.ts        # Diagram rendering
├── toast.ts          # Notification overlay
├── inline-nested.ts  # Collapses nested single-item lists
└── themes/kern.css   # All editor styling
```

## Markdown extensions

Kern extends GFM with a few syntax additions. Regular markdown files open fine — the extensions are only relevant if you use Kern-specific features. See [KERN-MARKDOWN.md](KERN-MARKDOWN.md) for the full spec.

| Syntax        | What Kern shows     | What GFM shows        |
| ------------- | ------------------- | --------------------- |
| `[ ] text`    | Standalone checkbox | Literal text          |
| `- [ ] text`  | Bullet + checkbox   | Checkbox (no bullet)  |
| `1. [ ] text` | Number + checkbox   | Literal `[ ]` in list |

## Dependencies

**Swift side:** AppKit and WebKit only. No third-party Swift packages.

**Web side:** `@milkdown/crepe` and `@milkdown/utils` (both pinned to 7.18.0), `mermaid`, `vite`, `typescript`. Milkdown versions are pinned because they're pre-1.0 and break between minors.

## Project status

All planned features are implemented. The app works for daily use. There's no code signing or notarization yet, so macOS will flag it on first launch (right-click → Open to bypass). No license has been chosen yet.

## Contributing

The codebase has a `CLAUDE.md` with detailed architecture notes and conventions if you want to orient yourself. The short version: Swift 6 strict concurrency is on, the menu bar is built programmatically (no storyboard), and the web layer's compiled output is committed to the repo.

If you find a bug, open an issue. Pull requests are welcome for fixes. For larger changes, open an issue first to discuss the approach.
