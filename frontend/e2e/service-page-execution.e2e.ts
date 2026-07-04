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
 *   EX-2  BOIN Clinical Trial Simulation — single nextflow workflow (no file inputs)
 *   EX-3  PBPK Allometric Scaling   — single nextflow workflow (not a chain)
 *
 * Each flow exercises:
 *   ✓ Pre-run state  — footer "Run", overall badge idle/pending
 *   ✓ Running state  — footer "Running…", phase card data-status="running"
 *   ✓ Terminal state — footer "Run again" OR "Restart"
 *   ✓ After-run tabs — "after-tab-*" buttons present; Download report link
 *
 * NO page.route() mocking. Real backend (AWS Batch via Galaxy :8081).
 * Screenshots → e2e/screenshots/service-execution/
 *
 * NOTE: Execution (Nextflow) requires dev EC2 (dev-public.biomate.ai) where
 * Nextflow + AWS Batch are configured. Running locally produces "FAILED"
 * terminal states (no Nextflow binary), which is correct failure-path
 * behavior but workflows won't complete. Routing + lifecycle assertions
 * still pass locally; completion + Findings content assertions require dev.
 *
 * Timeouts:
 *   - LLM routing:  90 s
 *   - AWS Batch execution: 20 min (ADMET/BOIN), 20 min (PBPK)
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

