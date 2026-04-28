/**
 * Demo A08 — nf-core fastp QC · watcher detach/reattach
 * Tips: watcher attached (live SSE) → detach without stopping → reopen any time
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'A08-nfcore-watcher';
const LABEL = 'A08 — nfcore watcher';
const N_STEPS = 3;

test('A08 — nfcore watcher: attach, detach, reattach flow', async ({ page }) => {
  test.setTimeout(200_000);

  // Pre-tour: running with watcher attached
  await loadRef(page, { scenario: 'nfcore', runState: 'running', watcherAttached: true, speed: 1200 });
  await shot(page, DEMO, 'pre_attached');
  await pause(page, 3_000);

  // Run the tour — 3 tips: watcher attached, detach without stopping, reopen anytime
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[A08] ✅ nfcore watcher demo complete');
});
