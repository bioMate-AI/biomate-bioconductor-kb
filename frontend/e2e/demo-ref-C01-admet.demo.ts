/**
 * Demo C01 — ADMET Property Prediction
 * Tips: single-step SMILES parsed → ADMET-AI computing endpoints → hERG gate tripped → CSV + AI analysis
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'C01-admet';
const LABEL = 'C01 — ADMET';
const N_STEPS = 4;

test('C01 — ADMET: single-step prediction, hERG QC gate, findings', async ({ page }) => {
  test.setTimeout(240_000);

  // Pre-tour: idle with SMILES pre-filled
  await loadRef(page, { scenario: 'admet', runState: 'idle' });
  await shot(page, DEMO, 'pre_idle');
  await pause(page, 3_000);

  // Run the tour — 4 tips: SMILES parsed, ADMET computing, hERG gate, endpoints ready
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[C01] ✅ ADMET demo complete');
});
