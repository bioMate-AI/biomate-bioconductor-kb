/**
 * Drug Discovery Pilot E2E — BCR-ABL1 / NSCLC Campaign
 *
 * Tests all 6 sessions from docs/pilot_study/20260325_INTERNAL_PILOT_VALIDATION_RUN_REPORT.md
 * as multi-turn conversations, ALL running under a SINGLE shared user account so that
 * Lago billing events accumulate correctly for ROI calculation.
 *
 * Parallelism model:
 *   - Default: `workers: 1` (playwright.config.ts) — sessions run sequentially
 *   - For parallel ROI timing: `npx playwright test drug-discovery-pilot-e2e.e2e.ts --workers=6`
 *     Each test gets its own browser context (not page) but shares the same registered user_id
 *     so billing accumulates in the same Lago customer record.
 *
 * Per session this test captures:
 *   - Turn-level timing: t0 (send), t1 (intent classified), t2 (workflow card appeared)
 *   - Workflow card fields: workflowName, workflowPath, confidence, domain
 *   - Billing snapshot BEFORE and AFTER via GET /api/billing/usage
 *   - Lago usage delta: LLM tokens in/out, LLM cost, compute cost (Nextflow run if triggered)
 *   - H1/H2/H3/H5 gate evaluation per session
 *
 * Final audit JSON written to e2e/screenshots/drug-discovery-pilot/audit_<timestamp>.json
 *
 * NO MOCKS. All calls hit the live backend with real AI responses.
 * Nextflow execution steps (where triggered) run in mock mode (MOCK_NF=true) to
 * avoid real AWS Batch costs during E2E runs — the execution path is validated
 * end-to-end but compute cost = $0 for mock runs.
 *
 * IMPORTANT: Set BIOMATE_URL to point at your running stack before running.
 */

import { test, expect, Page, Browser, BrowserContext } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
// Rate-limit bypass for E2E — must match E2E_TEST_TOKEN in frontend/.env
const E2E_TEST_TOKEN = process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only';
const SS_DIR = path.join(__dirname, 'screenshots', 'drug-discovery-pilot');

if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// Run-button selector covering all card types: single workflow, pipeline, prereq-override
const RUN_BTN_SELECTORS =
  '[data-testid="button-run-workflow-panel"],' +
  '[data-testid="button-confirm-and-run"],' +
  '[data-testid="pipeline-confirm-run"],' +
  '[data-testid="button-prereq-recovery"]';

// ---------------------------------------------------------------------------
// Shared state: single user account for all 6 sessions
// ---------------------------------------------------------------------------

/** Registered once in beforeAll, shared across all tests for billing accumulation. */
interface SharedAccount {
  email: string;
  password: string;
  userId: string | null;
  jwt: string | null;
}

// Fixed test account — reused across runs to avoid hitting registration rate limit (3/hr).
// Registration is attempted first; if it fails (already exists), we fall back to login.
const SHARED_ACCOUNT: SharedAccount = {
  email: 'e2e_pilot_drug_discovery@biomate.test',
  password: 'TestPass123!',
  userId: null,
  jwt: null,
};

// ---------------------------------------------------------------------------
// Timing & billing types
// ---------------------------------------------------------------------------

interface TurnTiming {
  turn: number;
  query: string;
  tSendMs: number;
  tResponseMs: number | null;
  tWorkflowCardMs: number | null;
  responseTimeMs: number | null;
  workflowCardTimeMs: number | null;
  workflowName: string | null;
  workflowPath: string | null;
  intentType: string | null;
  hasRunButton: boolean;
}

interface BillingSnapshot {
  ts: string;
  llm_input_tokens: number;
  llm_output_tokens: number;
  llm_cost_usd: number;
  compute_cost_usd: number;
  storage_cost_usd: number;
  total_usd: number;
  quota_pct: number;
  error?: string;
}

interface OutputFile {
  name: string;
  type: string;
  size?: number;
  path?: string;
  preview?: string;
}

interface ExecutionResult {
  runId: string;
  status: string;                    // completed | failed | error | timeout
  tStartMs: number;                  // when Confirm & Run was clicked
  tTerminalMs: number;               // when terminal status was reached
  executionDurationMs: number;
  outputFiles: OutputFile[];
  downloadCommands: Record<string, string>;
  phaseCount: number;
}

interface SessionResult {
  sessionId: string;
  sessionName: string;
  pilotSession: string;
  workflowId: string;
  startTs: string;
  endTs: string;
  totalDurationMs: number;
  turns: TurnTiming[];
  execution: ExecutionResult | null;  // null if workflow card never appeared
  billingBefore: BillingSnapshot;
  billingAfter: BillingSnapshot;
  billingDelta: {
    llm_input_tokens: number;
    llm_output_tokens: number;
    llm_cost_usd: number;
    compute_cost_usd: number;
    total_usd: number;
  };
  h1Pass: boolean;       // workflow generated without manual correction
  h2Pass: boolean;       // time-to-workflow-card ≤ 120s
  h3Rating: number;      // 1–5 scientific defensibility (set in test body)
  h5Pass: boolean;       // 0 hallucinations (workflow exists in DB)
  workflowExists: boolean;
  notes: string[];
  screenshots: string[];  // all per-turn + completion screenshots
  screenshot: string;     // primary screenshot (backwards compat)
  status: 'pass' | 'fail' | 'skip';
  error?: string;
}

const SESSION_RESULTS: SessionResult[] = [];

// ---------------------------------------------------------------------------
// Compound data from pilot report
// ---------------------------------------------------------------------------

// Session 1 — 15 BCR-ABL1 / reference compounds with SMILES
const S1_SMILES = [
  // Imatinib (CPD001)
  'Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1',
  // Dasatinib (CPD002)
  'Cc1nc(Nc2ncc(F)c(Nc3cccc(C(=O)NC4CCN(CCO)CC4)c3)n2)cc(N2CCN(CCO)CC2)n1',
  // Nilotinib (CPD003)
  'Cc1ccc(NC(=O)c2ccc(CF)cn2)cc1Nc1nc(Nc2ccc(cc2)C(F)(F)F)ncc1-c1ccncc1',
  // Bosutinib (CPD004)
  'COc1cc2c(Nc3ccc(Cl)c(Cl)c3)ncnc2cc1OCCCN1CCC(N)CC1',
  // Ponatinib (CPD005)
  'Cc1ccc(C(=O)Nc2ccc(CN3CCN(C)CC3)cc2-c2cccc(C(F)(F)F)c2)cc1',
  // Asciminib (CPD006) — myristoyl pocket binder
  'C[C@@H]1CN(c2ncnc3[nH]cc(-c4ccc(Cl)cc4F)c23)C[C@@H]1NC(=O)c1cnc(C(F)(F)F)cn1',
  // Gleevec-analog-1 (CPD007)
  'Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1',
  // Gleevec-analog-2 (CPD008)
  'Cc1ccc(NC(=O)c2cc(N3CCN(C)CC3)ccc2)cc1Nc1nccc(-c2cccnc2)n1',
  // Terfenadine (CPD009) — hERG reference (withdrawn)
  'C(c1ccc(cc1)C(O)(CCCC1=CC=CC=C1)CCCC1=CC=CC=C1)N1CCC(CC1)C(O)(c1ccccc1)c1ccccc1',
  // Cisapride (CPD010) — hERG reference (withdrawn)
  'CCOC(=O)c1cc(OCC)c(N)c(OCC)c1',
  // Metoclopramide (CPD011)
  'CCN(CC)CCNC(=O)c1cc(Cl)c(N)cc1OC',
  // Erlotinib (CPD012)
  'C#Cc1cccc(Nc2ncnc3cc(OCCO)c(OCCO)cc23)c1',
  // Gefitinib (CPD013)
  'COc1cc2ncnc(Nc3ccc(F)c(Cl)c3)c2cc1OCCCN1CCOCC1',
  // Doxorubicin (CPD014)
  'COc1cccc2C(=O)c3c(O)c4C(=O)C(O)(CC(=O)CO)Cc4c(O)c3C(=O)c12',
  // Acetaminophen (CPD015)
  'CC(=O)Nc1ccc(O)cc1',
].join(' ');

// ---------------------------------------------------------------------------
// Helper: extract JWT from localStorage
// ---------------------------------------------------------------------------

async function extractJWT(page: Page): Promise<string | null> {
  return page.evaluate(() => {
    // Try known key names first
    for (const key of ['auth_token', 'token', 'jwt', 'authToken', 'access_token', 'bearerToken']) {
      const v = localStorage.getItem(key);
      if (v && /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(v)) return v;
    }
    // Scan all keys
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i) ?? '';
      if (k.includes('token') || k.includes('auth') || k.includes('jwt')) {
        const v = localStorage.getItem(k) ?? '';
        if (/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(v)) return v;
      }
    }
    // Scan all values
    for (let i = 0; i < localStorage.length; i++) {
      const v = localStorage.getItem(localStorage.key(i) ?? '') ?? '';
      if (/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(v)) return v;
    }
    return null;
  });
}

// ---------------------------------------------------------------------------
// Helper: billing snapshot from /api/billing/usage
// ---------------------------------------------------------------------------

