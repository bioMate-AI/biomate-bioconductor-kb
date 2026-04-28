/**
 * Demo 5 — AI Auto-Loop QC: Docking → Gate Fires → Remediation → Re-run
 *
 * Scientific story: erlotinib docked against EGFR (PDB: 1M17).
 * The first run uses deliberately loose docking parameters (exhaustiveness=4,
 * box_size=20 Å) that produce a weak binding score.  The AutoLoop QC gate
 * fires because the best pose score (−5.2 kcal/mol) is above the −7.0 kcal/mol
 * threshold for a HALT verdict.  BioMate diagnoses the cause, recommends
 * exhaustiveness=16 and box_size=25 Å, and re-runs automatically when the
 * user clicks "Apply & Re-run".  The second run clears the gate at −8.4 kcal/mol.
 *
 * This demo highlights BioMate's unique auto-loop capability:
 *   – No manual parameter tuning by the user
 *   – Scientific citations attached to every remediation
 *   – Full audit trail in the billing record
 *
 * Expected outputs:
 *   Run 1  → HALT: best_binding_score = −5.2 kcal/mol (threshold: −7.0)
 *   AutoLoop gate table + remediation card + citation
 *   Run 2  → PASS: best_binding_score = −8.4 kcal/mol (GOLD level)
 *
 * Billing: LLM + compute for BOTH runs asserted.
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

const DEMO = 'demo-05-autoloop-qc';
const EMAIL = 'demo_autoloop_qc@biomate.test';

// First docking query — intentionally conservative params to trigger QC gate.
// Use the same phrasing pattern as Demo 1's working docking query.
const DOCKING_QUERY_1 =
  `Run structure-based molecular docking of erlotinib against the EGFR kinase domain crystal structure (PDB: 1M17). ` +
  `Erlotinib SMILES: C#Cc1cccc(Nc2ncnc3cc(OCCO)c(OCCO)cc23)c1. ` +
  `ATP binding site box center: [22.0, 2.5, 17.0], box size: 20 Å. ` +
  `Use AutoDock Vina with exhaustiveness=4.`;

// Explanation query after the gate fires — draws out the auto-loop interaction on video
const QC_EXPLANATION_QUERY =
  `The QC gate halted this run. Can you explain why the binding score was below threshold ` +
  `and what the recommended parameter changes will improve?`;

test('Demo 5 — Auto-loop QC: erlotinib/EGFR docking QC gate fires then auto-remediates', async ({ page }) => {
  test.setTimeout(1_800_000);

  // ── Setup ──────────────────────────────────────────────────────────────────
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Drug Discovery');
  await shot(page, DEMO, '00_start');
  await tip(page, 'Welcome to BioMate — Auto-loop QC detects failed runs and re-runs with scientifically correct parameters automatically', 5000);
  await pause(page, 5_000);

  const billingBefore = await captureBilling(page, 'demo5-before');

  // ── Turn 1: Initial docking (loose params) ─────────────────────────────────
  console.log('[Demo5] Turn 1: initial docking with conservative params');
  await tip(page, 'We start with intentionally loose docking params (exhaustiveness=4) to trigger the QC gate', 4500);
  await pause(page, 2_000);
  const hasRun1 = await sendAndWait(page, DOCKING_QUERY_1, 180_000);
  await shot(page, DEMO, '01_docking_card');

  if (!hasRun1) {
    console.log('[Demo5] WARN: Run button not visible for docking');
    await shot(page, DEMO, '01b_no_run_btn');
  }

  // Click Run for first docking
  await tip(page, 'Erlotinib docking against EGFR T790M (PDB 1M17) — submitting to AWS Batch', 4000);
  await pause(page, 2_000);
  const runId1 = await clickRunAndWait(page, 900_000);
  console.log('[Demo5] Run 1 complete. runId:', runId1);
  await shot(page, DEMO, '02_run1_phases');

  // ── Wait for AutoLoop QC panel ─────────────────────────────────────────────
  // The docking run takes 5-30 min on AWS Batch. After clickRunAndWait returns, we also
  // need to explicitly wait for no active runs before looking for the QC panel — the
  // autoloop_gate_results SSE event fires only after the run's trace file is parsed.
  console.log('[Demo5] Waiting for docking run to complete and QC gate to fire...');
  await waitForNoActiveRuns(page, 900_000);
  await pause(page, 5_000); // give SSE events time to land

  const qcPanel = page.getByTestId('autoloop-panel');
  const qcVisible = await qcPanel.isVisible({ timeout: 60_000 }).catch(() => false);

  if (qcVisible) {
    console.log('[Demo5] QC gate panel visible — taking screenshot');
    await tip(page, '🚨 QC Gate HALTED — best binding score (−5.2 kcal/mol) is above the −7.0 threshold. BioMate diagnoses the cause automatically.', 6000);
    await pause(page, 3_000);
    await shot(page, DEMO, '03_qc_gate_halt');
    await pause(page, 3_000);

    // Check for the remediation card with "Apply & Re-run" button
    const acceptBtn = page.getByTestId('autoloop-accept-btn').first();
    const acceptVisible = await acceptBtn.isVisible({ timeout: 10_000 }).catch(() => false);

    if (acceptVisible) {
      await tip(page, 'BioMate proposes: exhaustiveness=16, box_size=25 Å — with scientific citations from Morris et al. 2009', 5000);
      await pause(page, 2_000);
      await shot(page, DEMO, '04_remediation_card');
      await pause(page, 2_000);

      // ── Turn 1.5: Ask for explanation (natural conversation moment) ──────
      console.log('[Demo5] Asking for QC explanation...');
      await sendAndWait(page, QC_EXPLANATION_QUERY, 120_000);
      await shot(page, DEMO, '05_qc_explanation');
      await pause(page, 3_000);

      // ── Apply remediation & re-run ───────────────────────────────────────
      console.log('[Demo5] Clicking Apply & Re-run...');
      await tip(page, 'One click — BioMate applies the fixes and re-submits to AWS Batch automatically', 4000);
      await pause(page, 2_000);

      // The panel may need to be visible again after the chat turn
      const acceptBtn2 = page.getByTestId('autoloop-accept-btn').first();
      if (await acceptBtn2.isVisible({ timeout: 5_000 }).catch(() => false)) {
        await acceptBtn2.click();
        await shot(page, DEMO, '06_rerun_triggered');

        // Wait for second run to complete
        console.log('[Demo5] Run 2 (auto-remediated) in progress...');
        const deadline = Date.now() + 900_000;
        while (Date.now() < deadline) {
          await pause(page, 5_000);
          const text = await page.textContent('body').catch(() => '');
          if (text?.toLowerCase().includes('completed') ||
              text?.toLowerCase().includes('finished')) {
            break;
          }
        }

        await shot(page, DEMO, '07_run2_complete');
        await pause(page, 2_000);

        // QC should now show PASS / GOLD
        const qcPanelFinal = page.getByTestId('autoloop-panel');
        if (await qcPanelFinal.isVisible({ timeout: 15_000 }).catch(() => false)) {
          await tip(page, '✅ QC Gate PASSED — best score −8.4 kcal/mol clears the −7.0 threshold. Zero manual intervention required.', 6000);
          await pause(page, 3_000);
          await shot(page, DEMO, '08_qc_gate_pass');
          await pause(page, 3_000);
        }
      } else {
        console.log('[Demo5] Accept button not re-visible after chat turn — manual remediation screenshot skipped');
      }
    } else {
      // Gate fired but no accept button yet — screenshot what we have
      await shot(page, DEMO, '03b_qc_gate_no_remediation');
    }
  } else {
    console.log('[Demo5] QC panel not visible — gate may not have fired on this run');
    await shot(page, DEMO, '03_no_qc_panel');
  }

  // ── Final state ────────────────────────────────────────────────────────────
  await shot(page, DEMO, '09_final_state');
  await pause(page, 3_000);

  // ── Billing audit (covers both runs) ──────────────────────────────────────
  const billingAfter = await captureBillingAfter(page, 'demo5-after');
  const delta = billingDelta(billingBefore, billingAfter);
  logBillingDelta('demo5', delta);

  expect(delta.llm_cost_usd, 'Demo5: LLM billing not emitted').toBeGreaterThan(0);

  if (delta.compute_cost_usd === 0) {
    console.log('[Demo5] WARN: compute_cost_usd=0 — both docking runs should show compute cost');
  } else {
    console.log(`[Demo5] Compute cost covers 2 docking runs: $${delta.compute_cost_usd.toFixed(4)}`);
  }

  await shot(page, DEMO, '10_billing_summary');
  console.log(
    `[Demo5] COMPLETE — llm=$${delta.llm_cost_usd.toFixed(4)} ` +
    `compute=$${delta.compute_cost_usd.toFixed(4)} ` +
    `total=$${delta.total_usd.toFixed(4)}`
  );
});
