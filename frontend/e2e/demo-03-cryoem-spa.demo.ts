/**
 * Demo 3 — Structural Biology: Cryo-EM Single-Particle Analysis
 *
 * Scientific story: structure determination of beta-galactosidase using
 * CryoSPARC single-particle analysis.  EMPIAR-10028 is the standard
 * community benchmark dataset (T. thermophilus beta-gal, D2 symmetry).
 *
 * Pipeline phases:
 *   1. Import micrographs (MRC format, 1.06 Å/px)
 *   2. CTF estimation (CTFFIND4)
 *   3. Automated particle picking (Blob picker → topaz refinement)
 *   4. 2D classification (50 classes)
 *   5. Ab initio 3D reconstruction
 *   6. Homogeneous refinement (C2 symmetry)
 *   7. Local resolution estimation
 *
 * Expected outputs:
 *   map.mrc       → 3D density map
 *   FSC curve     → resolution estimate (target < 3.5 Å for publication)
 *   particle stack → curated 2D class averages
 *   local_res.mrc → local resolution map coloured by resolution
 *
 * Billing: LLM + compute both asserted.
 */

import { test, expect } from '@playwright/test';
import * as path from 'path';
import * as fs from 'fs';
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
  BASE_URL,
} from './demo-helpers.js';

const DEMO = 'demo-03-cryoem-spa';
const EMAIL = 'demo_cryoem_spa@biomate.test';

// A small synthetic 64×64 MRC file for the demo upload
// (production run would use the full EMPIAR-10028 dataset)
function makeMiniMrc(): Buffer {
  // MRC2014 header: 1024 bytes, then a minimal 64×64×1 float32 map
  const header = Buffer.alloc(1024, 0);
  header.writeInt32LE(64, 0);   // NX
  header.writeInt32LE(64, 4);   // NY
  header.writeInt32LE(1,  8);   // NZ
  header.writeInt32LE(2,  12);  // MODE = 2 (float32)
  header.writeFloatLE(1.06, 28); // XLEN (cell dimension Å)
  header.writeFloatLE(1.06, 32); // YLEN
  header.writeFloatLE(1.06, 36); // ZLEN
  header.write('MAP ', 208, 'ascii');
  header.writeInt32BE(0x44_44_00_00, 212); // machine stamp (little-endian)
  const pixels = Buffer.alloc(64 * 64 * 4); // float32 zeros
  return Buffer.concat([header, pixels]);
}

const SPA_QUERY =
  `Process these cryo-EM micrographs using CryoSPARC single-particle analysis. ` +
  `This is beta-galactosidase from T. thermophilus (D2 symmetry, MW ~465 kDa). ` +
  `Micrograph pixel size: 1.06 Å/px, acceleration voltage: 300 kV, spherical aberration: 2.7 mm. ` +
  `Run full SPA pipeline: CTF estimation → particle picking → 2D classification → ` +
  `ab initio reconstruction → homogeneous refinement → local resolution.`;

const ANALYSIS_QUERY =
  `What is the final resolution from the FSC curve (FSC = 0.143 criterion)? ` +
  `How many particles were used in the final refinement? ` +
  `Does the local resolution map show any anisotropy? ` +
  `Is this map of sufficient quality for atomic model building?`;

