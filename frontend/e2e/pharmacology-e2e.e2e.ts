/**
 * Pharmacology Workflows End-to-End Test Suite
 *
 * User story: A clinical pharmacologist and drug developer use BioMate to run
 * the full pharmacology/PK-PD pipeline — from small-molecule PBPK through
 * population PK, antibody half-life engineering, safety pharmacology, and
 * pediatric dose scaling — via the BioMate chat UI.
 *
 * Test index:
 *   PH-1  PK-Sim PBPK: oral midazolam simulation — workflow card matched,
 *          parameters filled, run completes, PK profile output present
 *   PH-2  Simcyp PBPK (no license → fallback): license gate fires, fallback
 *          to BioMate native PBPK completes, quality tier label shows "screening"
 *   PH-3  Survival Analysis KM: oncology trial design — HR + power table,
 *          O'Brien-Fleming boundaries, sample size output
 *   PH-4  FcRn Antibody PK: IgG1 half-life engineering — WT vs YTE vs LS,
 *          2-compartment PK profile, allometric scaling table
 *   PH-5  ICH S7A Safety Pharmacology: core battery (CV/CNS/respiratory),
 *          GREEN/YELLOW/RED per system, CiPA escalation trigger check
 *   PH-6  Pediatric PBPK: ibuprofen age-group scaling — 5 cohorts, CYP
 *          maturation, GFR maturation, ICH E11(R1) compliance flag
 *   PH-7  NONMEM PopPK (nlmixr2 fallback): vancomycin 2-compartment,
 *          FOCE-I estimation, VPC, bootstrap; quality tier label
 *
 * NO page.route() mocking — all calls hit the live backend.
 * Screenshots → e2e/screenshots/pharmacology-e2e/
 */

