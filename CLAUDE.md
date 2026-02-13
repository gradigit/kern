# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Kern

A native macOS WYSIWYG markdown editor. Swift + AppKit wraps WKWebView running Milkdown Crepe (ProseMirror-based). Opens `.md` files with Notion-quality rendering — no visible markdown syntax while editing. Target workflow: AI agent outputs files, user Cmd-clicks in terminal, file opens instantly in Kern.

## Session Start Checklist

**Every new session (including after context clears), do this first:**

1. Read `CONTEXT-RESTORE.md` — paste-ready prompt with current priorities and key files
2. Read `TODO.md` — it has the exact current state, what's done, what's in progress, what's next
3. Read `architect/plan.md` if you need implementation details for the current phase
4. Check `git log --oneline` to see recent commits

## Workflow Rules

* **Keep** **`TODO.md`** **constantly up to date.** Update it as you start tasks, complete sub-tasks, discover issues, or finish phases. This is your lifeline when context gets cleared — if you don't update it, the next session starts blind.

* **Update** **`CONTEXT-RESTORE.md`** before ending a session or when priorities change. This is what gets pasted after context clears — it must reflect the current top priority and key files.

* **Follow** **`architect/plan.md`** for phase-by-phase implementation steps, API corrections, and risk mitigations. This is the primary build guide.

* **Git commit** after completing each phase or significant milestone. Use descriptive messages with `Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>`.

* **Build + test before committing.** Always run `xcodebuild` and verify the app works. Run the app directly from the command line to see NSLog output:

  ```bash
  /path/to/DerivedData/.../Debug/Kern.app/Contents/MacOS/Kern &
  ```

* **Update this file** when phases complete (update the Build Phases section).

## Project Documents

| File                      | Purpose                                                                   | When to read                                                                   |
| ------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `CONTEXT-RESTORE.md`      | Paste-ready prompt for new sessions with current priorities and key files | **Paste after every context clear**                                            |
| `TODO.md`                 | Persistent task list with current progress, sub-tasks, known issues       | **Every session start** — this is the source of truth for current state        |
| `architect/plan.md`       | Implementation plan with step-by-step build instructions per phase        | **Primary reference** when building — has API corrections and risk mitigations |
| `architect/prompt.md`     | Architecture spec used as input to generate plan.md                       | Background context only; plan.md supersedes this                               |
| `architect/transcript.md` | Design questionnaire recording why decisions were made                    | Only if you need to understand decision rationale                              |
| `KERN-MARKDOWN.md`     | Kern's markdown syntax extensions vs GFM spec                             | When working on checkbox/task list rendering                                   |
| `MANUAL-TESTING.md`    | Checklist of items requiring human verification in running app            | After implementing UI changes — verify items manually                          |
| `architect/cold-start-optimization.md` | Deep research: cold start sequence, optimization plan, MarkEdit patterns | When working on launch performance — has verified timing data and priority list |
| `architect/benchmarking-methodology.md` | Cross-editor benchmark methodology, statistical approach, tool design   | When measuring performance — defines metrics, protocols, and measurement tools  |

## Build Commands

```bash
# Generate Xcode project from project.yml (required after changing project.yml or adding new Swift files)
xcodegen

# Build the macOS app
xcodebuild -project Kern.xcodeproj -scheme Kern build

# Build CoreEditor web layer (only when changing TypeScript/CSS)
cd CoreEditor && npm run build

# Dev server for CoreEditor (standalone browser testing)
cd CoreEditor && npm run dev

# Open a file in running Kern
open -a Kern /path/to/file.md
```

### Testing

```bash
# Run Playwright E2E tests (36 tests, WebKit browser matching WKWebView)
cd CoreEditor && npx playwright test

# Run Kern.app integration test
./scripts/test-kern-app.sh [--skip-build] [--screenshots]
```

Manual verification is also done by building and running the app. See `MANUAL-TESTING.md` for checklist.

## Architecture

Two-layer architecture with a JSON message bridge:

**Swift layer** (`KernApp/Sources/`) — AppKit shell, NSDocument lifecycle, WKWebView hosting
**Web layer** (`CoreEditor/`) — Milkdown Crepe editor, built to `CoreEditor/dist/` (multi-file output committed to repo)

The built output (\~5MB total: small HTML shell + code-split JS chunks + CSS + fonts) is bundled as a folder resource in the Xcode project. Mermaid and other heavy dependencies are lazy-loaded via ES module chunks. Zero network requirements.

### Bridge Pattern

* **Swift→JS**: `WebBridge.swift` calls `window.kern.*` methods via `WKWebView.callAsyncJavaScript()` (never use `evaluateJavaScript` — WebKit memory leak bug 215729)

* **JS→Swift**: `bridge.ts` posts messages to `window.webkit.messageHandlers.nativeBridge`, received by `NativeBridge.swift` via `WKScriptMessageHandler`

* Message handler name: `nativeBridge`. Messages use `{ type: "eventName", ... }` format.

* Bridge methods: `getMarkdown`, `setMarkdown`, `setTheme`, `getScrollPosition`, `setScrollPosition`, `execCommand`, `isReady`

### Key Swift Components