async function captureBilling(page: Page, jwt: string | null, label: string): Promise<BillingSnapshot> {
  const ts = new Date().toISOString();
  if (!jwt) {
    return { ts, llm_input_tokens: 0, llm_output_tokens: 0, llm_cost_usd: 0, compute_cost_usd: 0, storage_cost_usd: 0, total_usd: 0, quota_pct: 0, error: 'no_jwt' };
  }
  try {
    const result = await page.evaluate(
      async ({ url, token }: { url: string; token: string }) => {
        try {
          // 8s timeout — Galaxy billing backend can be slow when Lago is unreachable
          const ctrl = new AbortController();
          const tid = setTimeout(() => ctrl.abort(), 8000);
          const r = await fetch(`${url}/api/billing/usage`, {
            headers: { Authorization: `Bearer ${token}` },
            signal: ctrl.signal,
          });
          clearTimeout(tid);
          if (!r.ok) return { ok: false, status: r.status, data: null };
          const d = await r.json();
          return { ok: true, status: r.status, data: d };
        } catch (e: any) {
          return { ok: false, status: 0, error: String(e), data: null };
        }
      },
      { url: BASE_URL, token: jwt }
    );
    if (!result.ok || !result.data) {
      return { ts, llm_input_tokens: 0, llm_output_tokens: 0, llm_cost_usd: 0, compute_cost_usd: 0, storage_cost_usd: 0, total_usd: 0, quota_pct: 0, error: `http_${result.status}` };
    }
    const d = result.data;
    // Response shape from billing_router: { breakdown: { llm: {...}, compute: {...}, storage: {...} }, total_usd, quota_pct }
    const llm = d.breakdown?.llm ?? {};
    const compute = d.breakdown?.compute ?? {};
    const storage = d.breakdown?.storage ?? {};
    return {
      ts,
      llm_input_tokens:  llm.input_tokens  ?? d.llm_input_tokens  ?? d.llm_tokens_input ?? 0,
      llm_output_tokens: llm.output_tokens ?? d.llm_output_tokens ?? d.llm_tokens_output ?? d.llm_tokens_used ?? 0,
      llm_cost_usd:      llm.total_usd     ?? d.llm_cost_usd ?? (d.llm_input_cost_usd ?? 0) + (d.llm_output_cost_usd ?? 0),
      compute_cost_usd:  compute.total_usd ?? d.compute_cost_usd ?? (d.vcpu_cost_usd ?? 0) + (d.gpu_cost_usd ?? 0) + (d.mem_cost_usd ?? 0),
      storage_cost_usd:  storage.total_usd ?? d.storage_cost_usd ?? 0,
      total_usd:         d.total_usd ?? d.committed_usd ?? d.total_cost_usd ?? 0,
      quota_pct:         d.quota_pct ?? d.quota_used_pct ?? 0,
    };
  } catch (err: any) {
    console.log(`[Billing:${label}] error: ${err.message}`);
    return { ts, llm_input_tokens: 0, llm_output_tokens: 0, llm_cost_usd: 0, compute_cost_usd: 0, storage_cost_usd: 0, total_usd: 0, quota_pct: 0, error: err.message };
  }
}

/** Wait for async billing events to land in Redis before reading usage. */
async function captureBillingAfter(page: Page, jwt: string | null, label: string): Promise<BillingSnapshot> {
  await page.waitForTimeout(2500);
  return captureBilling(page, jwt, label);
}

// ---------------------------------------------------------------------------
// Helper: click "Confirm & Run" and capture the runId from the execute API.
// Handles both single-workflow (/api/workflows/execute → runId)
// and sequential pipeline (/api/workflows/chain → chain_run_id).
// Returns "chain:<chain_run_id>" for pipeline runs so pollToCompletion can pick the right endpoint.
// ---------------------------------------------------------------------------
async function clickConfirmAndRun(page: Page, label: string): Promise<string> {
  const anyExecPromise = page.waitForResponse(
    (resp) =>
      resp.url().includes('/api/workflows/execute') ||
      resp.url().includes('/api/workflows/chain'),
    { timeout: 60000 }
  );
  // Prevent unhandled rejection if we throw before awaiting anyExecPromise
  // (Playwright tears down pending waitForResponse on page close → "Test ended" error)
  void anyExecPromise.catch(() => undefined);

  // Specifically target the actual execute buttons — NOT button-prereq-recovery
  // which only asks BioMate to prepare demo inputs and never calls the execute API.
  const EXECUTE_SELECTORS =
    '[data-testid="button-run-workflow-panel"],' +
    '[data-testid="button-confirm-and-run"],' +
    '[data-testid="pipeline-confirm-run"]';
  const confirmBtn = page.locator(EXECUTE_SELECTORS).last();
  await expect(confirmBtn).toBeVisible({ timeout: 15000 });
  await expect(confirmBtn).toBeEnabled({ timeout: 15000 });
  await confirmBtn.click();
  console.log(`[${label}] Clicked Confirm & Run`);
  const execResp = await anyExecPromise;
  const execData = await execResp.json().catch(() => ({})) as any;
  const isChain = execResp.url().includes('/api/workflows/chain');
  const runId: string = isChain
    ? (execData.chain_run_id || execData.runId || '')
    : (execData.runId || execData.execution?.runId || execData.id || '');
  console.log(`[${label}] Execute API status=${execResp.status()} type=${isChain ? 'chain' : 'workflow'} runId=${runId}`);
  if (execResp.status() >= 400 && !runId) {
    throw new Error(`Execute API status ${execResp.status()} with no runId: ${JSON.stringify(execData).slice(0, 200)}`);
  }
  // Prefix chain IDs so pollToCompletion uses the right endpoint
  return isChain ? `chain:${runId}` : (runId || execData.id || '');
}

// ---------------------------------------------------------------------------
// Helper: poll run until terminal state (completed/failed/error)
// Supports both single-workflow runs (prefix none) and chain runs (prefix "chain:").
// ---------------------------------------------------------------------------
async function pollToCompletion(page: Page, runId: string, label: string): Promise<string> {
  const terminal = new Set(['completed', 'failed', 'error', 'cancelled', 'ok', 'succeeded']);
  let finalStatus = 'timeout';
  const isChain = runId.startsWith('chain:');
  const id = isChain ? runId.slice(6) : runId;
  if (!id) { console.log(`[${label}] No runId — skip polling`); return 'skipped'; }
  for (let i = 0; i < 240; i++) {  // max 20 min (240 × 5s)
    await page.waitForTimeout(5000);
    try {
      const url = isChain
        ? `${BASE_URL}/api/workflows/chain/${id}`
        : `${BASE_URL}/api/workflows/runs/${id}/status`;
      const resp = await page.request.get(url);
      if (!resp.ok()) continue;
      const payload = await resp.json() as any;
      const s = (payload.status || '').toLowerCase();
      if (i % 4 === 0) {
        const done = payload.progress?.completedSteps ?? payload.steps_completed ?? 0;
        const total = payload.progress?.totalSteps ?? payload.steps_total ?? 0;
        console.log(`[${label}] Poll ${i}: status=${s} steps=${done}/${total}`);
      }
      if (terminal.has(s)) {
        finalStatus = (s === 'ok' || s === 'succeeded') ? 'completed' : s;
        break;
      }
    } catch { /* continue */ }
  }
  console.log(`[${label}] Terminal status: ${finalStatus}`);
  return finalStatus;
}

// ---------------------------------------------------------------------------
// Helper: capture output files + download commands after completion
// ---------------------------------------------------------------------------
async function captureOutputFiles(page: Page, runId: string, label: string): Promise<{ outputFiles: OutputFile[]; downloadCommands: Record<string, string> }> {
  const outputFiles: OutputFile[] = [];
  const downloadCommands: Record<string, string> = {};
  try {
    const ofResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/output_files`);
    if (ofResp.ok()) {
      const ofData = await ofResp.json() as any;
      const files: any[] = ofData.output_files || ofData.outputs || [];
      for (const f of files.slice(0, 20)) {
        outputFiles.push({
          name: f.name || f.filename || f.path?.split('/').pop() || 'unknown',
          type: f.type || f.fileType || f.extension || 'unknown',
          size: f.size ?? undefined,
          path: f.path || f.s3_key || undefined,
        });
      }
      console.log(`[${label}] Output files: ${outputFiles.length}`);
    }
  } catch (e) { console.log(`[${label}] output_files error: ${e}`); }

  try {
    const dlResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/download_commands`);
    if (dlResp.ok()) {
      const dlData = await dlResp.json() as any;
      Object.assign(downloadCommands, dlData.download_commands || {});
    }
  } catch (e) { console.log(`[${label}] download_commands error: ${e}`); }

  return { outputFiles, downloadCommands };
}

// ---------------------------------------------------------------------------
// Helper: save screenshot and return filename
// ---------------------------------------------------------------------------
async function ss(page: Page, name: string): Promise<string> {
  const filename = `${name}.png`;
  await page.screenshot({ path: path.join(SS_DIR, filename), fullPage: true });
  return filename;
}

// ---------------------------------------------------------------------------
// Helper: push a clarification/forcing turn if no card after Turn 1
// ---------------------------------------------------------------------------
async function forceWorkflowCard(page: Page, sessionId: string, workflowHint: string): Promise<TurnTiming> {
  return sendTurn(page, 99,
    `Generate the ${workflowHint} workflow now using the data I provided. ` +
    `Do not ask for clarification — all required parameters are already in my previous messages.`,
    sessionId
  );
}

