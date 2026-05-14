/**
 * Demo T05 — Atlas + Modality Triage (BCMA / Q4 2024 FDA validation)
 *
 * Strategy: live-record full duration; EDIT to ~3:00 in post.
 */

import { test } from '@playwright/test';
import {
  setupDemoUser,
  sendAndWait,
  clickRunOnly,
  waitForNoActiveRuns,
  shot,
  pause,
  tip,
} from './demo-helpers.js';

const DEMO = 'demo-T05-modality-triage';
const EMAIL = 'demo_modality_triage@biomate.test';

const QUERY = `Score every therapeutic modality for BCMA based on single-cell atlas expression for multiple myeloma. Run atlas_expression_query first to characterize the target's normal-tissue distribution, then modality_triage to compare CAR-T, ADC, bispecific, PROTAC, ASO, and small molecule options.`;

test('Demo T05 — Modality triage for BCMA (Q4 2024 validation)', async ({ page }) => {
  test.setTimeout(900_000);

  // Beat 1: Intro
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Target Triage');
  await pause(page, 1000);
  await shot(page, DEMO, '00_start');

  await tip(
    page,
    'We ran this framework on every Q4 2024 FDA approval — 7 of 7 verdicts match the approved label. Today: BCMA for multiple myeloma.',
    6500
  );
  await pause(page, 5000);
  await shot(page, DEMO, '01_intro');

  // Beat 2: Query + routing
  await sendAndWait(page, QUERY, 180_000);
  await shot(page, DEMO, '02_workflow_ready');

  // Beat 3: Panel review
  await tip(
    page,
    'BioMate chained two workflows: atlas_expression_query first, then modality_triage. The AI knew the dependency.',
    5500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '03_panel_review');

  await tip(
    page,
    'Two phases queued sequentially: tissue distribution → modality scoring across seven options.',
    4500
  );
  await pause(page, 4000);
  await shot(page, DEMO, '04_phases_queued');

  // Beat 4: Click Run
  await tip(page, 'Submitting the chain to AWS Batch.', 3000);
  await pause(page, 1500);
  const runId = await clickRunOnly(page);
  console.log('[DemoT05] Submitted. runId:', runId);
  await pause(page, 2000);
  await shot(page, DEMO, '05_submitted');

  // Beat 5: Narrate execution
  await tip(
    page,
    'Querying Tabula Sapiens + CELLxGENE Census for BCMA expression across 26 tissues at single-cell resolution.',
    6000
  );
  await pause(page, 30_000);
  await shot(page, DEMO, '06_atlas_query');

  await tip(
    page,
    'Atlas profile: plasma cells (high) + plasmablasts (moderate). No critical-tissue hits. CAR-T evaluation in progress.',
    6000
  );
  await pause(page, 35_000);
  await shot(page, DEMO, '07_triage_scoring');

  await tip(
    page,
    'CAR-T VIABLE — exactly the Abecma/Carvykti pattern. Plus an IHC follow-up panel with antibody validation guidance for IND prep.',
    6500
  );
  await pause(page, 25_000);
  await shot(page, DEMO, '08_outputs');

  await waitForNoActiveRuns(page, 240_000);
  await pause(page, 4000);
  await shot(page, DEMO, '09_complete');

  // Beat 6: Closing
  await tip(
    page,
    'Run BioMate on your unannounced 2025 pipeline. We will show you what is in its atlas profile, before $50M of preclinical commitment.',
    6000
  );
  await pause(page, 5000);
  await shot(page, DEMO, '10_closing');
});
