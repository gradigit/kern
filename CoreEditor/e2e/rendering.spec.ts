import { test, expect } from "@playwright/test";

test.describe("Rendering", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await page.waitForSelector(".milkdown .editor", { timeout: 10_000 });
  });

  test("editor mounts and shows content", async ({ page }) => {
    const editor = page.locator(".milkdown .editor");
    await expect(editor).toBeVisible();
    // Dev mode shows sample markdown with H1 "Kern Editor"
    await expect(editor.locator("h1")).toContainText("Kern Editor");
  });

  test("renders headings", async ({ page }) => {
    const editor = page.locator(".milkdown .editor");
    await expect(editor.locator("h1")).toHaveCount(1);
    expect(await editor.locator("h2").count()).toBeGreaterThanOrEqual(1);
    expect(await editor.locator("h3").count()).toBeGreaterThanOrEqual(1);
  });

  test("renders bold and italic text", async ({ page }) => {
    const editor = page.locator(".milkdown .editor");
    await expect(editor.locator("strong").first()).toBeVisible();
    await expect(editor.locator("em").first()).toBeVisible();
  });

  test("renders inline code", async ({ page }) => {
    const editor = page.locator(".milkdown .editor");
    const inlineCode = editor.locator("code").first();
    await expect(inlineCode).toBeVisible();
  });

  test("renders code blocks with CodeMirror", async ({ page }) => {
    const editor = page.locator(".milkdown .editor");
    const codeBlocks = editor.locator(".milkdown-code-block");
    await expect(codeBlocks.first()).toBeVisible();
    await expect(codeBlocks.first().locator(".cm-editor")).toBeVisible();
  });

  test("renders tables", async ({ page }) => {
    const editor = page.locator(".milkdown .editor");
    // Milkdown table component may not report as "visible" in standard sense
    expect(await editor.locator("table").count()).toBeGreaterThanOrEqual(1);
    const rows = editor.locator("table tr");
    expect(await rows.count()).toBeGreaterThanOrEqual(2);
  });

  test("renders math equations", async ({ page }) => {
    const editor = page.locator(".milkdown .editor");
    // Milkdown renders LaTeX — look for katex or math container
    const mathEl = editor.locator(
      ".katex, .math-inline, [data-type='math_inline']",
    ).first();
    await expect(mathEl).toBeVisible();
  });

  test("renders blockquotes", async ({ page }) => {
    const editor = page.locator(".milkdown .editor");
    await expect(editor.locator("blockquote").first()).toBeVisible();
  });

  test("renders task lists with checkboxes", async ({ page }) => {
    const editor = page.locator(".milkdown .editor");
    const checkItems = editor.locator(
      ".milkdown-list-item-block .label.checked, .milkdown-list-item-block .label.unchecked",
    );
    expect(await checkItems.count()).toBeGreaterThanOrEqual(2);
  });
});
