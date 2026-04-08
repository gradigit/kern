# Kern

Kern is a native macOS WYSIWYG Markdown editor. You open a local `.md` file and edit rendered content directly, without living in raw markdown syntax.

This repository is the Kern codebase. The editor is built with AppKit + TextKit and does not use a WebView.

The product and app name are **Kern**.

## Why Kern Exists

Most local markdown workflows break down in one of these ways:

- You get a preview pane, but editing still happens in raw syntax.
- You get a rich editor, but it wants a project/workspace model instead of opening plain files.
- You get a web stack wrapped in desktop chrome, with bridge and runtime edge cases.

Kern is built for a simpler workflow: open any local markdown file, edit in true WYSIWYG, save back to deterministic markdown.

## What Kern Does Today

- True WYSIWYG as the default editing mode.
- GFM-first markdown behavior, with optional Kern extensions.
- Deterministic import/export via native markdown codec.
- Checkboxes in multiple forms (standalone, bulleted tasks, ordered tasks, heading tasks).
- Native code block chrome (language pill + copy affordance).
- Native rendering paths for images, Mermaid, and math.
- File watching, autosave, and standard macOS window/tab behavior.

## Quick Start (Open a Markdown File)

If you have built or installed the app bundle, open a markdown file with:

Open a markdown file in Kern:

```bash
open -a Kern /absolute/path/to/file.md
```

Optional shell helper:

```bash
kern() { open -a Kern "$@"; }
```

## Install From a GitHub Release

When a tagged release includes binary assets, download:

- `Kern-macOS-Release.dmg`
- `Kern-macOS-Release.dmg.sha256`

Check release-asset integrity:

```bash
shasum -a 256 -c Kern-macOS-Release.dmg.sha256
```

This only proves the downloaded DMG matches the published checksum sidecar from the same GitHub release. It does **not** authenticate publisher identity the way Apple signing/notarization would. If you want the stronger-trust path, build Kern from source instead.

Then:

1. open the DMG
2. drag `Kern.app` into `Applications`
3. launch `Kern.app` from `Applications`

Because the binary from this repository is currently unsigned and not notarized, macOS may block first launch. If that happens:

1. right-click `Kern.app` and choose `Open`
2. if needed, open **System Settings → Privacy & Security** and use **Open Anyway**

Detailed binary-install instructions live in [the GitHub release install guide](docs/release/installing-kern-from-github-release.md). The canonical public release gate lives in [Kern release validation gate](docs/release/release-validation-gate.md).

## Build And Run From Source

Requirements:

- macOS 14+
- Xcode 26.2+
- XcodeGen (`brew install xcodegen`)

CI is pinned to Xcode 26.x because the GitHub Actions default Xcode can lag behind the toolchain this repo currently requires.

Build:

```bash
xcodegen
xcodebuild -project KernTextKit.xcodeproj -scheme KernTextKit -configuration Debug -destination 'platform=macOS' build
```

Build + run with fixture:

```bash
./scripts/run-kern-native.sh test-fixtures/stress-test.md
```

Dedicated source-build instructions live in [the source-build guide](docs/release/building-kern-from-source.md).

## Test Commands

Fast unit tests:

```bash
./scripts/test-native-editor.sh --unit-only
```

Full default suite:

```bash
./scripts/test-native-editor.sh
```

Exhaustive lanes:

```bash
./scripts/test-native-editor.sh --unit-only --exhaustive
./scripts/test-native-editor.sh --unit-only --snapshots --exhaustive
```

Strict markdown spec conformance (CommonMark/GFM lane):

```bash
./scripts/test-markdown-spec-conformance.sh
```

Orchestrated exhaustive gate:

```bash
./scripts/run-exhaustive-native-suite.sh
```

Notes:

- Exhaustive lanes are intentionally strict and slower.

## Packaging From Source

Build the local development artifacts:

```bash
./scripts/package-kern-app.sh
```

This currently produces an unsigned app bundle and DMG for local development and evaluation.

It also writes the matching SHA-256 sidecar for the DMG.
The packager regenerates `KernTextKit.xcodeproj` via XcodeGen before building.

Maintainer-facing release publication steps live in [the GitHub release checklist](docs/release/github-release-checklist.md). The canonical release gate is defined in [Kern release validation gate](docs/release/release-validation-gate.md).

Signed/notarized macOS distribution is not published from this repository.

## Documentation Map

- [docs/plans/native-editor-test-suite.md](docs/plans/native-editor-test-suite.md)
- [docs/plans/markdown-spec-failure-tracker.md](docs/plans/markdown-spec-failure-tracker.md)
- [docs/plans/native-editor-missing-features-implementation-plan.md](docs/plans/native-editor-missing-features-implementation-plan.md)
- [docs/release/installing-kern-from-github-release.md](docs/release/installing-kern-from-github-release.md)
- [docs/release/building-kern-from-source.md](docs/release/building-kern-from-source.md)
- [docs/release/github-release-checklist.md](docs/release/github-release-checklist.md)
- [docs/release/release-validation-gate.md](docs/release/release-validation-gate.md)
- [docs/release/unsigned-dmg-security-posture.md](docs/release/unsigned-dmg-security-posture.md)
- [docs/release/public-repo-health.md](docs/release/public-repo-health.md)
- [NATIVE-EDITOR-TEST-MATRIX.md](NATIVE-EDITOR-TEST-MATRIX.md)
- [KERN-MARKDOWN.md](KERN-MARKDOWN.md)

## Current Focus Areas

- Task permutation and GFM/Kern profile behavior
- Ordered task numbering semantics
- Heading checkbox behavior
- Code block chrome interactions
- Image attachment edge cases
- Mermaid and math layout quality
- Anchor navigation behavior
- Find/replace overlay non-obstruction
- Exhaustive real-typing behavior

## Contributing

See:

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)
- [SUPPORT.md](SUPPORT.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)

If you want to contribute:

1. Open an issue first for larger behavior or architecture changes.
2. Keep changes aligned with the native test-suite plan documents.
3. Run at least `./scripts/test-native-editor.sh --unit-only` before opening a PR.

For review requests, include failing/passing test evidence and any snapshot or UI artifacts that explain behavior changes.

## Status

- Kern is the current native macOS app codebase.
- This repository is a public source project. Tagged releases may include an unsigned DMG plus checksum, but signed/notarized macOS distribution is not published from this repository.
- This repository is licensed under **Apache-2.0**.
- Open-source release hardening is active. Performance work and product hardening are still in progress.
