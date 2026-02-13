// Theme CSS — use export map paths
// common/* wildcard export maps to lib/theme/common/*
import "@milkdown/crepe/theme/common/style.css";
// classic.css export maps to lib/theme/classic/style.css — but that dir doesn't exist
// The actual dir is "crepe", so import directly via Vite alias
import "./themes/kern.css";

import { CrepeBuilder } from "@milkdown/crepe/builder";
import { blockEdit } from "@milkdown/crepe/feature/block-edit";
import { codeMirror } from "@milkdown/crepe/feature/code-mirror";
import { cursor } from "@milkdown/crepe/feature/cursor";
import { imageBlock } from "@milkdown/crepe/feature/image-block";
import { latex } from "@milkdown/crepe/feature/latex";
import { linkTooltip } from "@milkdown/crepe/feature/link-tooltip";
import { listItem } from "@milkdown/crepe/feature/list-item";
import { table } from "@milkdown/crepe/feature/table";
import { setupBridge } from "./bridge";
import { renderPreview } from "./mermaid";
import { showToast } from "./toast";
import { searchPlugin, initSearch } from "./search";
import { initInlineNested } from "./inline-nested";
import { listItemBlockConfig } from "@milkdown/kit/component/list-item-block";
import { commandsCtx, editorViewCtx } from "@milkdown/kit/core";
import {
  clearTextInCurrentBlockCommand,
  listItemSchema,
  orderedListSchema,
  setBlockTypeCommand,
  wrapInBlockTypeCommand,
} from "@milkdown/kit/preset/commonmark";
import {
  checkboxSchema,
  remarkCheckbox,
  checkboxInputRule,
  checkboxClickPlugin,
  initCheckboxIcons,
} from "./checkbox";
import {
  headingCheckboxSchema,
  remarkHeadingCheckbox,
  headingCheckboxClickPlugin,
  headingCheckboxDecoPlugin,
} from "./heading-checkbox";

// Checkmark SVG matching Crepe's 14×14 copy-button icon size
const checkIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>`;

// Copy button feedback — fires on click, independent of clipboard API promise.
// Crepe's onCopy depends on navigator.clipboard.writeText() resolving, which
// can silently fail in WKWebView. This click handler shows feedback regardless.
document.addEventListener('click', (e) => {
  const btn = (e.target as HTMLElement).closest('.copy-button') as HTMLElement | null;
  if (btn && !btn.classList.contains('kern-copied')) {
    const original = btn.innerHTML;
    btn.innerHTML = `${checkIcon} Copied!`;
    btn.classList.add('kern-copied');
    setTimeout(() => {
      btn.innerHTML = original;
      btn.classList.remove('kern-copied');
    }, 2000);
  }
});

// Crepe's 24×24 SVG icons for list item labels
const bulletIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/></svg>`;
const checkBoxCheckedIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="M19 3H5C3.9 3 3 3.9 3 5V19C3 20.1 3.9 21 5 21H19C20.1 21 21 20.1 21 19V5C21 3.9 20.1 3 19 3ZM10.71 16.29C10.32 16.68 9.69 16.68 9.3 16.29L5.71 12.7C5.32 12.31 5.32 11.68 5.71 11.29C6.1 10.9 6.73 10.9 7.12 11.29L10 14.17L16.88 7.29C17.27 6.9 17.9 6.9 18.29 7.29C18.68 7.68 18.68 8.31 18.29 8.7L10.71 16.29Z"/></svg>`;
const checkBoxUncheckedIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="M18 19H6C5.45 19 5 18.55 5 18V6C5 5.45 5.45 5 6 5H18C18.55 5 19 5.45 19 6V18C19 18.55 18.55 19 18 19ZM19 3H5C3.9 3 3 3.9 3 5V19C3 20.1 3.9 21 5 21H19C20.1 21 21 20.1 21 19V5C21 3.9 20.1 3 19 3Z"/></svg>`;

// Slash command icons
const taskListIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2" stroke="currentColor" stroke-width="2" fill="none"/><path d="M8 12l2.5 2.5L16 9" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
const bulletedTaskIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><circle cx="5" cy="12" r="2.5" fill="currentColor"/><rect x="11" y="6" width="10" height="10" rx="1.5" stroke="currentColor" stroke-width="1.5" fill="none"/><path d="M13.5 11l1.5 1.5L18 9.5" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
const orderedTaskIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><text x="2" y="16" font-size="12" font-family="sans-serif" font-weight="bold" fill="currentColor">1.</text><rect x="14" y="5" width="8" height="8" rx="1.5" stroke="currentColor" stroke-width="1.5" fill="none"/><path d="M16 9l1.5 1.5L20 7" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

