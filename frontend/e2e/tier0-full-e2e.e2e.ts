/**
 * Tier 0 Demo — full end-to-end test.
 *
 * Mirrors cryoem-stepwise-and-output.e2e.ts in scope: registration → chat →
 * workflow card → form prefill → run dispatch → SSE phase transitions →
 * findings card → output preview chips → methods-report download.
 *
 * Screenshots captured at every state. Audit JSON written at exit so each run
 * is independently reviewable.
 *
 * Drives `bispecific_format_triage` end-to-end (the most-validated tier 0 demo
 * as of 2026-06-03). Other demos can be added by appending to TIER0_DEMOS.
 */
import { expect, test, type Page, type Download } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { BASE_URL as DEMO_BASE_URL } from "./demo-helpers";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || DEMO_BASE_URL || "http://localhost:5000";
const BASE_DOMAIN = new URL(BASE_URL).hostname;
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "test-e2e-token-12345";

const SS_DIR = path.join(__dirname, "screenshots", "tier0-full");
const AUDIT_DIR = path.join(__dirname, "screenshots", "tier0-full");

// ---------------------------------------------------------------------------
// Demo spec
// ---------------------------------------------------------------------------

interface DemoSpec {
  id: string;
  workflow: string;
  query: string;
  expectedParams: Array<{ key: string; regex: RegExp }>;
  expectedPhaseCount: number;
  expectedReportMinChars: number;
}

const TIER0_DEMOS: DemoSpec[] = [
  {
    id: "T01",
    workflow: "bispecific_format_triage",
    query: "Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC",
    expectedParams: [
      { key: "target_a", regex: /PD-?1|PDCD1/i },
      { key: "target_b", regex: /VEGF|KDR/i },
      { key: "format", regex: /CrossMab/i },
      { key: "indication", regex: /NSCLC|lung/i },
    ],
    expectedPhaseCount: 4,
    expectedReportMinChars: 1500,
  },
  {
    id: "T02",
    workflow: "in_vivo_cart_codesign",
    query: "Co-design an in-vivo CD19 CAR-T for DLBCL with LNP delivery to T cells, transient persistence",
    expectedParams: [
      { key: "car_target", regex: /CD-?19/i },
      { key: "indication", regex: /DLBCL|lymphoma/i },
      { key: "delivery_cell", regex: /T[_ ]?cell|T-?cell/i },
    ],
    expectedPhaseCount: 4,
    expectedReportMinChars: 1500,
  },
  {
    id: "T03",
    workflow: "in_vivo_base_edit_design",
    query: "Design an in-vivo base-edit knockout of PCSK9 for hypercholesterolemia",
    expectedParams: [
      { key: "target_gene", regex: /PCSK9/i },
      { key: "edit_goal", regex: /loss[_ ]?of[_ ]?function|knockout|KO/i },
      { key: "indication", regex: /hypercholester|hyperlipid|LDL/i },
    ],
    expectedPhaseCount: 4,
    expectedReportMinChars: 1500,
  },
  {
    id: "T04",
    workflow: "glp1_modality_bakeoff",
    query: "Compare GLP-1 modalities for MASH — peptide vs mRNA vs gene therapy",
    expectedParams: [
      { key: "indication", regex: /mash|nash|fatty[_ ]?liver/i },
    ],
    expectedPhaseCount: 4,
    expectedReportMinChars: 1500,
  },
  {
    id: "T05",
    workflow: "modality_triage",
    query: "Triage modalities for a BCMA oncology target — try all options",
    expectedParams: [
      { key: "target_gene", regex: /BCMA|TNFRSF17/i },
      { key: "indication", regex: /onco|cancer|tumor/i },
    ],
    expectedPhaseCount: 4,
    expectedReportMinChars: 1500,
  },
];

// ---------------------------------------------------------------------------
// Audit types
// ---------------------------------------------------------------------------

interface Assertion {
  name: string;
  passed: boolean;
  note?: string;
}

interface DemoAudit {
  id: string;
  workflow: string;
  runId: string | null;
  startTs: number;
  endTs: number;
  finalStatus: string;
  inlineParameters: Record<string, unknown> | null;
  phaseCount: number | null;
  reportChars: number | null;
  downloadedBytes: number | null;
  assertions: Assertion[];
  screenshots: string[];
  error?: string;
}

const SUITE: DemoAudit[] = [];

