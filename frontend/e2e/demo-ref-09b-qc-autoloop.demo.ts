/**
 * Demo 09b — nf-core fastp QC · QC autoloop
 * Tips: QC step active → gate tripped → accept or dismiss → auto-loop closed
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'ref-09b-qc-autoloop';
const LABEL = '09b — nfcore QC autoloop';
const N_STEPS = 4;

test('Ref-09b — QC auto-loop: gate trips, autoloop card, resolved', async ({ page }) => {
  test.setTimeout(240_000);

  // Pre-tour: show running state before gate fires
  await loadRef(page, { scenario: 'nfcore', runState: 'running', speed: 900 });
  await shot(page, DEMO, 'pre_running');
  await pause(page, 3_000);

  // Run the tour — 4 tips: qc active, gate tripped, accept/dismiss, loop closed
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[09b] ✅ QC auto-loop demo complete');
});
