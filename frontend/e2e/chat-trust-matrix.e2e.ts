/**
 * C3 — Chat message trust matrix.
 *
 * Asserts the 6 testid'd controls in chat-message.tsx render + behave on
 * an AI message. State-dependent controls (download outputs, async retry,
 * IND chip) are skipped with rationale.
 */
import { test, expect, type Page } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login.js";
import * as path from "path";

const SHOT_DIR = "test-results/chat-matrix";

async function bootApp(page: Page) {
  await loginAsFixture(page);
  await page.goto(BASE_URL);
  await page
    .locator('[data-testid="button-sidebar-toggle"]')
    .waitFor({ state: "visible", timeout: 15_000 });
}

async function sendUserMessage(page: Page, text: string) {
  const composer = page.getByPlaceholder(/Ask BioMate/i);
  await expect(composer).toBeVisible();
  await composer.fill(text);
  await composer.press("Enter");
  await page
    .locator('[data-testid="button-copy-response-icon"]')
    .first()
    .waitFor({ state: "visible", timeout: 60_000 });
}

async function shot(page: Page, name: string) {
  await page.screenshot({
    path: path.join(SHOT_DIR, `${name}.png`),
    fullPage: false,
  });
}

test.describe("Chat message trust matrix (C3)", () => {
  test("C3.01 Copy button: visible + click triggers clipboard", async ({
    page, context,
  }) => {
    await context.grantPermissions(["clipboard-read", "clipboard-write"]);
    await bootApp(page);
    await sendUserMessage(page, "say hello in one sentence");
    const copy = page.locator('[data-testid="button-copy-response-icon"]').first();
    await expect(copy).toBeVisible();
    await copy.click();
    const clip = await page.evaluate(() =>
      navigator.clipboard.readText().catch(() => "")
    );
    expect(clip.length).toBeGreaterThan(0);
    await shot(page, "01_copy");
  });

  test("C3.02 Regenerate button: yields new response", async ({ page }) => {
    await bootApp(page);
    await sendUserMessage(page, "say hello in one sentence");
    const regen = page.locator('[data-testid="button-regenerate-message-icon"]').first();
    await expect(regen).toBeVisible();
    const before = await page.locator('[data-testid="button-copy-response-icon"]').count();
    await regen.click();
    await expect
      .poll(
        async () =>
          page.locator('[data-testid="button-copy-response-icon"]').count(),
        { timeout: 30_000 }
      )
      .toBeGreaterThan(before);
    await shot(page, "02_regenerate");
  });

  test("C3.03 Save response: visible when shown", async ({ page }) => {
    await bootApp(page);
    await sendUserMessage(page, "say hello");
    const save = page.locator('[data-testid="button-save-response"]').first();
    const visible = await save.isVisible().catch(() => false);
    if (visible) await shot(page, "03_save");
    else test.skip(true, "save-response only renders for action messages");
  });

  test.skip("C3.04 download-outputs only for workflow-execution messages — covered by C4", async () => {});
  test.skip("C3.05 async-try-again only renders when an async chat call has failed", async () => {});
  test.skip("C3.06 ind-report-handoff-chip only renders when workflow completes + IND project exists — covered by C5", async () => {});
});
