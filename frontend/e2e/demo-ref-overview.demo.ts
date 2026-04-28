/**
 * Demo Overview — Full 10-step walkthrough
 * Tips: welcome → chat handoff → panel header → phase list → running phase →
 *       QC gate fails → blocking errors → one primary action → detach watcher → done
 */
import { test } from '@playwright/test';
import { loadRef, runTourDemo, shot, pause } from './demo-ref-helpers.js';

const DEMO = 'overview';
const LABEL = 'Overview — full walkthrough';
const N_STEPS = 10;

test('Overview — full 10-step walkthrough of BioMate workflow panel', async ({ page }) => {
  test.setTimeout(360_000);

  // Pre-tour: nfcore running, watcher attached
  await loadRef(page, { scenario: 'nfcore', runState: 'running', watcherAttached: true });
  await shot(page, DEMO, 'pre_running');
  await pause(page, 3_000);

  // Run the overview tour — 10 steps covering all panel features and edge cases
  await runTourDemo(page, DEMO, LABEL, N_STEPS);

  await shot(page, DEMO, 'done');
  console.log('[Overview] ✅ Full overview demo complete');
});
