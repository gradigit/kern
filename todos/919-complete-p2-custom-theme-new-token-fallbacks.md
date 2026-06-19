---
status: complete
priority: p2
issue_id: "919"
tags: [code-review, themes, settings, visual-design]
dependencies: []
---

# Preserve new theme tokens for custom theme fallback

## Problem Statement

The theme palette was expanded with editor/sidebar backgrounds, secondary text, inline-code text, table headers, quote colors, and syntax/callout colors. The custom theme resolver still rebuilds a `ThemePalette` using only the old subset of fields, so custom themes silently fall back to default/dynamic values for the new visual surfaces.

## Findings

- `resolvedThemePalette` computes a `basePalette` for custom themes, but the returned `ThemePalette` only passes old fields: text, link, code block background/stroke, and inline code background.
- New fields such as `editorBackground`, `sidebarBackground`, `secondaryTextColor`, `inlineCodeText`, `tableHeaderBackground`, `quoteBar`, `quoteFill`, and `syntax` are not inherited from `basePalette`.
- That can make imported dark themes have mismatched editor backgrounds, table headers, callouts, and syntax colors even though built-in themes work.
- Existing tests assert built-in catalog membership but do not check custom theme fallback preservation for new tokens.

## Proposed Solutions

### Option 1: Preserve base palette fields in custom resolver

**Approach:** Pass through all new fields from `basePalette` when constructing the custom `ThemePalette`, only overriding fields explicitly supported by the custom JSON schema.

**Pros:**
- Smallest fix.
- Maintains backward compatibility with existing custom JSON schema.
- Prevents mismatched surfaces immediately.

**Cons:**
- Users still cannot directly set every new token in custom JSON.

**Effort:** 30-60 minutes

**Risk:** Low

---

### Option 2: Expand custom theme JSON schema

**Approach:** Add optional JSON fields for the new palette tokens and validate them in `CustomThemeDefinition`.

**Pros:**
- Full custom theme control.
- Aligns user-imported themes with built-in theme capability.

**Cons:**
- More schema/test/docs surface.
- Need migration/backward-compatibility docs.

**Effort:** 2-4 hours

**Risk:** Medium

## Recommended Action

Completed Option 1: custom themes keep the existing JSON schema and now inherit all expanded palette tokens from the resolved base palette, only overriding fields explicitly supported by the custom theme definition.

## Technical Details

Affected files:
- `KernApp/Sources/Editor/NativeEditorAppearance.swift:825` - custom palette resolution
- `KernTests/NativeEditorAppearanceTests.swift` - add custom fallback/token preservation tests
- `docs` / theme import docs if schema expands

## Resources

- Review source: local adversarial code review on 2026-06-19.

## Acceptance Criteria

- [x] Custom dark theme inherits dark editor/sidebar/table/quote/callout-compatible surfaces from the selected base appearance.
- [x] Custom theme tests verify new palette token fallback behavior.
- [x] If schema expands, invalid new color fields are validated and documented. (Schema was not expanded; no new validation/docs required.)
- [x] `./scripts/test-native-editor.sh --no-snapshots` passes.

## Work Log

### 2026-06-19 - Initial Discovery

**By:** Codex

**Actions:**
- Reviewed expanded `ThemePalette` fields and custom resolver construction.
- Compared built-in preset construction with custom theme construction.

**Learnings:**
- Built-in themes exercise the new token set, but imported custom themes currently use the old subset path.

### 2026-06-19 - Fix Implementation

**By:** Codex

**Actions:**
- Updated custom theme palette resolution to preserve editor/sidebar backgrounds, secondary text, inline-code text, table header, quote colors, and syntax colors from the base palette.
- Added a custom-theme fallback regression test that catches old-schema custom themes dropping expanded palette tokens.

**Validation:**
- Targeted appearance test passed.
- `./scripts/test-native-editor.sh --no-snapshots` passed: 443 tests, 84 skipped, 0 failures.

## Notes

This is especially relevant because the UI exposes custom JSON import next to the expanded theme pack.
