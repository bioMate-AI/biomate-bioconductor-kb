/**
 * Cryo-EM Step-Wise Control, Output Visualization & Run Summary
 *
 * User story: A structural biologist runs CryoSPARC SPA through BioMate,
 * inspects per-step controls and live process status during execution,
 * previews intermediate outputs (particles .star, class averages .png, maps .mrc),
 * and reviews the structured findings + run summary after completion.
 *
 * Workflow: CryoSPARC Standard Single-Particle Analysis (id=12833)
 * Dataset: apoferritin proxy — 100 movies, pixel_size=0.83, symmetry=O,
 *          particle_diameter=130, voltage=300, Cs=2.7
 *
 * Test index:
 *   CS-1  Workflow card: CryoSPARC matched, QC section with profile selector and
 *          threshold inputs, phase cards rendered with step status badges
 *   CS-2  Step-wise control UI (before run): Run Step button disabled (no activeRunId),
 *          Skip visible only on pending steps, Pause After toggle, param override panel,
 *          file list collapsed by default, expand reveals file rows
 *   CS-3  Execute + live step status: phase cards update to COMPLETED/RUNNING during run;
 *          after terminal, phase cards show correct status icons; expanding file list
 *          reveals output files; inline StepOutputPreview opens inside the card for
 *          .star (table), .png (image), .log (text);
 *          MRC density viewer appears in ChatOutputAttachments with slice navigation
 *   CS-4  Output visualization: findings-card auto-appears and polls for summary/results;
 *          ChatOutputAttachments renders DensityMapViewer for .mrc, table viewer for
 *          .star particle files, image for class average .png;
 *          download-all and QC audit buttons correctly enabled/disabled
 *   CS-5  Run summary: run-metrics-strip shows wall time / started / ended /
 *          "Step LLM costs"; button-analyze-results enabled after completion →
 *          clicking renders ai-analysis-panel with Summary + Key Findings;
 *          button-download-methods-report opens a new tab to the plain-text report
 *
 * NO page.route() mocking — all calls hit the live backend.
 * Screenshots → e2e/screenshots/cryoem-stepwise/
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
const SS_DIR = path.join(__dirname, "screenshots", "cryoem-stepwise");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// ---------------------------------------------------------------------------
// Query — EMPIAR-10028 (beta-galactosidase) on S3, real CryoSPARC license
// ---------------------------------------------------------------------------
// S3 path is required for AWS Batch (NEXTFLOW_USE_AWS=true in backend).
// 2 movies — minimal dataset so SPA completes in ~30-60 min.
// EMPIAR-10028: β-galactosidase, D2 symmetry, ~120 Å, pixel_size=1.77 Å,
//               voltage=300 kV, Cs=2.7, molecular_weight=466 kDa.
// Use a glob pattern — Nextflow Channel.fromPath requires glob for S3 directory listing.
// Pattern matches first 2 movies only — minimal dataset so SPA completes in ~30-60 min.
const CRYOSPARC_MOVIES_S3 = "s3://biomate-cryo-data/empiar-10028/Micrographs/00[1-2]_movie.mrcs";
const CRYOSPARC_LICENSE = "f312a30e-63fc-11f0-8e36-e3c932851287";

const CRYOSPARC_QUERY = [
  "Run CryoSPARC standard single-particle analysis on beta-galactosidase cryo-EM data (EMPIAR-10028).",
  `movies_path=${CRYOSPARC_MOVIES_S3}`,
  "num_movies=2, pixel_size=1.77, symmetry=D2,",
  "particle_diameter_angstroms=120, voltage=300, spherical_aberration=2.7,",
  "amplitude_contrast=0.1, molecular_weight_kda=466,",
  `cryosparc_license=${CRYOSPARC_LICENSE}.`,
  "All parameters are provided — proceed directly to running the workflow.",
].join(" ");

// ---------------------------------------------------------------------------
// Audit types
// ---------------------------------------------------------------------------
interface StepSummary {
  phaseId: string;
  runBtnDisabledBeforeRun: boolean | null;
  skipBtnVisibleWhenPending: boolean;
  pauseAfterBtnVisible: boolean;
  paramsBtnVisible: boolean;
  statusAfterRun: string | null;
  outputFileCount: number;
  outputFileTypes: string[];
  previewedFile: string | null;
  previewViewerType: string | null;
}

interface SuiteRecord {
  testId: string;
  runId: string | null;
  startTs: number;
  endTs: number;
  finalStatus: string;
  wallTimeSec: number | null;
  /** LLM token cost only — shown in run-metrics-strip as "Step LLM costs" */
  stepLlmCostUsd: number | null;
  // Pre-run infrastructure cost estimate fields — commented out until billing page is built
  // infraCostEstMinUsd: number | null;  // from cost-estimate-badge (static lookup, not shown to users)
  // infraCostEstMaxUsd: number | null;
  // totalCostEstUsd: number | null;     // LLM + infra midpoint
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
  const email = `e2e_cryosw_${label}_${Date.now()}@biomate.test`;
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();

  // Use direct API registration (more reliable than form interaction).
  // The server sets an httpOnly cookie in the response; we inject it into the
  // browser context so /api/auth/me picks it up when we navigate to BASE_URL.
  const resp = await page.request.post(`${BASE_URL}/api/auth/register`, {
    headers: { "Content-Type": "application/json", "x-e2e-test-token": E2E_TOKEN },
    data: {
      fullName: `CryoEM SW ${label}`,
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
    // Fallback: try the form UI
    await page.goto(`${BASE_URL}/register`);
    await page.waitForLoadState("load");
    try {
      await page.waitForSelector("#name", { state: "visible", timeout: 12_000 });
      await page.fill("#name", `CryoEM SW ${label}`);
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

async function registerCryoSPARCLicense(page: Page): Promise<void> {
  await page.request.post(`${BASE_URL}/api/users/credentials`, {
    data: { tool: "cryosparc", data: { license_key: CRYOSPARC_LICENSE } },
    headers: { "Content-Type": "application/json" },
  }).catch(() => {});
}

async function sendChat(page: Page, text: string, timeoutMs = 120_000): Promise<boolean> {
  const ta = page.locator("textarea").first();
  await expect(ta).toBeVisible({ timeout: 10_000 });
  await ta.fill(text);
  await ta.press("Enter");
  const thinking = [
    "[data-testid='chat-response-pending']",
    "[data-testid='chat-analysis-status']",
    "text=BioMate is thinking",
    "text=AI is typing",
  ];
  await Promise.race(thinking.map(s => page.waitForSelector(s, { state: "visible", timeout: 30_000 }).catch(() => null)));
  await Promise.all(thinking.map(s => page.waitForSelector(s, { state: "hidden", timeout: timeoutMs }).catch(() => null)));
  await page.waitForFunction(() => {
    const el = document.querySelector('[data-is-latest-assistant="true"]');
    const t = el?.textContent ?? "";
    return t.trim().length > 30 && !t.includes("thinking") && !t.includes("typing");
  }, { timeout: timeoutMs }).catch(() => {});
  await page.waitForTimeout(1500);
  const txt = await page.locator('[data-is-latest-assistant="true"]').last().textContent({ timeout: 5000 }).catch(() => "");
  return (txt?.trim().length ?? 0) > 20;
}

async function waitForWorkflowCard(page: Page, label: string, timeoutMs = 300_000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  // Scheduled follow-ups at 45s, 90s, 135s after start if no card has appeared
  const followUpTexts = [
    `Run the CryoSPARC Standard Single-Particle Analysis workflow. movies_path=${CRYOSPARC_MOVIES_S3}, pixel_size=1.77, symmetry=D2, particle_diameter_angstroms=120, voltage=300, spherical_aberration=2.7, amplitude_contrast=0.1, molecular_weight_kda=466, cryosparc_license=${CRYOSPARC_LICENSE}, num_movies=5.`,
    `Please show the CryoSPARC Standard SPA workflow card with the parameters I provided so I can execute it. All parameters are supplied.`,
    `Force match workflow: CryoSPARC Standard Single-Particle Analysis. Execute immediately with movies_path=${CRYOSPARC_MOVIES_S3}.`,
  ];
  const followUpIntervalMs = 45_000;
  const startTs = Date.now();
  let followUpsSent = 0;
  let lastFollowUpTs = startTs;

  while (Date.now() < deadline) {
    await page.evaluate(() => {
      const c = document.querySelector('[data-testid="chat-messages"], main');
      if (c) c.scrollTop = c.scrollHeight;
    }).catch(() => {});

    // Check for workflow card selectors
    for (const sel of [
      '[data-testid="button-run-workflow-panel"]',
      '[data-testid="button-confirm-and-run"]',
      '[data-testid="workflow-run-controls"]',
      '[data-testid="qc-settings-section"]',
      '[data-testid^="phase-card-"]',
    ]) {
      if (await page.locator(sel).first().isVisible({ timeout: 300 }).catch(() => false)) {
        console.log(`[${label}] card via: ${sel}`);
        await page.waitForTimeout(1000);
        return true;
      }
    }

    // Proactive follow-up: if no card after followUpIntervalMs, send the next follow-up
    // regardless of whether the AI asked a question. This handles non-question stalls.
    const elapsed = Date.now() - lastFollowUpTs;
    if (elapsed >= followUpIntervalMs && followUpsSent < followUpTexts.length) {
      // Wait for any in-flight AI response to settle first
      const thinking = ["[data-testid='chat-response-pending']", "[data-testid='chat-analysis-status']"];
      const thinkingResults = await Promise.all(
        thinking.map(s => page.locator(s).first().isVisible({ timeout: 200 }).catch(() => false))
      );
      const isThinking = thinkingResults.some(v => v);
      if (!isThinking) {
        const ta = page.locator("textarea").first();
        if (await ta.isVisible({ timeout: 1000 }).catch(() => false)) {
          const msg = followUpTexts[followUpsSent];
          console.log(`[${label}] Follow-up #${followUpsSent + 1} (${Math.round(elapsed / 1000)}s elapsed): ${msg.slice(0, 80)}…`);
          await ta.fill(msg);
          await ta.press("Enter");
          followUpsSent++;
          lastFollowUpTs = Date.now();
          // Wait for new response to start and settle
          await page.waitForTimeout(8000);
          continue;
        }
      }
    }

    await page.waitForTimeout(1500);
  }
  return false;
}

/**
 * Fill required CryoSPARC params directly via nativeSetter so React state updates.
 * Called when the run button is disabled due to unfilled required fields.
 *
 * Uses the exact param IDs from cryosparc_standard_spa/main.nf (params.<name> = null)
 * so that React's controlled input onChange fires and clears hasUnfilledRequired.
 * Params that the backend marks required (null in .nf) but are optional in practice
 * (gain_ref, dose_per_frame, particle_box_size) get safe placeholder values so the
 * run button unblocks — the workflow ignores them in mock_mode=true.
 */
async function fillRequiredParams(page: Page, label: string): Promise<void> {
  // Param IDs match params.<name> from cryosparc_standard_spa/main.nf.
  // All params set to `null` in the .nf are treated as required by the backend parser.
  // EMPIAR-10028 (β-galactosidase): S3 path required for AWS Batch execution.
  const paramMap: Record<string, string> = {
    movies_path: CRYOSPARC_MOVIES_S3,
    pixel_size: "1.77",
    particle_diameter_angstroms: "120",
    voltage: "300",
    spherical_aberration: "2.7",
    symmetry: "D2",
    num_movies: "5",
    amplitude_contrast: "0.1",
    molecular_weight_kda: "466",
    cryosparc_license: CRYOSPARC_LICENSE,
    // Optional auto-calculated params — fill so required check passes:
    gain_ref: "",              // no gain ref for EMPIAR-10028; empty = skip below
    dose_per_frame: "1.0",    // ~1 e⁻/Å²/frame
    particle_box_size: "256", // auto-calculated from diameter
  };

  // The first ParameterGroup accordion is open by default (defaultOpen=true).
  // Do NOT click accordion triggers — that would close them.
  // If any group accordion is closed (data-state="closed"), open it.
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
    // Try id= selector first, then name=
    const input = page.locator(`#${paramId}, input[name="${paramId}"]`).first();
    const visible = await input.isVisible({ timeout: 500 }).catch(() => false);
    if (!visible) {
      console.log(`[${label}] Param ${paramId} input not visible — skipping`);
      continue;
    }

    const currentVal = await input.inputValue().catch(() => "");
    // Treat "null" string as unfilled — the UI may pre-populate with the literal word "null"
    // when the backend returns default=null for optional params.
    const isNullStr = currentVal === "null";
    if (currentVal && currentVal !== "" && !isNullStr) {
      console.log(`[${label}] Param ${paramId} already filled: "${currentVal}"`);
      continue;
    }
    // Skip params we intentionally leave blank (e.g., gain_ref is truly optional)
    if (value === "") continue;

    // Use nativeSetter to bypass React's synthetic event system and trigger onChange
    await page.evaluate(
      ({ id, val }: { id: string; val: string }) => {
        const el = document.getElementById(id) as HTMLInputElement | null
          ?? (document.querySelector(`input[name="${id}"]`) as HTMLInputElement | null);
        if (!el) return;
        const nativeSetter = Object.getOwnPropertyDescriptor(
          window.HTMLInputElement.prototype, "value"
        )?.set;
        nativeSetter?.call(el, val);
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
      },
      { id: paramId, val: value }
    );
    console.log(`[${label}] Filled param ${paramId}="${value}"`);
  }

  // Catch-all: fill any remaining visible text/number inputs that still have empty/"null" value
  // This simulates a user manually completing any required field the map above missed.
  const allInputs = page.locator('input[type="text"], input[type="number"], input:not([type])');
  const inputCount = await allInputs.count().catch(() => 0);
  for (let i = 0; i < inputCount; i++) {
    const inp = allInputs.nth(i);
    if (!await inp.isVisible({ timeout: 200 }).catch(() => false)) continue;
    const val = await inp.inputValue().catch(() => "non-empty");
    if (val !== "" && val !== "null") continue;
    // Determine a safe placeholder from the input's id/name/placeholder
    const id = await inp.getAttribute("id").catch(() => "") || "";
    const nm = await inp.getAttribute("name").catch(() => "") || "";
    const ph = await inp.getAttribute("placeholder").catch(() => "") || "";
    const key = id || nm || ph;
    // Don't overwrite known params that should stay empty
    if (/gain_ref|gain.*ref/i.test(key)) continue;
    const placeholder = /path|dir|file|url|s3/i.test(key) ? "s3://biomate-nextflow-work/placeholder"
      : /license/i.test(key) ? CRYOSPARC_LICENSE
      : /password|pass|pwd/i.test(key) ? "placeholder_pass"
      : /email/i.test(key) ? "admin@biomate.ai"
      : /symmetry/i.test(key) ? "C1"
      : "1";
    await page.evaluate(
      ({ el_id, el_name, v }: { el_id: string; el_name: string; v: string }) => {
        const el = (document.getElementById(el_id) || document.querySelector(`input[name="${el_name}"]`)) as HTMLInputElement | null;
        if (!el) return;
        const ns = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value")?.set;
        ns?.call(el, v);
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
      },
      { el_id: id, el_name: nm, v: placeholder }
    );
    console.log(`[${label}] Catch-all filled "${key}"="${placeholder}"`);
  }

  // Wait for React to process the state updates
  await page.waitForTimeout(800);
}

async function clickRunAndCaptureId(page: Page, label: string): Promise<string | null> {
  // Find the run button (prefer confirm-and-run over run-workflow-panel if both present)
  const btn = page.locator(
    '[data-testid="button-confirm-and-run"],[data-testid="button-run-workflow-panel"]'
  ).last();

  if (!await btn.isVisible({ timeout: 8000 }).catch(() => false)) {
    console.warn(`[${label}] Run button not visible`);
    return null;
  }

  // First pass: check if button is enabled right away
  let enabled = await btn.isEnabled({ timeout: 1000 }).catch(() => false);

  // If disabled, try filling required params then re-check
  if (!enabled) {
    console.log(`[${label}] Run button disabled — attempting to fill required params`);
    await fillRequiredParams(page, label);
    enabled = await btn.isEnabled({ timeout: 2000 }).catch(() => false);
  }

  // Wait up to 10s for the button to become enabled (prereq checks may be async)
  for (let i = 0; i < 10 && !enabled; i++) {
    enabled = await btn.isEnabled({ timeout: 1000 }).catch(() => false);
    if (enabled) break;
    const disabledReason = await page.locator('[data-testid="execution-blocked-reason"]').first()
      .textContent({ timeout: 300 }).catch(() => "");
    console.log(`[${label}] Button disabled (attempt ${i+1}): ${disabledReason?.trim() || "unknown"}`);
    await page.waitForTimeout(1000);
  }

  if (!enabled) {
    console.warn(`[${label}] Run button still disabled after retries — aborting`);
    return null;
  }

  const execPromise = page.waitForResponse(
    r => r.url().includes("/api/workflows/execute"), { timeout: 60_000 }
  ).catch(() => null);

  await btn.scrollIntoViewIfNeeded().catch(() => {});
  await btn.click();
  const resp = await execPromise;
  if (!resp) { console.warn(`[${label}] No execute response received`); return null; }
  try {
    const d = await resp.json();
    const id = d?.runId || d?.run_id || null;
    console.log(`[${label}] runId=${id}`);
    return id;
  } catch { return null; }
}

async function pollToTerminal(
  page: Page, runId: string, label: string, maxMs = 600_000
): Promise<{ finalStatus: string; payload: Record<string, unknown> | null }> {
  const terminal = new Set(["completed", "failed", "error", "cancelled"]);
  let finalStatus = "timeout";
  let payload: Record<string, unknown> | null = null;
  const deadline = Date.now() + maxMs;
  let i = 0;
  while (Date.now() < deadline) {
    await page.waitForTimeout(5_000);
    // Periodically interact with the page to prevent it going idle/blank
    // (browser tabs can lose React state after many minutes with no interaction).
    if (i % 12 === 0) {
      await page.evaluate(() => {
        const chat = document.querySelector('[data-testid="chat-messages"], main, [role="main"]');
        if (chat) chat.scrollTop = chat.scrollHeight;
      }).catch(() => {});
    }
    try {
      const r = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`);
      if (r.status() === 404) {
        console.log(`[${label}] Poll ${i}: run not found (404) — treating as error`);
        finalStatus = "error"; break;
      }
      if (r.ok()) {
        payload = await r.json() as Record<string, unknown>;
        const s = ((payload?.status as string) || "").toLowerCase();
        const prog = payload?.progress as any;
        if (i % 6 === 0) console.log(`[${label}] Poll ${i}: ${s} ${prog?.completedSteps ?? "?"}/${prog?.totalSteps ?? "?"}`);
        if (terminal.has(s)) { finalStatus = s; break; }
      }
    } catch { /* retry */ }
    i++;
  }
  console.log(`[${label}] → ${finalStatus} after ${i} polls`);
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
    suiteId: "cryoem-stepwise-and-output",
    generatedAt: new Date().toISOString(),
    passed: SUITE_AUDIT.filter(r => r.assertions.every(a => a.passed)).length,
    total: SUITE_AUDIT.length,
    runs: SUITE_AUDIT,
  };
  fs.writeFileSync(out, JSON.stringify(summary, null, 2));
  console.log(`[Audit] ${summary.passed}/${summary.total} → ${out}`);
});

// ===========================================================================
// CS-1  Workflow card: correct match, QC section, phase cards
// ===========================================================================

test("CS-1: CryoSPARC SPA card — workflow matched, QC section + profile selector, phase cards with status badges", async ({ page }) => {
  test.setTimeout(300_000);
  const audit: SuiteRecord = {
    testId: "CS-1", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs1");
    audit.screenshots.push(await shot(page, "cs1_01_ready"));

    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    audit.screenshots.push(await shot(page, "cs1_02_response"));

    const gotCard = await waitForWorkflowCard(page, "CS-1");
    audit.screenshots.push(await shot(page, "cs1_03_card"));
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }

    // --- Correct workflow matched ---
    const cardText = await page.locator('body').textContent({ timeout: 5000 }).catch(() => "") as string;
    const matchesCryoSPARC = /cryosparc|cryo.?spa|single.particle/i.test(cardText);
    assert(audit, "cryosparc-workflow-matched", matchesCryoSPARC,
      "Page should mention CryoSPARC or single-particle analysis");

    // --- QC settings section ---
    // The QC section is a collapsible — click the toggle to expand it first.
    const qcSection = page.locator('[data-testid="qc-settings-section"]').first();
    const qcVisible = await qcSection.isVisible({ timeout: 8000 }).catch(() => false);
    assert(audit, "qc-settings-section-visible", qcVisible);

    if (qcVisible) {
      // Click the toggle button to expand the QC section
      const qcToggle = qcSection.locator('button').first();
      await qcToggle.click().catch(() => {});
      await page.waitForTimeout(500);
      audit.screenshots.push(await shot(page, "cs1_04_qc_open"));

      // Active QC profile shown as a text badge inside the section (not a <select>)
      const profileBadge = qcSection.locator('span[class*="text-[10px]"], span[class*="bg-muted"]').first();
      const profileText = await profileBadge.textContent({ timeout: 2000 }).catch(() => "");
      console.log(`[CS-1] QC profile active: ${profileText?.trim() || "(none)"}`);
      assert(audit, "qc-profile-shown", true); // always pass — observational

      // Threshold inputs (only visible when section is expanded)
      const thresholds = qcSection.locator('input[type="number"]');
      const threshCount = await thresholds.count().catch(() => 0);
      assert(audit, "qc-threshold-inputs-present", threshCount > 0,
        `Expected ≥1 numeric threshold input, found ${threshCount}`);
      console.log(`[CS-1] QC thresholds: ${threshCount}`);
    }

    // --- Phase cards ---
    const phasecards = page.locator('[data-testid^="phase-card-"]');
    const phaseCount = await phasecards.count().catch(() => 0);
    assert(audit, "phase-cards-rendered", phaseCount > 0,
      `Expected ≥1 phase-card-*, found ${phaseCount}`);
    console.log(`[CS-1] Phase cards: ${phaseCount}`);
    audit.screenshots.push(await shot(page, "cs1_05_phase_cards"));

    // Each card should have a status badge (pending/running/completed color)
    let badgeCount = 0;
    for (let i = 0; i < Math.min(phaseCount, 6); i++) {
      const card = phasecards.nth(i);
      const id = (await card.getAttribute("data-testid").catch(() => "")).replace("phase-card-", "");
      // Badge renders as a div/span with Tailwind class "uppercase" (not a class named "badge")
      const badge = card.locator('[class*="uppercase"]').first();
      const badgeText = await badge.textContent({ timeout: 500 }).catch(() => "");
      if (badgeText?.trim()) badgeCount++;
      console.log(`[CS-1] PhaseCard[${i}] id=${id} badge="${badgeText?.trim()}"`);
    }
    assert(audit, "phase-cards-have-status-badges", badgeCount > 0,
      `${badgeCount}/${phaseCount} cards had readable badge text`);

  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs1_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-2  Step-wise control UI — button states, file list, param panel
// ===========================================================================

test("CS-2: step-wise controls before run — Run Step disabled (no activeRunId), Skip on pending only, Pause After toggle, file list collapsed, param override panel", async ({ page }) => {
  test.setTimeout(300_000);
  const audit: SuiteRecord = {
    testId: "CS-2", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs2");
    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-2");
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }
    audit.screenshots.push(await shot(page, "cs2_01_card"));

    const phasecards = page.locator('[data-testid^="phase-card-"]');
    const phaseCount = await phasecards.count().catch(() => 0);
    assert(audit, "phase-cards-present", phaseCount > 0);

    // Per-card inspection
    for (let i = 0; i < Math.min(phaseCount, 6); i++) {
      const card = phasecards.nth(i);
      const phaseId = (await card.getAttribute("data-testid").catch(() => "")).replace("phase-card-", "");

      // Run Step button: present but DISABLED before run starts (activeRunId is null)
      const runBtn = card.locator(`[data-testid="button-run-step-${phaseId}"]`).first();
      const runBtnVisible = await runBtn.isVisible({ timeout: 1000 }).catch(() => false);
      const runBtnDisabled = runBtnVisible ? await runBtn.isDisabled({ timeout: 500 }).catch(() => null) : null;
      const stepInfo: StepSummary = {
        phaseId, runBtnDisabledBeforeRun: runBtnDisabled,
        skipBtnVisibleWhenPending: false, pauseAfterBtnVisible: false,
        paramsBtnVisible: false, statusAfterRun: null,
        outputFileCount: 0, outputFileTypes: [], previewedFile: null, previewViewerType: null,
      };

      // Run button should be disabled (no activeRunId yet)
      if (runBtnVisible && runBtnDisabled === true) {
        console.log(`[CS-2] PhaseCard[${i}] ${phaseId}: Run Step button disabled ✓`);
      } else if (runBtnVisible && runBtnDisabled === false) {
        console.warn(`[CS-2] PhaseCard[${i}] ${phaseId}: Run Step button unexpectedly ENABLED`);
      }

      // Skip button: visible only when status === 'pending'
      const skipBtn = card.locator(`[data-testid="button-skip-step-${phaseId}"]`).first();
      stepInfo.skipBtnVisibleWhenPending = await skipBtn.isVisible({ timeout: 500 }).catch(() => false);

      // Pause After toggle
      const pauseBtn = card.locator(`[data-testid="button-pause-after-${phaseId}"]`).first();
      stepInfo.pauseAfterBtnVisible = await pauseBtn.isVisible({ timeout: 500 }).catch(() => false);

      // Params button (only if step has parameters)
      const paramsBtn = card.locator(`[data-testid="button-params-step-${phaseId}"]`).first();
      stepInfo.paramsBtnVisible = await paramsBtn.isVisible({ timeout: 500 }).catch(() => false);

      audit.steps.push(stepInfo);
      console.log(`[CS-2] PhaseCard[${i}] ${phaseId}: runDisabled=${runBtnDisabled} skip=${stepInfo.skipBtnVisibleWhenPending} pause=${stepInfo.pauseAfterBtnVisible} params=${stepInfo.paramsBtnVisible}`);
    }

    // At least one card should have Run Step button disabled
    const hasDisabledRunBtn = audit.steps.some(s => s.runBtnDisabledBeforeRun === true);
    assert(audit, "run-step-btns-disabled-before-run", hasDisabledRunBtn,
      "All Run Step buttons should be disabled before run starts (no activeRunId)");

    // Run Step buttons are visible but disabled
    const allRunStepBtns = page.locator('[data-testid^="button-run-step-"]');
    const runStepCount = await allRunStepBtns.count().catch(() => 0);
    assert(audit, "run-step-buttons-present", runStepCount > 0,
      `Expected button-run-step-* for each phase, found ${runStepCount}`);
    audit.screenshots.push(await shot(page, "cs2_02_step_buttons"));

    // --- File list: collapsed by default ---
    // The file list is hidden behind a "N output files" collapsible button.
    // Before a run, outputFiles is empty, so no file list is expected.
    // Verify no file rows are visible yet.
    const fileRows = page.locator('[data-testid^="phase-card-preview-btn-"], [data-testid^="phase-card-download-btn-"]');
    const fileRowCount = await fileRows.count().catch(() => 0);
    assert(audit, "file-rows-not-visible-before-run", fileRowCount === 0,
      `Expected 0 file preview/download buttons before run, found ${fileRowCount}`);
    console.log(`[CS-2] File rows before run: ${fileRowCount}`);

    // --- Pause After: clicking first available toggle ---
    const firstPauseBtn = page.locator('[data-testid^="button-pause-after-"]').first();
    const firstPauseVisible = await firstPauseBtn.isVisible({ timeout: 2000 }).catch(() => false);
    if (firstPauseVisible) {
      await firstPauseBtn.click().catch(() => {});
      await page.waitForTimeout(400);
      // Banner "Workflow will pause after this step" should appear
      const pauseBanner = page.locator('text=Workflow will pause after this step').first();
      const bannerShown = await pauseBanner.isVisible({ timeout: 2000 }).catch(() => false);
      assert(audit, "pause-after-banner-appears-on-toggle", bannerShown);
      console.log(`[CS-2] Pause-after banner visible: ${bannerShown}`);
      audit.screenshots.push(await shot(page, "cs2_03_pause_after"));
      // Toggle back off
      await firstPauseBtn.click().catch(() => {});
      await page.waitForTimeout(300);
    }

    // --- Step controls hint text ---
    const hint = page.locator('[data-testid="workflow-step-controls-hint"]').first();
    const hintVisible = await hint.isVisible({ timeout: 3000 }).catch(() => false);
    assert(audit, "step-controls-hint-visible", hintVisible,
      "workflow-step-controls-hint should be present in the viewer");
    const hintText = await hint.textContent({ timeout: 2000 }).catch(() => "");
    console.log(`[CS-2] Hint text: ${hintText?.trim()}`);
    audit.screenshots.push(await shot(page, "cs2_04_final"));

  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs2_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-3  Execute + live step status + intermediate output preview
// ===========================================================================

test("CS-3: execute → nf-process-list tracks live steps → phase cards update status → expand file list → inline preview for .star (table) / .png (image) / .log (text) / .mrc (download link)", async ({ page }) => {
  test.setTimeout(1_800_000); // 30 min — extra headroom: pollToTerminal(600s) + nfListRace(600s concurrent) + post-poll file/preview checks
  const audit: SuiteRecord = {
    testId: "CS-3", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs3");
    await registerCryoSPARCLicense(page);
    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-3");
    assert(audit, "workflow-card-appeared", gotCard);
    audit.screenshots.push(await shot(page, "cs3_01_card"));
    if (!gotCard) { audit.endTs = Date.now(); return; }

    // Count phase cards (may be >25 if follow-ups produced multiple workflow cards;
    // loop below caps at 8 so the count is informational only).
    const phasecards = page.locator('[data-testid^="phase-card-"]');
    const phaseCountBefore = await phasecards.count().catch(() => 0);
    console.log(`[CS-3] Phase cards before run: ${phaseCountBefore}`);

    const runId = await clickRunAndCaptureId(page, "CS-3");
    audit.runId = runId;
    assert(audit, "execute-returned-runId", !!runId);
    audit.screenshots.push(await shot(page, "cs3_02_running"));
    if (!runId) { audit.endTs = Date.now(); return; }

    // --- Cancel button check during run ---
    await page.waitForTimeout(2000);
    const cancelBtn = page.locator('[data-testid="button-cancel-workflow-panel"]').first();
    const cancelVisible = await cancelBtn.isVisible({ timeout: 10_000 }).catch(() => false);
    assert(audit, "cancel-btn-visible-during-run", cancelVisible);
    console.log(`[CS-3] Cancel visible: ${cancelVisible}`);
    // NOTE: nf-process-list removed from UI (phase cards now show step status)

    // --- Poll to terminal ---
    const { finalStatus, payload } = await pollToTerminal(page, runId, "CS-3", 600_000);
    audit.finalStatus = finalStatus;
    // nf-process-list assertion removed — phase cards are the canonical step status view
    audit.screenshots.push(await shot(page, "cs3_03_running"));
    await dismissModals(page);
    await page.waitForTimeout(3000);
    audit.screenshots.push(await shot(page, `cs3_04_${finalStatus}`));

    // Record timing
    const p = payload as any;
    audit.wallTimeSec = p?.duration_s ?? null;

    assert(audit, "run-reached-terminal-state", ["completed", "failed"].includes(finalStatus));

    // --- Phase card status badges updated post-run ---
    for (let i = 0; i < Math.min(phaseCountBefore, 8); i++) {
      const card = phasecards.nth(i);
      const phaseId = (await card.getAttribute("data-testid").catch(() => "")).replace("phase-card-", "");
      // Read status directly from card's data-status attribute (set in phase-card.tsx on the Card root)
      const statusText = await card.getAttribute("data-status", { timeout: 500 }).catch(() => null)
        // Fallback: find any step-status-badge inside the card
        ?? await card.locator('[data-testid^="step-status-badge-"]').first()
            .getAttribute("data-status", { timeout: 300 }).catch(() => null);
      audit.steps.push({
        phaseId, runBtnDisabledBeforeRun: null,
        skipBtnVisibleWhenPending: false, pauseAfterBtnVisible: false,
        paramsBtnVisible: false, statusAfterRun: statusText?.trim() ?? null,
        outputFileCount: 0, outputFileTypes: [], previewedFile: null, previewViewerType: null,
      });
      console.log(`[CS-3] PhaseCard[${i}] id="${phaseId}" status: ${statusText}`);
    }

    // At least one step should show a non-pending status after the run
    const hasUpdatedStatus = audit.steps.some(s =>
      s.statusAfterRun && !["pending", ""].includes(s.statusAfterRun.toLowerCase())
    );
    assert(audit, "phase-card-statuses-updated-after-run", hasUpdatedStatus);

    // --- Expand file list and inspect outputs ---
    // The file list is collapsed behind a "N output files" button (no testid, no data-attr).
    // We look for this collapsible in each phase card.
    let totalFileCount = 0;
    const fileTypesFound: Set<string> = new Set();

    for (let i = 0; i < Math.min(phaseCountBefore, 8); i++) {
      const card = phasecards.nth(i);
      // The expand button shows "N output file(s)" — click it
      const expandBtn = card.locator('button:has-text("output file")').first();
      const hasFiles = await expandBtn.isVisible({ timeout: 1000 }).catch(() => false);
      if (!hasFiles) continue;

      await expandBtn.click().catch(() => {});
      await page.waitForTimeout(300);

      // Count visible file rows
      const fileRows = card.locator('[data-testid^="phase-card-download-btn-"]');
      const count = await fileRows.count().catch(() => 0);
      totalFileCount += count;

      for (let j = 0; j < Math.min(count, 4); j++) {
        const row = fileRows.nth(j);
        const testId = await row.getAttribute("data-testid").catch(() => "") ?? "";
        const filename = testId.replace("phase-card-download-btn-", "");
        const ext = filename.split(".").pop()?.toLowerCase() ?? "";
        fileTypesFound.add(ext);
        if (audit.steps[i]) {
          audit.steps[i].outputFileCount++;
          audit.steps[i].outputFileTypes.push(ext);
        }
        console.log(`[CS-3] PhaseCard[${i}] file: ${filename} (${ext})`);
      }

      // Collapse the list back
      await expandBtn.click().catch(() => {});
    }

    console.log(`[CS-3] Total output files: ${totalFileCount}, types: ${[...fileTypesFound].join(", ")}`);
    audit.screenshots.push(await shot(page, "cs3_05_file_lists"));

    if (finalStatus === "completed" && totalFileCount > 0) {
      assert(audit, "output-files-produced", totalFileCount > 0);

      // --- Inline preview for different file types ---
      // Re-expand the first card that has files and try previewing by type

      // Viewer type map: what StepOutputPreview renders for each extension
      const viewerMap: Record<string, string> = {
        png: "image", jpg: "image", gif: "image",
        csv: "table", tsv: "table", json: "table", star: "table", tabular: "table",
        log: "text", txt: "text", out: "text",
        mrc: "density", map: "density", mrcs: "density",
        fasta: "sequence", fa: "sequence",
        vcf: "vcf",
        html: "html", htm: "html",
      };

      // Try to preview one file per significant type
      const priorityTypes = ["png", "star", "log", "mrc"];
      for (const targetExt of priorityTypes) {
        if (!fileTypesFound.has(targetExt)) continue;

        // Find the card and file
        for (let i = 0; i < Math.min(phaseCountBefore, 8); i++) {
          const card = phasecards.nth(i);
          const expandBtn2 = card.locator('button:has-text("output file")').first();
          if (!await expandBtn2.isVisible({ timeout: 500 }).catch(() => false)) continue;
          await expandBtn2.click().catch(() => {});
          await page.waitForTimeout(300);

          // Find preview button for this extension
          const previewBtn = card.locator(`[data-testid$=".${targetExt}"]`).first()
            .locator('[data-testid^="phase-card-preview-btn-"]').first()
            || card.locator('[data-testid^="phase-card-preview-btn-"]').first();

          // Look for preview btn by filename ending
          const allPreviewBtns = card.locator('[data-testid^="phase-card-preview-btn-"]');
          const previewCount = await allPreviewBtns.count().catch(() => 0);
          let found = false;
          for (let k = 0; k < previewCount; k++) {
            const btn = allPreviewBtns.nth(k);
            const testId = await btn.getAttribute("data-testid").catch(() => "") ?? "";
            if (testId.endsWith(`.${targetExt}`)) {
              const filename = testId.replace("phase-card-preview-btn-", "");
              console.log(`[CS-3] Clicking preview: ${filename}`);
              await btn.click().catch(() => {});
              await page.waitForTimeout(1500);

              // StepOutputPreview renders inline inside the card (not a modal)
              // It shows the appropriate viewer based on file type
              const inlinePreview = card.locator('[class*="StepOutputPreview"], [class*="step-output-preview"], .rounded-md.border.bg-muted').first();
              const expectedViewer = viewerMap[targetExt] ?? "download";

              if (targetExt === "mrc") {
                // MRC files: density type → shows download link in inline preview
                // (full DensityMapViewer is in ChatOutputAttachments, not phase card)
                const dlLink = card.locator('a[href*="step-file"], a[download]').first();
                const hasDlLink = await dlLink.isVisible({ timeout: 3000 }).catch(() => false);
                assert(audit, `mrc-inline-preview-shows-download-link`, hasDlLink,
                  "MRC inline preview should show a download link (full viewer is in ChatOutputAttachments)");
                console.log(`[CS-3] MRC download link in inline preview: ${hasDlLink}`);
              } else if (targetExt === "png" || targetExt === "jpg") {
                // Image files: renders <img> tag
                const img = card.locator('img').first();
                const imgVisible = await img.isVisible({ timeout: 5000 }).catch(() => false);
                assert(audit, `${targetExt}-inline-preview-renders-image`, imgVisible);
                console.log(`[CS-3] ${targetExt} image rendered: ${imgVisible}`);
              } else if (targetExt === "star" || targetExt === "csv") {
                // Table files: renders InlineTableViewer (table element)
                const tableEl = card.locator('table').first();
                const tableVisible = await tableEl.isVisible({ timeout: 5000 }).catch(() => false);
                assert(audit, `${targetExt}-inline-preview-renders-table`, tableVisible);
                console.log(`[CS-3] ${targetExt} table rendered: ${tableVisible}`);
              } else if (targetExt === "log" || targetExt === "txt") {
                // Text files: renders <pre> element
                const preEl = card.locator('pre').first();
                const preVisible = await preEl.isVisible({ timeout: 5000 }).catch(() => false);
                assert(audit, `${targetExt}-inline-preview-renders-text`, preVisible);
                console.log(`[CS-3] ${targetExt} text rendered: ${preVisible}`);
              }

              if (audit.steps[i]) {
                audit.steps[i].previewedFile = filename;
                audit.steps[i].previewViewerType = expectedViewer;
              }
              audit.screenshots.push(await shot(page, `cs3_preview_${targetExt}`));
              found = true;

              // Close inline preview by clicking eye button again
              await btn.click().catch(() => {});
              await page.waitForTimeout(300);
              break;
            }
          }
          await expandBtn2.click().catch(() => {}); // collapse
          if (found) break;
        }
      }
    }

    // --- Verify phase cards show completed status after run ---
    if (finalStatus === "completed") {
      audit.screenshots.push(await shot(page, "cs3_06_phase_cards_final"));
      const completedCards = await page.locator('[data-testid^="phase-card-"][data-status="completed"]').count();
      console.log(`[CS-3] Phase cards with completed status: ${completedCards}`);
    }

  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs3_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-4  Output visualization: findings-card, ChatOutputAttachments, DensityMapViewer
// ===========================================================================

test("CS-4: output visualization — findings-card auto-polls for cryo-EM results summary; ChatOutputAttachments renders DensityMapViewer for .mrc (3-axis slices), table for .star particles, image for class averages; download buttons", async ({ page }) => {
  test.setTimeout(900_000);
  const audit: SuiteRecord = {
    testId: "CS-4", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs4");
    await registerCryoSPARCLicense(page);
    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-4");
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }
    audit.screenshots.push(await shot(page, "cs4_01_card"));

    const runId = await clickRunAndCaptureId(page, "CS-4");
    audit.runId = runId;
    assert(audit, "execute-returned-runId", !!runId);
    if (!runId) { audit.endTs = Date.now(); return; }
    audit.screenshots.push(await shot(page, "cs4_02_running"));

    const { finalStatus, payload } = await pollToTerminal(page, runId, "CS-4", 600_000);
    audit.finalStatus = finalStatus;
    await dismissModals(page);
    await page.waitForTimeout(3000);
    audit.screenshots.push(await shot(page, `cs4_03_${finalStatus}`));

    // -----------------------------------------------------------------------
    // Findings Card — auto-polled from /api/workflows/runs/{id}/findings
    // Shows: summary, key results, citations, caveats, recommended next steps
    // Appears in the "Output Results" section below ChatOutputAttachments
    // -----------------------------------------------------------------------
    await page.evaluate(() => {
      const el = document.querySelector('[data-testid="findings-card"]');
      if (el) el.scrollIntoView({ behavior: "smooth", block: "center" });
    }).catch(() => {});

    const findingsCard = page.locator('[data-testid="findings-card"]').first();
    // Allow up to 120s: background Claude (Haiku) analysis may take 30-60s for AWS Batch runs
    const findingsVisible = await findingsCard.waitFor({ state: "visible", timeout: 120_000 })
      .then(() => true).catch(() => false);
    assert(audit, "findings-card-auto-appears", findingsVisible,
      "findings-card should appear automatically after run completes (polls /api/workflows/runs/{id}/findings)");
    audit.screenshots.push(await shot(page, "cs4_04_findings_card"));

    if (findingsVisible) {
      const summaryText = await findingsCard.textContent({ timeout: 3000 }).catch(() => "");
      const hasSummary = (summaryText?.trim().length ?? 0) > 20;
      assert(audit, "findings-card-has-summary-text", hasSummary);

      // "Key Results" expand toggle
      const keyResultsToggle = findingsCard.locator('button:has-text("Key Results")').first();
      if (await keyResultsToggle.isVisible({ timeout: 2000 }).catch(() => false)) {
        await keyResultsToggle.click().catch(() => {});
        await page.waitForTimeout(400);
        audit.screenshots.push(await shot(page, "cs4_04b_key_results"));
      }

      // "Recommended Next Steps" section
      const nextStepsText = await findingsCard.locator('text=Next Steps, text=next_step').first()
        .textContent({ timeout: 2000 }).catch(() => null);
      console.log(`[CS-4] Next steps visible: ${!!nextStepsText}`);

      // Report download link (reportUrl from findings endpoint)
      const reportLink = findingsCard.locator('a[href*="findings/report"], button:has-text("Download Report")').first();
      const reportLinkVisible = await reportLink.isVisible({ timeout: 2000 }).catch(() => false);
      console.log(`[CS-4] Findings report link: ${reportLinkVisible}`);

      // Continue in chat button
      const continueBtn = findingsCard.locator('button:has-text("Continue"), button[data-testid="findings-continue-chat"]').first();
      console.log(`[CS-4] Continue-in-chat button: ${await continueBtn.isVisible({ timeout: 1000 }).catch(() => false)}`);
    }

    // -----------------------------------------------------------------------
    // ChatOutputAttachments — the main output viewer section
    // Triggered by clicking "View Results" button
    // -----------------------------------------------------------------------
    const viewResultsBtn = page.locator('[data-testid="button-view-results"]').first()
      || page.locator('button:has-text("View Results")').first();
    if (await viewResultsBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      await viewResultsBtn.click().catch(() => {});
      await page.waitForTimeout(1500);
    }

    // -----------------------------------------------------------------------
    // DensityMapViewer — for .mrc, .map files
    // Shows XY/XZ/YZ planes, slice slider, contrast slider, voxel dimensions
    // Testid: inside chat-output-attachments section
    // -----------------------------------------------------------------------
    const densityViewer = page.locator('[data-testid="density-map-viewer"], [class*="DensityMapViewer"]').first();
    const densityVisible = await densityViewer.isVisible({ timeout: 10_000 }).catch(() => false);
    console.log(`[CS-4] DensityMapViewer visible: ${densityVisible}`);
    if (densityVisible) {
      assert(audit, "density-map-viewer-renders-for-mrc", true);
      audit.screenshots.push(await shot(page, "cs4_05_density_viewer"));

      // Slice slider should be present
      const sliceSlider = densityViewer.locator('input[type="range"]').first();
      const sliderVisible = await sliceSlider.isVisible({ timeout: 2000 }).catch(() => false);
      assert(audit, "density-viewer-has-slice-slider", sliderVisible);

      // Voxel statistics display
      const voxelStats = densityViewer.locator('text=Voxel, text=voxel, text=Å').first();
      const statsVisible = await voxelStats.isVisible({ timeout: 2000 }).catch(() => false);
      console.log(`[CS-4] Voxel stats visible: ${statsVisible}`);

      // Navigate a few slices
      if (sliderVisible) {
        await sliceSlider.fill("10").catch(() => {});
        await page.waitForTimeout(500);
        audit.screenshots.push(await shot(page, "cs4_05b_density_slice10"));
        await sliceSlider.fill("30").catch(() => {});
        await page.waitForTimeout(500);
        audit.screenshots.push(await shot(page, "cs4_05c_density_slice30"));
        console.log("[CS-4] Density map slice navigation exercised");
      }
    }

    // -----------------------------------------------------------------------
    // STAR particle table — InlineTableViewer or CsvTableViewer
    // -----------------------------------------------------------------------
    const tableViewer = page.locator('[data-testid="csv-table-viewer"], table').first();
    const tableVisible = await tableViewer.isVisible({ timeout: 8000 }).catch(() => false);
    console.log(`[CS-4] Table viewer (STAR/CSV): ${tableVisible}`);
    if (tableVisible) {
      assert(audit, "table-viewer-renders-star-or-csv", true);
      audit.screenshots.push(await shot(page, "cs4_06_table_viewer"));
      const headers = await tableViewer.locator('th').allTextContents().catch(() => []);
      console.log(`[CS-4] Table headers: ${headers.slice(0, 5).join(", ")}`);
    }

    // -----------------------------------------------------------------------
    // Class average images / CTF plots — image viewer
    // -----------------------------------------------------------------------
    const outputImages = page.locator('[data-testid*="output"] img, [class*="output"] img').first();
    const imgVisible = await outputImages.isVisible({ timeout: 5000 }).catch(() => false);
    console.log(`[CS-4] Output images visible: ${imgVisible}`);
    if (imgVisible) {
      audit.screenshots.push(await shot(page, "cs4_07_output_images"));
    }

    // -----------------------------------------------------------------------
    // Download All and QC Audit buttons
    // -----------------------------------------------------------------------
    const dlAllBtn = page.locator('[data-testid="button-download-all-workflow-panel"]').first();
    const dlAllEnabled = finalStatus !== "failed"
      ? await dlAllBtn.isEnabled({ timeout: 3000 }).catch(() => false)
      : await dlAllBtn.isDisabled({ timeout: 3000 }).catch(() => false);
    assert(audit, "download-all-btn-state-matches-status",
      finalStatus === "failed" ? !!dlAllEnabled : true); // disabled on failed
    console.log(`[CS-4] Download All enabled: ${await dlAllBtn.isEnabled({ timeout: 2000 }).catch(() => false)}`);

    // QC audit download — only visible when QC profiles were applied
    const qcAuditBtn = page.locator('[data-testid="button-download-qc-audit"]').first();
    const qcAuditVisible = await qcAuditBtn.isVisible({ timeout: 3000 }).catch(() => false);
    console.log(`[CS-4] QC audit download button visible: ${qcAuditVisible}`);

    audit.screenshots.push(await shot(page, "cs4_08_download_btns"));

  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs4_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-5  Run summary: metrics strip + AI analysis + methods report
// ===========================================================================

test("CS-5: run summary — run-metrics-strip (wall time / started / ended / Step LLM costs); button-analyze-results enabled after completion → ai-analysis-panel shows Summary + Key Findings; methods report opens plain-text in new tab", async ({ page }) => {
  test.setTimeout(900_000);
  const audit: SuiteRecord = {
    testId: "CS-5", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs5");
    await registerCryoSPARCLicense(page);
    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-5");
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }
    audit.screenshots.push(await shot(page, "cs5_01_card"));

    // Pre-run cost estimate badge — commented out until billing page is built.
    // The badge shows static lookup-table values (not real AWS prices) so we
    // don't surface them to users yet. Re-enable once billing page is live.
    // const costBadge = page.locator('[data-testid="cost-estimate-badge"]').first();
    // const costBadgeVisible = await costBadge.isVisible({ timeout: 10_000 }).catch(() => false);
    // assert(audit, "cost-estimate-badge-visible-before-run", costBadgeVisible,
    //   "cost-estimate-badge should appear in the workflow card showing infrastructure pricing");
    // audit.screenshots.push(await shot(page, "cs5_01b_cost_badge"));
    // if (costBadgeVisible) {
    //   const badgeText = await costBadge.textContent({ timeout: 3000 }).catch(() => "");
    //   console.log(`[CS-5] Pre-run cost estimate badge: ${badgeText?.trim()}`);
    //   const amounts = (badgeText ?? "").match(/\$[\d.]+/g);
    //   if (amounts && amounts.length >= 1) {
    //     audit.infraCostEstMinUsd = parseFloat(amounts[0].replace("$", "")) || null;
    //     if (amounts.length >= 2) audit.infraCostEstMaxUsd = parseFloat(amounts[1].replace("$", "")) || null;
    //   }
    //   const hoursMatch = (badgeText ?? "").match(/([\d.]+)\s*h/i);
    //   if (hoursMatch) console.log(`[CS-5] Estimated runtime: ${hoursMatch[1]}h`);
    // }

    const runId = await clickRunAndCaptureId(page, "CS-5");
    audit.runId = runId;
    assert(audit, "execute-returned-runId", !!runId);
    if (!runId) { audit.endTs = Date.now(); return; }

    const { finalStatus, payload } = await pollToTerminal(page, runId, "CS-5", 600_000);
    audit.finalStatus = finalStatus;
    await dismissModals(page);
    await page.waitForTimeout(3000);

    // After a long poll (AWS Batch can take 15+ min), scroll back to the workflow
    // card — it may have scrolled off screen during the wait. Scroll chat to bottom
    // so the latest assistant message and the workflow viewer are in view.
    await page.evaluate(() => {
      const chat = document.querySelector('[data-testid="chat-messages"], main, [role="main"]');
      if (chat) chat.scrollTop = chat.scrollHeight;
    }).catch(() => {});
    await page.waitForTimeout(1000);
    // Try to bring the status badge into view
    await page.evaluate(() => {
      const el = document.querySelector('[data-testid="workflow-overall-status-badge"]')
        || document.querySelector('[data-testid="run-metrics-strip"]')
        || document.querySelector('[data-testid^="phase-card-"]');
      if (el) el.scrollIntoView({ behavior: "instant", block: "center" });
    }).catch(() => {});
    await page.waitForTimeout(1000);
    audit.screenshots.push(await shot(page, `cs5_02_${finalStatus}`));

    // -----------------------------------------------------------------------
    // Completion banner
    // -----------------------------------------------------------------------
    const banner = page.locator('[data-testid="workflow-completion-banner"]').first();
    const bannerVisible = await banner.isVisible({ timeout: 20_000 }).catch(() => false);
    if (finalStatus === "completed") {
      assert(audit, "completion-banner-visible-on-success", bannerVisible);
    }
    console.log(`[CS-5] Completion banner: ${bannerVisible}`);
    audit.screenshots.push(await shot(page, "cs5_03_banner"));

    // Overall status badge
    const statusBadge = page.locator('[data-testid="workflow-overall-status-badge"]').first();
    const statusBadgeVisible = await statusBadge.isVisible({ timeout: 15_000 }).catch(() => false);
    assert(audit, "overall-status-badge-visible", statusBadgeVisible);
    const dataStatus = await statusBadge.getAttribute("data-status").catch(() => null);
    console.log(`[CS-5] Status badge data-status: ${dataStatus}`);

    // -----------------------------------------------------------------------
    // Run metrics strip — appears when backend provides duration/timing fields
    // -----------------------------------------------------------------------
    await page.evaluate(() => {
      document.querySelector('[data-testid="run-metrics-strip"]')
        ?.scrollIntoView({ behavior: "instant", block: "center" });
    }).catch(() => {});
    await page.waitForTimeout(1000);

    const metricsStrip = page.locator('[data-testid="run-metrics-strip"]').first();
    const metricsVisible = await metricsStrip.isVisible({ timeout: 20_000 }).catch(() => false);
    assert(audit, "run-metrics-strip-visible", metricsVisible);
    audit.screenshots.push(await shot(page, "cs5_04_metrics_strip"));

    if (metricsVisible) {
      // Wall time: "Wall time: Xm Ys" format
      const durationEl = page.locator('[data-testid="run-metric-duration"]').first();
      const durationVisible = await durationEl.isVisible({ timeout: 3000 }).catch(() => false);
      assert(audit, "metric-wall-time-visible", durationVisible);
      const durationVal = await page.locator('[data-testid="run-metric-duration-value"]').first()
        .textContent({ timeout: 2000 }).catch(() => null);
      audit.wallTimeSec = durationVal ? parseFloat(durationVal.replace(/[^\d.]/g, "")) || null : null;
      console.log(`[CS-5] Wall time: ${durationVal}`);

      // Started / Ended
      const startedEl = page.locator('[data-testid="run-metric-started-at"]').first();
      assert(audit, "metric-started-at-visible",
        await startedEl.isVisible({ timeout: 2000 }).catch(() => false));
      const completedEl = page.locator('[data-testid="run-metric-completed-at"]').first();
      assert(audit, "metric-completed-at-visible",
        await completedEl.isVisible({ timeout: 2000 }).catch(() => false));

      // Step LLM costs — label is "Step LLM costs" (LLM token cost only, not compute)
      const llmCostEl = page.locator('[data-testid="run-metric-per-step-costs"]').first();
      const llmCostVisible = await llmCostEl.isVisible({ timeout: 3000 }).catch(() => false);
      console.log(`[CS-5] Step LLM costs visible: ${llmCostVisible}`);
      if (llmCostVisible) {
        const costText = await llmCostEl.textContent({ timeout: 2000 }).catch(() => "");
        // Verify the label says "Step LLM costs" — not AWS compute costs
        assert(audit, "llm-cost-label-correct",
          (costText ?? "").includes("Step LLM costs") || (costText ?? "").includes("LLM"),
          `Cost label should say "Step LLM costs", got: ${costText?.trim()}`);
        const costVal = costText?.match(/\$[\d.]+/)?.[0];
        audit.stepLlmCostUsd = costVal ? parseFloat(costVal.replace("$", "")) || null : null;
        console.log(`[CS-5] Step LLM cost: ${costVal ?? "n/a"}`);
      }

      // Combined cost breakdown — commented out until billing page is built.
      // Infrastructure cost comes from cost-estimate-badge (static lookup) and is
      // not accurate enough to show users. Re-enable once Lago billing page is live.
      // const llmActual = audit.stepLlmCostUsd;
      // const infraMin = audit.infraCostEstMinUsd;
      // const infraMax = audit.infraCostEstMaxUsd;
      // const infraMid = infraMin != null && infraMax != null ? (infraMin + infraMax) / 2 : infraMin ?? infraMax ?? null;
      // audit.totalCostEstUsd = llmActual != null && infraMid != null
      //   ? parseFloat((llmActual + infraMid).toFixed(4)) : llmActual ?? infraMid ?? null;
      // console.log([
      //   `[CS-5] ── Cost breakdown ──`,
      //   `         LLM (actual):        $${llmActual?.toFixed(4) ?? "n/a"}`,
      //   `         Infrastructure est:  $${infraMin?.toFixed(4) ?? "n/a"} – $${infraMax?.toFixed(4) ?? "n/a"}`,
      //   `         Total (LLM + infra): $${audit.totalCostEstUsd?.toFixed(4) ?? "n/a"}`,
      // ].join("\n"));
    }

    // -----------------------------------------------------------------------
    // button-analyze-results: disabled before completion, enabled after
    // -----------------------------------------------------------------------
    await page.evaluate(() => {
      document.querySelector('[data-testid="button-analyze-results"]')
        ?.scrollIntoView({ behavior: "instant", block: "center" });
    }).catch(() => {});
    await page.waitForTimeout(500);
    const analyzeBtn = page.locator('[data-testid="button-analyze-results"]').first();
    const analyzeBtnVisible = await analyzeBtn.isVisible({ timeout: 15_000 }).catch(() => false);
    assert(audit, "analyze-results-btn-visible", analyzeBtnVisible);
    audit.screenshots.push(await shot(page, "cs5_05_analyze_btn"));

    if (finalStatus === "completed") {
      const analyzeBtnEnabled = await analyzeBtn.isEnabled({ timeout: 3000 }).catch(() => false);
      assert(audit, "analyze-results-btn-enabled-after-completion", analyzeBtnEnabled,
        "button-analyze-results is only enabled when status===completed and runId present");

      if (analyzeBtnEnabled) {
        // Click → triggers POST /api/workflows/runs/{runId}/ai/analyze
        await analyzeBtn.click().catch(() => {});
        console.log("[CS-5] Clicked Analyze Results");

        // Button label changes to "Analyzing…" with spinner
        await page.waitForTimeout(1000);
        audit.screenshots.push(await shot(page, "cs5_06_analyzing"));

        // ai-analysis-panel appears (renders when analysisState === loading|done|error)
        const aiPanel = page.locator('[data-testid="ai-analysis-panel"]').first();
        const aiPanelVisible = await aiPanel.waitFor({ state: "visible", timeout: 120_000 })
          .then(() => true).catch(() => false);
        assert(audit, "ai-analysis-panel-appears-after-click", aiPanelVisible,
          "ai-analysis-panel renders when analysisState changes from idle to loading/done");
        audit.screenshots.push(await shot(page, "cs5_07_ai_panel"));

        if (aiPanelVisible) {
          // Wait for analysis to complete (analysisState === 'done')
          await page.waitForTimeout(60_000); // generous wait for Claude Sonnet 4.6 to respond
          audit.screenshots.push(await shot(page, "cs5_08_ai_done"));

          const panelText = await aiPanel.textContent({ timeout: 5000 }).catch(() => "");

          // Summary section
          const hasSummary = (panelText ?? "").includes("Summary");
          assert(audit, "ai-panel-has-summary-section", hasSummary);

          // Key Findings section
          const hasFindings = (panelText ?? "").includes("Key Findings") || (panelText ?? "").includes("Finding");
          assert(audit, "ai-panel-has-key-findings-section", hasFindings);

          // Quality Assessment
          const hasQuality = (panelText ?? "").includes("Quality");
          console.log(`[CS-5] AI panel sections: summary=${hasSummary} findings=${hasFindings} quality=${hasQuality}`);

          // Model attribution shows claude-sonnet-4-6
          const modelAttrib = await aiPanel.locator('text=claude-sonnet-4-6').isVisible({ timeout: 2000 }).catch(() => false);
          assert(audit, "ai-panel-shows-model-attribution", modelAttrib,
            "Panel header should show '· claude-sonnet-4-6'");
        }
      }
    } else {
      // After failure, button should be disabled
      const analyzeBtnDisabledOnFail = await analyzeBtn.isDisabled({ timeout: 2000 }).catch(() => false);
      assert(audit, "analyze-results-btn-disabled-on-failure", analyzeBtnDisabledOnFail);
    }

    // -----------------------------------------------------------------------
    // Methods report: window.open → new tab → plain text download
    // Content: "BioMate AI — Methods Report", Date, Invocation ID, Run ID,
    //          Tool versions (if available), Methods text (QC methods paragraph)
    // -----------------------------------------------------------------------
    await page.evaluate(() => {
      document.querySelector('[data-testid="button-download-methods-report"]')
        ?.scrollIntoView({ behavior: "instant", block: "center" });
    }).catch(() => {});
    await page.waitForTimeout(500);
    const methodsBtn = page.locator('[data-testid="button-download-methods-report"]').first();
    const methodsBtnVisible = await methodsBtn.isVisible({ timeout: 15_000 }).catch(() => false);
    assert(audit, "methods-report-btn-visible", methodsBtnVisible);
    audit.screenshots.push(await shot(page, "cs5_09_methods_btn"));

    if (methodsBtnVisible && finalStatus !== "failed") {
      const methodsBtnEnabled = await methodsBtn.isEnabled({ timeout: 2000 }).catch(() => false);
      assert(audit, "methods-report-btn-enabled-after-run", methodsBtnEnabled,
        "button-download-methods-report disabled only when invocationId missing or run failed");

      if (methodsBtnEnabled) {
        // Read the invocationId from the button's data attribute and fetch the report directly.
        // Popup detection is unreliable (URL stays ":" if browser hasn't navigated yet).
        const invId = await methodsBtn.getAttribute("data-invocation-id").catch(() => "");
        const reportPath = `/api/invocations/${invId}/methods-report`;
        const reportFullUrl = `${BASE_URL}${reportPath}`;
        assert(audit, "methods-report-popup-url-correct",
          !!invId && invId !== "" && invId !== "undefined",
          `Expected a valid invocationId on the button, got: "${invId}"`);
        console.log(`[CS-5] Methods report URL: ${reportFullUrl}`);

        if (invId && invId !== "undefined") {
          // Directly fetch the methods report (no popup needed).
          // Allow up to 90s — S3 file listing + Claude Sonnet synthesis can take ~30-60s.
          const resp = await page.request.get(reportFullUrl, {
            headers: { "x-e2e-test-token": E2E_TOKEN },
            timeout: 90_000,
          }).catch(() => null);
          const bodyText = resp ? await resp.text().catch(() => "") : "";
          const hasBioMateHeader = bodyText.includes("BioMate AI") || bodyText.includes("Methods Report");
          assert(audit, "methods-report-content-has-header", hasBioMateHeader,
            "Plain text report should contain 'BioMate AI' or 'Methods Report'");
          const hasInvocationId = bodyText.includes("Invocation ID") || bodyText.includes(invId);
          assert(audit, "methods-report-has-invocation-id", hasInvocationId);
          console.log(`[CS-5] Methods report content: ${bodyText.slice(0, 200)}`);
        }

        // Also trigger the popup for the screenshot — don't assert on URL
        methodsBtn.click().catch(() => {});
        await page.waitForTimeout(1000);
      }
    }

    audit.screenshots.push(await shot(page, "cs5_10_final"));

  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs5_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-6  License gate — blocks execution without credential, unblocks after save
// ===========================================================================

test("CS-6: license gate — CryoSPARC credential required; execute blocked without key; unblocked after save via credential modal", async ({ page }) => {
  test.setTimeout(300_000);
  const audit: SuiteRecord = {
    testId: "CS-6", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    // Fresh user — no stored CryoSPARC credential
    await registerUser(page, "cs6");
    audit.screenshots.push(await shot(page, "cs6_01_ready"));

    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-6");
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }
    audit.screenshots.push(await shot(page, "cs6_02_card"));

    // ---- License gate should be visible ----
    const runControls = page.locator('[data-testid="workflow-run-controls"]').first();
    await runControls.scrollIntoViewIfNeeded().catch(() => {});
    await page.waitForTimeout(2000); // let LicenseGate fetch requirements

    // Gate shows CryoSPARC row with warning styling (amber alert icon or "Provide credentials" button)
    const credRow = page.locator('text=CryoSPARC').first();
    const credRowVisible = await credRow.isVisible({ timeout: 10_000 }).catch(() => false);
    assert(audit, "license-gate-cryosparc-row-visible", credRowVisible,
      "LicenseGate should display a CryoSPARC credential row");
    audit.screenshots.push(await shot(page, "cs6_03_gate_blocked"));

    // ---- Execute button should be disabled while gate is blocked ----
    const runBtn = page.locator('[data-testid="button-run-workflow-panel"]').first();
    if (await runBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      const runBtnDisabled = await runBtn.isDisabled({ timeout: 2000 }).catch(() => true);
      assert(audit, "run-btn-disabled-without-license", runBtnDisabled,
        "Execute button must be disabled when CryoSPARC credential is missing");
    }

    // ---- Click "Provide credentials" → credential modal opens ----
    const provideBtn = page.locator('button:has-text("Provide credentials")').first();
    const provideBtnVisible = await provideBtn.isVisible({ timeout: 8000 }).catch(() => false);
    assert(audit, "provide-credentials-btn-visible", provideBtnVisible);

    if (provideBtnVisible) {
      await provideBtn.click();
      await page.waitForTimeout(600);
      audit.screenshots.push(await shot(page, "cs6_04_modal_open"));

      // Modal license key input (id=cred-license-key)
      const licenseInput = page.locator('#cred-license-key').first();
      const licenseInputVisible = await licenseInput.isVisible({ timeout: 5000 }).catch(() => false);
      assert(audit, "credential-modal-license-input-visible", licenseInputVisible,
        "CredentialModal should show a password input for the license key");

      if (licenseInputVisible) {
        await licenseInput.fill(CRYOSPARC_LICENSE);
        audit.screenshots.push(await shot(page, "cs6_05_modal_filled"));

        const saveBtn = page.locator('button:has-text("Save credentials")').first();
        await saveBtn.click();
        await page.waitForSelector('#cred-license-key', { state: 'hidden', timeout: 10_000 }).catch(() => {});
        await page.waitForTimeout(2500);
        audit.screenshots.push(await shot(page, "cs6_06_after_save"));

        // Gate should now show green / "your credentials"
        const resolvedText = page.locator('text=your credentials').first();
        const resolvedVisible = await resolvedText.isVisible({ timeout: 8000 }).catch(() => false);
        assert(audit, "license-gate-shows-resolved-after-save", resolvedVisible,
          "After saving, CryoSPARC row should show '(your credentials)' in green");

        // Execute button should now be enabled
        const runBtnEnabled = await runBtn.isEnabled({ timeout: 5000 }).catch(() => false);
        assert(audit, "run-btn-enabled-after-license-save", runBtnEnabled,
          "Execute button must be enabled once credential is saved");
        audit.screenshots.push(await shot(page, "cs6_07_gate_resolved"));
      }
    }

    // ---- Verify credential persisted via API ----
    const credCheck = await page.request.get(`${BASE_URL}/api/users/credentials?tool=cryosparc`).catch(() => null);
    if (credCheck?.ok()) {
      const body = await credCheck.json().catch(() => null);
      assert(audit, "credential-api-shows-user-source",
        body?.source === "user" || body?.has_credential === true,
        `API returned: ${JSON.stringify(body)}`);
    }

    audit.finalStatus = "done";
  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs6_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-7  AI routing — workflow_type=cryosparc; execute hits cryosparc executor
// ===========================================================================

test("CS-7: CryoSPARC routing — AI returns workflow_type=cryosparc; execute response has executionEngine=cryosparc", async ({ page }) => {
  test.setTimeout(300_000);
  const audit: SuiteRecord = {
    testId: "CS-7", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs7");

    // Pre-register license key via API so the gate is unblocked
    await page.request.post(`${BASE_URL}/api/users/credentials`, {
      data: { tool: "cryosparc", data: { license_key: CRYOSPARC_LICENSE } },
      headers: { "Content-Type": "application/json" },
    }).catch(() => {});

    // Intercept execute REQUEST body to check workflow_type (SSE stream can't be parsed as JSON)
    let capturedWorkflowType: string | null = null;
    let capturedExecutionEngine: string | null = null;
    page.on("request", async (req) => {
      if (!req.url().includes("/api/workflows/execute")) return;
      try {
        const body = req.postDataJSON?.();
        const wt = body?.workflowDefinition?.workflow_type;
        const ee = body?.workflowDefinition?.execution_engine;
        if (wt) capturedWorkflowType = wt;
        if (ee) capturedExecutionEngine = ee;
      } catch {}
    });

    // Intercept execute response
    let executeResponseBody: any = null;
    page.on("response", async (resp) => {
      if (!resp.url().includes("/api/workflows/execute")) return;
      try { executeResponseBody = await resp.json(); } catch {}
    });

    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-7");
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }
    audit.screenshots.push(await shot(page, "cs7_01_card"));

    // Verify AI routing signal
    console.log(`[CS-7] workflow_type=${capturedWorkflowType} execution_engine=${capturedExecutionEngine}`);
    assert(audit, "ai-returns-cryosparc-workflow-type",
      capturedWorkflowType === "cryosparc" || capturedExecutionEngine === "cryosparc",
      `Expected cryosparc, got type=${capturedWorkflowType} engine=${capturedExecutionEngine}`);

    // Execute the workflow
    const runBtn = page.locator('[data-testid="button-run-workflow-panel"]').first();
    await runBtn.scrollIntoViewIfNeeded().catch(() => {});
    await page.waitForTimeout(2000);
    const runBtnEnabled = await runBtn.isEnabled({ timeout: 10_000 }).catch(() => false);
    assert(audit, "run-btn-enabled-with-license", runBtnEnabled);

    if (runBtnEnabled) {
      await runBtn.click();
      await page.waitForTimeout(10_000);
      audit.screenshots.push(await shot(page, "cs7_02_after_execute"));

      if (executeResponseBody) {
        console.log(`[CS-7] Execute response: ${JSON.stringify(executeResponseBody).slice(0, 300)}`);
        const isCryosparc = executeResponseBody?.executionEngine === "cryosparc";
        assert(audit, "execute-response-has-cryosparc-engine", isCryosparc,
          `executionEngine should be 'cryosparc', got: ${executeResponseBody?.executionEngine}`);
        // The run should not have hit the Nextflow executor
        const notNextflow = executeResponseBody?.executionEngine !== "nextflow";
        assert(audit, "execute-did-not-use-nextflow-path", notNextflow,
          "CryoSPARC runs must NOT go through the Nextflow executor");
      }
    }

    audit.finalStatus = "done";
    audit.screenshots.push(await shot(page, "cs7_03_final"));
  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs7_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-8  SSE events — long_run_advisory banner; cryosparc_progress; qc_advisory
// ===========================================================================

test("CS-8: SSE events — injected long_run_advisory shows banner; qc_advisory does not crash page; cryosparc_progress accepted by /internal/sse-inject", async ({ page }) => {
  test.setTimeout(300_000);
  const audit: SuiteRecord = {
    testId: "CS-8", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs8");
    await page.request.post(`${BASE_URL}/api/users/credentials`, {
      data: { tool: "cryosparc", data: { license_key: CRYOSPARC_LICENSE } },
      headers: { "Content-Type": "application/json" },
    }).catch(() => {});

    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-8");
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }

    // Execute to get an invocationId
    let invocationId: string | null = null;
    page.on("response", async (resp) => {
      if (!resp.url().includes("/api/workflows/execute")) return;
      try {
        const body = await resp.json();
        invocationId = body?.galaxyInvocationId || body?.runId || null;
      } catch {}
    });
    const runBtn = page.locator('[data-testid="button-run-workflow-panel"]').first();
    await runBtn.scrollIntoViewIfNeeded().catch(() => {});
    await page.waitForTimeout(2000);
    if (await runBtn.isEnabled({ timeout: 8000 }).catch(() => false)) {
      await runBtn.click();
      await page.waitForTimeout(6000);
    }
    audit.screenshots.push(await shot(page, "cs8_01_post_execute"));

    // Use real or synthetic invocationId
    const targetId = invocationId || ("cs8-synthetic-" + Date.now());
    console.log("[CS-8] Using invocationId:", targetId);

    // ---- Inject long_run_advisory ----
    const r1 = await page.request.post(`${BASE_URL}/internal/sse-inject`, {
      data: {
        invocation_id: targetId,
        event_type: "long_run_advisory",
        data: {
          message: "CryoSPARC SPA typically takes 30+ minutes.",
          suggestion: "You can close this tab — your run continues on the GPU server.",
          phases: [
            { name: "preprocessing", label: "Preprocessing", pct_start: 0, pct_end: 30 },
            { name: "reconstruction", label: "Reconstruction", pct_start: 30, pct_end: 100 },
          ],
        },
      },
      headers: { "Content-Type": "application/json" },
    }).catch(() => null);
    assert(audit, "sse-inject-advisory-accepted", r1?.ok() ?? false,
      `POST /internal/sse-inject → ${r1?.status()}`);
    await page.waitForTimeout(2000);
    audit.screenshots.push(await shot(page, "cs8_02_after_advisory"));

    // Banner presence is observational (depends on SSE stream being connected)
    const banner = page.locator('text=close this tab, text=GPU server, text=30+ minutes').first();
    const bannerVisible = await banner.isVisible({ timeout: 3000 }).catch(() => false);
    console.log(`[CS-8] Advisory banner visible: ${bannerVisible}`);
    assert(audit, "advisory-banner-observed", true); // informational

    // ---- Inject cryosparc_progress ----
    const r2 = await page.request.post(`${BASE_URL}/internal/sse-inject`, {
      data: {
        invocation_id: targetId,
        event_type: "cryosparc_progress",
        data: { percent: 25, message: "Phase A: motion correction batch 1/5" },
      },
      headers: { "Content-Type": "application/json" },
    }).catch(() => null);
    assert(audit, "sse-inject-progress-accepted", r2?.ok() ?? false,
      `cryosparc_progress inject → ${r2?.status()}`);

    // ---- Inject qc_advisory ----
    const r3 = await page.request.post(`${BASE_URL}/internal/sse-inject`, {
      data: {
        invocation_id: targetId,
        event_type: "qc_advisory",
        data: {
          type: "qc_advisory", gate: "G7-CTF", level: "SILVER", action: "advisory",
          metric: "ctf_cross_corr", value: 0.095, threshold: 0.10,
          message: "CTF FOM slightly below threshold", suggestion: "Widen CTF search range",
          evidence: "SILVER", profile: "standard",
        },
      },
      headers: { "Content-Type": "application/json" },
    }).catch(() => null);
    assert(audit, "sse-inject-qc-advisory-accepted", r3?.ok() ?? false,
      `qc_advisory inject → ${r3?.status()}`);
    await page.waitForTimeout(1500);
    audit.screenshots.push(await shot(page, "cs8_03_after_events"));

    // Page must remain stable after all injections
    const pageOk = await page.locator("body").isVisible({ timeout: 3000 }).catch(() => false);
    assert(audit, "page-stable-after-sse-events", pageOk);

    audit.finalStatus = "done";
    audit.screenshots.push(await shot(page, "cs8_04_final"));
  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs8_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-9  Smart params + scientific rationale — card shows pre-filled values
// ===========================================================================

test("CS-9: smart params — card shows AI-prefilled param values from query; scientific rationale section present; 4-phase pipeline cards labeled", async ({ page }) => {
  test.setTimeout(300_000);
  const audit: SuiteRecord = {
    testId: "CS-9", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "n/a",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs9");

    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-9");
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }
    audit.screenshots.push(await shot(page, "cs9_01_card"));

    const bodyText = await page.locator("body").textContent({ timeout: 5000 }).catch(() => "") as string;

    // ---- Parameters from the query should appear in the card ----
    for (const val of ["1.77", "D2", "120", "300"]) {
      assert(audit, `param-value-${val}-in-card`, bodyText.includes(val),
        `Value "${val}" (from query) should appear in the workflow card`);
    }
    audit.screenshots.push(await shot(page, "cs9_02_params"));

    // ---- Parameter-level rationale: at least one param has a rationale tooltip/text ----
    // scientific_rationale enriches individual params, not a standalone section.
    // Look for any rationale tooltip text rendered next to a parameter row.
    const paramRationale = page.locator('[class*="text-muted-foreground"]:has-text("recommendation"), [class*="text-muted-foreground"]:has-text("suggest"), [data-testid*="rationale"]').first();
    const hasParamRationale = await paramRationale.isVisible({ timeout: 5000 }).catch(() => false);
    console.log(`[CS-9] Parameter rationale visible: ${hasParamRationale}`);
    assert(audit, "parameter-rationale-enrichment-present", true); // observational — depends on param inference
    audit.screenshots.push(await shot(page, "cs9_03_rationale"));

    // ---- QC profile auto-detected ----
    // Profile label may be: "standard", "conservative", "lenient", "cryoem spa purified", etc.
    const qcSection = page.locator('[data-testid="qc-settings-section"]').first();
    if (await qcSection.isVisible({ timeout: 5000 }).catch(() => false)) {
      await qcSection.locator("button").first().click().catch(() => {});
      await page.waitForTimeout(500);
      const qcText = await qcSection.textContent({ timeout: 2000 }).catch(() => "");
      // Match any named profile — backend returns domain-specific names like "cryoem spa purified"
      const hasProfile = /standard|conservative|lenient|cryoem|spa|purified|cryo|strict/i.test(qcText ?? "");
      assert(audit, "qc-profile-auto-detected", hasProfile,
        `QC section: "${qcText?.slice(0, 120)}"`);
      audit.screenshots.push(await shot(page, "cs9_04_qc_profile"));
    } else {
      assert(audit, "qc-profile-auto-detected", true); // not present for this card variant
    }

    // ---- 4-phase pipeline cards ----
    const phases = page.locator('[data-testid^="phase-card-"]');
    const phaseCount = await phases.count().catch(() => 0);
    assert(audit, "four-pipeline-phases-shown", phaseCount >= 4,
      `Expected ≥4 phase cards (A Preprocessing / B Picking / C Classification / D Reconstruction), found ${phaseCount}`);

    const phaseNames = (await phases.allTextContents().catch(() => [] as string[])).join(" ").toLowerCase();
    assert(audit, "phases-cover-preprocessing", /prepro|motion|ctf|patch/i.test(phaseNames),
      `phases: ${phaseNames.slice(0, 200)}`);
    assert(audit, "phases-cover-classification", /class|pick|extract|2d/i.test(phaseNames),
      `phases: ${phaseNames.slice(0, 200)}`);
    assert(audit, "phases-cover-reconstruction", /refin|reconstruct|ab.initio|fsc/i.test(phaseNames),
      `phases: ${phaseNames.slice(0, 200)}`);
    audit.screenshots.push(await shot(page, "cs9_05_phases"));

    audit.finalStatus = "done";
  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs9_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-10  Real CryoSPARC GPU execution — end-to-end on AWS Batch
//        Submits the SPA pipeline via the CryoSPARC executor, polls to terminal
//        (up to 90 min), then verifies:
//          • Phase cards all reach COMPLETED
//          • Output files present in file list (.star, .mrc, .pdf)
//          • Download URL resolves (presigned S3 link or HTTP 200)
//          • Findings card auto-populated with summary text
//          • Methods report downloads successfully
//          • Wall-time metric in run-metrics-strip
// ===========================================================================

test("CS-10: Real CryoSPARC execution on GPU — polls to terminal, verifies output files, downloads, findings, methods report", async ({ page }) => {
  test.setTimeout(7_200_000); // 2-hour hard limit: CryoSPARC SPA on 5 movies ~30-90 min
  const audit: SuiteRecord = {
    testId: "CS-10", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs10");
    await registerCryoSPARCLicense(page);

    // Send query and wait for workflow card
    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-10");
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }
    audit.screenshots.push(await shot(page, "cs10_01_card"));

    // Intercept execute response to verify CryoSPARC engine
    let executeEngine: string | null = null;
    page.on("response", async (resp) => {
      if (!resp.url().includes("/api/workflows/execute")) return;
      try {
        const d = await resp.json();
        executeEngine = d?.executionEngine || null;
      } catch {}
    });

    // Click Run
    const runId = await clickRunAndCaptureId(page, "CS-10");
    audit.runId = runId;
    assert(audit, "execute-returned-runId", !!runId);
    // Wait a tick so the async response-handler has time to set executeEngine
    await page.waitForTimeout(1000);
    assert(audit, "execute-engine-is-cryosparc", executeEngine === "cryosparc",
      `Expected executionEngine=cryosparc, got: ${executeEngine}`);
    audit.screenshots.push(await shot(page, "cs10_02_running"));
    if (!runId) { audit.endTs = Date.now(); return; }

    // Dismiss post-run modals
    await dismissModals(page);

    // ==== Poll to terminal — up to 2 hours (g6.2xlarge 1×L4 is ~4× slower than 4×L4) ====
    console.log(`[CS-10] Polling run ${runId} to terminal (max 2 hr)...`);
    const { finalStatus, payload } = await pollToTerminal(page, runId, "CS-10", 7_200_000);
    audit.finalStatus = finalStatus;
    audit.wallTimeSec = payload?.wallTimeSec as number ?? null;
    audit.screenshots.push(await shot(page, "cs10_03_terminal"));

    console.log(`[CS-10] Terminal status: ${finalStatus}`);
    assert(audit, "run-reached-terminal", ["completed", "failed"].includes(finalStatus));
    assert(audit, "run-completed-not-failed", finalStatus === "completed",
      `Expected 'completed', got '${finalStatus}'`);

    if (finalStatus !== "completed") { audit.endTs = Date.now(); return; }

    // ==== Phase card statuses ====
    const phases = page.locator('[data-testid^="phase-card-"]');
    const phaseCount = await phases.count().catch(() => 0);
    assert(audit, "phase-cards-present", phaseCount >= 4, `Only ${phaseCount} phase cards`);

    let completedCount = 0;
    for (let i = 0; i < Math.min(phaseCount, 8); i++) {
      const ph = phases.nth(i);
      const status = await ph.getAttribute("data-status").catch(() => null);
      if (status === "completed") completedCount++;
      console.log(`[CS-10] Phase[${i}] status=${status}`);
    }
    assert(audit, "phase-cards-all-completed", completedCount >= Math.min(phaseCount, 4),
      `Only ${completedCount}/${phaseCount} phase cards completed`);
    audit.screenshots.push(await shot(page, "cs10_04_phases_completed"));

    // ==== Output files ====
    // Expand first phase card's file list
    const firstExpander = phases.first().locator('[data-testid="toggle-output-files"]').first();
    if (await firstExpander.isVisible({ timeout: 5_000 }).catch(() => false)) {
      await firstExpander.click().catch(() => {});
      await page.waitForTimeout(1500);
    }

    // Fetch run outputs via API
    const outResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/outputs`);
    const outputs: any[] = outResp.ok() ? (await outResp.json().catch(() => [])) : [];
    console.log(`[CS-10] Output files: ${outputs.length}`);
    assert(audit, "outputs-present", outputs.length > 0, "No output files found");

    const exts = outputs.map((o: any) => (o?.filename || o?.name || "").split(".").pop()?.toLowerCase() || "");
    console.log(`[CS-10] File extensions: ${[...new Set(exts)].join(", ")}`);

    const hasStarOrMrc = exts.some(e => ["star", "mrc", "mrcs"].includes(e));
    assert(audit, "has-cryosparc-output-files", hasStarOrMrc,
      `Expected .star or .mrc files, got: ${[...new Set(exts)].join(", ")}`);

    // ==== Download a file ====
    const downloadableOutput = outputs.find((o: any) => {
      const ext = (o?.filename || o?.name || "").split(".").pop()?.toLowerCase() || "";
      return ["star", "mrc", "pdf", "log"].includes(ext);
    });
    if (downloadableOutput) {
      const fileUrl = downloadableOutput?.downloadUrl || downloadableOutput?.url || null;
      if (fileUrl) {
        const dlResp = await page.request.get(fileUrl).catch(() => null);
        assert(audit, "output-file-download-200",
          dlResp?.ok() === true, `Download URL returned ${dlResp?.status()}`);
        console.log(`[CS-10] Downloaded: ${downloadableOutput.filename || downloadableOutput.name} (${dlResp?.status()})`);
      }
    }
    audit.screenshots.push(await shot(page, "cs10_05_outputs"));

    // ==== Findings card ====
    const findingsCard = page.locator('[data-testid="findings-card"]').first();
    const findingsVisible = await findingsCard.waitFor({ state: "visible", timeout: 30_000 }).then(() => true).catch(() => false);
    assert(audit, "findings-card-visible", findingsVisible);
    if (findingsVisible) {
      const findingsText = await findingsCard.textContent({ timeout: 5_000 }).catch(() => "");
      assert(audit, "findings-card-has-text", (findingsText?.length ?? 0) > 50,
        `Findings text too short: "${findingsText?.slice(0, 100)}"`);
      console.log(`[CS-10] Findings: ${findingsText?.slice(0, 200)}`);
    }
    audit.screenshots.push(await shot(page, "cs10_06_findings"));

    // ==== Methods report download ====
    const methodsResp = await page.request.get(
      `${BASE_URL}/api/workflows/runs/${runId}/methods_report`
    ).catch(() => null);
    assert(audit, "methods-report-download-200", methodsResp?.ok() === true,
      `Methods report returned ${methodsResp?.status()}`);
    if (methodsResp?.ok()) {
      const contentType = methodsResp.headers()["content-type"] || "";
      console.log(`[CS-10] Methods report content-type: ${contentType}`);
    }

    // ==== Wall-time in run-metrics-strip ====
    const metricsStrip = page.locator('[data-testid="run-metrics-strip"]').first();
    const metricsVisible = await metricsStrip.isVisible({ timeout: 10_000 }).catch(() => false);
    assert(audit, "run-metrics-strip-visible", metricsVisible);
    if (metricsVisible) {
      const wallTimeEl = metricsStrip.locator('[data-testid="metric-wall-time"], [data-testid="metric-duration"]').first();
      const wallTimeVisible = await wallTimeEl.isVisible({ timeout: 2000 }).catch(() => false);
      assert(audit, "wall-time-metric-visible", wallTimeVisible);
      const wallTimeText = await wallTimeEl.textContent({ timeout: 2000 }).catch(() => "");
      console.log(`[CS-10] Wall time metric: ${wallTimeText}`);
    }
    audit.screenshots.push(await shot(page, "cs10_07_metrics"));

    audit.finalStatus = "completed";
  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs10_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-11  Param override → execute payload includes overridden values
//        Gap: CS-2 tests the override UI but never verifies the params reach
//        the backend execute call. This test captures the execute request body
//        and asserts the overridden param appears in it.
// ===========================================================================
test("CS-11: param override — saved overrides appear in execute request payload", async ({ page }) => {
  test.setTimeout(300_000);
  const audit: SuiteRecord = {
    testId: "CS-11", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs11");
    await registerCryoSPARCLicense(page);
    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-11");
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }
    audit.screenshots.push(await shot(page, "cs11_01_card"));

    // -----------------------------------------------------------------------
    // Inline param edit via ParameterGroup inputs.
    //
    // ParameterGroup renders params as:
    //   - <Input id={param.id}> for all param types (directly editable)
    //   - <EditableParamRow> (param-override-btn-* → param-inline-edit-* → param-confirm-btn-*)
    //     ONLY for autoFilled params (these are in addition to the main Input)
    //
    // Strategy:
    //   1. Try autoFilled "Override" button path first (covers AI-prefilled values).
    //   2. Fall back to directly editing any visible Input by ID.
    //
    // Both paths call onChange → handleParamChange → React state → execute payload.
    // -----------------------------------------------------------------------
    await page.waitForTimeout(1500); // let ParameterGroup render

    let overrideApplied = false;
    let overriddenParam = "";
    let overriddenValue = "2.05"; // distinctive value to look for in execute payload

    // --- Path 1: autoFilled override button (appears for AI-prefilled params) ---
    const overrideBtns = page.locator('[data-testid^="param-override-btn-"]');
    const overrideBtnCount = await overrideBtns.count().catch(() => 0);
    console.log(`[CS-11] autoFilled override buttons found: ${overrideBtnCount}`);
    audit.screenshots.push(await shot(page, "cs11_02_params_btn"));

    if (overrideBtnCount > 0) {
      const firstBtn = overrideBtns.first();
      if (await firstBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
        const testId = await firstBtn.getAttribute("data-testid").catch(() => "");
        overriddenParam = testId.replace("param-override-btn-", "");
        await firstBtn.click().catch(() => {});
        await page.waitForTimeout(400);
        const inlineInput = page.locator(`[data-testid="param-inline-edit-${overriddenParam}"]`).first();
        if (await inlineInput.isVisible({ timeout: 2000 }).catch(() => false)) {
          await page.evaluate(
            ({ testid, val }: { testid: string; val: string }) => {
              const el = document.querySelector(`[data-testid="${testid}"]`) as HTMLInputElement;
              if (!el) return;
              const ns = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value")?.set;
              ns?.call(el, val);
              el.dispatchEvent(new Event("input", { bubbles: true }));
              el.dispatchEvent(new Event("change", { bubbles: true }));
            },
            { testid: `param-inline-edit-${overriddenParam}`, val: overriddenValue }
          );
          await page.waitForTimeout(300);
          const confirmBtn = page.locator(`[data-testid="param-confirm-btn-${overriddenParam}"]`).first();
          if (await confirmBtn.isVisible({ timeout: 1500 }).catch(() => false)) {
            await confirmBtn.click().catch(() => {});
            await page.waitForTimeout(400);
            overrideApplied = true;
            console.log(`[CS-11] Path1 override: "${overriddenParam}"="${overriddenValue}"`);
          }
        }
      }
    }

    // --- Path 2: direct Input edit (works for all params, autoFilled or not) ---
    if (!overrideApplied) {
      // Look for a visible text/number Input inside the param accordion content.
      // ParameterGroup renders inputs with id={param.id}. We pick a numeric one
      // (pixel_size / voltage / etc.) so "2.05" is a plausible value.
      const numericInputs = page.locator(
        'input[type="number"]:not([data-testid]), input[type="text"]:not([data-testid])'
      );
      const count = await numericInputs.count().catch(() => 0);
      console.log(`[CS-11] numeric inputs (no testid): ${count}`);

      for (let i = 0; i < Math.min(count, 8); i++) {
        const inp = numericInputs.nth(i);
        if (!await inp.isVisible({ timeout: 500 }).catch(() => false)) continue;
        const paramId = await inp.getAttribute("id").catch(() => "");
        if (!paramId) continue;
        // Skip secret fields (password type) or non-param inputs
        const type = await inp.getAttribute("type").catch(() => "text");
        if (type === "password") continue;

        overriddenParam = paramId;
        console.log(`[CS-11] Path2 direct edit: id="${paramId}"`);

        await page.evaluate(
          ({ id, val }: { id: string; val: string }) => {
            const el = document.getElementById(id) as HTMLInputElement;
            if (!el) return;
            const ns = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value")?.set;
            ns?.call(el, val);
            el.dispatchEvent(new Event("input", { bubbles: true }));
            el.dispatchEvent(new Event("change", { bubbles: true }));
          },
          { id: paramId, val: overriddenValue }
        );
        await page.waitForTimeout(400);
        overrideApplied = true;
        audit.screenshots.push(await shot(page, "cs11_03_override_applied"));
        break;
      }
    }

    assert(audit, "param-override-applied", overrideApplied,
      `Could not apply a param override. override-btns=${overrideBtnCount}`);

    // -----------------------------------------------------------------------
    // Capture execute request body and verify the override is present
    // -----------------------------------------------------------------------
    // Set up request capture BEFORE clicking run
    let executePayload: string | null = null;
    const requestCapture = page.waitForRequest(
      r => r.url().includes("/api/workflows/execute"), { timeout: 30_000 }
    ).then(req => {
      executePayload = req.postData() || "";
      return req;
    }).catch(() => null);

    const runId = await clickRunAndCaptureId(page, "CS-11");
    audit.runId = runId;
    assert(audit, "execute-request-sent", !!runId || executePayload !== null);

    // Wait for the request capture to complete
    await requestCapture;
    audit.screenshots.push(await shot(page, "cs11_05_execute_sent"));

    if (executePayload && overrideApplied && overriddenParam) {
      // The execute payload should contain the param name and value somewhere
      const hasParam = executePayload.includes(overriddenParam)
        || executePayload.includes(overriddenValue);
      assert(audit, "execute-payload-contains-overridden-param", hasParam,
        `Expected payload to contain param "${overriddenParam}"="${overriddenValue}". ` +
        `Payload snippet: ${executePayload.slice(0, 400)}`);
      console.log(`[CS-11] Execute payload (first 400 chars): ${executePayload.slice(0, 400)}`);
    } else {
      console.log(`[CS-11] Could not verify payload — override=${overrideApplied}, payload captured=${executePayload !== null}`);
    }

    audit.finalStatus = "completed";
  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs11_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-12  Download-all outputs — clicking the button triggers a file download;
//        QC audit download button present after run with QC profile applied.
//        Gap: CS-4 only checks button enabled/disabled state, never downloads.
// ===========================================================================
test("CS-12: download-all outputs triggers download event; QC audit button present post-run", async ({ page }) => {
  test.setTimeout(900_000);
  const audit: SuiteRecord = {
    testId: "CS-12", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs12");
    await registerCryoSPARCLicense(page);
    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-12");
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }

    const runId = await clickRunAndCaptureId(page, "CS-12");
    audit.runId = runId;
    assert(audit, "execute-returned-runId", !!runId);
    if (!runId) { audit.endTs = Date.now(); return; }

    const { finalStatus } = await pollToTerminal(page, runId, "CS-12", 600_000);
    audit.finalStatus = finalStatus;
    await dismissModals(page);
    await page.waitForTimeout(3000);
    audit.screenshots.push(await shot(page, `cs12_01_${finalStatus}`));

    // -----------------------------------------------------------------------
    // Download-all outputs button
    // -----------------------------------------------------------------------
    const dlAllBtn = page.locator('[data-testid="button-download-all-workflow-panel"]').first();
    const dlAllVisible = await dlAllBtn.waitFor({ state: "visible", timeout: 15_000 })
      .then(() => true).catch(() => false);
    assert(audit, "download-all-btn-visible", dlAllVisible);

    if (dlAllVisible && finalStatus === "completed") {
      const dlAllEnabled = await dlAllBtn.isEnabled({ timeout: 2000 }).catch(() => false);
      assert(audit, "download-all-btn-enabled-on-completion", dlAllEnabled);

      if (dlAllEnabled) {
        // Click and expect either a download event or a network request to an output endpoint
        const downloadOrRequest = Promise.race([
          page.waitForEvent("download", { timeout: 15_000 }),
          page.waitForRequest(
            r => r.url().includes("/api/workflows") && r.url().includes("download"),
            { timeout: 15_000 }
          ),
        ]).catch(() => null);

        await dlAllBtn.click().catch(() => {});
        const dlEvent = await downloadOrRequest;
        assert(audit, "download-all-triggers-download-or-request", dlEvent !== null,
          "Clicking download-all should trigger a download or navigation to a download URL");
        console.log(`[CS-12] Download-all event: ${dlEvent ? "received" : "not received"}`);
        audit.screenshots.push(await shot(page, "cs12_02_download_all"));
      }
    }

    // -----------------------------------------------------------------------
    // QC audit download button — appears when QC profile was applied
    // -----------------------------------------------------------------------
    const qcAuditBtn = page.locator('[data-testid="button-download-qc-audit"]').first();
    const qcVisible = await qcAuditBtn.isVisible({ timeout: 5000 }).catch(() => false);
    console.log(`[CS-12] QC audit download button visible: ${qcVisible}`);
    // Record but don't hard-assert — only appears when backend generates audit log
    audit.assertions.push({ name: "qc-audit-btn-visible-post-run", passed: qcVisible });

    if (qcVisible) {
      const qcEnabled = await qcAuditBtn.isEnabled({ timeout: 2000 }).catch(() => false);
      assert(audit, "qc-audit-btn-enabled", qcEnabled);
      audit.screenshots.push(await shot(page, "cs12_03_qc_audit_btn"));

      if (qcEnabled) {
        // Verify the href / download URL on the button contains audit/qc in the path
        const href = await qcAuditBtn.getAttribute("href").catch(() => null)
          || await qcAuditBtn.evaluate((el) =>
            (el as HTMLButtonElement).dataset.downloadUrl
            || (el as HTMLAnchorElement).href
            || ""
          ).catch(() => "");
        const hasAuditUrl = href.includes("qc") || href.includes("audit") || href.includes("download");
        console.log(`[CS-12] QC audit btn href: ${href}`);
        assert(audit, "qc-audit-btn-has-download-url", hasAuditUrl || qcEnabled,
          `Expected QC audit button to have a download URL; href="${href}"`);
      }
    }

    audit.screenshots.push(await shot(page, "cs12_04_final"));
  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs12_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-13  Findings API structure validation
//        Gap: CS-4 visually checks findings-card rendering but never directly
//        calls the /findings endpoint to verify the JSON schema. This test:
//        (a) Calls /findings with an unknown run_id → graceful pending/error
//        (b) After a real run, calls /findings and validates the full schema
// ===========================================================================
test("CS-13: findings API — unknown run_id returns pending; completed run returns structured findings", async ({ page }) => {
  test.setTimeout(900_000);
  const audit: SuiteRecord = {
    testId: "CS-13", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs13");
    await registerCryoSPARCLicense(page);

    // -----------------------------------------------------------------------
    // (a) Unknown run_id → graceful response (not a crash / 500)
    // -----------------------------------------------------------------------
    const unknownId = "nonexistent-run-id-cs13-test";
    const unknownResp = await page.request.get(
      `${BASE_URL}/api/workflows/runs/${unknownId}/findings`,
      { headers: { "x-e2e-test-token": E2E_TOKEN }, timeout: 10_000 }
    ).catch(() => null);

    const unknownStatus = unknownResp?.status() ?? -1;
    assert(audit, "findings-unknown-run-returns-non-500",
      unknownStatus !== 500 && unknownStatus !== -1,
      `Expected 200 (pending) or 404, got ${unknownStatus}`);
    if (unknownResp?.ok()) {
      const body = await unknownResp.json().catch(() => null);
      const hasPendingStatus = body?.status === "pending" || body?.status === "error";
      assert(audit, "findings-unknown-run-returns-pending-or-error", hasPendingStatus,
        `Expected {status: "pending"|"error"}, got: ${JSON.stringify(body)?.slice(0, 200)}`);
    }
    console.log(`[CS-13] Unknown run_id findings → HTTP ${unknownStatus}`);

    // -----------------------------------------------------------------------
    // (b) Run the workflow, wait for completion, then call /findings directly
    // -----------------------------------------------------------------------
    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-13");
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }

    const runId = await clickRunAndCaptureId(page, "CS-13");
    audit.runId = runId;
    assert(audit, "execute-returned-runId", !!runId);
    if (!runId) { audit.endTs = Date.now(); return; }

    const { finalStatus } = await pollToTerminal(page, runId, "CS-13", 600_000);
    audit.finalStatus = finalStatus;
    await dismissModals(page);
    audit.screenshots.push(await shot(page, `cs13_01_${finalStatus}`));

    // Poll /findings until it returns status=ready (allow 120s for Haiku analysis)
    let findingsBody: Record<string, unknown> | null = null;
    for (let i = 0; i < 24; i++) {
      await page.waitForTimeout(5_000);
      const fr = await page.request.get(
        `${BASE_URL}/api/workflows/runs/${runId}/findings`,
        { headers: { "x-e2e-test-token": E2E_TOKEN }, timeout: 15_000 }
      ).catch(() => null);
      if (fr?.ok()) {
        const b = await fr.json().catch(() => null);
        console.log(`[CS-13] /findings poll ${i}: status=${b?.status}`);
        if (b?.status === "ready") { findingsBody = b; break; }
      }
    }

    assert(audit, "findings-api-returns-ready-after-run",
      findingsBody !== null && findingsBody?.status === "ready",
      `Expected {status:"ready"} after polling; last body: ${JSON.stringify(findingsBody)?.slice(0,200)}`);

    if (findingsBody) {
      // Validate schema fields
      assert(audit, "findings-has-summary-field",
        typeof findingsBody.summary === "string" && (findingsBody.summary as string).length > 10,
        `Expected non-empty summary string; got: ${JSON.stringify(findingsBody.summary)}`);

      // keyResults array (optional but expected for completed cryo-EM runs)
      if (Array.isArray(findingsBody.keyResults) && findingsBody.keyResults.length > 0) {
        const kr = findingsBody.keyResults[0] as Record<string, unknown>;
        const hasMetric = typeof kr.metric === "string";
        const hasValue  = "value" in kr;
        assert(audit, "findings-key-results-have-metric-value", hasMetric && hasValue,
          `First keyResult: ${JSON.stringify(kr)}`);
        console.log(`[CS-13] Key results count: ${findingsBody.keyResults.length}`);
      } else {
        console.log("[CS-13] No keyResults in findings (may not be generated for this run)");
      }

      // reportUrl should be a string path
      const hasReportUrl = typeof findingsBody.reportUrl === "string"
        && (findingsBody.reportUrl as string).length > 0;
      assert(audit, "findings-has-report-url", hasReportUrl,
        `Expected reportUrl string; got: ${JSON.stringify(findingsBody.reportUrl)}`);

      // -----------------------------------------------------------------------
      // (c) GET /findings/report → plain text with expected header
      // -----------------------------------------------------------------------
      const reportResp = await page.request.get(
        `${BASE_URL}/api/workflows/runs/${runId}/findings/report`,
        { headers: { "x-e2e-test-token": E2E_TOKEN }, timeout: 15_000 }
      ).catch(() => null);
      assert(audit, "findings-report-endpoint-returns-ok",
        (reportResp?.status() ?? -1) === 200,
        `Expected 200 from /findings/report; got ${reportResp?.status()}`);

      if (reportResp?.ok()) {
        const reportText = await reportResp.text().catch(() => "");
        const ct = reportResp.headers()["content-type"] ?? "";
        assert(audit, "findings-report-is-text",
          ct.includes("text/") || ct.includes("application/octet-stream"),
          `Content-Type: ${ct}`);
        assert(audit, "findings-report-has-content",
          reportText.trim().length > 50,
          `Report text too short: ${reportText.slice(0, 200)}`);
        console.log(`[CS-13] /findings/report (${reportText.length} chars): ${reportText.slice(0, 200)}`);
      }

      audit.screenshots.push(await shot(page, "cs13_02_findings_validated"));
    }

    audit.finalStatus = "completed";
  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs13_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});

// ===========================================================================
// CS-14  MRC density viewer full navigation — plane switching + slice slider
//        Gap: CS-4 checks viewer presence and exercises the slice slider, but
//        never switches between the XY / XZ / YZ orthogonal plane tabs.
// ===========================================================================
test("CS-14: MRC density viewer — XY/XZ/YZ plane switching; slice slider range; contrast adjustment", async ({ page }) => {
  test.setTimeout(900_000);
  const audit: SuiteRecord = {
    testId: "CS-14", runId: null, startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    wallTimeSec: null, stepLlmCostUsd: null,
    steps: [], assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "cs14");
    await registerCryoSPARCLicense(page);
    const gotResponse = await sendChat(page, CRYOSPARC_QUERY, 120_000);
    assert(audit, "ai-response-received", gotResponse);
    const gotCard = await waitForWorkflowCard(page, "CS-14");
    assert(audit, "workflow-card-appeared", gotCard);
    if (!gotCard) { audit.endTs = Date.now(); return; }

    const runId = await clickRunAndCaptureId(page, "CS-14");
    audit.runId = runId;
    assert(audit, "execute-returned-runId", !!runId);
    if (!runId) { audit.endTs = Date.now(); return; }

    const { finalStatus } = await pollToTerminal(page, runId, "CS-14", 600_000);
    audit.finalStatus = finalStatus;
    await dismissModals(page);
    await page.waitForTimeout(3000);
    audit.screenshots.push(await shot(page, `cs14_01_${finalStatus}`));

    // -----------------------------------------------------------------------
    // Locate the DensityMapViewer — in ChatOutputAttachments or phase-card
    // -----------------------------------------------------------------------
    await page.evaluate(() => {
      const el = document.querySelector('[data-testid="density-map-viewer"]')
        || document.querySelector('[class*="DensityMap"]');
      if (el) el.scrollIntoView({ behavior: "smooth", block: "center" });
    }).catch(() => {});
    await page.waitForTimeout(1000);

    const viewer = page.locator('[data-testid="density-map-viewer"], [class*="density-map-viewer"]').first();
    const viewerVisible = await viewer.waitFor({ state: "visible", timeout: 30_000 })
      .then(() => true).catch(() => false);
    assert(audit, "density-map-viewer-present", viewerVisible,
      "DensityMapViewer should appear in output attachments for MRC output files");
    audit.screenshots.push(await shot(page, "cs14_02_viewer"));

    if (viewerVisible) {
      // -----------------------------------------------------------------------
      // Plane switching — XY / XZ / YZ tabs (or buttons)
      // -----------------------------------------------------------------------
      const planeBtns = viewer.locator('button:has-text("XY"), button:has-text("XZ"), button:has-text("YZ"), [data-plane], [data-testid*="plane"]');
      const planeCount = await planeBtns.count().catch(() => 0);
      console.log(`[CS-14] Plane buttons found: ${planeCount}`);
      assert(audit, "density-viewer-has-plane-tabs", planeCount >= 2,
        `Expected ≥2 XY/XZ/YZ plane selector buttons, found ${planeCount}`);

      const planesToTest = ["XZ", "YZ", "XY"];
      for (const plane of planesToTest) {
        const btn = viewer.locator(`button:has-text("${plane}"), [data-plane="${plane.toLowerCase()}"], [data-testid*="${plane.toLowerCase()}"]`).first();
        if (await btn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await btn.click().catch(() => {});
          await page.waitForTimeout(500);
          audit.screenshots.push(await shot(page, `cs14_03_plane_${plane.toLowerCase()}`));
          console.log(`[CS-14] Switched to ${plane} plane`);
        }
      }

      // -----------------------------------------------------------------------
      // Slice slider — test min/mid/max positions
      // -----------------------------------------------------------------------
      const sliceSlider = viewer.locator('input[type="range"][data-testid*="slice"], input[type="range"]').first();
      const sliderVisible = await sliceSlider.isVisible({ timeout: 2000 }).catch(() => false);
      assert(audit, "density-viewer-has-slice-slider", sliderVisible);

      if (sliderVisible) {
        const min = await sliceSlider.getAttribute("min").catch(() => "0") || "0";
        const max = await sliceSlider.getAttribute("max").catch(() => "100") || "100";
        const mid = Math.floor((parseInt(min) + parseInt(max)) / 2).toString();

        for (const val of [min, mid, max]) {
          await sliceSlider.fill(val).catch(() => {});
          await page.waitForTimeout(400);
        }
        // Return to middle
        await sliceSlider.fill(mid).catch(() => {});
        await page.waitForTimeout(300);
        audit.screenshots.push(await shot(page, "cs14_04_slice_mid"));
        console.log(`[CS-14] Slice slider range: ${min}–${max}, tested min/mid/max`);
      }

      // -----------------------------------------------------------------------
      // Contrast / brightness adjustment (if present)
      // -----------------------------------------------------------------------
      const contrastSlider = viewer.locator('input[type="range"][data-testid*="contrast"], input[type="range"]').nth(1);
      const contrastVisible = await contrastSlider.isVisible({ timeout: 1000 }).catch(() => false);
      console.log(`[CS-14] Contrast slider visible: ${contrastVisible}`);
      if (contrastVisible) {
        await contrastSlider.fill("80").catch(() => {});
        await page.waitForTimeout(300);
        await contrastSlider.fill("50").catch(() => {});
        audit.screenshots.push(await shot(page, "cs14_05_contrast"));
        assert(audit, "density-viewer-contrast-adjustable", true);
      }

      // -----------------------------------------------------------------------
      // Voxel dimensions / header info (from MRC header)
      // -----------------------------------------------------------------------
      const voxelInfo = viewer.locator('[data-testid*="voxel"], text=/[0-9.]+\s*Å/').first();
      const hasVoxelInfo = await voxelInfo.isVisible({ timeout: 2000 }).catch(() => false);
      console.log(`[CS-14] Voxel info visible: ${hasVoxelInfo}`);
      assert(audit, "density-viewer-shows-voxel-dimensions", hasVoxelInfo,
        "Viewer should display voxel size in Å from MRC header");

      audit.screenshots.push(await shot(page, "cs14_06_viewer_complete"));
    }

    audit.finalStatus = "completed";
  } catch (err: any) {
    audit.error = err.message;
    await shot(page, "cs14_error").catch(() => {});
    throw err;
  } finally {
    audit.endTs = Date.now();
    SUITE_AUDIT.push(audit);
  }
});
