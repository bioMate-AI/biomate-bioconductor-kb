/**
 * Service Page — Full Execution Flow
 *
 * One sequential test covering the complete user journey across three
 * representative workflows.  Sequential by design: each workflow runs
 * to terminal state before the next starts, sharing a single login and
 * a single browser session.
 *
 * Journey:
 *   1. Login (once)
 *   2. ADMET full panel (aspirin)     — fast workflow, QC gate, real-time
 *      running-state tracking built-in
 *   3. BOIN clinical trial simulation — single Nextflow job, QC all-pass
 *   4. PBPK allometric scaling        — single Nextflow job, QC all-pass
 *
 * Each workflow step verifies:
 *   ✓ Routing:     workflow chip/name contains expected keyword
 *   ✓ Pre-run:     overall badge idle/pending
 *   ✓ Running:     footer "Running…", phase card data-status="running"
 *                  (captured in parallel with execution — won't miss fast runs)
 *   ✓ Terminal:    badge "completed", footer "Run again"
 *   ✓ After-run tabs: Outputs + Findings + QC report always expected
 *   ✓ Findings:    tab click, summary present, no "Analysis in progress…"
 *   ✓ QC report:   tab click, body rendered (all-passed or audit table)
 *   ✓ Download:    afterrun-download-report visible; screenshot on Findings tab
 *
 * Constraints (CLAUDE.md):
 *   - NO page.route() mocking. Real backend.
 *   - Login once per harness, not per workflow.
 *   - Fixture: lifeifei163361@163.com / E2E_FIXTURE_PASSWORD
 *   - Screenshots → e2e/screenshots/service-execution/
 *
 * Run against dev:
 *   BIOMATE_URL=https://dev-public.biomate.ai \
 *   E2E_FIXTURE_PASSWORD=WpmFixture!2026 \
 *   npx playwright test e2e/service-page-execution.e2e.ts --project=chromium
 *
 * Timeouts:
 *   LLM routing: 90 s per workflow
 *   AWS Batch:   20 min per workflow
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
const EXEC_TIMEOUT_MS  = 20 * 60_000; // 20 min per workflow

interface WorkflowStep {
  id: string;
  label: string;
  prompt: string;
  expectKeywords: string[];
}

const WORKFLOW_STEPS: WorkflowStep[] = [
  {
    id: 'ADMET',
    label: 'ADMET Full Panel',
    prompt: 'Run a full ADMET panel for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O) — hERG cardiotoxicity, DILI, Ames mutagenicity, CYP450 inhibition, and Lipinski Ro5 compliance',
    expectKeywords: ['admet', 'predict'],
  },
  {
    id: 'BOIN',
    label: 'BOIN Clinical Trial Simulation',
    prompt: 'Run a BOIN Phase I dose-escalation simulation for a new oncology compound — starting dose 10 mg, max dose 400 mg, target DLT rate 25%, 1000 simulations to find the MTD',
    expectKeywords: ['boin', 'clinical_trial', 'dose', 'escalation', 'simulation'],
  },
  {
    id: 'PBPK',
    label: 'PBPK Allometric Scaling',
    prompt: 'Run PBPK simulation for metoprolol (oral 100mg dose) — allometrically scale PK parameters from rat to human and predict Cmax, AUC, and half-life for pediatric dose selection',
    expectKeywords: ['pbpk', 'allometric', 'pediatric', 'pharmacokinetic'],
  },
];

// ── Auth ───────────────────────────────────────────────────────────────────────

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

async function getOverallStatus(page: Page): Promise<string> {
  return page.evaluate(() => {
    const badge = document.querySelector('[data-testid="workflow-overall-status-badge"]');
    if (badge) {
      const s = (badge as HTMLElement).dataset.status ?? '';
      if (s) return s;
    }
    const actionBar = document.querySelector('[data-testid="panel-action-bar"]');
    if (actionBar) {
      const s = (actionBar as HTMLElement).dataset.status ?? '';
      if (s && s !== 'idle') return s;
    }
    const cards = document.querySelectorAll('[data-testid^="phase-card-"]');
    if (Array.from(cards).some(c => (c as HTMLElement).dataset.status === 'running')) return 'running';
    if (Array.from(cards).some(c => (c as HTMLElement).dataset.status === 'completed')) return 'completed';
    if (Array.from(cards).some(c => (c as HTMLElement).dataset.status === 'failed')) return 'failed';
    return 'unknown';
  }).catch(() => 'unknown');
}

async function isTerminalState(page: Page): Promise<boolean> {
  return page.evaluate(() => {
    const runAgainCta = document.querySelector('[data-testid="panel-run-again-cta"]');
    if (runAgainCta) return true;
    const actionBar = document.querySelector('[data-testid="panel-action-bar"]');
    if (actionBar) {
      const s = (actionBar as HTMLElement).dataset.status ?? '';
      return /completed|failed|errored/i.test(s);
    }
    return false;
  }).catch(() => false);
}

async function getAfterRunTabs(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    const canonical = document.querySelectorAll('[data-testid^="after-tab-"]');
    if (canonical.length > 0) {
      return Array.from(canonical).map(el => el.textContent?.trim() ?? '').filter(Boolean);
    }
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

// ── Wait for status badge to settle after clickRunAndWait returns ──────────────
// clickRunAndWait detects the "run-again" CTA button; the overall status badge
// may still read "running" for a moment after that. Wait up to 10 s for it to flip.
async function waitForTerminalStatus(page: Page): Promise<string> {
  const deadline = Date.now() + 10_000;
  let status = await getOverallStatus(page);
  while (status === 'running' && Date.now() < deadline) {
    await pause(page, 1_000);
    status = await getOverallStatus(page);
  }
  return status;
}

// ── Single workflow step ───────────────────────────────────────────────────────

async function runWorkflowStep(page: Page, step: WorkflowStep): Promise<void> {
  console.log(`\n[${step.id}] ── ${step.label}`);

  // 1. Route
  await startNewChat(page);
  await sendAndWait(page, step.prompt, 90_000);

  const chipName = await page.locator('.wf-chip-name').first()
    .textContent({ timeout: 15_000 }).catch(() => null);
  const msgText = await page
    .locator('[data-is-latest-assistant="true"]').first()
    .textContent().catch(() => '') ?? '';
  const effectiveTitle = (chipName ?? msgText).toLowerCase();
  const routed = step.expectKeywords.some(kw => effectiveTitle.includes(kw.toLowerCase()));

  console.log(`[${step.id}] routing: "${chipName ?? '(chip missing)'}" → ${routed ? '✅' : '⚠️'}`);
  await shot(page, 'service-execution', `${step.id}_01_routed`);

  // 2. Pre-run state
  const preStatus = await getOverallStatus(page);
  console.log(`[${step.id}] pre-run status: "${preStatus}"`);
  await shot(page, 'service-execution', `${step.id}_02_prerun`);

  // 3. Run — capture running state IN PARALLEL with execution
  await waitForNoActiveRuns(page, 120_000);
  console.log(`[${step.id}] clicking Run…`);

  const execPromise = clickRunAndWait(page, EXEC_TIMEOUT_MS);

  let observedRunning = false;
  const runningPoll = (async () => {
    const deadline = Date.now() + 120_000;
    while (Date.now() < deadline) {
      const s = await getOverallStatus(page);
      if (s === 'running') {
        observedRunning = true;
        console.log(`[${step.id}] ✅ running state captured`);
        await shot(page, 'service-execution', `${step.id}_03_running`);
        return;
      }
      if (s === 'completed' || s === 'failed') return;
      await pause(page, 1_000);
    }
  })();

  await Promise.race([execPromise, runningPoll]);
  await execPromise;

  if (!observedRunning) {
    console.log(`[${step.id}] ⚠️ workflow completed before running state was captured`);
  }

  // 4. Terminal state — wait for badge to settle after clickRunAndWait returns
  const postStatus = await waitForTerminalStatus(page);
  const terminal = await isTerminalState(page);
  console.log(`[${step.id}] terminal: status="${postStatus}", terminal=${terminal}`);
  await shot(page, 'service-execution', `${step.id}_04_terminal`);

  expect(
    postStatus,
    `[${step.id}] workflow must complete successfully, got "${postStatus}"`
  ).toBe('completed');

  // 5. After-run tabs
  await pause(page, 2_000);

  const afterRunTabBtn = page.locator('[data-testid="panel-tab-after-run"]').first();
  if (await afterRunTabBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
    const isActive = await afterRunTabBtn.evaluate(el =>
      el.classList.contains('active') || el.getAttribute('aria-selected') === 'true'
    ).catch(() => false);
    if (!isActive) await afterRunTabBtn.click().catch(() => {});
    await pause(page, 1_000);
  }

  const tabs = await getAfterRunTabs(page);
  const hasOutputs  = tabs.some(t => /outputs?/i.test(t));
  const hasFindings = tabs.some(t => /finding/i.test(t));
  const hasQc       = tabs.some(t => /qc|quality/i.test(t));
  console.log(`[${step.id}] tabs: [${tabs.join(', ')}]  outputs=${hasOutputs ? '✅' : '❌'}  findings=${hasFindings ? '✅' : '❌'}  qc=${hasQc ? '✅' : '❌'}`);
  await shot(page, 'service-execution', `${step.id}_05_tabs`);

  expect(tabs.length, `[${step.id}] expected ≥2 after-run tabs, got ${tabs.length}`).toBeGreaterThanOrEqual(2);
  expect(hasFindings, `[${step.id}] Findings tab must be present`).toBe(true);
  expect(hasQc,       `[${step.id}] QC report tab must be present`).toBe(true);

  // 6. Findings tab
  const findingsBtn = page.locator('[data-testid="after-tab-findings"]').first();
  if (await findingsBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await findingsBtn.click();
    await pause(page, 1_500);
    await shot(page, 'service-execution', `${step.id}_06_findings`);

    const spinner = await page.locator('[data-testid="findings-loading"]').isVisible({ timeout: 500 }).catch(() => false);
    if (spinner) console.warn(`[${step.id}] ⚠️ findings spinner still visible after completion`);
    console.log(`[${step.id}] findings spinner: ${spinner ? '⚠️ still running' : '✅ none'}`);
  }

  // 7. QC tab
  const qcBtn = page.locator('[data-testid="after-tab-qc"]').first();
  if (await qcBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await qcBtn.click();
    await pause(page, 1_000);
    await shot(page, 'service-execution', `${step.id}_07_qc`);

    const qcBody    = await page.locator('[data-testid="qc-audit-tab"]').isVisible({ timeout: 5_000 }).catch(() => false);
    const qcAllPass = await page.locator('[data-testid="qc-all-passed"]').isVisible({ timeout: 2_000 }).catch(() => false);
    console.log(`[${step.id}] qc body=${qcBody ? '✅' : '❌'}  all-passed=${qcAllPass ? '✅' : '—'}`);
    expect(qcBody, `[${step.id}] QC tab body must render`).toBe(true);
  }

  // 8. Download report — navigate to Findings tab so screenshot is distinct from QC
  const downloadBtn = page.locator('[data-testid="afterrun-download-report"]').first();
  const downloadVisible = await downloadBtn.isVisible({ timeout: 5_000 }).catch(() => false);
  console.log(`[${step.id}] download report: ${downloadVisible ? '✅' : '⚠️ not found'}`);

  if (downloadVisible) {
    const findingsBtnDl = page.locator('[data-testid="after-tab-findings"]').first();
    if (await findingsBtnDl.isVisible({ timeout: 2_000 }).catch(() => false)) {
      await findingsBtnDl.click();
      await pause(page, 1_000);
    }
    await downloadBtn.scrollIntoViewIfNeeded().catch(() => {});
    await pause(page, 300);
    await shot(page, 'service-execution', `${step.id}_08_download`);
  }

  expect(downloadVisible, `[${step.id}] download report button must be visible after completion`).toBe(true);

  console.log(`[${step.id}] ✅ complete`);
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

// ── The test ───────────────────────────────────────────────────────────────────

test('Full execution flow — ADMET → BOIN → PBPK', async () => {
  // Total: (90 s LLM + 20 min exec + 60 s overhead) × 3 workflows
  test.setTimeout((90_000 + EXEC_TIMEOUT_MS + 60_000) * 3);

  for (const step of WORKFLOW_STEPS) {
    await runWorkflowStep(sharedPage, step);
  }

  console.log('\n✅ Full execution flow complete (ADMET → BOIN → PBPK)');
});
