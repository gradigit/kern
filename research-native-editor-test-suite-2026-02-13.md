# Research: Native WYSIWYG Markdown Editor Test Suite (macOS, No WebView)

> Historical research note retained for reference. It is not part of the active contributor quick-start path.


**Date:** 2026-02-13  
**Depth:** Full  
**Query:** Design a comprehensive, exhaustive, full-featured test suite for a macOS-native WYSIWYG Markdown editor (TextKit), aligned with Notion/GitHub behaviors and GFM/CommonMark rules. Include screenshot-based visual confirmation, strong logs, and an agentic “run tests -> fix -> rerun -> review -> commit” loop.

## Executive Summary

An “exhaustive” test suite for a native WYSIWYG Markdown editor must combine:

1. **Spec-level correctness** for Markdown syntax/semantics using **GFM/CommonMark** as ground truth (especially lists/tasks/indentation), and clear decisions for any **Kern extensions**.
2. **Behavioral correctness** for editing operations using **Notion-style type-to-convert shortcuts** and **GitHub-style list auto-continuation** as UX baselines.
3. **Deterministic artifacts**: golden fixtures for import/export, structured logs, `.xcresult` bundles, and screenshot attachments extracted with `xcresulttool`.
4. **A two-speed strategy**: fast unit tests (codec + attribute semantics + property/fuzz) and slower UI tests (XCUITest with screenshots) reserved for true integration.

Confidence: **High** for the layered approach (unit + UI + visual artifacts + generators). Confidence is **Medium** for “official” documentation of some Notion edge behaviors (heading/list exit rules are not always fully specified in help docs), so the suite should explicitly encode product decisions.

## Question Decomposition

1. What are the “ground truth” Markdown rules we should treat as spec (lists/tasks/indentation, etc.)?
2. What WYSIWYG editor behaviors should be considered baseline (Notion/GitHub)?
3. What is the most reliable architecture for macOS native UI testing + screenshots + log extraction?
4. How should the suite scale to “exhaustive permutations” without becoming unmaintainable?

## Detailed Findings

### 1) Markdown Ground Truth: Lists + Task Items

**GFM is a strict superset of CommonMark** and defines additional extensions (like task list items). The GFM spec provides precise rules for list marker indentation and nested list alignment, and defines the task list marker forms (`[ ]`, `[x]`).

Key test areas derived from the GFM spec:
- **List indentation**: 1–3 leading spaces before a list marker still counts as a list; 4 spaces typically becomes an indented code block in ambiguous contexts.
- **Nested lists**: a sublist must be indented to align with the parent item’s content; insufficient indentation breaks nesting.
- **Task list items**: task markers are list items with `[ ]` or `[x]` at the start of the first block.

Sources:
- GFM spec (lists + task list items): https://github.github.com/gfm/

### 2) WYSIWYG Input Rules: Notion “Type to Convert”

Notion documents Markdown-like shortcuts that are stable and easy to map to WYSIWYG block creation:
- `#` / `##` / `###` + space => headings
- `-` / `*` / `+` + space => bullet list
- `1.` + space => numbered list
- `[]` + space => to-do checkbox

These shortcuts should become deterministic input-rule tests: “typed pattern -> converted block + correct export”.

Sources:
- Notion: keyboard shortcuts and Markdown-style shortcuts: https://www.notion.so/help/keyboard-shortcuts
- Notion: writing/editing basics (shortcuts): https://www.notion.com/help/writing-and-editing-basics

### 3) List Auto-Continuation & Escape: GitHub Editor Behavior

GitHub documents list syntax auto-completion in its Markdown editor:
- Enter continues list markers
- Shift+Enter skips autocomplete and inserts a normal newline

These behaviors map cleanly to WYSIWYG list editing semantics:
- Enter on non-empty list item => create next list item
- Enter on empty list item => exit list
- Shift+Enter => hard line break (no list continuation)

Sources:
- GitHub changelog: list syntax autocompletion: https://github.blog/changelog/2022-05-12-list-syntax-is-autocompleted-in-the-markdown-editor/

### 4) Screenshot-Based Visual Confirmation: XCUITest + `.xcresult`

XCUITest can attach screenshots to tests, and Xcode stores them inside `.xcresult` bundles. A robust extraction path is:

- run UI tests with `xcodebuild ... -resultBundlePath <path>`
- export attachments with `xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>`

This produces a `manifest.json` describing which attachments came from which test, enabling automated artifact collection in an agentic loop.

Primary source (tooling): `xcresulttool` help output (Xcode CLI).

Supporting sources:
- Practical XCUITest screenshots usage patterns (non-official, cross-verify):
  - https://useyourloaf.com/blog/screenshot-ui-tests-in-xcode/
  - https://www.mokacoding.com/blog/xctest-screenshots/

### 5) Visual Regression Strategy (Planned)

UI-test screenshots are necessary but not sufficient for regressions. A stricter strategy is to add **snapshot testing** for AppKit views and keep baselines under version control.

A widely used OSS choice is Point-Free’s SnapshotTesting (supports many snapshot strategies and recording modes). The suite should:
- keep UI-test screenshots as always-on artifacts
- add view-level snapshot assertions for stable components (checkbox rendering, code block styling, list alignment)
- require explicit record mode to update baselines

Sources:
- SnapshotTesting repository + docs: https://github.com/pointfreeco/swift-snapshot-testing

### 6) Scaling to “Exhaustive Permutations”

“Every permutation” is only achievable with **generator-backed tests** and **bounded parameter sets**.

Recommended structure:
- **Golden fixtures** for high-value, human-auditable cases
- **Parametric generators** for systematic permutations:
  - list marker types (bullet/ordered/task)
  - indent widths (0–8)
  - nesting depth (0–6)
  - tight/loose list spacing
  - adjacency of block types
- **Property tests / fuzz** (seeded) for crash safety and invariants (idempotence, no marker corruption)

## Hypothesis Tracking

| Hypothesis | Initial | Final | Evidence |
|---|---:|---:|---|
| Layered suite (unit + UI + screenshot artifacts) is required for WYSIWYG correctness | High | High | Editor correctness spans parsing/serialization + UI behaviors + visual output |
| GFM lists/tasks are the most important spec surface for correctness/permutations | High | High | GFM spec has precise list/task rules; lists are common + subtle |
| Notion + GitHub behaviors are the best UX baselines for type-to-convert and Enter behavior | Med | High | Both document shortcuts/autocomplete explicitly |

## Self-Critique

| Issue | Severity | Resolution |
|---|---|---|
| Notion doesn’t fully specify some “exit block” edge behavior | Medium | Treat these as product decisions; encode as testable rules with explicit expected outcomes |
| Apple reference docs for XCTest APIs are hard to cite directly (JS-heavy pages) | Low | Use `xcresulttool` CLI output as primary for artifacts; use multiple reputable sources for screenshot patterns |

## Source Evaluation

| Source | Tier | Recency | Used For |
|---|---:|---:|---|
| github.github.com/gfm | 1 | stable | list/task rules + edge cases |
| Notion help center | 1 | current | shortcuts |
| GitHub changelog | 1 | current | list autocomplete + Shift+Enter |
| `xcresulttool` CLI help | 1 | current | attachment export pipeline |
| useyourloaf / mokacoding | 2 | recent-ish | screenshot patterns, practical guidance |
| SnapshotTesting repo | 1 | current | snapshot regression strategy |

