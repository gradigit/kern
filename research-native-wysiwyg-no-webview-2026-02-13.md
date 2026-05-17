# Research: Native macOS WYSIWYG Markdown Editor Engine (No WebView)

> Historical research note retained for reference. It is not part of the active contributor quick-start path.

Date: 2026-02-13
Depth: Full

## Executive Summary

You can build a true WYSIWYG Markdown editor on macOS without embedding a WebView, but the fastest realistic path is to keep the editor surface on Apple's text system (TextKit 2 via AppKit) and implement a Markdown-aware document model + serializer yourself.

Recommended language split:
- Swift/Objective-C for the editing surface (TextKit 2, IME, accessibility, undo, clipboard).
- Optional Rust/C for Markdown parsing/serialization and other pure compute tasks.

Rendering:
- LaTeX math is tractable without WebView using native renderers (SwiftMath/iosMath) and/or JavaScriptCore (MathJax -> SVG).
- Mermaid is the hardest requirement: upstream Mermaid assumes a real DOM + layout engine, so "JavaScriptCore only" is typically insufficient for full Mermaid fidelity. Practical workarounds are (a) headless browser rendering out-of-process with caching, or (b) a DOM-free Mermaid-compatible renderer for a subset of diagram types while you build native support incrementally.

Confidence: High on language/editor-surface recommendation, medium-high on math pipeline options, medium on Mermaid options (requires prototyping to confirm fidelity/performance tradeoffs).

## Sub-Questions Investigated

1. What language/stack is best for a native macOS WYSIWYG editor surface with good IME + accessibility?
2. How can we render LaTeX math without WebView (MVP and long-term)?
3. How can we render Mermaid without WebView (MVP and long-term)?
4. What would it take to build the entire engine from scratch in Rust/C++ (no JS), and what are the best primitives today?
5. What already exists (WYSIWYG Markdown editors), and what tech do they use?

## Detailed Findings

### 1) Editor Surface: Swift/AppKit + TextKit 2 is the shortest path to "native-quality"

Key facts:
- TextKit 2 is Apple's modern text system and is used by default for text controls on macOS Ventura (and later). It enables more modern text layout and introduces attachment APIs that can host UI in-text. (WWDC "Meet TextKit 2")
- TextKit 2 supports rich text attachments that can be interactive and handle events at the attachment level (useful for checkboxes, inline widgets, and potentially math/diagram blocks).

Implication:
- If you want a macOS-native WYSIWYG editing experience (especially Korean IME correctness + accessibility), you want to lean on NSTextView/TextKit rather than implement your own text input/editing stack from rendering primitives.

Practical building blocks:
- NSTextView + TextKit 2 directly.
- STTextView (open source) is an NSTextView replacement built on TextKit 2 that may be a useful reference or foundation.

### 2) Markdown Model and Round-Trip: .md-only requires an explicit contract

There are two viable contracts for ".md-only":
- Canonicalize on save: parse Markdown -> internal model -> serialize back to a stable, deterministic Markdown format.
- Preserve formatting: retain original trivia/whitespace and source locations. This is much harder and usually not worth it for an editor that already normalizes.

Parsing options:
- swift-markdown (Apple open source) provides a Markdown AST in Swift.
- cmark-gfm (GitHub) is a mature C parser for GitHub Flavored Markdown (GFM).
- Foundation/AppKit can import Markdown into attributed strings, but this does not solve "semantic editing" or guaranteed round-trip for all Markdown constructs (tables, tasks, etc.); treat it as a helper, not the core.

### 3) LaTeX Math Without WebView

MVP options (no WebView):
- JavaScriptCore + MathJax -> SVG: run MathJax in a JS runtime and convert TeX to SVG, then render SVG natively (often via rasterization to CGImage for speed). MathJax is designed to output SVG and has headless/server rendering patterns. There is an existing Swift wrapper (MathJaxSwift) that runs MathJax in JavaScriptCore and exposes tex2svg/tex2mml style conversions.
- Native math renderer: iosMath (Objective-C) and SwiftMath (Swift port) render LaTeX math-mode to a native view/drawing pipeline on iOS/macOS. This avoids any JS runtime.

Long-term:
- Prefer native rendering (SwiftMath/iosMath) for performance and tight integration (baseline alignment, selection behavior, efficient redraw).
- Keep MathJax-in-JSCore as a compatibility fallback (unsupported commands/macros) and for export.

Notes on KaTeX:
- KaTeX is fast, but its primary output is HTML/MathML; without a DOM/CSS renderer, it's awkward compared to MathJax SVG or native renderers.

### 4) Mermaid Without WebView

