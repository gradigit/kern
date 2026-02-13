# Quick Look Extension for Kern — Research

Can Kern replace QLmarkdown as the Finder preview app for `.md` files?

**Short answer**: Yes. Kern can bundle a Quick Look Preview Extension (`.appex`) that renders markdown in Finder's spacebar preview. It would be a separate rendering pipeline from the editor — simpler HTML output, no Milkdown/Crepe.

## How QLmarkdown Works

[sbarex/QLMarkdown](https://github.com/sbarex/QLMarkdown) is a host app + bundled Quick Look extension:

| Target | Purpose |
|--------|---------|
| `QLMarkdown.app` | Host app with settings UI |
| `Markdown QL Extension` (.appex) | Quick Look preview, lives in `QLMarkdown.app/Contents/PlugIns/` |
| `qlmarkdown_cli` | CLI for batch conversion |
| `external-launcher.xpc` | XPC service for opening links (sandbox workaround) |

**Rendering**: Parses markdown with `cmark-gfm` (C library), generates HTML, displays in WKWebView inside the Quick Look panel. Supports GFM tables, task lists, syntax highlighting, emoji, Mermaid, math.

**Limitations**: No control over window size/position — the Quick Look window is managed by the system. QLmarkdown can't remember window size because no Quick Look extension can. This is a macOS limitation, not a QLmarkdown bug.

## Quick Look Extension Architecture (macOS 12+)

Two APIs exist:

### QLPreviewProvider (Data-Based) — Recommended

- Subclass `QLPreviewProvider`, implement `providePreview(for:completionHandler:)`
- Return a `QLPreviewReply` with HTML data — the system renders it in its own WebKit view
- No WKWebView management needed, fewer sandbox issues
- `Info.plist`: set `QLIsDataBasedPreview = true`
- Available macOS 12 Monterey+

```swift
class PreviewProvider: QLPreviewProvider {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let markdown = try String(contentsOf: request.fileURL)
        let html = renderMarkdownToHTML(markdown) // cmark or swift-markdown
        let data = html.data(using: .utf8)!
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 600)) { _ in
            return data
        }
    }
}
```

CSS and images can be attached via `cid:` URLs in the HTML and `QLPreviewReplyAttachment`.

### QLPreviewingController (View-Based) — More Control

- Conform `NSViewController` to `QLPreviewingController`
- Implement `preparePreviewOfFile(at:completionHandler:)`
- Full control over view hierarchy — can embed WKWebView directly
- More sandbox complexity, WebKit first-responder issues
- Available macOS 10.15+

## What Kern Would Need

### New Extension Target

Add to `project.yml`:

```yaml
targets:
  KernQuickLook:
    type: app-extension
    platform: macOS
    deploymentTarget: "14.0"
    sources: KernApp/Extensions/QuickLook/
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.kern.app.QuickLook
      INFOPLIST_FILE: KernApp/Extensions/QuickLook/Info.plist
    entitlements:
      path: KernApp/Extensions/QuickLook/KernQuickLook.entitlements
```

### Info.plist for the Extension

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.quicklook.preview</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).PreviewProvider</string>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>QLIsDataBasedPreview</key>
        <true/>
        <key>QLSupportedContentTypes</key>
        <array>
            <string>net.daringfireball.markdown</string>
            <string>public.markdown</string>
        </array>
    </dict>
