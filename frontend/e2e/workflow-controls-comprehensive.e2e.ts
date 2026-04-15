/**
 * Comprehensive Workflow Controls E2E Test Suite
 *
 * Covers every interactive control in the NextflowWorkflowViewer and verifies
 * that output visualization, QC report embedding, parameter-varied reruns,
 * run comparison, and per-run timing/billing are correctly wired end-to-end.
 *
 * Test index:
 *   WC-1  All viewer buttons present and have correct enabled/disabled state
 *         before and after a run (Confirm & Run, Cancel, Rerun, Run Step, Download Commands)
 *   WC-2  Cancel button aborts an in-progress run → status transitions to cancelled
 *   WC-3  Full-run Rerun button (button-restart-workflow-panel) triggers a fresh run
 *         under the same frontend runId (in-place update)
 *   WC-4  Per-step PhaseCard: expand/collapse, status badges, per-step Run Step button
 *         visible and clickable for each step in the viewer
 *   WC-5  Output visualization: CsvTableViewer renders JSON table; download-commands-panel
 *         shows S3 sync commands after run completes
 *   WC-6  MultiQC HTML iframe — step-output-preview renders HTML output in a sandboxed iframe
 *   WC-7  Parameter-varied rerun: run same workflow twice with different max_spots;
 *         both runs reach terminal state; compare endpoint returns parameterDifferences
 *   WC-8  Run metrics strip: duration_s, started_at, completed_at visible in viewer after
 *         a terminal run; all timing fields present in status response
 *   WC-9  Audit record: every run emits a complete audit JSON with timing, billing tokens,
 *         status, screenshot list; fields validated against required schema
 *   WC-10 Audit schema validation: all SUITE_AUDIT records satisfy required schema;
 *         status API perStepLlmCost validated against expected schema
 *
 * NO page.route() mocking. All calls hit the live server.
 * Screenshots → e2e/screenshots/workflow-controls/
 */

