/**
 * Demo A01 — nf-core fastp QC · idle state
 * Tips: idle state, preview phases + QC gates, Confirm & Run
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'A01-nfcore-idle';
const LABEL = 'A01 — nfcore idle';
const N_STEPS = 3;

test('A01 — nfcore idle: param form, phase preview, run footer', async ({ page }) => {
  test.setTimeout(200_000);

  // Pre-tour: idle param form
  await loadRef(page, { scenario: 'nfcore', runState: 'idle' });
  await shot(page, DEMO, 'pre_idle');
  await pause(page, 3_000);

  // Run the tour — 3 tips: idle state, preview phases, one primary action
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[A01] ✅ nfcore idle demo complete');
});
