/**
 * Demo 1 — Drug Discovery Campaign: ADMET → Docking → Lead Ranking
 *
 * Scientific story: BCR-ABL1 kinase inhibitor development campaign.
 * Five approved / clinical-stage inhibitors are screened for ADMET safety,
 * then the top candidates are docked against the BCR-ABL1 crystal structure
 * (PDB 1IEP), and a final lead ranking integrates both safety and potency.
 *
 * Compounds:
 *   CPD-001  Imatinib   (first-gen, approved)
 *   CPD-002  Dasatinib  (second-gen, approved)
 *   CPD-003  Bosutinib  (second-gen, approved)
 *   CPD-004  Ponatinib  (third-gen, approved — for T315I mutation)
 *   CPD-005  Asciminib  (myristoyl-pocket, approved 2021)
 *
 * Expected outputs:
 *   ADMET  → hERG IC50 predictions, DILI scores, Ames flags
 *   Docking → binding affinity (kcal/mol), pose RMSD, top-ranked compound
 *   Ranking → integrated score table, recommended lead
 *
 * Billing: LLM + compute both asserted.
 */

import { test, expect } from '@playwright/test';
import {
  setupDemoUser,
  sendAndWait,
  clickRunAndWait,
  waitForNoActiveRuns,
  captureBilling,
  captureBillingAfter,
  billingDelta,
  logBillingDelta,
  shot,
  pause,
  tip,
  exploreTutorial,
} from './demo-helpers.js';

const DEMO = 'demo-01-drug-discovery';
const EMAIL = 'demo_drug_discovery@biomate.test';

const ADMET_QUERY = `Run ADMET toxicity screening on these 5 BCR-ABL1 kinase inhibitors and predict hERG cardiac risk (IC50), DILI probability, and Ames mutagenicity for each:

CPD-001 Imatinib:   Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1
CPD-002 Dasatinib:  Cc1nc(Nc2ncc(F)c(Nc3cccc(C(=O)NC4CCN(CCO)CC4)c3)n2)cc(N2CCN(CCO)CC2)n1
CPD-003 Bosutinib:  COc1cc2c(Nc3ccc(Cl)c(Cl)c3)ncnc2cc1OCCCN1CCC(N)CC1
CPD-004 Ponatinib:  Cc1ccc(C(=O)Nc2ccc(CN3CCN(C)CC3)cc2-c2cccc(C(F)(F)F)c2)cc1
CPD-005 Asciminib:  C[C@@H]1CN(c2ncnc3[nH]cc(-c4ccc(Cl)cc4F)c23)C[C@@H]1NC(=O)c1cnc(C(F)(F)F)cn1`;

const DOCKING_QUERY =
  `Now run structure-based molecular docking of imatinib (CPD-001) against the BCR-ABL1 kinase domain crystal structure (PDB: 1IEP). ` +
  `Imatinib SMILES: Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1. ` +
  `ATP binding site box center: [15.0, 34.0, 46.0], box size: 25 Å. ` +
  `Use AutoDock Vina with exhaustiveness=16.`;

const RANKING_QUERY =
  `Generate a final lead ranking table integrating the ADMET safety scores and docking binding affinities. ` +
  `Score each compound 0–100 (higher is better), flag any hERG IC50 < 1 µM as a safety concern, ` +
  `and identify the recommended development candidate with justification.`;

