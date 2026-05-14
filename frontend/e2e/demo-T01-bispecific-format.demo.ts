/**
 * Demo T01 — Bispecific Format Triage (Ivonescimab / HARMONi-2 story)
 *
 * Strategy: live-record full duration (~5-6 min); EDIT to ~3:00 in post.
 * Tips fire on a timer during the AWS Batch wait so the editor has anchor
 * points to keep at full speed; the gaps between tips get trimmed.
 *
 * Six narrative beats (matches docs/20260513_tier0_demo_narratives_v2.md):
 *   1. Intro / industry hook
 *   2. Type query → AI routes (real chat-stream)
 *   3. Workflow panel review + extracted params
 *   4. Click Run
 *   5. Narrate AWS execution (cold start → scoring → output → completion)
 *   6. Closing one-liner
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

const DEMO = 'demo-T01-bispecific-format';
const EMAIL = 'demo_bispecific@biomate.test';

const QUERY = `Design a PD-1 × VEGF bispecific antibody in CrossMab format for non-small cell lung cancer. Score every major bispecific format and explain which architecture fits the biology — same question Akeso/Summit answered for ivonescimab.`;

test('Demo T01 — Bispecific format: PD-1 × VEGF (Ivonescimab)', async ({ page }) => {
  test.setTimeout(900_000);

  // ── Beat 1: Intro (target 12s) ─────────────────────────────────────────────
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Bispecific Design');
  await pause(page, 1000);
  await shot(page, DEMO, '00_start');

  await tip(
    page,
    'October 2024 — Ivonescimab (PD-1 × VEGF CrossMab) beat Keytruda in HARMONi-2. Watch BioMate recover that format choice from inputs alone.',
    6000
  );
  await pause(page, 5000);
  await shot(page, DEMO, '01_intro');

  // ── Beat 2: Query + AI routing (target ~35s, real LLM time) ───────────────
  await sendAndWait(page, QUERY, 180_000);
  await shot(page, DEMO, '02_workflow_ready');

  // ── Beat 3: Workflow panel review (target ~25s) ────────────────────────────
  await tip(
    page,
    'BioMate extracted PD-1, VEGF, and NSCLC; routed to bispecific_format_triage at confidence 124.',
    4500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '03_panel_review');

  await tip(
    page,
    'Five formats queued: BiTE, CrossMab, KiH, DVD-Ig, nanobody fusion — scored on six axes.',
    4500
  );
  await pause(page, 4000);
  await shot(page, DEMO, '04_phases_queued');

  // ── Beat 4: Click Run (target ~10s) ────────────────────────────────────────
  await tip(page, 'Click Run — workflow dispatches to AWS Batch.', 3500);
  await pause(page, 1500);
  const runId = await clickRunOnly(page);
  console.log('[DemoT01] Submitted. runId:', runId);
  await pause(page, 2000);
  await shot(page, DEMO, '05_submitted');

  // ── Beat 5: Narrate AWS execution (live ~2:30, post-edited to ~1:00) ──────
  // The wait varies (cold-start 30-60s, container pull 30-60s, exec ~5-30s,
  // S3 upload ~10s). Fire tips on a timer; post-edit trims the gaps.

  await tip(
    page,
    'Phase 1 launched. AWS Batch worker spinning up, pulling the biomni-tools container from ECR.',
    5000
  );
  await pause(page, 30_000);
  await shot(page, DEMO, '06_phase_running');

  await tip(
    page,
    'Inside the container: 5 formats scored on 6 axes — half-life, cis engagement, trans engagement, manufacturing, ADA risk, affinity asymmetry.',
    6000
  );
  await pause(page, 35_000);
  await shot(page, DEMO, '07_scoring');

  await tip(
    page,
    'First output landed: format ranking complete. CrossMab #1 (score 100, 67%) — matching Ivonescimab.',
    5500
  );
  await pause(page, 25_000);
  await shot(page, DEMO, '08_output_landed');

  // Now wait for actual completion (whatever's left). This gap is what
  // post-production primarily trims.
  console.log('[DemoT01] Waiting for completion...');
  await waitForNoActiveRuns(page, 240_000);
  await pause(page, 4000);
  await shot(page, DEMO, '09_complete');

  // ── Beat 6: Closing (target ~15s) ──────────────────────────────────────────
  await tip(
    page,
    '30 seconds of orchestration. Same architectural answer Akeso reached over 18 months of design work.',
    5500
  );
  await pause(page, 5000);
  await shot(page, DEMO, '10_closing');
});
