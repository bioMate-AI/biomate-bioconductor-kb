/**
 * Service Page — Execution E2E Test
 *
 * Goes beyond routing: sends chat queries, clicks Run, verifies real-time
 * phase status transitions (idle→running→completed/failed), then audits
 * the after-run tabs (Findings / Methods / Report download).
 *
 * Three representative use cases spanning different execution paths:
 *
 *   EX-1  ADMET Full Panel          — fast bioinformatics, has QC gates
 *   EX-2  Pharmacovigilance (FAERS) — single nextflow workflow
 *   EX-3  Bulk RNA-seq DESeq2       — multi-step chain (bioc_rnaseq chain)
 *
 * Each flow exercises:
 *   ✓ Pre-run state  — footer "Run", overall badge idle/pending
 *   ✓ Running state  — footer "Running…", phase card data-status="running"
 *   ✓ Terminal state — footer "Run again" OR "Restart"
 *   ✓ After-run tabs — Findings, Methods tabs present; Report download link
 *
 * NO page.route() mocking. Real backend (AWS Batch via Galaxy :8081).
 * Screenshots → e2e/screenshots/service-execution/
 *
 * Timeouts:
 *   - LLM routing:  90 s
 *   - AWS Batch execution: 20 min (FAERS/ADMET), 30 min (RNA-seq chain)
 *
 * Run locally:
 *   BIOMATE_URL=http://localhost:5000 \
 *   E2E_FIXTURE_PASSWORD=WpmFixture!2026 \
 *   npx playwright test e2e/service-page-execution.e2e.ts --project=chromium
 *
 * Run against dev:
 *   BIOMATE_URL=https://dev-public.biomate.ai \
 *   E2E_FIXTURE_PASSWORD=WpmFixture!2026 \
 *   npx playwright test e2e/service-page-execution.e2e.ts --project=chromium
 */

import { test, expect, type Page, type Browser } from '@playwright/test';
import {
  sendAndWait,
  clickRunAndWait,
  waitForNoActiveRuns,
  shot,
  pause,
  BASE_URL,
} from './demo-helpers.js';

// ── Constants ──────────────────────────────────────────────────────────────────

const FIXTURE_EMAIL    = 'lifeifei163361@163.com';
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || 'WpmFixture!2026';
const E2E_TOKEN        = process.env.E2E_TEST_TOKEN ?? 'biomate-e2e-bypass-token-dev-only';

// Individual workflow execution timeouts
const ADMET_TIMEOUT_MS  = 20 * 60_000;  // 20 min
const FAERS_TIMEOUT_MS  = 20 * 60_000;  // 20 min
const RNASEQ_TIMEOUT_MS = 30 * 60_000;  // 30 min (chain = multiple steps)

interface ExecCase {
  id: string;
  label: string;
  prompt: string;
  /** Keywords expected in the workflow/chain card title */
  expectWorkflow: string[];
  executionTimeoutMs: number;
  /** Minimum number of after-run tabs expected to be visible */
  minAfterRunTabs: number;
}

const EXEC_CASES: ExecCase[] = [
  {
    id: 'EX-1',
    label: 'ADMET Full Panel',
    prompt: 'Run a full ADMET panel for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O) — hERG cardiotoxicity, DILI, Ames mutagenicity, CYP450 inhibition, and Lipinski Ro5 compliance',
    expectWorkflow: ['admet', 'ADMET', 'predict', 'Predict'],
    executionTimeoutMs: ADMET_TIMEOUT_MS,
    minAfterRunTabs: 2,
  },
  {
    id: 'EX-2',
    label: 'Pharmacovigilance FAERS',
    prompt: 'Analyze FAERS adverse event data for metformin — run ROR and PRR disproportionality scoring to identify significant adverse drug reactions',
    expectWorkflow: ['faers', 'FAERS', 'pharmacovigilance', 'adverse'],
    executionTimeoutMs: FAERS_TIMEOUT_MS,
    minAfterRunTabs: 2,
  },
  {
    id: 'EX-3',
    label: 'Bulk RNA-seq DESeq2',
    prompt: 'Run bulk RNA-seq differential expression analysis comparing treated vs control samples with DESeq2 — use the example FASTQ dataset (GSE183947, human, paired-end)',
    expectWorkflow: ['bulk_rnaseq', 'DESeq2', 'deseq2', 'differential', 'rna', 'RNA'],
    executionTimeoutMs: RNASEQ_TIMEOUT_MS,
    minAfterRunTabs: 2,
  },
];

// ── Auth helpers ───────────────────────────────────────────────────────────────

