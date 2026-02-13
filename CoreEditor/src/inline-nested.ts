/**
 * Inline nested checkboxes — collapse single-item nesting chains.
 *
 * Detects the pattern: a list item whose only content is an empty paragraph
 * followed by a single-item nested list (ul/ol). Marks these items with the
 * CSS class `kern-inline-nested` so that CSS can collapse the intermediate
 * wrappers with `display: contents`, rendering all labels on one line.
 *
 * Handles recursive nesting: `1. - 1. [x] text` → `1. • ☑ text`.
 *
 * Uses MutationObserver to re-scan whenever the editor DOM changes.
 */

const MARKER_CLASS = "kern-inline-nested";

function markCollapsible(): void {
  // Remove stale marks
  for (const el of document.querySelectorAll(`.${MARKER_CLASS}`)) {
    el.classList.remove(MARKER_CLASS);
  }

  // Find empty paragraphs (p with only a <br> child) inside .content-dom
  const emptyPs = document.querySelectorAll(
    ".milkdown .editor .content-dom > p:first-child:has(> br:only-child)",
  );

  for (const p of emptyPs) {
    const contentDom = p.parentElement;
    if (!contentDom?.classList.contains("content-dom")) continue;

    // Next sibling must be a ul/ol and the last child of content-dom
    const nextSib = p.nextElementSibling;
    if (!nextSib) continue;
    if (nextSib.tagName !== "UL" && nextSib.tagName !== "OL") continue;
    if (nextSib !== contentDom.lastElementChild) continue;

    // The ul/ol must have exactly one .milkdown-list-item-block child
    const blocks = nextSib.querySelectorAll(
      ":scope > .milkdown-list-item-block",
    );
    if (blocks.length !== 1) continue;

    // Mark the ancestor .list-item
    const listItem = contentDom.closest(".list-item");
    if (listItem) {
      listItem.classList.add(MARKER_CLASS);
    }
  }
}

/**
 * Initialize inline-nested detection. Call after the editor is created.
 */
export function initInlineNested(): void {
  // Initial scan
  markCollapsible();

  // Observe future DOM mutations in the editor
  const editor = document.querySelector(".milkdown .editor");
  if (editor) {
    const observer = new MutationObserver(() => {
      requestAnimationFrame(markCollapsible);
    });
    observer.observe(editor, { childList: true, subtree: true });
  }
}
