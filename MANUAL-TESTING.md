# Manual Testing

This checklist is for the packaged app path, not just a Debug launch from DerivedData.

Use it after building the current release artifact:

```bash
./scripts/package-kern-app.sh
```

## Automated smoke coverage

These checks are scriptable and should run before the human-only checklist.

- [ ] Packaged app smoke:

  ```bash
  ./scripts/test-kern-app.sh --packaged --skip-build
  ```

- [ ] Optional packaged-app screenshots:

  ```bash
  ./scripts/test-kern-app.sh --packaged --skip-build --screenshots
  ```

- [ ] DMG checksum:

  ```bash
  (cd dist && shasum -a 256 -c Kern-macOS-Release.dmg.sha256)
  ```

- [ ] DMG mount contents include:
  - `Kern.app`
  - `Applications` symlink

## Human-only packaged-app QA

These checks still need a human pass for UX feel, layout, and OS integration.

### Release artifact and first launch

- [ ] Open `Kern-macOS-Release.dmg`
- [ ] Drag `Kern.app` into `Applications`
- [ ] Launch `Kern.app` from `Applications` rather than from the mounted DMG
- [ ] If macOS blocks launch, the documented unsigned-app override flow works:
  - Finder `Open`
  - **System Settings → Privacy & Security → Open Anyway** if needed

### File lifecycle

- [ ] `open -a Kern some.md` opens the file without crashing
- [ ] Editing feels responsive enough for normal use (typing, selection, scroll)
- [ ] Cmd+S saves and the file changes on disk
- [ ] External change reload shows the expected reload notice/toast

### WYSIWYG core

- [ ] Headings render larger/bolder and hide leading `#` syntax
- [ ] Bullets render as bullets and hide leading `- `
- [ ] Ordered lists render as numbers and hide leading `1. `
- [ ] Inline bold/italic/code render correctly and hide syntax markers

### Tasks / checkboxes

- [ ] `- [ ] task` renders as a bulleted task and click toggles the checkbox
- [ ] `- [x] task` renders checked with appropriate styling
- [ ] `[ ] standalone` renders as a standalone checkbox with no bullet
- [ ] Checkbox hit target feels reasonable and alignment looks centered

### Tables / renderers

- [ ] Basic GFM table renders as a grid with distinct header styling
- [ ] Caret navigation inside table cells feels sane
- [ ] Images render correctly
- [ ] Mermaid renders correctly
- [ ] Math renders correctly

### Code blocks / find / navigation

- [ ] Code block uses monospaced font with distinct background
- [ ] Copy button appears when caret is inside a code block
- [ ] Copy copies the full code block contents
- [ ] Cmd+F opens Find and finds matches
- [ ] Cmd+Shift+H opens Find and Replace
- [ ] Anchor navigation works without obvious viewport bugs

### Preferences / multi-window / OS integration

- [ ] Preferences window opens and theme/font changes apply as expected
- [ ] Multiple windows/tabs behave sanely
- [ ] Finder “Open With” flow works for `.md` files
