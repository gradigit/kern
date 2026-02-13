# Plan: Native Editor Exhaustive Test Suite + Agentic Self-Repair Loop

Date: 2026-02-13

## Goal

Build a comprehensive, generator-backed test suite for Kern’s native TextKit WYSIWYG Markdown editor that can be driven agentically:
- run tests
- collect logs and screenshots
- diagnose failures
- implement fixes
- run review
- commit
- repeat

## Success Criteria

- Unit tests cover import/export determinism + semantic attributes for the implemented feature set.
- UI tests cover end-to-end typing behaviors, save/export, and key interactive affordances.
- Every UI test attaches screenshots and artifacts can be exported automatically.
- A single script runs the suite and produces a timestamped artifact bundle.
- A dedicated skill exists that drives the loop and prevents “hack-to-green” anti-patterns.

## Scope Decisions Needed (Must Confirm)

These decisions gate “expected output” for many tests:

1. Export dialect:
- Decision: **Support both modes via setting. Default = GFM.** (User preference, 2026-02-13)
  - Default export: `gfm`
  - Optional: `kern` export dialect for preserving standalone task syntax (`[ ] text`) and other Kern-friendly exports

2. Task rendering semantics:
- Decision: **Checkbox-only by default (GFM-like), bullet+checkbox as an option.** (User preference, 2026-02-13)

3. Ordered task semantics:
- Decision: **Optional feature. Default off (GFM), user-pref on.** (User preference, 2026-02-13)

4. “Exit syntax” rules:
- Heading: Enter exits to paragraph (single Enter)
- Lists: Enter continues; Enter on empty item exits
- Shift+Enter: line break without list continuation

5. Ordered list numbering:
- Decision: **Default = GFM-style sequential normalization**, optional **preserve typed numbers**. (User preference, 2026-02-13)

## Phases

### Phase 1: Harness Foundations (DONE / IN PROGRESS)

- Add accessibility identifiers for native editor UI elements.
- Add baseline XCUITest suite for native editor.
- Add golden fixture harness for codec round-trip.
- Add a single runner script that collects `.xcresult` and exports attachments.

Deliverables (in repo):
- `KernUITests/NativeEditorE2ETests.swift`
- `KernTests/NativeEditorGoldenFixturesTests.swift`
- `test-fixtures/native-editor-golden/`
- `scripts/test-native-editor.sh`
- `NATIVE-EDITOR-TEST-PLAN.md`
- `NATIVE-EDITOR-TEST-MATRIX.md`
- skill: `~/.claude/skills/kern-native-test-loop/SKILL.md`

### Phase 2: Spec Coverage for Current Feature Set

Add unit tests for:
- headings (levels 1-6) attributes + export
- bullets and ordered list attributes + export
- tasks: checked/unchecked, marker protection
- inline: bold/italic/code/link parsing + export escaping
- code blocks: fenced language retention + grouped export

Add golden fixtures for edge cases already implemented.

### Phase 3: Editing Behavior Unit Tests (Refactor for Testability)

Extract from `NativeEditorViewController` into testable functions:
- input-rule detection and transformation
- newline continuation + exit behavior
- marker deletion protection

Unit-test these functions with a synthetic attributed string + caret position.

### Phase 4: UI Test Expansion + Screenshot Artifacts

Add E2E tests for:
- task toggle (click)
- list continuation + exit for bullet/task/ordered
- shift-enter suppression
- code block copy button copies exact contiguous block
- save + reopen round-trip
- toast behavior on reload

Ensure each test attaches:
- initial state screenshot
- post-action screenshot
- (optional) “after save” screenshot

### Phase 5: Visual Regression (Snapshot Testing)

Introduce deterministic visual checks for core components:
- checkbox glyph alignment + size
- marker alignment for wrapped lines
- code block background + copy button positioning

Keep update workflow explicit (record mode).

Status:
- Implemented SnapshotTesting integration (gated behind `KERN_ENABLE_SNAPSHOT_TESTS=1`)
- Recording supported via `KERN_RECORD_SNAPSHOTS=1`