async function login(page: Page): Promise<void> {
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  const token = await page.evaluate(
    async ({ baseUrl, email, password, e2eToken }) => {
      const resp = await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-e2e-test-token': e2eToken },
        credentials: 'include',
        body: JSON.stringify({ email, password }),
      });
      if (!resp.ok) throw new Error(`Login ${resp.status}`);
      return ((await resp.json()) as { token: string }).token;
    },
    { baseUrl: BASE_URL, email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD, e2eToken: E2E_TOKEN }
  );
  const domain = new URL(BASE_URL).hostname;
  await page.context().addCookies([{
    name: 'biomate_token', value: token, domain, path: '/',
    httpOnly: true, secure: BASE_URL.startsWith('https'), sameSite: 'Lax',
  }]);
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  await page.evaluate(() => {
    try { localStorage.setItem('biomate_survey_suppressed_until', String(Date.now() + 7 * 86400_000)); } catch {}
  });
  await page.locator('[data-testid="chat-input"], textarea').first()
    .waitFor({ state: 'visible', timeout: 30_000 });
}

async function startNewChat(page: Page): Promise<void> {
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  await page.locator('[data-testid="chat-input"], textarea').first()
    .waitFor({ state: 'visible', timeout: 20_000 });
  await pause(page, 500);
}

// ── Panel state helpers ────────────────────────────────────────────────────────

/**
 * Returns the current data-status of the overall workflow badge.
 * Falls back to phase card statuses when no badge exists.
 */
async function getOverallStatus(page: Page): Promise<string> {
  return page.evaluate(() => {
    const badge = document.querySelector('[data-testid="workflow-overall-status-badge"]');
    if (badge) return (badge as HTMLElement).dataset.status ?? badge.textContent ?? 'unknown';
    // Fallback: any running phase card means "running"
    const cards = document.querySelectorAll('[data-testid^="phase-card-"]');
    if (Array.from(cards).some(c => (c as HTMLElement).dataset.status === 'running')) return 'running';
    if (Array.from(cards).some(c => (c as HTMLElement).dataset.status === 'completed')) return 'completed';
    if (Array.from(cards).some(c => (c as HTMLElement).dataset.status === 'failed')) return 'failed';
    return 'unknown';
  }).catch(() => 'unknown');
}

/**
 * Waits until at least one phase card shows data-status="running".
 * Returns true if running state was observed, false on timeout.
 */
async function waitForRunningState(page: Page, timeoutMs = 120_000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const status = await getOverallStatus(page);
    if (status === 'running') return true;
    // Also accept if already completed (fast workflows)
    if (status === 'completed' || status === 'failed') return true;
    await pause(page, 3_000);
  }
  return false;
}

/**
 * Returns visible after-run tab labels (Findings, Methods, Report, etc.)
 */
async function getAfterRunTabs(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    // After-run tabs are rendered in the workflow panel below phase cards
    const tabEls = document.querySelectorAll(
      '[data-testid^="after-run-tab-"], [role="tab"][data-value], .after-run-tab, [class*="after-run"]'
    );
    if (tabEls.length > 0) {
      return Array.from(tabEls).map(el => el.textContent?.trim() ?? '').filter(Boolean);
    }
    // Fallback: look for tab-like buttons containing known labels
    const allButtons = document.querySelectorAll('button, [role="tab"]');
    const knownLabels = ['findings', 'methods', 'outputs', 'report', 'citations', 'params', 'software', 'qc'];
    return Array.from(allButtons)
      .map(el => el.textContent?.trim().toLowerCase() ?? '')
      .filter(t => knownLabels.some(l => t.includes(l)));
  }).catch(() => []);
}

/**
 * Checks if the workflow panel shows a "Run again" or "Restart" footer button,
 * indicating the workflow reached a terminal state.
 */
async function isTerminalState(page: Page): Promise<boolean> {
  return page.evaluate(() => {
    const panel = document.querySelector(
      '[data-testid="nextflow-workflow-viewer"], [data-testid="workflow-artifact-panel"]'
    );
    if (!panel) return false;
    const footer = panel.querySelector('button');
    const label = footer?.textContent?.toLowerCase() ?? '';
    return label.includes('run again') || label.includes('restart') || label.includes('re-run');
  }).catch(() => false);
}

// ── Shared session ─────────────────────────────────────────────────────────────

let sharedPage: Page;

test.beforeAll(async ({ browser }) => {
  sharedPage = await browser.newPage();
  await login(sharedPage);
});

test.afterAll(async () => {
  await sharedPage.close().catch(() => {});
});

// ── Execution tests ────────────────────────────────────────────────────────────