const SAMPLE_MARKDOWN = `# Kern Editor

## Welcome to Kern — a macOS Markdown Editor

This is a **WYSIWYG** markdown editor built with *Milkdown Crepe*.
You can write in ~~plain text~~ rich markdown with \`inline code\`.

### Features

- **Bold**, *italic*, and ~~strikethrough~~ text
- Inline \`code\` formatting
- Links and images
- Math equations
- Mermaid diagrams

### Ordered Steps

1. Open a markdown file
2. Edit with WYSIWYG
3. Save automatically

### Task List

- [x] Build CoreEditor
- [x] Set up Milkdown Crepe
- [ ] Integrate with Swift
- [ ] Add file watching
- [ ] Tab virtualization

### [x] Completed Section

This heading has a checkbox that's checked.

### [ ] Pending Section

This heading has an unchecked checkbox.

#### Code Blocks

\`\`\`javascript
function greet(name) {
  console.log(\`Hello, \${name}!\`);
  return { greeting: \`Welcome to Kern\` };
}
\`\`\`

\`\`\`python
def fibonacci(n: int) -> list[int]:
    """Generate Fibonacci sequence."""
    a, b = 0, 1
    result = []
    for _ in range(n):
        result.append(a)
        a, b = b, a + b
    return result
\`\`\`

\`\`\`typescript
interface EditorConfig {
  theme: "light" | "dark";
  fontSize: number;
  fontFamily: string;
}

const config: EditorConfig = {
  theme: "light",
  fontSize: 16,
  fontFamily: "SF Pro Text",
};
\`\`\`

##### Table

| Feature | Status | Priority |
|---------|--------|----------|
| WYSIWYG | Done | High |
| Dark Mode | Done | High |
| LaTeX | Done | Medium |
| Mermaid | Done | Low |

##### Math

Inline math: $E = mc^2$

Block math:

$$
\\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}
$$

###### Blockquote

> "The best way to predict the future is to invent it."
> — Alan Kay

##### Links & Images

Visit [Milkdown](https://milkdown.dev) for documentation.

![Placeholder Image](https://via.placeholder.com/600x200/007aff/ffffff?text=Kern+Editor)

##### Mermaid Diagram

\`\`\`mermaid
flowchart TD
    A[Open File] --> B{File Type?}
    B -->|Markdown| C[Load in Editor]
    B -->|Other| D[Show Error]
    C --> E[Edit WYSIWYG]
    E --> F[Auto-save]
    F --> G[File Updated]
\`\`\`

##### 한국어 텍스트

Kern 에디터는 한국어 입력을 완벽하게 지원합니다.
한글 조합 중에도 텍스트가 올바르게 표시되며,
IME 입력 방식과 호환됩니다.

---

*Built with Milkdown Crepe on macOS*
`;

function reportError(error: unknown): void {
  const message =
    error instanceof Error ? error.message : String(error);
  const stack =
    error instanceof Error ? error.stack || "" : "";

  console.error("[Kern Error]", message, stack);

  // Report to Swift if available
  try {
    window.webkit?.messageHandlers.nativeBridge.postMessage({
      type: "error",
      message,
      stack,
    });
  } catch {
    // Not in WKWebView
  }
}

