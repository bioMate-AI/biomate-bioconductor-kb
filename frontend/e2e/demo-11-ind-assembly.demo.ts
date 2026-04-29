/**
 * Demo 11 — IND §2.6.1 Assembly with AI Regulatory Prose
 *
 * Scientific story: a computational CRO uses BioMate to generate the
 * CTD §2.6.1 Nonclinical Overview section for an EGFR inhibitor IND
 * submission. The LLM (Gemini 3 Flash) writes FDA-style regulatory prose
 * for each sub-section — PBPK qualification, ADMET screening, compound
 * prioritization, and applicability domain.
 *
 * Surfaces demonstrated:
 *   1. CRO compliance page — IND tab
 *   2. Form fill — molecule, target, indication, sponsor
 *   3. Generate IND Package — POST /api/drug-discovery/{cid}/ind-assembly
 *   4. Result panel — 6 sections, LLM narrative visible, Markdown + DOCX
 *   5. Markdown preview — FDA regulatory prose in §2.6.1.1 and §2.6.1.2
 *   6. Download endpoint — GET /ind-assembly/download?format=md
 *
 * No AWS Batch required — entirely in-process.
 * Total recording time ≈ 2 min.
 */

import { test, expect } from '@playwright/test';
import {
  setupDemoUser,
  shot,
  pause,
  tip,
  BASE_URL,
} from './demo-helpers.js';

const DEMO  = 'demo-11-ind-assembly';
const EMAIL = 'demo_ind_assembly@biomate.test';

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

