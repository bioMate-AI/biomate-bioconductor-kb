/**
 * Gap 3 — Run Again Param Carryover
 *
 * Verifies that after a workflow completes (or fails), clicking "Run again"
 * pre-fills the panel's parameter inputs with the values actually submitted
 * to the prior run, not the workflowDefinition defaults.
 *
 * Also verifies the "Reset to defaults" link is visible while pre-filled
 * params are in effect, and that clicking it re-applies defaults.
 *
 * See: docs/20260521_GAP3_RUN_AGAIN_PARAM_CARRYOVER.md
 *
 * NO mocking. Real backend, real run. The test uses a lightweight
 * workflow (no GPU, no AWS Batch) so the full loop completes in <2 min.
 *
 * Screenshots → e2e/screenshots/run-again-param-carryover/
 */

import { test, expect, Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";
const E2E_TOKEN =
  process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const SS_DIR = path.join(__dirname, "screenshots", "run-again-param-carryover");

if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

test.setTimeout(360000); // 6 min — workflow needs to start, complete, and verify

async function registerAndGoHome(page: Page): Promise<void> {
  // Matches the robust pattern from full-workflow-e2e.ts: tolerate registration
  // form quirks (extra optional fields, validation paths) and recover by
  // navigating directly to / after a brief wait. The auth cookie is set on
  // submit even when the URL doesn't change.
  const email = `e2e_gap3_${Date.now()}@biomate.test`;
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  await page.goto(`${BASE_URL}/register`);
  await page.evaluate(() => { try { localStorage.clear(); sessionStorage.clear(); } catch {} }).catch(() => {});
  await page.waitForLoadState("load");
  try {
    await page.waitForSelector("#name", { state: "visible", timeout: 10000 });
    await page.fill("#name", "Gap3 E2E");
    await page.fill("#email", email);
    await page.fill("#organization", "BioMate Test Lab");
    await page.selectOption("#role", { label: "Research Scientist" });
    await page.fill("#password", "TestPass123!");
    await page.fill("#confirmPassword", "TestPass123!");
    await page.click("#terms");
    await page.click('button[type="submit"]');
    await page.waitForTimeout(3000);
  } catch {
    // ignore — recovery via direct goto below
  }
  await page.goto(BASE_URL);
  await page.evaluate(() => { try { localStorage.clear(); sessionStorage.clear(); } catch {} }).catch(() => {});
  await page.reload();
  await page.waitForLoadState("load");
  await page.waitForSelector("textarea", { state: "visible", timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(1000);
}

test("Gap 3 — Run again pre-fills submitted params; Reset link restores defaults", async ({ page }) => {
  await registerAndGoHome(page);

  // Send a request that yields a lightweight workflow (no GPU/Batch).
  // QC preprocessing on a tiny test FASTQ — typically completes in ~30s end-to-end.
  await page.fill('textarea[placeholder*="message"], textarea[data-testid="chat-input"]',
    "Run QC preprocessing on /test/fixtures/tiny.fastq.gz");
  await page.click('[data-testid="chat-send-button"]');

  // Wait for the workflow panel to open in the right pane.
  await page.waitForSelector('[data-testid="button-run-workflow-panel"]', { timeout: 90000 });
  await page.screenshot({ path: path.join(SS_DIR, "01_panel_open.png"), fullPage: true });

  // Override a known param to a non-default value before running, so we can
  // assert it gets carried over after completion.
  // (Selector pattern: param-override-btn-{paramName} per CLAUDE.md memory.)
  const paramRow = page.locator('[data-testid^="param-override-btn-"]').first();
  if (await paramRow.count() === 0) {
    test.skip(true, "No editable params found in this workflow — skipping (workflow choice issue)");
  }
  await paramRow.click();
  // Capture the param name from the testid for later assertion.
  const paramTestId = await paramRow.getAttribute('data-testid');
  const paramName = (paramTestId || '').replace('param-override-btn-', '');
  expect(paramName).toBeTruthy();

  // Type a non-default sentinel into the now-revealed input. Use a string the
  // workflow will accept for any input type (numeric or text — the panel coerces).
  const inputLocator = page.locator(`[data-param-name="${paramName}"] input, [data-testid="param-input-${paramName}"]`).first();
  await inputLocator.fill("42");
  const submittedValue = "42";

  // Confirm & run.
  await page.click('[data-testid="button-run-workflow-panel"]');
  await page.screenshot({ path: path.join(SS_DIR, "02_run_started.png"), fullPage: true });

  // Wait for terminal status. Status badge data-status flips to completed/failed.
  await page.waitForFunction(() => {
    const badge = document.querySelector('[data-testid="workflow-overall-status-badge"]');
    const s = badge?.getAttribute('data-status');
    return s === 'completed' || s === 'failed';
  }, { timeout: 240000 });
  await page.screenshot({ path: path.join(SS_DIR, "03_terminal.png"), fullPage: true });

  // The button label should now read "Run again" or "Restart".
  const runBtn = page.locator('[data-testid="button-run-workflow-panel"]');
  const label = (await runBtn.textContent() || '').trim();
  expect(label).toMatch(/Run again|Restart/);

  // The Reset link should be visible — pre-fill from submittedParams happened.
  await expect(page.locator('[data-testid="button-reset-params-to-defaults"]')).toBeVisible();

  // The input should still show the submitted sentinel value, not the default.
  const valueAfterTerminal = await inputLocator.inputValue();
  expect(valueAfterTerminal).toBe(submittedValue);

  // Click Reset → param should revert to its default, Reset link hides.
  await page.click('[data-testid="button-reset-params-to-defaults"]');
  await expect(page.locator('[data-testid="button-reset-params-to-defaults"]')).toBeHidden();
  const valueAfterReset = await inputLocator.inputValue();
  expect(valueAfterReset).not.toBe(submittedValue);
  await page.screenshot({ path: path.join(SS_DIR, "04_after_reset.png"), fullPage: true });
});
