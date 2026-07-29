/**
 * CAPSTONE: a REAL dataset run to SUCCESSFUL completion, through a project.
 *
 * Unlike UC-PW2 (synthetic 2-read FASTQ → intentional failure), this uploads the
 * curated GSE227835 counts matrix (AChR+ myasthenia gravis PBMC, 10 MG vs 10 HC)
 * to a project, routes to nf-core/differentialabundance (DESeq2 on counts — no
 * genome alignment, ~5-10 min), and asserts the run COMPLETES and the report
 * contains real differential-expression results (not a failure abstract).
 *
 * Real browser, real backend, real S3, real AWS Batch. No mocks. Canonical fixture.
 */
import { test, expect, type Page } from '@playwright/test';
import { sendAndWait, clickRunAndWait, shot, pause, waitForNoActiveRuns, BASE_URL } from './demo-helpers.js';

const E2E_TOKEN = process.env.E2E_TEST_TOKEN ?? 'biomate-e2e-bypass-token-dev-only';
const FIXTURE_EMAIL = 'lifeifei163361@163.com';
const FIXTURE_PASS = process.env.E2E_FIXTURE_PASSWORD || 'WpmFixture!2026';
const EXEC_TIMEOUT_MS = 20 * 60_000; // differentialabundance on a small counts matrix

const MG_DIR = `${process.cwd()}/public/demo/mg_demo`;
const MG_FILES = [`${MG_DIR}/counts_matrix.csv`, `${MG_DIR}/sample_metadata.csv`, `${MG_DIR}/contrasts.csv`];

let projectId = '';
let runId: string | null = null;

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

test.describe.serial('project-real-run-capstone', () => {
  // Regression for docs/20260728_PROJECT_MULTIFILE_PARAM_MAPPING_GAP.md: project
  // files were routed with BARE FILENAMES (matrix=counts_matrix.csv) instead of
  // S3 URIs, so AWS Batch couldn't open them and the run failed at launch. Fixed by
  // resolveProjectFileParams() in server/routes.ts (stages project files into the
  // Batch bucket + substitutes the s3:// URI). fixme lifted once verified on dev.
  test('MG counts → differentialabundance → COMPLETED run with real DE results', async ({ browser, request }) => {
    test.setTimeout(90_000 + EXEC_TIMEOUT_MS + 180_000);
    const page = await browser.newPage();
    page.on('console', (m) => { if (/SSE|Execution|error/i.test(m.text())) console.log(`[browser] ${m.text().slice(0, 160)}`); });

    const token = await login(page);

    // Create the project via API
    const create = await request.post(`${BASE_URL}/api/projects`, {
      headers: { Authorization: `Bearer ${token}`, 'x-e2e-test-token': E2E_TOKEN },
      data: { name: `Capstone MG-DE ${Date.now()}`, description: 'real DE capstone', primaryDomain: 'transcriptomics',
        researchGoal: 'Differential expression in AChR+ myasthenia gravis PBMC (GSE227835)' },
    });
    expect(create.ok(), `create project: ${await create.text()}`).toBeTruthy();
    projectId = (await create.json()).project?.id ?? (await create.json()).id;
    console.log(`[cap] project ${projectId}`);

    // Upload the 3 real curated CSVs to the project
    await page.goto(`${BASE_URL}/projects?project=${projectId}&tab=files`);
    await page.getByTestId('project-file-tree').waitFor({ state: 'visible', timeout: 15_000 });
    await page.getByTestId('project-files-input').setInputFiles(MG_FILES);
    await expect(page.locator('text=counts_matrix.csv')).toBeVisible({ timeout: 20_000 });
    await shot(page, 'project-workspace', 'CAP_01_files_uploaded');
    console.log('[cap] 3 MG files uploaded');

    // Analyze → chat pre-fills → append the real scientific context → route
    await page.getByTestId('button-analyze-files').click();
    const input = page.locator('[data-testid="chat-input"], textarea').first();
    await input.waitFor({ state: 'visible', timeout: 12_000 });
    await waitForNoActiveRuns(page, 120_000);
    const prefill = await input.inputValue();
    const msg = prefill +
      '\n\nThese are bulk RNA-seq counts from GSE227835 (AChR+ myasthenia gravis PBMC, 10 MG patients vs 10 healthy controls): ' +
      'counts_matrix.csv, sample_metadata.csv (condition column), contrasts.csv. ' +
      'Run differential expression with nf-core/differentialabundance and report the key differentially expressed genes.';
    const hasRun = await sendAndWait(page, msg, 120_000);
    await shot(page, 'project-workspace', 'CAP_02_routed');
    expect(hasRun, 'LLM did not route to a runnable workflow').toBe(true);
    const chip = await page.locator('.wf-chip-name').first().textContent({ timeout: 10_000 }).catch(() => '');
    console.log(`[cap] routed chip: "${chip}"`);
    expect(chip?.toLowerCase(), 'expected a differential-abundance/expression workflow')
      .toMatch(/differential|abundance|deseq|rnaseq/);

    // Run and wait for a terminal state
    console.log('[cap] running...');
    runId = await clickRunAndWait(page, EXEC_TIMEOUT_MS);
    const status = await overallStatus(page);
    console.log(`[cap] terminal status="${status}" runId=${runId}`);
    await shot(page, 'project-workspace', 'CAP_03_terminal');

    // CAPSTONE assertion: this real dataset must COMPLETE (not fail)
    expect(status, `run did not COMPLETE — got "${status}" (runId ${runId})`).toBe('completed');

    // Audit the report content — must contain real DE results, not a failure abstract
    await pause(page, 2_000);
    const report = await request.get(`${BASE_URL}/api/invocations/${runId}/methods-report`, {
      headers: { Authorization: `Bearer ${token}`, 'x-e2e-test-token': E2E_TOKEN },
    });
    expect(report.status()).toBe(200);
    const txt = await report.text();
    console.log(`[cap] report ${txt.length} bytes; excerpt: ${txt.slice(0, 300).replace(/\n/g, ' ')}`);
    expect(txt.toLowerCase(), 'report must not describe an execution failure')
      .not.toMatch(/execution failure|no samples successfully completed/);
    expect(txt.toLowerCase(), 'report should mention DE results')
      .toMatch(/differential|upregulated|downregulated|deseq|log2|fdr/);
    await shot(page, 'project-workspace', 'CAP_04_after_run');

    // Confirm the run is linked to the project
    const runs = await request.get(`${BASE_URL}/api/projects/${projectId}/workflow-runs`, {
      headers: { Authorization: `Bearer ${token}`, 'x-e2e-test-token': E2E_TOKEN },
    }).catch(() => null);
    if (runs && runs.ok()) console.log(`[cap] project workflow-runs: ${(await runs.text()).slice(0, 120)}`);
    console.log('[cap] ✅ real dataset completed through a project with a real DE report');
  });

  test.afterAll(async ({ request }) => {
    if (!projectId) return;
    // Login into the request context (sets the biomate_token cookie), then delete.
    await request.post(`${BASE_URL}/api/auth/login`, {
      headers: { 'x-e2e-test-token': E2E_TOKEN },
      data: { email: FIXTURE_EMAIL, password: FIXTURE_PASS },
    }).catch(() => {});
    await request.delete(`${BASE_URL}/api/projects/${projectId}`, {
      headers: { 'x-e2e-test-token': E2E_TOKEN },
    }).catch(() => {});
  });
});