</dict>
```

### Markdown Parser

**Cannot use Milkdown/Crepe** — that requires a full JS runtime, too heavy for a Quick Look extension. Options:

| Parser | Language | Pros | Cons |
|--------|----------|------|------|
| [swift-markdown](https://github.com/swiftlang/swift-markdown) | Swift | Apple's own, pure Swift, SPM | No GFM tables/task lists out of the box |
| cmark-gfm | C | Full GFM support, battle-tested (used by GitHub) | C interop, need to wrap |
| [Ink](https://github.com/JohnSundell/Ink) | Swift | Fast, simple API | Limited feature set |

**Recommended**: `cmark-gfm` for feature parity with what Kern renders, or `swift-markdown` for simplicity.

### CSS Theme

Ship a static CSS file matching Kern's `kern.css` variables (light/dark). Attach to HTML via `cid:` URL or inline in `<style>` tag. The preview won't be pixel-identical to Kern's editor (no Milkdown component styling) but can match the typography and color palette.

## Key Constraints

### Things the Extension Cannot Do

- **Control window size or position** — managed entirely by Finder/QuickLookUIService
- **Persist state between invocations** — extension process is killed after preview closes
- **Access files beyond the previewed one** — sandbox only grants access to the target file
- **Open external URLs** — `NSWorkspace.shared.open()` fails in sandbox (QLMarkdown uses an XPC service workaround)
- **Use Kern's Milkdown rendering** — JS runtime too heavy, and WKWebView in extensions is fragile

### Things It Can Do

- **Share settings with Kern** via App Group / shared `UserDefaults(suiteName:)`
- **Match Kern's visual theme** via shared CSS
- **Render syntax-highlighted code blocks** via cmark-gfm + a highlight library
- **Render Mermaid diagrams** — but only if using WKWebView approach (not data-based HTML)
- **Set preview title** via `QLPreviewReply.title`

## Can Kern Be Faster Than QLmarkdown?

Potentially, for cold starts:

| Factor | QLmarkdown | Kern Extension |
|--------|------------|----------------|
| Parser | cmark-gfm (C, fast) | cmark-gfm or swift-markdown |
| Rendering | WKWebView (view-based) | Data-based HTML (system renders) |
| Features | Syntax highlight, Mermaid, math, emoji | Could be stripped to essentials |
| Cold start | ~2-3s first preview | Data-based may be faster (no WKWebView init) |

The data-based `QLPreviewReply` approach avoids WKWebView initialization overhead — the system handles rendering. This could shave time off cold starts compared to QLmarkdown's view-based approach.

However, **subsequent previews are fast regardless** — the extension process stays alive briefly between previews.

## Window Size Problem

QLmarkdown's window size issue is a macOS limitation:

> The Quick Look preview window is managed entirely by the system (Finder/QuickLookUIService). Extensions cannot influence the window frame, size, or position. `contentSize` in `QLPreviewReply` is a **hint**, not a command.

**Kern's Quick Look extension would have the same limitation.** No Quick Look extension can control or remember window size. The only workaround would be to not use Quick Look at all — instead make Kern the default "Open With" app for `.md` files, so spacebar opens nothing but double-click/Enter opens Kern directly.

## Registration

1. Bundle the `.appex` in `Kern.app/Contents/PlugIns/`
2. User launches Kern at least once — PlugInKit discovers the extension
3. Extension appears in **System Settings > Privacy & Security > Extensions > Quick Look**
4. User enables it (and disables QLmarkdown if installed)
5. Works in Finder even when Kern is not running

## Effort Estimate

- **Small**: Data-based HTML preview with `swift-markdown` + static CSS — basic rendering, no syntax highlighting or Mermaid. Good starting point.
- **Medium**: Add `cmark-gfm` for full GFM support + syntax highlighting via a Swift library.
- **Large**: View-based approach with WKWebView for Mermaid/math rendering + XPC for link opening.

## Decision: Worth Building?

**Pros**:
- Kern becomes a complete markdown tool (edit + preview)
- Can potentially be faster than QLmarkdown with data-based approach
- Single app to install instead of Kern + QLmarkdown
- Shared CSS theme between editor and preview

**Cons**:
- Window size limitation remains (same as QLmarkdown — this is macOS, not the app)
- Preview rendering will differ from editor rendering (no Milkdown)
- Adds build complexity (new target, parser dependency, entitlements)
- Maintenance burden for a feature that QLmarkdown already handles well

**Verdict**: Worth building as a "medium" effort if Kern is heading toward distribution. For personal use, QLmarkdown is fine — the window size issue won't be solved by switching.

---

## Part 2: Window Size, Performance, and Alternatives

### Is QLmarkdown As Fast As It Can Be?

Mostly yes, within Quick Look's architecture. The slowness comes from four compounding layers that are fundamental to Quick Look, not QLmarkdown-specific:

| Layer | Cost | Whose fault |
|-------|------|-------------|
| XPC process launch | ~50-100ms | macOS (extensions are out-of-process) |
| WebKit multi-process init | ~100-200ms | WebKit (UI + WebContent + Networking processes) |
| Sandbox/security checks | ~10-30ms | macOS |
| Markdown parse + HTML render | ~10-50ms | QLmarkdown (cmark-gfm is fast) |

The extension process is killed seconds after the preview closes, so nearly every spacebar press is a cold start. There is no API to keep the extension alive.

QLmarkdown could theoretically be faster if it used the data-based `QLPreviewReply` approach (letting the system render HTML instead of managing its own WKWebView). But the rendering layer is only ~20% of the total cold start time.

[Glance](https://github.com/chamburr/glance) is reported as faster than QLmarkdown — it's an all-in-one Quick Look extension that previews many formats. Worth trying as a drop-in replacement.

### Can Window Size/Position Be Controlled?

**From within a Quick Look extension**: Partially. [PreviewMarkdown](https://smittytone.net/previewmarkdown/) figured out how to hint at size from within the extension, offering small (42%), medium (50%), and large (75% of screen) options. It uses `QLPreviewReply`'s `contentSize` parameter more aggressively. But position is still system-controlled, and size is a hint not a guarantee.

**From outside via window managers**: The Quick Look panel is a `QLPreviewPanel` (subclass of `NSPanel` / `NSWindow`). It runs in `QuickLookUIService`, an XPC service, so its windows may be attributed to Finder in the window list. Options:

- **Hammerspoon**: Could detect the Quick Look window via `hs.window.filter.new(true):getWindows()` (which includes non-standard windows) or `hs.axuielement` querying Finder's accessibility tree. Then resize/reposition it. Fragile — the window might not appear in the standard window list.
- **yabai**: Could add a rule for `QuickLookUIService` floating windows with `--move abs:X:Y` and `--resize abs:W:H`. Whether yabai can "see" the window depends on `CGWindowList` visibility.
- **Accessibility API**: Since `QLPreviewPanel` is an `NSWindow` subclass, it exposes `AXPosition` and `AXSize` attributes. Direct `AXUIElement` calls could theoretically resize it. But system/sandboxed apps sometimes disallow programmatic movement.

**None of these approaches remember size across invocations.** You'd need a persistent daemon/script that detects Quick Look windows appearing and resizes them every time.

**No hidden defaults exist.** There is no `defaults write com.apple.finder QLPreviewSize` or equivalent. The only known Quick Look defaults key is `QLHidePanelOnDeactivate`.

### Alternative: Use Kern Itself Instead of Quick Look

This is the most promising approach. Instead of fighting Quick Look's limitations, bypass it entirely:

**How it works**: Intercept Finder's spacebar (or use a different hotkey), get the selected file, open it in Kern. Kern controls its own window — size, position, everything.

**Getting the Finder selection** (fast, ~5-10ms):
```bash
osascript -e 'tell application "Finder" to get POSIX path of (selection as alias)'
```

**Triggering options**:

| Method | Setup | Spacebar replacement? |
|--------|-------|-----------------------|
| **Karabiner-Elements** | Complex modification rule scoped to Finder | Yes — completely replaces spacebar in Finder |
| **Keyboard Maestro** | Finder-only macro group with spacebar trigger | Yes — intercepts and swallows the key |
| **Hammerspoon** | `hs.hotkey.bind` with Finder-frontmost check | No — uses a different hotkey (e.g. Cmd+Shift+Space) |

**Karabiner example** (replaces spacebar in Finder):
```json
{
  "conditions": [
    {"type": "frontmost_application_if", "bundle_identifiers": ["^com\\.apple\\.finder$"]}
  ],
  "from": {"key_code": "spacebar"},
  "to": [
    {"shell_command": "osascript -e 'tell app \"Finder\" to get POSIX path of (selection as alias)' | xargs open -a Kern"}
  ]
}
```

**Hammerspoon example** (Cmd+Shift+Space when Finder is active):
```lua
hs.hotkey.bind({"cmd", "shift"}, "space", function()
    local finder = hs.application.find("Finder")
    if finder and finder:isFrontmost() then
        local ok, path = hs.osascript.applescript(
            'tell app "Finder" to get POSIX path of (selection as alias)'
        )
        if ok and path then
            hs.task.new("/usr/bin/open", nil, {"-a", "Kern", path}):start()
        end
    end
end)
```

**Why this is better than any Quick Look approach**:
- Kern already has pre-warmed WKWebViews (EditorReusePool) — near-instant open
- Full window control — can set size, position, snap to left half
- Kern is already running (or can run as `LSUIElement` background app with no dock icon)
- The file opens in the full WYSIWYG editor, not a degraded preview
- No second rendering pipeline to maintain

**What Kern would need for this use case**:
- A "preview mode" or "read-only mode" flag (optional — could just open normally)
- `LSUIElement` support to run in background without a dock icon (optional)
- A way to snap the window to left-half on open — a few lines in `EditorWindowController`:
  ```swift
  if let screen = NSScreen.main {
      let frame = NSRect(
          x: screen.visibleFrame.minX,
          y: screen.visibleFrame.minY,
          width: screen.visibleFrame.width / 2,
          height: screen.visibleFrame.height
      )
      window.setFrame(frame, display: true)
  }
  ```

### Recommendation

1. **Short term**: Try [Glance](https://github.com/chamburr/glance) as a faster QLmarkdown alternative. If the rendering quality is acceptable, it solves the speed problem without any work.

2. **Medium term**: Set up a Hammerspoon hotkey (or Karabiner spacebar override) that opens the selected Finder file in Kern. This gives you instant preview with full window control. Kern already launches fast with its pre-warmed WebView pool.

3. **Skip building a Quick Look extension** unless Kern is being distributed to other users who expect spacebar preview to work. For personal use, the Hammerspoon/Karabiner approach is superior in every way — faster, controllable window, full editor instead of degraded preview.
