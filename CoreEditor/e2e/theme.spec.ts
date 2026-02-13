import { test, expect } from "@playwright/test";

test.describe("Themes", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await page.waitForSelector(".milkdown .editor", { timeout: 10_000 });
  });

  test("setTheme('dark') applies dark theme", async ({ page }) => {
    // Call the bridge API to switch theme
    await page.evaluate(() => {
      window.kern.setTheme("dark");
    });

    const milkdown = page.locator(".milkdown");
    await expect(milkdown).toHaveAttribute("data-theme", "dark");

    // Verify dark background color is applied
    const bgColor = await page.evaluate(() => {
      const el = document.querySelector(".milkdown") as HTMLElement;
      return getComputedStyle(el).getPropertyValue("--crepe-color-background");
    });
    expect(bgColor.trim()).toBe("#1c1c1e");
  });

  test("setTheme('light') applies light theme", async ({ page }) => {
    // First set dark, then back to light
    await page.evaluate(() => {
      window.kern.setTheme("dark");
      window.kern.setTheme("light");
    });

    const milkdown = page.locator(".milkdown");
    await expect(milkdown).toHaveAttribute("data-theme", "light");

    const bgColor = await page.evaluate(() => {
      const el = document.querySelector(".milkdown") as HTMLElement;
      return getComputedStyle(el).getPropertyValue("--crepe-color-background");
    });
    expect(bgColor.trim()).toBe("#ffffff");
  });

  test("body background updates with theme", async ({ page }) => {
    await page.evaluate(() => {
      window.kern.setTheme("dark");
    });

    const bodyBg = await page.evaluate(() => {
      const style = getComputedStyle(document.body);
      return style.backgroundColor;
    });
    // rgb(28, 28, 30) == #1c1c1e
    expect(bodyBg).toBe("rgb(28, 28, 30)");
  });
});