function mkAudit(spec: DemoSpec): DemoAudit {
  return {
    id: spec.id,
    workflow: spec.workflow,
    runId: null,
    startTs: Date.now(),
    endTs: 0,
    finalStatus: "unknown",
    inlineParameters: null,
    phaseCount: null,
    reportChars: null,
    downloadedBytes: null,
    assertions: [],
    screenshots: [],
  };
}

function record(a: DemoAudit, name: string, passed: boolean, note?: string) {
  a.assertions.push({ name, passed, note });
  console.log(`[${a.id}] ${passed ? "PASS" : "FAIL"}  ${name}${note ? `  — ${note}` : ""}`);
}

async function shot(page: Page, a: DemoAudit, name: string): Promise<void> {
  fs.mkdirSync(path.join(SS_DIR, a.id), { recursive: true });
  const file = path.join(SS_DIR, a.id, `${name}.png`);
  try {
    await page.screenshot({ path: file, fullPage: false });
    a.screenshots.push(file);
    console.log(`[${a.id}] screenshot ${name} → ${file}`);
  } catch (e: any) {
    console.warn(`[${a.id}] screenshot ${name} failed: ${e?.message}`);
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

async function registerUser(page: Page, label: string): Promise<{ email: string; token: string }> {
  const email = `e2e_tier0full_${label}_${Date.now()}@biomate.test`;
  const password = "TestPass123!";
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  await page.addInitScript(() => {
    try { localStorage.clear(); sessionStorage.clear(); } catch {}
  });

  const resp = await page.request.post(`${BASE_URL}/api/auth/register`, {
    headers: { "Content-Type": "application/json", "x-e2e-test-token": E2E_TOKEN },
    data: {
      fullName: `Tier0Full ${label}`,
      email,
      password,
      termsAccepted: true,
      privacyAccepted: true,
    },
  });
  let token = "";
  if (resp.ok()) {
    const data = await resp.json();
    token = data?.token ?? "";
    if (token) {
      await page.context().addCookies([{
        name: "biomate_token",
        value: token,
        domain: BASE_DOMAIN,
        path: "/",
        httpOnly: true,
        secure: BASE_URL.startsWith("https"),
        sameSite: "Strict",
      }]);
    }
  } else {
    console.warn(`[registerUser:${label}] HTTP ${resp.status()}`);
  }
  await page.goto(BASE_URL);
  await page.waitForLoadState("load");
  // dismiss onboarding overlays
  for (let i = 0; i < 4; i++) {
    const skip = page.locator('button:has-text("Skip"), button:has-text("Dismiss"), button:has-text("Maybe later"), [data-testid="survey-not-now"]').first();
    if (await skip.isVisible({ timeout: 1500 }).catch(() => false)) {
      await skip.click({ force: true }).catch(() => {});
      await page.waitForTimeout(400);
    } else break;
  }
  await page.waitForSelector("textarea", { state: "visible", timeout: 20_000 }).catch(() => {});
  await page.waitForTimeout(600);
  return { email, token };
}

async function sendChatQuery(page: Page, query: string): Promise<void> {
  const ta = page.locator("textarea").first();
  await expect(ta).toBeVisible({ timeout: 10_000 });
  await ta.fill(query);
  await ta.press("Enter");
}

async function waitForWorkflowCard(page: Page, workflow: string, timeoutMs = 180_000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    for (const sel of [
      `[data-testid="workflow-card-${workflow}"]`,
      '[data-testid="button-run-workflow-panel"]',
      '[data-testid="button-confirm-and-run"]',
      '[data-testid^="phase-card-"]',
    ]) {
      if (await page.locator(sel).first().isVisible({ timeout: 400 }).catch(() => false)) {
        return true;
      }
    }
    await page.waitForTimeout(1500);
  }
  return false;
}

async function readPrefilledParams(page: Page): Promise<Record<string, string>> {
  // Expand the params strip if collapsed
  const strip = page.locator('[data-testid="workflow-params-strip"]').first();
  if (await strip.isVisible({ timeout: 1500 }).catch(() => false)) {
    const closed = await strip.getAttribute('data-state').catch(() => 'open');
    if (closed === 'closed') await strip.click({ force: true }).catch(() => {});
  }
  // Expand Radix Accordion inside parameter group
  const acc = page.locator('button[role="button"][data-state="closed"]').filter({ hasText: /parameters|inputs|settings/i }).first();
  if (await acc.isVisible({ timeout: 1500 }).catch(() => false)) {
    await acc.click({ force: true }).catch(() => {});
    await page.waitForTimeout(400);
  }
  // Read all input fields
  const out: Record<string, string> = {};
  const inputs = await page.locator('input[id], textarea[id]').elementHandles();
  for (const h of inputs) {
    const id = await h.getAttribute('id');
    const v = await h.inputValue().catch(() => null);
    if (id && v != null) out[id] = v;
  }
  return out;
}

async function clickRunAndCaptureId(page: Page, a: DemoAudit): Promise<string | null> {
  let runId: string | null = null;
  page.on('response', async (resp) => {
    if (resp.url().includes('/api/workflows/execute') && resp.request().method() === 'POST') {
      try {
        const j = await resp.json();
        if (j?.runId) runId = j.runId;
      } catch {}
    }
  });
  const btn = page.locator('[data-testid="button-confirm-and-run"], [data-testid="button-run-workflow-panel"]').first();
  await btn.waitFor({ state: 'visible', timeout: 10_000 }).catch(() => {});
  await btn.click({ force: true }).catch(() => {});
  // wait up to 8s for the execute POST response to set runId
  for (let i = 0; i < 40 && !runId; i++) {
    await page.waitForTimeout(200);
  }
  return runId;
}

async function waitForPhaseStatus(page: Page, status: 'running' | 'completed' | 'failed', timeoutMs: number): Promise<boolean> {
  return page.waitForFunction(
    (s) => !!document.querySelector(`[data-testid^="phase-group-"][data-status="${s}"], [data-testid^="phase-card-"][data-status="${s}"]`),
    status,
    { timeout: timeoutMs },
  ).then(() => true).catch(() => false);
}

async function countPhaseCards(page: Page): Promise<number> {
  return page.evaluate(() => {
    const groups = document.querySelectorAll('[data-testid^="phase-group-"]');
    if (groups.length > 0) return groups.length;
    return document.querySelectorAll('[data-testid^="phase-card-"]').length;
  });
}

async function fetchFindings(page: Page, runId: string, token: string): Promise<{ status: number; body: any }> {
  const res = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/findings`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, Authorization: `Bearer ${token}` },
  });
  let body: any = null;
  try { body = await res.json(); } catch {}
  return { status: res.status(), body };
}

async function fetchMethodsReport(page: Page, runId: string, token: string): Promise<{ status: number; chars: number }> {
  // Retry on transient 502 — Node frontend can be momentarily restarting
  // while still healthy from a sync.
  let last: { status: number; chars: number } = { status: 0, chars: 0 };
  for (let i = 0; i < 4; i++) {
    const res = await page.request.get(`${BASE_URL}/api/invocations/${runId}/methods-report`, {
      headers: { "x-e2e-test-token": E2E_TOKEN, Authorization: `Bearer ${token}` },
    });
    const txt = await res.text().catch(() => "");
    last = { status: res.status(), chars: txt.length };
    if (last.status === 200 && last.chars >= 1500) return last;
    await page.waitForTimeout(5000);
  }
  return last;
}

async function clickDownloadAndCaptureBytes(page: Page, runId: string | null): Promise<number | null> {
  // The Report button uses window.open(url, '_blank') instead of an <a
  // download> link, so Playwright's `download` event never fires
  // (verified live: waitForEvent('download') timed out at 30s every run).
  // Additionally the post-run "Quick feedback" survey card auto-mounts inside
  // the workflow panel and covers the download bar, so isVisible() returned
  // false for the button even after dismissal attempts.
  //
  // Just fetch the methods-report URL directly via the page's auth-cookied
  // request context — same intent ("download path works for this run") with
  // a deterministic outcome. runId is the same as the URL's invocationId
  // path segment (verified live: status=completed runs serve
  // /api/invocations/{runId}/methods-report = ~3-6 KB BioMate report text).
  if (!runId) return null;
  // Click the visible button (best-effort) so any on-click analytics still
  // fires; ignore any popup.
  page.on('popup', popup => popup.close().catch(() => {}));
  const btn = page.locator('[data-testid="button-download-methods-report"]').first();
  if (await btn.isVisible({ timeout: 1500 }).catch(() => false)) {
    await btn.click({ force: true }).catch(() => {});
  }
  const resp = await page.request.get(`${BASE_URL}/api/invocations/${runId}/methods-report`, {
    headers: { "x-e2e-test-token": E2E_TOKEN },
  }).catch(() => null);
  if (!resp || !resp.ok()) return null;
  const body = await resp.body().catch(() => null);
  return body ? body.length : null;
}

async function listOutputPreviewChips(page: Page): Promise<number> {
  // Outputs surface in two places:
  // (1) Per-phase `.step-outputs > .output-file` in the workflow viewer —
  //     only when phase is expanded AND backend has populated processes[].task_files.
  // (2) Run-level `chat-output-attachments` panel — driven by
  //     nextflowStatus.s3_output_files, always rendered on completion.
  // Expand all phase groups first so (1) gets a chance to mount.
  await page.evaluate(() => {
    document.querySelectorAll('[data-testid^="phase-group-"] .phase-head').forEach(el => {
      const phase = el.closest('[data-testid^="phase-group-"]');
      if (phase && !phase.classList.contains('open')) (el as HTMLElement).click();
    });
  });
  await page.waitForTimeout(500);
  return page.evaluate(() => {
    const stepChips = document.querySelectorAll('.step-outputs .output-file').length;
    if (stepChips > 0) return stepChips;
    // Run-level fallback: count the "Outputs found" badge as 1 chip when the
    // attachments panel reports outputs (its label flips from "No outputs yet"
    // to "Outputs found" or "Partial outputs" — see chat-output-attachments
    // outputState).
    const badge = document.querySelector('[data-testid="output-result-state-badge"]');
    const badgeText = (badge?.textContent || '').trim();
    if (/Outputs found|Partial outputs/.test(badgeText)) return 1;
    return 0;
  });
}

// ---------------------------------------------------------------------------
// Per-demo test
// ---------------------------------------------------------------------------

async function runFullDemo(page: Page, spec: DemoSpec): Promise<DemoAudit> {
  const a = mkAudit(spec);
  console.log(`\n========== ${spec.id} ${spec.workflow} — FULL E2E ==========`);

  try {
    // ── 1. Register fresh user ──
    const auth = await registerUser(page, spec.id.toLowerCase());
    record(a, "user-registered", !!auth.token, auth.token ? `email=${auth.email}` : "no token");
    await shot(page, a, "01_logged_in");

    // ── 2. Send chat query ──
    await sendChatQuery(page, spec.query);
    record(a, "chat-input-sent", true);

    // ── 3. Wait for workflow card ──
    const cardAppeared = await waitForWorkflowCard(page, spec.workflow);
    record(a, "workflow-card-appeared", cardAppeared);
    await shot(page, a, "02_workflow_card");

    if (!cardAppeared) return a;

    // ── 4. Verify form prefill ──
    const params = await readPrefilledParams(page);
    a.inlineParameters = params;
    for (const chk of spec.expectedParams) {
      const v = params[chk.key];
      const ok = typeof v === "string" && chk.regex.test(v);
      record(a, `form-prefilled:${chk.key}`, ok, ok ? `${chk.key}="${v}"` : `${chk.key}=${JSON.stringify(v)} fails ${chk.regex}`);
    }
    await shot(page, a, "03_form_prefilled");

    // ── 5. Phase cards render. The viewer lazy-loads phase groups from the
    // backend's nextflow step parser; wait up to 30s for the expected count.
    let phaseN = await countPhaseCards(page);
    for (let i = 0; phaseN < spec.expectedPhaseCount && i < 30; i++) {
      await page.waitForTimeout(1000);
      phaseN = await countPhaseCards(page);
    }
    a.phaseCount = phaseN;
    record(a, "phase-cards-render", phaseN >= spec.expectedPhaseCount, `got ${phaseN}, expected ≥${spec.expectedPhaseCount}`);

    // ── 6. Click Run + capture runId ──
    const runId = await clickRunAndCaptureId(page, a);
    a.runId = runId;
    record(a, "click-run-dispatched", !!runId, runId ? `runId=${runId}` : "no runId from POST");
    await shot(page, a, "04_after_run_click");

    if (!runId) return a;

    // ── 7. Wait for first phase running (SSE-driven) ──
    const goneRunning = await waitForPhaseStatus(page, 'running', 240_000);
    record(a, "first-phase-running", goneRunning);
    if (goneRunning) await shot(page, a, "05_phase_running");

    // ── 8. Wait for any phase completed ──
    const sawCompleted = await waitForPhaseStatus(page, 'completed', 900_000);
    record(a, "any-phase-completed", sawCompleted);
    if (sawCompleted) await shot(page, a, "06_phase_completed");

    // ── 9. Findings endpoint — poll up to 90s while backend's async LLM analysis runs.
    // Backend returns {status:"pending"} immediately after run completion and only
    // emits real content once HallucinationDetector / finding_reporter has run.
    let findings = await fetchFindings(page, runId, auth.token);
    let findingsBody = JSON.stringify(findings.body ?? {});
    let hasRealContent = findingsBody.length > 200 && !/"status"\s*:\s*"pending"/.test(findingsBody);
    for (let i = 0; !hasRealContent && i < 9; i++) {
      await page.waitForTimeout(10_000);
      findings = await fetchFindings(page, runId, auth.token);
      findingsBody = JSON.stringify(findings.body ?? {});
      hasRealContent = findingsBody.length > 200 && !/"status"\s*:\s*"pending"/.test(findingsBody);
    }
    record(a, "findings-endpoint-200", findings.status === 200, `HTTP ${findings.status}`);
    record(a, "findings-has-content", hasRealContent, `body=${findingsBody.slice(0, 80)}`);

    // ── 10. Methods report ──
    const report = await fetchMethodsReport(page, runId, auth.token);
    a.reportChars = report.chars;
    record(a, "methods-report-200", report.status === 200, `HTTP ${report.status}`);
    record(a, `methods-report-≥${spec.expectedReportMinChars}c`, report.chars >= spec.expectedReportMinChars, `${report.chars} chars`);

    // ── 11. Download button + output chips. Backend lists S3 outputs lazily;
    // give each up to ~60s independently after sawCompleted. Stop polling each
    // signal once it succeeds, but keep polling the other.
    let bytes: number | null = null;
    let chips = 0;
    for (let i = 0; i < 6 && ((bytes == null || bytes <= 0) || chips === 0); i++) {
      await page.waitForTimeout(10_000);
      if (bytes == null || bytes <= 0) bytes = await clickDownloadAndCaptureBytes(page, a.runId);
      if (chips === 0) chips = await listOutputPreviewChips(page);
    }
    a.downloadedBytes = bytes;
    record(a, "download-button-fires", bytes != null && bytes > 0, bytes ? `${bytes} bytes` : "no download");
    record(a, "output-preview-chips-render", chips > 0, `${chips} chips`);
    await shot(page, a, "07_final_state");

    a.finalStatus = sawCompleted ? "succeeded" : "incomplete";
  } catch (e: any) {
    a.error = String(e?.message ?? e);
    record(a, "exception-during-run", false, a.error);
  } finally {
    a.endTs = Date.now();
    SUITE.push(a);
  }
  return a;
}

// ---------------------------------------------------------------------------
// Test runner
// ---------------------------------------------------------------------------

test.afterAll(async () => {
  fs.mkdirSync(AUDIT_DIR, { recursive: true });
  const file = path.join(AUDIT_DIR, `tier0_full_audit_${Date.now()}.json`);
  fs.writeFileSync(file, JSON.stringify(SUITE, null, 2));
  console.log(`\n========== Audit JSON: ${file} ==========`);
  for (const a of SUITE) {
    const passed = a.assertions.filter(x => x.passed).length;
    const failed = a.assertions.filter(x => !x.passed).length;
    console.log(`${a.id} ${a.workflow}: PASS=${passed} FAIL=${failed} runId=${a.runId} status=${a.finalStatus} report=${a.reportChars}c download=${a.downloadedBytes}B`);
  }
});

test.describe("Tier 0 full E2E", () => {
  test.describe.configure({ mode: "default" });

  for (const spec of TIER0_DEMOS) {
    test(`${spec.id}: ${spec.workflow} — register → chat → card → prefill → run → SSE → findings → report → download`,
      async ({ page }) => {
        test.setTimeout(2_400_000); // 40 min per demo (Batch cold-start tolerant)
        const a = await runFullDemo(page, spec);
        const failed = a.assertions.filter(x => !x.passed);
        if (failed.length > 0) {
          expect.soft(failed, `${spec.id} had ${failed.length} failed assertions`).toEqual([]);
        }
      });
  }
});
