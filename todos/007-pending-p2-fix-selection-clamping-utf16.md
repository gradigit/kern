---
status: pending
priority: p2
issue_id: "007"
tags: [code-review, native-editor, correctness, unicode]
dependencies: []
---

# Selection clamping uses String.count instead of NSString length (UTF-16 mismatch)

## Problem Statement

Several places clamp an `NSRange` caret location using `textView.string.count`. `NSRange` indices are in UTF-16 code units, while `String.count` is grapheme clusters. With non-ASCII content (emoji, combining characters), this can misplace the caret after external updates.

## Findings

- `KernApp/Sources/Editor/NativeEditorViewController.swift:114-116`
  - `let maxLocation = max(0, textView.string.count)` used for clamping `selection.location`.
- `KernApp/Sources/Editor/NativeEditorViewController.swift:131-134`
  - Same pattern when restoring selection after `renderMarkdown`.

## Proposed Solutions

### Option 1: Clamp using text storage length (UTF-16)

**Approach:**
- Use `textView.textStorage?.length` (or `(textView.string as NSString).length`) for max bounds.

**Pros:**
- Correct for all Unicode cases.

**Cons:**
- None meaningful.

**Effort:** Small

**Risk:** Low

## Acceptance Criteria

- [ ] Add unit test with emoji content ensuring selection restore is stable
- [ ] Replace `String.count` clamps with UTF-16 length clamps

## Work Log

### 2026-02-13 - Code Review Finding

**By:** Codex

**Actions:**
- Located UTF-16 vs grapheme mismatch in selection restore paths.

