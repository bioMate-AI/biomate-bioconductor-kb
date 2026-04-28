/**
 * Demo B01 — WGS Germline GATK4 · idle
 * Tips: 3-phase overview → phase breakdown (SRA/BWA-MEM2/HaplotypeCaller) → ready to run
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'B01-gatk-idle';
const LABEL = 'B01 — GATK idle';
const N_STEPS = 3;

test('B01 — GATK idle: variant-calling param form with tips', async ({ page }) => {
  test.setTimeout(200_000);

  // Pre-tour: idle GATK param form
  await loadRef(page, { scenario: 'gatk', runState: 'idle' });
  await shot(page, DEMO, 'pre_idle');
  await pause(page, 3_000);

  // Run the tour — 3 tips: WGS overview, phase breakdown, hg38 ready
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[B01] ✅ GATK idle demo complete');
});
