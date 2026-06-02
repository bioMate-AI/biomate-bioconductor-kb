/**
 * Cryo Tutorial Recording — Research Agent UI
 *
 * Records two tours from the Research Agent UI sandbox:
 *   09d — CryoSPARC SPA · 3-minute deep dive   (20 steps, cartoon)
 *   09f — After run · all tabs                   (13 steps, cartoon)
 *
 * Uses the Playwright `demo` project which has video: 'on' at 1920×1080.
 * Videos land in e2e/demo-artifacts/ automatically.
 *
 * Run with:
 *   npx playwright test e2e/cryo-tutorial-research-ui.demo.ts --project=demo
 */

import { test, chromium } from '@playwright/test';
import type { Page } from '@playwright/test';
import { mkdirSync } from 'fs';

// ── URL ─────────────────────────────────────────────────────────────────────
const RESEARCH_UI_URL =
  'http://localhost:7779/tutorials-work/Cryo%20Tutorial%20Package/' +
  'Cryo%20Tutorial%20(Research%20Agent%20UI)/Research%20Agent%20UI.html';

// ── Initial tweaks (cryosparc scenario, comfortable density, light theme) ───
const INITIAL_TWEAKS = {
  scenarioId: 'cryosparc',
  speed: 1.0,
  theme: 'light',
  density: 'comfortable',
  panelWidth: 530,
  sidebarMode: 'auto',
  panelOpen: true,
  pillPlacement: 'after-marker',
  collapseThreshold: 3,
  showTs: false,
  planEditDefault: true,
  comparePlacement: 'inline',
  pilotDefaultOn: true,
  countdownSeconds: 10,
  autoStartScenario: false,
};

// ── Per-step pause (ms) keyed by 0-based step index ─────────────────────────
// Derived from narration script timings at ~150 wpm + 1.5s breath.

/** 09d — CryoSPARC SPA deep dive (20 steps) */
const STEP_PAUSE_09D: Record<number, number> = {
  0:  7_000,  // Welcome
  1:  8_000,  // Two views / plan checklist
  2:  6_000,  // Run header
  3:  9_000,  // 5 phases overview
  4:  7_000,  // Inside Phase A
  5:  8_000,  // Confirm & Run
  6:  5_500,  // We're off!
  7:  7_500,  // Live progress per step
  8:  8_000,  // CTF gate tripped
  9: 12_000,  // Halt card — longer beat (auto-loop explanation)
  10: 8_000,  // Gate cleared
  11: 8_000,  // Step outputs
  12: 7_000,  // Phase B picking
  13: 6_000,  // Phase C 2D
  14: 6_500,  // Phase D 3D
  15: 8_000,  // Phase E sharpening
  16: 6_000,  // All 23 steps complete
  17: 6_500,  // Outputs downloadable
  18: 7_000,  // After-run section
  19: 9_000,  // Wrap-up (last)
};

/** 09f — After run · all tabs (13 steps) */
const STEP_PAUSE_09F: Record<number, number> = {
  0:  18_000,  // Intro — long (multi-sentence)
  1:  11_000,  // After-run header + Download
  2:  16_000,  // 7 tabs
  3:  20_000,  // Findings tab — longest
  4:  19_000,  // Outputs tab
  5:   8_000,  // Outputs on step row
  6:  10_000,  // Inline preview
  7:  19_000,  // Methods tab
  8:  16_000,  // Parameters tab
  9:   6_500,  // Software tab
  10:  8_000,  // Citations tab
  11: 17_000,  // QC audit tab
  12: 18_000,  // Wrap-up
};

// ── Helpers ─────────────────────────────────────────────────────────────────

function screenshotDir(demo: string): string {
  const dir = `e2e/screenshots/${demo}`;
  mkdirSync(dir, { recursive: true });
  return dir;
}

async function shot(page: Page, demo: string, name: string): Promise<void> {
  const dir = screenshotDir(demo);
  await page.screenshot({ path: `${dir}/${name}.png`, fullPage: false });
  console.log(`[Screenshot] ${demo}/${name}.png`);
}

