/**
 * Demo 6 — Drug Discovery CRO Compliance
 *
 * Scientific story: regulatory-track EGFR inhibitor campaign.
 * A medicinal chemist starts a new optimization campaign for EGFR T790M
 * (osimertinib-resistant NSCLC) in BioMate's CRO compliance suite.
 * The demo walks through every surface:
 *
 *   1. Campaign creation via the 3-step wizard
 *   2. PBPK model validation report with EMA criterion badge
 *   3. 21 CFR Part 11 audit trail — chain-linked SHA-256 records
 *   4. Auto-retrain loop status + Bayesian proposal
 *   5. IND assembly — CTD §2.6.1 Nonclinical Overview
 *   6. eSig — TOTP enrollment + sign an action
 *
 * No AWS Batch required — all surfaces use fast in-process APIs.
 * Total recording time ≈ 3 min.
 */

import { test, expect } from '@playwright/test';
import {
  setupDemoUser,
  shot,
  pause,
  tip,
  BASE_URL,
} from './demo-helpers.js';

const DEMO = 'demo-06-cro-compliance';
const EMAIL = 'demo_cro_compliance@biomate.test';

// ── Helpers ────────────────────────────────────────────────────────────────────

async function apiCall(
  page: import('@playwright/test').Page,
  method: string,
  path: string,
  body?: object
): Promise<{ status: number; body: any }> {
  return page.evaluate(
    async ({ baseUrl, method, path, body }) => {
      const opts: RequestInit = {
        method,
        credentials: 'include' as RequestCredentials,
        headers: { 'Content-Type': 'application/json' },
      };
      if (body) opts.body = JSON.stringify(body);
      const res = await fetch(`${baseUrl}${path}`, opts);
      return { status: res.status, body: await res.json().catch(() => null) };
    },
    { baseUrl: BASE_URL, method, path, body }
  );
}

// ── Test ───────────────────────────────────────────────────────────────────────