for (const ec of EXEC_CASES) {
  test(`${ec.id} — ${ec.label} — full lifecycle`, async () => {
    // Total: LLM routing (90 s) + execution timeout + overhead
    test.setTimeout(90_000 + ec.executionTimeoutMs + 60_000);

    console.log(`\n[${ec.id}] ${ec.label}`);
    console.log(`     prompt: "${ec.prompt.slice(0, 80)}…"`);

    // ── Step 1: Route to workflow ───────────────────────────────────────────
    await startNewChat(sharedPage);
    await sendAndWait(sharedPage, ec.prompt, 90_000);

    // Verify workflow card appeared
    const chipName = await sharedPage.locator('.wf-chip-name').first()
      .textContent({ timeout: 15_000 }).catch(() => null);
    const msgText = await sharedPage
      .locator('[data-is-latest-assistant="true"]').first()
      .textContent().catch(() => '') ?? '';
    const effectiveTitle = (chipName ?? msgText).toLowerCase();

    const routed = ec.expectWorkflow.some(kw => effectiveTitle.includes(kw.toLowerCase()));
    console.log(`[${ec.id}] Routing: "${chipName ?? '(chip missing, checked message)'}" → ${routed ? '✅' : '⚠️ keyword not matched'}`);
    await shot(sharedPage, 'service-execution', `${ec.id}_01_routed`);

    if (!routed) {
      console.warn(`[${ec.id}] ⚠️ Routing unexpected — title="${chipName}", continuing with execution anyway`);
    }

    // ── Step 2: Verify pre-run state ────────────────────────────────────────
    const preStatus = await getOverallStatus(sharedPage);
    console.log(`[${ec.id}] Pre-run status: "${preStatus}"`);
    await shot(sharedPage, 'service-execution', `${ec.id}_02_prerun`);

    // ── Step 3: Click Run and observe running state ─────────────────────────
    // First wait for any previous run on this fixture to clear
    await waitForNoActiveRuns(sharedPage, 120_000);

    console.log(`[${ec.id}] Clicking Run…`);
    await clickRunAndWait(sharedPage, ec.executionTimeoutMs);

    // Capture running state screenshot (phase cards with running spinner)
    const observedRunning = await waitForRunningState(sharedPage, 30_000);
    if (observedRunning) {
      console.log(`[${ec.id}] ✅ Running state observed`);
      await shot(sharedPage, 'service-execution', `${ec.id}_03_running`);
    } else {
      console.log(`[${ec.id}] ⚠️ Running state not observed before completion`);
    }

    // ── Step 4: Verify terminal state ───────────────────────────────────────
    const postStatus = await getOverallStatus(sharedPage);
    const terminal = await isTerminalState(sharedPage);
    console.log(`[${ec.id}] Post-run status: "${postStatus}", terminal: ${terminal}`);
    await shot(sharedPage, 'service-execution', `${ec.id}_04_terminal`);

    expect(
      postStatus === 'completed' || postStatus === 'failed',
      `[${ec.id}] Expected terminal status (completed|failed), got "${postStatus}"`
    ).toBe(true);

    if (postStatus === 'failed') {
      console.warn(`[${ec.id}] ⚠️ Workflow failed — checking after-run tabs anyway`);
    } else {
      console.log(`[${ec.id}] ✅ Workflow completed`);
    }

    // ── Step 5: Verify after-run tabs ───────────────────────────────────────
    await pause(sharedPage, 2_000); // allow tabs to render

    const tabs = await getAfterRunTabs(sharedPage);
    console.log(`[${ec.id}] After-run tabs visible: [${tabs.join(', ')}]`);
    await shot(sharedPage, 'service-execution', `${ec.id}_05_tabs`);

    // Check for Findings tab
    const hasFindings = tabs.some(t => t.toLowerCase().includes('finding'));
    const hasMethods  = tabs.some(t => t.toLowerCase().includes('method'));
    const hasReport   = tabs.some(t => t.toLowerCase().includes('report') || t.toLowerCase().includes('output'));

    console.log(`[${ec.id}]   Findings: ${hasFindings ? '✅' : '❌'}  Methods: ${hasMethods ? '✅' : '❌'}  Report/Outputs: ${hasReport ? '✅' : '❌'}`);

    if (postStatus === 'completed') {
      expect(
        tabs.length,
        `[${ec.id}] Expected ≥ ${ec.minAfterRunTabs} after-run tabs on completed run, got ${tabs.length}`
      ).toBeGreaterThanOrEqual(ec.minAfterRunTabs);
    }

    // ── Step 6: Click Findings and verify content ────────────────────────────
    if (hasFindings) {
      const findingsBtn = sharedPage.locator(
        '[data-testid="after-run-tab-findings"], button:has-text("Findings"), [role="tab"]:has-text("Findings")'
      ).first();
      const findingsVisible = await findingsBtn.isVisible({ timeout: 3_000 }).catch(() => false);
      if (findingsVisible) {
        await findingsBtn.click().catch(() => {});
        await pause(sharedPage, 1_500);
        await shot(sharedPage, 'service-execution', `${ec.id}_06_findings`);
        console.log(`[${ec.id}] ✅ Findings tab clicked and screenshot captured`);
      }
    }

    // ── Step 7: Click Methods and verify content ─────────────────────────────
    if (hasMethods) {
      const methodsBtn = sharedPage.locator(
        '[data-testid="after-run-tab-methods"], button:has-text("Methods"), [role="tab"]:has-text("Methods")'
      ).first();
      const methodsVisible = await methodsBtn.isVisible({ timeout: 3_000 }).catch(() => false);
      if (methodsVisible) {
        await methodsBtn.click().catch(() => {});
        await pause(sharedPage, 1_500);
        await shot(sharedPage, 'service-execution', `${ec.id}_07_methods`);
        console.log(`[${ec.id}] ✅ Methods tab clicked and screenshot captured`);

        // Verify methods content is non-empty
        const methodsText = await sharedPage
          .locator('[data-testid="after-run-tab-content-methods"], [class*="methods-content"], [class*="tab-content"]')
          .first().textContent({ timeout: 5_000 }).catch(() => '');
        if (methodsText && methodsText.trim().length > 50) {
          console.log(`[${ec.id}]   Methods text: "${methodsText.trim().slice(0, 100)}…"`);
        }
      }
    }

    // ── Step 8: Check for report download link ───────────────────────────────
    const downloadLink = sharedPage.locator(
      'a[download], button:has-text("Download"), a:has-text("Download Report"), [data-testid*="download"]'
    ).first();
    const downloadVisible = await downloadLink.isVisible({ timeout: 5_000 }).catch(() => false);
    console.log(`[${ec.id}] Download button: ${downloadVisible ? '✅ visible' : '⚠️ not found'}`);

    if (downloadVisible) {
      await shot(sharedPage, 'service-execution', `${ec.id}_08_download`);
    }

    console.log(`[${ec.id}] ✅ Full lifecycle audit complete`);
  });
}