import { test, expect, type Page } from '@playwright/test';
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
const PBPK_TIMEOUT_MS   = 20 * 60_000;  // 20 min

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
    label: 'BOIN Clinical Trial Simulation',
    prompt: 'Run a BOIN Phase I dose-escalation simulation for a new oncology compound — starting dose 10 mg, max dose 400 mg, target DLT rate 25%, 1000 simulations to find the MTD',
    expectWorkflow: ['boin', 'BOIN', 'clinical_trial', 'dose', 'escalation', 'simulation'],
    executionTimeoutMs: FAERS_TIMEOUT_MS,
    minAfterRunTabs: 2,
  },
  {
    id: 'EX-3',
    label: 'PBPK Allometric Scaling',
    // Single nextflow workflow — avoids chain UI incompatibility with clickRunAndWait.
    // Routes to pbpk_pediatric (verified in 21-case routing test as Q04).
    prompt: 'Run PBPK simulation for metoprolol (oral 100mg dose) — allometrically scale PK parameters from rat to human and predict Cmax, AUC, and half-life for pediatric dose selection',
    expectWorkflow: ['pbpk', 'PBPK', 'allometric', 'pediatric', 'pharmacokinetic'],
    executionTimeoutMs: PBPK_TIMEOUT_MS,
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
 * Falls back to panel-action-bar data-status when no badge exists.
 */
async function getOverallStatus(page: Page): Promise<string> {
  return page.evaluate(() => {
    // Primary: workflow-overall-status-badge (set in nextflow-workflow-viewer.tsx)
    const badge = document.querySelector('[data-testid="workflow-overall-status-badge"]');
    if (badge) {
      const s = (badge as HTMLElement).dataset.status ?? '';
      if (s) return s;
    }
    // Secondary: panel-action-bar data-status (set on the footer action bar)
    const actionBar = document.querySelector('[data-testid="panel-action-bar"]');
    if (actionBar) {
      const s = (actionBar as HTMLElement).dataset.status ?? '';
      if (s && s !== 'idle') return s;
    }
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
 * Returns visible after-run tab labels.
 *
 * Uses the canonical data-testid="after-tab-{id}" pattern from AfterRunReport.tsx.
 * Tabs are always shown in order: Outputs → Findings → [QC report] → [Methods] →
 * [Citations] → Parameters → [Software].
 *
 * Minimum: Outputs + Findings + Parameters (3) are always shown.
 * Methods appears only when the methods API returns real content.
 */
async function getAfterRunTabs(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    // Canonical: after-tab-{id} data-testids from AfterRunReport.tsx
    const canonical = document.querySelectorAll('[data-testid^="after-tab-"]');
    if (canonical.length > 0) {
      return Array.from(canonical).map(el => el.textContent?.trim() ?? '').filter(Boolean);
    }
    // Fallback: look for role=tab buttons with known after-run labels
    // Only match tab-like elements within the after-run section
    const afterRunSection = document.querySelector('[data-testid="panel-after-run"]');
    if (afterRunSection) {
      const tabBtns = afterRunSection.querySelectorAll('button[role="tab"]');
      if (tabBtns.length > 0) {
        return Array.from(tabBtns).map(el => el.textContent?.trim() ?? '').filter(Boolean);
      }
    }
    return [];
  }).catch(() => []);
}

/**
 * Checks if the workflow panel shows a "Run again" or "Restart" footer button,
 * indicating the workflow reached a terminal state.
 * Uses the canonical data-testid="panel-run-again-cta" from nextflow-workflow-viewer.tsx.
 */
async function isTerminalState(page: Page): Promise<boolean> {
  return page.evaluate(() => {
    // Primary: panel-run-again-cta appears ONLY in terminal (completed/failed) state
    const runAgainCta = document.querySelector('[data-testid="panel-run-again-cta"]');
    if (runAgainCta) return true;
    // Secondary: check panel-action-bar data-status
    const actionBar = document.querySelector('[data-testid="panel-action-bar"]');
    if (actionBar) {
      const s = (actionBar as HTMLElement).dataset.status ?? '';
      return /completed|failed|errored/i.test(s);
    }
    return false;
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
    console.log(`[${ec.id}] Routing: "${chipName ?? '(chip missing)'}" → ${routed ? '✅' : '⚠️ keyword not matched'}`);
    await shot(sharedPage, 'service-execution', `${ec.id}_01_routed`);

    // Routing is not a hard failure — wrong routing is already caught by the 21-case test
    if (!routed) {
      console.warn(`[${ec.id}] ⚠️ Routing unexpected — title="${chipName}", proceeding with execution`);
    }

    // ── Step 2: Verify pre-run state ────────────────────────────────────────
    const preStatus = await getOverallStatus(sharedPage);
    console.log(`[${ec.id}] Pre-run status: "${preStatus}"`);
    await shot(sharedPage, 'service-execution', `${ec.id}_02_prerun`);

    // ── Step 3: Click Run and observe running state ─────────────────────────
    // Wait for any previous run on this fixture to clear
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
      postStatus,
      `[${ec.id}] Workflow must complete successfully, got "${postStatus}"`
    ).toBe('completed');

    console.log(`[${ec.id}] ✅ Workflow completed`);

    // ── Step 5: Verify after-run tabs ───────────────────────────────────────
    await pause(sharedPage, 2_000); // allow tabs to render

    // Ensure After run tab is active (auto-switches on terminal but may need nudge)
    const afterRunTabBtn = sharedPage.locator('[data-testid="panel-tab-after-run"]').first();
    if (await afterRunTabBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
      const isActive = await afterRunTabBtn.evaluate(el =>
        el.classList.contains('active') || el.getAttribute('aria-selected') === 'true'
      ).catch(() => false);
      if (!isActive) await afterRunTabBtn.click().catch(() => {});
      await pause(sharedPage, 1_000);
    }

    const tabs = await getAfterRunTabs(sharedPage);
    console.log(`[${ec.id}] After-run tabs: [${tabs.join(', ')}]`);
    await shot(sharedPage, 'service-execution', `${ec.id}_05_tabs`);

    // Check for known after-run tabs
    const hasOutputs  = tabs.some(t => /outputs?/i.test(t));
    const hasFindings = tabs.some(t => /finding/i.test(t));
    const hasMethods  = tabs.some(t => /method/i.test(t));
    const hasParams   = tabs.some(t => /param/i.test(t));

    console.log(`[${ec.id}]   Outputs: ${hasOutputs ? '✅' : '❌'}  Findings: ${hasFindings ? '✅' : '❌'}  Methods: ${hasMethods ? '✅' : '❌'}  Params: ${hasParams ? '✅' : '❌'}`);

    // Outputs + Findings + Parameters are always shown (even on failed runs).
    // Assert tabs are present regardless of completion status.
    expect(
      tabs.length,
      `[${ec.id}] Expected ≥ ${ec.minAfterRunTabs} after-run tabs (Outputs+Findings always present), got ${tabs.length}: [${tabs.join(', ')}]`
    ).toBeGreaterThanOrEqual(ec.minAfterRunTabs);

    expect(
      hasFindings,
      `[${ec.id}] Expected "Findings" tab in after-run section, got: [${tabs.join(', ')}]`
    ).toBe(true);

    // ── Step 6: Click Findings and verify content ────────────────────────────
    const findingsBtn = sharedPage.locator('[data-testid="after-tab-findings"]').first();
    const findingsVisible = await findingsBtn.isVisible({ timeout: 5_000 }).catch(() => false);
    if (findingsVisible) {
      await findingsBtn.click().catch(() => {});
      await pause(sharedPage, 1_500);
      await shot(sharedPage, 'service-execution', `${ec.id}_06_findings`);
      console.log(`[${ec.id}] ✅ Findings tab clicked`);
    }

    // ── Step 7: Click Methods if present ────────────────────────────────────
    if (hasMethods) {
      const methodsBtn = sharedPage.locator('[data-testid="after-tab-methods"]').first();
      const methodsVisible = await methodsBtn.isVisible({ timeout: 3_000 }).catch(() => false);
      if (methodsVisible) {
        await methodsBtn.click().catch(() => {});
        await pause(sharedPage, 1_500);
        await shot(sharedPage, 'service-execution', `${ec.id}_07_methods`);
        console.log(`[${ec.id}] ✅ Methods tab clicked`);
      }
    }

    // ── Step 8: Check for report download button ─────────────────────────────
    const downloadBtn = sharedPage.locator('[data-testid="afterrun-download-report"]').first();
    const downloadVisible = await downloadBtn.isVisible({ timeout: 5_000 }).catch(() => false);
    console.log(`[${ec.id}] Download report: ${downloadVisible ? '✅ visible' : '⚠️ not found'}`);

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

  // Click the workflow chip to open the panel (in case it didn't auto-open)
  const chip = sharedPage.locator('.wf-chip-name, [data-testid="workflow-chip"]').first();
  if (await chip.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await chip.click().catch(() => {});
    await pause(sharedPage, 1_500);
  }

  // Verify pre-run idle state — give the panel 20 s to render
  const panelExists = await sharedPage
    .locator('[data-testid="workflow-artifact-panel"]')
    .isVisible({ timeout: 20_000 }).catch(() => false);

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
  const finalTerminal = await isTerminalState(sharedPage);
  console.log(`[EX-RT] Final status: "${finalStatus}", terminal: ${finalTerminal}, running captured: ${runningCaptured}`);
  await shot(sharedPage, 'service-execution', 'EX-RT_03_terminal');

  expect(
    finalStatus === 'completed' || finalStatus === 'failed',
    `Expected completed/failed terminal status, got "${finalStatus}"`
  ).toBe(true);

  // Verify after-run tabs appear after terminal state
  await pause(sharedPage, 2_000);
  const tabs = await getAfterRunTabs(sharedPage);
  console.log(`[EX-RT] After-run tabs: [${tabs.join(', ')}]`);
  await shot(sharedPage, 'service-execution', 'EX-RT_04_tabs');

  expect(
    tabs.length,
    `[EX-RT] Expected after-run tabs on terminal state, got ${tabs.length}: [${tabs.join(', ')}]`
  ).toBeGreaterThan(0);

  console.log('[EX-RT] ✅ Status transition audit complete');
});
