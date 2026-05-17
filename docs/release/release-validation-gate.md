# Release validation gate for unsigned DMG releases

This document defines the current release gate for Kern's public GitHub-hosted macOS binary path.

It separates:
- the **contributor baseline** enforced by CI
- the **release-only maintainer validation** required before a GitHub release is considered valid

## Scope of this gate

This gate applies to the current public release model:
- a GitHub-hosted `Kern-macOS-Release.dmg`
- a matching `Kern-macOS-Release.dmg.sha256`
- an unsigned, not-notarized macOS app

This gate does **not** require:
- Apple signing or notarization
- Homebrew support
- the deferred full-fidelity benchmark goal

## Contributor baseline enforced by CI

The contributor baseline is the PR/main gate. CI currently enforces these commands:

```bash
./scripts/test-native-editor.sh --unit-only
./scripts/test-markdown-spec-conformance.sh
./scripts/run-typing-behavior-gate.sh --lane pr
cd scripts/kern-bench && swift test -c release
```

These checks answer the question:

> Is the current tree healthy enough to merge as source code?

## Release-only maintainer validation

These checks are **not** part of the contributor PR baseline.

They are release-only because they depend on:
- locally generating the release artifact
- inspecting the packaged DMG
- and, after upload, verifying the published GitHub release asset against the recorded digest

Run these before calling a GitHub release ready:

### 1. Build the local release artifacts

```bash
./scripts/package-kern-app.sh
```

Expected outputs:
- `dist/Kern.app`
- `dist/Kern-macOS-Release.dmg`
- `dist/Kern-macOS-Release.dmg.sha256`

### 2. Smoke-test the packaged app bundle

```bash
./scripts/test-kern-app.sh --packaged --skip-build
```

This checks the packaged `dist/Kern.app` path rather than only a Debug launch from DerivedData.

### 3. Verify the local checksum

```bash
(cd dist && shasum -a 256 -c Kern-macOS-Release.dmg.sha256)
```

### 4. Inspect the DMG contents

```bash
TMP_MOUNT_ROOT="$(mktemp -d /tmp/kern-release-mount.XXXXXX)"
ATTACH_OUT="$(hdiutil attach -nobrowse -readonly -mountroot "$TMP_MOUNT_ROOT" dist/Kern-macOS-Release.dmg)"
MOUNT_POINT="$(printf '%s\n' "$ATTACH_OUT" | awk -F '\t' 'NF>=3 { print $3 }' | tail -n 1)"
ls -la "$MOUNT_POINT"
hdiutil detach "$MOUNT_POINT"
rmdir "$TMP_MOUNT_ROOT"
```

Expected mount contents:
- `Kern.app`
- `Applications` symlink

### 5. Inspect signing and trust posture

Inspect the packaged app directly:

```bash
codesign -dvvv --entitlements :- dist/Kern.app
spctl --assess --type execute -vv dist/Kern.app || true
plutil -p dist/Kern.app/Contents/Info.plist
```

For the current unsigned GitHub DMG path, the expected posture is:

- the app is ad-hoc signed for local packaging
- no Apple team identity is embedded
- the app is not notarized
- Gatekeeper/trust assessment is expected to show that this is **not** a trusted notarized distribution artifact

Treat these commands as an inspection step, not as a notarization gate for the current public release model.

### 6. Verify the uploaded release asset after publication

After uploading the DMG to a GitHub release, verify the published asset matches the recorded digest:

```bash
./scripts/verify-github-release-asset.sh <tag>
```

This step is required to bind the reviewed local artifact to the downloaded published asset.

## Release-ready conditions

For the current unsigned DMG path, a GitHub release is ready only if **all** of the following are true:

1. the contributor baseline is green
2. the local packager produced the expected DMG and SHA sidecar
3. the packaged app smoke test passed
4. the local checksum passed
5. the DMG mount contents are correct
6. the signing/trust inspection matches the documented current posture:
   - ad-hoc signed
   - not notarized
   - not a trusted notarized distribution artifact
7. the release notes and install docs clearly state:
   - the app is unsigned
   - the app is not notarized
   - macOS may block first launch
   - the documented override path is Finder `Open`, then **Privacy & Security → Open Anyway** if needed
8. after upload, the published DMG matches the recorded SHA-256 digest

## Related docs

- [Installing Kern from a GitHub release](installing-kern-from-github-release.md)
- [Building Kern from source](building-kern-from-source.md)
- [GitHub release checklist](github-release-checklist.md)
