/**
 * Browser-verify the Regenerate flow on dev-public.biomate.ai.
 *
 * Walks: register → /ind-report → click BM-0042 → expand §2.6.1 →
 *        open Regenerate modal → click ↻ → observe phase banner +
 *        either streaming tokens OR error fallback notice.
 *
 * Run with:
 *   BIOMATE_URL=https://dev-public.biomate.ai \
 *     npx playwright test frontend/e2e/regenerate-dev-smoke.e2e.ts --headed
 *
 * Captures screenshots to /tmp/regen-dev-shots/.
 */

import { test, expect, type Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { BASE_URL, setupTestUser } from "./helpers.js";

const SHOTS = "/tmp/regen-dev-shots";
if (!fs.existsSync(SHOTS)) fs.mkdirSync(SHOTS, { recursive: true });
const shot = (p: Page, name: string) =>
  p.screenshot({ path: path.join(SHOTS, `${name}.png`), fullPage: false });

test.describe("Regenerate flow (dev-public)", () => {
  test.setTimeout(360_000);

  test("phase banner + stream area appear when Regenerate clicked", async ({ page }) => {
    // Auth (handles the /ind-report ProtectedRoute)
    await setupTestUser(page, `regen_dev_${Date.now()}`);

    await page.goto(`${BASE_URL}/ind-report?onboarding=0`, { waitUntil: "domcontentloaded" });
    await expect(page.locator(".ind-shell").first()).toBeVisible({ timeout: 15000 });
    await shot(page, "01_shell_loaded");

    // Click into the first project in the left nav (should be BM-0042 if the
    // registry seed is in place; otherwise demo state shows a default).
    const navItem = page.locator("[data-testid^='ind-nav-project-'], .ind-left-nav .nav-item, .ind-left-nav button").first();
    if (await navItem.count()) {
      await navItem.click();
      await page.waitForTimeout(500);
    }
    await shot(page, "02_project_selected");

    // Find a Regenerate button — class is `.regen-btn` per IndDocPanel.tsx
    const regen = page.locator("button.regen-btn").first();
    const regenCount = await regen.count();
    test.skip(regenCount === 0, "No .regen-btn rendered in current demo state");
    await regen.scrollIntoViewIfNeeded();
    await shot(page, "03_regen_visible");
    await regen.click();

    // Modal opens — submit immediately ("Regenerate as is" path)
    const modal = page.locator("[data-tour='ind-regenerate-modal']");
    await expect(modal).toBeVisible({ timeout: 5000 });
    await shot(page, "04_modal_open");

    const submitBtn = modal.locator("button.ind-btn.primary").filter({ hasText: /Regenerate/ });
    await submitBtn.click();

    // The stream area should appear — phase banner visible within a few seconds
    const phaseMsg = page.locator("[data-testid='regen-phase-msg']");
    await expect(phaseMsg).toBeVisible({ timeout: 10_000 });
    const initialPhase = (await phaseMsg.textContent())?.trim() ?? "";
    console.log(`[regen-dev] initial phase: ${initialPhase}`);
    await shot(page, "05_phase_streaming");

    // Wait until we see either "complete" success state or "fallback to Gemini" error
    const closeBtn = page.locator("[data-tour='ind-regenerate-modal'] button.ind-btn.primary").filter({ hasText: "Close" });
    await closeBtn.waitFor({ timeout: 180_000 });
    const finalPhase = (await phaseMsg.textContent())?.trim() ?? "";
    console.log(`[regen-dev] final phase: ${finalPhase}`);

    // Was there generated text OR an error notice?
    const draft = page.locator("[data-testid='regen-draft-text']");
    const draftPresent = (await draft.count()) > 0;
    const errorNotice = await page.locator("text=/fall back to Gemini/i").count();
    await shot(page, "06_terminal_state");

    console.log(`[regen-dev] draft visible: ${draftPresent}; error notice: ${errorNotice > 0}`);
    expect(draftPresent || errorNotice > 0).toBe(true);
  });
});
