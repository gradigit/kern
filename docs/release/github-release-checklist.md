# GitHub release checklist for the unsigned DMG

This checklist is for maintainers preparing a GitHub release that includes the current unsigned Kern DMG.

For the canonical contributor-vs-release validation split, see [Kern release validation gate](release-validation-gate.md).

## Preconditions

- use a clean release worktree
- confirm the [Kern release validation gate](release-validation-gate.md) has passed
- make sure the release notes do not claim signing or notarization
- make sure `gh` is available for the maintainer upload/download verification steps

## Build the release artifacts

```bash
./scripts/package-kern-app.sh
```

Expected outputs:

- `dist/Kern.app`
- `dist/Kern-macOS-Release.dmg`
- `dist/Kern-macOS-Release.dmg.sha256`

## Verify the local artifact

Packaged app smoke test:

```bash
./scripts/test-kern-app.sh --packaged --skip-build
```

Checksum:

```bash
(cd dist && shasum -a 256 -c Kern-macOS-Release.dmg.sha256)
```

Quick mount inspection:

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

Signing/trust inspection:

```bash
codesign -dvvv --entitlements :- dist/Kern.app
spctl --assess --type execute -vv dist/Kern.app || true
plutil -p dist/Kern.app/Contents/Info.plist
```

Expected current posture:

- ad-hoc signed
- no Apple team identity
- not notarized
- not a trusted notarized distribution artifact

## Release body template

Use wording equivalent to the following:

````md
## Binary download

This release may include these binary assets:

- `Kern-macOS-Release.dmg`
- `Kern-macOS-Release.dmg.sha256`

The binary from this repository is currently unsigned and not notarized.

## Verify the download

```bash
shasum -a 256 -c Kern-macOS-Release.dmg.sha256
```

## Install

1. Open the DMG
2. Drag `Kern.app` into `Applications`
3. Launch `Kern.app` from `Applications`

If macOS blocks first launch:

1. Right-click `Kern.app` and choose `Open`
2. If needed, use **System Settings → Privacy & Security → Open Anyway**

## Build from source

If you prefer not to use the binary download, see [Building Kern from source](building-kern-from-source.md).
````

## Upload the assets

Upload both files to the GitHub release:

- `dist/Kern-macOS-Release.dmg`
- `dist/Kern-macOS-Release.dmg.sha256`

## Bind the published asset to the reviewed digest

After upload, verify the published DMG against the recorded local SHA-256 sidecar:

```bash
./scripts/verify-github-release-asset.sh <tag>
```

Defaults:

- asset name: `Kern-macOS-Release.dmg`
- SHA sidecar: `dist/Kern-macOS-Release.dmg.sha256`
- repo: derived from `origin`

Archive the successful verification output with the release evidence. The release is not complete until the downloaded published asset matches the recorded digest.
