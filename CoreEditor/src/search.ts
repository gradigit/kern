import type { CrepeBuilder } from "@milkdown/crepe/builder";
import { Plugin, PluginKey, TextSelection } from "@milkdown/kit/prose/state";
import type { EditorState, Transaction } from "@milkdown/kit/prose/state";
import { Decoration, DecorationSet } from "@milkdown/kit/prose/view";
import type { EditorView } from "@milkdown/kit/prose/view";
import { $prose } from "@milkdown/utils";
import type { Ctx } from "@milkdown/kit/ctx";
import { editorViewCtx } from "@milkdown/kit/core";

// ── Plugin State ──────────────────────────────────────────────────────────

interface SearchState {
  query: string;
  matches: Array<{ from: number; to: number }>;
  currentIndex: number;
  caseSensitive: boolean;
  showReplace: boolean;
}

const initialState: SearchState = {
  query: "",
  matches: [],
  currentIndex: -1,
  caseSensitive: false,
  showReplace: false,
};

const searchPluginKey = new PluginKey<SearchState>("kern-search");

// ── Meta actions dispatched via transactions ─────────────────────────────

interface SearchMeta {
  action:
    | "setQuery"
    | "nextMatch"
    | "prevMatch"
    | "toggleCase"
    | "clear"
    | "setShowReplace";
  query?: string;
  showReplace?: boolean;
}

function dispatchSearch(view: EditorView, meta: SearchMeta) {
  const tr = view.state.tr;
  tr.setMeta(searchPluginKey, meta);
  view.dispatch(tr);
}

// ── Match finding ─────────────────────────────────────────────────────────

function findMatches(
  doc: EditorState["doc"],
  query: string,
  caseSensitive: boolean,
): Array<{ from: number; to: number }> {
  if (!query) return [];
  const matches: Array<{ from: number; to: number }> = [];
  const searchStr = caseSensitive ? query : query.toLowerCase();

  doc.descendants((node, pos) => {
    if (!node.isText || !node.text) return;
    const text = caseSensitive ? node.text : node.text.toLowerCase();
    let index = 0;
    while (index < text.length) {
      const found = text.indexOf(searchStr, index);
      if (found === -1) break;
      matches.push({ from: pos + found, to: pos + found + query.length });
      index = found + 1;
    }
  });

  return matches;
}

// ── Search UI ─────────────────────────────────────────────────────────────

let searchBarEl: HTMLElement | null = null;
let searchInput: HTMLInputElement | null = null;
let replaceInput: HTMLInputElement | null = null;
let counterEl: HTMLElement | null = null;
let replaceRow: HTMLElement | null = null;
let debounceTimer: ReturnType<typeof setTimeout> | null = null;
let currentView: EditorView | null = null;

function createSearchBar(view: EditorView): HTMLElement {
  const bar = document.createElement("div");
  bar.className = "kern-search-bar";
  bar.addEventListener("keydown", (e) => e.stopPropagation());

  // Search row
  const searchRow = document.createElement("div");
  searchRow.className = "kern-search-row";

  const expandBtn = document.createElement("button");
  expandBtn.className = "kern-search-btn kern-search-expand";
  expandBtn.innerHTML = `<svg width="12" height="12" viewBox="0 0 12 12"><path d="M4 3l4 3-4 3" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  expandBtn.title = "Toggle Replace";
  expandBtn.addEventListener("click", () => {
    dispatchSearch(view, { action: "setShowReplace" });
  });
  searchRow.appendChild(expandBtn);

  const input = document.createElement("input");
  input.type = "text";
  input.className = "kern-search-input";
  input.placeholder = "Find\u2026";
  input.addEventListener("input", () => {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      dispatchSearch(view, { action: "setQuery", query: input.value });
    }, 150);
  });
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      if (e.shiftKey) {
        dispatchSearch(view, { action: "prevMatch" });
      } else {
        dispatchSearch(view, { action: "nextMatch" });
      }
    }
    if (e.key === "Escape") {
      e.preventDefault();
      hideSearchBar(view);
    }
  });
  searchRow.appendChild(input);
  searchInput = input;

  const counter = document.createElement("span");
  counter.className = "kern-search-counter";
  counter.textContent = "0 of 0";
  searchRow.appendChild(counter);
  counterEl = counter;

  const prevBtn = document.createElement("button");
  prevBtn.className = "kern-search-btn";
  prevBtn.innerHTML = `<svg width="12" height="12" viewBox="0 0 12 12"><path d="M9 8L6 5 3 8" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  prevBtn.title = "Previous (Shift+Enter)";
  prevBtn.addEventListener("click", () =>
    dispatchSearch(view, { action: "prevMatch" }),
  );
  searchRow.appendChild(prevBtn);

  const nextBtn = document.createElement("button");
  nextBtn.className = "kern-search-btn";
  nextBtn.innerHTML = `<svg width="12" height="12" viewBox="0 0 12 12"><path d="M3 4l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  nextBtn.title = "Next (Enter)";
  nextBtn.addEventListener("click", () =>
    dispatchSearch(view, { action: "nextMatch" }),
  );
  searchRow.appendChild(nextBtn);

  const caseBtn = document.createElement("button");
  caseBtn.className = "kern-search-btn kern-search-case";
  caseBtn.textContent = "Aa";
  caseBtn.title = "Match Case";
  caseBtn.addEventListener("click", () =>
    dispatchSearch(view, { action: "toggleCase" }),
  );
  searchRow.appendChild(caseBtn);

  const closeBtn = document.createElement("button");
  closeBtn.className = "kern-search-btn kern-search-close";
  closeBtn.innerHTML = `<svg width="12" height="12" viewBox="0 0 12 12"><path d="M3 3l6 6M9 3l-6 6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>`;
  closeBtn.title = "Close (Esc)";
  closeBtn.addEventListener("click", () => hideSearchBar(view));
  searchRow.appendChild(closeBtn);

  bar.appendChild(searchRow);

  // Replace row
  const rRow = document.createElement("div");
  rRow.className = "kern-replace-row";
  rRow.style.display = "none";

  const rInput = document.createElement("input");
  rInput.type = "text";
  rInput.className = "kern-search-input kern-replace-input";
  rInput.placeholder = "Replace\u2026";
  rInput.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      e.preventDefault();
      hideSearchBar(view);
    }
  });
  rRow.appendChild(rInput);
  replaceInput = rInput;

  const replaceBtn = document.createElement("button");
  replaceBtn.className = "kern-search-btn kern-replace-btn";
  replaceBtn.textContent = "Replace";
  replaceBtn.addEventListener("click", () => replaceCurrent(view));
  rRow.appendChild(replaceBtn);

  const replaceAllBtn = document.createElement("button");
  replaceAllBtn.className = "kern-search-btn kern-replace-btn";
  replaceAllBtn.textContent = "Replace All";
  replaceAllBtn.addEventListener("click", () => replaceAll(view));
  rRow.appendChild(replaceAllBtn);

  bar.appendChild(rRow);
  replaceRow = rRow;

  return bar;
}

