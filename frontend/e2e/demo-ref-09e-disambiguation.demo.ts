/**
 * Demo 09e — Disambiguation card
 * Tips: two matching pipelines → selected pipeline loaded → running with confidence
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'ref-09e-disambiguation';
const LABEL = '09e — disambiguation';
const N_STEPS = 3;

test('Ref-09e — Disambiguation: two close matches, selection, run', async ({ page }) => {
  test.setTimeout(200_000);

  // Pre-tour: disambiguation card visible
  await loadRef(page, { scenario: 'nfcore', runState: 'idle', disambig: true });
  await shot(page, DEMO, 'pre_disambig');
  await pause(page, 3_000);

  // Run the tour — 3 tips: two matches shown, pipeline selected, running
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[09e] ✅ Disambiguation demo complete');
});
