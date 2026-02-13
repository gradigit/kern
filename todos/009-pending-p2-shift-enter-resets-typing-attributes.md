---
status: pending
priority: p2
issue_id: "009"
tags: [code-review, native-editor, ux]
dependencies: []
---

# Shift+Enter/list-break path resets typing attributes to base (may drop inline style)

## Problem Statement

When `suppressNextAutoNewlineContinuation` is set (Shift+Enter or explicit line break), `handleNewlineContinuationIfNeeded` resets typing attributes to the base font/color. This likely drops any active inline style the user expects to continue typing with (bold/italic/code).

## Findings

- `KernApp/Sources/Editor/NativeMarkdownTextView.swift:32-45`
  - Shift+Enter sets `suppressNextAutoNewlineContinuation = true` then inserts a line break.
- `KernApp/Sources/Editor/NativeEditorViewController.swift:364-367`
  - If suppression flag is set, it calls `setBaseTypingAttributes()` and returns.

## Proposed Solutions

### Option 1: Preserve typing attributes from insertion point

**Approach:**
- When suppression flag is observed, set typing attributes based on the attributes at the caret location (excluding marker attributes), rather than resetting to base.

**Pros:**
- More intuitive WYSIWYG typing behavior.

**Cons:**
- Needs careful handling if caret is in marker region.

**Effort:** Medium

**Risk:** Medium

---

### Option 2: Document as current limitation

**Approach:**
- Keep behavior for MVP and add a test to lock it in.

**Pros:**
- Zero complexity.

**Cons:**
- UX regression vs Notion-like editors.

**Effort:** Small

**Risk:** Low

## Acceptance Criteria

- [ ] Decide intended behavior for inline style carry-over across Shift+Enter
- [ ] Add UI test covering the behavior (bold then Shift+Enter then type)
- [ ] Implementation matches the decided behavior

## Work Log

### 2026-02-13 - Code Review Finding

**By:** Codex

**Actions:**
- Noted unconditional typing-attribute reset on suppression path.

