# Research: WYSIWYG Markdown Input Rules (Notion + GitHub Benchmarks)
Date: 2026-02-13
Depth: Full

## Executive Summary
For a native WYSIWYG Markdown editor, Notion provides the clearest, documented baseline for “type-to-convert” input rules (headings, lists, to-dos) and GitHub provides a well-documented baseline for list auto-continuation behavior on Enter (including Shift+Enter escape). For Markdown fidelity, GitHub Flavored Markdown (GFM) defines task list syntax as list items with `[ ]` / `[x]` markers, and ordered lists as `1.` / `1)` markers (numbers after the first are not semantically important).

Recommendation for Kern MVP behavior:
- Use Notion-style input rules for creating blocks (fast, learnable, documented).
- Use GitHub-style “press Enter to continue list, press Enter on empty item to exit, Shift+Enter to escape” behavior for list editing.
- Render task items as checkboxes without visible bullet markers (matches user expectations and common renderers), while exporting to standard GFM `- [ ]` task list items for `.md` interoperability.

## Sub-Questions Investigated
1. What typed shortcuts should create headings, bulleted lists, numbered lists, and checkboxes in a WYSIWYG editor?
2. What should Enter / Shift+Enter do inside lists and headings?
3. What’s the canonical Markdown syntax for checkboxes and numbered lists (so Kern exports valid `.md`)?
4. What UI affordances do code blocks typically have (copy button, wrapping)?

## Detailed Findings

### 1) Notion “Type-to-Convert” Shortcuts
Notion documents Markdown-like shortcuts for quickly creating block types:
- To-do checkbox: type `[]` followed by a space (no space inside the brackets). (Notion Keyboard Shortcuts)
- Numbered list: type `1.` / `a.` / `i.` followed by a space. (Notion Keyboard Shortcuts)
- Bulleted list: type `*` / `-` / `+` followed by a space. (Notion Writing & editing basics)
- Headings: type `#` / `##` / `###` followed by a space. (Notion Writing & editing basics)

Sources:
- Notion Help Center: “Keyboard shortcuts” (Markdown shortcuts section)
- Notion Help Center: “Writing & editing basics” (Markdown shortcut section)

### 2) Enter / Shift+Enter List Behavior (GitHub Baseline)
GitHub’s Markdown editor documents list auto-completion behavior:
- When writing list syntax (bullets, numbers, task lists), pressing Enter auto-completes the next list marker.
- Press Shift+Enter to skip the autocomplete and continue writing on the next line.

Source:
- GitHub Changelog: “List syntax is autocompleted in the Markdown editor” (2022-05-12)
 - GitHub Changelog: “Markdown list syntax now autocompleted” (2020-12-15)

Practical WYSIWYG mapping (recommended for Kern):
- Enter at end of non-empty list item: create the next list item (same type).
- Enter on an empty list item: exit the list (convert to paragraph).
- Shift+Enter: insert a line break without creating a new list item.

### 3) Markdown Ground Truth: Task Lists + Ordered Lists
GFM defines:
- Task list items as list items that begin with `[ ]` or `[x]` (case-insensitive) in the first block of the list item.
- Ordered list markers as digits followed by `.` or `)` (eg `1.`), with indentation/spacing rules.

Sources:
- GFM Spec: Task list items extension
- GFM Spec: Lists section (ordered list marker)

Implication:
- Kern can safely export to `- [ ] ...` / `- [x] ...` for maximum compatibility, even if the UI uses a Notion-style `[] ` shortcut to create the block.

### 4) Code Block UX (Copy / Wrap)
Notion’s guide for code blocks mentions offering options such as wrapping code or copying to clipboard. Multiple non-official but consistent sources describe a copy button shown on hover.

Sources:
- Notion Help Center: “Code blocks” (mentions wrap/copy options)
- Notionyelp: “Code Block in Notion” (describes copy button top-right)
- Obsidian forum discussion referencing Notion’s code-block copy button

## Hypothesis Assessment
| Hypothesis | Confidence | Supporting Evidence | Contradicting Evidence |
|---|---|---|---|
| H1: Notion-style typed shortcuts are the best MVP baseline for WYSIWYG block creation. | High | Notion documents stable shortcuts across block types. | None found. |
| H2: GitHub’s Enter/Shift+Enter list auto-completion behavior maps cleanly to WYSIWYG list editing. | Medium | GitHub documents autocomplete and Shift+Enter escape. | GitHub is source-mode; exact cursor semantics differ from WYSIWYG blocks. |
| H3: Exporting task items as GFM `- [ ]` is the most interoperable `.md` format. | High | Defined in GFM spec; widely supported. | Some apps treat tasks as extensions. |

## Verification Status
### Verified (2+ sources)
- Notion supports `[] ` -> to-do checkbox shortcut. (Notion Keyboard Shortcuts; also repeated in many guides)
- Notion supports `1. ` (and variants) -> numbered list shortcut. (Notion Keyboard Shortcuts; Notion Writing & editing basics)
- GitHub autocompletes list syntax on Enter and uses Shift+Enter to skip. (GitHub Changelog; commonly observed behavior)
- GFM defines task list item markers `[ ]` / `[x]` (GFM spec; widely implemented)

### Medium confidence (2 sources, but not both official)
- Notion uses Shift+Enter to insert a line break within the same block, and Markdown export differentiates in-block breaks vs. new blocks. (Reddit anecdote + third-party Notion Markdown compatibility guide)

### Unverified / Needs Better Sources
- Exact Notion behavior for “exit heading on Enter” (likely true because headings are blocks; needs an official line or a controlled test).
- Exact Notion behavior for “exit list on empty item Enter” (commonly true; needs an official line or a controlled test).
- Exact Notion UI details for code-block copy button placement/hover (official docs mention copy option but not UI specifics).

## Limitations & Gaps
- Notion’s official docs describe shortcuts but often don’t specify precise cursor/Enter edge cases.
- “Official” behavior is often emergent UX rather than standardized spec; expect to tune based on user testing.

## Sources
| Source | URL | Quality | Accessed |
|---|---|---:|---|
| Notion Help Center: Keyboard shortcuts | https://www.notion.so/help/keyboard-shortcuts | Official | 2026-02-13 |
| Notion Help Center: Writing & editing basics | https://www.notion.com/help/writing-and-editing-basics | Official | 2026-02-13 |
| GitHub Changelog: List syntax autocomplete | https://github.blog/changelog/2022-05-12-list-syntax-is-autocompleted-in-the-markdown-editor/ | Official | 2026-02-13 |
| GitHub Changelog: Markdown list syntax now autocompleted | https://github.blog/changelog/2020-12-15-markdown-list-syntax-now-autocompleted/ | Official | 2026-02-13 |
| GFM Spec: Task list items | https://github.github.com/gfm/#task-list-items-extension- | Official | 2026-02-13 |
| Notion Help Center: Code blocks | https://www.notion.so/help/guides/code-blocks | Official | 2026-02-13 |
| Notionyelp: Code Block in Notion | https://notionyelp.com/code-block-in-notion/ | Medium | 2026-02-13 |
| Obsidian forum (Notion copy button reference) | https://forum.obsidian.md/t/code-block-copy-button/34968 | Medium | 2026-02-13 |
| Reddit: Preserving paragraph breaks when copying into other apps | https://www.reddit.com/r/Notion/comments/k2ythz | Low | 2026-02-13 |
| Notion & Markdown compatibility cheatsheet | https://en.markdown.net.br/tools/notion/ | Medium | 2026-02-13 |
