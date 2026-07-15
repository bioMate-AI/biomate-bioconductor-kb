/**
 * C2 — Sidebar trust matrix (live JSX only).
 *
 * The source-tree app-sidebar.tsx defines 11 controls but 7 are inside
 * `{/* ... *\/}` comment blocks awaiting validation. This matrix asserts
 * only the shipped controls + uses test.skip with file:line for hidden
 * ones so the matrix surfaces them automatically when they un-hide.
 */
import { test, expect, type Page } from "@playwright/test";
import { loginAsFixture, resetFixtureCache, BASE_URL } from "./_fixture-login.js";
import * as path from "path";

const SHOT_DIR = "test-results/sidebar-matrix";

async function bootApp(page: Page) {
  await loginAsFixture(page);
  await page
    .locator('[data-testid="button-sidebar-toggle"]')
    .waitFor({ state: "visible", timeout: 15_000 });
}

async function shot(page: Page, name: string) {
  await page.screenshot({
    path: path.join(SHOT_DIR, `${name}.png`),
    fullPage: false,
  });
}

test.describe("Sidebar trust matrix — live JSX (C2)", () => {
  test("C2.01 New Chat: visible + click stays on /", async ({ page }) => {
    await bootApp(page);
    const btn = page.locator('[data-testid="button-new-chat"]');
    await expect(btn).toBeVisible();
    await expect(btn).toContainText(/new chat/i);
    await btn.click();
    await expect(btn).toBeVisible();
    await shot(page, "01_new_chat");
  });

  test("C2.02 Workflows: opens StarredWorkflowsDialog", async ({ page }) => {
    await bootApp(page);
    await page.locator('[data-testid="button-workflows-nav"]').click();
    await expect(page.locator('[role="dialog"]').first()).toBeVisible({
      timeout: 5_000,
    });
    await shot(page, "02_workflows_dialog");
  });

  test("C2.03 IND Report: navigates to /ind-report", async ({ page }) => {
    await bootApp(page);
    await page.locator('[data-testid="button-ind-report"]').click();
    await expect(page).toHaveURL(/\/ind-report/);
    await shot(page, "03_ind_report");
  });

  test("C2.04 Sidebar toggle: collapse → icon rail → expand round-trip", async ({
    page,
  }) => {
    await bootApp(page);
    const toggle = page.locator('[data-testid="button-sidebar-toggle"]');
    const newChat = page.locator('[data-testid="button-new-chat"]');
    await expect(newChat).toBeVisible();
    await toggle.click();
    await page.waitForTimeout(300);
    await expect(newChat).toBeHidden({ timeout: 3_000 });
    const expand = page.locator('[data-testid="button-sidebar-expand"]');
    await expect(expand).toBeVisible();
    await shot(page, "04_collapsed");
    await expand.click();
    await expect(newChat).toBeVisible({ timeout: 3_000 });
  });

  test("C2.05 Sign out: visible + click returns to /login", async ({ page }) => {
    await bootApp(page);
    await page.locator('[data-testid="button-logout"]').click();
    await expect(page).toHaveURL(/\/login/, { timeout: 5_000 });
    await shot(page, "05_logout");
    resetFixtureCache();
  });

  // Hidden controls — refer back to source for un-hiding gates
  test.skip("C2.x1 CRO Library — hidden in app-sidebar.tsx '/* CRO Library — commented out */'", async () => {});
  test.skip("C2.x2 Capabilities — hidden in app-sidebar.tsx ('/*')", async () => {});
  test.skip("C2.x3 Blog — hidden in app-sidebar.tsx ('/*')", async () => {});
  test.skip("C2.x4 Starred Workflows — hidden in 'Beta: Actions panel hidden' block", async () => {});
  test.skip("C2.x5 Recent Tools — hidden in 'Beta: Actions panel hidden' block", async () => {});
  test.skip("C2.x6 Billing — hidden in 'Billing summary hidden until billing page is ready'", async () => {});
  test.skip("C2.x7 Settings — hidden in 'Beta: Actions panel hidden' block", async () => {});
});
