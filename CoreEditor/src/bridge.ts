import type { CrepeBuilder } from "@milkdown/crepe/builder";
import type { Ctx } from "@milkdown/kit/ctx";
import { replaceAll } from "@milkdown/utils";
import { callCommand } from "@milkdown/utils";
import { toggleStrongCommand } from "@milkdown/kit/preset/commonmark";
import { toggleEmphasisCommand } from "@milkdown/kit/preset/commonmark";
import { toggleInlineCodeCommand } from "@milkdown/kit/preset/commonmark";
import { undoCommand } from "@milkdown/kit/plugin/history";
import { redoCommand } from "@milkdown/kit/plugin/history";
import {
  showSearch as searchShow,
  hideSearch as searchHide,
  useSelectionForFind as searchUseSelection,
} from "./search";

declare global {
  interface Window {
    webkit?: {
      messageHandlers: {
        nativeBridge: {
          postMessage(message: unknown): void;
        };
      };
    };
    kern: KernBridge;
  }
}

export interface KernBridge {
  getMarkdown(): string;
  setMarkdown(markdown: string): void;
  setTheme(theme: "light" | "dark"): void;
  getScrollPosition(): number;
  setScrollPosition(position: number): void;
  execCommand(command: string): boolean;
  isReady(): boolean;
  showSearch(withReplace: boolean): void;
  hideSearch(): void;
  useSelectionForFind(): void;
}

function getScrollContainer(): Element {
  // #editor is the actual scroll container (overflow-y: auto, contains the full content)
  return document.getElementById("editor") || document.documentElement;
}

/** GitHub-style slug: lowercase, strip non-alphanumeric except hyphens, collapse spaces to hyphens */
function slugify(text: string): string {
  return text
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-");
}

/**
 * Scroll to a fragment anchor. Tries getElementById first, then falls back to
 * scanning headings by matching slugified text content.
 */
function scrollToFragment(fragment: string): void {
  // 1. Direct ID lookup
  const direct = document.getElementById(fragment);
  if (direct) {
    direct.scrollIntoView({ behavior: "smooth" });
    return;
  }

  // 2. Slugified match against heading elements
  const target = slugify(fragment);
  const editor = document.querySelector(".milkdown .editor");
  if (!editor) return;
  const headings = editor.querySelectorAll("h1, h2, h3, h4, h5, h6");
  for (const h of headings) {
    const hSlug = slugify(h.textContent || "");
    if (hSlug === target) {
      h.scrollIntoView({ behavior: "smooth" });
      return;
    }
    // Also check the element's actual id attribute (Milkdown's format)
    const hId = h.getAttribute("id");
    if (hId && slugify(hId) === target) {
      h.scrollIntoView({ behavior: "smooth" });
      return;
    }
  }
}

