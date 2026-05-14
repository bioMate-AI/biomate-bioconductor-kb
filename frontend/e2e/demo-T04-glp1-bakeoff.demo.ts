/**
 * Demo T04 — GLP-1 Modality Bake-Off (Tirzepatide / Retatrutide story)
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

const DEMO = 'demo-T04-glp1-bakeoff';
const EMAIL = 'demo_glp1@biomate.test';

const QUERY = `What is the best GLP-1 modality for MASH? Compare semaglutide-class, tirzepatide-class, retatrutide triple-agonist, and oral orforglipron — score each on receptor pharmacology and indication fit.`;

test('Demo T04 — GLP-1 modality bake-off for MASH', async ({ page }) => {
  test.setTimeout(900_000);

  // Beat 1: Intro
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Metabolic Disease');
  await pause(page, 1000);
  await shot(page, DEMO, '00_start');

  await tip(
    page,
    'GLP-1 is the trillion-dollar drug class of the decade. Every pharma is asking "what\'s the next GLP-1?" The answer is indication-aware.',
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
    'BioMate extracted disease=MASH and the four candidate modalities; routed to glp1_modality_bakeoff at confidence 130.',
    4500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '03_panel_review');

  await tip(
    page,
    'Workflow scores six modalities across three receptors — GLP1R, GIPR, GCGR — weighted by indication.',
    4500
  );
  await pause(page, 4000);
  await shot(page, DEMO, '04_phases_queued');

  // Beat 4: Click Run
  await tip(page, 'Submitting to AWS Batch.', 3000);
  await pause(page, 1500);
  const runId = await clickRunOnly(page);
  console.log('[DemoT04] Submitted. runId:', runId);
  await pause(page, 2000);
  await shot(page, DEMO, '05_submitted');

  // Beat 5: Narrate execution
  await tip(
    page,
    'Pulling atlas expression for all three GLP-1 family receptors. GCGR is hepatocyte-dominant — that matters for MASH.',
    6000
  );
  await pause(page, 30_000);
  await shot(page, DEMO, '06_atlas_pull');

  await tip(
    page,
    'For MASH, GCGR adds hepatic fat oxidation — therapeutic. For T2D, it would be a liability — hyperglycemia.',
    6000
  );
  await pause(page, 35_000);
  await shot(page, DEMO, '07_scoring');

  await tip(
    page,
    'Top recommendation: retatrutide-class triple agonist. Receptor pattern GLP1R + GIPR + GCGR.',
    5500
  );
  await pause(page, 25_000);
  await shot(page, DEMO, '08_top_modality');

  await waitForNoActiveRuns(page, 240_000);
  await pause(page, 4000);
  await shot(page, DEMO, '09_complete');

  // Beat 6: Closing
  await tip(
    page,
    'Tirzepatide for obesity. Retatrutide for MASH. Orforglipron for cost. All in one bake-off.',
    5500
  );
  await pause(page, 5000);
  await shot(page, DEMO, '10_closing');
});