test('Demo 6 — CRO Compliance: Campaign → Validation → Audit → IND → eSig', async ({ page }) => {
  test.setTimeout(600_000); // 10-min ceiling

  // ─── 0. Login then go directly to CRO page ───────────────────────────────
  // setupDemoUser authenticates in-browser (no chat platform detour needed).
  // We navigate to /drug-discovery-cro immediately after auth so the entire
  // recording is on the CRO compliance surfaces.
  console.log('[Demo6] Step 0: Login + navigate directly to CRO page');
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Drug Discovery');
  await page.goto(`${BASE_URL}/drug-discovery-cro`);
  await page.waitForLoadState('load');
  await pause(page, 3_000); // let campaign creation + UI settle

  await shot(page, DEMO, '00_cro_page');
  await tip(page, 'BioMate CRO Compliance Suite — regulatory-grade drug discovery for computational CROs', 4500);
  await pause(page, 4_500);

  // ─── 1. Confirm page loaded ────────────────────────────────────────────────
  console.log('[Demo6] Step 1: CRO compliance page loaded');
  await shot(page, DEMO, '01_cro_page_loaded');
  console.log('[Demo6] CRO demo page loaded');

  // ─── 2. Campaign Wizard (if visible) ──────────────────────────────────────
  // The page pre-creates a campaign and opens on the Validation tab.
  // Show that a campaign badge is present.
  const campaignBadge = page.locator('text=cmp-demo-egfr').first();
  const hasBadge = await campaignBadge.isVisible({ timeout: 8_000 }).catch(() => false);
  console.log('[Demo6] Campaign badge visible:', hasBadge);
  await shot(page, DEMO, '02_campaign_badge');

  // ─── 3. Validation Tab ────────────────────────────────────────────────────
  console.log('[Demo6] Step 3: Validation Panel');
  await tip(page, 'Validation tab — PBPK model meets EMA 2-fold criterion: ≥67% of compounds within 2× of observed Cmax and AUC', 5000);
  const validationTab = page.locator('button', { hasText: 'Validation' }).first();
  if (await validationTab.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await validationTab.click();
    await pause(page, 3_000);
  }
  await shot(page, DEMO, '03_validation_tab');
  await pause(page, 2_000);

  // ─── 4. Audit Trail Tab ───────────────────────────────────────────────────
  console.log('[Demo6] Step 4: Audit Trail');
  await tip(page, 'Audit trail — every computation is logged with SHA-256 chain links, timestamps, and user attribution (21 CFR Part 11)', 5000);
  const auditTab = page.locator('button', { hasText: 'Audit' }).first();
  if (await auditTab.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await auditTab.click();
    await pause(page, 3_000);
  }
  await shot(page, DEMO, '04_audit_tab');
  await pause(page, 2_000);

  // ─── 5. Auto-Retrain Tab ──────────────────────────────────────────────────
  console.log('[Demo6] Step 5: Auto-Retrain Loop');
  await tip(page, 'Auto-retrain — BioMate monitors model drift and triggers Bayesian re-fitting when new assay data arrives', 5000);
  const retrainTab = page.locator('button', { hasText: /retrain|auto/i }).first();
  if (await retrainTab.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await retrainTab.click();
    await pause(page, 3_000);
  }
  await shot(page, DEMO, '05_retrain_tab');

  // ─── 6. IND Assembly Tab ──────────────────────────────────────────────────
  console.log('[Demo6] Step 6: IND Assembly');
  await tip(page, 'IND Assembly — BioMate auto-generates the CTD §2.6.1 Nonclinical Overview from your campaign data', 5000);
  const indTab = page.locator('button', { hasText: /^IND$/ }).first();
  if (await indTab.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await indTab.click();
    await pause(page, 1_500);
  }

  // Fill the form
  const molInput = page.locator('[data-testid="ind-mol-input"]').first();
  if (await molInput.isVisible({ timeout: 4_000 }).catch(() => false)) {
    await molInput.fill('ERB-001');
    await pause(page, 300);
  }
  const targetInput = page.locator('[data-testid="ind-target-input"]').first();
  if (await targetInput.isVisible({ timeout: 2_000 }).catch(() => false)) {
    await targetInput.fill('EGFR T790M');
    await pause(page, 300);
  }
  const indicationInput = page.locator('[data-testid="ind-indication-input"]').first();
  if (await indicationInput.isVisible({ timeout: 2_000 }).catch(() => false)) {
    await indicationInput.fill('NSCLC — 2nd line after erlotinib failure');
    await pause(page, 300);
  }
  const sponsorInput = page.locator('[data-testid="ind-sponsor-input"]').first();
  if (await sponsorInput.isVisible({ timeout: 2_000 }).catch(() => false)) {
    await sponsorInput.fill('BioMate Technologies');
    await pause(page, 300);
  }

  await shot(page, DEMO, '06a_ind_form_filled');

  // Click Generate
  const generateBtn = page.locator('[data-testid="ind-generate-button"]').first();
  if (await generateBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
    await generateBtn.click();
    console.log('[Demo6] Generating IND package...');
    // Wait for result (download buttons appear)
    await page.locator('[data-testid="ind-download-md-button"]').first()
      .waitFor({ state: 'visible', timeout: 30_000 })
      .catch(() => null);
    await pause(page, 2_000);
  }

  await shot(page, DEMO, '06b_ind_generated');

  // ─── 7. eSig Status via API ───────────────────────────────────────────────
  console.log('[Demo6] Step 7: eSig status');
  await tip(page, 'Electronic Signature — TOTP-based eSig for every regulatory action, fully 21 CFR Part 11 compliant', 5000);
  await pause(page, 3_000);
  const esigStatus = await apiCall(page, 'GET', `/api/drug-discovery/esig/status?user_id=${EMAIL}`);
  console.log('[Demo6] eSig enrolled:', esigStatus.body?.enrolled);

  // If not enrolled, enroll now
  if (!esigStatus.body?.enrolled) {
    const enroll = await apiCall(page, 'POST', `/api/drug-discovery/esig/enroll?user_id=${EMAIL}`);
    console.log('[Demo6] eSig enroll status:', enroll.status, '| has QR URI:', !!enroll.body?.qr_uri);
    await shot(page, DEMO, '07a_esig_enrolled');
  }

  await shot(page, DEMO, '07_esig_status');

  // ─── 8. Final overview ────────────────────────────────────────────────────
  console.log('[Demo6] Step 8: Show validation tab with EMA badge');
  const valTab2 = page.locator('button', { hasText: 'Validation' }).first();
  if (await valTab2.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await valTab2.click();
    await pause(page, 3_000);
  }
  await shot(page, DEMO, '08_validation_final');

  // ─── 9. Summary API calls ─────────────────────────────────────────────────
  console.log('[Demo6] Verifying all APIs are live...');

  // Read campaign ID from data attribute set by the demo page
  const cid = await page.locator('[data-testid="demo-campaign-id"]')
    .getAttribute('data-campaign-id')
    .catch(() => null) ?? 'cmp-demo-egfr';

  console.log('[Demo6] Campaign ID:', cid);

  const apis = await Promise.all([
    apiCall(page, 'GET', '/api/drug-discovery/model-validation/pbpk'),
    apiCall(page, 'GET', `/api/drug-discovery/audit?resource_id=${cid}&limit=5`),
    apiCall(page, 'GET', `/api/drug-discovery/${cid}/retrain/status`),
    apiCall(page, 'GET', `/api/drug-discovery/audit/verify`),
  ]);

  console.log(
    '[Demo6] APIs:',
    `pbpk=${apis[0].status}`,
    `audit=${apis[1].status} (${apis[1].body?.total ?? 0} records)`,
    `retrain=${apis[2].status}`,
    `audit/verify=${apis[3].status}`
  );

  expect(apis[0].status).toBe(200); // PBPK validation
  expect(apis[1].status).toBe(200); // Audit log query (returns empty list for fresh campaign)
  expect(apis[2].status).toBe(200); // Retrain status
  expect(apis[3].status).toBe(200); // Audit chain verify

  await shot(page, DEMO, '09_done');
  console.log('[Demo6] ✅ All surfaces demonstrated successfully');
});
