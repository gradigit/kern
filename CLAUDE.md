# CLAUDE.md

Guidance for working in this repository.

## What Is KernTextKit

KernTextKit is a native macOS WYSIWYG Markdown editor built with Swift + AppKit + TextKit (no WebView).

Primary goal: **true WYSIWYG** editing with deterministic Markdown round-trip (default: **GFM**, with optional Kern extensions).

This repo is the TextKit rewrite. The legacy WebKit/CoreEditor implementation lives in the original `Kern` repo/worktree.

## Build

```bash
xcodegen
xcodebuild -project KernTextKit.xcodeproj -scheme KernTextKit build
open ~/Library/Developer/Xcode/DerivedData/KernTextKit-*/Build/Products/Debug/KernTextKit.app
```

Open a file:

```bash
open -a KernTextKit /path/to/file.md
```

## Testing

Unit tests only:

```bash
./scripts/test-native-editor.sh --unit-only
```

Unit + UI tests (UI requires Automation permissions + unlocked screen):

```bash
./scripts/test-native-editor.sh
```

## Key Code

- `KernApp/Sources/App/main.swift`: entry point + perf logs + env-driven preferences for tests
- `KernApp/Sources/App/AppDelegate.swift`: programmatic menu bar + save hooks (flush export)
- `KernApp/Sources/Editor/EditorDocument.swift`: NSDocument I/O + autosave + file-change reload
- `KernApp/Sources/Editor/EditorWindowController.swift`: NSWindow setup for document windows/tabs
- `KernApp/Sources/Editor/NativeEditorViewController.swift`: TextKit editor UI + input rules + find/replace + code copy button
- `KernApp/Sources/Editor/NativeMarkdownCodec.swift`: Markdown import/export + round-trip attributes

## Swift 6 Concurrency Notes

- `EditorDocument` is not `@MainActor` (NSDocument I/O can run off-main). It uses `@preconcurrency import AppKit` + `nonisolated init`.
- UI/controller types are `@MainActor`.

## Repo Rules Of Thumb

- Prefer fixing behavior via the codec (import/export) over string hacks.
- Keep the default path fast: GFM defaults, optional extensions behind preferences.
- Avoid UI-test-only logic in production code; prefer env-driven preferences for determinism.
