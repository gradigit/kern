# CLAUDE.md

Guidance for working in this repository.

## What Is KernTextKit

KernTextKit is the primary Kern codebase: a native macOS WYSIWYG Markdown editor built with Swift + AppKit + TextKit (no WebView).

Primary goal: true WYSIWYG editing with deterministic Markdown round-trip (default: GFM, optional Kern extensions).

## Read First

1. AGENTS.md
2. docs/plans/native-editor-test-suite.md
3. docs/plans/markdown-spec-failure-tracker.md
4. docs/plans/native-editor-missing-features-implementation-plan.md
5. NATIVE-EDITOR-TEST-MATRIX.md

## Build And Run

```bash
./scripts/run-kern-native.sh test-fixtures/stress-test.md
```

Manual build:

```bash
xcodebuild -project KernTextKit.xcodeproj -scheme KernTextKit -configuration Debug -destination 'platform=macOS' build
```

## Test Commands

Fast unit tests:

```bash
./scripts/test-native-editor.sh --unit-only
```

Full default suite (unit + UI):

```bash
./scripts/test-native-editor.sh
```

Exhaustive suites:

```bash
./scripts/test-native-editor.sh --exhaustive
./scripts/test-native-editor.sh --unit-only --snapshots --exhaustive
./scripts/test-native-editor.sh --ui-only --exhaustive
```

Strict markdown conformance:

```bash
./scripts/test-markdown-spec-conformance.sh
```

## Key Code

- KernApp/Sources/App/main.swift: entry point and test-env overrides
- KernApp/Sources/App/AppDelegate.swift: app lifecycle, menus, save hooks
- KernApp/Sources/Editor/EditorDocument.swift: NSDocument load/save/autosave/reload
- KernApp/Sources/Editor/EditorWindowController.swift: window and tab setup
- KernApp/Sources/Editor/NativeEditorViewController.swift: native editor behavior and UI orchestration
- KernApp/Sources/Editor/NativeMarkdownCodec.swift: markdown import/export semantics
- KernApp/Sources/Editor/NativeMarkdownTextView.swift: text interaction and rendering behavior
- KernApp/Sources/Editor/MarkdownRichAttachments.swift: images/mermaid/math attachment rendering

## Session Learnings

- `kern://editor` is legacy WebKit routing (Kern-webkit), not TextKit.
- Memory-check loop that worked well:
  - open stress fixture + many tabs
  - sample RSS over time with `ps`
  - run `leaks <pid>` for leak report
- Native image cache is now bounded in MarkdownRichAttachments:
  - `NSCache.totalCostLimit = 128MB`
  - `NSCache.countLimit = 256`
  - `setObject(..., cost: estimatedImageCostBytes(...))`
- Packaging script avoids broad `rm -rf` patterns; use guarded directory deletion helper in `scripts/package-kern-app.sh`.

## Swift 6 Concurrency Notes

- EditorDocument is intentionally not `@MainActor`; NSDocument I/O can run off-main.
- UI/controller types are `@MainActor`.

## Working Rules

- Prefer fixing behavior via the native codec and attributed-text model, not markdown string hacks.
- Keep defaults fast and deterministic; gate optional behavior via preferences/env flags.
- Always check `git status --short` before starting to avoid mixing unrelated edits.
