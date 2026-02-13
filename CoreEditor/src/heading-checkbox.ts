/**
 * Heading checkbox extension — Kern extension to markdown.
 *
 * Syntax:  ## [ ] unchecked heading   /   ## [x] checked heading
 * Works with any heading level (h1-h6). AI agents often produce this syntax
 * for task headings. See KERN-MARKDOWN.md for spec.
 *
 * Architecture:
 * - Schema extension: adds `checked` attr to heading
 * - Remark plugin: parses [x]/[ ] from markdown heading text
 * - Decoration plugin: adds CSS classes + data attrs via PM node decorations
 *   (direct DOM manipulation loops infinitely — PM strips non-toDOM changes)
 * - CSS ::before pseudo-element renders the checkbox icon (no DOM injection)
 * - Click plugin: toggles checked state when click lands in ::before area
 */

import { headingSchema } from "@milkdown/kit/preset/commonmark";
import { $remark, $prose } from "@milkdown/utils";
import { Plugin, PluginKey } from "@milkdown/prose/state";
import { Decoration, DecorationSet } from "@milkdown/prose/view";

// ── Node Schema (extends built-in heading) ───────────────────────────────

export const headingCheckboxSchema = headingSchema.extendSchema(
  (prev) => {
    return (ctx) => {
      const baseSchema = prev(ctx);
      return {
        ...baseSchema,
        attrs: {
          ...baseSchema.attrs,
          checked: { default: null }, // null = no checkbox, false = unchecked, true = checked
        },
        parseMarkdown: {
          match: ({ type }: any) => type === "heading",
          runner: (state: any, node: any, type: any) => {
            if (node.checked == null) {
              baseSchema.parseMarkdown.runner(state, node, type);
              return;
            }
            const depth = node.depth as number;
            state.openNode(type, { level: depth, checked: node.checked });
            state.next(node.children);
            state.closeNode();
          },
        },
        toMarkdown: {
          match: (node: any) => node.type.name === "heading",
          runner: (state: any, node: any) => {
            if (node.attrs.checked === null) {
              baseSchema.toMarkdown.runner(state, node);
              return;
            }

            const depth = node.attrs.level;
            const checked = node.attrs.checked;
            state.openNode("heading", undefined, { depth });

            const marker = checked ? "[x] " : "[ ] ";
            state.addNode("text", [], marker);

            state.next(node.content);
            state.closeNode();
          },
        },
      };
    };
  }
);

// ── Remark Plugin (parse) ─────────────────────────────────────────────────

function transformHeadingCheckboxes(tree: any) {
  if (!tree.children) return;

  for (let i = 0; i < tree.children.length; i++) {
    const node = tree.children[i];

    if (node.type === "heading" && node.children?.length > 0) {
      const first = node.children[0];
      if (first.type === "text") {
        const match = first.value.match(/^\[( |x)\] /);
        if (match) {
          const checked = match[1] === "x";
          first.value = first.value.slice(match[0].length);
          if (first.value === "") {
            node.children.shift();
          }
          node.checked = checked;
        }
      }
    }

    if (
      node.children &&
      ["root", "blockquote", "footnoteDefinition"].includes(node.type)
    ) {
      transformHeadingCheckboxes(node);
    }
  }
}

export const remarkHeadingCheckbox = $remark(
  "remarkHeadingCheckbox",
  () =>
    function () {
      return (tree: any) => {
        transformHeadingCheckboxes(tree);
      };
    }
);

// ── Decoration Plugin ───────────────────────────────────────────────────
// PM node decorations add CSS classes and data attributes to heading elements.
// CSS ::before renders the checkbox icon — no DOM injection needed.

function buildDecorations(doc: any): DecorationSet {
  const decos: Decoration[] = [];
  doc.descendants((node: any, pos: number) => {
    if (node.type.name !== "heading") return;
    const checked = node.attrs.checked;
    if (checked == null) return;

    const classes = checked
      ? "kern-heading-checkbox kern-heading-checkbox-checked"
      : "kern-heading-checkbox";

    decos.push(
      Decoration.node(pos, pos + node.nodeSize, {
        class: classes,
        "data-heading-checked": String(checked),
      })
    );
  });
  return DecorationSet.create(doc, decos);
}

const decoPluginKey = new PluginKey("kern-heading-checkbox-deco");

export const headingCheckboxDecoPlugin = $prose(
  () =>
    new Plugin({
      key: decoPluginKey,
      state: {
        init(_, state) {
          return buildDecorations(state.doc);
        },
        apply(tr, decoSet) {
          if (tr.docChanged) {
            return buildDecorations(tr.doc);
          }
          return decoSet.map(tr.mapping, tr.doc);
        },
      },
      props: {
        decorations(state) {
          return decoPluginKey.getState(state);
        },
      },
    })
);

// ── Click Handler Plugin ─────────────────────────────────────────────────
// Toggles checked state when click lands in the ::before area (~first 30px).

const clickPluginKey = new PluginKey("kern-heading-checkbox-click");

export const headingCheckboxClickPlugin = $prose(
  () =>
    new Plugin({
      key: clickPluginKey,
      props: {
        handleClick(view, _pos, event) {
          // Find the heading element from the click target
          const target = event.target as HTMLElement;
          const heading = target.closest("h1, h2, h3, h4, h5, h6") as HTMLElement | null;
          if (!heading) return false;
          if (!heading.classList.contains("kern-heading-checkbox")) return false;

          // Check if click was in the ::before area (left side)
          const rect = heading.getBoundingClientRect();
          const clickX = event.clientX - rect.left;
          if (clickX > 30) return false;

          // Find the heading node in the document
          const pos = view.posAtDOM(heading, 0);
          const $pos = view.state.doc.resolve(pos);
          // Walk up to find the heading node
          for (let d = $pos.depth; d >= 0; d--) {
            const node = $pos.node(d);
            if (node.type.name === "heading" && node.attrs.checked != null) {
              const nodePos = $pos.before(d);
              view.dispatch(
                view.state.tr.setNodeMarkup(nodePos, undefined, {
                  ...node.attrs,
                  checked: !node.attrs.checked,
                })
              );
              return true;
            }
          }
          return false;
        },
      },
    })
);
