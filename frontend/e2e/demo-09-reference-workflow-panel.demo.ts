/**
 * Demo 9 — Claude Reference Design: Workflow Panel Tour
 *
 * Records the 10-step tutorial tour from the Claude reference prototype:
 *   reference/claude_design/cro/Workflow Panel Redesign.html
 *
 * Steps (from src/Tour.jsx):
 *   1  Welcome
 *   2  From chat to workflow        (chat-handoff)
 *   3  Run status at a glance       (panel-header)
 *   4  Phases, not a flat step list (phase-list)
 *   5  Drill into the running phase (phase-list .phase.open)
 *   6  When a QC gate fails         (phase-list, qcHalt=true)
 *   7  Blocking errors inline       (panel-body, blocked=true)
 *   8  One primary action           (run-footer)
 *   9  Detach without losing        (watcher)
 *  10  You're ready to explore      (center, "Got it")
 *
 * Also walks through all 4 scenarios via Tweaks: nfcore, gatk, cryosparc, admet.
 */

import { test } from '@playwright/test';
import { shot, pause } from './demo-helpers.js';

const DEMO = 'demo-09-reference-workflow-panel';
// Reference files served via standalone python http.server on port 7779
// Started with: python3 -m http.server 7779 --directory /home/yzhang/biomate/reference/claude_design
const REF_URL = 'http://localhost:7779/cro/Workflow%20Panel%20Redesign.html';

const STEP_PAUSE: Record<number, number> = {
  0: 6_000,
  1: 5_500,
  2: 5_500,
  3: 5_500,
  4: 5_500,
  5: 6_000,
  6: 6_000,
  7: 5_500,
  8: 5_500,
  9: 6_000,
};
const TOTAL_STEPS = 10;

test('Demo 9 — Reference Workflow Panel Tour', async ({ page }) => {
  test.setTimeout(600_000);

  // ─── 0. Open reference design ─────────────────────────────────────────────
  await page.goto(REF_URL, { waitUntil: 'networkidle', timeout: 30_000 });
  await page.evaluate(() => {
    try { localStorage.removeItem('biomate-tweaks'); } catch {}
    try { localStorage.removeItem('biomate_wf_tour_seen'); } catch {}
  });
  await page.reload({ waitUntil: 'networkidle' });
  await pause(page, 2_500);
  await shot(page, DEMO, '00_reference_home');

  // ─── 1. Start tour ────────────────────────────────────────────────────────
  const tutBtn = page.locator('.tut-btn').first();
  await tutBtn.waitFor({ state: 'visible', timeout: 15_000 });
  await tutBtn.hover();
  await pause(page, 1_000);
  await tutBtn.click();
  await pause(page, 900);
  await shot(page, DEMO, '01_tour_started');

  // ─── 2. Walk all 10 steps ─────────────────────────────────────────────────
  for (let i = 0; i < TOTAL_STEPS; i++) {
    await page.locator('.tour-callout').waitFor({ state: 'visible', timeout: 10_000 });
    await pause(page, 500);
    await shot(page, DEMO, `step_${String(i + 1).padStart(2, '0')}`);
    await pause(page, (STEP_PAUSE[i] ?? 5_500) - 500);

    const nextBtn = page.locator('.tour-callout .btn.primary').first();
    await nextBtn.waitFor({ state: 'visible', timeout: 5_000 });
    await nextBtn.click();
    await pause(page, 700);
    console.log(`[Demo9] Step ${i + 1}/${TOTAL_STEPS} done`);
  }

  await page.locator('.tour-callout').waitFor({ state: 'hidden', timeout: 5_000 });
  await pause(page, 1_800);
  await shot(page, DEMO, '02_tour_complete');

  // ─── 3. Tweaks — walk through all 4 scenarios ─────────────────────────────
  const tweaksToggle = page.locator('[title*="weak"], [aria-label*="weak"], .tweaks-toggle, .host-toolbar button').first();
  // Open tweaks via postMessage (how the host toolbar triggers it)
  await page.evaluate(() => window.postMessage({ type: '__activate_edit_mode' }, '*'));
  await pause(page, 1_200);

  const tweaks = page.locator('.tweaks').first();
  if (await tweaks.isVisible({ timeout: 4_000 }).catch(() => false)) {
    await shot(page, DEMO, '03_tweaks_open');

    for (const [label, name] of [['nf-core', 'nfcore'], ['GATK', 'gatk'], ['CryoSPARC', 'cryosparc'], ['ADMET', 'admet']]) {
      const btn = page.locator('.tweaks').locator(`button.opt`).filter({ hasText: new RegExp(label, 'i') }).first();
      if (await btn.isVisible({ timeout: 2_000 }).catch(() => false)) {
        await btn.click();
        await pause(page, 2_000);
        await shot(page, DEMO, `04_scenario_${name}`);
        console.log(`[Demo9] Scenario ${name} captured`);
      }
    }

    // Show QC halt state
    const qcBtn = page.locator('.tweaks button.opt').filter({ hasText: /qc halt/i }).first();
    if (await qcBtn.isVisible({ timeout: 2_000 }).catch(() => false)) {
      await qcBtn.click();
      await pause(page, 2_000);
      await shot(page, DEMO, '05_qc_halt_state');
    }

    // Close tweaks
    await page.evaluate(() => window.postMessage({ type: '__deactivate_edit_mode' }, '*'));
    await pause(page, 800);
  }

  await shot(page, DEMO, 'done');
  console.log('[Demo9] ✅ Reference Workflow Panel Tour complete');
});
