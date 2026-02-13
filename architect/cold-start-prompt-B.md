# Cold Start Optimization — Phase B: Build System Overhaul

Replace `vite-plugin-singlefile` with standard Vite code splitting + extend `EditorSchemeHandler` to serve JS chunks from the app bundle. This reduces HTML size from ~5MB to ~50-100KB and enables JSC bytecode caching for the main JS bundle.

**Prerequisite:** Phase A must be complete and all tests passing. Phase B changes the build pipeline — the committed `CoreEditor/dist/` output format changes from a single HTML file to a directory of files.

Read `architect/cold-start-optimization.md` — the "Vite Build Splitting for WKWebView" and "MarkEdit Reference Patterns > EditorChunkLoader" sections have the verified research for this phase.

## Prerequisite Verification

Before starting any implementation, verify Phase A is complete:

1. Run all 36 Playwright tests: `cd CoreEditor && npx playwright test` — all must pass
2. Build and run Kern: `xcodegen && xcodebuild -project Kern.xcodeproj -scheme Kern build` — must succeed
3. Verify Phase A baseline timing exists in `test-results/baseline-timing.txt`
4. Verify CrepeBuilder migration is done (main.ts imports from `@milkdown/crepe/builder`)

If any of these fail, fix Phase A first. Do not proceed.

## Pre-Implementation

Capture timing baseline with Phase A optimizations (should be in `test-results/baseline-timing.txt` from Phase A — add a Phase A baseline if not present). Build Release and measure 5 runs.

## What Changes

### Current state (after Phase A)
- `vite-plugin-singlefile` inlines everything into one `CoreEditor/dist/index.html` (~4.5-5MB after Phase A CrepeBuilder migration)
- All JS, CSS, fonts, and lazy chunks (mermaid ~2.8MB as base64) are inside the HTML
- `EditorSchemeHandler` serves this single file on `kern://editor/`
- WKWebView loads `kern://editor/index.html`

### Target state
- Vite outputs standard build: `index.html` + `app-[hash].js` + `chunks/` directory
- `EditorSchemeHandler` serves ALL files from `CoreEditor/dist/` via `kern://editor/*`
- HTML is ~50-100KB (just the shell + `<script src>` tag)
- Main JS bundle is ~500-800KB (entry point + critical path)
- Lazy chunks (mermaid as single chunk, KaTeX, CodeMirror languages) load on demand via scheme handler
- External `<script src="/app-[hash].js">` may enable JSC bytecode disk cache

## Implementation

### Step 1: ES Module Go/No-Go Test

**This step determines the entire approach. Do it first before any other work.**

Vite outputs `<script type="module" src="...">`. WKWebView may block ES modules loaded from non-standard URL scheme origins.

**Quick test:** Create a minimal test to verify ES modules work via `kern://` scheme:

1. Temporarily modify the Vite config to remove `vite-plugin-singlefile` and build
2. Load `kern://editor/index.html` in WKWebView
3. Check the console for module-related errors (e.g., "Blocked loading module", CORS errors)

**If ES modules work via `kern://` (expected — MarkEdit uses `chunk-loader://` successfully):** Proceed with the remaining steps.

**If ES modules are blocked, use this fallback Vite config:**
```typescript
rollupOptions: {
  output: {
    format: "iife",
    inlineDynamicImports: true,  // Required for IIFE
  },
}
```
This produces a single JS file (no code splitting) but still external (not inlined in HTML). HTML stays small, bytecode caching still possible, just no lazy chunks. Skip the `manualChunks` config in Step 2 if using this fallback.

**Do not proceed with Steps 2-6 until this go/no-go is resolved.**

### Step 2: Update Vite Config

**File:** `CoreEditor/vite.config.mts`

Remove `vite-plugin-singlefile`. Replace with:

```typescript
import { defineConfig } from "vite";

export default defineConfig({
  base: "/",
  build: {
    target: "safari17",     // macOS 14 = Safari 17
    outDir: "dist",
    assetsInlineLimit: 0,   // Don't inline anything as base64
    assetsDir: "chunks",
    rollupOptions: {
      output: {
        assetFileNames: "chunks/[name]-[hash][extname]",
        chunkFileNames: "chunks/[name]-[hash].js",
        entryFileNames: "app-[hash].js",
        manualChunks: {
          mermaid: ["mermaid"],
        },
      },
    },
  },
  // ... keep existing resolve.alias and other config if present
});
```

**Why `base: "/"`:** The page loads at `kern://editor/index.html`. URLs like `/app-ABC.js` resolve to `kern://editor/app-ABC.js` — the scheme handler receives path `/app-ABC.js` and maps it directly to `dist/app-ABC.js`. No path prefix stripping needed.

**Why `manualChunks`:** Without this, Rollup splits mermaid (~2.8MB) into 100+ tiny chunks. `manualChunks` consolidates the entire `mermaid` package into a single lazy chunk. This reduces file count and avoids excessive scheme handler requests on first mermaid render.

**Remove from package.json:** `cd CoreEditor && npm uninstall vite-plugin-singlefile`

### Step 3: Extend EditorSchemeHandler

**File:** `KernApp/Sources/Bridge/EditorSchemeHandler.swift`

Currently serves a single HTML file from memory. Extend to serve any file from `CoreEditor/dist/` on disk:

