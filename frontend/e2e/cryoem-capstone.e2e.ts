/**
 * CAPSTONE (non-project domain): Cryo-EM single-particle analysis, real UI e2e.
 *
 * Canonical fixture, real browser, real backend, real CryoSPARC GPU execution.
 * No mocks. Drives the curated EMPIAR apoferritin query through the chat UI
 * (pre-staged data + configured CryoSPARC instance), runs the SPA pipeline, waits
 * for completion, and audits the report for a real 3D reconstruction / resolution.
 */
import { test, expect, type Page } from '@playwright/test';
import { sendAndWait, clickRunAndWait, shot, pause, waitForNoActiveRuns, BASE_URL } from './demo-helpers.js';

const E2E_TOKEN = process.env.E2E_TEST_TOKEN ?? 'biomate-e2e-bypass-token-dev-only';
const FIXTURE_EMAIL = 'lifeifei163361@163.com';
const FIXTURE_PASS = process.env.E2E_FIXTURE_PASSWORD || 'WpmFixture!2026';
const EXEC_TIMEOUT_MS = 30 * 60_000; // GPU SPA pipeline

const CRYO_QUERY = 'Run CryoSPARC standard single-particle analysis on the EMPIAR-10025 apoferritin dataset - CTF estimation, particle picking, 2D classification, ab-initio, and refinement. Report the final resolution.';

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

// Real UI e2e (canonical fixture, to-completion + report audit). Routing works ("CryoSPARC
// Standard SPA"); execution BLOCKED BY INFRA -- the CryoSPARC GPU host 52.42.49.175:30000 is
// down/unreachable (port closed). Un-fixme when the GPU instance is up. See
// docs/20260730_WGS_CRYOEM_UI_E2E_FINDINGS.md.
test.fixme('Cryo-EM SPA on EMPIAR apoferritin completes via the UI', async ({ browser, request }) => {
  test.setTimeout(180_000 + EXEC_TIMEOUT_MS);
  const page = await browser.newPage();
  page.on('console', (m) => { if (/SSE|Execution|error/i.test(m.text())) console.log(`[browser] ${m.text().slice(0, 160)}`); });

  const token = await login(page);
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  await page.evaluate(() => { try { localStorage.setItem('biomate_survey_suppressed_until', String(Date.now() + 7 * 86400_000)); } catch {} });
  await waitForNoActiveRuns(page, 120_000);

  const hasRun = await sendAndWait(page, CRYO_QUERY, 180_000);
  await shot(page, 'cryoem-capstone', 'CRYO_01_routed');
  expect(hasRun, 'Cryo-EM query did not route to a runnable workflow').toBe(true);
  const chip = await page.locator('.wf-chip-name').first().textContent({ timeout: 10_000 }).catch(() => '');
  console.log(`[cryo] routed chip: "${chip}"`);
  expect(chip?.toLowerCase(), 'expected a cryosparc/cryo-em SPA workflow')
    .toMatch(/cryosparc|cryo.?em|spa|particle|micrograph/);

  console.log('[cryo] running on CryoSPARC GPU...');
  const runId = await clickRunAndWait(page, EXEC_TIMEOUT_MS);
  const status = await overallStatus(page);
  console.log(`[cryo] terminal status="${status}" runId=${runId}`);
  await shot(page, 'cryoem-capstone', 'CRYO_02_terminal');

  expect(status, `Cryo-EM run did not COMPLETE - got "${status}" (runId ${runId})`).toBe('completed');

  await pause(page, 2_000);
  const report = await request.get(`${BASE_URL}/api/invocations/${runId}/methods-report`, {
    headers: { Authorization: `Bearer ${token}`, 'x-e2e-test-token': E2E_TOKEN },
  });
  expect(report.status()).toBe(200);
  const txt = await report.text();
  console.log(`[cryo] report ${txt.length} bytes; excerpt: ${txt.slice(0, 300).replace(/\n/g, ' ')}`);
  expect(txt.toLowerCase(), 'report must not describe an execution failure')
    .not.toMatch(/execution failure|no samples successfully completed/);
  expect(txt.toLowerCase(), 'report should mention SPA/reconstruction results')
    .toMatch(/resolution|reconstruction|refinement|angstrom|particle|3d|map/);
  await shot(page, 'cryoem-capstone', 'CRYO_03_report');
  console.log('[cryo] Cryo-EM SPA completed via the UI with a real report');
});
