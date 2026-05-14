/**
 * Demo T02 — In Vivo CAR-T Co-Design (Capstan / fratricide story)
 *
 * Scientific story: Capstan ($165M), Umoja ($122M), Kelonia ($115M) raised $400M+
 * to skip ex vivo CAR-T manufacturing ($400-500K/patient → $5-50K). The design
 * problem is multi-modality: LNP tropism × CAR target × fratricide. Only BioMate
 * chains all three in one query.
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

const DEMO = 'demo-T02-in-vivo-cart';
const EMAIL = 'demo_invivo_cart@biomate.test';

const QUERY = `Design an in vivo CAR-T for CD19 using an anti-CD8 LNP for B-cell lymphoma. Check fratricide risk between the CAR target and the LNP delivery vehicle, and emit the full CAR construct sequence.`;

test('Demo T02 — In vivo CAR-T: CD19 + anti-CD8 LNP (Capstan pattern)', async ({ page }) => {
  test.setTimeout(900_000);

  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Cell Therapy');
  await pause(page, 1500);
  await shot(page, DEMO, '00_start');

  await tip(
    page,
    'Capstan, Umoja, and Kelonia raised $400M+ to skip ex vivo CAR-T manufacturing. The hard part is multi-modality co-design.',
    7000
  );
  await pause(page, 4500);
  await shot(page, DEMO, '01_intro_tip');

  await tip(
    page,
    'LNP tropism × CAR target × fratricide. Get any one wrong and the program dies. Watch all three resolve in one query.',
    6500
  );
  await pause(page, 4500);

  // ── Type query, AI routes ──────────────────────────────────────────────────
  await sendAndWait(page, QUERY, 180_000);
  await shot(page, DEMO, '02_workflow_ready');

  await tip(
    page,
    'BioMate extracted CAR target, LNP, and indication. Routed to in_vivo_cart_codesign at confidence 144.',
    5500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '03_extracted_params');

  // ── Review parameters ──────────────────────────────────────────────────────
  await tip(
    page,
    'Phase 1: atlas safety on CD19 (B-cell restricted, clean). Phase 2: LNP tropism. Phase 3: fratricide check. Phase 4: CAR construct.',
    7000
  );
  await pause(page, 5000);
  await shot(page, DEMO, '04_phases');

  // ── Execute ────────────────────────────────────────────────────────────────
  await tip(page, 'Submitting to AWS Batch — the full multi-modality chain runs in 4 minutes.', 4500);
  await pause(page, 2000);
  const runId = await clickRunAndWait(page, 600_000);
  console.log('[DemoT02] Run complete. runId:', runId);
  await shot(page, DEMO, '05_run_complete');

  await waitForNoActiveRuns(page, 600_000);
  await pause(page, 5000);

  // ── Show outputs ───────────────────────────────────────────────────────────
  await tip(
    page,
    'Fratricide check: anti-CD8 LNP transfects T cells; CD19 is on B cells; no overlap → GO.',
    6500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '06_fratricide_check');

  await tip(
    page,
    'CAR construct emitted as FASTA: FMC63 scFv + CD8α hinge + CD28 costim + CD3ζ — Kymriah pattern, 1485 AA.',
    7000
  );
  await pause(page, 5000);
  await shot(page, DEMO, '07_cart_construct');

  // ── Closing ────────────────────────────────────────────────────────────────
  await tip(
    page,
    'Switch the CAR target to CD7 and the same workflow correctly fires a fratricide warning — automatically.',
    7000
  );
  await pause(page, 5000);
  await shot(page, DEMO, '08_closing');
});
