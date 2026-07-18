/**
 * B3 Settings dialog affordance — RetrainAdapterCard trust matrix.
 *
 *   R1 sidebar Settings → dialog opens
 *   R2 Advanced tab → RetrainAdapterCard mounted + pair-count rendered
 *   R3 'Re-train on my edits' click → at least one job row appears
 *   R4 Refresh button keeps the dialog stable (no error overlay)
 *
 * Live-DOM assertions only; the affordance hits real /api/regulatory_llm
 * routes through the Node proxy. Per CLAUDE.md §"Testing Rules" no mocks.
 */
import { test, expect, type Page } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login.js";
import * as path from "path";

const SHOT_DIR = "test-results/retrain-card-matrix";

async function openSettings(page: Page) {
  await loginAsFixture(page);
  await page.goto(BASE_URL);
  await page.locator('[data-testid="button-settings"]').click();
  await page.locator('[role="dialog"]').first().waitFor({ state: "visible", timeout: 5_000 });
}

async function gotoAdvanced(page: Page) {
  await page.locator('[data-testid="tab-advanced"]').click();
  await page.locator('[data-testid="retrain-adapter-card"]').waitFor({
    state: "visible", timeout: 5_000,
  });
}

async function shot(page: Page, name: string) {
  await page.screenshot({ path: path.join(SHOT_DIR, `${name}.png`), fullPage: false });
}

test.describe("Retrain adapter card (B3 Settings affordance)", () => {
  test("R1 Settings dialog opens from sidebar", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(BASE_URL);
    await page.locator('[data-testid="button-settings"]').click();
    const dialog = page.locator('[role="dialog"]').first();
    await expect(dialog).toBeVisible({ timeout: 5_000 });
    await shot(page, "01_settings_open");
  });

  test("R2 Advanced tab mounts RetrainAdapterCard with pair count", async ({ page }) => {
    await openSettings(page);
    await gotoAdvanced(page);
    const card = page.locator('[data-testid="retrain-adapter-card"]');
    await expect(card).toBeVisible();
    const count = page.locator('[data-testid="retrain-pair-count"]');
    await expect(count).toBeVisible();
    await expect(count).toContainText(/edit pair/i);
    await shot(page, "02_card_mounted");
  });

  test("R3 Submit queues a job — visible in history", async ({ page }) => {
    await openSettings(page);
    await gotoAdvanced(page);
    const before = await page.locator('[data-testid^="retrain-job-"]').count();
    await page.locator('[data-testid="retrain-submit-btn"]').click();
    // History updates after refresh inside submit handler
    await expect.poll(
      async () => page.locator('[data-testid^="retrain-job-"]').count(),
      { timeout: 15_000 }
    ).toBeGreaterThan(before);
    await shot(page, "03_job_queued");
  });

  test("R4 Refresh keeps the card stable (no error overlay)", async ({ page }) => {
    await openSettings(page);
    await gotoAdvanced(page);
    await page.locator('[data-testid="retrain-refresh-btn"]').click();
    await page.waitForTimeout(1_000);
    const err = page.locator('[data-testid="retrain-error"]');
    expect(await err.isVisible().catch(() => false)).toBe(false);
    await shot(page, "04_refresh_stable");
  });
});