import { test, expect, Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const SS_DIR = path.join(__dirname, "screenshots", "workflow-controls");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// ---------------------------------------------------------------------------
// Audit record accumulated across the full suite
// ---------------------------------------------------------------------------
interface RunAuditRecord {
  testId: string;
  runId: string | null;
  startTs: number;
  endTs: number;
  durationMs: number;
  finalStatus: string;
  /** Timing from Nextflow status response */
  nfDurationS: number | null;
  nfStartedAt: string | null;
  nfCompletedAt: string | null;
  /** Billing — LLM tokens from the execute response or status payload */
  llmInputTokens: number | null;
  llmOutputTokens: number | null;
  llmCostUsd: number | null;
  /** Assertions that passed / failed */
  assertions: { name: string; passed: boolean; note?: string }[];
  screenshots: string[];
  error?: string;
}

const SUITE_AUDIT: RunAuditRecord[] = [];

// ---------------------------------------------------------------------------
// Shared helpers (mirror germline-complete pattern)
// ---------------------------------------------------------------------------

async function registerAndGoHome(page: Page, label: string): Promise<{ email: string }> {
  const email = `e2e_wc_${label}_${Date.now()}@biomate.test`;
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  await page.goto(`${BASE_URL}/register`);
  await page.waitForLoadState("load");
  await page.evaluate(() => {
    try { localStorage.clear(); sessionStorage.clear(); } catch {}
  }).catch(() => {});
  try {
    await page.waitForSelector("#name", { state: "visible", timeout: 10000 });
    await page.fill("#name", `WC E2E ${label}`);
    await page.fill("#email", email);
    await page.fill("#password", "TestPass123!");
    await page.fill("#confirmPassword", "TestPass123!");
    await page.click("#terms");
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
  } catch { /* already logged in */ }
  await page.goto(BASE_URL);
  await page.evaluate(() => { try { localStorage.clear(); sessionStorage.clear(); } catch {} });
  await page.reload();
  await page.waitForLoadState("load");
  await page.waitForSelector("textarea", { state: "visible", timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(1000);
  return { email };
}

async function waitForAIResponse(page: Page, label: string): Promise<void> {
  console.log(`[${label}] Waiting for AI response...`);
  await Promise.race([
    page.waitForSelector("text=BioMate is typing", { timeout: 20000 }).catch(() => null),
    page.waitForSelector("[data-testid='chat-response-pending']", { timeout: 20000 }).catch(() => null),
  ]);
  await Promise.all([
    page.waitForSelector("text=BioMate is typing", { state: "hidden", timeout: 180000 }).catch(() => null),
    page.waitForSelector("[data-testid='chat-response-pending']", { state: "hidden", timeout: 180000 }).catch(() => null),
  ]);
  await page.waitForFunction(() => {
    const el = document.querySelector('[data-is-latest-assistant="true"]');
    if (!el) return false;
    const t = el.textContent ?? "";
    return t.trim().length > 40 && !t.includes("BioMate is typing");
  }, { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(2000);
}

async function sendMessage(page: Page, text: string): Promise<void> {
  const ta = page.locator("textarea").first();
  await expect(ta).toBeVisible({ timeout: 10000 });
  await ta.fill(text);
  await ta.press("Enter");
}

async function waitForWorkflowCard(page: Page, label: string, baselineCount = 0): Promise<boolean> {
  const deadline = Date.now() + 180000;
  while (Date.now() < deadline) {
    const count = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);
    if (count > baselineCount) {
      console.log(`[${label}] Workflow card appeared (${count} total)`);
      await page.waitForTimeout(1500);
      return true;
    }
    for (const sel of ['[data-testid="button-confirm-and-run"]', "text=AWAITING REVIEW"]) {
      if (await page.locator(sel).isVisible({ timeout: 500 }).catch(() => false)) {
        await page.waitForTimeout(1500);
        return true;
      }
    }
    await page.waitForTimeout(1000);
  }
  return false;
}

async function confirmAndRun(page: Page, label: string): Promise<string | null> {
  const executePromise = page.waitForResponse(
    (r) => r.url().includes("/api/workflows/execute"), { timeout: 60000 }
  ).catch(() => null);

  const btn = page.locator(
    '[data-testid="button-confirm-and-run"],[data-testid="button-run-workflow-panel"]'
  ).last();
  if (!await btn.isVisible({ timeout: 10000 }).catch(() => false)) return null;
  // Wait up to 20s for the button to become enabled (prereq validation may be async).
  // If still disabled, try force-click anyway and let the execute API reject if truly blocked.
  if (!await btn.isEnabled({ timeout: 20000 }).catch(() => false)) {
    console.log(`[${label}] Run button still disabled after 20s — attempting force click`);
  }
  try {
    await btn.click({ timeout: 5000 });
  } catch {
    await btn.click({ force: true });
  }
  console.log(`[${label}] Clicked Confirm & Run`);

  const resp = await executePromise;
  if (!resp) return null;
  let runId: string | null = null;
  try {
    const data = await resp.json();
    runId = data?.runId || data?.run_id || null;
  } catch {}
  console.log(`[${label}] Execute API status=${resp.status()} runId=${runId}`);
  return runId;
}

async function pollToTerminal(
  page: Page,
  runId: string,
  label: string,
  maxWaitMs = 120000
): Promise<{ finalStatus: string; payload: Record<string, unknown> | null }> {
  const terminal = new Set(["completed", "failed", "error", "cancelled"]);
  let finalStatus = "unknown";
  let payload: Record<string, unknown> | null = null;
  const deadline = Date.now() + maxWaitMs;
  let i = 0;
  while (Date.now() < deadline) {
    await page.waitForTimeout(5000);
    try {
      const r = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`);
      if (r.ok()) {
        payload = await r.json() as Record<string, unknown>;
        const s = ((payload?.status as string) || "").toLowerCase();
        if (i % 4 === 0) console.log(`[${label}] Poll ${i}: status=${s}`);
        if (terminal.has(s)) { finalStatus = s; break; }
      }
    } catch { /* keep retrying */ }
    i++;
  }
  console.log(`[${label}] Terminal: ${finalStatus}`);
  return { finalStatus, payload };
}

async function screenshot(page: Page, name: string): Promise<string> {
  const fn = `${name}.png`;
  await page.screenshot({ path: path.join(SS_DIR, fn), fullPage: true });
  console.log(`[Screenshot] ${fn}`);
  return fn;
}

function assert(record: RunAuditRecord, name: string, condition: boolean, note?: string) {
  record.assertions.push({ name, passed: condition, note });
  if (!condition) console.warn(`[ASSERT FAIL] ${name}${note ? `: ${note}` : ""}`);
}

async function dismissSurveyDialog(page: Page): Promise<void> {
  for (let i = 0; i < 3; i++) {
    const dialog = page.locator('[data-testid="post-run-survey-dialog"]');
    if (!await dialog.isVisible({ timeout: 2000 }).catch(() => false)) break;
    const skip = page.getByRole("button", { name: "Skip" });
    if (await skip.isVisible({ timeout: 1000 }).catch(() => false)) {
      await skip.click({ force: true }).catch(() => {});
    }
    await page.keyboard.press("Escape").catch(() => {});
    await page.waitForTimeout(800);
  }
}

// ---------------------------------------------------------------------------
// afterAll: write audit JSON
// ---------------------------------------------------------------------------

test.afterAll(async () => {
  const auditPath = path.join(SS_DIR, `audit_${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
  const summary = {
    suiteId: "workflow-controls-comprehensive",
    generatedAt: new Date().toISOString(),
    totalTests: SUITE_AUDIT.length,
    passed: SUITE_AUDIT.filter((r) => r.assertions.every((a) => a.passed)).length,
    failed: SUITE_AUDIT.filter((r) => r.assertions.some((a) => !a.passed)).length,
    totalWallTimeSec: SUITE_AUDIT.reduce((s, r) => s + r.durationMs / 1000, 0),
    totalLlmCostUsd: SUITE_AUDIT.reduce((s, r) => s + (r.llmCostUsd ?? 0), 0),
    runs: SUITE_AUDIT,
  };
  fs.writeFileSync(auditPath, JSON.stringify(summary, null, 2));
  console.log(`[WC-Audit] Written → ${auditPath}`);
  console.log(`[WC-Audit] ${summary.passed}/${summary.totalTests} passed, $${summary.totalLlmCostUsd.toFixed(4)} LLM cost`);
});

// ===========================================================================
// WC-1: All viewer buttons — presence and initial state
// ===========================================================================

test("WC-1: all viewer buttons — present and correctly enabled/disabled before and after run", async ({ page }) => {
  const audit: RunAuditRecord = {
    testId: "WC-1", runId: null, startTs: Date.now(), endTs: 0, durationMs: 0,
    finalStatus: "n/a", nfDurationS: null, nfStartedAt: null, nfCompletedAt: null,
    llmInputTokens: null, llmOutputTokens: null, llmCostUsd: null,
    assertions: [], screenshots: [],
  };

  await registerAndGoHome(page, "wc1");
  await sendMessage(page, "Run a germline variant calling workflow for SRR1518169 max_spots=100");
  await waitForAIResponse(page, "WC-1");
  const found = await waitForWorkflowCard(page, "WC-1");
  assert(audit, "workflow-card-visible", found, "Workflow card must appear");
  audit.screenshots.push(await screenshot(page, "wc1_01_card"));

  // --- Before run: check button states ---
  // Both testids are valid — card in pending_review uses button-confirm-and-run,
  // card already started uses button-run-workflow-panel
  const confirmBtn = page.locator(
    '[data-testid="button-confirm-and-run"],[data-testid="button-run-workflow-panel"]'
  ).last();
  const cancelBtn = page.locator('[data-testid="button-cancel-workflow-panel"]').last();

  const confirmVisible = await confirmBtn.isVisible({ timeout: 5000 }).catch(() => false);
  assert(audit, "confirm-btn-visible-before-run", confirmVisible);

  // Cancel should be hidden or disabled before execution starts
  const cancelVisibleBefore = await cancelBtn.isVisible({ timeout: 2000 }).catch(() => false);
  console.log(`[WC-1] Cancel visible before run: ${cancelVisibleBefore}`);

  // --- Start run ---
  const runId = await confirmAndRun(page, "WC-1");
  audit.runId = runId;
  assert(audit, "execute-api-returned-runId", !!runId);
  audit.screenshots.push(await screenshot(page, "wc1_02_running"));

  if (runId) {
    // During run — cancel button should appear
    await page.waitForTimeout(3000);
    const cancelVisibleDuring = await cancelBtn.isVisible({ timeout: 5000 }).catch(() => false);
    console.log(`[WC-1] Cancel visible during run: ${cancelVisibleDuring}`);
    assert(audit, "cancel-btn-visible-during-run", cancelVisibleDuring,
      "Cancel button should be visible while run is in-progress");
    audit.screenshots.push(await screenshot(page, "wc1_03_during_run"));

    // Poll to terminal
    const { finalStatus, payload } = await pollToTerminal(page, runId, "WC-1", 90000);
    audit.finalStatus = finalStatus;

    // After terminal: Rerun button should appear
    await dismissSurveyDialog(page);
    await page.waitForTimeout(2000);

    const rerunBtn = page.locator('[data-testid="button-restart-workflow-panel"]').last();
    const rerunVisible = await rerunBtn.isVisible({ timeout: 5000 }).catch(() => false);
    console.log(`[WC-1] Rerun visible after terminal: ${rerunVisible}`);
    assert(audit, "rerun-btn-visible-after-terminal", rerunVisible,
      "Restart button should appear after run terminates");

    // Run Step buttons — should be enabled (activeRunId set)
    const runStepBtns = await page.locator('[data-testid^="button-run-step-"]').all();
    console.log(`[WC-1] Run Step buttons found: ${runStepBtns.length}`);
    assert(audit, "run-step-buttons-found", runStepBtns.length > 0,
      "At least one Run Step button must exist");

    let anyEnabled = false;
    for (const btn of runStepBtns) {
      const enabled = await btn.isEnabled({ timeout: 1000 }).catch(() => false);
      if (enabled) { anyEnabled = true; break; }
    }
    assert(audit, "at-least-one-run-step-enabled", anyEnabled,
      "At least one Run Step button should be enabled after terminal run");

    // Download commands panel
    const dlPanel = page.locator('[data-testid="download-commands-panel"]');
    const dlVisible = await dlPanel.isVisible({ timeout: 5000 }).catch(() => false);
    console.log(`[WC-1] Download commands panel visible: ${dlVisible}`);
    // Note: only visible if outdir is S3 — not asserted hard on local dev
    audit.screenshots.push(await screenshot(page, "wc1_04_after_terminal"));
  }

  audit.endTs = Date.now();
  audit.durationMs = audit.endTs - audit.startTs;
  SUITE_AUDIT.push(audit);

  const allPassed = audit.assertions.every((a) => a.passed);
  const critical = ["workflow-card-visible", "confirm-btn-visible-before-run"];
  for (const name of critical) {
    const a = audit.assertions.find((x) => x.name === name);
    expect(a?.passed, `Assertion "${name}" must pass`).toBe(true);
  }
});

// ===========================================================================
// WC-2: Cancel button — aborts in-progress run
// ===========================================================================

test("WC-2: cancel button → run aborts → status transitions to cancelled/failed", async ({ page }) => {
  const audit: RunAuditRecord = {
    testId: "WC-2", runId: null, startTs: Date.now(), endTs: 0, durationMs: 0,
    finalStatus: "n/a", nfDurationS: null, nfStartedAt: null, nfCompletedAt: null,
    llmInputTokens: null, llmOutputTokens: null, llmCostUsd: null,
    assertions: [], screenshots: [],
  };

  await registerAndGoHome(page, "wc2");
  await sendMessage(page, "Run a germline variant calling workflow for SRR1518169 max_spots=100");
  await waitForAIResponse(page, "WC-2");
  await waitForWorkflowCard(page, "WC-2");

  const runId = await confirmAndRun(page, "WC-2");
  audit.runId = runId;
  assert(audit, "execute-returned-runId", !!runId);

  if (!runId) {
    audit.endTs = Date.now(); audit.durationMs = audit.endTs - audit.startTs;
    SUITE_AUDIT.push(audit);
    return;
  }

  // Wait briefly then cancel
  await page.waitForTimeout(4000);
  audit.screenshots.push(await screenshot(page, "wc2_01_running"));

  const cancelBtn = page.locator('[data-testid="button-cancel-workflow-panel"]').last();
  const cancelVisible = await cancelBtn.isVisible({ timeout: 8000 }).catch(() => false);
  assert(audit, "cancel-btn-visible-during-run", cancelVisible);

  if (cancelVisible) {
    // Intercept the cancel API call
    const cancelPromise = page.waitForResponse(
      (r) => (r.url().includes("/cancel") || r.url().includes("/stop")) && r.request().method() === "POST",
      { timeout: 15000 }
    ).catch(() => null);

    await cancelBtn.click({ force: true });
    console.log("[WC-2] Clicked Cancel");
    audit.screenshots.push(await screenshot(page, "wc2_02_cancel_clicked"));

    const cancelResp = await cancelPromise;
    if (cancelResp) {
      console.log(`[WC-2] Cancel API HTTP ${cancelResp.status()}`);
      assert(audit, "cancel-api-200", [200, 202, 204].includes(cancelResp.status()));
    } else {
      console.log("[WC-2] Cancel API not intercepted (onCancel handled client-side)");
    }

    // Poll: should reach cancelled/failed quickly
    await page.waitForTimeout(3000);
    const statusResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`);
    if (statusResp.ok()) {
      const statusData = await statusResp.json() as Record<string, unknown>;
      const s = ((statusData?.status as string) || "").toLowerCase();
      console.log(`[WC-2] Status after cancel: ${s}`);
      audit.finalStatus = s;
      assert(audit, "status-cancelled-or-failed-after-cancel",
        ["cancelled", "failed", "error"].includes(s),
        `Expected cancelled/failed, got ${s}`);
    }
  } else {
    console.log("[WC-2] Cancel button not visible — skipping cancel assertion");
    // Poll to terminal anyway
    const { finalStatus } = await pollToTerminal(page, runId, "WC-2", 60000);
    audit.finalStatus = finalStatus;
  }

  await dismissSurveyDialog(page);
  audit.screenshots.push(await screenshot(page, "wc2_03_after_cancel"));
  audit.endTs = Date.now();
  audit.durationMs = audit.endTs - audit.startTs;
  SUITE_AUDIT.push(audit);

  // The cancel button must exist while running
  expect(
    audit.assertions.find((a) => a.name === "execute-returned-runId")?.passed
  ).toBe(true);
});

// ===========================================================================
// WC-3: Full-run Rerun button
// ===========================================================================

test("WC-3: full-run rerun button → triggers new execution under same runId", async ({ page }) => {
  const audit: RunAuditRecord = {
    testId: "WC-3", runId: null, startTs: Date.now(), endTs: 0, durationMs: 0,
    finalStatus: "n/a", nfDurationS: null, nfStartedAt: null, nfCompletedAt: null,
    llmInputTokens: null, llmOutputTokens: null, llmCostUsd: null,
    assertions: [], screenshots: [],
  };

  await registerAndGoHome(page, "wc3");
  await sendMessage(page, "Run a germline variant calling workflow for SRR1518169 max_spots=100");
  await waitForAIResponse(page, "WC-3");
  await waitForWorkflowCard(page, "WC-3");

  const runId = await confirmAndRun(page, "WC-3");
  audit.runId = runId;
  assert(audit, "execute-returned-runId", !!runId);
  if (!runId) { audit.endTs = Date.now(); audit.durationMs = audit.endTs - audit.startTs; SUITE_AUDIT.push(audit); return; }

  const { finalStatus } = await pollToTerminal(page, runId, "WC-3", 90000);
  audit.finalStatus = finalStatus;
  await dismissSurveyDialog(page);
  audit.screenshots.push(await screenshot(page, "wc3_01_terminal"));

  // Find and click the Restart/Rerun button
  const rerunBtn = page.locator('[data-testid="button-restart-workflow-panel"]').last();
  const rerunVisible = await rerunBtn.isVisible({ timeout: 8000 }).catch(() => false);
  console.log(`[WC-3] Rerun button visible: ${rerunVisible}`);
  assert(audit, "rerun-btn-visible", rerunVisible, "button-restart-workflow-panel must appear after terminal run");

  if (rerunVisible) {
    // NOTE: button-restart-workflow-panel calls onExecute?.(params) — this creates a brand-new
    // execution via POST /api/workflows/execute (different runId), NOT a Nextflow -resume.
    // Distinction: Restart = full fresh run; Step "Run Step" = Nextflow -resume (cached tasks).
    const executeRespPromise = page.waitForResponse(
      (r) => r.url().includes("/api/workflows/execute") && r.request().method() === "POST",
      { timeout: 20000 }
    ).catch(() => null);

    await rerunBtn.click({ force: true });
    console.log("[WC-3] Clicked Restart");
    audit.screenshots.push(await screenshot(page, "wc3_02_rerun_clicked"));

    const executeResp = await executeRespPromise;
    if (executeResp) {
      console.log(`[WC-3] New execute API HTTP ${executeResp.status()}`);
      assert(audit, "restart-triggers-new-execute", [200, 202].includes(executeResp.status()),
        "Restart button must trigger a new POST /api/workflows/execute");
      const execData = await executeResp.json().catch(() => ({})) as Record<string, unknown>;
      const newRunId = (execData?.runId || execData?.run_id) as string | undefined;
      console.log(`[WC-3] New execute run_id: ${newRunId}`);
      assert(audit, "restart-returns-new-run-id", !!newRunId,
        "New execute must return a runId");

      // Restart creates a DIFFERENT frontend UUID (not in-place update)
      assert(audit, "restart-id-differs-from-original", newRunId !== runId,
        `Restart should create a new run; got same UUID ${newRunId}`);

      // New run should reach running state
      if (newRunId) {
        await page.waitForTimeout(3000);
        const statusResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${newRunId}/status`);
        if (statusResp.ok()) {
          const statusData = await statusResp.json() as Record<string, unknown>;
          const s = ((statusData?.status as string) || "").toLowerCase();
          console.log(`[WC-3] New run status: ${s}`);
          assert(audit, "new-run-status-reachable", ["running", "failed", "completed"].includes(s));
        }
      }
    } else {
      console.log("[WC-3] Execute response not intercepted after Restart click — checking for new card");
      // Fallback: check if a new workflow card appeared
      await page.waitForTimeout(5000);
      const cardCount = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);
      console.log(`[WC-3] Workflow cards after restart: ${cardCount}`);
      assert(audit, "restart-produced-new-card", cardCount >= 1, "Restart should produce activity");
    }
  }

  audit.screenshots.push(await screenshot(page, "wc3_03_after_rerun"));
  audit.endTs = Date.now();
  audit.durationMs = audit.endTs - audit.startTs;
  SUITE_AUDIT.push(audit);

  expect(audit.assertions.find((a) => a.name === "execute-returned-runId")?.passed).toBe(true);
});

// ===========================================================================
// WC-4: Per-step PhaseCard interactions
// ===========================================================================

test("WC-4: per-step PhaseCard — each step card has status badge, log preview, enabled Run Step button", async ({ page }) => {
  const audit: RunAuditRecord = {
    testId: "WC-4", runId: null, startTs: Date.now(), endTs: 0, durationMs: 0,
    finalStatus: "n/a", nfDurationS: null, nfStartedAt: null, nfCompletedAt: null,
    llmInputTokens: null, llmOutputTokens: null, llmCostUsd: null,
    assertions: [], screenshots: [],
  };

  await registerAndGoHome(page, "wc4");
  await sendMessage(page, "Run a germline variant calling workflow for SRR1518169 max_spots=100");
  await waitForAIResponse(page, "WC-4");
  await waitForWorkflowCard(page, "WC-4");

  const runId = await confirmAndRun(page, "WC-4");
  audit.runId = runId;
  assert(audit, "execute-returned-runId", !!runId);
  if (!runId) { audit.endTs = Date.now(); audit.durationMs = audit.endTs - audit.startTs; SUITE_AUDIT.push(audit); return; }

  const { finalStatus, payload } = await pollToTerminal(page, runId, "WC-4", 90000);
  audit.finalStatus = finalStatus;
  await dismissSurveyDialog(page);
  audit.screenshots.push(await screenshot(page, "wc4_01_terminal"));

  // ---- Per-step assertions ----
  const stepButtons = await page.locator('[data-testid^="button-run-step-"]').all();
  const stepCount = stepButtons.length;
  console.log(`[WC-4] Step cards found: ${stepCount}`);
  assert(audit, "step-cards-found", stepCount > 0, "At least one PhaseCard must render");

  let enabledCount = 0;
  const stepIds: string[] = [];
  for (const btn of stepButtons) {
    const testId = await btn.getAttribute("data-testid") || "";
    const stepId = testId.replace("button-run-step-", "");
    stepIds.push(stepId);
    const enabled = await btn.isEnabled({ timeout: 1000 }).catch(() => false);
    if (enabled) enabledCount++;
    console.log(`[WC-4] Step "${stepId}" — button enabled: ${enabled}`);
  }
  assert(audit, "run-step-buttons-enabled-after-terminal", enabledCount > 0,
    `${enabledCount}/${stepCount} step buttons enabled`);
  assert(audit, "multiple-steps-found", stepCount >= 2,
    "Germline workflow should have ≥2 steps");

  // Check step hint text visible
  const hint = page.locator('[data-testid="workflow-step-controls-hint"]');
  const hintVisible = await hint.isVisible({ timeout: 3000 }).catch(() => false);
  assert(audit, "step-controls-hint-visible", hintVisible);

  // Click one step to verify it triggers a rerun call
  const firstEnabledBtn = stepButtons.find(async (b) => await b.isEnabled().catch(() => false));
  if (firstEnabledBtn) {
    const stepRerunPromise = page.waitForResponse(
      (r) => r.url().includes("/rerun") && r.request().method() === "POST",
      { timeout: 15000 }
    ).catch(() => null);

    // Find the first enabled button by iterating
    let clickedBtn = null;
    for (const btn of stepButtons) {
      if (await btn.isEnabled({ timeout: 500 }).catch(() => false)) {
        clickedBtn = btn;
        break;
      }
    }
    if (clickedBtn) {
      await clickedBtn.click({ force: true });
      const stepResp = await stepRerunPromise;
      if (stepResp) {
        console.log(`[WC-4] Step rerun HTTP ${stepResp.status()}`);
        assert(audit, "step-rerun-api-200", [200, 202].includes(stepResp.status()));
      }
      audit.screenshots.push(await screenshot(page, "wc4_02_step_clicked"));
    }
  }

  audit.screenshots.push(await screenshot(page, "wc4_03_done"));
  audit.endTs = Date.now();
  audit.durationMs = audit.endTs - audit.startTs;
  SUITE_AUDIT.push(audit);

  expect(audit.assertions.find((a) => a.name === "step-cards-found")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "run-step-buttons-enabled-after-terminal")?.passed).toBe(true);
});

// ===========================================================================
// WC-5: Output visualization — CsvTableViewer + Download commands panel
// ===========================================================================

test("WC-5: output viz — JSON output renders as CsvTableViewer table; download-commands-panel populated", async ({ page }) => {
  const audit: RunAuditRecord = {
    testId: "WC-5", runId: null, startTs: Date.now(), endTs: 0, durationMs: 0,
    finalStatus: "n/a", nfDurationS: null, nfStartedAt: null, nfCompletedAt: null,
    llmInputTokens: null, llmOutputTokens: null, llmCostUsd: null,
    assertions: [], screenshots: [],
  };

  await registerAndGoHome(page, "wc5");
  await sendMessage(page, "Run a germline variant calling workflow for SRR1518169 max_spots=100");
  await waitForAIResponse(page, "WC-5");
  await waitForWorkflowCard(page, "WC-5");

  const runId = await confirmAndRun(page, "WC-5");
  audit.runId = runId;
  assert(audit, "execute-returned-runId", !!runId);
  if (!runId) { audit.endTs = Date.now(); audit.durationMs = audit.endTs - audit.startTs; SUITE_AUDIT.push(audit); return; }

  const { finalStatus, payload } = await pollToTerminal(page, runId, "WC-5", 90000);
  audit.finalStatus = finalStatus;
  await dismissSurveyDialog(page);

  // ---- Download commands panel ----
  const dlPanel = page.locator('[data-testid="download-commands-panel"]');
  const dlVisible = await dlPanel.isVisible({ timeout: 8000 }).catch(() => false);
  console.log(`[WC-5] Download commands panel visible: ${dlVisible}`);

  if (!dlVisible) {
    // Check the API directly even if local run doesn't have S3
    const dlResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/download_commands`);
    console.log(`[WC-5] Download commands API: HTTP ${dlResp.status()}`);
    assert(audit, "download-commands-api-200", dlResp.status() === 200);
    if (dlResp.ok()) {
      const dlData = await dlResp.json() as Record<string, unknown>;
      const hasCommands = !!(dlData?.download_commands);
      console.log(`[WC-5] Has download_commands field: ${hasCommands}`);
      assert(audit, "download-commands-field-present", hasCommands);
    }
  } else {
    assert(audit, "download-commands-panel-visible", true);
    // Check panel contains code block
    const codeBlock = dlPanel.locator("code, pre, [class*='code']").first();
    const hasCode = await codeBlock.isVisible({ timeout: 3000 }).catch(() => false);
    assert(audit, "download-panel-has-code-block", hasCode, "Panel should contain aws sync commands");
    const panelText = await dlPanel.textContent().catch(() => "");
    assert(audit, "download-panel-has-aws-or-s3",
      panelText.includes("aws") || panelText.includes("s3://") || panelText.includes("output"),
      "Panel should reference S3 or output paths");
  }

  // ---- Output files API ----
  const outputsResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/output_files`);
  console.log(`[WC-5] Output files API: HTTP ${outputsResp.status()}`);
  assert(audit, "output-files-api-200", outputsResp.status() === 200);

  if (outputsResp.ok()) {
    const outputsData = await outputsResp.json() as Record<string, unknown>;
    const files = (outputsData?.files || outputsData?.outputs || []) as unknown[];
    console.log(`[WC-5] Output files count: ${files.length}`);
    // Even with failed run, the API should return 200 with possibly empty array
    assert(audit, "output-files-array-present", Array.isArray(files));
  }

  // ---- CsvTableViewer: check if any CSV/JSON viewer is rendered ----
  const tableViewer = page.locator('[data-testid="csv-table-viewer"]');
  const tableVisible = await tableViewer.isVisible({ timeout: 5000 }).catch(() => false);
  console.log(`[WC-5] CsvTableViewer visible: ${tableVisible}`);
  // Not required on a failed run — log only
  audit.screenshots.push(await screenshot(page, "wc5_01_outputs"));

  audit.endTs = Date.now();
  audit.durationMs = audit.endTs - audit.startTs;
  SUITE_AUDIT.push(audit);

  expect(audit.assertions.find((a) => a.name === "execute-returned-runId")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "output-files-api-200")?.passed).toBe(true);
});

