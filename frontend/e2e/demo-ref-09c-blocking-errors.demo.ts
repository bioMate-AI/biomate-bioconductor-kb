/**
 * Demo 09c — Blocking errors (licenseGate + blocked param)
 * Tips: two blockers found → license configured → all clear
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'ref-09c-blocking-errors';
const LABEL = '09c — blocking errors';
const N_STEPS = 3;

test('Ref-09c — Blocking errors: license gate + missing param', async ({ page }) => {
  test.setTimeout(200_000);

  // Pre-tour: show both blockers active — run disabled
  await loadRef(page, { scenario: 'nfcore', runState: 'idle', licenseGate: true, blocked: true });
  await shot(page, DEMO, 'pre_blocked');
  await pause(page, 3_000);

  // Run the tour — 3 tips: two blockers, license fixed, all clear
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[09c] ✅ Blocking errors demo complete');
});