### Phase 6: Exhaustive Permutation Generation

Implement generator-backed tests:
- systematic list indentation/nesting permutations (bounded depth/width)
- adjacency permutations of block types
- seeded fuzz tests for inline marker stress

Define “exhaustive” as: complete coverage within explicit bounds, not infinite combinations.

### Phase 7: Agentic Loop Hardening

Enhance the skill + scripts to:
- run targeted tests by name
- parse `.xcresult` failures into a structured summary
- timebox retries, escalate decisions to user
- enforce review step before commit

## Verification Commands

- Unit: `xcodebuild -project Kern.xcodeproj -scheme Kern test`
- UI: `xcodebuild -project Kern.xcodeproj -scheme KernUI test`
- Runner: `./scripts/test-native-editor.sh`

## Risks / Failure Modes

- UI test flakiness due to event timing or permission prompts.
- Pixel-based snapshots can be flaky across machines (font rendering, DPI).
- “Exhaustive permutations” can explode; must bound generators.

## [Iteration] Research Findings

- GFM/CommonMark list rules (indentation and nested list alignment) are the biggest “edge case surface area” and should be the first target for generator-backed tests.
- Notion documents stable type-to-convert shortcuts (`[] `, `1. `, `- `, `# `) which map cleanly to deterministic input-rule tests.
- GitHub documents list auto-completion and Shift+Enter escape behavior, which provides a clear baseline for Enter handling in lists.
- Xcode `.xcresult` bundles can be post-processed with `xcresulttool export attachments` to extract screenshot artifacts per test case (manifest-driven).

References (in repo):
- `research-native-editor-test-suite-2026-02-13.md`
- `research-wysiwyg-input-rules-2026-02-13.md`

## [Iteration] Self-Critique

- The plan needs explicit decisions for Markdown dialect + task rendering semantics; otherwise golden outputs are unstable.
- IME composition and clipboard/paste behaviors are not yet captured as concrete test cases.
- Backspace/join-block behavior and selection formatting need dedicated tests.
- Performance targets need defined thresholds (what is “too slow”).

Additional gaps discovered during implementation:
- Golden fixtures needed a preference-aware “cases” mechanism to avoid combinatorial file explosion (now implemented via `*.case.json`).
- Visual regression needs a workflow decision: are snapshot baselines committed to git, and do we accept OS/font drift?

## [Forging-Plans Mode 2] Adversarial Review (Gaps + Fixups)

High-risk gaps (will block “autonomous iteration” later):
1. **Ambiguous export semantics for extensions in GFM mode**:
   - Example: heading checkboxes and ordered tasks are “extensions” but still valid plain GFM text.
   - Decision implemented:
     - default: preserve extension syntax under `exportDialect=gfm`
     - option: `portable` (avoid extension syntax; uses `☐/☑`)
     - option: `lint` (rewrite extension blocks into widely-supported patterns, ex: checkbox headings -> task list items)
2. **Editing semantics not fully unit-testable**:
   - Core logic still lives in `NativeEditorViewController` and is exercised mostly via UI tests.
   - This will slow agentic loops and increase flakiness until extracted into pure functions.
3. **Clipboard/IME/paste not covered**:
   - These are common “real user” breakpoints and typically regress.
4. **Snapshot baseline policy**:
   - Need explicit policy: commit baselines, and what counts as acceptable drift across macOS versions.

Medium-risk gaps:
1. **Ordered-task and heading-checkbox click targets**:
   - Implemented: configurable hit target (`glyph` default; optional `marker` region toggles).
2. **Nested list, tables, blockquotes**:
   - Forward spec tests exist (gated), but no incremental plan for graduating them from expected-failure to enforced.

Recommended next actions:
1. Add/expand UI tests for checkbox toggling across block kinds (task/ordered-task/heading-checkbox) in both hit-target modes.
2. Extract newline continuation + input-rule conversion into a small pure module and write unit tests for it.
3. Add IME + paste tests (at least: paste markdown text into paragraph and ensure conversion/export stability).
