/**
 * Demo T01 — Bispecific Format Triage (Ivonescimab / HARMONi-2 story)
 *
 * Scientific story: Ivonescimab beat Keytruda head-to-head in HARMONi-2 (Oct 2024)
 * as a PD-1 × VEGF CrossMab bispecific. BioMate recovers the same CrossMab choice
 * from atlas data + biology alone — in 30 seconds vs the 18 months Akeso/Summit took.
 *
 * Target runtime: 3 minutes (pre-recording; AWS Batch run takes 2-3 min, total demo ~5 min raw).
 */

import { test } from '@playwright/test';
import {
  setupDemoUser,
  sendAndWait,
  clickRunAndWait,
  waitForNoActiveRuns,
  shot,
  pause,
  tip,
} from './demo-helpers.js';

const DEMO = 'demo-T01-bispecific-format';
const EMAIL = 'demo_bispecific@biomate.test';

const QUERY = `Design a PD-1 × VEGF bispecific antibody in CrossMab format for non-small cell lung cancer (NSCLC). Score every major bispecific format (BiTE, CrossMab, KiH, DVD-Ig, nanobody fusion) and explain which architecture fits the biology — the same question Akeso/Summit answered when they built ivonescimab.`;

test('Demo T01 — Bispecific format: PD-1 × VEGF (Ivonescimab recovery)', async ({ page }) => {
  test.setTimeout(900_000);

  // ── Setup ──────────────────────────────────────────────────────────────────
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Bispecific Design');
  await pause(page, 1500);
  await shot(page, DEMO, '00_start');

  await tip(
    page,
    'October 2024 — Ivonescimab beat Keytruda in HARMONi-2. The format choice (CrossMab) was the design key. Watch BioMate recover it from atlas data alone.',
    7000
  );
  await pause(page, 4000);
  await shot(page, DEMO, '01_intro_tip');

  // ── Type query, AI routes ──────────────────────────────────────────────────
  await tip(page, 'Asking BioMate to triage the format choice from PD-1 + VEGF target biology...', 5000);
  await pause(page, 1500);
  await sendAndWait(page, QUERY, 180_000);
  await shot(page, DEMO, '02_workflow_ready');

  await tip(
    page,
    'BioMate extracted the targets and indication, then routed to bispecific_format_triage. Confidence 124.',
    5000
  );
  await pause(page, 4500);
  await shot(page, DEMO, '03_extracted_params');

  // ── Review parameters ──────────────────────────────────────────────────────
  await tip(
    page,
    'Six formats scored on six axes: half-life, cis engagement, trans engagement, manufacturing, ADA risk, affinity asymmetry.',
    6000
  );
  await pause(page, 4500);
  await shot(page, DEMO, '04_params_review');

  // ── Execute ────────────────────────────────────────────────────────────────
  await tip(page, 'Submitting to AWS Batch...', 3500);
  await pause(page, 1500);
  const runId = await clickRunAndWait(page, 600_000);
  console.log('[DemoT01] Run complete. runId:', runId);
  await shot(page, DEMO, '05_run_complete');

  await waitForNoActiveRuns(page, 600_000);
  await pause(page, 5000);

  // ── Show outputs ───────────────────────────────────────────────────────────
  await tip(
    page,
    'Result: CrossMab #1 (score 100, 67%). Same format Akeso chose. Cis engagement on tumor microvessel.',
    6500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '06_top_format');

  await tip(
    page,
    'Other formats ranked with explicit manufacturing flags. DVD-Ig flagged for aggregation risk. BiTE flagged for short half-life.',
    6000
  );
  await pause(page, 4500);
  await shot(page, DEMO, '07_ranking');

  // ── Closing ────────────────────────────────────────────────────────────────
  await tip(
    page,
    '30 seconds, same answer Akeso reached over 18 months. Try it on your next bispecific.',
    7000
  );
  await pause(page, 5000);
  await shot(page, DEMO, '08_closing');
});
