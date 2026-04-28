/**
 * Demo B03 — WGS Germline GATK4 · completed
 * Tips: all 3 phases done (VCF/BAM/QC) → per-phase outputs → Download All + Methods Report
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'B03-gatk-completed';
const LABEL = 'B03 — GATK completed';
const N_STEPS = 3;

test('B03 — GATK completed: VCF output, variant stats, downloads', async ({ page }) => {
  test.setTimeout(200_000);

  // Pre-tour: completed state with results links
  await loadRef(page, { scenario: 'gatk', runState: 'completed' });
  await shot(page, DEMO, 'pre_completed');
  await pause(page, 3_000);

  // Run the tour — 3 tips: all phases done, per-phase outputs, download+methods
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[B03] ✅ GATK completed demo complete');
});