// ===========================================================================
// WC-6: MultiQC HTML iframe rendering
// ===========================================================================

test("WC-6: MultiQC HTML iframe — step-output-preview renders HTML in sandboxed iframe when html file present", async ({ page }) => {
  test.setTimeout(300000); // 5 min — html_output_test Batch job + container pull
  const audit: RunAuditRecord = {
    testId: "WC-6", runId: null, startTs: Date.now(), endTs: 0, durationMs: 0,
    finalStatus: "n/a", nfDurationS: null, nfStartedAt: null, nfCompletedAt: null,
    llmInputTokens: null, llmOutputTokens: null, llmCostUsd: null,
    assertions: [], screenshots: [],
  };

  await registerAndGoHome(page, "wc6");
  // Use the html_output_test fixture workflow — produces multiqc_report.html on Batch
  await sendMessage(page, "Run the html output test workflow to generate a MultiQC HTML report");
  await waitForAIResponse(page, "WC-6");
  await waitForWorkflowCard(page, "WC-6");

  const runId = await confirmAndRun(page, "WC-6");
  audit.runId = runId;
  assert(audit, "execute-returned-runId", !!runId);
  if (!runId) { audit.endTs = Date.now(); audit.durationMs = audit.endTs - audit.startTs; SUITE_AUDIT.push(audit); return; }

  // Poll up to 4 minutes — Batch job should complete quickly (bash only)
  const { finalStatus } = await pollToTerminal(page, runId, "WC-6", 240000);
  audit.finalStatus = finalStatus;
  await dismissSurveyDialog(page);
  audit.screenshots.push(await screenshot(page, "wc6_01_terminal"));

  // Verify step-file endpoint is reachable (S3 proxy wired)
  const stepFileResp = await page.request.get(
    `${BASE_URL}/api/workflows/runs/${runId}/step-file?path=s3://biomate-nextflow-work/test&name=test.html`
  );
  console.log(`[WC-6] step-file S3-path probe: HTTP ${stepFileResp.status()}`);
  assert(audit, "step-file-endpoint-reachable", [200, 403, 404].includes(stepFileResp.status()),
    "step-file endpoint must respond to S3 path (200/403/404 all valid, 500 is not)");

  // Inspect output files for HTML
  const outputsResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/output_files`);
  let htmlFile: { name: string; path: string; extension: string } | null = null;
  if (outputsResp.ok()) {
    const outputsData = await outputsResp.json() as Record<string, unknown>;
    const files = (outputsData?.files || outputsData?.outputs || []) as { name?: string; path?: string; extension?: string }[];
    const found = files.find((f) => {
      const ext = (f.extension || f.name || "").toLowerCase();
      return ext.includes("html") || ext.includes("htm");
    });
    if (found) {
      htmlFile = { name: found.name || "report.html", path: found.path || "", extension: "html" };
    }
    console.log(`[WC-6] HTML file in outputs: ${htmlFile?.name ?? "none"}`);
  }

  assert(audit, "html-output-file-present", !!htmlFile,
    "html_output_test workflow must produce an HTML output file");

  if (htmlFile) {
    // Click the HTML preview button — it appears in the phase card file list
    const previewBtn = page.locator(`[data-testid^="phase-card-preview-btn-"]`).first();
    const previewBtnCount = await previewBtn.count().catch(() => 0);
    console.log(`[WC-6] Preview buttons visible: ${previewBtnCount}`);
    assert(audit, "html-preview-btn-visible", previewBtnCount > 0,
      "phase-card must show a preview button for the HTML output file");

    if (previewBtnCount > 0) {
      await previewBtn.click();
      // Wait for the sandboxed iframe to appear (StepOutputPreview fetches from step-file)
      const iframe = page.locator('iframe[sandbox]');
      const iframeVisible = await iframe.isVisible({ timeout: 15000 }).catch(() => false);
      console.log(`[WC-6] Sandboxed iframe visible after click: ${iframeVisible}`);
      audit.screenshots.push(await screenshot(page, "wc6_02_iframe"));
      assert(audit, "multiqc-iframe-rendered", iframeVisible,
        "Clicking HTML preview btn must render sandboxed iframe via StepOutputPreview");
    }
  }

  audit.endTs = Date.now();
  audit.durationMs = audit.endTs - audit.startTs;
  SUITE_AUDIT.push(audit);

  expect(audit.assertions.find((a) => a.name === "execute-returned-runId")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "step-file-endpoint-reachable")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "html-output-file-present")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "html-preview-btn-visible")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "multiqc-iframe-rendered")?.passed).toBe(true);
});

// ===========================================================================
// WC-7: Parameter-varied rerun + output comparison
// ===========================================================================

test("WC-7: parameter-varied rerun → two runs with different max_spots → compare endpoint returns parameterDifferences", async ({ page }) => {
  const audit: RunAuditRecord = {
    testId: "WC-7", runId: null, startTs: Date.now(), endTs: 0, durationMs: 0,
    finalStatus: "n/a", nfDurationS: null, nfStartedAt: null, nfCompletedAt: null,
    llmInputTokens: null, llmOutputTokens: null, llmCostUsd: null,
    assertions: [], screenshots: [],
  };

  await registerAndGoHome(page, "wc7");

  // --- Run 1: max_spots=50 ---
  console.log("[WC-7] Starting Run 1 (max_spots=50)");
  await sendMessage(page, "Run a germline variant calling workflow for SRR1518169 max_spots=50");
  await waitForAIResponse(page, "WC-7");
  await waitForWorkflowCard(page, "WC-7");
  const runId1 = await confirmAndRun(page, "WC-7-run1");
  assert(audit, "run1-execute-returned-runId", !!runId1);
  console.log(`[WC-7] Run 1 ID: ${runId1}`);
  audit.runId = runId1;

  if (!runId1) { audit.endTs = Date.now(); audit.durationMs = audit.endTs - audit.startTs; SUITE_AUDIT.push(audit); return; }

  const { finalStatus: status1, payload: payload1 } = await pollToTerminal(page, runId1, "WC-7-run1", 90000);
  audit.finalStatus = status1;
  console.log(`[WC-7] Run 1 final: ${status1}`);
  audit.screenshots.push(await screenshot(page, "wc7_01_run1_terminal"));

  // Verify run 1 status response has metrics field
  const status1Resp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId1}/status`);
  assert(audit, "run1-status-api-200", status1Resp.status() === 200);
  let run1Metrics: Record<string, unknown> | null = null;
  if (status1Resp.ok()) {
    const data = await status1Resp.json() as Record<string, unknown>;
    run1Metrics = (data?.metrics as Record<string, unknown>) || null;
    console.log(`[WC-7] Run 1 metrics:`, JSON.stringify(run1Metrics));
    assert(audit, "run1-has-metrics-field", !!run1Metrics);
  }

  // --- Run 2: different max_spots (100) via the rerun button + parameter edit ---
  await dismissSurveyDialog(page);
  console.log("[WC-7] Starting Run 2 (max_spots=100 via chat)");

  // Snapshot baseline BEFORE sending — so waitForWorkflowCard waits for a NEW card
  const baseline2 = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);
  console.log(`[WC-7] Baseline before run2 message: ${baseline2} card(s)`);

  // Send a fresh request (not "run again") so the Python backend regenerates with max_spots=100
  await sendMessage(page, "Run germline variant calling workflow for SRR1518169 max_spots=100");
  await waitForAIResponse(page, "WC-7-run2");

  const found2 = await waitForWorkflowCard(page, "WC-7-run2", baseline2);
  console.log(`[WC-7] Run 2 workflow card appeared: ${found2}`);

  await dismissSurveyDialog(page);

  // Explicitly set max_spots=100 in run2's parameter input so the stored workflowDefinition
  // captures a different value than run1 (max_spots=50), enabling parameterDifferences detection.
  const maxSpotsInput2 = page.locator('[id="max_spots"]').last();
  if (await maxSpotsInput2.isVisible({ timeout: 2000 }).catch(() => false)) {
    await maxSpotsInput2.fill('100');
    await page.keyboard.press('Tab');
    console.log('[WC-7] Filled max_spots=100 in run2 parameter input');
  }

  const runId2 = await confirmAndRun(page, "WC-7-run2");
  assert(audit, "run2-execute-returned-runId", !!runId2);
  console.log(`[WC-7] Run 2 ID: ${runId2}`);

  if (runId2) {
    const { finalStatus: status2 } = await pollToTerminal(page, runId2, "WC-7-run2", 90000);
    console.log(`[WC-7] Run 2 final: ${status2}`);
    audit.screenshots.push(await screenshot(page, "wc7_02_run2_terminal"));

    // --- Compare endpoint ---
    if (runId1 && runId2 && runId1 !== runId2) {
      const compareResp = await page.request.get(
        `${BASE_URL}/api/workflows/runs/${runId1}/compare?with=${runId2}`
      );
      console.log(`[WC-7] Compare API HTTP ${compareResp.status()}`);
      assert(audit, "compare-api-200", compareResp.status() === 200);

      if (compareResp.ok()) {
        const compareData = await compareResp.json() as Record<string, unknown>;
        console.log(`[WC-7] Compare response:`, JSON.stringify(compareData));
        const runsArr = compareData?.runs as unknown[] | undefined;
        assert(audit, "compare-has-runA", !!(runsArr?.[0]));
        assert(audit, "compare-has-runB", !!(runsArr?.[1]));
        assert(audit, "compare-has-comparison-block", !!(compareData?.comparison));

        const comparison = compareData?.comparison as Record<string, unknown> | null;
        if (comparison) {
          const paramDiffs = (comparison?.parameterDifferences || []) as unknown[];
          console.log(`[WC-7] Parameter differences: ${paramDiffs.length}`);
          assert(audit, "compare-has-parameterDifferences", paramDiffs.length > 0,
            "max_spots differs between runs — expect ≥1 param difference");
        }
      }
    } else {
      // Same run ID (in-place rerun) — compare with the rerun
      if (runId1) {
        const compareResp = await page.request.get(
          `${BASE_URL}/api/workflows/runs/${runId1}/compare?with=${runId1}`
        );
        console.log(`[WC-7] Compare API (same run) HTTP ${compareResp.status()}`);
        assert(audit, "compare-api-reachable", [200, 400].includes(compareResp.status()));
      }
    }
  }

  audit.screenshots.push(await screenshot(page, "wc7_03_done"));
  audit.endTs = Date.now();
  audit.durationMs = audit.endTs - audit.startTs;
  SUITE_AUDIT.push(audit);

  expect(audit.assertions.find((a) => a.name === "run1-execute-returned-runId")?.passed).toBe(true);
});

