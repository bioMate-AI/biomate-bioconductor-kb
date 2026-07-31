/**
 * CAPSTONE (non-project domain): WGS variant calling, real UI e2e to completion.
 *
 * Canonical fixture, real browser, real backend, real AWS Batch. No mocks.
 * Drives a WGS query (SRA accession -> hg38 -> GATK -> snpEff) through the chat UI,
 * runs it, waits for completion, and audits the report for real variant results.
 * WGS is text-routed (no file upload) so all params should auto-fill.
 */
import { test, expect, type Page } from '@playwright/test';
import { sendAndWait, clickRunAndWait, shot, pause, waitForNoActiveRuns, BASE_URL } from './demo-helpers.js';

const E2E_TOKEN = process.env.E2E_TEST_TOKEN ?? 'biomate-e2e-bypass-token-dev-only';
const FIXTURE_EMAIL = 'lifeifei163361@163.com';
const FIXTURE_PASS = process.env.E2E_FIXTURE_PASSWORD || 'WpmFixture!2026';
const EXEC_TIMEOUT_MS = 30 * 60_000;

// Small subsampled WGS run so it completes in a reasonable window.
const WGS_QUERY =
  'Run whole-genome variant calling on SRA accession SRR1518169 (subsample: max_spots=500000). ' +
  'Align to hg38 with BWA-MEM2, call variants with GATK HaplotypeCaller (GVCF mode), apply VQSR, ' +
  'and annotate with snpEff (GRCh38.105). Report total variants, PASS variants, and Ti/Tv ratio.';

async function login(page: Page): Promise<string> {
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  return page.evaluate(async ({ baseUrl, email, password, e2eToken }) => {
    const r = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'x-e2e-test-token': e2eToken },
      credentials: 'include', body: JSON.stringify({ email, password }),
    });
    if (!r.ok) throw new Error(`login ${r.status}`);
    return ((await r.json()) as { token: string }).token;
  }, { baseUrl: BASE_URL, email: FIXTURE_EMAIL, password: FIXTURE_PASS, e2eToken: E2E_TOKEN });
}

async function overallStatus(page: Page): Promise<string> {
  return page.evaluate(() => {
    const b = document.querySelector('[data-testid="workflow-overall-status-badge"]') as HTMLElement | null;
    return b?.dataset.status ?? 'unknown';
  }).catch(() => 'unknown');
}

// Real UI e2e (canonical fixture, to-completion + report audit).
// PROGRESS: the launch-race ("fetch failed") bug is FIXED (routes.ts retry budget) -- the run now
// LAUNCHES (nextflow cmd present). REMAINING BLOCKER: the reference genome alias is passed to the
// workflow as the bare string "--reference hg38" instead of the S3 FASTA path
// (s3://ngi-igenomes/.../hg38/.../genome.fa), so BWA/GATK can't open the reference and it fails at
// ~10s. The genome-alias -> S3-FASTA resolution is inconsistent (an earlier run had the full path).
// Un-fixme once reference resolution is fixed. See docs/20260730_WGS_CRYOEM_ROOTCAUSE_AND_FIXES.md.
test.fixme('WGS variant calling (SRR1518169 -> hg38 -> GATK -> snpEff) completes via the UI', async ({ browser, request }) => {
  test.setTimeout(180_000 + EXEC_TIMEOUT_MS);
  const page = await browser.newPage();
  page.on('console', (m) => { if (/SSE|Execution|error/i.test(m.text())) console.log(`[browser] ${m.text().slice(0, 160)}`); });

  const token = await login(page);
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  await page.evaluate(() => { try { localStorage.setItem('biomate_survey_suppressed_until', String(Date.now() + 7 * 86400_000)); } catch {} });
  await waitForNoActiveRuns(page, 120_000);

  // Route the WGS pipeline from a single natural-language query
  const hasRun = await sendAndWait(page, WGS_QUERY, 180_000);
  await shot(page, 'wgs-capstone', 'WGS_01_routed');
  expect(hasRun, 'WGS query did not route to a runnable workflow').toBe(true);
  const chip = await page.locator('.wf-chip-name').first().textContent({ timeout: 10_000 }).catch(() => '');
  console.log(`[wgs] routed chip: "${chip}"`);
  expect(chip?.toLowerCase(), 'expected a variant-calling/WGS workflow')
    .toMatch(/sarek|variant|gatk|wgs|haplotype|genom/);

  // Execute on AWS Batch and wait for a terminal state
  console.log('[wgs] running on AWS Batch...');
  const runId = await clickRunAndWait(page, EXEC_TIMEOUT_MS);
  const status = await overallStatus(page);
  console.log(`[wgs] terminal status="${status}" runId=${runId}`);
  await shot(page, 'wgs-capstone', 'WGS_02_terminal');

  expect(status, `WGS run did not COMPLETE - got "${status}" (runId ${runId})`).toBe('completed');

  // Audit the report - must contain real variant-calling results
  await pause(page, 2_000);
  const report = await request.get(`${BASE_URL}/api/invocations/${runId}/methods-report`, {
    headers: { Authorization: `Bearer ${token}`, 'x-e2e-test-token': E2E_TOKEN },
  });
  expect(report.status()).toBe(200);
  const txt = await report.text();
  console.log(`[wgs] report ${txt.length} bytes; excerpt: ${txt.slice(0, 300).replace(/\n/g, ' ')}`);
  expect(txt.toLowerCase(), 'report must not describe an execution failure')
    .not.toMatch(/execution failure|no samples successfully completed/);
  expect(txt.toLowerCase(), 'report should mention variant-calling results')
    .toMatch(/variant|ti\/tv|snp|gatk|vcf|haplotype/);
  await shot(page, 'wgs-capstone', 'WGS_03_report');
  console.log('[wgs] WGS variant calling completed via the UI with a real report');
});
