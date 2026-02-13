---
status: pending
priority: p2
issue_id: "004"
tags: [code-review, native-editor, markdown, codec, compatibility]
dependencies: []
---

# Normalize CRLF/CR newlines on Markdown import

## Problem Statement

`NativeMarkdownCodec.importMarkdown` splits input on `\\n` only and does not normalize `\\r\\n` or `\\r`. Windows-origin markdown files can therefore retain stray `\\r` characters, breaking parsing (fences/headings/lists) and round-trip stability.

## Findings

- `KernApp/Sources/Editor/NativeMarkdownCodec.swift:95`
  - `let lines = markdown.split(separator: "\\n", omittingEmptySubsequences: false)...`
  - No normalization step exists prior to parsing.
- Multiple parsing helpers use `.whitespaces` instead of `.whitespacesAndNewlines` (e.g. `parseFenceStart`), which makes stray `\\r` particularly problematic.

## Proposed Solutions

### Option 1: Normalize line endings at the start of import

**Approach:**
- Replace `\\r\\n` with `\\n`, and `\\r` with `\\n` before splitting.

**Pros:**
- Simple, predictable.
- Matches what the golden tests already normalize in output comparisons.

**Cons:**
- Slight behavior change for edge cases (rare).

**Effort:** Small

**Risk:** Low

---

### Option 2: Normalize per-line via trimming `\\r` suffix

**Approach:**
- After split, strip a trailing `\\r` from each line.

**Pros:**
- Narrower change.

**Cons:**
- Easier to miss other `\\r` occurrences.

**Effort:** Small

**Risk:** Low

## Recommended Action

## Technical Details

**Affected files:**
- `KernApp/Sources/Editor/NativeMarkdownCodec.swift:90`
- Add fixtures/tests under `test-fixtures/native-editor-golden/`

## Acceptance Criteria

- [ ] Add unit test importing CRLF and CR inputs
- [ ] `import -> export` output is stable and equivalent to LF version
- [ ] Golden fixtures cover CRLF normalization

## Work Log

### 2026-02-13 - Code Review Finding

**By:** Codex

**Actions:**
- Identified missing newline normalization in codec import path.

**Learnings:**
- Cross-platform markdown interchange will require consistent newline handling early in the pipeline.