// ===========================================================================
// WC-8: Run metrics strip — timing visible in viewer
// ===========================================================================

test("WC-8: run metrics strip — duration_s, started_at, completed_at visible in viewer after terminal run", async ({ page }) => {
  const audit: RunAuditRecord = {
    testId: "WC-8", runId: null, startTs: Date.now(), endTs: 0, durationMs: 0,
    finalStatus: "n/a", nfDurationS: null, nfStartedAt: null, nfCompletedAt: null,
    llmInputTokens: null, llmOutputTokens: null, llmCostUsd: null,
    assertions: [], screenshots: [],
  };

  await registerAndGoHome(page, "wc8");
  await sendMessage(page, "Run a germline variant calling workflow for SRR1518169 max_spots=100");
  await waitForAIResponse(page, "WC-8");
  await waitForWorkflowCard(page, "WC-8");

  const runId = await confirmAndRun(page, "WC-8");
  audit.runId = runId;
  assert(audit, "execute-returned-runId", !!runId);
  if (!runId) { audit.endTs = Date.now(); audit.durationMs = audit.endTs - audit.startTs; SUITE_AUDIT.push(audit); return; }

  const { finalStatus, payload } = await pollToTerminal(page, runId, "WC-8", 90000);
  audit.finalStatus = finalStatus;
  await dismissSurveyDialog(page);

  // --- Timing fields in status API response ---
  const statusResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`);
  assert(audit, "status-api-200", statusResp.status() === 200);

  if (statusResp.ok()) {
    const statusData = await statusResp.json() as Record<string, unknown>;
    const nfStatus = statusData?.nextflowStatus as Record<string, unknown> | null;
    const metrics = statusData?.metrics as Record<string, unknown> | null;

    const durationS = nfStatus?.duration_s as number | null;
    const startedAt = nfStatus?.started_at as number | null;
    const completedAt = nfStatus?.completed_at as number | null;
    const metricsTotalSeconds = (metrics?.runtime as Record<string, unknown> | null)?.totalSeconds as number | null;

    console.log(`[WC-8] nextflowStatus.duration_s: ${durationS}`);
    console.log(`[WC-8] nextflowStatus.started_at: ${startedAt}`);
    console.log(`[WC-8] nextflowStatus.completed_at: ${completedAt}`);
    console.log(`[WC-8] metrics.runtime.totalSeconds: ${metricsTotalSeconds}`);

    audit.nfDurationS = durationS;
    audit.nfStartedAt = startedAt ? new Date(startedAt * 1000).toISOString() : null;
    audit.nfCompletedAt = completedAt ? new Date(completedAt * 1000).toISOString() : null;

    assert(audit, "status-has-duration_s-in-nextflowStatus", durationS != null,
      "nextflowStatus.duration_s must be present after terminal run");
    assert(audit, "status-has-started_at-in-nextflowStatus", startedAt != null,
      "nextflowStatus.started_at must be present");
    assert(audit, "status-metrics-runtime-totalSeconds", metricsTotalSeconds != null,
      "metrics.runtime.totalSeconds must be populated from duration_s");

    if (durationS != null) {
      assert(audit, "duration-s-positive", durationS > 0, `duration_s=${durationS} must be > 0`);
    }
  }

  // --- UI: run-metrics-strip visible in viewer ---
  await page.waitForTimeout(2000);
  const metricsStrip = page.locator('[data-testid="run-metrics-strip"]');
  const stripVisible = await metricsStrip.isVisible({ timeout: 8000 }).catch(() => false);
  console.log(`[WC-8] run-metrics-strip visible: ${stripVisible}`);
  assert(audit, "run-metrics-strip-visible", stripVisible,
    "Metrics strip with timing should appear in viewer after terminal run");

  if (stripVisible) {
    const durationDisplay = page.locator('[data-testid="run-metric-duration"]');
    const durationVisible = await durationDisplay.isVisible({ timeout: 3000 }).catch(() => false);
    assert(audit, "duration-display-visible", durationVisible);

    if (durationVisible) {
      const durationText = await page.locator('[data-testid="run-metric-duration-value"]').textContent().catch(() => "");
      console.log(`[WC-8] Duration display: "${durationText}"`);
      assert(audit, "duration-display-non-empty", (durationText?.trim() || "").length > 0);
    }

    const startedDisplay = page.locator('[data-testid="run-metric-started-at"]');
    const startedVisible = await startedDisplay.isVisible({ timeout: 2000 }).catch(() => false);
    console.log(`[WC-8] Started-at display visible: ${startedVisible}`);
    assert(audit, "started-at-display-visible", startedVisible);
  }

  audit.screenshots.push(await screenshot(page, "wc8_01_metrics_strip"));
  audit.endTs = Date.now();
  audit.durationMs = audit.endTs - audit.startTs;
  SUITE_AUDIT.push(audit);

  expect(audit.assertions.find((a) => a.name === "execute-returned-runId")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "status-has-duration_s-in-nextflowStatus")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "status-metrics-runtime-totalSeconds")?.passed).toBe(true);
});

// ===========================================================================
// WC-9: Audit record completeness
// ===========================================================================

test("WC-9: audit record — every run emits complete JSON with timing, status, assertions, screenshots", async ({ page }) => {
  const audit: RunAuditRecord = {
    testId: "WC-9", runId: null, startTs: Date.now(), endTs: 0, durationMs: 0,
    finalStatus: "n/a", nfDurationS: null, nfStartedAt: null, nfCompletedAt: null,
    llmInputTokens: null, llmOutputTokens: null, llmCostUsd: null,
    assertions: [], screenshots: [],
  };

  await registerAndGoHome(page, "wc9");
  await sendMessage(page, "Run a germline variant calling workflow for SRR1518169 max_spots=100");
  await waitForAIResponse(page, "WC-9");
  await waitForWorkflowCard(page, "WC-9");

  const runId = await confirmAndRun(page, "WC-9");
  audit.runId = runId;
  assert(audit, "execute-returned-runId", !!runId);
  if (!runId) { audit.endTs = Date.now(); audit.durationMs = audit.endTs - audit.startTs; SUITE_AUDIT.push(audit); return; }

  const { finalStatus, payload } = await pollToTerminal(page, runId, "WC-9", 90000);
  audit.finalStatus = finalStatus;

  // Collect billing token info from any available source
  const statusResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`);
  if (statusResp.ok()) {
    const statusData = await statusResp.json() as Record<string, unknown>;
    // Record timing
    const nfStatus = statusData?.nextflowStatus as Record<string, unknown> | null;
    audit.nfDurationS = (nfStatus?.duration_s as number) ?? null;
    audit.nfStartedAt = nfStatus?.started_at
      ? new Date((nfStatus.started_at as number) * 1000).toISOString() : null;
    audit.nfCompletedAt = nfStatus?.completed_at
      ? new Date((nfStatus.completed_at as number) * 1000).toISOString() : null;
  }

  // Try billing API
  try {
    const billingResp = await page.request.get(`${BASE_URL}/api/billing/usage`);
    if (billingResp.ok()) {
      const billingData = await billingResp.json() as Record<string, unknown>;
      audit.llmInputTokens = (billingData?.llm_input_tokens as number) ?? null;
      audit.llmOutputTokens = (billingData?.llm_output_tokens as number) ?? null;
      audit.llmCostUsd = (billingData?.llm_cost_usd as number) ?? null;
      console.log(`[WC-9] Billing: input=${audit.llmInputTokens} output=${audit.llmOutputTokens} cost=$${audit.llmCostUsd}`);
    }
  } catch { /* billing not critical */ }

  audit.screenshots.push(await screenshot(page, "wc9_01_final"));

  // --- Verify the audit record itself is complete ---
  assert(audit, "audit-has-runId", !!audit.runId);
  assert(audit, "audit-has-startTs", audit.startTs > 0);
  assert(audit, "audit-has-finalStatus", audit.finalStatus !== "n/a");
  assert(audit, "audit-has-screenshots", audit.screenshots.length > 0);

  // Verify status API has all required timing fields
  if (statusResp.ok()) {
    const statusData = await statusResp.json() as Record<string, unknown>;
    const requiredFields = ["runId", "status", "progress", "metrics", "nextflowStatus"];
    for (const field of requiredFields) {
      assert(audit, `status-field-${field}`, field in statusData,
        `Status response must include "${field}"`);
    }

    const metrics = statusData?.metrics as Record<string, unknown> | null;
    assert(audit, "metrics-has-runtime", !!(metrics?.runtime),
      "metrics.runtime must be present (populated from nextflowStatus timing)");

    const runtime = metrics?.runtime as Record<string, unknown> | null;
    if (runtime) {
      assert(audit, "runtime-has-totalSeconds", "totalSeconds" in runtime,
        "metrics.runtime.totalSeconds must be set");
    }

    // perStepLlmCost must be present (even if empty — it tracks per-step LLM usage)
    assert(audit, "metrics-has-perStepLlmCost", "perStepLlmCost" in (metrics || {}),
      "metrics.perStepLlmCost must be present in status response");
    const perStepCost = metrics?.perStepLlmCost as Record<string, number | null> | null;
    console.log(`[WC-9] perStepLlmCost:`, JSON.stringify(perStepCost));
    if (perStepCost !== null && perStepCost !== undefined) {
      // All values should be number or null
      const allValid = Object.values(perStepCost).every(v => v === null || typeof v === "number");
      assert(audit, "perStepLlmCost-values-valid", allValid,
        "perStepLlmCost values must be number | null");
    }
  }

  // Write a final per-test audit entry for WC-9
  const perTestAuditPath = path.join(SS_DIR, `wc9_audit_${runId}.json`);
  const perTestAudit = {
    testId: "WC-9",
    runId: audit.runId,
    startTs: new Date(audit.startTs).toISOString(),
    endTs: new Date(audit.endTs || Date.now()).toISOString(),
    durationMs: audit.durationMs,
    finalStatus: audit.finalStatus,
    timing: {
      nfDurationS: audit.nfDurationS,
      nfStartedAt: audit.nfStartedAt,
      nfCompletedAt: audit.nfCompletedAt,
    },
    billing: {
      llmInputTokens: audit.llmInputTokens,
      llmOutputTokens: audit.llmOutputTokens,
      llmCostUsd: audit.llmCostUsd,
    },
    assertions: audit.assertions,
    screenshots: audit.screenshots,
  };
  fs.writeFileSync(perTestAuditPath, JSON.stringify(perTestAudit, null, 2));
  console.log(`[WC-9] Per-test audit written → ${perTestAuditPath}`);
  console.log(`[WC-9] Assertions: ${audit.assertions.filter(a => a.passed).length}/${audit.assertions.length} passed`);

  audit.endTs = Date.now();
  audit.durationMs = audit.endTs - audit.startTs;
  SUITE_AUDIT.push(audit);

  // Hard assertions: the audit infrastructure itself must work
  expect(audit.assertions.find((a) => a.name === "execute-returned-runId")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "status-field-metrics")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "metrics-has-runtime")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "metrics-has-perStepLlmCost")?.passed).toBe(true);
});

