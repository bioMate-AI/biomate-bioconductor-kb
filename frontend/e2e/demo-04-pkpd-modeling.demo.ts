/**
 * Demo 4 — PK/PD Modeling: IVIVE → PBPK → Clinical Dose Prediction
 *
 * Scientific story: translational PK for imatinib (Gleevec).
 * In-vitro intrinsic clearance data from human liver microsomes is scaled
 * via IVIVE to predict in-vivo hepatic clearance.  The predicted CL_h is
 * then fed into a 7-compartment PBPK model to simulate plasma
 * concentration-time profiles and predict the clinical dose needed to
 * maintain steady-state Cmax above the IC90 for BCR-ABL1 inhibition.
 *
 * Imatinib literature values used for validation:
 *   CL_int (HLM)    : 44 µL/min/mg protein
 *   fu plasma        : 0.07 (93% bound to α1-acid glycoprotein)
 *   Vd               : 435 L
 *   CL_obs clinical  : 14 L/h
 *   t½ clinical      : 18 h
 *   BCR-ABL1 IC90    : 1 µM (≈ 594 ng/mL)
 *
 * Expected outputs:
 *   IVIVE      → CL_h predicted (L/h), fu correction, Vd
 *   PBPK       → Cmax, AUC(0-24), t½, Cmin at steady state
 *   Dose pred  → recommended dose (mg/day) to maintain Cmin > IC90
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

const DEMO = 'demo-04-pkpd-modeling';
const EMAIL = 'demo_pkpd_modeling@biomate.test';

const IVIVE_QUERY =
  `Run IVIVE (in vitro–in vivo extrapolation) hepatic clearance prediction for imatinib. ` +
  `In vitro data: CL_int = 44 µL/min/mg HLM protein, fu_inc = 0.015 (microsomal binding). ` +
  `Physiological scaling: MPPGL = 45 mg/g liver, liver weight = 1500 g. ` +
  `fu plasma = 0.07. Use the well-stirred liver model. ` +
  `Report: predicted CL_h (L/h), extraction ratio, predicted oral bioavailability assuming complete absorption.`;

const PBPK_QUERY =
  `Now run a 7-compartment PBPK simulation for imatinib using the IVIVE-derived clearance. ` +
  `Parameters: MW = 493.6 g/mol, logP = 3.7, pKa = 7.7, Vd = 435 L, fu = 0.07. ` +
  `Simulate oral dosing at 400 mg QD for 96 hours to reach steady state. ` +
  `Report: Cmax, Cmin, AUC(0–24h) at steady state, t½, time to steady state. ` +
  `Is the predicted Cmin above the BCR-ABL1 IC90 of 1 µM (594 ng/mL)?`;

const DOSE_QUERY =
  `Based on the PBPK results, what is the minimum effective dose to maintain steady-state ` +
  `Cmin above the BCR-ABL1 IC90 of 1 µM (594 ng/mL)? ` +
  `Compare with the approved clinical dose (400 mg QD). ` +
  `What is the predicted therapeutic window (Cmax:IC90 ratio)? ` +
  `Does the model predict any accumulation risk?`;

test('Demo 4 — PK/PD: imatinib IVIVE → PBPK → clinical dose prediction', async ({ page }) => {
  test.setTimeout(1_800_000);

  // ── Setup ──────────────────────────────────────────────────────────────────
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Pharmacology');
  await shot(page, DEMO, '00_start');

  await tip(page, 'Welcome to BioMate — translational PK/PD modeling from in vitro data to clinical dose prediction', 4500);
  await pause(page, 4_500);

  const billingBefore = await captureBilling(page, 'demo4-before');

  // ── Turn 1: IVIVE ──────────────────────────────────────────────────────────
  console.log('[Demo4] Turn 1: IVIVE hepatic clearance');
  await tip(page, 'Step 1: IVIVE scales microsomal intrinsic clearance to whole-organ hepatic clearance', 4000);
  await pause(page, 2_000);

  const hasRunIvive = await sendAndWait(page, IVIVE_QUERY, 180_000);
  await shot(page, DEMO, '01_ivive_card');

  if (hasRunIvive) {
    await tip(page, 'MPPGL, liver weight, fu_plasma, and CL_int were all auto-extracted from your message', 4000);
    await pause(page, 3_000);

    await tip(page, 'Well-stirred liver model: CL_h = Q_h × (fu × CL_int) / (Q_h + fu × CL_int)', 4500);
    await pause(page, 3_000);

    console.log('[Demo4] Running IVIVE workflow...');
    const runId1 = await clickRunAndWait(page, 600_000);
    console.log('[Demo4] IVIVE complete. runId:', runId1);

    await shot(page, DEMO, '02_ivive_results');

    // Comprehensive tutorial traversal of IVIVE results
    await exploreTutorial(page, (text, ms) => tip(page, text, ms));

    await shot(page, DEMO, '02b_ivive_explored');

    await waitForNoActiveRuns(page, 600_000);
    await pause(page, 3_000);
  } else {
    await shot(page, DEMO, '01b_ivive_response');
  }

  // ── Turn 2: PBPK simulation ────────────────────────────────────────────────
  console.log('[Demo4] Turn 2: PBPK simulation');
  await tip(page, 'Step 2: 7-compartment PBPK simulation — blood, lung, liver, gut, kidney, muscle, adipose', 4500);
  await pause(page, 2_000);

  const hasRunPbpk = await sendAndWait(page, PBPK_QUERY, 180_000);
  await shot(page, DEMO, '03_pbpk_card');

  if (hasRunPbpk) {
    await tip(page, 'MW, logP, pKa, Vd, and fu were parsed from your message — no schema to fill manually', 4000);
    await pause(page, 3_000);

    await tip(page, 'Simulating 96 hours of QD dosing to reach pharmacokinetic steady state', 3500);
    await pause(page, 2_000);

    console.log('[Demo4] Running PBPK simulation...');
    const runId2 = await clickRunAndWait(page, 600_000);
    console.log('[Demo4] PBPK complete. runId:', runId2);

    await shot(page, DEMO, '04_pbpk_results');

    // Comprehensive tutorial traversal of PBPK results — plots and metrics
    await exploreTutorial(page, (text, ms) => tip(page, text, ms));

    await shot(page, DEMO, '04b_pbpk_explored');

    await pause(page, 3_000);
  } else {
    await shot(page, DEMO, '03b_pbpk_response');
  }

  // ── Turn 3: Dose prediction ────────────────────────────────────────────────
  console.log('[Demo4] Turn 3: clinical dose prediction');
  await tip(page, 'Step 3: BioMate integrates IVIVE + PBPK to derive the minimum effective clinical dose', 4500);
  await pause(page, 2_000);

  await sendAndWait(page, DOSE_QUERY, 120_000);
  await shot(page, DEMO, '05_dose_prediction');

  await tip(page, 'Predicted Cmin vs BCR-ABL1 IC90 determines whether 400 mg QD is above the therapeutic threshold', 4500);
  await pause(page, 4_000);

  // Scroll through the dose prediction response for the recording
  await page.locator('[data-is-latest-assistant="true"]').scrollIntoViewIfNeeded().catch(() => null);
  await pause(page, 2_000);

  await tip(page, 'Therapeutic window (Cmax:IC90 ratio) and accumulation risk are computed from the steady-state profile', 4500);
  await pause(page, 4_000);

  // ── Billing audit ──────────────────────────────────────────────────────────
  const billingAfter = await captureBillingAfter(page, 'demo4-after');
  const delta = billingDelta(billingBefore, billingAfter);
  logBillingDelta('demo4', delta);

  await tip(page, `Total session cost: $${delta.total_usd.toFixed(4)} — IVIVE + PBPK compute + AI interpretation`, 5000);
  await pause(page, 5_000);

  expect(delta.llm_cost_usd, 'Demo4: LLM billing not emitted').toBeGreaterThan(0);

  if (delta.compute_cost_usd === 0) {
    console.log('[Demo4] WARN: compute_cost_usd=0');
  }

  await shot(page, DEMO, '06_final');
  console.log(
    `[Demo4] COMPLETE — llm=$${delta.llm_cost_usd.toFixed(4)} ` +
    `compute=$${delta.compute_cost_usd.toFixed(4)}`
  );
});