export function setupBridge(crepe: CrepeBuilder): KernBridge {
  let lastMarkdown = "";
  // Suppress native notifications during programmatic setMarkdown calls.
  // Milkdown normalizes markdown on parse→serialize, which would trigger
  // a false contentChanged → autosave → file modification date change.
  let suppressNativeNotify = false;

  const bridge: KernBridge = {
    getMarkdown(): string {
      return crepe.getMarkdown();
    },

    setMarkdown(markdown: string): void {
      suppressNativeNotify = true;
      lastMarkdown = markdown;
      crepe.editor.action(replaceAll(markdown, true));
      // Sync lastMarkdown to Milkdown's normalized form so future
      // user edits are correctly detected as changes.
      lastMarkdown = crepe.getMarkdown();
      suppressNativeNotify = false;
    },

    setTheme(theme: "light" | "dark"): void {
      document.documentElement.setAttribute("data-theme", theme);
      const milkdownEl = document.querySelector(".milkdown");
      if (milkdownEl) {
        milkdownEl.setAttribute("data-theme", theme);
      }
      // Update body background for the theme
      document.body.style.background =
        theme === "dark" ? "#1c1c1e" : "#ffffff";
    },

    getScrollPosition(): number {
      const container = getScrollContainer();
      return container ? container.scrollTop : 0;
    },

    setScrollPosition(position: number): void {
      const container = getScrollContainer();
      if (container) {
        container.scrollTop = position;
      }
    },

    execCommand(command: string): boolean {
      try {
        switch (command) {
          case "undo":
            return crepe.editor.action(callCommand(undoCommand.key));
          case "redo":
            return crepe.editor.action(callCommand(redoCommand.key));
          case "bold":
            return crepe.editor.action(callCommand(toggleStrongCommand.key));
          case "italic":
            return crepe.editor.action(callCommand(toggleEmphasisCommand.key));
          case "code":
            return crepe.editor.action(
              callCommand(toggleInlineCodeCommand.key)
            );
          default:
            console.warn(`Unknown command: ${command}`);
            return false;
        }
      } catch (e) {
        console.error(`Failed to execute command "${command}":`, e);
        return false;
      }
    },

    isReady(): boolean {
      return true;
    },

    showSearch(withReplace: boolean): void {
      searchShow(withReplace);
    },

    hideSearch(): void {
      searchHide();
    },

    useSelectionForFind(): void {
      searchUseSelection();
    },
  };

  // Register markdown change listener with dedup
  crepe.on((listener) => {
    listener.markdownUpdated(
      (_ctx: Ctx, markdown: string, prevMarkdown: string) => {
        // Dedup: skip if markdown hasn't changed
        if (markdown === lastMarkdown) return;
        lastMarkdown = markdown;

        // Suppress notifications during programmatic setMarkdown calls.
        // This prevents Milkdown's markdown normalization from triggering
        // a false dirty flag → autosave → unwanted file modification date change.
        if (suppressNativeNotify) return;

        // Notify Swift via message handler (if available)
        try {
          window.webkit?.messageHandlers.nativeBridge.postMessage({
            type: "contentChanged",
            markdown,
          });
        } catch {
          // Not in WKWebView — ignore
        }
      }
    );
  });

  // Track scroll position for tab virtualization (debounced 200ms)
  let scrollTimer: ReturnType<typeof setTimeout> | null = null;
  const scrollContainer = getScrollContainer();
  if (scrollContainer) {
    scrollContainer.addEventListener("scroll", () => {
      if (scrollTimer) clearTimeout(scrollTimer);
      scrollTimer = setTimeout(() => {
        try {
          window.webkit?.messageHandlers.nativeBridge.postMessage({
            type: "scrollChanged",
            position: scrollContainer.scrollTop,
          });
        } catch {
          // Not in WKWebView
        }
      }, 200);
    });
  }

  // Handle link clicks: tooltip link-display and Cmd+click in editor
  document.addEventListener(
    "click",
    (e: MouseEvent) => {
      const target = e.target as HTMLElement;

      // 1. Click on URL display in link tooltip
      const linkDisplay = target.closest(".link-display");
      if (linkDisplay) {
        const href =
          linkDisplay.getAttribute("href") || linkDisplay.textContent?.trim();
        if (href) {
          e.preventDefault();
          e.stopPropagation();
          if (href.startsWith("#")) {
            scrollToFragment(href.slice(1));
          } else {
            try {
              window.webkit?.messageHandlers.nativeBridge.postMessage({
                type: "openURL",
                url: href,
              });
            } catch {
              window.open(href, "_blank");
            }
          }
          return;
        }
      }

      // 2. Cmd+click on links in editor content
      if (e.metaKey) {
        const anchor = target.closest("a[href]") as HTMLAnchorElement | null;
        if (anchor) {
          const href = anchor.getAttribute("href");
          if (href) {
            e.preventDefault();
            e.stopPropagation();
            if (href.startsWith("#")) {
              scrollToFragment(href.slice(1));
            } else {
              try {
                window.webkit?.messageHandlers.nativeBridge.postMessage({
                  type: "openURL",
                  url: href,
                });
              } catch {
                window.open(href, "_blank");
              }
            }
          }
        }
      }
    },
    true,
  );

  // Hide link tooltips while Cmd is held — prevents tooltip from blocking
  // adjacent links when user is Cmd+clicking to open links.
  document.addEventListener(
    "keydown",
    (e: KeyboardEvent) => {
      if (e.key === "Meta") {
        document.documentElement.classList.add("kern-cmd-held");
      }
    },
    true,
  );
  document.addEventListener(
    "keyup",
    (e: KeyboardEvent) => {
      if (e.key === "Meta") {
        document.documentElement.classList.remove("kern-cmd-held");
      }
    },
    true,
  );
  window.addEventListener("blur", () => {
    document.documentElement.classList.remove("kern-cmd-held");
  });

  window.kern = bridge;
  return bridge;
}
