import { test, expect } from "@playwright/test";

test.describe("Heading Checkbox", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await page.waitForSelector(".milkdown .editor", { timeout: 10_000 });
    // Wait for decoration plugin to apply classes
    await page.waitForTimeout(500);
  });

  test("renders checked heading checkbox from sample markdown", async ({ page }) => {
    const editor = page.locator(".milkdown .editor");
    // Sample markdown has: ### [x] Completed Section
    const checkedHeading = editor.locator("h3.kern-heading-checkbox-checked");
    await expect(checkedHeading).toBeVisible({ timeout: 5000 });
    await expect(checkedHeading).toContainText("Completed Section");
  });

  test("renders unchecked heading checkbox from sample markdown", async ({ page }) => {
    const editor = page.locator(".milkdown .editor");
    // Sample markdown has: ### [ ] Pending Section
    const uncheckedHeading = editor.locator("h3.kern-heading-checkbox:not(.kern-heading-checkbox-checked)");
    await expect(uncheckedHeading).toBeVisible({ timeout: 5000 });
    await expect(uncheckedHeading).toContainText("Pending Section");
  });

  test("heading checkbox has ::before pseudo-element with icon", async ({ page }) => {
    const editor = page.locator(".milkdown .editor");
    const heading = editor.locator("h3.kern-heading-checkbox").first();
    await expect(heading).toBeVisible({ timeout: 5000 });

    // CSS ::before renders the checkbox icon via background-image
    const beforeStyle = await heading.evaluate((el) => {
      const style = window.getComputedStyle(el, "::before");
      return {
        content: style.content,
        backgroundImage: style.backgroundImage,
        width: style.width,
      };
    });
    expect(beforeStyle.content).not.toBe("none");
    expect(beforeStyle.backgroundImage).toContain("url(");
  });

  test("clicking heading checkbox area toggles state via JS", async ({ page }) => {
    // Toggle via ProseMirror transaction (the click handler is hard to test
    // via Playwright because ::before pseudo-elements aren't real DOM targets).
    // This verifies the underlying toggle mechanism works.
    const result = await page.evaluate(() => {
      const view = (window as any).__kern_editorView ||
        document.querySelector('.milkdown .editor')?.pmViewDesc?.view;
      if (!view) return { error: "no view" };

      const { doc } = view.state;
      let targetPos = -1;
      let targetNode: any = null;
      doc.descendants((node: any, pos: number) => {
        if (node.type.name === "heading" && node.attrs.checked === false && targetPos === -1) {
          targetPos = pos;
          targetNode = node;
        }
      });
      if (targetPos === -1) return { error: "no unchecked heading found" };

      view.dispatch(
        view.state.tr.setNodeMarkup(targetPos, undefined, {
          ...targetNode.attrs,
          checked: true,
        })
      );
      return { toggled: true };
    });
    expect(result).toEqual({ toggled: true });
    await page.waitForTimeout(300);

    const editor = page.locator(".milkdown .editor");
    const pendingHeading = editor.locator("h3").filter({ hasText: "Pending Section" });
    await expect(pendingHeading).toHaveClass(/kern-heading-checkbox-checked/, { timeout: 3000 });
  });

  test("unchecking heading checkbox via JS", async ({ page }) => {
    const result = await page.evaluate(() => {
      const view = (window as any).__kern_editorView ||
        document.querySelector('.milkdown .editor')?.pmViewDesc?.view;
      if (!view) return { error: "no view" };

      const { doc } = view.state;
      let targetPos = -1;
      let targetNode: any = null;
      doc.descendants((node: any, pos: number) => {
        if (node.type.name === "heading" && node.attrs.checked === true && targetPos === -1) {
          targetPos = pos;
          targetNode = node;
        }
      });
      if (targetPos === -1) return { error: "no checked heading found" };

      view.dispatch(
        view.state.tr.setNodeMarkup(targetPos, undefined, {
          ...targetNode.attrs,
          checked: false,
        })
      );
      return { toggled: true };
    });
    expect(result).toEqual({ toggled: true });
    await page.waitForTimeout(300);

    const editor = page.locator(".milkdown .editor");
    const completedHeading = editor.locator("h3").filter({ hasText: "Completed Section" });
    await expect(completedHeading).not.toHaveClass(/kern-heading-checkbox-checked/, { timeout: 3000 });
  });

  test("setMarkdown with heading checkbox renders correctly", async ({ page }) => {
    const testContent = "## [ ] Unchecked Task\n\nSome content.\n\n## [x] Checked Task\n\nMore content.";
    await page.evaluate((md) => window.kern.setMarkdown(md), testContent);
    await page.waitForTimeout(800);

    const editor = page.locator(".milkdown .editor");
    const unchecked = editor.locator("h2.kern-heading-checkbox:not(.kern-heading-checkbox-checked)");
    const checked = editor.locator("h2.kern-heading-checkbox-checked");

    await expect(unchecked).toContainText("Unchecked Task");
    await expect(checked).toContainText("Checked Task");
  });

  test("getMarkdown serializes heading checkbox correctly", async ({ page }) => {
    const testContent = "## [ ] My Task Heading\n\nContent here.";
    await page.evaluate((md) => window.kern.setMarkdown(md), testContent);
    await page.waitForTimeout(500);

    const markdown = await page.evaluate(() => window.kern.getMarkdown());
    expect(markdown).toContain("## [ ] My Task Heading");
  });

  test("toggled heading checkbox serializes with [x]", async ({ page }) => {
    const testContent = "## [ ] Toggle Me\n\nContent.";
    await page.evaluate((md) => window.kern.setMarkdown(md), testContent);
    await page.waitForTimeout(800);

    const editor = page.locator(".milkdown .editor");
    const heading = editor.locator("h2.kern-heading-checkbox").first();
    await expect(heading).toBeVisible({ timeout: 5000 });

    // Click the heading's ::before area to toggle
    await heading.click({ position: { x: 10, y: 10 } });
    await page.waitForTimeout(300);

    const markdown = await page.evaluate(() => window.kern.getMarkdown());
    expect(markdown).toContain("## [x] Toggle Me");
  });

  test("regular headings without checkbox render normally", async ({ page }) => {
    const testContent = "## Normal Heading\n\nNo checkbox.";
    await page.evaluate((md) => window.kern.setMarkdown(md), testContent);
    await page.waitForTimeout(500);

    const editor = page.locator(".milkdown .editor");
    const heading = editor.locator("h2");
    await expect(heading).toContainText("Normal Heading");
    await expect(heading).not.toHaveClass(/kern-heading-checkbox/);
  });

  test("h1 with checkbox works", async ({ page }) => {
    const testContent = "# [ ] Top Level Task\n\nDescription.";
    await page.evaluate((md) => window.kern.setMarkdown(md), testContent);
    await page.waitForTimeout(800);

    const editor = page.locator(".milkdown .editor");
    const h1 = editor.locator("h1.kern-heading-checkbox");
    await expect(h1).toContainText("Top Level Task", { timeout: 5000 });
  });

  test("h6 with checkbox works", async ({ page }) => {
    const testContent = "###### [x] Deep Level Task\n\nDescription.";
    await page.evaluate((md) => window.kern.setMarkdown(md), testContent);
    await page.waitForTimeout(800);

    const editor = page.locator(".milkdown .editor");
    const h6 = editor.locator("h6.kern-heading-checkbox-checked");
    await expect(h6).toContainText("Deep Level Task", { timeout: 5000 });
  });
});
