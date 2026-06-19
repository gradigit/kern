---
status: complete
priority: p3
issue_id: "920"
tags: [code-review, snapshots, visual-regression, textkit]
dependencies: []
---

# Add visual regression coverage for callouts and custom checkboxes

## Problem Statement

The new callout cards and custom-drawn checkboxes are primarily visual/TextKit drawing behavior. Unit tests cover callout markdown round-trip and theme catalog membership, but they do not catch pixel regressions in checkbox placement, callout card bounds, theme contrast, or dark/light dynamic color resolution.

## Findings

- Checkbox drawing is an overlay after `super.draw`, while the underlying checkbox glyph is transparent. This is a reasonable TextKit-preserving approach, but regressions will be visual rather than semantic.
- Callout cards are drawn by grouping paragraph ranges in `NativeMarkdownTextView`, and sizing depends on layout manager bounding rects.
- Existing added tests do not cover screenshot/snapshot output for callouts, checkboxes, or expanded theme-specific surfaces.
- Manual screenshots caught usable output, but those screenshots are temporary artifacts, not durable gates.

## Proposed Solutions

### Option 1: Add focused snapshot fixtures

**Approach:** Add a compact fixture containing callouts, checked/unchecked tasks, inline code, table, and code block; record dark/light snapshots for a small set of representative themes.

**Pros:**
- Directly tests the risk surface.
- Easy to review diffs when UI changes.

**Cons:**
- Snapshot maintenance burden.
- Needs stable fonts/appearance configuration.

**Effort:** 2-3 hours

**Risk:** Low

---

### Option 2: Add geometry unit seams

**Approach:** Expose test seams for checkbox rect computation and callout grouping, then assert bounds without full image snapshots.

**Pros:**
- Less brittle than pixel snapshots.
- Catches layout grouping errors quickly.

**Cons:**
- Does not catch actual color/contrast regressions.

**Effort:** 2-4 hours

**Risk:** Medium

## Recommended Action

Completed a combined Option 1/Option 2 release-safe coverage path: added geometry seams for checkbox/callout layout, made snapshot light/dark theme selection deterministic, recorded the intentional visual baseline updates, and verified the snapshot-only lane.

## Technical Details

Affected files:
- `KernApp/Sources/Editor/NativeMarkdownTextView.swift:41` - checkbox overlay drawing
- `KernApp/Sources/Editor/NativeMarkdownTextView.swift:789` - callout grouping
- `KernTests` snapshot fixtures/baselines

## Resources

- Review source: local adversarial code review on 2026-06-19.

## Acceptance Criteria

- [x] Snapshot or geometry tests cover checked and unchecked checkbox rendering.
- [x] Snapshot or geometry tests cover callout card grouping across multi-line callouts.
- [x] At least one dark and one light theme are covered.
- [x] `./scripts/test-native-editor.sh --snapshots --exhaustive` or an agreed narrower snapshot lane passes when baselines are intentionally updated. (`--record-snapshots --snapshots-only --exhaustive` refreshed baselines; `--snapshots-only --exhaustive` verified 7 snapshot tests, 0 failures.)

## Work Log

### 2026-06-19 - Initial Discovery

**By:** Codex

**Actions:**
- Reviewed visual drawing code and tests added in this change.
- Compared manual screenshot QA against durable test coverage.

**Learnings:**
- The current change is functionally covered but visually under-covered.

### 2026-06-19 - Fix Implementation

**By:** Codex

**Actions:**
- Added test seams for checkbox overlay rectangles and callout group ranges.
- Added geometry tests for checked/unchecked checkboxes across light/dark appearances and multi-line callout grouping boundaries.
- Fixed snapshot tests so explicit light/dark cases no longer depend on the host macOS appearance.
- Recorded updated visual baselines for the intentional theme/checkbox visual changes.

**Validation:**
- Targeted geometry tests passed.
- `./scripts/test-native-editor.sh --record-snapshots --snapshots-only --exhaustive` recorded and then verified all snapshot baselines: 7 snapshot tests, 0 failures in verify mode.
- `./scripts/test-native-editor.sh --snapshots-only --exhaustive` passed: 7 snapshot tests, 0 failures.
- `./scripts/test-native-editor.sh --no-snapshots` passed: 443 tests, 84 skipped, 0 failures.

## Notes

This is P3 because the current screenshots look acceptable and semantic tests pass, but the risk should be addressed before relying on the theme system long-term.