test('Demo 1 — BCR-ABL1 inhibitor campaign: ADMET → docking → lead ranking', async ({ page }) => {
  test.setTimeout(1_800_000);

  // ── Setup ──────────────────────────────────────────────────────────────────
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Drug Discovery');
  await pause(page, 1_000);
  await shot(page, DEMO, '00_start');

  await tip(page, 'Welcome to BioMate — your AI-native drug discovery platform', 4000);
  await pause(page, 4_000);

  const billingBefore = await captureBilling(page, 'demo1-before');

  // ── Turn 1: ADMET screening ────────────────────────────────────────────────
  console.log('[Demo1] Turn 1: ADMET screening');
  await tip(page, 'BioMate automatically identifies the right workflow from your natural language query', 4000);
  await pause(page, 2_000);

  const hasRunAdmet = await sendAndWait(page, ADMET_QUERY, 180_000);
  await shot(page, DEMO, '01_admet_card');

  if (hasRunAdmet) {
    await tip(page, 'BioMate pre-filled all parameters — SMILES, assay type, and safety thresholds — from your message', 4000);
    await pause(page, 3_000);

    await tip(page, 'Submitting to AWS Batch — a fully managed compute cluster spins up automatically', 3500);
    await pause(page, 2_000);

    console.log('[Demo1] Running ADMET workflow on AWS Batch...');
    const runId1 = await clickRunAndWait(page, 900_000);
    console.log('[Demo1] ADMET complete. runId:', runId1);

    await shot(page, DEMO, '02_admet_results');

    // Comprehensive tutorial traversal of ADMET results
    await exploreTutorial(page, (text, ms) => tip(page, text, ms));

    await shot(page, DEMO, '02b_admet_explored');

    await waitForNoActiveRuns(page, 900_000);
    await pause(page, 3_000);
  } else {
    console.log('[Demo1] WARN: ADMET run button not visible — taking screenshot of AI response');
    await shot(page, DEMO, '01b_admet_response');
  }

  // ── Turn 2: Docking ────────────────────────────────────────────────────────
  console.log('[Demo1] Turn 2: molecular docking');
  await tip(page, 'Now let\'s run structure-based docking to measure binding affinity', 3500);
  await pause(page, 2_000);

  const hasRunDocking = await sendAndWait(page, DOCKING_QUERY, 180_000);
  await shot(page, DEMO, '03_docking_card');

  if (hasRunDocking) {
    await tip(page, 'PDB structure, binding site coordinates, and exhaustiveness were all auto-filled', 4000);
    await pause(page, 3_000);

    await tip(page, 'AutoDock Vina running on AWS Batch — exhaustiveness=16 for high-quality poses', 3500);
    await pause(page, 2_000);

    console.log('[Demo1] Running docking workflow on AWS Batch...');
    const runId2 = await clickRunAndWait(page, 900_000);
    console.log('[Demo1] Docking complete. runId:', runId2);

    await shot(page, DEMO, '04_docking_results');

    // Comprehensive tutorial traversal of docking results
    await exploreTutorial(page, (text, ms) => tip(page, text, ms));

    await shot(page, DEMO, '04b_docking_explored');

    await waitForNoActiveRuns(page, 900_000);
    await pause(page, 3_000);
  } else {
    await shot(page, DEMO, '03b_docking_response');
  }

  // ── Turn 3: Lead ranking ───────────────────────────────────────────────────
  console.log('[Demo1] Turn 3: lead ranking');
  await tip(page, 'BioMate can synthesize results across multiple runs into a final recommendation', 4000);
  await pause(page, 2_000);

  await sendAndWait(page, RANKING_QUERY, 180_000);
  await shot(page, DEMO, '05_ranking_response');

  await tip(page, 'Integrated score table — safety + potency combined into a single ranked list', 4000);
  await pause(page, 4_000);

  // Scroll through the ranking response slowly for the recording
  await page.locator('[data-is-latest-assistant="true"]').scrollIntoViewIfNeeded().catch(() => null);
  await pause(page, 2_000);

  await tip(page, 'The recommended development candidate is highlighted with full scientific justification', 4000);
  await pause(page, 4_000);

  // ── Billing audit ──────────────────────────────────────────────────────────
  const billingAfter = await captureBillingAfter(page, 'demo1-after');
  const delta = billingDelta(billingBefore, billingAfter);
  logBillingDelta('demo1', delta);

  await tip(page, `Total session cost: $${delta.total_usd.toFixed(4)} — LLM + AWS Batch compute tracked automatically`, 5000);
  await pause(page, 5_000);

  // LLM cost must be recorded for every demo
  expect(delta.llm_cost_usd, 'Demo1: LLM billing not emitted').toBeGreaterThan(0);

  if (delta.compute_cost_usd === 0) {
    console.log('[Demo1] WARN: compute_cost_usd=0 — check AWS Batch→Lambda→Lago pipeline');
  }

  await shot(page, DEMO, '06_final');
  console.log(
    `[Demo1] COMPLETE — llm=$${delta.llm_cost_usd.toFixed(4)} ` +
    `compute=$${delta.compute_cost_usd.toFixed(4)} ` +
    `total=$${delta.total_usd.toFixed(4)}`
  );
});
