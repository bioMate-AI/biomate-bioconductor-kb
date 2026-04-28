/**
 * Demo 09a — nf-core fastp QC · normal run
 * Tips: parameters auto-filled → live progress bar → phase hierarchy → run complete
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'ref-09a-normal-run';
const LABEL = '09a — nfcore normal run';
const N_STEPS = 4;

test('Ref-09a — Normal run: nf-core fastp QC with tips', async ({ page }) => {
  test.setTimeout(240_000);

  // Pre-tour: show idle state with param form
  await loadRef(page, { scenario: 'nfcore', runState: 'idle' });
  await shot(page, DEMO, 'pre_idle');
  await pause(page, 3_000);

  // Run the tour — 4 tips: params autofill, live bar, phase list, run complete
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[09a] ✅ Normal run demo complete');
});
