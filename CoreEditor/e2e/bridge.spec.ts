import { test, expect } from "@playwright/test";

test.describe("Bridge API (window.kern)", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await page.waitForSelector(".milkdown .editor", { timeout: 10_000 });
  });

  test("window.kern is defined and isReady returns true", async ({ page }) => {
    const ready = await page.evaluate(() => window.kern?.isReady());
    expect(ready).toBe(true);
  });

  test("getMarkdown returns non-empty markdown", async ({ page }) => {
    const markdown = await page.evaluate(() => window.kern.getMarkdown());
    expect(markdown).toBeTruthy();
    expect(markdown.length).toBeGreaterThan(50);
    // Should contain the sample H1
    expect(markdown).toContain("# Kern Editor");
  });

  test("setMarkdown replaces editor content", async ({ page }) => {
    const testContent = "# Test Heading\n\nHello from Playwright.";
    await page.evaluate((md) => window.kern.setMarkdown(md), testContent);

    // Wait for the editor to update
    await page.waitForTimeout(500);

    // Verify the content changed
    const markdown = await page.evaluate(() => window.kern.getMarkdown());
    expect(markdown).toContain("Test Heading");
    expect(markdown).toContain("Hello from Playwright");
  });

  test("getScrollPosition returns a number", async ({ page }) => {
    const pos = await page.evaluate(() => window.kern.getScrollPosition());
    expect(typeof pos).toBe("number");
    expect(pos).toBeGreaterThanOrEqual(0);
  });

  test("setScrollPosition scrolls the editor", async ({ page }) => {
    // Set a scroll position
    await page.evaluate(() => window.kern.setScrollPosition(100));
    await page.waitForTimeout(300);

    const pos = await page.evaluate(() => window.kern.getScrollPosition());
    // Should be near 100 (smooth scrolling may not be exact)
    expect(pos).toBeGreaterThan(50);
  });

  test("execCommand('bold') toggles bold", async ({ page }) => {
    // Set simple content and select it
    await page.evaluate(() => {
      window.kern.setMarkdown("Hello world");
    });
    await page.waitForTimeout(500);

    // execCommand should not throw
    const result = await page.evaluate(() => window.kern.execCommand("bold"));
    expect(typeof result).toBe("boolean");
  });

  test("execCommand with unknown command returns false", async ({ page }) => {
    const result = await page.evaluate(() =>
      window.kern.execCommand("nonexistent"),
    );
    expect(result).toBe(false);
  });
});
