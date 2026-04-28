/**
 * Demo 09d — CryoSPARC SPA (5 phases, 23 steps)
 * Tips: 5-phase overview → progress bar → CTF fit quality gate → 3D complete
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'ref-09d-cryosparc';
const LABEL = '09d — CryoSPARC SPA';
const N_STEPS = 4;

test('Ref-09d — CryoSPARC SPA: 5-phase walkthrough with QC gate', async ({ page }) => {
  test.setTimeout(240_000);

  // Pre-tour: idle with 5-phase structure visible
  await loadRef(page, { scenario: 'cryosparc', runState: 'idle' });
  await shot(page, DEMO, 'pre_idle_5phases');
  await pause(page, 3_000);

  // Run the tour — 4 tips: phase list, progress, CTF gate, reconstruction done
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[09d] ✅ CryoSPARC demo complete');
});
