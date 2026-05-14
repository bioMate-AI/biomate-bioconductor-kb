/**
 * Demo T05 — Atlas + Modality Triage (Q4 2024 FDA validation story)
 *
 * Scientific story: We ran the same framework on every Q4 2024 FDA approval.
 * 7/7 verdicts match the documented label safety profile. This demo shows the
 * full atlas-driven modality triage for BCMA — recovering Abecma/Carvykti as
 * the validated CAR-T pattern, with ADC and bispecific also viable.
 *
 * Target runtime: 3 minutes.
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

const DEMO = 'demo-T05-modality-triage';
const EMAIL = 'demo_modality_triage@biomate.test';

const QUERY = `Score every therapeutic modality for BCMA based on single-cell atlas expression for multiple myeloma. Run atlas_expression_query first to characterize the target's normal-tissue distribution, then modality_triage to compare CAR-T, ADC, bispecific T-cell engager, PROTAC, ASO, and small molecule options.`;

test('Demo T05 — Modality triage for BCMA (Q4 2024 validation pattern)', async ({ page }) => {
  test.setTimeout(900_000);

  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Target Triage');
  await pause(page, 1500);
  await shot(page, DEMO, '00_start');

  await tip(
    page,
    'We ran this framework on every Q4 2024 FDA approval — Itovebi, Hympavzi, Vyloy, Tryngolza, Bizengri, Voranigo, Niktimvo. 7/7 match the approved label.',
    8000
  );
  await pause(page, 5500);
  await shot(page, DEMO, '01_intro_tip');

  await tip(
    page,
    'Today: run it on BCMA, the multiple myeloma target behind Abecma and Carvykti. What does the framework recommend?',
    6500
  );
  await pause(page, 4500);

  // ── Type query ─────────────────────────────────────────────────────────────
  await sendAndWait(page, QUERY, 180_000);
  await shot(page, DEMO, '02_workflow_ready');

  await tip(
    page,
    'Two workflows chained: atlas_expression_query → modality_triage. Confidence 96 on the routing.',
    5500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '03_extracted_params');

  // ── Review parameters ──────────────────────────────────────────────────────
  await tip(
    page,
    'BCMA atlas profile: plasma cells (high) + plasmablasts (moderate). No critical tissue hits — clean for cell therapy.',
    7000
  );
  await pause(page, 5000);
  await shot(page, DEMO, '04_atlas_profile');

  // ── Execute ────────────────────────────────────────────────────────────────
  await tip(page, 'Submitting to AWS Batch.', 3500);
  await pause(page, 1500);
  const runId = await clickRunAndWait(page, 600_000);
  console.log('[DemoT05] Run complete. runId:', runId);
  await shot(page, DEMO, '05_run_complete');

  await waitForNoActiveRuns(page, 600_000);
  await pause(page, 5000);

  // ── Show outputs ───────────────────────────────────────────────────────────
  await tip(
    page,
    'CAR-T VIABLE — exactly the Abecma/Carvykti pattern, BCMA + 4-1BB costim. ADC VIABLE. Bispecific VIABLE.',
    7000
  );
  await pause(page, 5000);
  await shot(page, DEMO, '06_modality_ranking');

  await tip(
    page,
    'Plus an IHC follow-up panel — top 5 expressing tissues with antibody validation guidance for IND prep.',
    6500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '07_ihc_panel');

  // ── Closing ────────────────────────────────────────────────────────────────
  await tip(
    page,
    'Run BioMate on your unannounced 2025 pipeline. We will show you what is in its atlas profile, before $50M of preclinical commitment.',
    7500
  );
  await pause(page, 5000);
  await shot(page, DEMO, '08_closing');
});
