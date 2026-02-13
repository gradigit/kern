# KernTextKit

A native macOS WYSIWYG Markdown editor built with AppKit + TextKit (no WebView).

Default Markdown dialect is **GitHub Flavored Markdown (GFM)** for compatibility. Kern-specific extensions are optional and configurable.

## Requirements

- macOS 14.0+
- Xcode 16+
- XcodeGen (`brew install xcodegen`)

## Build

```bash
xcodegen
xcodebuild -project KernTextKit.xcodeproj -scheme KernTextKit build
```

Run the built app:

```bash
open ~/Library/Developer/Xcode/DerivedData/KernTextKit-*/Build/Products/Debug/KernTextKit.app
```

Or build+run via script:

```bash
./scripts/run-kern-native.sh
```

## Open A File

```bash
open -a KernTextKit /path/to/file.md
```

## Testing

Unit tests (fast, no UI automation):

```bash
./scripts/test-native-editor.sh --unit-only
```

UI tests (requires macOS Automation permissions and an unlocked screen):

```bash
./scripts/test-native-editor.sh
```

## Notes

- This repo is the native TextKit rewrite. The legacy WebKit/CoreEditor implementation lives in the original `Kern` repo/worktree.