function showSearchBar(view: EditorView, withReplace: boolean) {
  currentView = view;

  if (!searchBarEl) {
    searchBarEl = createSearchBar(view);
    document.body.appendChild(searchBarEl);
  }

  searchBarEl.style.display = "";

  if (withReplace) {
    dispatchSearch(view, { action: "setShowReplace", showReplace: true });
  }

  // Focus input and select existing text
  setTimeout(() => {
    searchInput?.focus();
    searchInput?.select();
  }, 0);
}

function hideSearchBar(view: EditorView) {
  if (searchBarEl) {
    searchBarEl.style.display = "none";
  }
  dispatchSearch(view, { action: "clear" });
  view.focus();
}

function updateUI(state: SearchState) {
  if (!searchBarEl) return;

  // Update counter
  if (counterEl) {
    if (state.matches.length === 0) {
      counterEl.textContent = state.query ? "0 results" : "";
    } else {
      counterEl.textContent = `${state.currentIndex + 1} of ${state.matches.length}`;
    }
  }

  // Update replace row visibility
  if (replaceRow) {
    replaceRow.style.display = state.showReplace ? "" : "none";
  }

  // Update expand button rotation
  const expandBtn = searchBarEl.querySelector(".kern-search-expand");
  if (expandBtn) {
    (expandBtn as HTMLElement).classList.toggle("expanded", state.showReplace);
  }

  // Update case button active state
  const caseBtn = searchBarEl.querySelector(".kern-search-case");
  if (caseBtn) {
    (caseBtn as HTMLElement).classList.toggle("active", state.caseSensitive);
  }
}

// ── Replace operations ───────────────────────────────────────────────────

function replaceCurrent(view: EditorView) {
  const state = searchPluginKey.getState(view.state);
  if (!state || state.matches.length === 0 || !replaceInput) return;

  const match = state.matches[state.currentIndex];
  if (!match) return;

  const replaceText = replaceInput.value;
  const tr = view.state.tr.replaceWith(
    match.from,
    match.to,
    replaceText ? view.state.schema.text(replaceText) : [],
  );
  tr.setMeta(searchPluginKey, { action: "setQuery", query: searchInput?.value ?? "" });
  view.dispatch(tr);
}

function replaceAll(view: EditorView) {
  const state = searchPluginKey.getState(view.state);
  if (!state || state.matches.length === 0 || !replaceInput) return;

  const replaceText = replaceInput.value;
  // Replace in reverse order to preserve positions
  let tr = view.state.tr;
  const sorted = [...state.matches].sort((a, b) => b.from - a.from);
  for (const match of sorted) {
    tr = tr.replaceWith(
      match.from,
      match.to,
      replaceText ? view.state.schema.text(replaceText) : [],
    );
  }
  tr.setMeta(searchPluginKey, { action: "setQuery", query: searchInput?.value ?? "" });
  view.dispatch(tr);
}

// ── ProseMirror Plugin ───────────────────────────────────────────────────