test('Demo 11 — IND §2.6.1 Assembly with AI Regulatory Prose', async ({ page }) => {
  test.setTimeout(300_000); // 5-min ceiling

  // ─── 0. Auth + ensure campaign exists + navigate to CRO page ────────────────
  console.log('[Demo11] Step 0: Login + ensure campaign + CRO page');
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Drug Discovery');

  // Pre-create the campaign so the CRO page has something to open
  const CAMPAIGN_ID = 'cmp-ind-demo-egfr';
  await page.evaluate(
    async ({ baseUrl, cid, userId }) => {
      await fetch(`${baseUrl}/api/drug-discovery/campaigns`, {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          campaign_id:   cid,
          user_id:       userId,
          molecule_name: 'ERB-001',
          target:        'EGFR T790M',
          indication:    'NSCLC — 2nd line',
          sponsor:       'BioMate Technologies',
          objective:     'balance',
        }),
      });
    },
    { baseUrl: BASE_URL, cid: CAMPAIGN_ID, userId: EMAIL }
  );

  await page.goto(`${BASE_URL}/drug-discovery-cro`);
  await page.waitForLoadState('load');
  await pause(page, 2_000);

  // Click the campaign row to open the workspace
  const campaignRow = page.locator('[data-testid="campaign-row"]').first();
  if (await campaignRow.isVisible({ timeout: 10_000 }).catch(() => false)) {
    await campaignRow.click();
    await pause(page, 1_500);
  }
  await page.waitForSelector('[data-testid="demo-campaign-id"]', { timeout: 20_000 });

  await shot(page, DEMO, '00_cro_loaded');
  await tip(page, 'BioMate CRO Compliance Suite — generating IND §2.6.1 with FDA-style AI regulatory prose', 5000);
  await pause(page, 5_000);

  // ─── 1. Open IND tab ─────────────────────────────────────────────────────────
  console.log('[Demo11] Step 1: IND tab');
  const indTab = page.locator('button', { hasText: /^IND$/ }).first();
  if (await indTab.isVisible({ timeout: 8_000 }).catch(() => false)) {
    await indTab.click();
    await pause(page, 1_500);
  }
  await shot(page, DEMO, '01_ind_tab_open');
  await tip(page, 'IND Assembly tab — fill campaign details and generate the full CTD §2.6.1 Nonclinical Overview', 4500);
  await pause(page, 4_500);

  // ─── 2. Fill the form ────────────────────────────────────────────────────────
  console.log('[Demo11] Step 2: Fill form');
  const molInput = page.locator('[data-testid="ind-mol-input"]').first();
  if (await molInput.isVisible({ timeout: 4_000 }).catch(() => false)) {
    await molInput.click({ clickCount: 3 });
    await molInput.fill('ERB-001');
    await pause(page, 400);
  }
  const targetInput = page.locator('[data-testid="ind-target-input"]').first();
  if (await targetInput.isVisible({ timeout: 2_000 }).catch(() => false)) {
    await targetInput.triple_click?.() ?? await targetInput.click({ clickCount: 3 });
    await targetInput.fill('EGFR T790M');
    await pause(page, 400);
  }
  const indicationInput = page.locator('[data-testid="ind-indication-input"]').first();
  if (await indicationInput.isVisible({ timeout: 2_000 }).catch(() => false)) {
    await indicationInput.triple_click?.() ?? await indicationInput.click({ clickCount: 3 });
    await indicationInput.fill('NSCLC — 2nd line after erlotinib failure');
    await pause(page, 400);
  }
  const sponsorInput = page.locator('[data-testid="ind-sponsor-input"]').first();
  if (await sponsorInput.isVisible({ timeout: 2_000 }).catch(() => false)) {
    await sponsorInput.triple_click?.() ?? await sponsorInput.click({ clickCount: 3 });
    await sponsorInput.fill('BioMate Technologies');
    await pause(page, 400);
  }

  await shot(page, DEMO, '02_form_filled');
  await tip(page, 'Molecule, target, indication, sponsor — BioMate pulls the rest from campaign data (PBPK metrics, ADMET scores, audit records)', 5000);
  await pause(page, 5_000);

  // ─── 3. Generate ────────────────────────────────────────────────────────────
  console.log('[Demo11] Step 3: Generate IND Package');
  await tip(page, 'Generating… Gemini 3 Flash writes 2–4 sentences of FDA regulatory prose for each section', 4000);
  const generateBtn = page.locator('[data-testid="ind-generate-button"]').first();
  if (await generateBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
    await generateBtn.click();
    console.log('[Demo11] Waiting for download button to appear…');
    await page.locator('[data-testid="ind-download-md-button"]').first()
      .waitFor({ state: 'visible', timeout: 60_000 })
      .catch(() => null);
    await pause(page, 2_000);
  }

  await shot(page, DEMO, '03_generated');
  await tip(page, 'IND package ready — 6 sections assembled, PBPK metrics cited, compound rankings included', 5000);
  await pause(page, 5_000);

  // ─── 4. Open markdown preview ───────────────────────────────────────────────
  console.log('[Demo11] Step 4: Markdown preview');
  const previewTrigger = page.locator('text=Markdown Preview').first();
  if (await previewTrigger.isVisible({ timeout: 4_000 }).catch(() => false)) {
    await previewTrigger.click();
    await pause(page, 1_500);
  }
  await shot(page, DEMO, '04_markdown_preview');
  await tip(page, '§2.6.1.1 Overview — AI-generated FDA regulatory prose: "The candidate was identified through the BioMate integrated computational platform…"', 6000);
  await pause(page, 6_000);

  // ─── 5. Verify via API and check narrative quality ───────────────────────────
  console.log('[Demo11] Step 5: API verification');

  const cid = await page.locator('[data-testid="demo-campaign-id"]')
    .getAttribute('data-campaign-id')
    .catch(() => null) ?? 'cmp-demo-egfr';

  const assembleResult = await apiCall(page, 'POST', `/api/drug-discovery/${cid}/ind-assembly`, {
    molecule_name: 'ERB-001',
    target_name:   'EGFR T790M',
    indication:    'NSCLC — 2nd line after erlotinib failure',
    sponsor:       'BioMate Technologies',
  });

  console.log(`[Demo11] Assemble: ${assembleResult.status}`);
  expect(assembleResult.status).toBe(200);

  const r = assembleResult.body;
  const fullMd: string = r.markdown_content ?? '';
  console.log(`[Demo11] Full document: ${fullMd.length} chars`);
  console.log(`[Demo11] Sections: ${r.sections?.join(', ')}`);
  console.log(`[Demo11] Pandoc: ${r.pandoc_available} | DOCX: ${r.docx_generated}`);

  // Verify all 8 section headings present (§2.6.1 sub-sections + §2.6.2 + §2.6.3)
  expect(r.sections?.length, 'all 8 sections').toBeGreaterThanOrEqual(8);
  for (const sec of ['2.6.1.1', '2.6.1.2', '2.6.1.3', '2.6.1.4', '2.6.1.5', '2.6.1.6', '2.6.2', '2.6.3']) {
    expect(fullMd, `heading ${sec} in document`).toContain(sec);
  }

  // §2.6.2 and §2.6.3 content quality checks
  expect(fullMd, '§2.6.2 Pharmacokinetics section present').toContain('Pharmacokinetics');
  expect(fullMd, '§2.6.3 Toxicology section present').toContain('Toxicology');

  // Narrative quality check — §2.6.1.1 and §2.6.1.2 must have real prose
  const overviewMatch = fullMd.match(/## 2\.6\.1\.1.*?\n\n(.*?)(?=\n##|\n\n###)/s);
  const narrative261_1 = overviewMatch?.[1]?.trim() ?? '';
  console.log(`[Demo11] §2.6.1.1 narrative (first 200): ${narrative261_1.slice(0, 200)}`);
  expect(narrative261_1.length, '§2.6.1.1 narrative non-empty').toBeGreaterThan(50);

  // Download endpoint
  const dlResult = await page.evaluate(
    async ({ baseUrl, cid }) => {
      const res = await fetch(
        `${baseUrl}/api/drug-discovery/${cid}/ind-assembly/download?format=md`,
        { credentials: 'include' }
      );
      const text = await res.text();
      return { status: res.status, length: text.length, preview: text.slice(0, 120) };
    },
    { baseUrl: BASE_URL, cid }
  );
  console.log(`[Demo11] Download: ${dlResult.status} | ${dlResult.length} chars`);
  console.log(`[Demo11] Download preview: ${dlResult.preview}`);
  expect(dlResult.status, 'download 200').toBe(200);
  expect(dlResult.length, 'download non-empty').toBeGreaterThan(1000);

  await shot(page, DEMO, '05_api_verified');
  await tip(page, `Full document: ${fullMd.length} chars · §2.6.1.1–§2.6.1.6 · ${r.pandoc_available ? 'MD + DOCX' : 'MD only'} · ready for IND filing`, 6000);
  await pause(page, 6_000);

  // ─── 6. Final shot — show download buttons on current page ─────────────────
  console.log('[Demo11] Step 6: Download buttons');

  await shot(page, DEMO, '06_ind_tab_final');
  await tip(page, 'IND Assembly complete — download the CTD §2.6.1 package to attach to your FDA IND submission', 5000);
  await pause(page, 5_000);

  await shot(page, DEMO, 'done');
  console.log('[Demo11] ✅ Complete');
});
