# Forge State
## Current Stage: complete
## Mode: 1
## Depth: full
## Categories Asked: [1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12]
## Categories Skipped: [7 — local-only app, no security concerns]
## Key Decisions:
- Audience: Personal → product trajectory
- Priority #1: Rendering quality (Notion-level)
- Priority #2: Reliability (never crash, never lose data)
- Korean IME: Critical for v1
- Bridge: Simple/manual (4-6 methods)
- Web build: Commit built HTML
- Build system: Whatever follows best practices
- Conflict handling: Warn if user has unsaved edits, silent reload otherwise
- File open target: <200ms
- Simultaneous files: 20+ (memory tension with WKWebView pool)
- Debounce: 300ms
- Tab behavior: All in tabs, one window
- Milkdown risk: Fork and fix
- Mermaid: Lazy-load in v1
- Testing: Manual + key unit tests (bridge, file watching)
- Distribution: Direct Xcode build for v1
- PoC gates: Mandatory validation checkpoints before full build
- Extensibility: Theme system designed for later expansion
- Done = replaces MarkText daily
- Mermaid: bundled at build time (no internet)
- Network: zero internet requirements
- Conflict handling: always revert + toast
- Priorities: rendering quality and reliability co-equal #1
- Scroll preservation on reload
- Undo/Redo forwarded to JS editor (not NSDocument UndoManager)

## Cold Start Optimization Forge (Feb 2026): complete
- Scope: All 11 items + background daemon + login item
- Phasing: Two prompts (Phase A: Swift+JS, Phase B: build system)
- _drawsBackground: Yes, use it (on WKWebView, not WKWebViewConfiguration)
- KaTeX: Keep bundled in Phase A, lazy via code splitting in Phase B
- Daemon: Opt-in via menu toggle, Cmd+Q = hide (applicationShouldTerminate returns .terminateCancel)
- Login item: SMAppService, tied to keep-running setting
- Verification: OSSignposter + NSLog + before/after comparison
- Challenge: Prompt A 23 issues (all fixed), Prompt B 20 issues (all fixed)
- Artifacts: cold-start-prompt-A.md, cold-start-prompt-B.md
