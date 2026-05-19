/**
 * Responsive coverage — verifies the prototype's CSS breakpoints
 * (@media max-width: 1280px and 1024px) still produce a working
 * layout. Specifically tests:
 *   • At 1024px: ind-doc-panel is hidden, ind-doc-fab is visible
 *   • At 1280px: shell columns shrink to 220/1fr/420
 *   • IndEmptyState renders when ?onboarding=1 query param is set
 */
import { test, expect } from "@playwright/test";

test("at 1024px: doc panel hidden, FAB visible", async ({ page }) => {
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.goto("/");

  // Wait for shell to mount
  await page.waitForSelector(".ind-shell");

  // Doc panel should be display: none at this viewport
  const docPanelDisplay = await page.locator(".ind-doc-panel").first().evaluate(
    (el) => getComputedStyle(el).display,
  );
  expect(docPanelDisplay).toBe("none");

  // FAB should be display: flex
  const fab = page.locator(".ind-doc-fab");
  await expect(fab).toBeVisible();
  const fabDisplay = await fab.evaluate((el) => getComputedStyle(el).display);
  expect(fabDisplay).toBe("flex");
});

test("at 1280px: shell columns shrink to 220px/1fr/420px", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto("/");
  await page.waitForSelector(".ind-shell");

  const cols = await page.locator(".ind-shell").evaluate(
    (el) => getComputedStyle(el).gridTemplateColumns,
  );
  // Expect 220px / minmax(0, 1fr) / 420px — exact values from CSS
  expect(cols).toContain("220px");
  expect(cols).toContain("420px");
});

test("at default 1440px: shell columns are 240px/1fr/480px", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/");
  await page.waitForSelector(".ind-shell");

  const cols = await page.locator(".ind-shell").evaluate(
    (el) => getComputedStyle(el).gridTemplateColumns,
  );
  expect(cols).toContain("240px");
  expect(cols).toContain("480px");
});

test("?onboarding=1 renders IndEmptyState with reference compounds", async ({ page }) => {
  await page.goto("/?onboarding=1");
  await expect(page.locator(".ind-empty")).toBeVisible();
  await expect(page.locator(".ind-empty-card h1")).toContainText("BioMate IND Report");
  // 3 reference compound chips from DEMO_REFERENCE_COMPOUNDS
  await expect(page.locator(".ind-ref-chip")).toHaveCount(3);
  // Clicking "Start with a compound" exits onboarding mode
  await page.locator(".ind-empty-start").click();
  await expect(page.locator(".ind-shell .ind-center")).toBeVisible();
});