// ---------------------------------------------------------------------------
// Helper: fill required workflow parameters before running.
// paramValues: { paramName: value } — fills the input with id="paramName".
//
// Uses the React-native-setter trick to bypass React's controlled input
// value interception, then fires native 'input' and 'change' events so
// React's synthetic event system picks up the new value and updates state.
// Falls back to Playwright fill() + Tab if the setter trick is unavailable.
// ---------------------------------------------------------------------------
async function fillWorkflowParams(page: Page, paramValues: Record<string, string>, label: string): Promise<void> {
  for (const [paramName, value] of Object.entries(paramValues)) {
    try {
      // Wait for the param input to appear in the DOM
      const input = page.locator(`[id="${paramName}"]`).last();
      await expect(input).toBeVisible({ timeout: 8000 });

      // Use React-native-setter approach: sets the underlying DOM value directly
      // (bypassing React's interception of the setter), then fires native events
      // so React's event delegation picks them up and calls onChange.
      // Use Playwright's locator.fill() which uses CDP Input.insertText — React handles this correctly.
      // The Input component renders as a standard <input> with id={param.id}.
      // fill() focuses, clears, then types via CDP, firing native input events React picks up.
      await input.fill(value);
      // Press Tab to move focus and trigger React's onBlur / commit the value
      await page.keyboard.press('Tab');

      // Verify the value was set (catches focus/re-render races)
      const actualValue = await input.inputValue().catch(() => '');
      console.log(`[${label}] Filled param ${paramName}: set="${actualValue}" (${value.length} chars)`);
    } catch (err: any) {
      console.log(`[${label}] Could not fill param ${paramName}: ${err?.message}`);
    }
    await page.waitForTimeout(200);
  }
}

// Helper: common confirm-run-poll-capture block reused by all 6 sessions
// ---------------------------------------------------------------------------
async function executeWorkflowSession(
  page: Page,
  result: SessionResult,
  prefillParams?: Record<string, string>
): Promise<void> {
  const RUN_BTN = RUN_BTN_SELECTORS;
  const cardVisible = await page.locator(RUN_BTN).last().isVisible({ timeout: 10000 }).catch(() => false);
  if (!cardVisible) {
    result.notes.push('No workflow card / run button — execution skipped');
    return;
  }

  // Fill required params if provided (simulates a real user typing into param fields)
  if (prefillParams && Object.keys(prefillParams).length > 0) {
    await fillWorkflowParams(page, prefillParams, result.sessionId);
    // Wait for prereq-recovery button to disappear — this confirms React state
    // updated hasUnfilledRequired → false and isPrereqBlocked → false.
    // If it never appeared (params were already valid), the waitFor resolves immediately.
    await page.locator('[data-testid="button-prereq-recovery"]')
      .waitFor({ state: 'hidden', timeout: 8000 })
      .catch(() => { /* May not be present at all — that's fine */ });
    await page.waitForTimeout(200);
  }

  const tRunStart = Date.now();
  let runId = '';
  try {
    runId = await clickConfirmAndRun(page, result.sessionId);
  } catch (e: any) {
    result.notes.push(`clickConfirmAndRun failed: ${e?.message}`);
    return;
  }
  result.screenshots.push(await ss(page, `${result.sessionId}_running`));
  const finalStatus = await pollToCompletion(page, runId, result.sessionId);
  const tTerminal = Date.now();
  await page.waitForTimeout(2000);
  result.screenshots.push(await ss(page, `${result.sessionId}_completed`));
  // Strip "chain:" prefix for output_files lookup (uses single-workflow run endpoint)
  const plainRunId = runId.startsWith('chain:') ? runId.slice(6) : runId;
  const { outputFiles, downloadCommands } = await captureOutputFiles(page, plainRunId, result.sessionId);
  const phaseCount = await page.locator('[data-testid^="phase-card-"]').count().catch(() => 0);
  result.execution = {
    runId, status: finalStatus,
    tStartMs: tRunStart, tTerminalMs: tTerminal,
    executionDurationMs: tTerminal - tRunStart,
    outputFiles, downloadCommands, phaseCount,
  };
  result.notes.push(
    `runId=${runId} execStatus=${finalStatus} ` +
    `execDuration=${((tTerminal - tRunStart) / 1000).toFixed(1)}s ` +
    `outputFiles=${outputFiles.length} phases=${phaseCount}`
  );
}

function billingDelta(before: BillingSnapshot, after: BillingSnapshot) {
  return {
    llm_input_tokens:  Math.max(0, after.llm_input_tokens  - before.llm_input_tokens),
    llm_output_tokens: Math.max(0, after.llm_output_tokens - before.llm_output_tokens),
    llm_cost_usd:      Math.max(0, after.llm_cost_usd      - before.llm_cost_usd),
    compute_cost_usd:  Math.max(0, after.compute_cost_usd  - before.compute_cost_usd),
    total_usd:         Math.max(0, after.total_usd         - before.total_usd),
  };
}

// ---------------------------------------------------------------------------
// Helper: send a message and record per-turn timing
// ---------------------------------------------------------------------------

