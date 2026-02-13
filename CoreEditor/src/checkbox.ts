/**
 * Standalone checkbox node — Kern extension to markdown.
 *
 * Syntax:  [ ] unchecked item   /   [x] checked item
 * Unlike GFM task lists (- [ ]), these are standalone paragraphs with a checkbox.
 * See KERN-MARKDOWN.md for spec differences.
 */

import { $nodeSchema, $inputRule, $remark, $prose } from "@milkdown/utils";
import { InputRule } from "@milkdown/prose/inputrules";
import { Plugin, PluginKey } from "@milkdown/prose/state";

// Same icons used by Milkdown's list-item-block
const checkedIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="M19 3H5C3.9 3 3 3.9 3 5V19C3 20.1 3.9 21 5 21H19C20.1 21 21 20.1 21 19V5C21 3.9 20.1 3 19 3ZM10.71 16.29C10.32 16.68 9.69 16.68 9.3 16.29L5.71 12.7C5.32 12.31 5.32 11.68 5.71 11.29C6.1 10.9 6.73 10.9 7.12 11.29L10 14.17L16.88 7.29C17.27 6.9 17.9 6.9 18.29 7.29C18.68 7.68 18.68 8.31 18.29 8.7L10.71 16.29Z"/></svg>`;
const uncheckedIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="M18 19H6C5.45 19 5 18.55 5 18V6C5 5.45 5.45 5 6 5H18C18.55 5 19 5.45 19 6V18C19 18.55 18.55 19 18 19ZM19 3H5C3.9 3 3 3.9 3 5V19C3 20.1 3.9 21 5 21H19C20.1 21 21 20.1 21 19V5C21 3.9 20.1 3 19 3Z"/></svg>`;

// ── Node Schema ──────────────────────────────────────────────────────────

export const checkboxSchema = $nodeSchema("checkbox", () => ({
  group: "block",
  content: "inline*",
  defining: true,
  attrs: {
    checked: { default: false },
  },
  parseDOM: [
    {
      tag: "div.kern-checkbox",
      getAttrs: (dom) => {
        if (!(dom instanceof HTMLElement)) return false;
        return { checked: dom.dataset.checked === "true" };
      },
    },
  ],
  toDOM: (node) => [
    "div",
    {
      class: `kern-checkbox${node.attrs.checked ? " kern-checkbox-checked" : ""}`,
      "data-checked": String(node.attrs.checked),
    },
    ["span", { class: "kern-checkbox-icon", contenteditable: "false" }],
    ["span", { class: "kern-checkbox-content" }, 0],
  ],
  parseMarkdown: {
    match: ({ type }: any) => type === "kern_checkbox",
    runner: (state: any, node: any, type: any) => {
      state.openNode(type, { checked: Boolean(node.checked) });
      if (node.children) {
        state.next(node.children);
      }
      state.closeNode();
    },
  },
  toMarkdown: {
    match: (node: any) => node.type.name === "checkbox",
    runner: (state: any, node: any) => {
      // Emit as kern_checkbox mdast node — the remark plugin serializes it
      state.openNode("kern_checkbox", undefined, {
        checked: node.attrs.checked,
      });
      state.next(node.content);
      state.closeNode();
    },
  },
}));

// ── Remark Plugin (parse + serialize) ────────────────────────────────────

/** Walk mdast tree, converting paragraphs starting with [ ] or [x] into kern_checkbox nodes. */
function transformCheckboxes(tree: any) {
  if (!tree.children) return;
  for (let i = 0; i < tree.children.length; i++) {
    const node = tree.children[i];
    if (node.type === "paragraph" && node.children?.length > 0) {
      const first = node.children[0];
      if (first.type === "text") {
        const match = first.value.match(/^\[( |x)\] /);
        if (match) {
          const checked = match[1] === "x";
          first.value = first.value.slice(match[0].length);
          if (first.value === "") {
            node.children.shift();
          }
          tree.children[i] = {
            type: "kern_checkbox",
            checked,
            children: node.children,
            position: node.position,
          };
        }
      }
    }
    // Recurse into block containers
    if (
      node.children &&
      ["blockquote", "listItem", "root", "footnoteDefinition"].includes(
        node.type
      )
    ) {
      transformCheckboxes(node);
    }
  }
}

/** mdast-util-to-markdown handler for kern_checkbox nodes. */
function handleKernCheckbox(node: any, _parent: any, state: any, info: any) {
  const marker = node.checked ? "[x] " : "[ ] ";
  const exit = state.enter("kern_checkbox");
  const content = state.containerPhrasing(node, info);
  exit();
  return marker + content;
}

export const remarkCheckbox = $remark("remarkCheckbox", () =>
  function (this: any) {
    // Register the serialization handler so remark-stringify knows about kern_checkbox
    let extensions: any[] = this.data("toMarkdownExtensions") || [];
    extensions = [
      ...extensions,
      { handlers: { kern_checkbox: handleKernCheckbox } },
    ];
    this.data("toMarkdownExtensions", extensions);

    // Return the parser transformer
    return (tree: any) => {
      transformCheckboxes(tree);
    };
  }
);

// ── Input Rule ───────────────────────────────────────────────────────────

export const checkboxInputRule = $inputRule((ctx) => {
  const checkboxType = checkboxSchema.type(ctx);
  return new InputRule(
    /^\[( |x)\] $/,
    (state, match, start, end) => {
      // Don't convert inside list items — let the GFM task list rule handle those
      const $start = state.doc.resolve(start);
      for (let d = $start.depth; d > 0; d--) {
        if ($start.node(d).type.name === "list_item") return null;
      }

      const checked = match[1] === "x";
      return state.tr
        .delete(start, end)
        .setBlockType(start, start, checkboxType, { checked });
    }
  );
});

// ── Click Handler Plugin ─────────────────────────────────────────────────

export const checkboxClickPlugin = $prose(() => {
  return new Plugin({
    key: new PluginKey("kern-checkbox-click"),
    props: {
      handleClickOn(view, _pos, node, nodePos, event) {
        if (node.type.name !== "checkbox") return false;
        const target = event.target as HTMLElement;
        if (!target.closest(".kern-checkbox-icon")) return false;

        view.dispatch(
          view.state.tr.setNodeMarkup(nodePos, undefined, {
            ...node.attrs,
            checked: !node.attrs.checked,
          })
        );
        return true;
      },
    },
  });
});

// ── Icon Injection ───────────────────────────────────────────────────────
// toDOM can't set innerHTML, so we inject icons via MutationObserver after mount.

let checkboxObserver: MutationObserver | null = null;

function updateCheckboxIcons(root: Element) {
  root.querySelectorAll(".kern-checkbox-icon").forEach((el) => {
    const parent = el.closest(".kern-checkbox");
    if (!parent) return;
    const checked = parent.getAttribute("data-checked") === "true";
    const icon = checked ? checkedIcon : uncheckedIcon;
    if (el.innerHTML !== icon) {
      el.innerHTML = icon;
    }
  });
}

export function initCheckboxIcons() {
  const editor = document.querySelector(".milkdown .editor");
  if (!editor) return;

  // Initial pass
  updateCheckboxIcons(editor);

  // Watch for new/changed checkboxes
  checkboxObserver?.disconnect();
  checkboxObserver = new MutationObserver(() => {
    updateCheckboxIcons(editor);
  });
  checkboxObserver.observe(editor, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["data-checked"],
  });
}
