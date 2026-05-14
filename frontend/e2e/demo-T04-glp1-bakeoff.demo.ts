/**
 * Demo T04 — GLP-1 Modality Bake-Off (Tirzepatide / Retatrutide story)
 *
 * Scientific story: Trillion-dollar drug class. Every pharma is asking "what's the
 * next GLP-1?" The answer is now indication-aware: tirzepatide for obesity, retatrutide
 * for MASH (GCGR adds hepatic fat oxidation), orforglipron for cost. BioMate's
 * framework triages all candidates across GLP1R / GIPR / GCGR in 30 seconds.
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

const DEMO = 'demo-T04-glp1-bakeoff';
const EMAIL = 'demo_glp1@biomate.test';

const QUERY = `What is the best GLP-1 modality for MASH? Compare semaglutide-class, tirzepatide-class, retatrutide triple-agonist, and oral orforglipron — score each on receptor pharmacology and indication fit.`;

test('Demo T04 — GLP-1 modality bake-off for MASH', async ({ page }) => {
  test.setTimeout(900_000);

  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Metabolic Disease');
  await pause(page, 1500);
  await shot(page, DEMO, '00_start');

  await tip(
    page,
    'GLP-1 is the trillion-dollar drug story of the decade. SELECT, SURMOUNT, SYNERGY-NASH — all in the last 18 months.',
    7000
  );
  await pause(page, 4500);
  await shot(page, DEMO, '01_intro_tip');

  await tip(
    page,
    'Every pharma asks "what\'s the next GLP-1?" The answer depends on indication. Watch BioMate triage across GLP1R / GIPR / GCGR.',
    7000
  );
  await pause(page, 5000);

  // ── Type query ─────────────────────────────────────────────────────────────
  await sendAndWait(page, QUERY, 180_000);
  await shot(page, DEMO, '02_workflow_ready');

  await tip(
    page,
    'Routed to glp1_modality_bakeoff at confidence 130. Extracted disease=MASH and 4 candidate modalities.',
    5500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '03_extracted_params');

  // ── Review parameters ──────────────────────────────────────────────────────
  await tip(
    page,
    'Each receptor has its own atlas profile. GLP1R: gut + pancreas + brain. GIPR: adipose + β-cell. GCGR: hepatocyte.',
    7000
  );
  await pause(page, 5000);
  await shot(page, DEMO, '04_receptors');

  // ── Execute ────────────────────────────────────────────────────────────────
  await tip(page, 'Submitting to AWS Batch.', 3500);
  await pause(page, 1500);
  const runId = await clickRunAndWait(page, 600_000);
  console.log('[DemoT04] Run complete. runId:', runId);
  await shot(page, DEMO, '05_run_complete');

  await waitForNoActiveRuns(page, 600_000);
  await pause(page, 5000);

  // ── Show outputs ───────────────────────────────────────────────────────────
  await tip(
    page,
    'For MASH: triple GLP1R+GIPR+GCGR wins (retatrutide-class). GCGR adds hepatic fat oxidation — exactly the SYNERGY-NASH mechanism.',
    7500
  );
  await pause(page, 5500);
  await shot(page, DEMO, '06_top_recommendation');

  await tip(
    page,
    'Switch indication to T2D and the same workflow downgrades triple agonist — GCGR causes hyperglycemia, anti-mechanism for diabetes.',
    7500
  );
  await pause(page, 5000);
  await shot(page, DEMO, '07_indication_awareness');

  // ── Closing ────────────────────────────────────────────────────────────────
  await tip(
    page,
    'Tirzepatide for obesity. Retatrutide for MASH. Orforglipron for cost. All in one bake-off.',
    7000
  );
  await pause(page, 5000);
  await shot(page, DEMO, '08_closing');
});