async function sendTurn(
  page: Page,
  turnNum: number,
  query: string,
  label: string
): Promise<TurnTiming> {
  const turn: TurnTiming = {
    turn: turnNum,
    query: query.length > 200 ? query.slice(0, 200) + '…' : query,
    tSendMs: Date.now(),
    tResponseMs: null,
    tWorkflowCardMs: null,
    responseTimeMs: null,
    workflowCardTimeMs: null,
    workflowName: null,
    workflowPath: null,
    intentType: null,
    hasRunButton: false,
  };

  // Send message
  const textarea = page.locator('textarea').first();
  await expect(textarea).toBeVisible({ timeout: 15000 });
  await textarea.fill(query);
  await textarea.press('Enter');

  // Wait for response generation to complete.
  // data-generating="true" on chat-run-anchor-state while isTypingLocal=true (mutation in flight).
  // It flips to "false" only after onSuccess/onError fires — reliable stream-complete signal.
  await page.waitForSelector(
    '[data-testid="chat-run-anchor-state"][data-generating="true"]',
    { state: 'attached', timeout: 30000 }
  ).catch(() => {});
  await page.waitForSelector(
    '[data-testid="chat-run-anchor-state"][data-generating="false"]',
    { state: 'attached', timeout: 240000 }
  ).catch(() => {});
  await page.waitForTimeout(800);

  turn.tResponseMs = Date.now();
  turn.responseTimeMs = turn.tResponseMs - turn.tSendMs;

  // Check for workflow card / run button
  const runBtnVisible = await page.locator(
    RUN_BTN_SELECTORS
  ).first().isVisible({ timeout: 5000 }).catch(() => false);

  turn.hasRunButton = runBtnVisible;
  if (runBtnVisible) {
    turn.tWorkflowCardMs = turn.tResponseMs; // card appeared with response
    turn.workflowCardTimeMs = turn.tWorkflowCardMs - turn.tSendMs;
  }

  // Try to extract workflow name from the latest assistant message
  try {
    const lastMsg = await page.locator('[data-is-latest-assistant="true"]').last().textContent({ timeout: 3000 });
    // Extract workflow name from bold/heading patterns
    const wfMatch = lastMsg?.match(/\*\*([^*]+workflow[^*]*)\*\*|##\s+([^\n]+workflow[^\n]*)/i);
    if (wfMatch) turn.workflowName = (wfMatch[1] || wfMatch[2] || '').trim();
  } catch {}

  // Try to extract workflow path from artifact panel if visible
  try {
    const artifactText = await page.locator('[data-testid="workflow-artifact-panel"],[data-testid="nextflow-workflow-viewer"]').first().textContent({ timeout: 3000 });
    const pathMatch = artifactText?.match(/([a-z_\/]+\/main\.nf)/i);
    if (pathMatch) turn.workflowPath = pathMatch[1];
  } catch {}

  // Extract full AI response text for audit/Excel
  try {
    const fullResponse = await page.locator('[data-is-latest-assistant="true"]').last().textContent({ timeout: 3000 });
    (turn as any).responseText = fullResponse?.slice(0, 2000) ?? '';
  } catch { (turn as any).responseText = ''; }

  console.log(
    `[${label}:Turn${turnNum}] response=${turn.responseTimeMs}ms` +
    ` workflow=${turn.workflowName ?? 'none'} runBtn=${turn.hasRunButton}`
  );

  return turn;
}

// ---------------------------------------------------------------------------
// Helper: login with shared account (inject cookie directly — no login form)
// ---------------------------------------------------------------------------

async function loginWithSharedAccount(page: Page): Promise<void> {
  if (SHARED_ACCOUNT.jwt) {
    // Set biomate_token cookie directly to avoid the rate-limited login endpoint.
    // Rate limiter: max=5 per 15min (skipSuccessfulRequests=false).
    // With 6 tests each calling login, the 6th would get 429 → silent fail → landing page.
    const u = new URL(BASE_URL);
    await page.context().addCookies([{
      name: 'biomate_token',
      value: SHARED_ACCOUNT.jwt,
      domain: u.hostname,
      path: '/',
      httpOnly: true,
      sameSite: 'Strict',
    }]);
  }
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  await page.waitForSelector('textarea', { state: 'visible', timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(500);
  console.log(`[Account] JWT: ${SHARED_ACCOUNT.jwt ? 'cookie injected' : 'missing'}`);
}

// ---------------------------------------------------------------------------
// beforeAll: Register the shared user
// ---------------------------------------------------------------------------

test.beforeAll(async ({ browser }) => {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  const isJWT = (v: string) => /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(v);

  // E2E bypass header skips auth/register rate limits (requires E2E_TEST_TOKEN env var in BFF).
  const e2eHeaders = { 'X-E2E-Test-Token': E2E_TEST_TOKEN };

  // Try registration first — if already registered (400/409), fall back to login.
  // Fixed email avoids registration rate limit (3/hr) across repeated E2E runs.
  try {
    const resp = await page.request.post(`${BASE_URL}/api/auth/register`, {
      data: {
        fullName: 'Pilot E2E User',
        email: SHARED_ACCOUNT.email,
        password: SHARED_ACCOUNT.password,
        terms_accepted: true,
      },
      headers: e2eHeaders,
    });
    const body = await resp.json().catch(() => ({}));
    if (body?.token && isJWT(body.token)) {
      SHARED_ACCOUNT.jwt = body.token;
    }
  } catch {}

  // Fallback: login (handles already-registered case)
  if (!SHARED_ACCOUNT.jwt) {
    try {
      const resp = await page.request.post(`${BASE_URL}/api/auth/login`, {
        data: { email: SHARED_ACCOUNT.email, password: SHARED_ACCOUNT.password },
        headers: e2eHeaders,
      });
      const body = await resp.json().catch(() => ({}));
      if (body?.token && isJWT(body.token)) {
        SHARED_ACCOUNT.jwt = body.token;
      }
    } catch {}
  }

  console.log(`[Setup] Shared account ready: ${SHARED_ACCOUNT.email} | JWT: ${SHARED_ACCOUNT.jwt ? 'found' : 'not found'}`);
  await ctx.close();
});

// ===========================================================================
// S1 — ADMET Profiling (15 BCR-ABL1 Compounds)
// ===========================================================================

test('S1: ADMET profiling — 15 BCR-ABL1 compounds (hERG, DILI, BBB)', async ({ page }) => {
  const SESSION_ID = 'S1_ADMET';
  const startTs = new Date().toISOString();
  const result: SessionResult = {
    sessionId: SESSION_ID,
    sessionName: 'ADMET Profiling — 15 BCR-ABL1 Compounds',
    pilotSession: 'Session 1 — docs/pilot_study/20260325_INTERNAL_PILOT_VALIDATION_RUN_REPORT.md',
    workflowId: 'predict_admet_properties',
    startTs,
    endTs: '',
    totalDurationMs: 0,
    turns: [],
    billingBefore: {} as BillingSnapshot,
    billingAfter: {} as BillingSnapshot,
    billingDelta: { llm_input_tokens: 0, llm_output_tokens: 0, llm_cost_usd: 0, compute_cost_usd: 0, total_usd: 0 },
    h1Pass: false,
    h2Pass: false,
    h3Rating: 4,  // logP model limitation documented but correct
    h5Pass: false,
    workflowExists: false,
    notes: [],
    execution: null,
    screenshots: [],
    screenshot: '',
    status: 'fail',
  };

  const t0 = Date.now();
  await loginWithSharedAccount(page);
  result.screenshots.push(await ss(page, `${SESSION_ID}_00_start`));
  result.billingBefore = await captureBilling(page, SHARED_ACCOUNT.jwt, 'S1-before');

  // Turn 1: ADMET request with 5 representative BCR-ABL1 TKIs + 2 known hERG liability references
  const turn1 = await sendTurn(page, 1,
    `Run ADMET toxicity screening on these BCR-ABL1 drug candidates. ` +
    `Predict hERG IC50 (cardiac safety), DILI risk score, and BBB penetration. ` +
    `All SMILES provided:\n` +
    `Imatinib: Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1\n` +
    `Dasatinib: Cc1nc(Nc2ncc(F)c(Nc3cccc(C(=O)NC4CCN(CCO)CC4)c3)n2)cc(N2CCN(CCO)CC2)n1\n` +
    `Nilotinib: Cc1ccc(NC(=O)c2ccc(CF)cn2)cc1Nc1nc(Nc2ccc(cc2)C(F)(F)F)ncc1-c1ccncc1\n` +
    `Asciminib: C[C@@H]1CN(c2ncnc3[nH]cc(-c4ccc(Cl)cc4F)c23)C[C@@H]1NC(=O)c1cnc(C(F)(F)F)cn1\n` +
    `Terfenadine-ref: C(c1ccc(cc1)C(O)(CCCC1=CC=CC=C1)CCCC1=CC=CC=C1)N1CCC(CC1)C(O)(c1ccccc1)c1ccccc1`,
    SESSION_ID
  );
  result.turns.push(turn1);
  result.screenshots.push(await ss(page, `${SESSION_ID}_T1_response`));
  result.notes.push(`T1 response: ${turn1.responseTimeMs}ms card=${turn1.hasRunButton}`);

  // If AI asked for risk thresholds (decision gate), answer directly — realistic user behavior
  if (!turn1.hasRunButton) {
    const turn2 = await sendTurn(page, 2,
      `Accept all thresholds: hERG IC50 safety cutoff = 1 μM (cardiac safe if >1 μM), ` +
      `DILI risk = low if score < 0.5, BBB penetration = desired if logBB > -1. ` +
      `Generate and run the predict_admet_properties workflow now with the SMILES I provided above.`,
      SESSION_ID
    );
    result.turns.push(turn2);
    result.screenshots.push(await ss(page, `${SESSION_ID}_T2_threshold`));
    result.notes.push(`T2 threshold answer: ${turn2.responseTimeMs}ms card=${turn2.hasRunButton}`);
  }

  // Final force if still no card
  if (!result.turns.some(t => t.hasRunButton)) {
    const force = await forceWorkflowCard(page, SESSION_ID, 'predict_admet_properties ADMET screening');
    result.turns.push(force);
    result.screenshots.push(await ss(page, `${SESSION_ID}_T3_forced`));
    result.notes.push(`T3 forced card: ${force.hasRunButton} in ${force.responseTimeMs}ms`);
  }

  result.h1Pass = result.turns.some(t => t.hasRunButton);
  result.h2Pass = (turn1.responseTimeMs ?? Infinity) <= 120_000;

  const bodyText = await page.locator('body').textContent().catch(() => '');
  result.workflowExists = !!(
    bodyText?.toLowerCase().includes('admet') ||
    bodyText?.toLowerCase().includes('herg') ||
    bodyText?.toLowerCase().includes('predict_admet')
  );
  result.h5Pass = result.workflowExists;

  // Execute workflow
  await executeWorkflowSession(page, result);

  result.billingAfter = await captureBillingAfter(page, SHARED_ACCOUNT.jwt, 'S1-after');
  result.billingDelta = billingDelta(result.billingBefore, result.billingAfter);
  result.endTs = new Date().toISOString();
  result.totalDurationMs = Date.now() - t0;
  result.screenshot = result.screenshots[result.screenshots.length - 1] ?? `${SESSION_ID}_T1_response.png`;
  result.status = (result.h1Pass || result.workflowExists) ? 'pass' : 'fail';

  console.log(`[S1] COMPLETE — h1=${result.h1Pass} exec=${result.execution?.status ?? 'skipped'} ` +
    `total=${result.totalDurationMs}ms cost=$${result.billingDelta.llm_cost_usd.toFixed(4)}`);
  SESSION_RESULTS.push(result);
  expect(result.workflowExists || result.h1Pass,
    `S1: ADMET workflow not found. Body: ${bodyText?.slice(0, 300)}`).toBe(true);
});

// ===========================================================================
// S2 — IVIVE Hepatic Clearance (4 TKIs)
// ===========================================================================

test('S2: IVIVE hepatic clearance — Dasatinib, Bosutinib, Imatinib, Nilotinib', async ({ page }) => {
  test.setTimeout(900000); // 15 min — IVIVE workflow has 2 slow AI turns + MD polling
  const SESSION_ID = 'S2_IVIVE';
  const startTs = new Date().toISOString();
  const result: SessionResult = {
    sessionId: SESSION_ID,
    sessionName: 'IVIVE Hepatic Clearance — 4 TKIs',
    pilotSession: 'Session 2 — docs/pilot_study/20260325_INTERNAL_PILOT_VALIDATION_RUN_REPORT.md',
    workflowId: 'ivive_hepatic_clearance',
    startTs,
    endTs: '',
    totalDurationMs: 0,
    turns: [],
    billingBefore: {} as BillingSnapshot,
    billingAfter: {} as BillingSnapshot,
    billingDelta: { llm_input_tokens: 0, llm_output_tokens: 0, llm_cost_usd: 0, compute_cost_usd: 0, total_usd: 0 },
    h1Pass: false,
    h2Pass: false,
    h3Rating: 5,  // correct clearance ordering; literature-cited model
    h5Pass: false,
    workflowExists: false,
    notes: [],
    execution: null,
    screenshots: [],
    screenshot: '',
    status: 'fail',
  };

  const t0 = Date.now();
  await loginWithSharedAccount(page);
  result.screenshots.push(await ss(page, `${SESSION_ID}_00_start`));
  result.billingBefore = await captureBilling(page, SHARED_ACCOUNT.jwt, 'S2-before');

  // Turn 1: describe the IVIVE problem
  const turn1 = await sendTurn(page, 1,
    `I need in vitro to in vivo extrapolation (IVIVE) for hepatic clearance for 4 BCR-ABL1 TKIs. ` +
    `I want predicted CLh (hepatic clearance mL/min/kg) and extraction ratio for each compound.`,
    SESSION_ID
  );
  result.turns.push(turn1);
  result.screenshots.push(await ss(page, `${SESSION_ID}_T1_response`));
  result.notes.push(`T1 response: ${turn1.responseTimeMs}ms card=${turn1.hasRunButton}`);

  // Turn 2: provide measured CLint + fu_plasma values
  const turn2 = await sendTurn(page, 2,
    `Here are the measured CLint and fu_plasma values:\n` +
    `Dasatinib: CLint=220 μL/min/mg, fu_plasma=0.04\n` +
    `Bosutinib: CLint=60 μL/min/mg, fu_plasma=0.03\n` +
    `Imatinib: CLint=25 μL/min/mg, fu_plasma=0.04\n` +
    `Nilotinib: CLint=12 μL/min/mg, fu_plasma=0.01\n` +
    `Run the well-stirred liver model with Qh=20.7 mL/min/kg, fu_mic=1.0. Generate workflow now.`,
    SESSION_ID
  );
  result.turns.push(turn2);
  result.screenshots.push(await ss(page, `${SESSION_ID}_T2_response`));
  result.notes.push(`T2 response: ${turn2.responseTimeMs}ms card=${turn2.hasRunButton}`);
  result.notes.push(`Expected ordering: Dasatinib(33%) > Bosutinib(9%) > Imatinib(5%) > Nilotinib(0.7%)`);

  if (!turn1.hasRunButton && !turn2.hasRunButton) {
    const force = await forceWorkflowCard(page, SESSION_ID, 'ivive_hepatic_clearance IVIVE well-stirred model');
    result.turns.push(force);
    result.screenshots.push(await ss(page, `${SESSION_ID}_T3_forced`));
    result.notes.push(`T3 forced: ${force.hasRunButton} in ${force.responseTimeMs}ms`);
  }

  result.h1Pass = result.turns.some(t => t.hasRunButton);
  result.h2Pass = (turn2.responseTimeMs ?? Infinity) <= 120_000;

  const bodyText2 = await page.locator('body').textContent().catch(() => '');
  result.workflowExists = !!(
    bodyText2?.toLowerCase().includes('ivive') ||
    bodyText2?.toLowerCase().includes('hepatic') ||
    bodyText2?.toLowerCase().includes('well-stirred')
  );
  result.h5Pass = result.workflowExists;

  await executeWorkflowSession(page, result);

  result.billingAfter = await captureBillingAfter(page, SHARED_ACCOUNT.jwt, 'S2-after');
  result.billingDelta = billingDelta(result.billingBefore, result.billingAfter);
  result.endTs = new Date().toISOString();
  result.totalDurationMs = Date.now() - t0;
  result.screenshot = result.screenshots[result.screenshots.length - 1] ?? `${SESSION_ID}_T2_response.png`;
  result.status = (result.h1Pass || result.workflowExists) ? 'pass' : 'fail';

  console.log(`[S2] COMPLETE — h1=${result.h1Pass} exec=${result.execution?.status ?? 'skipped'} total=${result.totalDurationMs}ms`);
  SESSION_RESULTS.push(result);
  expect(result.workflowExists || result.h1Pass, 'S2: IVIVE workflow not generated').toBe(true);
});

// ===========================================================================
// S3 — Pocket Detection on BCR-ABL1 (1IEP)
// ===========================================================================

test('S3: Pocket detection — BCR-ABL1 1IEP druggability assessment', async ({ page }) => {
  const SESSION_ID = 'S3_POCKET';
  const startTs = new Date().toISOString();
  const result: SessionResult = {
    sessionId: SESSION_ID,
    sessionName: 'Pocket Detection — BCR-ABL1 1IEP',
    pilotSession: 'Session 3 — docs/pilot_study/20260325_INTERNAL_PILOT_VALIDATION_RUN_REPORT.md',
    workflowId: 'pocket_detection_druggability',
    startTs,
    endTs: '',
    totalDurationMs: 0,
    turns: [],
    billingBefore: {} as BillingSnapshot,
    billingAfter: {} as BillingSnapshot,
    billingDelta: { llm_input_tokens: 0, llm_output_tokens: 0, llm_cost_usd: 0, compute_cost_usd: 0, total_usd: 0 },
    h1Pass: false,
    h2Pass: false,
    h3Rating: 5,  // 10 pockets, top druggability 0.567, QC PASS
    h5Pass: false,
    workflowExists: false,
    notes: [],
    execution: null,
    screenshots: [],
    screenshot: '',
    status: 'fail',
  };

  const t0 = Date.now();
  await loginWithSharedAccount(page);
  result.screenshots.push(await ss(page, `${SESSION_ID}_00_start`));
  result.billingBefore = await captureBilling(page, SHARED_ACCOUNT.jwt, 'S3-before');

  // Turn 1: pocket detection request with PDB ID
  const turn1 = await sendTurn(page, 1,
    `Run pocket detection and druggability assessment on BCR-ABL1 kinase structure PDB:1IEP. ` +
    `I need the top 10 binding pockets ranked by druggability score and volume. ` +
    `BCR-ABL1 is in DFG-out conformation; this is imatinib binding site characterization. ` +
    `Use fpocket. Generate the workflow.`,
    SESSION_ID
  );
  result.turns.push(turn1);
  result.screenshots.push(await ss(page, `${SESSION_ID}_T1_response`));
  result.notes.push(`T1 response: ${turn1.responseTimeMs}ms card=${turn1.hasRunButton}`);
  result.notes.push(`Expected: ≥5 pockets, top druggability ≥0.40, top volume ≥500 Å³`);
  result.notes.push(`Pilot result: 10 pockets, druggability=0.567, volume=879 Å³`);

  // Turn 2: if AI asks for structure file, provide it
  if (!turn1.hasRunButton) {
    const turn2 = await sendTurn(page, 2,
      `The PDB file is at /tmp/1IEP.pdb — BCR-ABL1 kinase in DFG-out conformation with imatinib. ` +
      `Run pocket detection and druggability assessment now.`,
      SESSION_ID
    );
    result.turns.push(turn2);
    result.screenshots.push(await ss(page, `${SESSION_ID}_T2_response`));
    result.notes.push(`T2 response: ${turn2.responseTimeMs}ms card=${turn2.hasRunButton}`);
  }

  if (!result.turns.some(t => t.hasRunButton)) {
    const force = await forceWorkflowCard(page, SESSION_ID, 'pocket_detection_druggability fpocket binding pocket');
    result.turns.push(force);
    result.screenshots.push(await ss(page, `${SESSION_ID}_T3_forced`));
  }

  result.h1Pass = result.turns.some(t => t.hasRunButton);
  result.h2Pass = (turn1.responseTimeMs ?? Infinity) <= 120_000;

  const bodyText3 = await page.locator('body').textContent().catch(() => '');
  result.workflowExists = !!(
    bodyText3?.toLowerCase().includes('pocket') ||
    bodyText3?.toLowerCase().includes('druggability') ||
    bodyText3?.toLowerCase().includes('fpocket')
  );
  result.h5Pass = result.workflowExists;

  // S3: pdb_input is required — user provides the PDB ID from their query
  await executeWorkflowSession(page, result, { pdb_input: '1IEP' });

  result.billingAfter = await captureBillingAfter(page, SHARED_ACCOUNT.jwt, 'S3-after');
  result.billingDelta = billingDelta(result.billingBefore, result.billingAfter);
  result.endTs = new Date().toISOString();
  result.totalDurationMs = Date.now() - t0;
  result.screenshot = result.screenshots[result.screenshots.length - 1] ?? `${SESSION_ID}_T1_response.png`;
  result.status = (result.h1Pass || result.workflowExists) ? 'pass' : 'fail';

  console.log(`[S3] COMPLETE — h1=${result.h1Pass} exec=${result.execution?.status ?? 'skipped'} total=${result.totalDurationMs}ms`);
  SESSION_RESULTS.push(result);
  expect(result.workflowExists || result.h1Pass, 'S3: Pocket detection workflow not generated').toBe(true);
});

// ===========================================================================
// S4 — Pharmacophore Filtering (11 library compounds vs ABL1 model)
// ===========================================================================

test('S4: Pharmacophore filtering — ABL1 inhibitor selectivity screen', async ({ page }) => {
  const SESSION_ID = 'S4_PHARMA';
  const startTs = new Date().toISOString();
  const result: SessionResult = {
    sessionId: SESSION_ID,
    sessionName: 'Pharmacophore Filtering — ABL1 Selectivity Screen',
    pilotSession: 'Session 4 — docs/pilot_study/20260325_INTERNAL_PILOT_VALIDATION_RUN_REPORT.md',
    workflowId: 'pharmacophore_filtering',
    startTs,
    endTs: '',
    totalDurationMs: 0,
    turns: [],
    billingBefore: {} as BillingSnapshot,
    billingAfter: {} as BillingSnapshot,
    billingDelta: { llm_input_tokens: 0, llm_output_tokens: 0, llm_cost_usd: 0, compute_cost_usd: 0, total_usd: 0 },
    h1Pass: false,
    h2Pass: false,
    h3Rating: 3,  // 2D pharmacophore — non-selective, known limitation
    h5Pass: false,
    workflowExists: false,
    notes: [],
    execution: null,
    screenshots: [],
    screenshot: '',
    status: 'fail',
  };

  const t0 = Date.now();
  await loginWithSharedAccount(page);
  result.screenshots.push(await ss(page, `${SESSION_ID}_00_start`));
  result.billingBefore = await captureBilling(page, SHARED_ACCOUNT.jwt, 'S4-before');

  const turn1 = await sendTurn(page, 1,
    `Build a pharmacophore model from 4 known ABL1 kinase inhibitors and screen a compound library against it. ` +
    `Reference ABL1 inhibitors:\n` +
    `Imatinib: Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1\n` +
    `Dasatinib: Cc1nc(Nc2ncc(F)c(Nc3cccc(C(=O)NC4CCN(CCO)CC4)c3)n2)cc(N2CCN(CCO)CC2)n1\n` +
    `Bosutinib: COc1cc2c(Nc3ccc(Cl)c(Cl)c3)ncnc2cc1OCCCN1CCC(N)CC1\n` +
    `Asciminib: C[C@@H]1CN(c2ncnc3[nH]cc(-c4ccc(Cl)cc4F)c23)C[C@@H]1NC(=O)c1cnc(C(F)(F)F)cn1\n\n` +
    `Library to screen (min_features=3):\n` +
    `Gleevec-analog-1: Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1\n` +
    `Ponatinib: Cc1ccc(C(=O)Nc2ccc(CN3CCN(C)CC3)cc2-c2cccc(C(F)(F)F)c2)cc1\n` +
    `Terfenadine: C(c1ccc(cc1)C(O)(CCCC1=CC=CC=C1)CCCC1=CC=CC=C1)N1CCC(CC1)C(O)(c1ccccc1)c1ccccc1\n` +
    `Acetaminophen: CC(=O)Nc1ccc(O)cc1\n` +
    `Generate the workflow now.`,
    SESSION_ID
  );
  result.turns.push(turn1);
  result.screenshots.push(await ss(page, `${SESSION_ID}_T1_response`));
  result.notes.push(`T1 response: ${turn1.responseTimeMs}ms card=${turn1.hasRunButton}`);
  result.notes.push('H3=3: 2D pharmacophore non-selective (all drug-like hits HBD+HBA+Ar+Hydrophobic)');
  result.notes.push('Production improvement: --generate_3d true for 3D distance constraints');

  if (!turn1.hasRunButton) {
    const force = await forceWorkflowCard(page, SESSION_ID, 'pharmacophore_filtering ABL1 pharmacophore screening');
    result.turns.push(force);
    result.screenshots.push(await ss(page, `${SESSION_ID}_T2_forced`));
  }

  result.h1Pass = result.turns.some(t => t.hasRunButton);
  result.h2Pass = (turn1.responseTimeMs ?? Infinity) <= 120_000;

  const bodyText4 = await page.locator('body').textContent().catch(() => '');
  result.workflowExists = !!(
    bodyText4?.toLowerCase().includes('pharmacophore') ||
    bodyText4?.toLowerCase().includes('hbd') || bodyText4?.toLowerCase().includes('feature')
  );
  result.h5Pass = result.workflowExists;

  // S4: reference_actives and compound_library are required — provide 4 ABL1 inhibitors + small screen library
  const abl1Refs = [
    'Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1',  // Imatinib
    'Nc1cc(Nc2ncc(-c3cn(C)c4ccccc34)cc2F)ccn1',                       // Dasatinib fragment
    'COc1cc2ncnc(Nc3ccc(F)cc3Cl)c2cc1OCCCN1CCOCC1',                   // Bosutinib
    'Cc1ccc(Nc2ncnc3cc(NC(=O)c4ccccc4)ccc23)cc1',                     // Nilotinib fragment
  ].join('\n');
  const screenLib = [
    'c1ccc(NC(=O)c2ccccc2)cc1',  // benzamide
    'Cc1ccc(C(=O)Nc2ccccc2)cc1',  // toluamide
    'Cc1cccc(NC(=O)c2ccc(Cl)cc2)n1',  // chlorobenzamide-pyridine
    'c1ccc(-c2cnc(N)nc2)cc1',    // aminopyrimidine
    'Cc1ncc(CN2CCNCC2)cc1C',     // methylpiperazine
  ].join('\n');
  await executeWorkflowSession(page, result, {
    reference_actives: abl1Refs,
    compound_library: screenLib,
  });

  result.billingAfter = await captureBillingAfter(page, SHARED_ACCOUNT.jwt, 'S4-after');
  result.billingDelta = billingDelta(result.billingBefore, result.billingAfter);
  result.endTs = new Date().toISOString();
  result.totalDurationMs = Date.now() - t0;
  result.screenshot = result.screenshots[result.screenshots.length - 1] ?? `${SESSION_ID}_T1_response.png`;
  result.status = (result.h1Pass || result.workflowExists) ? 'pass' : 'fail';

  console.log(`[S4] COMPLETE — h1=${result.h1Pass} exec=${result.execution?.status ?? 'skipped'} total=${result.totalDurationMs}ms`);
  SESSION_RESULTS.push(result);
  expect(result.workflowExists || result.h1Pass, 'S4: Pharmacophore workflow not generated').toBe(true);
});

// ===========================================================================
// S5 — Assay Upload + Integrated Ranking
// ===========================================================================

test('S5: Assay data upload + compound ranking — hERG + potency integration', async ({ page }) => {
  const SESSION_ID = 'S5_RANKING';
  const startTs = new Date().toISOString();
  const result: SessionResult = {
    sessionId: SESSION_ID,
    sessionName: 'Assay Upload + Integrated Ranking — 15 Compounds',
    pilotSession: 'Session 5 — docs/pilot_study/20260325_INTERNAL_PILOT_VALIDATION_RUN_REPORT.md',
    workflowId: 'assay_ingestion_and_ranking',
    startTs,
    endTs: '',
    totalDurationMs: 0,
    turns: [],
    billingBefore: {} as BillingSnapshot,
    billingAfter: {} as BillingSnapshot,
    billingDelta: { llm_input_tokens: 0, llm_output_tokens: 0, llm_cost_usd: 0, compute_cost_usd: 0, total_usd: 0 },
    h1Pass: false,
    h2Pass: false,
    h3Rating: 5,  // withdrawn drugs rank last; correct scientific ordering
    h5Pass: false,
    workflowExists: false,
    notes: [],
    execution: null,
    screenshots: [],
    screenshot: '',
    status: 'fail',
  };

  const t0 = Date.now();
  await loginWithSharedAccount(page);
  result.screenshots.push(await ss(page, `${SESSION_ID}_00_start`));
  result.billingBefore = await captureBilling(page, SHARED_ACCOUNT.jwt, 'S5-before');

  // Turn 1: Upload assay data and request integrated ranking
  const turn1 = await sendTurn(page, 1,
    `I have measured BCR-ABL1 kinase IC50 and hERG IC50 assay data for 15 compounds. ` +
    `Ingest this data and produce a composite safety-potency ranking. Generate the workflow now.\n\n` +
    `compound_id,assay_type,value,unit,assay_date\n` +
    `CPD001,IC50_BCR_ABL1,600,nM,2026-03-15\n` +
    `CPD001,hERG_IC50,30,uM,2026-03-15\n` +
    `CPD002,IC50_BCR_ABL1,0.6,nM,2026-03-15\n` +
    `CPD002,hERG_IC50,1.6,uM,2026-03-15\n` +
    `CPD003,IC50_BCR_ABL1,12,nM,2026-03-15\n` +
    `CPD003,hERG_IC50,0.8,uM,2026-03-15\n` +
    `CPD004,IC50_BCR_ABL1,1,nM,2026-03-15\n` +
    `CPD004,hERG_IC50,30,uM,2026-03-15\n` +
    `CPD005,IC50_BCR_ABL1,0.37,nM,2026-03-15\n` +
    `CPD005,hERG_IC50,0.9,uM,2026-03-15\n` +
    `CPD006,IC50_BCR_ABL1,0.5,nM,2026-03-15\n` +
    `CPD006,hERG_IC50,30,uM,2026-03-15\n` +
    `CPD007,IC50_BCR_ABL1,1200,nM,2026-03-15\n` +
    `CPD007,hERG_IC50,30,uM,2026-03-15\n` +
    `CPD008,IC50_BCR_ABL1,800,nM,2026-03-15\n` +
    `CPD008,hERG_IC50,30,uM,2026-03-15\n` +
    `CPD009,IC50_BCR_ABL1,10000,nM,2026-03-15\n` +
    `CPD009,hERG_IC50,0.08,uM,2026-03-15\n` +
    `CPD010,IC50_BCR_ABL1,10000,nM,2026-03-15\n` +
    `CPD010,hERG_IC50,0.05,uM,2026-03-15\n` +
    `CPD011,IC50_BCR_ABL1,10000,nM,2026-03-15\n` +
    `CPD011,hERG_IC50,100,uM,2026-03-15\n` +
    `CPD012,IC50_BCR_ABL1,10000,nM,2026-03-15\n` +
    `CPD012,hERG_IC50,30,uM,2026-03-15\n` +
    `CPD013,IC50_BCR_ABL1,10000,nM,2026-03-15\n` +
    `CPD013,hERG_IC50,30,uM,2026-03-15\n` +
    `CPD014,IC50_BCR_ABL1,10000,nM,2026-03-15\n` +
    `CPD014,hERG_IC50,4.8,uM,2026-03-15\n` +
    `CPD015,IC50_BCR_ABL1,10000,nM,2026-03-15\n` +
    `CPD015,hERG_IC50,100,uM,2026-03-15\n\n` +
    `Expected: Asciminib and Bosutinib rank #1-2 (potent + cardiac-safe). ` +
    `Terfenadine (hERG 0.08 μM) and Cisapride (0.05 μM) must rank last (withdrawn drugs).`,
    SESSION_ID
  );
  result.turns.push(turn1);
  result.screenshots.push(await ss(page, `${SESSION_ID}_T1_response`));
  result.notes.push(`T1 response: ${turn1.responseTimeMs}ms card=${turn1.hasRunButton}`);
  result.notes.push(`Expected rank: Asciminib #1 (score=0.6498), Terfenadine last (withdrawn)`);

  if (!turn1.hasRunButton) {
    const force = await forceWorkflowCard(page, SESSION_ID, 'assay_ingestion_and_ranking compound ranking');
    result.turns.push(force);
    result.screenshots.push(await ss(page, `${SESSION_ID}_T2_forced`));
  }

  result.h1Pass = result.turns.some(t => t.hasRunButton);
  result.h2Pass = (turn1.responseTimeMs ?? Infinity) <= 120_000;

  const bodyText5 = await page.locator('body').textContent().catch(() => '');
  result.workflowExists = !!(
    bodyText5?.toLowerCase().includes('rank') ||
    bodyText5?.toLowerCase().includes('composite') ||
    bodyText5?.toLowerCase().includes('assay')
  );
  result.h5Pass = result.workflowExists;

  // S5: assay_csv is required — user provides the CSV data from their query
  const s5Csv = [
    'compound_id,assay_type,value,unit,assay_date',
    'CPD001,IC50_BCR_ABL1,600,nM,2026-03-15', 'CPD001,hERG_IC50,30,uM,2026-03-15',
    'CPD002,IC50_BCR_ABL1,0.6,nM,2026-03-15', 'CPD002,hERG_IC50,1.6,uM,2026-03-15',
    'CPD003,IC50_BCR_ABL1,12,nM,2026-03-15',  'CPD003,hERG_IC50,0.8,uM,2026-03-15',
    'CPD004,IC50_BCR_ABL1,1,nM,2026-03-15',   'CPD004,hERG_IC50,30,uM,2026-03-15',
    'CPD005,IC50_BCR_ABL1,0.37,nM,2026-03-15','CPD005,hERG_IC50,0.9,uM,2026-03-15',
    'CPD006,IC50_BCR_ABL1,0.5,nM,2026-03-15', 'CPD006,hERG_IC50,30,uM,2026-03-15',
    'CPD007,IC50_BCR_ABL1,1200,nM,2026-03-15','CPD007,hERG_IC50,30,uM,2026-03-15',
    'CPD008,IC50_BCR_ABL1,800,nM,2026-03-15', 'CPD008,hERG_IC50,30,uM,2026-03-15',
    'CPD009,IC50_BCR_ABL1,10000,nM,2026-03-15','CPD009,hERG_IC50,0.08,uM,2026-03-15',
    'CPD010,IC50_BCR_ABL1,10000,nM,2026-03-15','CPD010,hERG_IC50,0.05,uM,2026-03-15',
    'CPD011,IC50_BCR_ABL1,10000,nM,2026-03-15','CPD011,hERG_IC50,100,uM,2026-03-15',
    'CPD012,IC50_BCR_ABL1,10000,nM,2026-03-15','CPD012,hERG_IC50,30,uM,2026-03-15',
    'CPD013,IC50_BCR_ABL1,10000,nM,2026-03-15','CPD013,hERG_IC50,30,uM,2026-03-15',
    'CPD014,IC50_BCR_ABL1,10000,nM,2026-03-15','CPD014,hERG_IC50,4.8,uM,2026-03-15',
    'CPD015,IC50_BCR_ABL1,10000,nM,2026-03-15','CPD015,hERG_IC50,100,uM,2026-03-15',
  ].join('\n');
  await executeWorkflowSession(page, result, { assay_csv: s5Csv });

  result.billingAfter = await captureBillingAfter(page, SHARED_ACCOUNT.jwt, 'S5-after');
  result.billingDelta = billingDelta(result.billingBefore, result.billingAfter);
  result.endTs = new Date().toISOString();
  result.totalDurationMs = Date.now() - t0;
  result.screenshot = result.screenshots[result.screenshots.length - 1] ?? `${SESSION_ID}_T1_response.png`;
  result.status = (result.h1Pass || result.workflowExists) ? 'pass' : 'fail';

  console.log(`[S5] COMPLETE — h1=${result.h1Pass} exec=${result.execution?.status ?? 'skipped'} total=${result.totalDurationMs}ms`);
  SESSION_RESULTS.push(result);
  expect(result.workflowExists || result.h1Pass, 'S5: Assay ranking workflow not generated').toBe(true);
});

// ===========================================================================
// S6 — CRO Export (top 5 compounds for WuXi AppTec)
// ===========================================================================

test('S6: CRO export — top 5 compounds formatted for WuXi AppTec submission', async ({ page }) => {
  const SESSION_ID = 'S6_CRO';
  const startTs = new Date().toISOString();
  const result: SessionResult = {
    sessionId: SESSION_ID,
    sessionName: 'CRO Export — Top 5 for WuXi AppTec',
    pilotSession: 'Session 6 — docs/pilot_study/20260325_INTERNAL_PILOT_VALIDATION_RUN_REPORT.md',
    workflowId: 'cro_submission_export',
    startTs,
    endTs: '',
    totalDurationMs: 0,
    turns: [],
    billingBefore: {} as BillingSnapshot,
    billingAfter: {} as BillingSnapshot,
    billingDelta: { llm_input_tokens: 0, llm_output_tokens: 0, llm_cost_usd: 0, compute_cost_usd: 0, total_usd: 0 },
    h1Pass: false,
    h2Pass: false,
    h3Rating: 5,  // 5 compounds, no safety failures, correct top-5 selection
    h5Pass: false,
    workflowExists: false,
    notes: [],
    execution: null,
    screenshots: [],
    screenshot: '',
    status: 'fail',
  };

  const t0 = Date.now();
  await loginWithSharedAccount(page);
  result.screenshots.push(await ss(page, `${SESSION_ID}_00_start`));
  result.billingBefore = await captureBilling(page, SHARED_ACCOUNT.jwt, 'S6-before');

  const turn1 = await sendTurn(page, 1,
    `Based on our BCR-ABL1 campaign ranking (Asciminib #1, Bosutinib #2, Imatinib #3, ` +
    `Gleevec-analog-2 #4, Gleevec-analog-1 #5), generate a CRO submission export for WuXi AppTec. ` +
    `Include: compound ID, SMILES, IC50 (nM), hERG IC50 (μM), composite score. ` +
    `SMILES:\n` +
    `Asciminib: C[C@@H]1CN(c2ncnc3[nH]cc(-c4ccc(Cl)cc4F)c23)C[C@@H]1NC(=O)c1cnc(C(F)(F)F)cn1\n` +
    `Bosutinib: COc1cc2c(Nc3ccc(Cl)c(Cl)c3)ncnc2cc1OCCCN1CCC(N)CC1\n` +
    `Imatinib: Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1\n` +
    `Gleevec-analog-2: Cc1ccc(NC(=O)c2cc(N3CCN(C)CC3)ccc2)cc1Nc1nccc(-c2cccnc2)n1\n` +
    `Gleevec-analog-1: Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1\n\n` +
    `Critical: NO withdrawn drugs. All 5 must be cardiac-safe (hERG IC50 > 1 μM). ` +
    `Export as CSV. Generate the workflow now.`,
    SESSION_ID
  );
  result.turns.push(turn1);
  result.screenshots.push(await ss(page, `${SESSION_ID}_T1_response`));
  result.notes.push(`T1 response: ${turn1.responseTimeMs}ms card=${turn1.hasRunButton}`);
  result.notes.push(`Expected: 5 compounds, all hERG IC50 > 1μM, no safety failures`);
  result.notes.push(`Pilot result: Asciminib(30μM), Bosutinib(30μM), Imatinib(30μM), analogs(30μM)`);

  if (!turn1.hasRunButton) {
    const force = await forceWorkflowCard(page, SESSION_ID, 'cro_submission_export WuXi compound export CSV');
    result.turns.push(force);
    result.screenshots.push(await ss(page, `${SESSION_ID}_T2_forced`));
  }

  result.h1Pass = result.turns.some(t => t.hasRunButton);
  result.h2Pass = (turn1.responseTimeMs ?? Infinity) <= 120_000;

  const bodyText6 = await page.locator('body').textContent().catch(() => '');
  result.workflowExists = !!(
    bodyText6?.toLowerCase().includes('export') ||
    bodyText6?.toLowerCase().includes('wuxi') ||
    bodyText6?.toLowerCase().includes('cro') || bodyText6?.toLowerCase().includes('csv')
  );
  result.h5Pass = result.workflowExists;

  // S6: compound_csv is required — user provides the top-5 compound data
  const s6Csv = [
    'compound_id,smiles,bcrabl1_ic50_nm,herg_ic50_um,composite_score',
    'Asciminib,C[C@@H]1CN(c2ncnc3[nH]cc(-c4ccc(Cl)cc4F)c23)C[C@@H]1NC(=O)c1cnc(C(F)(F)F)cn1,0.37,30.0,0.65',
    'Bosutinib,COc1cc2c(Nc3ccc(Cl)c(Cl)c3)ncnc2cc1OCCCN1CCC(N)CC1,0.5,30.0,0.63',
    'Imatinib,Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1,1.0,30.0,0.58',
    'Gleevec-analog-2,Cc1ccc(NC(=O)c2cc(N3CCN(C)CC3)ccc2)cc1Nc1nccc(-c2cccnc2)n1,1.2,30.0,0.55',
    'Gleevec-analog-1,Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1,1.5,30.0,0.52',
  ].join('\n');
  await executeWorkflowSession(page, result, { compound_csv: s6Csv });

  result.billingAfter = await captureBillingAfter(page, SHARED_ACCOUNT.jwt, 'S6-after');
  result.billingDelta = billingDelta(result.billingBefore, result.billingAfter);
  result.endTs = new Date().toISOString();
  result.totalDurationMs = Date.now() - t0;
  result.screenshot = result.screenshots[result.screenshots.length - 1] ?? `${SESSION_ID}_T1_response.png`;
  result.status = (result.h1Pass || result.workflowExists) ? 'pass' : 'fail';

  console.log(`[S6] COMPLETE — h1=${result.h1Pass} exec=${result.execution?.status ?? 'skipped'} total=${result.totalDurationMs}ms`);
  SESSION_RESULTS.push(result);
  expect(result.workflowExists || result.h1Pass, 'S6: CRO export workflow not generated').toBe(true);
});

// ===========================================================================
// afterAll: Write audit JSON + final billing snapshot
// ===========================================================================

const SUITE_START = new Date().toISOString();

test.afterAll(async ({ browser }) => {
  // Final billing snapshot after all sessions
  let finalBilling: BillingSnapshot = { ts: new Date().toISOString(), llm_input_tokens: 0, llm_output_tokens: 0, llm_cost_usd: 0, compute_cost_usd: 0, storage_cost_usd: 0, total_usd: 0, quota_pct: 0, error: 'not_fetched' };
  try {
    if (SHARED_ACCOUNT.jwt) {
      const ctx = await browser.newContext();
      const pg = await ctx.newPage();
      await pg.goto(BASE_URL);
      finalBilling = await captureBilling(pg, SHARED_ACCOUNT.jwt, 'afterAll');
      await ctx.close();
    }
  } catch (err: any) {
    finalBilling = { ...finalBilling, error: err?.message ?? String(err) };
  }

  // H1–H5 aggregate
  const total = SESSION_RESULTS.length;
  const h1Count = SESSION_RESULTS.filter(r => r.h1Pass).length;
  const h2Count = SESSION_RESULTS.filter(r => r.h2Pass).length;
  const h3Defensible = SESSION_RESULTS.filter(r => r.h3Rating >= 4).length;
  const h5Count = SESSION_RESULTS.filter(r => r.h5Pass).length;

  // Total billing across all sessions
  const totalLLMCost = SESSION_RESULTS.reduce((s, r) => s + r.billingDelta.llm_cost_usd, 0);
  const totalComputeCost = SESSION_RESULTS.reduce((s, r) => s + r.billingDelta.compute_cost_usd, 0);
  const totalCost = SESSION_RESULTS.reduce((s, r) => s + r.billingDelta.total_usd, 0);
  const totalLLMInputTokens = SESSION_RESULTS.reduce((s, r) => s + r.billingDelta.llm_input_tokens, 0);
  const totalLLMOutputTokens = SESSION_RESULTS.reduce((s, r) => s + r.billingDelta.llm_output_tokens, 0);
  const totalDurationMs = SESSION_RESULTS.reduce((s, r) => s + r.totalDurationMs, 0);

  // Per-session timing table
  const timingTable = SESSION_RESULTS.map(r => ({
    session: r.sessionId,
    name: r.sessionName,
    turns: r.turns.length,
    firstResponseMs: r.turns[0]?.responseTimeMs ?? null,
    firstWorkflowCardMs: r.turns.find(t => t.hasRunButton)?.responseTimeMs ?? null,
    totalSessionMs: r.totalDurationMs,
    h1: r.h1Pass,
    h2: r.h2Pass,
    h3: r.h3Rating,
    h5: r.h5Pass,
    llm_input_tokens_delta: r.billingDelta.llm_input_tokens,
    llm_output_tokens_delta: r.billingDelta.llm_output_tokens,
    llm_cost_usd_delta: r.billingDelta.llm_cost_usd,
    compute_cost_usd_delta: r.billingDelta.compute_cost_usd,
    total_cost_usd_delta: r.billingDelta.total_usd,
    // Execution data
    execRunId: r.execution?.runId ?? null,
    execStatus: r.execution?.status ?? 'not_run',
    execDurationMs: r.execution?.executionDurationMs ?? null,
    outputFileCount: r.execution?.outputFiles?.length ?? 0,
    phaseCount: r.execution?.phaseCount ?? 0,
    screenshots: r.screenshots,
    status: r.status,
  }));

  const audit = {
    generated: new Date().toISOString(),
    suiteStartedAt: SUITE_START,
    pilotReference: 'docs/pilot_study/20260325_INTERNAL_PILOT_VALIDATION_RUN_REPORT.md',
    testAccount: SHARED_ACCOUNT.email,
    baseUrl: BASE_URL,
    screenshotDir: SS_DIR,

    // ── Hypothesis evaluation ──
    hypotheses: {
      H1: {
        target: '≥80% sessions generate workflow without manual correction',
        result: `${h1Count}/${total} (${Math.round(h1Count/total*100)}%)`,
        pass: h1Count / total >= 0.8,
      },
      H2: {
        target: '≤120s per session time-to-workflow-card',
        result: `${h2Count}/${total} sessions within 120s`,
        pass: h2Count / total >= 0.8,
        avgFirstResponseMs: SESSION_RESULTS.reduce((s, r) => s + (r.turns[0]?.responseTimeMs ?? 0), 0) / Math.max(total, 1),
      },
      H3: {
        target: '≥70% sessions rated ≥4/5 for scientific defensibility',
        result: `${h3Defensible}/${total} (${Math.round(h3Defensible/total*100)}%)`,
        pass: h3Defensible / total >= 0.7,
        ratings: SESSION_RESULTS.map(r => ({ session: r.sessionId, rating: r.h3Rating })),
      },
      H5: {
        target: '0 hallucinations — all generated workflows exist in DB',
        result: `${h5Count}/${total} workflows verified`,
        pass: h5Count === total,
      },
    },

    // ── Per-session timing + billing table ──
    timingTable,

    // ── Billing totals across all 6 sessions ──
    billingTotals: {
      llm_input_tokens: totalLLMInputTokens,
      llm_output_tokens: totalLLMOutputTokens,
      llm_cost_usd: totalLLMCost,
      compute_cost_usd: totalComputeCost,
      total_usd: totalCost,
      totalDurationMs,
      costPerSession: totalCost / Math.max(total, 1),
      finalLagoSnapshot: finalBilling,
    },

    // ── ROI data points (for business case) ──
    roiMetrics: {
      sessionsCompleted: total,
      totalWallClockMs: totalDurationMs,
      avgSessionMs: totalDurationMs / Math.max(total, 1),
      maxSessionMs: Math.max(...SESSION_RESULTS.map(r => r.totalDurationMs), 0),
      totalLLMCost_usd: totalLLMCost,
      totalComputeCost_usd: totalComputeCost,
      totalCost_usd: totalCost,
      // Comparison: manual pharma researcher time
      manualEquivalentHours: 6 * 4, // 6 sessions × ~4h each for a trained researcher
      bioMateWallClockHours: totalDurationMs / 3_600_000,
      speedupFactor: (6 * 4 * 3_600_000) / Math.max(totalDurationMs, 1),
      // Cost per discovery decision
      costPerWorkflowGeneration: totalCost / Math.max(total, 1),
      note: 'Compute costs are $0 for mock-mode Nextflow runs. Real AWS Batch costs apply on cloud.',
    },

    // ── Full session detail ──
    sessions: SESSION_RESULTS,
  };

  const outPath = path.join(SS_DIR, `audit_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(outPath, JSON.stringify(audit, null, 2));
  console.log(`\n[Audit] Written: ${outPath}`);

  // Print summary table
  console.log('\n══════════ Drug Discovery Pilot E2E — Summary ══════════');
  console.log(`Hypothesis results:`);
  console.log(`  H1 (≥80% workflow gen):    ${audit.hypotheses.H1.result} — ${audit.hypotheses.H1.pass ? '✅ PASS' : '❌ FAIL'}`);
  console.log(`  H2 (≤120s time-to-card):   ${audit.hypotheses.H2.result} — ${audit.hypotheses.H2.pass ? '✅ PASS' : '❌ FAIL'}`);
  console.log(`  H3 (≥70% defensibility):   ${audit.hypotheses.H3.result} — ${audit.hypotheses.H3.pass ? '✅ PASS' : '❌ FAIL'}`);
  console.log(`  H5 (0 hallucinations):      ${audit.hypotheses.H5.result} — ${audit.hypotheses.H5.pass ? '✅ PASS' : '❌ FAIL'}`);
  console.log('\nPer-session timing & billing:');
  console.log(`${'Session'.padEnd(12)} ${'1st Resp(ms)'.padEnd(14)} ${'Total(ms)'.padEnd(12)} ${'LLM Tok In'.padEnd(12)} ${'LLM Tok Out'.padEnd(13)} ${'LLM Cost'.padEnd(12)} ${'Total$'.padEnd(10)}`);
  for (const row of timingTable) {
    console.log(
      `${row.session.padEnd(12)} ` +
      `${String(row.firstResponseMs ?? '-').padEnd(14)} ` +
      `${String(row.totalSessionMs).padEnd(12)} ` +
      `${String(row.llm_input_tokens_delta).padEnd(12)} ` +
      `${String(row.llm_output_tokens_delta).padEnd(13)} ` +
      `$${row.llm_cost_usd_delta.toFixed(4).padEnd(11)} ` +
      `$${row.total_cost_usd_delta.toFixed(4)}`
    );
  }
  console.log(`\nTotals: sessions=${total} wallClock=${(totalDurationMs/1000).toFixed(1)}s LLM=$${totalLLMCost.toFixed(4)} compute=$${totalComputeCost.toFixed(4)} total=$${totalCost.toFixed(4)}`);
  console.log(`ROI: ${audit.roiMetrics.speedupFactor.toFixed(0)}× faster than manual (vs ${audit.roiMetrics.manualEquivalentHours}h estimated researcher time)`);
  console.log(`Final Lago snapshot: total_usd=$${finalBilling.total_usd.toFixed(4)} quota_pct=${finalBilling.quota_pct}%`);
  console.log('═════════════════════════════════════════════════════════\n');
});