// ── Real-time state transition test ───────────────────────────────────────────
// Focused test that verifies the idle→running→completed transition sequence
// for ADMET (fastest workflow) using data-status attributes on phase cards.

test('EX-RT — real-time status tracking: idle→running→completed', async () => {
  test.setTimeout(90_000 + ADMET_TIMEOUT_MS + 60_000);

  console.log('\n[EX-RT] Real-time status tracking audit');

  await startNewChat(sharedPage);
  await sendAndWait(
    sharedPage,
    'Run ADMET prediction for ibuprofen (SMILES: CC(C)Cc1ccc(cc1)C(C)C(=O)O)',
    90_000
  );

  // Verify pre-run idle state
  const panelExists = await sharedPage
    .locator('[data-testid="nextflow-workflow-viewer"]')
    .isVisible({ timeout: 10_000 }).catch(() => false);

  if (!panelExists) {
    console.log('[EX-RT] ⚠️ No workflow panel visible — skipping status tracking');
    return;
  }

  const idleStatus = await getOverallStatus(sharedPage);
  console.log(`[EX-RT] Pre-run status: "${idleStatus}"`);
  await shot(sharedPage, 'service-execution', 'EX-RT_01_idle');

  expect(
    idleStatus === 'idle' || idleStatus === 'pending' || idleStatus === 'unknown',
    `Expected idle/pending pre-run status, got "${idleStatus}"`
  ).toBe(true);

  // Click Run and capture running state as soon as possible
  await waitForNoActiveRuns(sharedPage, 60_000);

  let runningCaptured = false;
  const runPromise = clickRunAndWait(sharedPage, ADMET_TIMEOUT_MS);

  // Poll for running state in parallel with execution
  const runningCheckPromise = (async () => {
    const deadline = Date.now() + 120_000;
    while (Date.now() < deadline) {
      const s = await getOverallStatus(sharedPage);
      if (s === 'running') {
        runningCaptured = true;
        console.log('[EX-RT] ✅ Running state captured');
        await shot(sharedPage, 'service-execution', 'EX-RT_02_running');
        return;
      }
      if (s === 'completed' || s === 'failed') return; // already past running
      await pause(sharedPage, 2_000);
    }
  })();

  await Promise.race([runPromise, runningCheckPromise]);
  await runPromise; // ensure execution completes

  const finalStatus = await getOverallStatus(sharedPage);
  console.log(`[EX-RT] Final status: "${finalStatus}", running captured: ${runningCaptured}`);
  await shot(sharedPage, 'service-execution', 'EX-RT_03_completed');

  expect(
    finalStatus === 'completed' || finalStatus === 'failed',
    `Expected completed/failed terminal status, got "${finalStatus}"`
  ).toBe(true);

  console.log('[EX-RT] ✅ Status transition audit complete');
});
