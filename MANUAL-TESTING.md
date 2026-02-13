# Manual Testing Required

Items that require human verification in the running app. These cannot be confirmed from the command line.

## Current Session Changes

### Code Block Copy Feedback (Phase 13)
- [x] Hover over a code block — Copy button appears
- [x] Click Copy — button swaps to "✓ Copied!" with green color for 2 seconds
- [x] Button reverts to original clipboard icon + "Copy" text after 2s
- [x] Multiple code blocks work independently
- [x] Rapid clicks don't cause glitches (pointer-events: none during feedback)

### Table Text Wrapping (Phase 13)
- [x] Long text in table cells wraps instead of overflowing into adjacent columns
- [x] Table still scrolls horizontally if all columns are wide

### Code Block Scrollbar (Phase 13)
- [x] Horizontal scrollbar in single-line code blocks doesn't overlap text
- [x] No vertical scrollbar appears on single-line code blocks
- [x] Multi-line code blocks still render correctly

### Cmd+Hold Tooltip Hiding
- [ ] Hold Cmd key — link tooltips should disappear
- [ ] Release Cmd key — tooltips should reappear on hover
- [ ] Cmd+click a link — should open in browser without tooltip blocking adjacent links
- [ ] Cmd+Tab away and back — tooltip should work normally after (blur clears state)

### Inline Nested Checkboxes (CSS collapse + renderLabel approach)
- [ ] `1. - [x] text` renders as: `1. • ☑ text` — number, bullet dot, checkbox, text on ONE line
- [ ] `2. - [ ] text` renders as: `2. • ☐ text` — same with unchecked box
- [ ] `- 1. [x] text` renders as: `• 1. ☑ text` — bullet, number, checkbox, text on ONE line
- [ ] `1. - 1. [x] text` renders as: `1. • 1. ☑ text` — four indicators, recursive collapse
- [ ] Regular ordered lists (no checkbox) still render normally
- [ ] Bulleted tasks (`- [x] text`) show bullet dot + checkbox (`• ☑ text`)
- [ ] Click checkbox — toggles checked state
- [ ] Dark mode rendering looks correct
- [ ] Verify icons are normal-sized (not tiny/squished)

### Needs Decision: New-line behavior in collapsed nested lists
- [ ] Place cursor inside a collapsed inline-nested item and press Enter — what happens?
- [ ] Does it create a new item at the correct nesting level?
- [ ] Does the collapsed layout break when editing inside it?
- [ ] Try deleting text from a collapsed item — does the collapse update correctly?
- [ ] Consider: should pressing Enter in `1. • ☑ text` create a new sub-item at the checkbox level, or a new top-level ordered item?
- This needs design decisions — note findings and discuss before implementing fixes.

### Regression Checks
- [ ] Search & Replace (Cmd+F) still works
- [ ] Link clicking (Cmd+click) still works
- [ ] Mermaid diagrams still render
- [ ] Theme switching (light/dark) still works

### Phase 12: Checkbox System + Cmd+N/Cmd+T

#### Standalone Checkboxes (`[ ] text`)
- [ ] Type `[ ] ` (bracket-space-bracket-space) in empty paragraph — should create standalone checkbox
- [ ] Type `[x] ` — should create checked standalone checkbox
- [ ] Click checkbox icon — toggles checked/unchecked state
- [ ] Checked state shows strikethrough text with reduced opacity
- [ ] Standalone checkbox serializes to `[ ] text` in markdown (not `- [ ] text`)
- [ ] Loading a file with `[ ] text` lines renders standalone checkboxes

#### Bulleted Tasks (`- [ ] text`)
- [ ] Type `- [ ] text` — shows bullet dot + checkbox (`• ☐ text`)
- [ ] Type `- [x] text` — shows bullet dot + checked checkbox (`• ☑ text`)
- [ ] Bullet indicator is always visible (not hidden)

#### Ordered Tasks (`1. [ ] text`)
- [ ] Type `1. [ ] text` — shows `1. ☐ text`
- [ ] Type `1. [x] text` — shows `1. ☑ text`

#### Slash Menu
- [ ] Type `/` — slash menu appears
- [ ] "Task List" creates standalone checkbox node (`[ ]`)
- [ ] "Bulleted Task" creates bullet + checkbox (`- [ ]`)
- [ ] "Ordered Task" creates ordered + checkbox (`1. [ ]`)
- [ ] Default "Task List" from Milkdown is NOT shown (replaced by our version)

#### Cmd+N / Cmd+T
- [ ] Cmd+N opens a new untitled document in a separate window
- [ ] Cmd+T opens a new untitled document as a tab in the current window
- [ ] Multiple Cmd+T presses create multiple tabs
- [ ] New window from Cmd+N is independent (not tabbed to existing)

#### Markdown Round-Trip
- [ ] Create standalone checkbox, save file, reopen — checkbox preserved
- [ ] Create bulleted task, save, reopen — bullet + checkbox preserved
- [ ] Create ordered task, save, reopen — ordered + checkbox preserved
- [ ] File contents match expected markdown syntax (check with external editor)
