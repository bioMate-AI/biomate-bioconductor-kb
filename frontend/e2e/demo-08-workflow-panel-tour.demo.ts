/**
 * Demo 8 — BioMate Workflow Panel Tutorial Tour
 *
 * Records the 9-step built-in tutorial tour that lives inside the Workflow Panel.
 * The tour was ported from the Claude design reference (reference/claude_design/cro/src/Tour.jsx)
 * and covers the full lifecycle of a bioinformatics run:
 *
 *   Step 1  — Welcome (center overlay)
 *   Step 2  — From chat to workflow  (data-tour="chat-handoff", right)
 *   Step 3  — Run status at a glance (data-tour="panel-header", left)
 *   Step 4  — Phases, not a flat list (data-tour="phase-list", left)
 *   Step 5  — When a QC gate fails   (data-tour="phase-list", left)
 *   Step 6  — Blocking errors inline  (data-tour="panel-body", left)
 *   Step 7  — One primary action      (data-tour="run-footer", top)
 *   Step 8  — Detach without losing   (data-tour="watcher", top)
 *   Step 9  — You're ready (center overlay, "Got it")
 *
 * Total recording time ≈ 2.5 min (slow, easy to follow).
 */

import { test } from '@playwright/test';
import {
  setupDemoUser,
  shot,
  pause,
  sendAndWait,
  BASE_URL,
} from './demo-helpers.js';

const DEMO  = 'demo-08-workflow-panel-tour';
const EMAIL = 'demo_wf_tour@biomate.test';

// Pause on each step index before advancing (ms) — slow enough to read comfortably.
const STEP_PAUSE: Record<number, number> = {
  0: 6_000,  // Welcome — centre slide, viewers read the intro
  1: 5_500,  // Chat-handoff spotlight
  2: 5_500,  // Panel-header spotlight
  3: 5_500,  // Phase-list spotlight
  4: 5_500,  // QC-halt callout (same target as phase-list)
  5: 5_000,  // Blocked/alert callout
  6: 5_000,  // Run-footer spotlight
  7: 5_000,  // Watcher bar spotlight
  8: 6_000,  // Done — centre slide, "Got it"
};
const DEFAULT_STEP_PAUSE = 5_000;
const TOTAL_STEPS = 9;

test('Demo 8 — Workflow Panel Tutorial Tour', async ({ page }) => {
  test.setTimeout(600_000); // 10-min ceiling for slow pacing

  // ─── 0. Auth ──────────────────────────────────────────────────────────────
  console.log('[Demo8] Login and navigate to BioMate');
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Drug Discovery');

  // Extra pause after login — let the page fully settle before recording
  await pause(page, 2_000);
  await shot(page, DEMO, '00_home');

  // ─── 1. Open the Workflow Panel by asking BioMate to run a pipeline ───────
  console.log('[Demo8] Sending workflow query to open the panel');
  const panelOpened = await sendAndWait(
    page,
    'Run ADMET screening on aspirin (CAS 50-78-2)',
    60_000,
  );

  if (!panelOpened) {
    console.warn('[Demo8] Run button not visible — checking if panel already open');
  }

  // Wait for the workflow panel to be present in DOM
  await page.waitForSelector(
    '[data-testid="workflow-right-panel"], [data-testid="workflow-artifact-panel"], [data-testid="button-start-tour"]',
    { state: 'visible', timeout: 45_000 },
  );
  // Long pause so viewers can read the panel before the tour starts
  await pause(page, 2_500);

  await shot(page, DEMO, '01_panel_open');

  // ─── 2. Hover over Tutorial button, then click ────────────────────────────
  console.log('[Demo8] Hovering over Tutorial button');
  const tutBtn = page.locator('[data-testid="button-start-tour"]').first();
  await tutBtn.waitFor({ state: 'visible', timeout: 15_000 });
  await tutBtn.hover();
  await pause(page, 1_500);  // viewers see hover state
  await tutBtn.click();
  await pause(page, 1_000);  // wait for overlay fade-in

  await shot(page, DEMO, '02_tour_started');

  // ─── 3. Step through all 9 tour steps ────────────────────────────────────
  for (let stepIdx = 0; stepIdx < TOTAL_STEPS; stepIdx++) {
    const stepPause = STEP_PAUSE[stepIdx] ?? DEFAULT_STEP_PAUSE;
    console.log(`[Demo8] Tour step ${stepIdx + 1}/${TOTAL_STEPS} — pause ${stepPause}ms`);

    // Wait for the callout to appear (it animates in)
    await page.locator('.tour-callout').waitFor({ state: 'visible', timeout: 8_000 });
    // Extra settle time so the callout animation completes before screenshot
    await pause(page, 600);

    await shot(page, DEMO, `step_${String(stepIdx + 1).padStart(2, '0')}`);

    // Hold on each step so viewers can read the callout text
    await pause(page, stepPause - 600);

    // Click "Next →" / "Got it" — last step
    const nextBtn = page.locator('.tour-callout .tour-btn.primary').first();
    await nextBtn.waitFor({ state: 'visible', timeout: 5_000 });
    await nextBtn.click();
    // Pause after click so the transition between steps is smooth (not jarring)
    await pause(page, 700);
  }

  // ─── 4. Confirm tour overlay is gone ─────────────────────────────────────
  console.log('[Demo8] Tour complete — verifying overlay dismissed');
  await page.locator('.tour-callout').waitFor({ state: 'hidden', timeout: 5_000 });
  await pause(page, 2_000);

  await shot(page, DEMO, '03_tour_done_panel_visible');

  // ─── 5. Show Tutorial button for replay ──────────────────────────────────
  console.log('[Demo8] Highlighting Tutorial button for replay demo');
  const tutBtnAgain = page.locator('[data-testid="button-start-tour"]').first();
  if (await tutBtnAgain.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await tutBtnAgain.scrollIntoViewIfNeeded();
    await tutBtnAgain.hover();
    await pause(page, 2_000);
    await shot(page, DEMO, '04_tutorial_btn_hover');
  }

  await shot(page, DEMO, 'done');
  console.log('[Demo8] ✅ Workflow Panel Tutorial Tour recording complete');
});
