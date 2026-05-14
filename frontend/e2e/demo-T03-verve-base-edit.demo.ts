/**
 * Demo T03 — In Vivo Base Editing (VERVE-102 story)
 *
 * Scientific story: Verve VERVE-101 paused Nov 2023 (LFT). VERVE-102 dosed Q4 2024
 * with reformulated LNP. Most-watched gene editing trial globally. BioMate's framework
 * recovers Verve's exact design (CBE, LNP-IV hepatocyte) from inputs alone — and
 * flags the LFT lesson without post-hoc knowledge.
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

const DEMO = 'demo-T03-verve-base-edit';
const EMAIL = 'demo_verve@biomate.test';

const QUERY = `Design an in vivo base edit for PCSK9 loss-of-function for hypercholesterolemia, the same kind of program Verve Therapeutics is running with VERVE-102.`;

test('Demo T03 — In vivo base edit: PCSK9 (VERVE-102 recovery)', async ({ page }) => {
  test.setTimeout(900_000);

  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Gene Editing');
  await pause(page, 1500);
  await shot(page, DEMO, '00_start');

  await tip(
    page,
    'VERVE-102 dosed first patient Q4 2024 — most-watched gene editing trial in the world. PCSK9 KO via in vivo base editing.',
    7000
  );
  await pause(page, 4500);
  await shot(page, DEMO, '01_intro_tip');

  await tip(
    page,
    'Can BioMate reach Verve\'s design from inputs alone? Editor class, delivery, LNP chemistry, IND-readiness checklist.',
    6500
  );
  await pause(page, 4500);

  // ── Type query ─────────────────────────────────────────────────────────────
  await sendAndWait(page, QUERY, 180_000);
  await shot(page, DEMO, '02_workflow_ready');

  await tip(
    page,
    'Routed to in_vivo_base_edit_design at confidence 164. Extracted gene=PCSK9 and reference=VERVE-102.',
    5500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '03_extracted_params');

  // ── Review parameters ──────────────────────────────────────────────────────
  await tip(
    page,
    'Editor: CBE (cytosine base editor) — premature stop via CAA→TAA. Delivery: LNP-IV to hepatocyte. Same as VERVE-102.',
    7000
  );
  await pause(page, 5000);
  await shot(page, DEMO, '04_design_decisions');

  // ── Execute ────────────────────────────────────────────────────────────────
  await tip(page, 'Submitting to AWS Batch — design package emerges in ~3 minutes.', 4500);
  await pause(page, 2000);
  const runId = await clickRunAndWait(page, 600_000);
  console.log('[DemoT03] Run complete. runId:', runId);
  await shot(page, DEMO, '05_run_complete');

  await waitForNoActiveRuns(page, 600_000);
  await pause(page, 5000);

  // ── Show outputs ───────────────────────────────────────────────────────────
  await tip(
    page,
    'CMC flag emitted: "VERVE-101 LFT elevation Nov 2023 — optimize LNP for lower hepatotoxicity (reduced PEG, alternative ionizable lipid)."',
    7500
  );
  await pause(page, 5500);
  await shot(page, DEMO, '06_cmc_flag');

  await tip(
    page,
    'That is the exact lesson Verve applied to VERVE-102 — recovered without seeing their actual reformulation.',
    6500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '07_lesson_recovered');

  // ── Closing ────────────────────────────────────────────────────────────────
  await tip(
    page,
    'Same framework recovers Beam BEAM-101 (sickle cell, ex vivo HSC, ABE) and Verve VERVE-201 (ANGPTL3).',
    7000
  );
  await pause(page, 5000);
  await shot(page, DEMO, '08_closing');
});