async function init(): Promise<void> {
  try {
    const t0 = performance.now();
    const root = document.getElementById("editor");
    if (!root) {
      throw new Error("Editor root element #editor not found");
    }

    // Determine if we're in WKWebView or standalone
    const isWKWebView = !!window.webkit?.messageHandlers?.nativeBridge;

    console.log(`[Kern Perf] Before Crepe init at ${(performance.now() - t0).toFixed(1)}ms`);

    // Create editor using CrepeBuilder — explicit feature loading for smaller bundle
    // (drops toolbar and placeholder, which Kern doesn't use)
    const crepe = new CrepeBuilder({
      root,
      defaultValue: isWKWebView ? "" : SAMPLE_MARKDOWN,
    });

    crepe.addFeature(codeMirror, { renderPreview });
    crepe.addFeature(blockEdit, {
      blockHandle: {
        getOffset: () => 0,
        getPlacement: ({ active }: any) =>
          active.node.type.name === 'heading' ? 'left' : 'left-start',
      },
      listGroup: {
        taskList: null, // Disable default — we replace with checkbox node
      },
      buildMenu: (builder: any) => {
        const listGroup = builder.getGroup('list');

        // Task List: standalone checkbox ([ ] syntax)
        listGroup.addItem('task-list', {
          label: 'Task List',
          icon: taskListIcon,
          onRun: (ctx: any) => {
            const commands = ctx.get(commandsCtx);
            const cbType = checkboxSchema.type(ctx);
            commands.call(clearTextInCurrentBlockCommand.key);
            commands.call(setBlockTypeCommand.key, {
              nodeType: cbType,
              attrs: { checked: false },
            });
          },
        });

        // Bulleted Task: bullet list + checkbox (- [ ] syntax)
        listGroup.addItem('bulleted-task', {
          label: 'Bulleted Task',
          icon: bulletedTaskIcon,
          onRun: (ctx: any) => {
            const commands = ctx.get(commandsCtx);
            const listItemType = listItemSchema.type(ctx);
            commands.call(clearTextInCurrentBlockCommand.key);
            commands.call(wrapInBlockTypeCommand.key, {
              nodeType: listItemType,
              attrs: { checked: false },
            });
          },
        });

        // Ordered Task: ordered list + checkbox (1. [ ] syntax)
        listGroup.addItem('ordered-task', {
          label: 'Ordered Task',
          icon: orderedTaskIcon,
          onRun: (ctx: any) => {
            const commands = ctx.get(commandsCtx);
            const orderedList = orderedListSchema.type(ctx);

            commands.call(clearTextInCurrentBlockCommand.key);
            commands.call(wrapInBlockTypeCommand.key, {
              nodeType: orderedList,
            });

            const view = ctx.get(editorViewCtx);
            const { state } = view;
            const { $from } = state.selection;
            for (let d = $from.depth; d > 0; d--) {
              const node = $from.node(d);
              if (node.type.name === 'list_item') {
                const pos = $from.before(d);
                view.dispatch(
                  state.tr.setNodeMarkup(pos, undefined, {
                    ...node.attrs,
                    checked: false,
                  })
                );
                break;
              }
            }
          },
        });
      },
    } as any);
    crepe.addFeature(linkTooltip, { onCopyLink: () => showToast("Link copied") });
    crepe.addFeature(listItem);
    crepe.addFeature(cursor);
    crepe.addFeature(imageBlock);
    crepe.addFeature(table);
    crepe.addFeature(latex);

    // Show all nesting indicators for checked items (e.g., "1. • ☑" not just "☑").
    // When a checked item is inside a bullet or ordered list, renderLabel returns
    // both the list type indicator and the checkbox icon so every nesting level
    // is visible after CSS collapses the structure to one line.
    crepe.editor.config((ctx) => {
      ctx.update(listItemBlockConfig.key, (prev) => ({
        ...prev,
        renderLabel: ({
          label,
          listType,
          checked,
        }: {
          label: string;
          listType: string;
          checked?: boolean | null;
        }) => {
          if (checked == null) {
            if (listType === "bullet") return bulletIcon;
            return label;
          }
          const checkIcon = checked
            ? checkBoxCheckedIcon
            : checkBoxUncheckedIcon;
          if (listType === "ordered") {
            return `<span class="kern-combined-label kern-ordered-check"><span class="kern-indicator">${label}</span>${checkIcon}</span>`;
          }
          return `<span class="kern-combined-label"><span class="kern-indicator">${bulletIcon}</span>${checkIcon}</span>`;
        },
      }));
    });

    // Register plugins before creating editor
    crepe.editor.use(searchPlugin);
    crepe.editor.use(remarkCheckbox);
    crepe.editor.use(checkboxSchema.node);
    crepe.editor.use(checkboxSchema.ctx);
    crepe.editor.use(checkboxInputRule);
    crepe.editor.use(checkboxClickPlugin);

    // Heading checkbox — extends heading schema with optional checkbox
    crepe.editor.use(remarkHeadingCheckbox);
    crepe.editor.use(headingCheckboxSchema.node);
    crepe.editor.use(headingCheckboxSchema.ctx);
    crepe.editor.use(headingCheckboxClickPlugin);
    crepe.editor.use(headingCheckboxDecoPlugin);

    // Set up bridge before creating editor (registers listener)
    const bridge = setupBridge(crepe);

    // Create the editor
    await crepe.create();
    console.log(`[Kern Perf] crepe.create() complete at ${(performance.now() - t0).toFixed(1)}ms`);


    // Check for pre-injected content from Swift. When a document's stringValue
    // is set while the WKWebView is still loading, Swift injects the markdown
    // as window.__kern_initialContent via callAsyncJavaScript. Applying it here
    // (before posting editorReady) eliminates the editorReady→setMarkdown round-trip.
    const initialContent = (window as any).__kern_initialContent as string | undefined;
    if (initialContent) {
      bridge.setMarkdown(initialContent);
      delete (window as any).__kern_initialContent;
      console.log(`[Kern Perf] Initial content applied at ${(performance.now() - t0).toFixed(1)}ms`);
    }

    // Notify Swift that editor is ready
    try {
      window.webkit?.messageHandlers.nativeBridge.postMessage({
        type: "editorReady",
      });
    } catch {
      // Not in WKWebView (standalone dev mode, or pre-loaded warm-up WKWebView)
    }

    // Defer non-critical init — search, inline-nested, checkbox icons
    // These can run while Swift is pushing content via setMarkdown()
    setTimeout(() => {
      initSearch(crepe);
      initInlineNested();
      initCheckboxIcons();
      // Expose editor view for heading checkbox toggle tests
      (window as any).__kern_editorView = crepe.editor.ctx.get(editorViewCtx);
    }, 0);

    console.log(`[Kern Perf] Init complete at ${(performance.now() - t0).toFixed(1)}ms`);
  } catch (error) {
    reportError(error);
  }
}

init();