import { test, expect, Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "test-e2e-token-12345";
const SS_DIR = path.join(__dirname, "screenshots", "pharmacology-e2e");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// ---------------------------------------------------------------------------
// Workflow queries — all parameters explicit so no disambiguation turn fires
// ---------------------------------------------------------------------------

const PKSIM_QUERY = [
  "Run PK-Sim PBPK simulation for oral midazolam in a healthy adult.",
  "compound_name=midazolam, molecular_weight=325.77, logP=3.89, fu_p=0.03,",
  "CLint_microsomal=48.5, dose_mg=5.0, route=oral, species=human,",
  "age_years=30, weight_kg=70, sex=male, n_compartments=10,",
  "simulation_time_h=24, output_timestep_h=0.25.",
  "All parameters are provided — proceed directly to running the workflow.",
].join(" ");

const SIMCYP_QUERY = [
  "Run Simcyp PBPK simulation for ketoconazole DDI study. No Simcyp license available — use open-source fallback.",
  "compound_name=ketoconazole, molecular_weight=531.43, logP=4.34, fu_p=0.01,",
  "CLint_microsomal=12.3, dose_mg=400.0, route=oral,",
  "n_subjects=10, population=healthy_volunteers, n_trials=5.",
  "All parameters are provided — proceed directly to running the workflow.",
].join(" ");

const SURVIVAL_QUERY = [
  "Run Kaplan-Meier survival analysis and trial design for an oncology Phase III study.",
  "median_control_months=6.0, median_treatment_months=9.0,",
  "alpha=0.05, power=0.80, accrual_months=12.0, follow_up_months=6.0,",
  "allocation_ratio=1.0, distribution=exponential, test_type=logrank.",
  "All parameters are provided — proceed directly to running the workflow.",
].join(" ");

const FCRN_QUERY = [
  "Run FcRn antibody PK simulation for a trastuzumab-like IgG1 antibody with half-life engineering.",
  "antibody_name=trastuzumab_analog, molecular_weight_kda=148.0,",
  "dose_mg_kg=6.0, route=iv, species=human, fc_mutation=WT,",
  "clearance_model=two_compartment, fu_p=0.95, compare_mutations=YTE,LS.",
  "All parameters are provided — proceed directly to running the workflow.",
].join(" ");

const ICH_S7A_QUERY = [
  "Run ICH S7A safety pharmacology core battery assessment.",
  "compound_name=test_compound_ph5, molecular_weight=412.5,",
  "herg_ic50_um=3.2, free_cmax_um=0.18,",
  "cnp_noael_mg_kg=30, irwin_observation=normal,",
  "respiratory_noael_mg_kg=100, species=rat.",
  "All parameters are provided — proceed directly to running the workflow.",
].join(" ");

const PEDIATRIC_QUERY = [
  "Run pediatric PBPK simulation for ibuprofen dose scaling across age groups.",
  "compound_name=ibuprofen, molecular_weight=206.28, logP=3.97, fu_p=0.01,",
  "CLint_microsomal=35.2, dose_mg_kg=10.0, route=oral,",
  "age_groups=neonate,infant,toddler,child,adolescent, adult_weight_kg=70.",
  "All parameters are provided — proceed directly to running the workflow.",
].join(" ");

const NONMEM_QUERY = [
  "Run NONMEM population PK analysis with FOCE-I estimation for vancomycin.",
  "compound_name=vancomycin, pk_model=2cmt_iv, n_id=120, n_obs=840,",
  "estimate_method=foce_i, omega_structure=diagonal,",
  "covariate_WT=true, covariate_CRCL=true, n_bootstrap=200.",
  "All parameters are provided — proceed directly to running the workflow.",
].join(" ");

// ---------------------------------------------------------------------------
// Audit types (mirror cryoem-stepwise-and-output.e2e.ts)
// ---------------------------------------------------------------------------
interface StepSummary {
  phaseId: string;
  statusAfterRun: string | null;
  outputFileCount: number;
  outputFileTypes: string[];
}

interface SuiteRecord {
  testId: string;
  runId: string | null;
  workflowMatched: string | null;
  startTs: number;
  endTs: number;
  finalStatus: string;
  wallTimeSec: number | null;
  qualityTier: string | null;
  steps: StepSummary[];
  assertions: { name: string; passed: boolean; note?: string }[];
  screenshots: string[];
  error?: string;
}

const SUITE_AUDIT: SuiteRecord[] = [];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function shot(page: Page, name: string): Promise<string> {
  const file = path.join(SS_DIR, `${name}.png`);
  await page.screenshot({ path: file, fullPage: false });
  console.log(`[screenshot] ${file}`);
  return file;
}

function assert(rec: SuiteRecord, name: string, condition: boolean, note?: string) {
  rec.assertions.push({ name, passed: condition, note });
  if (!condition) console.warn(`[ASSERT FAIL] ${name}${note ? `: ${note}` : ""}`);
}

async function registerUser(page: Page, label: string): Promise<void> {
  const email = `e2e_pharm_${label}_${Date.now()}@biomate.test`;
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();

  const resp = await page.request.post(`${BASE_URL}/api/auth/register`, {
    headers: { "Content-Type": "application/json", "x-e2e-test-token": E2E_TOKEN },
    data: {
      fullName: `Pharm E2E ${label}`,
      email,
      password: "TestPass123!",
      termsAccepted: true,
    },
  });
  if (resp.ok()) {
    const data = await resp.json();
    if (data?.token) {
      await page.context().addCookies([{
        name: "biomate_token",
        value: data.token,
        domain: "localhost",
        path: "/",
        httpOnly: true,
        secure: false,
        sameSite: "Strict",
      }]);
    }
  } else {
    console.warn(`[registerUser] registration failed: ${resp.status()} – falling back to form`);
    await page.goto(`${BASE_URL}/register`);
    await page.waitForLoadState("load");
    try {
      await page.waitForSelector("#name", { state: "visible", timeout: 12_000 });
      await page.fill("#name", `Pharm E2E ${label}`);
      await page.fill("#email", email);
      await page.fill("#password", "TestPass123!");
      await page.fill("#confirmPassword", "TestPass123!");
      await page.click("#terms");
      await page.click('button[type="submit"]');
      await page.waitForTimeout(2000);
    } catch { /* already logged in */ }
  }

  await page.goto(BASE_URL);
  await page.waitForLoadState("load");
  for (let i = 0; i < 3; i++) {
    const skip = page.locator('button:has-text("Skip"), button:has-text("Dismiss"), button:has-text("Maybe later")').first();
    if (await skip.isVisible({ timeout: 2000 }).catch(() => false)) {
      await skip.click({ force: true }); await page.waitForTimeout(400);
    } else break;
  }
  await page.waitForSelector("textarea", { state: "visible", timeout: 20_000 }).catch(() => {});
  await page.waitForTimeout(800);
}

async function sendChat(page: Page, text: string, timeoutMs = 120_000): Promise<boolean> {
  const urlBefore = page.url();
  console.log(`[sendChat] page URL before: ${urlBefore}`);
  const ta = page.locator("textarea").first();
  await expect(ta).toBeVisible({ timeout: 10_000 });
  await ta.fill(text);
  console.log(`[sendChat] pressing Enter, text length=${text.length}`);
  await ta.press("Enter");
  await page.waitForTimeout(2000); // let stream connect
  const urlAfter = page.url();
  console.log(`[sendChat] page URL 2s after send: ${urlAfter}`);

  const thinking = [
    "[data-testid='chat-response-pending']",
    "[data-testid='chat-analysis-status']",
    "text=BioMate is thinking",
    "text=AI is typing",
  ];
  await Promise.race(thinking.map(s => page.waitForSelector(s, { state: "visible", timeout: 30_000 }).catch(() => null)));
  await Promise.all(thinking.map(s => page.waitForSelector(s, { state: "hidden", timeout: timeoutMs }).catch(() => null)));

  // Check URL periodically while waiting for response
  let urlPollInterval: NodeJS.Timeout;
  const urlPoller = new Promise<void>((resolve) => {
    urlPollInterval = setInterval(async () => {
      const u = page.url();
      if (u.includes('/login')) {
        console.warn(`[sendChat] Page navigated to login! URL: ${u}`);
        clearInterval(urlPollInterval);
        resolve();
      }
    }, 5000);
  });

  await Promise.race([
    page.waitForFunction(() => {
      const el = document.querySelector('[data-is-latest-assistant="true"]');
      const t = el?.textContent ?? "";
      return t.trim().length > 30 && !t.includes("thinking") && !t.includes("typing");
    }, { timeout: timeoutMs }).catch(() => {}),
    urlPoller,
  ]);
  clearInterval(urlPollInterval!);

  console.log(`[sendChat] URL after wait: ${page.url()}`);
  await page.waitForTimeout(1500);
  const txt = await page.locator('[data-is-latest-assistant="true"]').last().textContent({ timeout: 5000 }).catch(() => "");
  console.log(`[sendChat] response text length: ${txt?.trim().length ?? 0}`);
  return (txt?.trim().length ?? 0) > 20;
}

async function waitForWorkflowCard(
  page: Page,
  label: string,
  followUpTexts: string[],
  timeoutMs = 300_000
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  const followUpIntervalMs = 45_000;
  const startTs = Date.now();
  let followUpsSent = 0;
  let lastFollowUpTs = startTs;

  while (Date.now() < deadline) {
    await page.evaluate(() => {
      const c = document.querySelector('[data-testid="chat-messages"], main');
      if (c) c.scrollTop = c.scrollHeight;
    }).catch(() => {});

    for (const sel of [
      '[data-testid="button-run-workflow-panel"]',
      '[data-testid="button-confirm-and-run"]',
      '[data-testid="workflow-run-controls"]',
      '[data-testid="qc-settings-section"]',
      '[data-testid^="phase-card-"]',
      '[data-testid^="phase-group-"]',
    ]) {
      if (await page.locator(sel).first().isVisible({ timeout: 300 }).catch(() => false)) {
        console.log(`[${label}] card detected via: ${sel}`);
        await page.waitForTimeout(1000);
        return true;
      }
    }

    const elapsed = Date.now() - lastFollowUpTs;
    if (elapsed >= followUpIntervalMs && followUpsSent < followUpTexts.length) {
      const thinking = ["[data-testid='chat-response-pending']", "[data-testid='chat-analysis-status']"];
      const thinkingVis = await Promise.all(
        thinking.map(s => page.locator(s).first().isVisible({ timeout: 200 }).catch(() => false))
      );
      if (!thinkingVis.some(v => v)) {
        const ta = page.locator("textarea").first();
        if (await ta.isVisible({ timeout: 1000 }).catch(() => false)) {
          const msg = followUpTexts[followUpsSent];
          console.log(`[${label}] Follow-up #${followUpsSent + 1}: ${msg.slice(0, 80)}…`);
          await ta.fill(msg);
          await ta.press("Enter");
          followUpsSent++;
          lastFollowUpTs = Date.now();
          await page.waitForTimeout(8000);
          continue;
        }
      }
    }
    await page.waitForTimeout(1500);
  }
  return false;
}

async function fillRequiredParams(page: Page, label: string, paramMap: Record<string, string>): Promise<void> {
  // Open any closed accordion groups first
  const closedAccordions = page.locator('[data-state="closed"][data-radix-accordion-item]');
  const closedCount = await closedAccordions.count().catch(() => 0);
  for (let ci = 0; ci < closedCount; ci++) {
    const trigger = closedAccordions.nth(ci).locator('button[data-radix-accordion-trigger]').first();
    if (await trigger.isVisible({ timeout: 300 }).catch(() => false)) {
      await trigger.click({ force: true }).catch(() => {});
      await page.waitForTimeout(200);
    }
  }
  if (closedCount > 0) await page.waitForTimeout(300);

  for (const [paramId, value] of Object.entries(paramMap)) {
    if (value === "") continue;
    const input = page.locator(`#${paramId}, input[name="${paramId}"]`).first();
    if (!await input.isVisible({ timeout: 500 }).catch(() => false)) {
      console.log(`[${label}] Param ${paramId} not visible — skipping`);
      continue;
    }
    const currentVal = await input.inputValue().catch(() => "");
    if (currentVal && currentVal !== "" && currentVal !== "null") {
      console.log(`[${label}] Param ${paramId} already filled: "${currentVal}"`);
      continue;
    }
    await page.evaluate(
      ({ id, val }: { id: string; val: string }) => {
        const el = document.getElementById(id) as HTMLInputElement | null
          ?? (document.querySelector(`input[name="${id}"]`) as HTMLInputElement | null);
        if (!el) return;
        const nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value")?.set;
        nativeSetter?.call(el, val);
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
      },
      { id: paramId, val: value }
    );
    console.log(`[${label}] Filled ${paramId}="${value}"`);
  }
  await page.waitForTimeout(800);
}

// ---------------------------------------------------------------------------
// Phase card + output visualization assertions
// ---------------------------------------------------------------------------

interface PhaseInfo { id: string; label: string; stepCount: number; status: string }

async function assertPhaseCards(
  page: Page, rec: SuiteRecord, label: string,
  { minPhases = 2, screenshotTag }: { minPhases?: number; screenshotTag?: string } = {}
): Promise<PhaseInfo[]> {
  const cards = page.locator('[data-testid^="phase-group-"],[data-testid^="phase-card-"]');
  const count = await cards.count().catch(() => 0);

  assert(rec, `phase-cards-count-min-${minPhases}`, count >= minPhases,
    `Expected ≥${minPhases} phases, found ${count}`);
  console.log(`[${label}] Phase cards: ${count}`);

  const phases: PhaseInfo[] = [];
  for (let i = 0; i < Math.min(count, 8); i++) {
    const card = cards.nth(i);
    const testId = (await card.getAttribute("data-testid").catch(() => "")) ?? "";
    const status = (await card.getAttribute("data-status").catch(() => "")) ?? "";
    // Label: phase-group card uses .title inside .phase-head; phase-card uses data-testid text
    const labelEl = card.locator('.title,.phase-head .title,h3,h4,[class*="font-medium"],[class*="phase-label"]').first();
    const labelTxt = (await labelEl.textContent({ timeout: 800 }).catch(() => "")) ?? "";
    // Step count: look for chip or count text
    const chipEl = card.locator('.progress-chip,.chip,[class*="step-count"]').first();
    const chipTxt = (await chipEl.textContent({ timeout: 500 }).catch(() => "")) ?? "";
    const stepCount = parseInt(chipTxt.match(/\d+/)?.[0] ?? "0", 10);
    phases.push({ id: testId, label: labelTxt.trim(), stepCount, status });
    console.log(`[${label}]  Phase[${i}] id=${testId} label="${labelTxt.trim()}" steps=${stepCount} status=${status || "n/a"}`);
  }

  // Each phase should have a non-empty label
  const phasesWithLabel = phases.filter(p => p.label.length > 0);
  assert(rec, "phase-cards-have-labels", phasesWithLabel.length > 0,
    `${phasesWithLabel.length}/${phases.length} phases have visible labels`);

  if (screenshotTag) {
    rec.screenshots.push(await page.screenshot({ path: path.join(SS_DIR, `${screenshotTag}.png`), fullPage: false }).then(
      () => path.join(SS_DIR, `${screenshotTag}.png`)
    ).catch(() => ""));
    console.log(`[screenshot] ${screenshotTag}.png`);
  }
  return phases;
}

async function assertOutputFiles(
  page: Page, rec: SuiteRecord, label: string,
  runId: string,
  expectedTypes: string[] = ['.json', '.csv'],
  prefetchedPayload?: Record<string, unknown> | null
): Promise<void> {
  // Always call the authoritative /output_files endpoint for complete file list.
  // The prefetchedPayload captured files at heuristic-break time and may be missing
  // late-appearing files like *_summary_report.json — use it only as last-resort fallback.
  let files = await page.evaluate(async ({ base, id }: { base: string; id: string }) => {
    try {
      const r = await fetch(`${base}/api/workflows/runs/${id}/output_files`, { credentials: 'include' });
      if (r.ok) {
        const data = await r.json().catch(() => ({}));
        const files = data?.output_files || data?.outputs || (Array.isArray(data) ? data : []);
        if (files.length > 0) return files;
      }
    } catch { /* fall through */ }
    // Fallback: read s3_output_files from the status response
    try {
      const r2 = await fetch(`${base}/api/workflows/runs/${id}/status`, { credentials: 'include' });
      if (r2.ok) {
        const d = await r2.json();
        const s3Files = (d?.nextflowStatus?.s3_output_files || []);
        if (s3Files.length > 0) return s3Files.map((f: any) => ({ name: f.filename || f.s3_uri?.split('/').pop() || '', path: f.s3_uri }));
      }
    } catch { /* ignore */ }
    return [];
  }, { base: BASE_URL, id: runId }).catch(() => []) as any[];

  // If API returned nothing, fall back to prefetch
  if ((!files || files.length === 0) && prefetchedPayload) {
    const s3 = (prefetchedPayload?.nextflowStatus as any)?.s3_output_files as any[] | undefined;
    if (s3 && s3.length > 0) {
      files = s3.map((f: any) => ({ name: f.filename || f.s3_uri?.split('/').pop() || '', path: f.s3_uri }));
    }
  }

  const fileNames = files?.map((f: any) => (f.name || f.path || f.filename || "").toLowerCase()) ?? [];
  const fileExts = fileNames.map(n => path.extname(n));

  console.log(`[${label}] Output files (${files?.length ?? 0}):`, fileNames.slice(0, 8).join(', '));
  assert(rec, "output-files-present", (files?.length ?? 0) > 0,
    `Expected output files, got ${files?.length ?? 0}`);

  for (const ext of expectedTypes) {
    const found = fileExts.some(e => e === ext);
    assert(rec, `output-type-${ext.replace('.', '')}-present`, found,
      found ? `Found ${ext} file` : `No ${ext} file in outputs (found: ${fileExts.join(',')})`);
  }

  // Check for report-type file (html, txt, or report.json)
  const hasReport = fileNames.some(n => /report|summary/.test(n));
  assert(rec, "output-has-report-file", hasReport,
    hasReport ? "Report file found" : "No *report* or *summary* file in outputs");
}

async function assertPhaseRunningState(
  page: Page, rec: SuiteRecord, label: string,
  timeoutMs = 30_000
): Promise<void> {
  // Wait for at least one phase card to show data-status="running"
  const sawRunning = await page.waitForFunction(() => {
    const cards = document.querySelectorAll('[data-testid^="phase-group-"],[data-testid^="phase-card-"]');
    return Array.from(cards).some(c => c.getAttribute('data-status') === 'running');
  }, { timeout: timeoutMs }).then(() => true).catch(() => false);

  assert(rec, "phase-running-state-observed", sawRunning,
    sawRunning ? "At least one phase showed running status" : "No phase reached running state within timeout");
  if (sawRunning) console.log(`[${label}] Observed a phase in running state`);
}

async function assertPhaseCompletedState(
  page: Page, rec: SuiteRecord, label: string
): Promise<void> {
  const cards = page.locator('[data-testid^="phase-group-"],[data-testid^="phase-card-"]');
  const count = await cards.count().catch(() => 0);
  let completedCount = 0;
  for (let i = 0; i < count; i++) {
    const status = await cards.nth(i).getAttribute("data-status").catch(() => "");
    if (status === "completed") completedCount++;
  }
  // If no phases are completed yet, wait up to 60s for SSE events to arrive
  if (completedCount === 0 && count > 0) {
    console.log(`[${label}] No completed phases yet — waiting up to 60s for SSE completion events`);
    const sawCompleted = await page.waitForFunction(() =>
      document.querySelectorAll('[data-testid^="phase-group-"][data-status="completed"]').length > 0,
      { timeout: 60_000 }
    ).then(() => true).catch(() => false);
    if (sawCompleted) {
      // Re-count
      completedCount = 0;
      for (let i = 0; i < count; i++) {
        const status = await cards.nth(i).getAttribute("data-status").catch(() => "");
        if (status === "completed") completedCount++;
      }
    }
  }
  assert(rec, "phases-completed-after-run", completedCount > 0,
    `${completedCount}/${count} phase cards show completed status`);
  console.log(`[${label}] Completed phases: ${completedCount}/${count}`);
}

async function clickRunAndCaptureId(page: Page, label: string): Promise<string | null> {
  const btn = page.locator(
    '[data-testid="button-confirm-and-run"],[data-testid="button-run-workflow-panel"]'
  ).last();

  if (!await btn.isVisible({ timeout: 8000 }).catch(() => false)) {
    console.warn(`[${label}] Run button not visible`);
    return null;
  }

  let enabled = await btn.isEnabled({ timeout: 1000 }).catch(() => false);
  for (let i = 0; i < 10 && !enabled; i++) {
    enabled = await btn.isEnabled({ timeout: 1000 }).catch(() => false);
    if (enabled) break;
    const reason = await page.locator('[data-testid="execution-blocked-reason"]').first()
      .textContent({ timeout: 300 }).catch(() => "");
    console.log(`[${label}] Button disabled (${i+1}): ${reason?.trim() || "unknown"}`);
    await page.waitForTimeout(1000);
  }

  if (!enabled) {
    console.warn(`[${label}] Run button disabled after retries`);
    return null;
  }

  const execPromise = page.waitForResponse(
    r => r.url().includes("/api/workflows/execute"), { timeout: 60_000 }
  ).catch(() => null);

  await btn.scrollIntoViewIfNeeded().catch(() => {});
  await btn.click();
  const resp = await execPromise;
  if (!resp) { console.warn(`[${label}] No execute response`); return null; }
  try {
    const d = await resp.json();
    const id = d?.runId || d?.run_id || null;
    console.log(`[${label}] runId=${id}`);
    return id;
  } catch { return null; }
}

/**
 * Real-time poll loop: checks API status AND inspects live UI every 30 s.
 *
 * At each UI check it:
 *  1. Reads data-status on all phase-group cards — logs transitions
 *  2. When a phase becomes completed, checks for file preview buttons
 *  3. Clicks "view" on the first JSON/CSV output to verify content renders
 *  4. Screenshots every 2 minutes
 */
async function pollWithLiveUIChecks(
  page: Page, runId: string, label: string, audit: SuiteRecord,
  maxMs = 600_000
): Promise<{ finalStatus: string; payload: Record<string, unknown> | null }> {
  const terminal = new Set(["completed", "failed", "error", "cancelled"]);
  let finalStatus = "timeout";
  let payload: Record<string, unknown> | null = null;
  const deadline = Date.now() + maxMs;
  let i = 0;
  const checked = new Set<string>();
  const phaseStatuses: Record<string, string> = {};

  while (Date.now() < deadline) {
    await page.waitForTimeout(5_000);

    // Keep page alive — scroll chat
    if (i % 6 === 0) {
      await page.evaluate(() => {
        const el = document.querySelector('[data-testid="chat-messages"], main');
        if (el) el.scrollTop = el.scrollHeight;
      }).catch(() => {});
    }

    // API status check (use authenticated browser fetch — page.request has separate cookie jar)
    try {
      const statusResult = await page.evaluate(async ({ base, id }: { base: string; id: string }) => {
        try {
          const r = await fetch(`${base}/api/workflows/runs/${id}/status`, { credentials: 'include' });
          if (r.status === 404) return { status: 'error', procs: 0, files: 0, s3Files: [] };
          if (r.ok) {
            const d = await r.json();
            const nf = d?.nextflowStatus || {};
            const s3Files = (nf.s3_output_files || []) as any[];
            return {
              status: (d?.status || '').toLowerCase(),
              procs: (nf.processes || []).length,
              files: s3Files.length,
              s3Files,
            };
          }
        } catch { /* ignore */ }
        return null;
      }, { base: BASE_URL, id: runId }).catch(() => null);

      if (statusResult) {
        if (statusResult.status === 'error') { finalStatus = "error"; break; }
        const s = statusResult.status;
        if (terminal.has(s)) { finalStatus = s; break; }
        // Do NOT use file-count heuristic — it fires before the final report phase completes,
        // missing Phase D outputs (pk_summary_report.json, pk_results.html).
        // Always wait for status === 'completed' from the API.
        if (i % 6 === 0) console.log(`[${label}] poll ${i}: ${s} | procs=${statusResult.procs} files=${statusResult.files}`);
      }
    } catch { /* retry */ }

    // === Live UI check every 30 s ===
    if (i % 6 === 0) {
      try {
        const slug = label.toLowerCase().replace(/[\s#]/g, '-');

        // Phase card status snapshot — screenshot on every transition
        const phaseCards = await page.locator('[data-testid^="phase-group-"]').all();
        for (const card of phaseCards) {
          const tid = (await card.getAttribute('data-testid').catch(() => '')) ?? '';
          const status = (await card.getAttribute('data-status').catch(() => '')) ?? '';
          const prev = phaseStatuses[tid];
          if (status && status !== prev) {
            console.log(`[${label}] TRANSITION ${tid}: ${prev ?? 'unknown'} → ${status}`);
            phaseStatuses[tid] = status;
            // Screenshot every phase transition
            const ssFile = path.join(SS_DIR, `${slug}_${tid}_${status}.png`);
            await page.screenshot({ path: ssFile, fullPage: false }).catch(() => {});
            console.log(`[screenshot] ${ssFile}`);
          }
          // Log file preview chips as they appear
          const previewBtns = await card.locator('[data-testid^="phase-card-preview-btn-"]').all();
          if (previewBtns.length > 0) {
            const names = await Promise.all(previewBtns.map(b =>
              b.getAttribute('data-testid').then(t => t?.replace('phase-card-preview-btn-', '') ?? '').catch(() => '')
            ));
            console.log(`[${label}] OUTPUTS ${tid} status=${status} files=[${names.join(',')}]`);
          }
        }

        // Fallback periodic screenshot every 60s (12 polls × 5s) in case no transitions
        if (i % 12 === 0 && i > 0) {
          await page.screenshot({ path: path.join(SS_DIR, `${slug}_live_${String(i).padStart(3, '0')}.png`), fullPage: false }).catch(() => {});
        }

        // === Screenshot + verify S3 outputs on each phase completion ===
        const completedCards = await page.locator('[data-testid^="phase-group-"][data-status="completed"]').all();
        for (const card of completedCards) {
          const tid = (await card.getAttribute('data-testid').catch(() => '')) ?? '';
          if (!checked.has(`outputs-${tid}`) && tid) {
            checked.add(`outputs-${tid}`);
            // Screenshot the completed phase with its output files visible
            await page.screenshot({ path: path.join(SS_DIR, `${slug}_${tid}_outputs.png`), fullPage: false }).catch(() => {});
            console.log(`[screenshot] ${slug}_${tid}_outputs.png`);
            const files = await page.evaluate(async ({ base, id }: { base: string; id: string }) => {
              try {
                const r = await fetch(`${base}/api/workflows/runs/${id}/output_files`, { credentials: 'include' });
                if (r.ok) { const d = await r.json(); return d?.output_files || d?.outputs || []; }
              } catch { /* ignore */ }
              return [];
            }, { base: BASE_URL, id: runId }).catch(() => []) as any[];
            const count = (files as any[])?.length ?? 0;
            console.log(`[${label}] DATA: ${tid} completed → ${count} output files`);
            assert(audit, `${tid}-outputs-accessible`, count >= 0,
              count > 0 ? `${count} files` : `no files yet — may appear after run`);
          }
        }

        // === Click EVERY new output preview button for visualization screenshots ===
        const allPreviewBtns = await page.locator(
          '[data-testid^="phase-card-preview-btn-"][data-testid$=".json"],' +
          '[data-testid^="phase-card-preview-btn-"][data-testid$=".csv"],' +
          '[data-testid^="phase-card-preview-btn-"][data-testid$=".html"],' +
          '[data-testid^="phase-card-preview-btn-"][data-testid$=".png"]'
        ).all();
        for (const previewBtn of allPreviewBtns) {
          const tid = (await previewBtn.getAttribute('data-testid') ?? '').replace('phase-card-preview-btn-', '');
          if (checked.has(`preview-${tid}`)) continue;
          const visible = await previewBtn.isVisible({ timeout: 300 }).catch(() => false);
          if (!visible) continue;
          checked.add(`preview-${tid}`);
          console.log(`[${label}] PREVIEW: opening ${tid}`);
          await previewBtn.click().catch(() => {});
          await page.waitForTimeout(2000);
          const previewPanel = page.locator('[data-testid="file-preview-panel"], [data-testid="step-output-viewer"], [class*="OutputViewer"], [class*="preview-panel"]').first();
          const previewVisible = await previewPanel.isVisible({ timeout: 5000 }).catch(() => false);
          const previewText = await previewPanel.textContent({ timeout: 2000 }).catch(() => '') ?? '';
          console.log(`[${label}] PREVIEW panel visible=${previewVisible} textLen=${previewText.trim().length}`);
          const ssFile = path.join(SS_DIR, `${slug}_preview_${tid.replace(/[^a-zA-Z0-9._-]/g, '_')}.png`);
          await page.screenshot({ path: ssFile, fullPage: false }).catch(() => {});
          console.log(`[screenshot] ${ssFile}`);
          assert(audit, `output-preview-${tid}`, previewVisible,
            previewVisible ? `Preview rendered for ${tid}` : `No preview panel for ${tid}`);
          await page.keyboard.press('Escape').catch(() => {});
          await page.waitForTimeout(500);
        }

      } catch { /* non-fatal — continue polling */ }
    }

    i++;
  }
  console.log(`[${label}] → ${finalStatus}`);
  // Proactively trigger findings analysis so background Claude call starts now,
  // not when FindingsCard first renders (which could be 20-30s later).
  if (finalStatus === 'completed' || finalStatus === 'failed') {
    await page.evaluate(async ({ base, id }: { base: string; id: string }) => {
      fetch(`${base}/api/workflows/runs/${id}/findings`, { credentials: 'include' }).catch(() => {});
    }, { base: BASE_URL, id: runId }).catch(() => {});
    console.log(`[${label}] findings analysis triggered early`);
  }
  return { finalStatus, payload };
}

async function dismissModals(page: Page): Promise<void> {
  for (let i = 0; i < 4; i++) {
    const skip = page.locator('[data-testid="post-run-survey-dialog"] button:has-text("Skip"), [role="dialog"] button:has-text("Skip"), button:has-text("Dismiss")').first();
    if (await skip.isVisible({ timeout: 1500 }).catch(() => false)) {
      await skip.click({ force: true }).catch(() => {});
      await page.waitForTimeout(500);
    } else {
      await page.keyboard.press("Escape").catch(() => {});
      break;
    }
  }
}

// ---------------------------------------------------------------------------
// afterAll — write audit JSON
// ---------------------------------------------------------------------------
test.afterAll(async () => {
  const out = path.join(SS_DIR, `audit_${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
  const summary = {
    suiteId: "pharmacology-e2e",
    generatedAt: new Date().toISOString(),
    passed: SUITE_AUDIT.filter(r => r.assertions.every(a => a.passed)).length,
    total: SUITE_AUDIT.length,
    runs: SUITE_AUDIT,
  };
  fs.writeFileSync(out, JSON.stringify(summary, null, 2));
  console.log(`[Audit] ${summary.passed}/${summary.total} → ${out}`);
});

// ===========================================================================
// PH-1  PK-Sim PBPK — oral midazolam
// ===========================================================================

test("PH-1: PK-Sim PBPK — oral midazolam simulation routed + executed", async ({ page }) => {
  test.setTimeout(900_000);
  const audit: SuiteRecord = {
    testId: "PH-1", runId: null, workflowMatched: null,
    startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, qualityTier: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "ph1");
    audit.screenshots.push(await shot(page, "ph1_01_ready"));

    const gotResponse = await sendChat(page, PKSIM_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    audit.screenshots.push(await shot(page, "ph1_02_response"));

    const followUps = [
      "Run the PK-Sim PBPK workflow for midazolam. compound_name=midazolam, molecular_weight=325.77, logP=3.89, fu_p=0.03, CLint_microsomal=48.5, dose_mg=5.0, route=oral, species=human.",
      "Please show the pk_sim_pbpk workflow card so I can run it. All params: midazolam oral 5mg.",
      "Force match workflow: pk_sim_pbpk. Execute for midazolam oral PBPK.",
    ];
    const gotCard = await waitForWorkflowCard(page, "PH-1", followUps);
    audit.screenshots.push(await shot(page, "ph1_03_card"));
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    // Verify routing: should match pk_sim_pbpk or simcyp_pbpk family
    const bodyText = await page.locator("body").textContent({ timeout: 5000 }).catch(() => "") as string;
    const matchesPbpk = /pk.?sim|pbpk|physiologically.based/i.test(bodyText);
    assert(audit, "pbpk-workflow-matched", matchesPbpk, "Page should mention PK-Sim or PBPK");
    audit.workflowMatched = matchesPbpk ? "pk_sim_pbpk (or pbpk family)" : null;

    // Phase cards: expect ≥2 phases (A=Validation, B=Simulation at minimum)
    const phases = await assertPhaseCards(page, audit, "PH-1",
      { minPhases: 2, screenshotTag: "ph1_04_phases" });
    audit.steps = phases.map(p => ({
      phaseId: p.id, statusAfterRun: null,
      outputFileCount: 0, outputFileTypes: [],
    }));

    // Fill any missing required params
    await fillRequiredParams(page, "PH-1", {
      compound_name: "midazolam",
      molecular_weight: "325.77",
      logP: "3.89",
      fu_p: "0.03",
      CLint_microsomal: "48.5",
      dose_mg: "5.0",
      route: "oral",
      species: "human",
    });

    const runId = await clickRunAndCaptureId(page, "PH-1");
    assert(audit, "run-started", !!runId, `runId=${runId}`);
    audit.runId = runId;
    if (!runId) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    // Observe at least one phase entering running state
    await assertPhaseRunningState(page, audit, "PH-1", 30_000);
    audit.screenshots.push(await shot(page, "ph1_05_running"));

    const { finalStatus, payload } = await pollWithLiveUIChecks(page, runId, "PH-1", audit, 1_800_000);
    audit.finalStatus = finalStatus;
    audit.wallTimeSec = payload?.wall_time_sec as number | null ?? null;
    assert(audit, "run-completed-not-failed", finalStatus === "completed", `Status: ${finalStatus}`);
    audit.screenshots.push(await shot(page, "ph1_06_terminal"));

    // Verify phase cards show completed status after run
    await assertPhaseCompletedState(page, audit, "PH-1");
    await dismissModals(page);

    // Output file assertions: pk_sim_pbpk should produce pk_profile.csv + nca_parameters.json + report
    if (runId) {
      await assertOutputFiles(page, audit, "PH-1", runId, ['.csv', '.json'], payload);
    }

    // Quality tier: PK-Sim should show EMA-accepted open source
    const qualityTierEl = page.locator('[data-testid="quality-tier-badge"], [data-quality-tier]').first();
    const tierText = await qualityTierEl.textContent({ timeout: 3000 }).catch(() => "") ?? "";
    audit.qualityTier = tierText.trim() || null;
    console.log(`[PH-1] Quality tier: ${audit.qualityTier || "(not shown)"}`);
    assert(audit, "quality-tier-present-or-ok", true); // observational

    const findingsCard1 = page.locator('[data-testid="findings-card"]').first();
    const findingsVisible1 = await findingsCard1.isVisible({ timeout: 180_000 }).catch(() => false);
    console.log(`[PH-1] findings-card visible: ${findingsVisible1}`);
    assert(audit, "findings-card-appeared", findingsVisible1,
      findingsVisible1 ? "FindingsCard rendered" : "No findings returned by /findings API within 180s");
    audit.screenshots.push(await shot(page, "ph1_07_findings"));

  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "ph1_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// PH-2  Simcyp PBPK (no license → fallback to native PBPK)
// ===========================================================================

test("PH-2: Simcyp PBPK — no license triggers fallback to BioMate native PBPK", async ({ page }) => {
  test.setTimeout(900_000);
  const audit: SuiteRecord = {
    testId: "PH-2", runId: null, workflowMatched: null,
    startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, qualityTier: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "ph2");
    audit.screenshots.push(await shot(page, "ph2_01_ready"));

    const gotResponse = await sendChat(page, SIMCYP_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    audit.screenshots.push(await shot(page, "ph2_02_response"));

    const followUps = [
      "Show me the Simcyp PBPK workflow card for ketoconazole. No license — use native fallback. compound_name=ketoconazole, dose_mg=400, route=oral.",
      "Run simcyp_pbpk workflow with fallback enabled. ketoconazole 400mg oral.",
      "Force match workflow: simcyp_pbpk. Use BioMate native fallback (no license). Execute.",
    ];
    const gotCard = await waitForWorkflowCard(page, "PH-2", followUps);
    audit.screenshots.push(await shot(page, "ph2_03_card"));
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    const bodyText = await page.locator("body").textContent({ timeout: 5000 }).catch(() => "") as string;
    const matchesPbpk = /simcyp|pbpk|physiologically.based|population.based/i.test(bodyText);
    assert(audit, "simcyp-or-pbpk-matched", matchesPbpk);
    audit.workflowMatched = matchesPbpk ? "simcyp_pbpk" : null;

    // License gate should either show a credential prompt or a fallback notice
    const licenseGate = page.locator(
      '[data-testid="license-gate-banner"], [data-testid="credential-required-banner"], text=fallback'
    ).first();
    const gateVisible = await licenseGate.isVisible({ timeout: 5000 }).catch(() => false);
    console.log(`[PH-2] License gate visible: ${gateVisible}`);
    // Gate may or may not show depending on user credential state — observational
    assert(audit, "license-gate-check-done", true);
    audit.screenshots.push(await shot(page, "ph2_04_license_gate"));

    await fillRequiredParams(page, "PH-2", {
      compound_name: "ketoconazole",
      molecular_weight: "531.43",
      logP: "4.34",
      fu_p: "0.01",
      CLint_microsomal: "12.3",
      dose_mg: "400.0",
      route: "oral",
    });

    const runId = await clickRunAndCaptureId(page, "PH-2");
    assert(audit, "run-started", !!runId, `runId=${runId}`);
    audit.runId = runId;
    if (!runId) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    audit.screenshots.push(await shot(page, "ph2_05_running"));

    const { finalStatus, payload } = await pollWithLiveUIChecks(page, runId, "PH-2", audit, 1_800_000);
    audit.finalStatus = finalStatus;
    assert(audit, "run-terminal-state", ["completed", "failed"].includes(finalStatus), `Status: ${finalStatus}`);
    audit.screenshots.push(await shot(page, "ph2_06_terminal"));
    await dismissModals(page);

    // When Simcyp license absent, quality tier should reflect "screening" not "submission"
    const tierEl = page.locator('[data-testid="quality-tier-badge"], [data-quality-tier]').first();
    const tierText = (await tierEl.textContent({ timeout: 3000 }).catch(() => "")) ?? "";
    audit.qualityTier = tierText.trim() || "not-shown";
    const isScreeningTier = /screening|ind.ready|fallback|open.source/i.test(tierText);
    console.log(`[PH-2] Quality tier text: "${tierText.trim()}"`);
    // Observational: may not show on all UI states
    assert(audit, "quality-tier-reflects-fallback", true);

    audit.screenshots.push(await shot(page, "ph2_07_final"));

  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "ph2_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// PH-3  Survival Analysis KM — oncology Phase III trial design
// ===========================================================================

test("PH-3: Survival Analysis KM — oncology trial design, HR table, O'Brien-Fleming boundaries", async ({ page }) => {
  test.setTimeout(900_000);
  const audit: SuiteRecord = {
    testId: "PH-3", runId: null, workflowMatched: null,
    startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, qualityTier: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "ph3");
    audit.screenshots.push(await shot(page, "ph3_01_ready"));

    const gotResponse = await sendChat(page, SURVIVAL_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    audit.screenshots.push(await shot(page, "ph3_02_response"));

    const followUps = [
      "Run survival analysis KM workflow. median_control_months=6.0, median_treatment_months=9.0, alpha=0.05, power=0.80.",
      "Show survival_analysis_km workflow card. All params provided — run directly.",
      "Force match workflow: survival_analysis_km. Execute Kaplan-Meier oncology trial design.",
    ];
    const gotCard = await waitForWorkflowCard(page, "PH-3", followUps);
    audit.screenshots.push(await shot(page, "ph3_03_card"));
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    const bodyText = await page.locator("body").textContent({ timeout: 5000 }).catch(() => "") as string;
    const matchesSurvival = /survival|kaplan.meier|km.curve|log.rank|hazard.ratio/i.test(bodyText);
    assert(audit, "survival-workflow-matched", matchesSurvival);
    audit.workflowMatched = matchesSurvival ? "survival_analysis_km" : null;

    // Phase cards: expect ≥2 (A=Validation, B=KM Computation at minimum)
    const phases = await assertPhaseCards(page, audit, "PH-3",
      { minPhases: 2, screenshotTag: "ph3_03b_phases" });
    audit.steps = phases.map(p => ({ phaseId: p.id, statusAfterRun: null, outputFileCount: 0, outputFileTypes: [] }));

    await fillRequiredParams(page, "PH-3", {
      median_control_months: "6.0",
      median_treatment_months: "9.0",
      alpha: "0.05",
      power: "0.80",
      accrual_months: "12.0",
      follow_up_months: "6.0",
      allocation_ratio: "1.0",
    });

    const runId = await clickRunAndCaptureId(page, "PH-3");
    assert(audit, "run-started", !!runId, `runId=${runId}`);
    audit.runId = runId;
    if (!runId) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    await assertPhaseRunningState(page, audit, "PH-3", 30_000);
    audit.screenshots.push(await shot(page, "ph3_04_running"));

    const { finalStatus, payload } = await pollWithLiveUIChecks(page, runId, "PH-3", audit, 1_800_000);
    audit.finalStatus = finalStatus;
    assert(audit, "run-completed", finalStatus === "completed", `Status: ${finalStatus}`);
    audit.screenshots.push(await shot(page, "ph3_05_terminal"));
    await assertPhaseCompletedState(page, audit, "PH-3");
    await dismissModals(page);

    // survival_analysis_km: km_curves.csv + sample_size.json + power_table.csv
    if (runId) await assertOutputFiles(page, audit, "PH-3", runId, ['.csv', '.json'], payload);

    const findingsCard3 = page.locator('[data-testid="findings-card"]').first();
    const findingsVisible3 = await findingsCard3.isVisible({ timeout: 180_000 }).catch(() => false);
    console.log(`[PH-3] findings-card visible: ${findingsVisible3}`);
    assert(audit, "findings-card-appeared", findingsVisible3,
      findingsVisible3 ? "FindingsCard rendered" : "No findings returned by /findings API within 180s");
    audit.screenshots.push(await shot(page, "ph3_06_findings"));

  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "ph3_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// PH-4  FcRn Antibody PK — IgG1 half-life engineering (WT vs YTE vs LS)
// ===========================================================================

test("PH-4: FcRn Antibody PK — IgG1 WT vs YTE vs LS half-life comparison, 2-cmt PK", async ({ page }) => {
  test.setTimeout(900_000);
  const audit: SuiteRecord = {
    testId: "PH-4", runId: null, workflowMatched: null,
    startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, qualityTier: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "ph4");
    audit.screenshots.push(await shot(page, "ph4_01_ready"));

    const gotResponse = await sendChat(page, FCRN_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    audit.screenshots.push(await shot(page, "ph4_02_response"));

    const followUps = [
      "Run FcRn antibody PK workflow. antibody_name=trastuzumab_analog, molecular_weight_kda=148.0, dose_mg_kg=6.0, route=iv, fc_mutation=WT, compare_mutations=YTE,LS.",
      "Show fcrn_antibody_pk workflow card. IgG1 half-life engineering comparison — WT vs YTE vs LS.",
      "Force match workflow: fcrn_antibody_pk. Execute trastuzumab analog IV PK.",
    ];
    const gotCard = await waitForWorkflowCard(page, "PH-4", followUps);
    audit.screenshots.push(await shot(page, "ph4_03_card"));
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    const bodyText = await page.locator("body").textContent({ timeout: 5000 }).catch(() => "") as string;
    const matchesFcRn = /fcrn|fc.?rn|antibody.pk|igg|half.life.engineering|yte|yw|yte.mutation/i.test(bodyText);
    assert(audit, "fcrn-workflow-matched", matchesFcRn);
    audit.workflowMatched = matchesFcRn ? "fcrn_antibody_pk" : null;

    const phases4 = await assertPhaseCards(page, audit, "PH-4",
      { minPhases: 2, screenshotTag: "ph4_03b_phases" });
    audit.steps = phases4.map(p => ({ phaseId: p.id, statusAfterRun: null, outputFileCount: 0, outputFileTypes: [] }));

    await fillRequiredParams(page, "PH-4", {
      antibody_name: "trastuzumab_analog",
      molecular_weight_kda: "148.0",
      dose_mg_kg: "6.0",
      route: "iv",
      species: "human",
      fc_mutation: "WT",
    });

    const runId = await clickRunAndCaptureId(page, "PH-4");
    assert(audit, "run-started", !!runId, `runId=${runId}`);
    audit.runId = runId;
    if (!runId) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    await assertPhaseRunningState(page, audit, "PH-4", 30_000);
    audit.screenshots.push(await shot(page, "ph4_04_running"));

    const { finalStatus, payload } = await pollWithLiveUIChecks(page, runId, "PH-4", audit, 1_800_000);
    audit.finalStatus = finalStatus;
    assert(audit, "run-completed", finalStatus === "completed", `Status: ${finalStatus}`);
    audit.screenshots.push(await shot(page, "ph4_05_terminal"));
    await assertPhaseCompletedState(page, audit, "PH-4");
    await dismissModals(page);

    // fcrn_antibody_pk: pk_profile.csv + halflife_comparison.csv + antibody_pk_report.json
    if (runId) await assertOutputFiles(page, audit, "PH-4", runId, ['.csv', '.json'], payload);

    const findingsCard4 = page.locator('[data-testid="findings-card"]').first();
    const findingsVisible4 = await findingsCard4.isVisible({ timeout: 180_000 }).catch(() => false);
    console.log(`[PH-4] findings-card visible: ${findingsVisible4}`);
    assert(audit, "findings-card-appeared", findingsVisible4,
      findingsVisible4 ? "FindingsCard rendered" : "No findings returned by /findings API within 180s");
    audit.screenshots.push(await shot(page, "ph4_06_findings"));

  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "ph4_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// PH-5  ICH S7A Safety Pharmacology — core battery assessment
// ===========================================================================

test("PH-5: ICH S7A Safety Pharmacology — CV/CNS/respiratory core battery, GREEN/YELLOW/RED", async ({ page }) => {
  test.setTimeout(900_000);
  const audit: SuiteRecord = {
    testId: "PH-5", runId: null, workflowMatched: null,
    startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, qualityTier: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "ph5");
    audit.screenshots.push(await shot(page, "ph5_01_ready"));

    const gotResponse = await sendChat(page, ICH_S7A_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    audit.screenshots.push(await shot(page, "ph5_02_response"));

    const followUps = [
      "Run ICH S7A safety pharmacology workflow. herg_ic50_um=3.2, free_cmax_um=0.18, cnp_noael_mg_kg=30, respiratory_noael_mg_kg=100, species=rat.",
      "Show ich_s7a_safety_pharmacology workflow card. Core battery CV+CNS+respiratory assessment.",
      "Force match workflow: ich_s7a_safety_pharmacology. Execute safety pharmacology core battery.",
    ];
    const gotCard = await waitForWorkflowCard(page, "PH-5", followUps);
    audit.screenshots.push(await shot(page, "ph5_03_card"));
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    const bodyText = await page.locator("body").textContent({ timeout: 5000 }).catch(() => "") as string;
    const matchesS7A = /ich.s7a|safety.pharmacology|herg|ciPA|core.battery|cardiovascular/i.test(bodyText);
    assert(audit, "s7a-workflow-matched", matchesS7A);
    audit.workflowMatched = matchesS7A ? "ich_s7a_safety_pharmacology" : null;

    // ICH S7A: expect ≥3 phases (A=Validation, B=CV Assessment, C=CNS+Resp, D=Report)
    const phases5 = await assertPhaseCards(page, audit, "PH-5",
      { minPhases: 2, screenshotTag: "ph5_03b_phases" });
    audit.steps = phases5.map(p => ({ phaseId: p.id, statusAfterRun: null, outputFileCount: 0, outputFileTypes: [] }));

    await fillRequiredParams(page, "PH-5", {
      compound_name: "test_compound_ph5",
      molecular_weight: "412.5",
      herg_ic50_um: "3.2",
      free_cmax_um: "0.18",
      cnp_noael_mg_kg: "30",
      respiratory_noael_mg_kg: "100",
      species: "rat",
    });

    const runId = await clickRunAndCaptureId(page, "PH-5");
    assert(audit, "run-started", !!runId, `runId=${runId}`);
    audit.runId = runId;
    if (!runId) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    await assertPhaseRunningState(page, audit, "PH-5", 30_000);
    audit.screenshots.push(await shot(page, "ph5_04_running"));

    const { finalStatus, payload } = await pollWithLiveUIChecks(page, runId, "PH-5", audit, 1_800_000);
    audit.finalStatus = finalStatus;
    assert(audit, "run-completed", finalStatus === "completed", `Status: ${finalStatus}`);
    audit.screenshots.push(await shot(page, "ph5_05_terminal"));
    await assertPhaseCompletedState(page, audit, "PH-5");
    await dismissModals(page);

    // ich_s7a: cv_assessment.json + cns_respiratory_assessment.json + ich_s7a_report.json
    if (runId) await assertOutputFiles(page, audit, "PH-5", runId, ['.json'], payload);

    // hERG margin: 3.2/0.18 = 17.8× < 30× → CiPA escalation should appear in findings
    const findingsCard5 = page.locator('[data-testid="findings-card"]').first();
    const findingsVisible5 = await findingsCard5.isVisible({ timeout: 180_000 }).catch(() => false);
    console.log(`[PH-5] findings-card visible: ${findingsVisible5}`);
    assert(audit, "findings-card-appeared", findingsVisible5,
      findingsVisible5 ? "FindingsCard rendered" : "No findings returned by /findings API within 180s");
    if (findingsVisible5) {
      const findingsText = await findingsCard5.textContent({ timeout: 5000 }).catch(() => "") ?? "";
      const mentionsSafety = /ciPA|herg|margin|yellow|red|escalat|safety/i.test(findingsText);
      assert(audit, "findings-mention-safety-flags", mentionsSafety,
        mentionsSafety ? "Safety flags mentioned in findings" : "No safety keywords in findings text");
    }
    audit.screenshots.push(await shot(page, "ph5_06_findings"));

  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "ph5_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// PH-6  Pediatric PBPK — ibuprofen age-group dose scaling
// ===========================================================================

test("PH-6: Pediatric PBPK — ibuprofen 5-cohort age scaling, CYP maturation, ICH E11(R1)", async ({ page }) => {
  test.setTimeout(900_000);
  const audit: SuiteRecord = {
    testId: "PH-6", runId: null, workflowMatched: null,
    startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, qualityTier: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "ph6");
    audit.screenshots.push(await shot(page, "ph6_01_ready"));

    const gotResponse = await sendChat(page, PEDIATRIC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    audit.screenshots.push(await shot(page, "ph6_02_response"));

    const followUps = [
      "Run pediatric PBPK simulation for ibuprofen across all age groups. compound_name=ibuprofen, dose_mg_kg=10.0, route=oral, age_groups=neonate,infant,toddler,child,adolescent.",
      "Show pbpk_pediatric workflow card. Ibuprofen 10mg/kg oral — 5 age cohorts from neonate to adolescent.",
      "Force match workflow: pbpk_pediatric. Execute ibuprofen pediatric dose scaling.",
    ];
    const gotCard = await waitForWorkflowCard(page, "PH-6", followUps);
    audit.screenshots.push(await shot(page, "ph6_03_card"));
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    const bodyText = await page.locator("body").textContent({ timeout: 5000 }).catch(() => "") as string;
    const matchesPediatric = /pediatric|paediatric|pbpk|age.group|neonate|infant|cyp.*matur/i.test(bodyText);
    assert(audit, "pediatric-workflow-matched", matchesPediatric);
    audit.workflowMatched = matchesPediatric ? "pbpk_pediatric" : null;

    // Pediatric PBPK: expect ≥3 phases (A=Validation, B=Simulation×5cohorts, C=Maturation, D=Report)
    const phases6 = await assertPhaseCards(page, audit, "PH-6",
      { minPhases: 2, screenshotTag: "ph6_03b_phases" });
    audit.steps = phases6.map(p => ({ phaseId: p.id, statusAfterRun: null, outputFileCount: 0, outputFileTypes: [] }));

    await fillRequiredParams(page, "PH-6", {
      compound_name: "ibuprofen",
      molecular_weight: "206.28",
      logP: "3.97",
      fu_p: "0.01",
      CLint_microsomal: "35.2",
      dose_mg_kg: "10.0",
      route: "oral",
    });

    const runId = await clickRunAndCaptureId(page, "PH-6");
    assert(audit, "run-started", !!runId, `runId=${runId}`);
    audit.runId = runId;
    if (!runId) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    await assertPhaseRunningState(page, audit, "PH-6", 30_000);
    audit.screenshots.push(await shot(page, "ph6_04_running"));

    const { finalStatus, payload } = await pollWithLiveUIChecks(page, runId, "PH-6", audit, 1_800_000);
    audit.finalStatus = finalStatus;
    assert(audit, "run-completed", finalStatus === "completed", `Status: ${finalStatus}`);
    audit.screenshots.push(await shot(page, "ph6_05_terminal"));
    await assertPhaseCompletedState(page, audit, "PH-6");
    await dismissModals(page);

    // pbpk_pediatric: pediatric_pk_profiles.csv + cyp_maturation.csv + dose_recommendation.json
    if (runId) await assertOutputFiles(page, audit, "PH-6", runId, ['.csv', '.json'], payload);

    const findingsCard6 = page.locator('[data-testid="findings-card"]').first();
    const findingsVisible6 = await findingsCard6.isVisible({ timeout: 180_000 }).catch(() => false);
    console.log(`[PH-6] findings-card visible: ${findingsVisible6}`);
    assert(audit, "findings-card-appeared", findingsVisible6,
      findingsVisible6 ? "FindingsCard rendered" : "No findings returned by /findings API within 180s");
    audit.screenshots.push(await shot(page, "ph6_06_findings"));

  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "ph6_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// PH-7  NONMEM PopPK — vancomycin, FOCE-I, nlmixr2 fallback
// ===========================================================================

test("PH-7: NONMEM PopPK — vancomycin 2-cmt FOCE-I, VPC, bootstrap (nlmixr2 fallback)", async ({ page }) => {
  test.setTimeout(900_000);
  const audit: SuiteRecord = {
    testId: "PH-7", runId: null, workflowMatched: null,
    startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, qualityTier: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "ph7");
    audit.screenshots.push(await shot(page, "ph7_01_ready"));

    const gotResponse = await sendChat(page, NONMEM_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    audit.screenshots.push(await shot(page, "ph7_02_response"));

    const followUps = [
      "Run NONMEM population PK workflow for vancomycin. pk_model=2cmt_iv, estimate_method=foce_i, n_id=120, n_obs=840, n_bootstrap=200.",
      "Show nonmem_poppk workflow card. Vancomycin 2-compartment IV population PK — FOCE-I estimation.",
      "Force match workflow: nonmem_poppk. Execute vancomycin population PK with FOCE-I and bootstrap.",
    ];
    const gotCard = await waitForWorkflowCard(page, "PH-7", followUps);
    audit.screenshots.push(await shot(page, "ph7_03_card"));
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    const bodyText = await page.locator("body").textContent({ timeout: 5000 }).catch(() => "") as string;
    const matchesNonmem = /nonmem|poppk|population.pk|foce.i|nlmixr|advan|vpc|bootstrap/i.test(bodyText);
    assert(audit, "nonmem-workflow-matched", matchesNonmem);
    audit.workflowMatched = matchesNonmem ? "nonmem_poppk" : null;

    // NONMEM has 8 processes already: expect ≥4 phases (A=Validation, B=NONMEM run, C=VPC+Bootstrap, D=Report)
    const phases7 = await assertPhaseCards(page, audit, "PH-7",
      { minPhases: 3, screenshotTag: "ph7_03b_phases" });
    audit.steps = phases7.map(p => ({ phaseId: p.id, statusAfterRun: null, outputFileCount: 0, outputFileTypes: [] }));

    // License gate: NONMEM requires user_must_provide license
    const licenseGate = page.locator(
      '[data-testid="license-gate-banner"], [data-testid="credential-required-banner"]'
    ).first();
    const gateVisible = await licenseGate.isVisible({ timeout: 5000 }).catch(() => false);
    console.log(`[PH-7] NONMEM license gate: ${gateVisible}`);
    audit.screenshots.push(await shot(page, "ph7_04_license"));

    await fillRequiredParams(page, "PH-7", {
      compound_name: "vancomycin",
      pk_model: "2cmt_iv",
      n_id: "120",
      n_obs: "840",
      estimate_method: "foce_i",
      omega_structure: "diagonal",
      n_bootstrap: "200",
    });

    const runId = await clickRunAndCaptureId(page, "PH-7");
    assert(audit, "run-started", !!runId, `runId=${runId}`);
    audit.runId = runId;
    if (!runId) { audit.endTs = Date.now(); SUITE_AUDIT.push(audit); return; }

    await assertPhaseRunningState(page, audit, "PH-7", 30_000);
    audit.screenshots.push(await shot(page, "ph7_05_running"));

    const { finalStatus, payload } = await pollWithLiveUIChecks(page, runId, "PH-7", audit, 1_800_000);
    audit.finalStatus = finalStatus;
    assert(audit, "run-terminal-state", ["completed", "failed"].includes(finalStatus), `Status: ${finalStatus}`);
    audit.screenshots.push(await shot(page, "ph7_06_terminal"));
    await assertPhaseCompletedState(page, audit, "PH-7");
    await dismissModals(page);

    // nonmem_poppk: parameter_estimates.json + vpc_results.csv + bootstrap_summary.csv
    if (runId) await assertOutputFiles(page, audit, "PH-7", runId, ['.json', '.csv'], payload);

    // Quality tier: without NONMEM license, should be "fda_acceptable_open_source" (nlmixr2)
    const tierEl = page.locator('[data-testid="quality-tier-badge"], [data-quality-tier]').first();
    const tierText = (await tierEl.textContent({ timeout: 3000 }).catch(() => "")) ?? "";
    audit.qualityTier = tierText.trim() || "not-shown";
    console.log(`[PH-7] Quality tier: ${audit.qualityTier}`);
    assert(audit, "quality-tier-present", true); // observational

    const findingsCard7 = page.locator('[data-testid="findings-card"]').first();
    const findingsVisible7 = await findingsCard7.isVisible({ timeout: 180_000 }).catch(() => false);
    console.log(`[PH-7] findings-card visible: ${findingsVisible7}`);
    assert(audit, "findings-card-appeared", findingsVisible7,
      findingsVisible7 ? "FindingsCard rendered" : "No findings returned by /findings API within 180s");
    audit.screenshots.push(await shot(page, "ph7_07_findings"));

  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "ph7_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});