export const searchPlugin = $prose((_ctx: Ctx) => {
  return new Plugin<SearchState>({
    key: searchPluginKey,

    state: {
      init(): SearchState {
        return { ...initialState };
      },

      apply(tr: Transaction, prev: SearchState, _oldState, newState): SearchState {
        const meta = tr.getMeta(searchPluginKey) as SearchMeta | undefined;
        if (!meta) {
          // If doc changed and we have an active query, recompute matches
          if (tr.docChanged && prev.query) {
            const matches = findMatches(newState.doc, prev.query, prev.caseSensitive);
            let currentIndex = prev.currentIndex;
            if (currentIndex >= matches.length) {
              currentIndex = matches.length > 0 ? 0 : -1;
            }
            const next = { ...prev, matches, currentIndex };
            updateUI(next);
            return next;
          }
          return prev;
        }

        let next = { ...prev };

        switch (meta.action) {
          case "setQuery": {
            const query = meta.query ?? "";
            const matches = findMatches(newState.doc, query, prev.caseSensitive);
            next = {
              ...prev,
              query,
              matches,
              currentIndex: matches.length > 0 ? 0 : -1,
            };
            break;
          }
          case "nextMatch": {
            if (prev.matches.length > 0) {
              next = {
                ...prev,
                currentIndex: (prev.currentIndex + 1) % prev.matches.length,
              };
            }
            break;
          }
          case "prevMatch": {
            if (prev.matches.length > 0) {
              next = {
                ...prev,
                currentIndex:
                  (prev.currentIndex - 1 + prev.matches.length) %
                  prev.matches.length,
              };
            }
            break;
          }
          case "toggleCase": {
            const caseSensitive = !prev.caseSensitive;
            const matches = findMatches(newState.doc, prev.query, caseSensitive);
            next = {
              ...prev,
              caseSensitive,
              matches,
              currentIndex: matches.length > 0 ? 0 : -1,
            };
            break;
          }
          case "setShowReplace": {
            next = {
              ...prev,
              showReplace: meta.showReplace ?? !prev.showReplace,
            };
            break;
          }
          case "clear": {
            next = { ...initialState };
            break;
          }
        }

        updateUI(next);
        return next;
      },
    },

    props: {
      decorations(state: EditorState): DecorationSet {
        const searchState = searchPluginKey.getState(state);
        if (!searchState || searchState.matches.length === 0) {
          return DecorationSet.empty;
        }

        const decorations = searchState.matches.map((match, i) =>
          Decoration.inline(match.from, match.to, {
            class:
              i === searchState.currentIndex
                ? "kern-search-current"
                : "kern-search-match",
          }),
        );

        return DecorationSet.create(state.doc, decorations);
      },
    },

    view(view: EditorView) {
      currentView = view;
      return {
        update(view: EditorView) {
          const state = searchPluginKey.getState(view.state);
          if (state && state.currentIndex >= 0 && state.matches[state.currentIndex]) {
            const match = state.matches[state.currentIndex];
            // Scroll current match into view
            const coords = view.coordsAtPos(match.from);
            const searchBarHeight = searchBarEl?.offsetHeight ?? 0;
            const editorRoot = document.getElementById("editor");
            if (editorRoot && coords) {
              const rect = editorRoot.getBoundingClientRect();
              // If match is above the visible area (behind search bar) or below, scroll
              if (
                coords.top < rect.top + searchBarHeight + 8 ||
                coords.bottom > rect.bottom - 8
              ) {
                editorRoot.scrollBy({
                  top: coords.top - rect.top - searchBarHeight - 40,
                  behavior: "smooth",
                });
              }
            }
          }
        },
      };
    },
  });
});

// ── Bridge API ────────────────────────────────────────────────────────────

let crepeRef: CrepeBuilder | null = null;

export function initSearch(crepe: CrepeBuilder): void {
  crepeRef = crepe;

  // Intercept Cmd+F / Cmd+Shift+H / Cmd+E at document level (capture phase).
  // WKWebView has a built-in find (Cmd+F) that runs in the view hierarchy
  // BEFORE the NSMenu keyboard equivalents, so we must catch these in JS.
  document.addEventListener(
    "keydown",
    (e: KeyboardEvent) => {
      if (!e.metaKey) return;
      if (e.key === "f" && !e.shiftKey) {
        e.preventDefault();
        e.stopPropagation();
        showSearch(false);
      } else if (e.key === "h" && e.shiftKey) {
        e.preventDefault();
        e.stopPropagation();
        showSearch(true);
      } else if (e.key === "e" && !e.shiftKey) {
        e.preventDefault();
        e.stopPropagation();
        useSelectionForFind();
      }
    },
    true,
  );
}

export function showSearch(withReplace: boolean): void {
  if (!crepeRef) return;
  crepeRef.editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    showSearchBar(view, withReplace);
  });
}

export function hideSearch(): void {
  if (!crepeRef) return;
  crepeRef.editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    hideSearchBar(view);
  });
}

export function useSelectionForFind(): void {
  if (!crepeRef) return;
  crepeRef.editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    const { from, to } = view.state.selection;
    if (from !== to) {
      const text = view.state.doc.textBetween(from, to);
      showSearchBar(view, false);
      if (searchInput) {
        searchInput.value = text;
        dispatchSearch(view, { action: "setQuery", query: text });
      }
    } else {
      showSearchBar(view, false);
    }
  });
}