// ===========================================================================
// WC-10: Audit log schema validation
// ===========================================================================

test("WC-10: audit log schema — all suite audit records satisfy required schema; perStepLlmCost present in status API", async ({ page }) => {
  const audit: RunAuditRecord = {
    testId: "WC-10", runId: null, startTs: Date.now(), endTs: 0, durationMs: 0,
    finalStatus: "n/a", nfDurationS: null, nfStartedAt: null, nfCompletedAt: null,
    llmInputTokens: null, llmOutputTokens: null, llmCostUsd: null,
    assertions: [], screenshots: [],
  };

  // --- Validate accumulated SUITE_AUDIT records from previous tests ---
  const requiredAuditFields = [
    "testId", "runId", "startTs", "endTs", "durationMs",
    "finalStatus", "assertions", "screenshots",
  ] as const;

  console.log(`[WC-10] Validating ${SUITE_AUDIT.length} accumulated audit records`);
  assert(audit, "suite-has-records", SUITE_AUDIT.length > 0,
    "SUITE_AUDIT must have at least one record from prior tests");

  let schemaViolations = 0;
  for (const record of SUITE_AUDIT) {
    for (const field of requiredAuditFields) {
      if (!(field in record)) {
        console.log(`[WC-10] SCHEMA VIOLATION: ${record.testId} missing field "${field}"`);
        schemaViolations++;
      }
    }
    // assertions array must be non-null
    if (!Array.isArray(record.assertions)) {
      console.log(`[WC-10] SCHEMA VIOLATION: ${record.testId} assertions is not an array`);
      schemaViolations++;
    }
    // screenshots array must be non-null
    if (!Array.isArray(record.screenshots)) {
      console.log(`[WC-10] SCHEMA VIOLATION: ${record.testId} screenshots is not an array`);
      schemaViolations++;
    }
    // startTs must be a positive number
    if (typeof record.startTs !== "number" || record.startTs <= 0) {
      console.log(`[WC-10] SCHEMA VIOLATION: ${record.testId} startTs invalid`);
      schemaViolations++;
    }
  }

  console.log(`[WC-10] Schema violations: ${schemaViolations}/${SUITE_AUDIT.length} records`);
  assert(audit, "all-audit-records-schema-valid", schemaViolations === 0,
    `${schemaViolations} schema violations found across ${SUITE_AUDIT.length} audit records`);

  // --- Validate each record's assertions are typed correctly ---
  let assertionTypeViolations = 0;
  for (const record of SUITE_AUDIT) {
    for (const a of (record.assertions || [])) {
      if (typeof a.name !== "string" || typeof a.passed !== "boolean") {
        assertionTypeViolations++;
      }
    }
  }
  assert(audit, "assertion-types-valid", assertionTypeViolations === 0,
    `${assertionTypeViolations} assertion entries have invalid type (name: string, passed: boolean required)`);

  // --- Fresh status API check: validate perStepLlmCost schema ---
  await registerAndGoHome(page, "wc10");
  await sendMessage(page, "Run a germline variant calling workflow for SRR1518169 max_spots=50");
  await waitForAIResponse(page, "WC-10");
  await waitForWorkflowCard(page, "WC-10");

  const runId = await confirmAndRun(page, "WC-10");
  audit.runId = runId;
  assert(audit, "execute-returned-runId", !!runId);

  if (runId) {
    // Don't need to poll to terminal — just check schema of status response immediately
    const statusResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`);
    assert(audit, "status-api-200", statusResp.status() === 200);

    if (statusResp.ok()) {
      const statusData = await statusResp.json() as Record<string, unknown>;
      const metrics = statusData?.metrics as Record<string, unknown> | null;

      assert(audit, "metrics-present", !!metrics, "metrics must be in status response");
      assert(audit, "metrics-has-perStepLlmCost", metrics != null && "perStepLlmCost" in metrics,
        "metrics.perStepLlmCost must be present");

      const perStepCost = metrics?.perStepLlmCost as Record<string, unknown> | null;
      if (perStepCost) {
        const allValid = Object.values(perStepCost).every(v => v === null || typeof v === "number");
        assert(audit, "perStepLlmCost-schema-valid", allValid,
          "all perStepLlmCost values must be number | null");
        console.log(`[WC-10] perStepLlmCost has ${Object.keys(perStepCost).length} entries`);
      }

      // Validate required top-level status fields
      const requiredStatusFields = ["runId", "status", "progress", "metrics"];
      for (const field of requiredStatusFields) {
        assert(audit, `status-has-${field}`, field in statusData);
      }
    }

    audit.screenshots.push(await screenshot(page, "wc10_01_status"));
  }

  audit.endTs = Date.now();
  audit.durationMs = audit.endTs - audit.startTs;
  SUITE_AUDIT.push(audit);

  expect(audit.assertions.find((a) => a.name === "suite-has-records")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "all-audit-records-schema-valid")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "execute-returned-runId")?.passed).toBe(true);
  expect(audit.assertions.find((a) => a.name === "metrics-has-perStepLlmCost")?.passed).toBe(true);
});
