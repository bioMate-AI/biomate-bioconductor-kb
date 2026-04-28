/**
 * Demo 10 — BioMate Workflow Panel Reference Design (All Scenarios + Tour)
 *
 * Records the Claude reference design prototype directly:
 *   /home/yzhang/biomate/reference/claude_design/cro/Workflow Panel Redesign.html
 *
 * Shows all 4 scenarios and the 10-step tutorial tour from:
 *   reference/claude_design/cro/src/Tour.jsx
 *
 * Scenarios:
 *   nfcore   — nf-core fastp QC, 2 phases, 4 steps (used by tour)
 *   cryosparc — CryoSPARC SPA, 5 phases, 23 steps, QC auto-loop
 *   gatk     — WGS Germline GATK4, 3 phases, 8 steps
 *   admet    — ADMET Property Prediction, 1 step
 *
 * Tour steps (10):
 *   1  Welcome
 *   2  From chat to workflow (chat-handoff)
 *   3  Run status at a glance (panel-header)
 *   4  Phases, not a flat list (phase-list)
 *   5  Drill into running phase (phase-list .phase.open)
 *   6  When a QC gate fails (qcHalt=true)
 *   7  Blocking errors inline (blocked+licenseGate)
 *   8  One primary action (run-footer)
 *   9  Detach without losing (watcher)
 *  10  You're ready to explore ("Got it")
 *
 * Total recording time ≈ 5 min.
 */

import { test } from '@playwright/test';
import { shot, pause } from './demo-helpers.js';

const DEMO = 'demo-10-workflow-panel-reference';
// Python HTTP server avoids the Express CSP blocking unpkg.com CDN scripts
// Started with: python3 -m http.server 7779 --directory /home/yzhang/biomate/reference/claude_design
const WP_URL = 'http://localhost:7779/cro/Workflow%20Panel%20Redesign.html';

// Pause per tour step (ms)
const STEP_PAUSE: Record<number, number> = {
  0:  6_000,  // Welcome
  1:  5_500,  // Chat handoff
  2:  5_500,  // Panel header
  3:  5_500,  // Phase list
  4:  6_000,  // Running phase (drill in)
  5:  6_500,  // QC gate fails (auto-loop)
  6:  6_000,  // Blocking errors
  7:  5_500,  // One primary action
  8:  5_500,  // Detach watcher
  9:  6_000,  // Done — "Got it"
};
const DEFAULT_STEP_PAUSE = 5_500;
const TOTAL_STEPS = 10;

test('Demo 10 — Workflow Panel Reference Design Tour', async ({ page }) => {
  test.setTimeout(600_000);

  // ─── 0. Open the reference design ─────────────────────────────────────────
  console.log('[Demo10] Opening Workflow Panel reference design');
  await page.goto(WP_URL, { waitUntil: 'networkidle', timeout: 30_000 });
  await pause(page, 3_000); // Babel transpile + React render

  // Reset localStorage for fresh state
  await page.evaluate(() => {
    try { localStorage.removeItem('biomate-tweaks'); } catch {}
    try { localStorage.removeItem('biomate_wf_tour_seen'); } catch {}
  });
  await page.reload({ waitUntil: 'networkidle' });
  await pause(page, 2_500);

  await shot(page, DEMO, '00_panel_nfcore_running');

  // ─── 1. Show CryoSPARC scenario via Tweaks ────────────────────────────────
  console.log('[Demo10] Switching to CryoSPARC scenario');
  const tweaksToggle = page.locator('[title*="Tweaks"], [title*="tweak"], button:has-text("Tweaks")').first();
  // The tweaks toolbar is opened by a host postMessage
  await page.evaluate(() => window.postMessage({ type: '__activate_edit_mode' }, '*'));
  await pause(page, 1_200);

  const tweaksPanel = page.locator('.tweaks').first();
  const tweaksVisible = await tweaksPanel.isVisible({ timeout: 5_000 }).catch(() => false);
  if (tweaksVisible) {
    // Switch to CryoSPARC
    const cryoBtn = page.locator('.opt').filter({ hasText: /cryosparc/i }).first();
    if (await cryoBtn.isVisible({ timeout: 2_000 }).catch(() => false)) {
      await cryoBtn.click();
      await pause(page, 1_500);
      await shot(page, DEMO, '01_scenario_cryosparc');
    }

    // Switch to GATK
    const gatkBtn = page.locator('.opt').filter({ hasText: /gatk/i }).first();
    if (await gatkBtn.isVisible({ timeout: 2_000 }).catch(() => false)) {
      await gatkBtn.click();
      await pause(page, 1_500);
      await shot(page, DEMO, '02_scenario_gatk');
    }

    // Show QC halt edge case
    const qcHaltBtn = page.locator('.opt').filter({ hasText: /qc halt/i }).first();
    if (await qcHaltBtn.isVisible({ timeout: 2_000 }).catch(() => false)) {
      // Switch back to nfcore running first
      const nfcoreBtn = page.locator('.opt').filter({ hasText: /nf.?core/i }).first();
      await nfcoreBtn.click();
      await pause(page, 800);
      await qcHaltBtn.click();
      await pause(page, 2_000);
      await shot(page, DEMO, '03_qc_halt_state');

      // Turn off qcHalt
      await qcHaltBtn.click();
    }

    // Close tweaks
    await page.evaluate(() => window.postMessage({ type: '__deactivate_edit_mode' }, '*'));
    await pause(page, 800);
  }

  // ─── 2. Start the tutorial tour ──────────────────────────────────────────
  console.log('[Demo10] Starting tutorial tour');
  const tutBtn = page.locator('.tut-btn').first();
  await tutBtn.waitFor({ state: 'visible', timeout: 15_000 });
  await tutBtn.hover();
  await pause(page, 1_000);
  await tutBtn.click();
  await pause(page, 800);

  await shot(page, DEMO, '04_tour_start');

  // ─── 3. Step through all tour steps ──────────────────────────────────────
  for (let stepIdx = 0; stepIdx < TOTAL_STEPS; stepIdx++) {
    const stepPause = STEP_PAUSE[stepIdx] ?? DEFAULT_STEP_PAUSE;
    console.log(`[Demo10] Tour step ${stepIdx + 1}/${TOTAL_STEPS} — pause ${stepPause}ms`);

    await page.locator('.tour-callout').waitFor({ state: 'visible', timeout: 10_000 });
    await pause(page, 500);

    await shot(page, DEMO, `step_${String(stepIdx + 1).padStart(2, '0')}`);

    await pause(page, stepPause - 500);

    const nextBtn = page.locator('.tour-callout .btn.primary').first();
    await nextBtn.waitFor({ state: 'visible', timeout: 5_000 });
    await nextBtn.click();
    await pause(page, 700);
  }

  // ─── 4. Verify tour ended ─────────────────────────────────────────────────
  await page.locator('.tour-callout').waitFor({ state: 'hidden', timeout: 5_000 });
  await pause(page, 2_000);

  await shot(page, DEMO, 'done');
  console.log('[Demo10] ✅ Workflow Panel Reference Tour recording complete');
});
