/**
 * Demo T03 — In Vivo Base Editing (VERVE-102 / PCSK9)
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

const DEMO = 'demo-T03-verve-base-edit';
const EMAIL = 'demo_verve@biomate.test';

const QUERY = `Design an in vivo base edit for PCSK9 loss-of-function for hypercholesterolemia, the same kind of program Verve Therapeutics is running with VERVE-102.`;

test('Demo T03 — In vivo base edit: PCSK9 (VERVE-102)', async ({ page }) => {
  test.setTimeout(900_000);

  // Beat 1: Intro
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Gene Editing');
  await pause(page, 1000);
  await shot(page, DEMO, '00_start');

  await tip(
    page,
    'VERVE-102 dosed first patient Q4 2024 — most-watched gene editing trial in the world. PCSK9 knockout via in vivo base editing. Can BioMate reach Verve\'s design?',
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
    'BioMate extracted gene=PCSK9, edit_goal=loss_of_function, and routed to in_vivo_base_edit_design at confidence 164.',
    4500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '03_panel_review');

  await tip(
    page,
    'Five phases queued: tissue restriction → editor class → delivery → guide RNA → IND-readiness checklist.',
    4500
  );
  await pause(page, 4000);
  await shot(page, DEMO, '04_phases_queued');

  // Beat 4: Click Run
  await tip(page, 'Submitting to AWS Batch.', 3000);
  await pause(page, 1500);
  const runId = await clickRunOnly(page);
  console.log('[DemoT03] Submitted. runId:', runId);
  await pause(page, 2000);
  await shot(page, DEMO, '05_submitted');

  // Beat 5: Narrate execution
  await tip(
    page,
    'Atlas check: PCSK9 is hepatocyte-restricted — ideal LNP IV target.',
    5000
  );
  await pause(page, 30_000);
  await shot(page, DEMO, '06_atlas_check');

  await tip(
    page,
    'Editor: CBE (cytosine base editor). Premature stop via CAA→TAA at codon W8 — exactly what VERVE-101 used.',
    6000
  );
  await pause(page, 35_000);
  await shot(page, DEMO, '07_editor_selected');

  await tip(
    page,
    'CMC flag emitted: "VERVE-101 LFT elevation Nov 2023 — optimize LNP for lower hepatotoxicity." Exactly the VERVE-102 reformulation.',
    6500
  );
  await pause(page, 25_000);
  await shot(page, DEMO, '08_cmc_flag');

  await waitForNoActiveRuns(page, 240_000);
  await pause(page, 4000);
  await shot(page, DEMO, '09_complete');

  // Beat 6: Closing
  await tip(
    page,
    'Same workflow recovers Beam BEAM-101 (sickle cell, ABE, ex vivo HSC) and Verve VERVE-201 (ANGPTL3).',
    5500
  );
  await pause(page, 5000);
  await shot(page, DEMO, '10_closing');
});
