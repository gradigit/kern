# Research: Soft Line Break + Checkbox Hit Target (Notion/GitHub/GFM)

> Historical research note retained for reference. It is not part of the active contributor quick-start path.

Date: 2026-02-13
Depth: Full (targeted)

## Executive Summary

- **Shift+Enter (WYSIWYG “line break in same block”)**: Notion documents Shift+Enter as a line break *within the same block*. In Markdown, the interoperable on-disk representation is a **hard line break**, which CommonMark defines as either a trailing backslash or two trailing spaces at end-of-line.
- **Recommendation for Kern**: represent Shift+Enter internally as **U+2028**, and serialize it as **CommonMark hard breaks using trailing backslash** (`\\` at end-of-line). This avoids brittle trailing spaces while staying within Markdown.
- **Checkbox click target**: Notion and GitHub-style task lists primarily toggle by clicking the checkbox itself. A “marker-region click toggles” mode is useful as an option, but default should match Notion/GitHub.

## Sub-Questions Investigated

1. What does Notion define Shift+Enter to do?
2. How should a WYSIWYG “soft break” be serialized to Markdown for correct rendering?
3. What is a reasonable default click target for tasks (checkbox vs marker region)?

## Findings

### 1) Notion: Shift+Enter Inserts a Line Break Within the Same Block

Notion’s keyboard shortcuts explicitly define:
- **Shift + Enter**: “Line break within the same block”

Source:
- Notion Help Center: Keyboard shortcuts — https://www.notion.so/help/keyboard-shortcuts

### 2) CommonMark/GFM: Hard Line Break Syntax

CommonMark defines a **hard line break** as:
- a line ending preceded by a **backslash**, or
- a line ending preceded by **two or more spaces**

Source:
- CommonMark Spec (hard line breaks) — https://spec.commonmark.org/0.31.2/#hard-line-breaks

### 3) Checkbox Hit Target (Notion/GitHub Baseline)

Neither Notion nor GFM “spec” defines click targets, but the prevailing UX in Notion/GitHub task lists is:
- Toggle by clicking the **checkbox glyph**, not arbitrary marker prefix space.

Practical implication:
- Default to **glyph-only toggle** for correctness and predictability.
- Offer optional “marker-region toggles” for users who prefer it.

Supporting sources (task list UX context):
- GitHub Docs: About task lists — https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/about-task-lists

## Recommendations For Kern (Product Decisions)

1. **Shift+Enter internal representation**: use `U+2028` for deterministic round-tripping inside `NSAttributedString`.
2. **Shift+Enter Markdown serialization**: emit `\\` hard breaks (CommonMark) rather than trailing spaces.
3. **Checkbox hit target default**: `glyph` (Notion/GitHub-like); optional `marker` mode.

## Limitations / Gaps

- Notion docs do not fully specify “Enter exits heading” and similar edge cases; treat these as explicit product decisions and lock them in with deterministic tests.

