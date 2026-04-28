/**
 * Demo B02 — WGS Germline GATK4 · running
 * Tips: Phase A downloading from SRA → Phase B queued (BWA/BQSR) → SSE stream open
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'B02-gatk-running';
const LABEL = 'B02 — GATK running';
const N_STEPS = 3;

test('B02 — GATK running: alignment + variant calling in progress', async ({ page }) => {
  test.setTimeout(200_000);

  // Pre-tour: GATK running, Phase A active
  await loadRef(page, { scenario: 'gatk', runState: 'running', speed: 900, watcherAttached: true });
  await shot(page, DEMO, 'pre_running');
  await pause(page, 3_000);

  // Run the tour — 3 tips: SRA download, BWA queued, SSE stream
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[B02] ✅ GATK running demo complete');
});
