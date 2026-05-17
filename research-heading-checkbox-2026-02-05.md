# Research: Heading Checkbox Feature for Kern

> Historical research note retained for reference. It is not part of the active contributor quick-start path.

Date: 2026-02-05
Depth: Full

## Executive Summary

Implementing `## [ ] Heading` syntax in Milkdown/Kern requires extending the existing heading node schema. After researching Milkdown's architecture and the existing checkbox implementation, I've identified **two viable approaches** with different tradeoffs.

**Confidence: High** — The approach is well-understood based on the existing `checkbox.ts` pattern and Milkdown's heading schema.

## Sub-Questions Investigated

1. **How does Milkdown's heading schema work?**
   → `headingSchema` in `@milkdown/preset-commonmark` defines a node with `level` (1-6) and `id` attributes. Uses `headingAttr` for additional HTML attributes via `$nodeAttr`. The `toDOM` renders as `h1`-`h6` elements.

2. **Can `headingAttr` inject a `checked` attribute and custom rendering?**
   → **Partially.** `headingAttr` only adds HTML attributes to the DOM element — it cannot change the DOM structure (add checkbox icon). Need to **override the heading schema** or use **MutationObserver** for icon injection.

3. **How do remark plugins transform mdast nodes?**
   → The `$remark` utility creates plugins that transform the mdast tree before ProseMirror parses it. The existing `remarkCheckbox` in `checkbox.ts` shows the pattern: walk the tree, match specific node types, transform to custom node types.

4. **What's the pattern for click handlers on headings?**
   → Use `$prose` to create a ProseMirror plugin with `handleClickOn` prop, same as `checkboxClickPlugin`.

## Detailed Findings

### Approach A: Extend Heading Schema (Recommended)

**How it works:**
1. Create a new heading schema that adds `checked: boolean | null` attribute
2. The remark plugin transforms headings with `[ ]`/`[x]` prefix
3. `toDOM` renders a checkbox icon element before heading text (like `checkbox.ts` does)
4. `toMarkdown` serializes back with `## [x] Text` format
5. Click handler toggles the `checked` attribute

**Implementation:**
```typescript
// In heading-checkbox.ts
import { $nodeSchema, $remark, $prose } from "@milkdown/utils";

export const headingCheckboxSchema = $nodeSchema("heading", (ctx) => ({
  content: "inline*",
  group: "block",
  defining: true,
  attrs: {
    id: { default: "" },
    level: { default: 1 },
    checked: { default: null },  // null = no checkbox, false = unchecked, true = checked
  },
  parseDOM: [/* h1-h6 parsing */],
  toDOM: (node) => {
    const level = node.attrs.level;
    if (node.attrs.checked === null) {
      // Standard heading
      return [`h${level}`, { id: node.attrs.id }, 0];
    }
    // Heading with checkbox
    return [`h${level}`, { class: "kern-heading-checkbox", "data-checked": String(node.attrs.checked) },
      ["span", { class: "kern-heading-checkbox-icon", contenteditable: "false" }],
      ["span", { class: "kern-heading-checkbox-content" }, 0]
    ];
  },
  parseMarkdown: {
    match: ({ type }) => type === "heading",
    runner: (state, node, type) => {
      const depth = node.depth;
      // Check if first child text starts with [ ] or [x]
      // Extract checked state from node if transformed by remark plugin
      const checked = node.checked ?? null;
      state.openNode(type, { level: depth, checked });
      state.next(node.children);
      state.closeNode();
    },
  },
  toMarkdown: {
    match: (node) => node.type.name === "heading",
    runner: (state, node) => {
      // If checked attribute exists, we need to inject [ ] or [x] in the text
      const depth = node.attrs.level;
      state.openNode("heading", undefined, { depth });
      if (node.attrs.checked !== null) {
        // Inject checkbox marker at start
        const marker = node.attrs.checked ? "[x] " : "[ ] ";
        state.write(marker);
      }
      serializeText(state, node);
      state.closeNode();
    },
  },
}));
```

**Pros:**
- Clean, follows Milkdown patterns
- Checkbox state is part of the ProseMirror document model
- Works with undo/redo
- Type-safe

**Cons:**
- Overrides the existing heading schema — must register BEFORE commonmark
- Need to replicate all existing heading functionality
- More code

### Approach B: Remark Transform + MutationObserver (Simpler)

