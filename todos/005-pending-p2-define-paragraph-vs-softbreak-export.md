---
status: pending
priority: p2
issue_id: "005"
tags: [code-review, native-editor, markdown, codec, wysiwyg]
dependencies: []
---

# Define paragraph vs soft-break semantics for Enter and export

## Problem Statement

The native editor uses TextKit paragraphs (newline-separated) as the primary block unit, but Markdown semantics require blank lines to separate paragraphs. Today, `exportMarkdown` joins blocks with a single newline (`\\n`), which in GFM/CommonMark is typically a softbreak inside one paragraph unless there is an empty line.

This is a design gap vs "true WYSIWYG + GFM syntax ground truth" and needs an explicit spec and tests.

## Findings

- `KernApp/Sources/Editor/NativeMarkdownCodec.swift:396-402`
  - `outBlocks.joined(separator: "\\n")` means adjacent blocks are separated by one newline.
  - If a user presses Enter once between two paragraphs in the editor, export will output a single newline, not a blank line.
- `KernApp/Sources/Editor/NativeEditorViewController.swift:362-441`
  - Auto-newline continuation handles lists/headings but does not define paragraph separation semantics outside those cases.
- Test fixtures largely assume explicit blank lines already exist in the source; they do not yet specify editor-Enter behavior for paragraph separation.

## Proposed Solutions

### Option 1: Treat TextKit paragraph breaks as Markdown block breaks (export blank lines between block groups)

**Approach:**
- In export, group runs of list items and code blocks.
- Separate non-list blocks (paragraphs/headings) with blank lines (`\\n\\n`).
- Keep list items tight by default (single newline within list run).

**Pros:**
- Produces Markdown that renders closer to WYSIWYG expectations.
- Keeps output portable (GFM).

**Cons:**
- Requires grouping logic and careful handling of edge cases (loose lists, mixed blocks).

**Effort:** Medium/Large

**Risk:** Medium

---

### Option 2: Treat TextKit newline as Markdown softbreak (require blank line in editor for paragraph separation)

**Approach:**
- Document that "paragraphs are separated by an empty line" (Enter twice) to match Markdown source rules.
- Add tests to enforce.

**Pros:**
- Minimal code changes.
- Matches raw Markdown semantics.

**Cons:**
- Worse WYSIWYG UX vs Notion-style editors.

**Effort:** Small

**Risk:** Low

## Recommended Action

## Acceptance Criteria

- [ ] Decide and document the intended behavior (Notion-like vs Markdown-source-like)
- [ ] Add unit/UI tests capturing Enter behavior and exported Markdown rendering expectations
- [ ] Ensure round-trip stability for the decided behavior

## Work Log

### 2026-02-13 - Code Review Finding

**By:** Codex

**Actions:**
- Flagged mismatch between TextKit paragraph model and GFM paragraph separation rules.

**Learnings:**
- This needs a product-level decision; implementation follows.