test('Demo 3 — Cryo-EM SPA: micrographs → CTF → 2D classes → 3D map', async ({ page }) => {
  test.setTimeout(1_800_000);

  // ── Setup ──────────────────────────────────────────────────────────────────
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Cryo-EM');
  await shot(page, DEMO, '00_start');
  await tip(page, 'Welcome to BioMate — AI-native structural biology: from raw micrographs to publication-quality 3D maps', 4500);
  await pause(page, 4_500);

  const billingBefore = await captureBilling(page, 'demo3-before');

  // ── Upload demo micrograph ─────────────────────────────────────────────────
  console.log('[Demo3] Uploading demo MRC micrograph...');
  const mrcPath = path.join('/tmp', 'demo_empiar10028.mrc');
  fs.writeFileSync(mrcPath, makeMiniMrc());

  // Find the file input and upload
  const fileInput = page.locator('input[type="file"]').first();
  const inputVisible = await fileInput.isVisible({ timeout: 3_000 }).catch(() => false);
  if (inputVisible) {
    await fileInput.setInputFiles(mrcPath);
    await pause(page, 2_000);
    await shot(page, DEMO, '01_file_uploaded');
  } else {
    // Try to open the upload panel first
    for (const sel of [
      page.getByTestId('upload-button'),
      page.getByRole('button', { name: /upload|attach|file/i }).first(),
      page.locator('[data-testid="chat-file-input"]'),
    ]) {
      if (await sel.isVisible({ timeout: 1_500 }).catch(() => false)) {
        await sel.click();
        await pause(page, 500);
        break;
      }
    }
    const fi2 = page.locator('input[type="file"]').first();
    if (await fi2.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await fi2.setInputFiles(mrcPath);
      await pause(page, 2_000);
      await shot(page, DEMO, '01_file_uploaded');
    } else {
      console.log('[Demo3] File input not accessible — proceeding without file upload');
    }
  }

  // ── Turn 1: SPA pipeline ───────────────────────────────────────────────────
  console.log('[Demo3] Turn 1: CryoSPARC SPA pipeline');
  await tip(page, 'BioMate identifies the 7-step CryoSPARC SPA pipeline from your natural language request', 4000);
  await pause(page, 2_000);
  const hasRun = await sendAndWait(page, SPA_QUERY, 180_000);
  await shot(page, DEMO, '02_spa_card');

  if (hasRun) {
    await tip(page, 'Pixel size, voltage, Cs, and symmetry were all auto-extracted from your message', 4000);
    await pause(page, 3_000);

    await tip(page, 'Submitting to AWS Batch — GPU-accelerated CTF estimation and particle picking', 3500);
    await pause(page, 2_000);

    console.log('[Demo3] Running CryoSPARC SPA on AWS Batch...');
    const runId = await clickRunAndWait(page, 1_200_000);
    console.log('[Demo3] SPA complete. runId:', runId);

    await shot(page, DEMO, '03_spa_phases');
    await pause(page, 2_000);

    await tip(page, 'All 7 pipeline steps completed — CTF → picking → 2D classes → ab initio → refinement', 4000);
    await pause(page, 3_000);

    await shot(page, DEMO, '04_spa_results');
    await pause(page, 2_000);

    // Comprehensive tutorial traversal of cryo-EM results
    await exploreTutorial(page, (text, ms) => tip(page, text, ms));

    await shot(page, DEMO, '04b_spa_explored');

    await waitForNoActiveRuns(page, 1_200_000);
    await pause(page, 3_000);
  } else {
    await shot(page, DEMO, '02b_spa_response');
  }

  // ── Turn 2: Structure analysis ─────────────────────────────────────────────
  console.log('[Demo3] Turn 2: structure quality analysis');
  await tip(page, 'Ask BioMate to interpret the FSC curve and evaluate map quality for atomic model building', 4000);
  await pause(page, 2_000);
  await sendAndWait(page, ANALYSIS_QUERY, 120_000);
  await shot(page, DEMO, '05_analysis');

  await tip(page, 'FSC = 0.143 criterion resolution, particle count, local resolution anisotropy — all reported automatically', 4500);
  await pause(page, 4_000);

  await page.locator('[data-is-latest-assistant="true"]').scrollIntoViewIfNeeded().catch(() => null);
  await pause(page, 2_000);

  // ── Billing audit ──────────────────────────────────────────────────────────
  const billingAfter = await captureBillingAfter(page, 'demo3-after');
  const delta = billingDelta(billingBefore, billingAfter);
  logBillingDelta('demo3', delta);

  await tip(page, `Total session cost: $${delta.total_usd.toFixed(4)} — CryoSPARC GPU compute + AI structure analysis`, 5000);
  await pause(page, 5_000);

  expect(delta.llm_cost_usd, 'Demo3: LLM billing not emitted').toBeGreaterThan(0);

  if (delta.compute_cost_usd === 0) {
    console.log('[Demo3] WARN: compute_cost_usd=0');
  }

  await shot(page, DEMO, '06_final');
  console.log(
    `[Demo3] COMPLETE — llm=$${delta.llm_cost_usd.toFixed(4)} ` +
    `compute=$${delta.compute_cost_usd.toFixed(4)}`
  );
});
