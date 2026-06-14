/**
 * Shared helpers for reference-design demo recordings.
 *
 * Key principle: tweaks are applied silently via localStorage BEFORE the page
 * loads. The Tweaks panel is never shown on screen.
 *
 * Tutorials use the reference design's own built-in TourPicker + tour callout
 * (spotlight overlay). Call runTourDemo() to open the picker, select a specific
 * demo by its label, and step through all of its tip callouts.
 */

import type { Page } from '@playwright/test';

export const REF_URL = 'http://localhost:7779/biomate/Workflow%20Panel%20Redesign.html';

export interface RefTweaks {
  scenario?:       'nfcore' | 'gatk' | 'cryosparc' | 'admet';
  runState?:       'idle' | 'running' | 'completed' | 'failed';
  speed?:          number;
  panelWidth?:     number;
  sidebarMode?:    'auto' | 'expanded' | 'hidden';
  qcHalt?:         boolean;
  licenseGate?:    boolean;
  blocked?:        boolean;
  disambig?:       boolean;
  watcherAttached?: boolean;
}

const DEFAULTS: Required<RefTweaks> = {
  scenario:        'nfcore',
  runState:        'running',
  speed:           900,
  panelWidth:      510,
  sidebarMode:     'auto',
  qcHalt:          false,
  licenseGate:     false,
  blocked:         false,
  disambig:        false,
  watcherAttached: true,
};

/** Per-step hold time in ms (index 0 = first step). Used by runTourDemo(). */
export const TIP_STEP_PAUSE: Record<number, number> = {
  0: 6_000,
  1: 5_500,
  2: 5_500,
  3: 6_000,
  4: 5_500,
  5: 6_000,
  6: 5_500,
  7: 5_500,
  8: 5_500,
  9: 6_000,
};

/**
 * Load the reference design with the given tweaks pre-applied.
 */
export async function loadRef(page: Page, tweaks: RefTweaks): Promise<void> {
  const merged = { ...DEFAULTS, ...tweaks };

  await page.addInitScript((t) => {
    try { localStorage.setItem('biomate-tweaks', JSON.stringify(t)); } catch {}
    try { localStorage.removeItem('biomate_wf_tour_seen'); } catch {}
  }, merged);

  await page.goto(REF_URL, { waitUntil: 'networkidle', timeout: 30_000 });
  await page.waitForTimeout(2_500);
}

/**
 * Switch tweaks mid-recording by updating localStorage and reloading.
 */
export async function switchTweaks(page: Page, tweaks: RefTweaks): Promise<void> {
  const current = await page.evaluate(() => {
    try { return JSON.parse(localStorage.getItem('biomate-tweaks') || '{}'); } catch { return {}; }
  });
  const merged = { ...DEFAULTS, ...current, ...tweaks };

  await page.evaluate((t) => {
    try { localStorage.setItem('biomate-tweaks', JSON.stringify(t)); } catch {}
  }, merged);

  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForTimeout(2_000);
}

/**
 * Open the TourPicker, select a specific demo by its label, then step through
 * all N tip callouts — screenshotting each one.
 *
 * @param label   Exact label shown in the picker (e.g. '09a — nfcore normal run')
 * @param nSteps  Number of steps in that demo's tour
 */
export async function runTourDemo(
  page: Page,
  demo: string,
  label: string,
  nSteps: number,
  /**
   * Optional per-step pause override (index 0 = first step).
   * Sparse map; missing indices fall back to TIP_STEP_PAUSE then 5_500ms.
   * Use for content-dense steps like a stats-trap explanation or a multi-score
   * disambig card — see docs/20260610_BIOC_TUTORIAL_NARRATIVE_AUDIT.md
   * for the timing audit that prompted this hook.
   */
  pauseOverride?: Record<number, number>,
): Promise<void> {
  // Click the Tutorial button to open the picker
  const tutBtn = page.locator('.tut-btn').first();
  await tutBtn.waitFor({ state: 'visible', timeout: 15_000 });
  await tutBtn.hover();
  await page.waitForTimeout(600);
  await tutBtn.click();
  await page.waitForTimeout(900);

  // Screenshot the picker so it's visible in the video
  await page.locator('.tour-picker').waitFor({ state: 'visible', timeout: 10_000 });
  await page.waitForTimeout(400);
  await shot(page, demo, '00_picker');

  // Select this demo from the list
  await page.locator('.tour-picker-item').filter({ hasText: label }).click();
  await page.waitForTimeout(800);

  // Step through all N tour steps
  for (let i = 0; i < nSteps; i++) {
    await page.locator('.tour-callout').waitFor({ state: 'visible', timeout: 10_000 });
    await page.waitForTimeout(500);
    await shot(page, demo, `tip_${String(i + 1).padStart(2, '0')}`);
    const baseHold = pauseOverride?.[i] ?? TIP_STEP_PAUSE[i] ?? 5_500;
    await page.waitForTimeout(baseHold - 500);
    const nextBtn = page.locator('.tour-callout .btn.primary').first();
    await nextBtn.waitFor({ state: 'visible', timeout: 5_000 });
    await nextBtn.click();
    await page.waitForTimeout(700);
  }

  // Wait for callout to close
  await page.locator('.tour-callout').waitFor({ state: 'hidden', timeout: 8_000 });
  await page.waitForTimeout(1_200);
}

/** Take a named screenshot into e2e/screenshots/<demo>/<name>.png */
export async function shot(page: Page, demo: string, name: string): Promise<void> {
  const { mkdirSync } = await import('fs');
  const dir = `e2e/screenshots/${demo}`;
  mkdirSync(dir, { recursive: true });
  await page.screenshot({ path: `${dir}/${name}.png`, fullPage: false });
  console.log(`[Screenshot] ${demo}/${name}.png`);
}

export const pause = (page: Page, ms: number) => page.waitForTimeout(ms);
