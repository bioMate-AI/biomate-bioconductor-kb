/**
 * Demo A04 — nf-core fastp QC · failed state
 * Tips: run failed badge → failed step with error inline → run again or diagnose
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'A04-nfcore-failed';
const LABEL = 'A04 — nfcore failed';
const N_STEPS = 3;

test('A04 — nfcore failed: error state, failed step, retry option', async ({ page }) => {
  test.setTimeout(200_000);

  // Pre-tour: failed state showing error banner
  await loadRef(page, { scenario: 'nfcore', runState: 'failed' });
  await shot(page, DEMO, 'pre_failed');
  await pause(page, 3_500);

  // Run the tour — 3 tips: run failed, failed step highlighted, run again
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[A04] ✅ nfcore failed demo complete');
});