async function pause(page: Page, ms: number): Promise<void> {
  await page.waitForTimeout(ms);
}

/**
 * Load the Research Agent UI with pre-set tweaks in localStorage,
 * then wait until the React app has fully rendered (Babel transpilation
 * happens in-browser and can take 3–8 s).
 */
async function loadResearchUI(page: Page): Promise<void> {
  await page.addInitScript((tweaks) => {
    try {
      localStorage.setItem('biomate-research-tweaks', JSON.stringify(tweaks));
      localStorage.removeItem('biomate_wf_tour_seen');
    } catch (_) {}
  }, INITIAL_TWEAKS);

  await page.goto(RESEARCH_UI_URL, { waitUntil: 'load', timeout: 30_000 });

  // Wait for Babel to finish transpiling and React to render the Tutorial button
  await page.locator('.tut-btn').first().waitFor({ state: 'visible', timeout: 30_000 });
  // Extra settle time for the scenario engine to initialise
  await pause(page, 2_000);
}

/**
 * Open the TourPicker, launch a specific tour by label, then step through
 * all N steps using the per-step pause map.
 */
async function runTour(
  page: Page,
  demo: string,
  label: string,
  nSteps: number,
  stepPauses: Record<number, number>,
): Promise<void> {
  // Open the picker
  const tutBtn = page.locator('.tut-btn').first();
  await tutBtn.waitFor({ state: 'visible', timeout: 10_000 });
  await tutBtn.hover();
  await pause(page, 500);
  await tutBtn.click();
  await pause(page, 800);

  // Picker must be visible
  await page.locator('.tour-picker').waitFor({ state: 'visible', timeout: 10_000 });
  await pause(page, 400);
  await shot(page, demo, '00_picker');

  // Select the tour
  await page.locator('.tour-picker-item').filter({ hasText: label }).click();
  await pause(page, 1_000);

  // Walk each step
  for (let i = 0; i < nSteps; i++) {
    await page.locator('.tour-callout').waitFor({ state: 'visible', timeout: 10_000 });
    await pause(page, 400);
    await shot(page, demo, `step_${String(i + 1).padStart(2, '0')}`);

    // Hold for the narration beat (minus the screenshot time already spent)
    const hold = Math.max(500, (stepPauses[i] ?? 7_000) - 400);
    await pause(page, hold);

    // Advance — callout has a CSS entry animation; force: true bypasses
    // the stability check so we don't wait 60s for an animating element.
    const nextBtn = page.locator('.tour-callout .btn.primary').first();
    await nextBtn.waitFor({ state: 'visible', timeout: 5_000 });
    // Wait for animation to settle (~300ms for typical CSS transitions)
    await pause(page, 400);
    await nextBtn.click({ force: true });
    await pause(page, 600);
  }

  // Confirm callout closed
  await page.locator('.tour-callout').waitFor({ state: 'hidden', timeout: 8_000 });
  await pause(page, 1_500);
}

// ── Tests ────────────────────────────────────────────────────────────────────

test('09d — CryoSPARC SPA · 3-minute deep dive', async ({ page }) => {
  test.setTimeout(300_000); // 5 min ceiling

  const DEMO = 'cryo-09d-research-ui';

  await loadResearchUI(page);
  await shot(page, DEMO, 'pre_load');
  await pause(page, 2_000);

  await runTour(
    page,
    DEMO,
    '09d — CryoSPARC SPA · 3-minute deep dive',
    20,
    STEP_PAUSE_09D,
  );

  await shot(page, DEMO, 'done');
  console.log('[09d] ✅ CryoSPARC SPA tutorial recording complete');
});

test('09f — After run · all tabs', async ({ page }) => {
  test.setTimeout(300_000); // 5 min ceiling

  const DEMO = 'cryo-09f-research-ui';

  await loadResearchUI(page);
  await shot(page, DEMO, 'pre_load');
  await pause(page, 2_000);

  await runTour(
    page,
    DEMO,
    '09f — After run · all tabs',
    13,
    STEP_PAUSE_09F,
  );

  await shot(page, DEMO, 'done');
  console.log('[09f] ✅ After-run report tutorial recording complete');
});
