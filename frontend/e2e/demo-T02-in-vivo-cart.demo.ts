/**
 * Demo T02 — In Vivo CAR-T Co-Design (Capstan / Kelonia / Umoja story)
 *
 * Strategy: live-record full duration (~5-6 min); EDIT to ~3:00 in post.
 * Mid-execution tips narrate the AWS Batch run; post-production trims gaps.
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

const DEMO = 'demo-T02-in-vivo-cart';
const EMAIL = 'demo_invivo_cart@biomate.test';

const QUERY = `Design an in vivo CAR-T for CD19 using an anti-CD8 LNP for B-cell lymphoma. Check fratricide risk between the CAR target and the LNP delivery vehicle, and emit the full CAR construct sequence.`;

test('Demo T02 — In vivo CAR-T: CD19 + anti-CD8 LNP', async ({ page }) => {
  test.setTimeout(900_000);

  // Beat 1: Intro
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Cell Therapy');
  await pause(page, 1000);
  await shot(page, DEMO, '00_start');

  await tip(
    page,
    'Capstan, Umoja, Kelonia raised $400M+ to skip ex vivo CAR-T manufacturing. The hard part is multi-modality co-design: LNP × target × fratricide.',
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
    'BioMate extracted CAR target, LNP, and indication; routed to in_vivo_cart_codesign at confidence 144.',
    4500
  );
  await pause(page, 4500);
  await shot(page, DEMO, '03_panel_review');

  await tip(
    page,
    'Four phases queued: atlas safety → LNP tropism → fratricide check → CAR construct assembly.',
    4500
  );
  await pause(page, 4000);
  await shot(page, DEMO, '04_phases_queued');

  // Beat 4: Click Run
  await tip(page, 'Submitting to AWS Batch.', 3000);
  await pause(page, 1500);
  const runId = await clickRunOnly(page);
  console.log('[DemoT02] Submitted. runId:', runId);
  await pause(page, 2000);
  await shot(page, DEMO, '05_submitted');

  // Beat 5: Narrate execution
  await tip(
    page,
    'Phase 1 launched: atlas check on CD19. B-cell restricted, no critical tissue hits — VIABLE.',
    5500
  );
  await pause(page, 30_000);
  await shot(page, DEMO, '06_phase_running');

  await tip(
    page,
    'Phase 3 is the trap. LNP anti-CD5 transfects T cells. CD19 is on B cells. No overlap → no fratricide.',
    6000
  );
  await pause(page, 35_000);
  await shot(page, DEMO, '07_fratricide_check');

  await tip(
    page,
    'CAR construct emitted as FASTA — FMC63 + CD8α + CD28 + CD3ζ. Kymriah architecture, 1485 AA.',
    5500
  );
  await pause(page, 25_000);
  await shot(page, DEMO, '08_construct_emitted');

  await waitForNoActiveRuns(page, 240_000);
  await pause(page, 4000);
  await shot(page, DEMO, '09_complete');

  // Beat 6: Closing
  await tip(
    page,
    'Switch CAR target to CD7 and the same workflow fires a fratricide warning automatically.',
    5500
  );
  await pause(page, 5000);
  await shot(page, DEMO, '10_closing');
});