This is the hardest part of the "no WebView" vision.

Reality check:
- Mermaid's upstream renderer is "browser code": it assumes DOM primitives and its own docs note that JSDOM-based tests cannot validate layout because JSDOM has no rendering engine.

Workaround options:
- Out-of-process headless browser rendering (highest fidelity):
  - Use mermaid-cli (Puppeteer + headless Chrome) or a similar Playwright-based renderer to convert Mermaid text to SVG/PNG, then display the result in the native editor.
  - Keep a single renderer instance warm, cache by (diagramTextHash + config/theme + rendererVersion), and render asynchronously.
  - Security: lock Mermaid securityLevel to strict; cap size; hard timeouts; block network.
- DOM-free Mermaid-compatible rendering (lower fidelity / partial coverage):
  - "beautiful-mermaid" is a DOM-free, pure TypeScript Mermaid-compatible renderer that supports a limited set of diagram types (Flowcharts, State, Sequence, Class, ER) and outputs SVG/ASCII. This can run in JavaScriptCore without a DOM.
  - Strategy: use a subset renderer for interactive preview, and fall back to headless upstream Mermaid for unsupported diagrams and export.
- Fully native Mermaid (highest effort):
  - Parse Mermaid syntax and implement per-diagram layout/rendering (graphs, sequence diagrams, timelines, etc.). Supporting the full Mermaid surface area is a multi-year effort.

SVG portability:
- Mermaid output can include <foreignObject> depending on configuration; many non-browser SVG renderers struggle with this. Prefer disabling htmlLabels when targeting native SVG renderers, or render to PNG.

### 5) Fully Native From Scratch (No JS) in Rust/C++

Rust:
- Parley: promising rich text layout library; includes some editing primitives (selection/caret geometry, IME preedit modeling), but it is not a full rich document editor.
- Vello: GPU 2D renderer. Great for drawing, not an editor.
- cosmic-text: strong text shaping/layout primitives, still not a full rich document editor.
- GPUI (Zed): high-performance UI framework, but Zed is a code editor and does not provide a WYSIWYG Markdown editor component.

C++:
- Skia's skparagraph provides paragraph layout and hit-testing primitives, not a full editing widget.
- Qt QTextEdit/QTextDocument can import/export Markdown and provides a rich text widget; it is the shortest path in C++ but is not "macOS-native" (large framework) and Markdown round-trip constraints apply.

Conclusion:
- A from-scratch engine is primarily an IME + accessibility + selection correctness project, not a "fast rendering language" project.

### 6) Existing Editor Landscape

True WYSIWYG Markdown editors exist (e.g., Typora markets itself as WYSIWYG), but the successful ones almost always rely on web tech (Electron/WebView) for the editing surface.

Open-source:
- MarkText is open source and Electron-based.

macOS-native without web tech:
- Strong evidence suggests this category is effectively empty for "true WYSIWYG + Markdown file output + modern features (tables, tasks, math, mermaid)"; native apps tend to be either source editors or use proprietary storage models.

## Hypothesis Tracking

| Hypothesis | Confidence | Supporting Evidence | Contradicting Evidence |
|-----------|------------|---------------------|------------------------|
| H1: Best editor-surface language is Swift/AppKit + TextKit 2 | High | Apple TextKit 2 direction; native IME/a11y expectations | None meaningful for macOS-only |
| H2: LaTeX can be rendered well without WebView using native libs or JSCore | High | iosMath/SwiftMath exist; MathJax supports SVG output and headless operation | Some TeX macro compatibility gaps |
| H3: Full Mermaid fidelity without a browser engine is not currently practical | High | Mermaid assumes DOM/layout; mermaid-cli uses headless browser | DOM-free subset renderers exist, but are incomplete |
| H4: A full from-scratch Rust/C++ engine is a multi-year effort dominated by platform integration | High | Rust/C++ stacks are primitives; no mature rich doc editor components | Qt offers a faster-but-heavy path |

## Verification Status

### Verified (2+ sources)
- TextKit 2 is Apple's modern text system and is default in macOS Ventura-era controls (WWDC + third-party summaries).
- Mermaid-cli uses a headless browser approach (docs + repo).
- MathJax supports SVG output and can run in headless/server-style environments (docs + existing wrapper implementations).
- MarkText is Electron-based (repo metadata + build tooling).

### Unverified / Needs Prototyping
- Whether upstream Mermaid can be made to work in JavaScriptCore with a minimal DOM shim and still produce correct layout fast enough for interactive editing.
- Whether a native SVG renderer in the editor can handle Mermaid's SVG output without converting to PNG in all cases.

## Limitations & Gaps