```swift
import WebKit
import UniformTypeIdentifiers

final class EditorSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {

    static let scheme = "kern"
    static let editorURL = URL(string: "kern://editor/index.html")!

    /// Base directory for editor files in the app bundle
    private var distURL: URL? {
        Bundle.main.url(forResource: "dist", withExtension: nil)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let distURL = distURL else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        // url.path returns the path component (e.g., "/app-ABC.js", "/chunks/mermaid-XYZ.js")
        // Default to index.html for empty path or root
        var filePath = url.path
        if filePath.isEmpty || filePath == "/" {
            filePath = "/index.html"
        }

        // Strip leading slash for file lookup
        let relativePath = String(filePath.dropFirst())
        let fileURL = distURL.appendingPathComponent(relativePath)

        // Security: ensure the resolved path is within dist/
        let distPrefix = distURL.standardizedFileURL.path + "/"
        guard fileURL.standardizedFileURL.path.hasPrefix(distPrefix) else {
            NSLog("[SchemeHandler] Path traversal blocked: %@", filePath)
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            NSLog("[SchemeHandler] File not found: %@", relativePath)
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let mimeType = Self.mimeType(for: fileURL)

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": "\(data.count)",
            ]
        ) else {
            urlSchemeTask.didFailWithError(URLError(.unknown))
            return
        }

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // No-op — all responses are synchronous
    }

    private static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "html": return "text/html"
        case "js", "mjs": return "application/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default:
            if let utType = UTType(filenameExtension: ext) {
                return utType.preferredMIMEType ?? "application/octet-stream"
            }
            return "application/octet-stream"
        }
    }
}
```

Key changes from current implementation:
- **`@unchecked Sendable`** — kept from current code (all responses are synchronous, no mutable state after init)
- **`HTTPURLResponse`** instead of `URLResponse` — provides status codes and proper headers, which WebKit may need for ES module CORS handling
- **File-based serving** — reads from disk on each request instead of caching HTML data in memory. Bundle files are already in the OS page cache, so this is fast
- **Path traversal protection** — `distPrefix` uses trailing `/` to prevent `dist-evil/` style bypasses
- **`.mjs` MIME type** — some bundlers output `.mjs` files
- **`import UniformTypeIdentifiers`** — needed for the UTType fallback in the default MIME type case

**Remove:** The `loadHTML()` method and `htmlData` property — no longer needed.

**Update callers:** Remove the `schemeHandler.loadHTML()` call from `AppDelegate.applicationDidFinishLaunching` (or wherever it's called during warm-up). The scheme handler now reads files on demand.

### Step 4: Update project.yml

The `CoreEditor/dist` folder resource needs to include all files, not just `index.html`.

**File:** `project.yml`

The existing config should already include `CoreEditor/dist` as a folder resource. Verify it uses folder reference (blue folder in Xcode) not group reference — folder reference includes all files recursively. Run `xcodegen` after any changes.

### Step 5: Update .gitignore and committed output

Previously, only `CoreEditor/dist/index.html` was committed. Now `CoreEditor/dist/` contains multiple files.

**Decision:** Continue committing `CoreEditor/dist/` to the repo. The directory will contain:
- `index.html` (~50-100KB)
- `app-[hash].js` (~500-800KB)
- `chunks/` directory with lazy chunks (mermaid ~2.8MB as single file, plus smaller chunks)

This is larger in file count but smaller in total size (no base64 encoding overhead). The git diff will be noisier but the build stays simple (no npm build step in Xcode).

### Step 6: Build and Test

1. Uninstall singlefile plugin: `cd CoreEditor && npm uninstall vite-plugin-singlefile`
2. Update `vite.config.mts` as described in Step 2
3. Build: `cd CoreEditor && npm run build`
4. Verify dist/ output: should have `index.html`, `app-[hash].js`, and `chunks/` directory
5. Check that mermaid is a single chunk (not 100+ files): `ls CoreEditor/dist/chunks/ | wc -l` — should be <20 files
6. Test in dev mode: `cd CoreEditor && npm run dev` — verify editor works in Safari
7. Build Xcode: `xcodegen && xcodebuild -project Kern.xcodeproj -scheme Kern build`
8. Run Kern from terminal and verify editor loads correctly via scheme handler
9. Check console for errors (especially module loading, CORS, or 404 errors)
10. Run all 36 Playwright tests: `cd CoreEditor && npx playwright test`
11. Run integration test: `./scripts/test-kern-app.sh --skip-build`

### Step 7: Verify Bytecode Caching (Optional Investigation)

After code splitting works, test if JSC caches the external script:

1. Open a file in Kern (first load — JS must be compiled)
2. Close the document, open another file (second load — should use cache)
3. Compare `performance.now()` timing between first and second load
4. If the second load is significantly faster (~50-150ms), bytecode caching is working

If caching doesn't work with `kern://` scheme, the other benefits of code splitting (smaller HTML, lazy chunks) still apply.

## Rollback Plan

If code splitting causes issues in WKWebView (module loading, CORS, etc.):

1. Keep the new `EditorSchemeHandler` (serves multiple files — strictly more capable)
2. Revert `vite.config.mts` to use IIFE format with `inlineDynamicImports: true`
3. This produces a single JS file (no code splitting) but still external (not inlined)
4. HTML stays small, bytecode caching still possible, just no lazy chunks

## Success Criteria

- HTML size reduced from ~5MB to <200KB
- Total dist/ size reduced (no base64 encoding overhead)
- All 36 Playwright tests pass
- Kern loads correctly with code-split output
- Mermaid lazy loading still works (single chunk loads on demand via scheme handler)
- LaTeX rendering still works (KaTeX loads as separate chunk)
- No regressions: all Phase A optimizations still effective
- Cold start time reduced by additional 30-150ms compared to Phase A baseline