**How it works:**
1. Remark plugin transforms heading mdast nodes: extracts `[ ]`/`[x]` from text, adds `checked` property
2. The existing heading schema is NOT modified
3. MutationObserver (like checkbox.ts) watches for `.milkdown h1, h2...` elements and injects checkbox icons
4. Click handler uses `handleClick` (not `handleClickOn`) to find heading nodes and toggle

**Implementation:**
```typescript
// Remark plugin transforms heading mdast:
// Input: ## [ ] Task heading
// Output: heading node with children stripped of "[ ] " prefix, plus `checked: false` data

export const remarkHeadingCheckbox = $remark("remarkHeadingCheckbox", () =>
  function () {
    return (tree) => {
      // Walk tree, find heading nodes
      // If first text child starts with [ ] or [x], extract and set node.checked
    };
  }
);
```

**Problem:** The standard `headingSchema.parseMarkdown` ignores the `checked` property we add — it only reads `depth`. So the attribute is lost.

**Workaround:** Use `headingAttr` to inject `data-checked` attribute based on... but we don't have access to the mdast node in `headingAttr`.

**Verdict:** This approach doesn't work cleanly because Milkdown's heading parser doesn't forward custom mdast properties to ProseMirror attributes.

### Final Recommendation: Approach A

Override the heading schema with a version that adds `checked` attribute. This is the same pattern used for `checkbox.ts` (which creates a new block node type).

## Implementation Steps

1. **Create `CoreEditor/src/heading-checkbox.ts`:**
   - Define `headingCheckboxSchema` extending heading with `checked` attribute
   - Define `remarkHeadingCheckbox` to transform mdast headings
   - Define `headingCheckboxClickPlugin` for toggling
   - Define `initHeadingCheckboxIcons` for MutationObserver icon injection

2. **Update `CoreEditor/src/main.ts`:**
   - Import and register the new schema BEFORE Crepe's commonmark preset
   - Call `initHeadingCheckboxIcons()` in deferred init

3. **Add CSS in `CoreEditor/src/themes/kern.css`:**
   - `.kern-heading-checkbox` container styling
   - `.kern-heading-checkbox-icon` positioning (inline, before text)
   - `.kern-heading-checkbox-checked` styling

4. **Update `KERN-MARKDOWN.md`:**
   - Document heading checkbox syntax

5. **Add Playwright tests:**
   - Rendering `## [ ] Heading` and `## [x] Heading`
   - Click toggling
   - Serialization round-trip

## Key Challenge: Schema Override Order

Milkdown uses the LAST registered schema for each node name. To override heading:

```typescript
// In main.ts, AFTER Crepe setup but BEFORE create():
crepe.editor.use(headingCheckboxSchema.node);
crepe.editor.use(headingCheckboxSchema.ctx);
```

This should replace the default heading schema from commonmark.

**Verification needed:** Test that this actually overrides vs throws an error.

## Verified Claims (2+ sources)

- ProseMirror schemas can be extended with custom attributes ([ProseMirror Guide](https://prosemirror.net/docs/guide/), Milkdown source code)
- Milkdown's `$nodeSchema` creates a node type that can be registered via `.use()` (Milkdown source, checkbox.ts implementation)
- MutationObserver is the pattern for injecting icons into toDOM structures (checkbox.ts, mermaid.ts in this codebase)

## Unverified Claims

- Whether registering a schema with the same name (`"heading"`) after commonmark actually replaces it, or if it errors. **Needs testing.**

## Conflicts Resolved

- None identified

## Limitations & Gaps

- **Input rule:** Should typing `## [ ] ` trigger checkbox heading? Current plan: no input rule — only parse existing markdown. Users won't type this; AI agents produce it.
- **Block menu:** Should there be a slash command to create checkbox headings? Low priority — can add later if needed.
- **Nested checkboxes:** What if `## [ ] [ ] Double`? Current plan: only match first `[ ]`.

## Sources

| Source | URL | Quality | Accessed |
|--------|-----|---------|----------|
| Milkdown heading schema | node_modules/@milkdown/preset-commonmark/src/node/heading.ts | Official | 2026-02-05 |
| Kern checkbox.ts | CoreEditor/src/checkbox.ts | Project source | 2026-02-05 |
| Milkdown utils $nodeAttr | node_modules/@milkdown/utils/src/composable/composed/$attr.ts | Official | 2026-02-05 |
| ProseMirror Guide | https://prosemirror.net/docs/guide/ | Official | 2026-02-05 |
| Milkdown list-item schema | node_modules/@milkdown/preset-commonmark/src/node/list-item.ts | Official | 2026-02-05 |