| File                                  | Role                                                                                         |
| ------------------------------------- | -------------------------------------------------------------------------------------------- |
| `App/main.swift`                      | Manual entry point — instantiates KernDocumentController before app.run()                    |
| `App/KernDocumentController.swift`    | NSDocumentController subclass — tracks Apple Event file opens to prevent extra untitled docs |
| `App/AppDelegate.swift`               | Lifecycle, programmatic menu bar (File/Edit/Format/View/Window), pool warm-up, Cmd+N/Cmd+T   |
| `App/AppearanceManager.swift`         | Observes system theme, broadcasts `setTheme()` to all live editors                           |
| `App/AppHacks.swift`                  | AX bundle loading swizzle — moves to background thread to avoid blocking launch             |
| `Editor/EditorDocument.swift`         | NSDocument subclass — file I/O, autosave, file watching, content tracking                    |
| `Editor/EditorViewController.swift`   | WKWebView host, bridge callbacks, virtualization, format actions, crash recovery             |
| `Editor/EditorWindowController.swift` | Programmatic NSWindow, native tab support, WKWebView cleanup on close                        |
| `Editor/EditorReusePool.swift`        | LRU-evicting WKWebView pool (max 5 live, unlimited virtualized)                              |
| `Bridge/WebBridge.swift`              | Swift→JS calls via `callAsyncJavaScript` with arguments dict                                 |
| `Bridge/NativeBridge.swift`           | JS→Swift message handler via WKScriptMessageHandler                                          |
| `Bridge/EditorSchemeHandler.swift`    | kern:// scheme handler, serves all files from CoreEditor/dist/ bundle folder                 |

### Key TypeScript Components

| File             | Role                                                                        |
| ---------------- | --------------------------------------------------------------------------- |
| `src/main.ts`    | Crepe editor init, error reporting to Swift, sample markdown for dev mode   |
| `src/bridge.ts`  | `window.kern` API, `markdownUpdated` listener with dedup via `lastMarkdown` |
| `src/mermaid.ts` | Lazy mermaid rendering via MutationObserver, dynamic import                 |
| `src/checkbox.ts` | Standalone checkbox node (`[ ] text`) — schema, remark plugin, input rule, click handler |
| `src/search.ts`   | ProseMirror search & replace plugin with DecorationSet highlights                        |
| `src/toast.ts`    | Toast notification overlay (`showToast()`)                                                |
| `src/inline-nested.ts` | MutationObserver collapsing single-item nested lists to one line                    |

## Swift 6 Concurrency Gotchas

The project uses `SWIFT_STRICT_CONCURRENCY: complete` (Swift 6 mode).

* **EditorDocument is NOT** **`@MainActor`** — its `read(from:ofType:)` and `data(ofType:)` are called on background threads by NSDocumentController. It uses `@preconcurrency import AppKit` and `nonisolated override init()` to avoid runtime `dispatch_assert_queue_fail` crashes when NSDocumentController opens documents from background threads.

* **All other Swift classes are** **`@MainActor`** — EditorViewController, EditorWindowController, EditorReusePool, WebBridge, NativeBridge, AppDelegate, KernDocumentController.

* WKWebView bridge calls (`callAsyncJavaScript`) must happen on main thread.

* EditorDocument has intentional Swift 6 warnings for background-thread property access — do not try to "fix" these.

## Build System

XcodeGen generates `.xcodeproj` from `project.yml`. Key settings:

* macOS 14.0+ deployment target

* Swift 6.0, strict concurrency

* `CoreEditor/dist` included as a folder resource

* Code signing disabled (`CODE_SIGN_IDENTITY: "-"`)

* Sandbox disabled for development (entitlements ready for future signing)

* **Run** **`xcodegen`** **after adding new Swift files** — it regenerates the xcodeproj from project.yml

## Build Phases (Project Status)

See `TODO.md` for detailed sub-task state and known issues.

1. **CoreEditor HTML** — DONE
2. **Minimal Swift Shell** — DONE
3. **NSDocument Integration** — DONE
4. **File Watching + Auto-Reload** — DONE
5. **Tab Virtualization** — DONE
6. **Themes + Menus + Polish** — DONE
7. **Bug Fixes (Phase 7)** — DONE
8. *(skipped)*
9. **Bug Fixes + Polish (Phase 9)** — DONE
10. **Bug Fixes, Features & Tests (Phase 10)** — DONE
11. **UX Improvements (Phase 11)** — DONE
12. **Checkbox System + Cmd+N/Cmd+T (Phase 12)** — DONE
13. **Copy Feedback, Table Wrapping, Scrollbar Fixes (Phase 13)** — DONE
14. **Cold Start Optimization Phase A (Phase 14)** — DONE
15. **Cold Start Optimization Phase B — Code Splitting (Phase 15)** — DONE
16. **Cold Start Optimization Phase C — Deep Optimization (Phase 16)** — DONE

## Locked Decisions

Do not revisit these:

* Milkdown Crepe as editor engine (not Tiptap/BlockNote/CodeMirror)

* Individual files only, no vault/workspace mode

* No cloud sync, plugins, split pane, or vim keybindings

* Simple manual bridge (\~8 methods, not typed code-gen)

* Built dist/ output committed to repo (not an Xcode build phase)

* Always-revert conflict handling with toast notification

* 5 live WKWebViews max, background tabs virtualized to strings

* Window restoration out of scope for v1

* Undo/Redo forwarded to JS editor (not NSDocument UndoManager)

* No Main.storyboard — menu bar built programmatically in AppDelegate

## Dependencies

**Swift**: AppKit, WebKit (system frameworks only)
**npm** (`CoreEditor/package.json`): `@milkdown/crepe@7.18.0` (pinned exact), `@milkdown/utils@7.18.0` (pinned exact), `mermaid@^11`, `vite@^6`, `typescript@^5`

Milkdown versions are pinned because pre-1.0 versions may break between minors.

## Reference

MarkEdit source at `/Users/aaaaa/marktext-claude/MarkEdit/` is used as an architectural reference for Swift + WKWebView patterns. Do not copy code directly — adapt patterns for Kern's simpler requirements.
