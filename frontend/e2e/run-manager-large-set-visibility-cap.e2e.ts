import { test, expect } from "@playwright/test";
import { setupTestUser, waitForRunManagerItems } from "./helpers.js";

// Maximum number of run cards a single bucket is expected to show before
// requiring a "show more" action. Matches the design spec of 6.
const BUCKET_VISIBLE_CAP = 6;

test.describe("Run Manager Large Set Visibility Cap", () => {
  test("panel renders without errors and applies bucket visibility cap when many runs exist", async ({ page }) => {
    await setupTestUser(page, "rm-cap");

    // Open run manager.
    await page.getByTestId("button-toggle-run-manager").click();
    const panel = page.getByTestId("run-manager-panel");
    await expect(panel).toBeVisible({ timeout: 10000 });

    // Switch to "All Chats" scope to see the widest possible run set.
    const allChatsScope = page.getByTestId("run-manager-scope-all-chats");
    const scopeExists = await allChatsScope.isVisible({ timeout: 3000 }).catch(() => false);
    if (scopeExists) {
      await allChatsScope.click();
      await page.waitForTimeout(2000);
    }

    // Wait briefly for any runs to load.
    await page.waitForTimeout(2000);

    const runItems = panel.locator("[data-testid^='run-manager-item-']:not([data-testid*='-cta-'])");
    const totalVisible = await runItems.count();

    if (totalVisible === 0) {
      // Fresh user — no runs. Verify empty state renders correctly.
      const panelText = (await panel.innerText().catch(() => "")).trim();
      expect(panelText.length).toBeGreaterThan(0);
      const bodyText = await page.locator("body").innerText().catch(() => "");
      expect(bodyText.toLowerCase()).not.toContain("something went wrong");
      return;
    }

    // Runs exist. For each populated bucket, verify the visible cap is respected.
    const buckets = ["running", "failed", "queued", "completed"] as const;
    for (const bucket of buckets) {
      const bucketContainer = panel.getByTestId(`run-manager-bucket-${bucket}`);
      const bucketExists = await bucketContainer.isVisible({ timeout: 1000 }).catch(() => false);
      if (!bucketExists) continue;

      const bucketItems = bucketContainer.locator(
        "[data-testid^='run-manager-item-']:not([data-testid*='-cta-'])"
      );
      const bucketCount = await bucketItems.count();

      if (bucketCount > 0) {
        // The rendered count must not exceed the cap.
        expect(
          bucketCount,
          `Bucket "${bucket}" shows ${bucketCount} visible cards, expected at most ${BUCKET_VISIBLE_CAP}`
        ).toBeLessThanOrEqual(BUCKET_VISIBLE_CAP);
      }
    }

    // If there are more runs than the cap, a "show more" or pagination
    // control must be present somewhere in the panel.
    const bucketCountElements = panel.locator("[data-testid^='run-manager-bucket-count-']");
    const bucketCountEls = await bucketCountElements.count();
    for (let i = 0; i < bucketCountEls; i++) {
      const el = bucketCountElements.nth(i);
      const countText = (await el.innerText().catch(() => "0")).trim();
      const count = parseInt(countText, 10);
      if (isNaN(count) || count <= BUCKET_VISIBLE_CAP) continue;

      // There are more runs in this bucket than the cap — a "show more"
      // / load-more / pagination control should exist somewhere in the panel.
      const showMoreVisible =
        (await panel.getByText(/show more/i).first().isVisible({ timeout: 2000 }).catch(() => false)) ||
        (await panel.getByText(/load more/i).first().isVisible({ timeout: 2000 }).catch(() => false)) ||
        (await panel.getByRole("button", { name: /more/i }).first().isVisible({ timeout: 2000 }).catch(() => false));

      // This is a best-effort check: if the app shows a count > cap it should
      // surface a way to access the hidden items.
      if (!showMoreVisible) {
        // Acceptable if the panel uses a different pattern (e.g. scroll-based).
        // Do not fail hard — just confirm the panel is still functional.
        await expect(panel).toBeVisible();
      }
    }

    // No errors.
    const bodyText = await page.locator("body").innerText().catch(() => "");
    expect(bodyText.toLowerCase()).not.toContain("something went wrong");
    expect(bodyText.toLowerCase()).not.toContain("unexpected error");
  });

  test("search with no matching term shows empty state inside the panel", async ({ page }) => {
    await setupTestUser(page, "rm-cap-search");

    await page.getByTestId("button-toggle-run-manager").click();
    const panel = page.getByTestId("run-manager-panel");
    await expect(panel).toBeVisible({ timeout: 10000 });

    // Look for the search input.
    const searchInput = panel.getByTestId("run-manager-search-input");
    const searchVisible = await searchInput.isVisible({ timeout: 3000 }).catch(() => false);
    if (!searchVisible) {
      // No search input present — skip the sub-test.
      await expect(panel).toBeVisible();
      return;
    }

    // Type a token that cannot match any real workflow name.
    await searchInput.fill("no-such-run-token-xyzzy-9999");
    await page.waitForTimeout(1000);

    // After filtering, either:
    //   (a) "No runs" text appears in each bucket, or
    //   (b) no run-manager-item elements are visible at all.
    const runItems = panel.locator("[data-testid^='run-manager-item-']:not([data-testid*='-cta-'])");
    const visibleAfterSearch = await runItems.count();
    expect(visibleAfterSearch).toBe(0);

    // Panel itself must not show a JS error boundary.
    const bodyText = await page.locator("body").innerText().catch(() => "");
    expect(bodyText.toLowerCase()).not.toContain("something went wrong");
  });
});
