---
status: complete
priority: p2
issue_id: "918"
tags: [code-review, markdown, conformance, callouts]
dependencies: []
---

# Gate callout parsing/export by markdown profile semantics

## Problem Statement

The new callout/admonition support is implemented as a Kern extension, but the import/export paths currently apply it unconditionally. That risks breaking strict CommonMark/GFM conformance runs and portable/lint export profiles that are supposed to keep Kern extensions explicit and opt-in.

## Findings

- `NativeMarkdownCodec.importMarkdown` parses any blockquote line beginning with `[!KIND]` as a callout before checking strict conformance mode.
- `exportParagraph` always emits `[!KIND]` for paragraphs tagged with `.kernCalloutKind`, regardless of `exportDialect` or `gfmExtensionExportStrategy`.
- The parser accepts folded-callout suffixes (`[!NOTE]+` / `[!NOTE]-`) but does not store or export that fold state, so opening and saving those callouts loses author intent.
- Existing strict-profile regression tests cover heading and ordered-task extensions, but not callouts.
- The change passed the default suite, but default tests skip the full strict spec gate unless enabled.

## Proposed Solutions

### Option 1: Treat callouts like other Kern extensions

**Approach:** Only parse/render callouts when strict conformance is disabled. On export, follow existing extension policy: preserve in default GFM preserve mode, degrade in portable mode, and lint/rewrite as a normal blockquote/plain text where appropriate.

**Pros:**
- Aligns with existing option semantics.
- Keeps strict conformance and portable exports predictable.
- Small localized change.

**Cons:**
- Requires deciding exact portable/lint representation.

**Effort:** 1-2 hours

**Risk:** Low

---

### Option 2: Add explicit callout option

**Approach:** Add an `Options.calloutsEnabled` or profile flag and wire it through defaults/settings.

**Pros:**
- Gives users/control tests explicit behavior.
- Future-proofs callout variants.

**Cons:**
- More UI/defaults/test surface area.
- Probably more complexity than needed for v0.1.

**Effort:** 3-5 hours

**Risk:** Medium

## Recommended Action

Completed Option 1: callouts now behave as an opt-in Kern extension. Strict conformance keeps callout syntax literal, default preserve mode round-trips callouts including fold suffixes, and portable/lint export degrades callouts to ordinary blockquote text.

## Technical Details

Affected files:
- `KernApp/Sources/Editor/NativeMarkdownCodec.swift:682` - unconditional import callout parse
- `KernApp/Sources/Editor/NativeMarkdownCodec.swift:1678` - unconditional grouped callout export
- `KernApp/Sources/Editor/NativeMarkdownCodec.swift:6449` - unconditional `[!KIND]` paragraph export
- `KernTests/NativeMarkdownCodecCalloutTests.swift` - add strict and portable/lint coverage
- `KernTests/NativeMarkdownSpecConformanceTests.swift` - add callout-specific strict profile canary

## Resources

- Review source: local adversarial code review on 2026-06-19.

## Acceptance Criteria

- [x] Strict conformance import keeps `> [!NOTE]` literal when Kern extensions are disabled.
- [x] Default WYSIWYG profile still hides callout marker and round-trips the callout.
- [x] Portable/lint export behavior is explicit and tested.
- [x] Fold suffixes (`+` / `-`) are either preserved round-trip or intentionally rejected/literalized with tests.
- [x] `./scripts/test-native-editor.sh --no-snapshots` passes.
- [x] `./scripts/test-markdown-spec-conformance.sh` passes or documented gate remains green under required environment.

## Work Log

### 2026-06-19 - Initial Discovery

**By:** Codex

**Actions:**
- Reviewed callout import/export diff.
- Compared against existing strict extension behavior for heading and ordered tasks.
- Identified missing callout coverage in strict-profile tests.

**Learnings:**
- Callout implementation is visually functional, but profile semantics need to be wired before release.

### 2026-06-19 - Fix Implementation

**By:** Codex

**Actions:**
- Gated callout import behind strict-conformance mode so strict profiles keep `[!NOTE]` syntax literal.
- Stored and re-exported callout fold suffixes with a dedicated attributed-string key.
- Made portable/lint GFM export drop the admonition marker while retaining blockquote text.
- Added callout unit tests plus a strict-profile canary in the spec conformance tests.

**Validation:**
- Targeted callout/spec tests passed.
- `./scripts/test-native-editor.sh --no-snapshots` passed: 443 tests, 84 skipped, 0 failures.
- `./scripts/test-markdown-spec-conformance.sh` passed: CommonMark + GFM strict conformance tests, 5 tests, 0 failures.

## Notes

This is not a rendering blocker, but it is important for the repo's documented CommonMark/GFM conformance contract.
