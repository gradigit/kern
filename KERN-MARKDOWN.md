# Kern Markdown Extensions

Kern extends standard GitHub Flavored Markdown (GFM) with the following syntax. Files using these extensions render correctly in Kern but may show raw syntax in other markdown renderers.

## Standalone Checkboxes

**Syntax:** `[ ] text` or `[x] text` at the start of a line (no list marker).

```
[ ] Unchecked item
[x] Checked item
```

**Renders as:** A clickable checkbox followed by text, without any list indicator.

**GFM equivalent:** GFM requires a list marker (`- [ ] text`). Bare `[ ] text` renders as literal text in standard renderers.

**Rationale:** `[ ]` is more intuitive and fewer keystrokes than `- [ ]` for simple checkboxes. It also frees `- [ ]` to mean "bulleted task" (bullet dot + checkbox).

## Bulleted Task Lists

**Syntax:** `- [ ] text` or `- [x] text` (standard GFM task list syntax).

```
- [ ] Unchecked bulleted task
- [x] Checked bulleted task
```

**Kern rendering:** Shows bullet dot + checkbox (`• ☐ text`), making the list structure visible.

**GFM rendering:** Shows just a checkbox without bullet indicator. The syntax is identical — only the rendering differs.

## Ordered Task Lists

**Syntax:** `1. [ ] text` or `1. [x] text` (GFM extension).

```
1. [ ] First ordered task
2. [x] Second ordered task (done)
3. [ ] Third ordered task
```

**Renders as:** Number + checkbox (`1. ☐ text`).

**GFM behavior:** Most GFM renderers treat `1. [ ] text` as a regular ordered list item with literal `[ ]` text. Kern recognizes the checkbox syntax inside ordered lists.

## Summary

| Syntax | Kern Rendering | GFM Behavior |
|--------|---------------|--------------|
| `[ ] text` | ☐ text (standalone checkbox) | Literal `[ ] text` |
| `- [ ] text` | • ☐ text (bulleted task) | ☐ text (task list, no bullet) |
| `1. [ ] text` | 1. ☐ text (ordered task) | 1. [ ] text (literal) |
| `- text` | • text (bullet list) | • text (same) |
| `1. text` | 1. text (ordered list) | 1. text (same) |

## Heading Checkboxes

**Syntax:** `## [ ] Heading text` or `## [x] Heading text` (any heading level).

```
# [ ] Top-level task heading
## [x] Completed section
### [ ] Sub-task heading
```

**Renders as:** A clickable checkbox before the heading text.

**GFM behavior:** Renders as a heading with literal `[ ]` or `[x]` in the text.

**Rationale:** AI agents often produce task headings with checkbox syntax. Kern renders these as interactive checkboxes rather than showing raw syntax.

## Summary

| Syntax | Kern Rendering | GFM Behavior |
|--------|---------------|--------------|
| `[ ] text` | ☐ text (standalone checkbox) | Literal `[ ] text` |
| `- [ ] text` | • ☐ text (bulleted task) | ☐ text (task list, no bullet) |
| `1. [ ] text` | 1. ☐ text (ordered task) | 1. [ ] text (literal) |
| `## [ ] text` | ☐ **Heading** (checkbox heading) | ## [ ] text (literal in heading) |
| `- text` | • text (bullet list) | • text (same) |
| `1. text` | 1. text (ordered list) | 1. text (same) |

## Compatibility

Files using Kern extensions are valid UTF-8 markdown. In other renderers:
- `[ ] text` appears as literal text (harmless)
- `- [ ] text` renders as a standard GFM task list (checkbox without bullet)
- `1. [ ] text` renders as an ordered list with `[ ]` prefix in the text
- `## [ ] text` renders as a heading with `[ ]` prefix in the text
