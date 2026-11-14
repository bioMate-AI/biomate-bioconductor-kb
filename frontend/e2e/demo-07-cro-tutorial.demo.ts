/**
 * Demo 7 — BioMate CRO Tutorial Tour (in-app spotlight walkthrough)
 *
 * Opens DIRECTLY on the CRO compliance page — no chat interface, no landing
 * page, no navigation in the video.  Auth is performed silently via the
 * Playwright API context (same cookie jar as the page but no page navigation).
 *
 * Tour steps:
 *   1  Welcome               (centre overlay)
 *   2  Five surfaces          (tabs bar spotlight)
 *   3  The DMTA loop          (stepper spotlight)
 *   4  Regulated actions      (campaign header spotlight)
 *   5  EMA 2-fold             (Validation tab — criterion banner)
 *   6  Audit chain            (Audit tab — audit list)
 *   7  Auto-retrain loop      (Auto-Retrain tab — loop strip)
 *   8  One-click IND §2.6.1   (IND tab — generate button)
 *   9  Electronic signatures  (Sign action button spotlight)
 *  10  You're ready           (centre overlay)
 *
 * Viewport: 1920×1080 Full HD (matched to video.size in chromium-cro project).
 * Total recording time ≈ 2 min.
 */

import { test } from '@playwright/test';
import { shot, pause } from './demo-helpers.js';

const DEMO  = 'demo-07-cro-tutorial';
const EMAIL = 'demo_cro_tutorial@biomate.test';
const PASS  = 'DemoPass123!';
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only';
const BASE_URL  = process.env.BIOMATE_URL    || 'http://localhost:5000';

// How long to linger on each tour step before clicking Next (ms).
const STEP_PAUSE: Record<number, number> = {
  0:  5_500,  // Welcome
  1:  5_000,  // Tabs bar
  2:  5_500,  // DMTA stepper
  3:  5_000,  // Campaign header (regulated actions)
  4:  7_000,  // Validation — EMA criterion (tab switch)
  5:  7_000,  // Audit — hash chain list (tab switch)
  6:  7_000,  // Auto-Retrain — loop strip (tab switch)
  7:  7_000,  // IND — generate button (tab switch)
  8:  5_500,  // Sign action button
  9:  6_000,  // You're ready
};

test('Demo 7 — CRO Tutorial Tour', async ({ page }) => {
  test.setTimeout(360_000);

  // ─── 0. Silent auth via API context (no page navigation, no landing page) ──
  console.log('[Demo7] Authenticating via API (no page shown)');

  // Pre-set localStorage so the survey never shows when the CRO page loads.
  // addInitScript runs before every page navigation in this context.
  await page.addInitScript(() => {
    try {
      localStorage.setItem(
        'biomate_survey_suppressed_until',
        String(Date.now() + 7 * 24 * 60 * 60 * 1000)
      );
    } catch { /* ignore */ }
  });

  // Register or login — cookies are shared with the page context automatically
  const apiCtx = page.context();
  const regResp = await apiCtx.request.post(`${BASE_URL}/api/auth/register`, {
    data: { name: 'BioMate Demo', email: EMAIL, password: PASS, terms_accepted: true },
    headers: { 'Content-Type': 'application/json', 'X-E2E-Test-Token': E2E_TOKEN },
  });
  if (!regResp.ok()) {
    await apiCtx.request.post(`${BASE_URL}/api/auth/login`, {
      data: { email: EMAIL, password: PASS },
      headers: { 'Content-Type': 'application/json', 'X-E2E-Test-Token': E2E_TOKEN },
    });
  }

  // ─── Navigate DIRECTLY to the CRO page — first frame of the video ─────────
  console.log('[Demo7] Opening CRO compliance page');
  await page.goto(`${BASE_URL}/drug-discovery-cro`);
  await page.waitForLoadState('load');

  // Wait for campaign setup
  await page.waitForSelector('[data-testid="demo-campaign-id"]', { timeout: 30_000 });
  await pause(page, 3_000);
  await shot(page, DEMO, '00_cro_loaded');

  // ─── 1. Launch the tutorial tour ──────────────────────────────────────────
  console.log('[Demo7] Starting tutorial tour');
  const tutBtn = page.locator('[data-tour="tut-btn"]').first();
  await tutBtn.waitFor({ state: 'visible', timeout: 10_000 });
  await pause(page, 1_200);
  await tutBtn.click();
  await pause(page, 800);
  await shot(page, DEMO, '01_tour_welcome');

  // ─── 2. Walk through all 10 steps ─────────────────────────────────────────
  const TOTAL_STEPS = 10;

  for (let stepIdx = 0; stepIdx < TOTAL_STEPS; stepIdx++) {
    const ms = STEP_PAUSE[stepIdx] ?? 5_000;
    console.log(`[Demo7] Step ${stepIdx + 1}/${TOTAL_STEPS} — linger ${ms}ms`);

    await page.locator('.cro-tour-callout').waitFor({ state: 'visible', timeout: 10_000 });

    // Give tab-switching steps extra time for the panel to mount and the
    // spotlight to glide into place
    if (stepIdx >= 4 && stepIdx <= 7) await pause(page, 1_000);

    await pause(page, ms);
    await shot(page, DEMO, `step_${String(stepIdx + 1).padStart(2, '0')}`);

    const nextBtn = page.locator('.cro-tour-callout button[type="button"]').last();
    await nextBtn.click();
    await pause(page, 700);
  }

  // ─── 3. Tour done ──────────────────────────────────────────────────────────
  console.log('[Demo7] Tour complete');
  await pause(page, 2_000);
  await shot(page, DEMO, 'final_dashboard');

  // ─── 4. eSig modal ────────────────────────────────────────────────────────
  console.log('[Demo7] Opening eSig modal');
  const signBtn = page.locator('[data-tour="esig-btn"]').first();
  if (await signBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await signBtn.click();
    await pause(page, 1_500);
    await shot(page, DEMO, 'esig_modal_open');

    const cancelBtn = page.getByRole('button', { name: /cancel/i }).first();
    if (await cancelBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await cancelBtn.click();
    } else {
      await page.keyboard.press('Escape');
    }
    await pause(page, 1_000);
  }

  await shot(page, DEMO, 'done');
  console.log('[Demo7] ✅ Complete');
});