- This research focuses on feasibility and architecture choices, not measured benchmarks for TextKit 2 vs alternatives in the specific "Notion-style Markdown WYSIWYG" workload.
- The Mermaid pipeline requires a concrete prototype to validate: performance, fidelity, and security hardening.

## Sources

| Source | URL | Quality | Accessed | Notes |
|--------|-----|---------|----------|------|
| WWDC 2022 transcript: Meet TextKit 2 | https://developer.apple.com/videos/play/wwdc2022/10090/ | High | 2026-02-13 | TextKit 2 overview, attachments, platform direction |
| Indie Stack: TextKit 1 vs 2 notes | https://indiestack.com/2022/02/text-kit-1-vs-2/ | Medium | 2026-02-13 | Practical notes, caveats on opting out of TextKit 2 |
| STTextView | https://github.com/krzyzanowskim/STTextView | High | 2026-02-13 | NSTextView replacement built on TextKit 2 |
| Apple swift-markdown | https://github.com/swiftlang/swift-markdown | High | 2026-02-13 | Markdown AST in Swift |
| cmark-gfm | https://github.com/github/cmark-gfm | High | 2026-02-13 | GFM parser reference implementation |
| NSAttributedString docs (mentions Markdown import) | https://developer.apple.com/documentation/foundation/nsattributedstring | High | 2026-02-13 | Mentions creating attributed strings from Markdown |
| Mermaid config usage (securityLevel) | https://mermaid.js.org/config/usage | High | 2026-02-13 | SecurityLevel + config concepts |
| Mermaid secure config schema | https://mermaid.js.org/config/schema-docs/config-properties-secure.html | High | 2026-02-13 | Secure config allowlist, caps |
| Mermaid render docs | https://mermaid.js.org/config/usage#rendering | High | 2026-02-13 | render() output and behavior |
| Mermaid CLI | https://github.com/mermaid-js/mermaid-cli | High | 2026-02-13 | Headless rendering approach (Puppeteer/Chrome) |
| Mermaid issue: non-browser rendering libs | https://github.com/mermaid-js/mermaid/issues/58 | Medium | 2026-02-13 | Evidence of portability pain |
| beautiful-mermaid (GitHub) | https://github.com/lukilabs/beautiful-mermaid | High | 2026-02-13 | DOM-free subset renderer |
| mermaid-isomorphic (Playwright-based rendering) | https://www.npmjs.com/package/mermaid-isomorphic | Medium | 2026-02-13 | Reuses Playwright browser instance for Node rendering |
| Kroki issue: configure Mermaid htmlLabels=false | https://github.com/yuzutech/kroki/issues/1410 | Medium | 2026-02-13 | Points to htmlLabels=false to avoid foreignObject/HTML labels |
| KaTeX API docs | https://katex.org/docs/api.html | High | 2026-02-13 | Output formats (html/mathml) |
| MathJax output docs | https://docs.mathjax.org/en/v3.2/output/ | High | 2026-02-13 | Output processors incl SVG |
| MathJax SVG output docs | https://docs.mathjax.org/en/latest/output/svg.html | High | 2026-02-13 | SVG output details |
| iosMath | https://github.com/kostub/iosMath | High | 2026-02-13 | Native LaTeX math-mode rendering |
| SwiftMath | https://github.com/mgriebling/SwiftMath | High | 2026-02-13 | Swift port of iosMath |
| MathJaxSwift | https://github.com/colinc86/MathJaxSwift | Medium | 2026-02-13 | JSCore-based MathJax wrapper |
| Parley (docs.rs) | https://docs.rs/parley/latest/parley/ | High | 2026-02-13 | Rich text layout primitives |
| Vello | https://github.com/linebender/vello | High | 2026-02-13 | GPU renderer |
| cosmic-text docs | https://pop-os.github.io/cosmic-text/cosmic_text/ | High | 2026-02-13 | Text engine primitives |
| Qt QTextEdit | https://doc.qt.io/qt-6/qtextedit.html | High | 2026-02-13 | Markdown import/export, limitations |
| Qt QTextDocument Markdown features | https://doc.qt.io/qt-6/qtextdocument.html | High | 2026-02-13 | Markdown dialect subset |
| Typora: What is Typora | https://typora.io/ | Medium | 2026-02-13 | Markets itself as WYSIWYG |
| Typora support: theme debugging via Safari Web Inspector | https://support.typora.io/Debugging-Themes/ | Medium | 2026-02-13 | Indicates a web rendering surface on macOS |
| MarkText repo | https://github.com/marktext/marktext | High | 2026-02-13 | Electron-based open source editor |
