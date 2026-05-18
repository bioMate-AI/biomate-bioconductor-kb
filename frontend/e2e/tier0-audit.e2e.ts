/**
 * Tier 0 Demo Audit — T01..T05 super-merged E2E
 *
 * Audits the five Tier 0 demo workflows end-to-end against the live backend.
 * Models on `cryoem-stepwise-and-output.e2e.ts` ("CS-3+4+5+10+12+13+14")
 * for the super-merged audit-record pattern.
 *
 * Catches the three root-cause bugs documented in
 * `docs/20260514_demos_broken_audit.md`:
 *   Bug 1  LLM key remap: inline params must use workflow `required_params`
 *          keys (e.g. `target_a`/`target_b`), not LLM's raw `target_1`/`target_2`.
 *   Bug 2  Form prefill: LLM-extracted values must land in the form inputs
 *          BEFORE Run, otherwise the run button stays disabled / dispatch
 *          silently fails.
 *   Bug 3  Phase-split: all N phase cards must render with
 *          `data-testid^="phase-group-"` and transition idle→running→completed
 *          via live SSE.
 *
 * For each demo (T01..T05) the test asserts:
 *   1. chat-stream emits `workflow_ready` with remapped inline params
 *   2. form is prefilled with LLM values before Run
 *   3. all N phase cards render with `data-testid^="phase-group-"`
 *   4. SSE phase transitions idle→running in real time
 *   5. per-phase output file chips appear after each phase
 *   6. findings endpoint returns real content
 *   7. methods-report endpoint returns real content
 *   8. analyze-results + download-methods-report buttons render
 *   9. all assertions are recorded into per-demo audit arrays
 *
 * NO mocking — per CLAUDE.md, all calls hit live backend at localhost:5000.
 * Screenshots saved to `e2e/screenshots/tier0-audit/<demoId>/`.
 *
 * Run with:
 *   cd frontend && npx playwright test tier0-audit.e2e.ts --reporter=list
 */

import { test, expect, Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";
import { clickRunOnly, BASE_URL as DEMO_BASE_URL } from "./demo-helpers";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || DEMO_BASE_URL || "http://localhost:5000";
const BASE_DOMAIN = new URL(BASE_URL).hostname;
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "test-e2e-token-12345";
const SS_ROOT = path.join(__dirname, "screenshots", "tier0-audit");
if (!fs.existsSync(SS_ROOT)) fs.mkdirSync(SS_ROOT, { recursive: true });

// ---------------------------------------------------------------------------
// Tier 0 demo catalog
// ---------------------------------------------------------------------------

interface DemoSpec {
  id: string;
  workflow: string;
  query: string;
  /** Required-param keys the workflow declares — inline params must include these. */
  requiredKeys: string[];
  /**
   * Sanity check on extracted values:
   * each entry's `key` must exist in inlineParameters AND match the regex.
   */
  valueChecks: { key: string; regex: RegExp }[];
  /** Expected phase-card count (Bug 3). T05 chains atlas+triage = 7. */
  expectedPhaseCount: number;
}

const DEMOS: DemoSpec[] = [
  {
    id: "T01",
    workflow: "bispecific_format_triage",
    query: "Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC",
    requiredKeys: ["target_a", "target_b", "format", "indication"],
    valueChecks: [
      { key: "target_a", regex: /PD-?1|PDCD1/i },
      { key: "target_b", regex: /VEGF|KDR/i },
      { key: "format", regex: /crossmab/i },
      { key: "indication", regex: /NSCLC|lung/i },
    ],
    expectedPhaseCount: 4,
  },
  {
    id: "T02",
    workflow: "in_vivo_cart_codesign",
    query: "In vivo CAR-T for CD19 B-cell lymphoma with anti-CD8 LNP delivery",
    requiredKeys: ["car_target", "indication", "lnp_targeting"],
    valueChecks: [
      { key: "car_target", regex: /CD19/i },
      { key: "indication", regex: /lymphoma|b[_-]?cell/i },
      { key: "lnp_targeting", regex: /anti[_-]?CD8|CD8/i },
    ],
    expectedPhaseCount: 4,
  },
  {
    id: "T03",
    workflow: "in_vivo_base_edit_design",
    query: "Base editing strategy for PCSK9 loss of function in hypercholesterolemia (VERVE-102 style)",
    requiredKeys: ["target_gene", "edit_goal", "indication"],
    valueChecks: [
      { key: "target_gene", regex: /PCSK9/i },
      { key: "edit_goal", regex: /loss[_ -]?of[_ -]?function|lof/i },
      { key: "indication", regex: /hypercholesterolemia/i },
    ],
    expectedPhaseCount: 4,
  },
  {
    id: "T04",
    workflow: "glp1_modality_bakeoff",
    query: "Compare GLP-1 modalities for MASH: semaglutide vs tirzepatide vs retatrutide",
    requiredKeys: ["disease"],
    valueChecks: [
      { key: "disease", regex: /MASH/i },
    ],
    expectedPhaseCount: 4,
  },
  {
    id: "T05",
    workflow: "modality_triage",
    query: "Modality triage for BCMA in multiple myeloma",
    requiredKeys: ["target_gene"],
    valueChecks: [
      { key: "target_gene", regex: /BCMA/i },
    ],
    // T05 chains atlas (3) + triage (4) = 7 phases
    expectedPhaseCount: 7,
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
  confidence: number | null;
  phaseCount: number | null;
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
    confidence: null,
    phaseCount: null,
    assertions: [],
    screenshots: [],
  };
}

function record(a: DemoAudit, name: string, passed: boolean, note?: string) {
  a.assertions.push({ name, passed, note });
  const tag = passed ? "PASS" : "FAIL";
  console.log(`[${a.id}] ${tag}  ${name}${note ? `  — ${note}` : ""}`);
}

async function shot(page: Page, demoId: string, name: string): Promise<string> {
  const dir = path.join(SS_ROOT, demoId);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `${name}.png`);
  await page.screenshot({ path: file, fullPage: false }).catch(() => {});
  return file;
}

// ---------------------------------------------------------------------------
// Auth — register a fresh user, capture JWT for chat-stream calls
// ---------------------------------------------------------------------------

interface AuthCtx {
  email: string;
  token: string;
  userId: number | string | null;
}

async function registerUser(page: Page, label: string): Promise<AuthCtx> {
  const email = `e2e_tier0_${label}_${Date.now()}@biomate.test`;
  const password = "TestPass123!";

  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  await page.addInitScript(() => {
    try { localStorage.clear(); sessionStorage.clear(); } catch {}
  });

  const resp = await page.request.post(`${BASE_URL}/api/auth/register`, {
    headers: { "Content-Type": "application/json", "x-e2e-test-token": E2E_TOKEN },
    data: {
      fullName: `Tier0 ${label}`,
      email,
      password,
      termsAccepted: true,
      privacyAccepted: true,
    },
  });

  let token = "";
  let userId: number | string | null = null;
  if (resp.ok()) {
    const d = await resp.json().catch(() => ({} as any));
    token = d?.token ?? "";
    userId = d?.user?.id ?? d?.userId ?? null;
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
    console.warn(`[registerUser:${label}] registration failed HTTP ${resp.status()}`);
  }

  await page.goto(BASE_URL);
  await page.waitForLoadState("load");
  // Dismiss any onboarding overlay
  for (let i = 0; i < 4; i++) {
    const skip = page.locator(
      'button:has-text("Skip"), button:has-text("Dismiss"), button:has-text("Maybe later"), [data-testid="survey-not-now"]'
    ).first();
    if (await skip.isVisible({ timeout: 1500 }).catch(() => false)) {
      await skip.click({ force: true }).catch(() => {});
      await page.waitForTimeout(400);
    } else break;
  }
  await page.waitForSelector("textarea", { state: "visible", timeout: 20_000 }).catch(() => {});
  await page.waitForTimeout(500);

  return { email, token, userId };
}

// ---------------------------------------------------------------------------
// Assertion #1: chat-stream emits workflow_ready with remapped inline params
// ---------------------------------------------------------------------------

interface WorkflowReadyEvent {
  inlineParameters: Record<string, unknown> | null;
  workflowName: string | null;
  confidence: number | null;
  raw: string;
}

/**
 * POST /api/chat/stream with the canonical query; parse SSE text/event-stream
 * looking for `event: workflow_ready` with a `data:` JSON payload.
 *
 * Uses page.request (Node-side fetch) with the user's JWT as Bearer token AND
 * the e2e bypass header.
 */
async function captureWorkflowReady(
  page: Page,
  auth: AuthCtx,
  query: string,
  demoId: string,
  timeoutMs = 90_000
): Promise<WorkflowReadyEvent> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "X-E2E-Test-Token": E2E_TOKEN,
  };
  if (auth.token) headers["Authorization"] = `Bearer ${auth.token}`;

  // Use page.evaluate so the browser session cookie carries over.
  const result = await page.evaluate(
    async ({ base, body, hdrs, demo, timeout }: any) => {
      try {
        const ctrl = new AbortController();
        const timer = setTimeout(() => ctrl.abort(), timeout);
        const r = await fetch(`${base}/api/chat/stream`, {
          method: "POST",
          headers: hdrs,
          credentials: "include",
          body: JSON.stringify(body),
          signal: ctrl.signal,
        });
        if (!r.ok || !r.body) {
          clearTimeout(timer);
          return { raw: "", error: `HTTP ${r.status}` };
        }
        const reader = r.body.getReader();
        const decoder = new TextDecoder();
        let raw = "";
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          raw += decoder.decode(value, { stream: true });
          if (raw.includes("workflow_ready")) {
            // Give the producer ~1.5 s to flush the full data: block + done event.
            await new Promise(res => setTimeout(res, 1500));
            try { await reader.cancel(); } catch {}
            break;
          }
        }
        clearTimeout(timer);
        return { raw, error: null };
      } catch (e: any) {
        return { raw: "", error: String(e?.message ?? e) };
      }
    },
    {
      base: BASE_URL,
      body: { message: query, demoId },
      hdrs: headers,
      demo: demoId,
      timeout: timeoutMs,
    }
  );

  const raw: string = result?.raw ?? "";
  if (result?.error) {
    console.warn(`[${demoId}] chat-stream fetch error: ${result.error}`);
  }

  // Parse SSE: find `event: workflow_ready` followed by `data: {…}`
  let inlineParameters: Record<string, unknown> | null = null;
  let workflowName: string | null = null;
  let confidence: number | null = null;

  const lines = raw.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    if (/^event:\s*workflow_ready\s*$/.test(lines[i])) {
      // Collect contiguous data: lines
      const dataChunks: string[] = [];
      for (let j = i + 1; j < lines.length; j++) {
        const m = /^data:\s?(.*)$/.exec(lines[j]);
        if (m) { dataChunks.push(m[1]); continue; }
        if (lines[j].trim() === "" && dataChunks.length) break;
        if (/^event:/.test(lines[j])) break;
      }
      if (dataChunks.length) {
        try {
          const obj = JSON.parse(dataChunks.join("\n"));
          inlineParameters =
            obj?.metadata?.inlineParameters ??
            obj?.inlineParameters ??
            obj?.metadata?.inline_parameters ??
            null;
          workflowName =
            obj?.metadata?.workflowName ??
            obj?.workflowName ??
            obj?.metadata?.workflow_name ??
            null;
          confidence =
            obj?.metadata?.confidence ??
            obj?.confidence ??
            null;
        } catch (e) {
          console.warn(`[${demoId}] workflow_ready JSON parse failed`);
        }
      }
      break;
    }
  }

  return { inlineParameters, workflowName, confidence, raw };
}

// ---------------------------------------------------------------------------
// UI helpers — send query in the chat input, wait for the workflow card
// ---------------------------------------------------------------------------

async function sendChat(page: Page, query: string, timeoutMs = 120_000): Promise<boolean> {
  const ta = page.locator("textarea").first();
  if (!await ta.isVisible({ timeout: 10_000 }).catch(() => false)) return false;
  await ta.fill(query);
  await ta.press("Enter");
  const thinking = [
    "[data-testid='chat-response-pending']",
    "[data-testid='chat-analysis-status']",
    "text=BioMate is thinking",
  ];
  await Promise.race(thinking.map(s =>
    page.waitForSelector(s, { state: "visible", timeout: 30_000 }).catch(() => null)
  ));
  await Promise.all(thinking.map(s =>
    page.waitForSelector(s, { state: "hidden", timeout: timeoutMs }).catch(() => null)
  ));
  await page.waitForTimeout(1200);
  return true;
}

async function waitForWorkflowCard(page: Page, timeoutMs = 180_000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    for (const sel of [
      '[data-testid="button-run-workflow-panel"]',
      '[data-testid="button-confirm-and-run"]',
      '[data-testid="workflow-run-controls"]',
      '[data-testid^="phase-group-"]',
      '[data-testid^="phase-card-"]',
    ]) {
      if (await page.locator(sel).first().isVisible({ timeout: 300 }).catch(() => false)) {
        return true;
      }
    }
    await page.waitForTimeout(1200);
  }
  return false;
}

/**
 * Read all visible form input values keyed by `id` / `name`.
 * Used by Assertion #2 to confirm LLM values landed in the form before Run.
 */
async function readFormValues(page: Page): Promise<Record<string, string>> {
  // The viewer collapses inline-parameter inputs under "Advanced settings" —
  // expand it (button-toggle-advanced-settings) before reading values so the
  // <Input> elements are actually in the DOM. Per docs/20260518_tier0_audit_T01_results.md.
  const toggle = page.locator('[data-testid="button-toggle-advanced-settings"]').first();
  if (await toggle.isVisible({ timeout: 2000 }).catch(() => false)) {
    // Only click if strip isn't already open (className contains "open")
    const isOpen = await toggle.evaluate(
      (el: Element) => (el as HTMLElement).className.includes('open')
    ).catch(() => false);
    if (!isOpen) {
      await toggle.click().catch(() => {});
      await page.waitForTimeout(400);
    }
  }
  return page.evaluate(() => {
    const out: Record<string, string> = {};
    const inputs = document.querySelectorAll(
      'input[type="text"], input[type="number"], input:not([type]), textarea, select'
    );
    inputs.forEach(el => {
      const node = el as HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement;
      const key = node.id || node.name || "";
      if (!key) return;
      const v = node.value ?? "";
      if (v && v !== "null") out[key] = v;
    });
    return out;
  }).catch(() => ({}));
}

// ---------------------------------------------------------------------------
// SSE phase transitions (Assertion #4) — wait for first idle→running
// ---------------------------------------------------------------------------

async function waitForFirstRunningPhase(page: Page, timeoutMs = 120_000): Promise<boolean> {
  return page.waitForFunction(
    () => !!document.querySelector('[data-testid^="phase-group-"][data-status="running"]'),
    { timeout: timeoutMs }
  ).then(() => true).catch(() => false);
}

async function waitForAnyCompletedPhase(page: Page, timeoutMs = 900_000): Promise<boolean> {
  return page.waitForFunction(
    () => !!document.querySelector('[data-testid^="phase-group-"][data-status="completed"]'),
    { timeout: timeoutMs }
  ).then(() => true).catch(() => false);
}

// ---------------------------------------------------------------------------
// Per-demo audit
// ---------------------------------------------------------------------------

async function auditDemo(page: Page, spec: DemoSpec): Promise<DemoAudit> {
  const a = mkAudit(spec);
  console.log(`\n========== ${spec.id}  ${spec.workflow} ==========`);

  try {
    const auth = await registerUser(page, spec.id.toLowerCase());

    // ── #1  chat-stream workflow_ready event with remapped inline params ─────
    const evt = await captureWorkflowReady(page, auth, spec.query, spec.id);
    a.inlineParameters = evt.inlineParameters;
    a.confidence = evt.confidence;

    record(a, "chat-stream-emits-workflow-ready", !!evt.inlineParameters,
      evt.inlineParameters ? `workflow=${evt.workflowName}` : "no workflow_ready event found");

    if (evt.inlineParameters) {
      const keys = Object.keys(evt.inlineParameters);

      // Bug 1: required keys must be remapped — no raw `target_1`/`target_2`/`gene`/`target`
      const rawLlmKeys = ["target_1", "target_2", "gene", "target"];
      const stillRaw = rawLlmKeys.filter(k => keys.includes(k));
      record(a, "no-raw-llm-keys-leaked",
        stillRaw.length === 0,
        stillRaw.length ? `raw keys present: ${stillRaw.join(",")}` : undefined);

      for (const reqKey of spec.requiredKeys) {
        record(a, `inline-has-required-key:${reqKey}`,
          keys.includes(reqKey),
          keys.includes(reqKey) ? undefined : `missing ${reqKey}; got [${keys.join(",")}]`);
      }

      for (const chk of spec.valueChecks) {
        const v = evt.inlineParameters[chk.key];
        const ok = typeof v === "string" && chk.regex.test(v);
        record(a, `inline-value-matches:${chk.key}`,
          ok, ok ? `${chk.key}="${v}"` : `${chk.key}=${JSON.stringify(v)} fails ${chk.regex}`);
      }

      if (typeof evt.confidence === "number") {
        record(a, "confidence-at-least-80",
          evt.confidence >= 80, `confidence=${evt.confidence}`);
      }

      // T01-specific reinforcement of Bug 1
      if (spec.id === "T01") {
        record(a, "T01-target_a-not-target_1",
          keys.includes("target_a") && !keys.includes("target_1"));
        record(a, "T01-target_b-not-target_2",
          keys.includes("target_b") && !keys.includes("target_2"));
      }
    } else {
      // Record skipped assertions so the audit count stays consistent
      for (const reqKey of spec.requiredKeys) {
        record(a, `inline-has-required-key:${reqKey}`, false, "no inlineParameters");
      }
      for (const chk of spec.valueChecks) {
        record(a, `inline-value-matches:${chk.key}`, false, "no inlineParameters");
      }
    }

    // ── #2  UI: send the same query through the chat input, form prefilled ──
    const sentOk = await sendChat(page, spec.query);
    record(a, "chat-input-sent", sentOk);

    const cardOk = await waitForWorkflowCard(page);
    record(a, "workflow-card-appeared", cardOk);
    a.screenshots.push(await shot(page, spec.id, "01_card"));

    if (cardOk) {
      const formValues = await readFormValues(page);
      // Each value check from the chat-stream should also be visible in the form
      for (const chk of spec.valueChecks) {
        const v = formValues[chk.key];
        const ok = typeof v === "string" && chk.regex.test(v);
        record(a, `form-prefilled:${chk.key}`,
          ok, ok ? `${chk.key}="${v}"` : `form ${chk.key}=${JSON.stringify(v)}`);
      }

      // ── #3  N phase cards render with phase-group-* testid + data-status ──
      const groups = page.locator('[data-testid^="phase-group-"]');
      const groupCount = await groups.count().catch(() => 0);
      a.phaseCount = groupCount;
      record(a, "phase-group-cards-render",
        groupCount >= spec.expectedPhaseCount,
        `got ${groupCount} groups, expected ≥${spec.expectedPhaseCount}`);

      // initial data-status should be pending/idle on the first card
      const firstStatus = await groups.first().getAttribute("data-status").catch(() => null);
      record(a, "first-phase-initial-status-pending",
        firstStatus === "pending" || firstStatus === "idle" || firstStatus === null,
        `data-status=${firstStatus}`);

      // ── #4  Run + SSE: idle→running on first phase ──────────────────────
      let runId: string | null = null;
      try {
        runId = await clickRunOnly(page);
      } catch (e: any) {
        record(a, "click-run-dispatched", false, e?.message ?? String(e));
      }
      if (runId) {
        a.runId = runId;
        record(a, "click-run-dispatched", true, `runId=${runId}`);
        a.screenshots.push(await shot(page, spec.id, "02_running"));

        const sawRunning = await waitForFirstRunningPhase(page, 120_000);
        record(a, "first-phase-transitions-running", sawRunning);

        // Bug D from 20260518 audit: AWS Batch cold-start can exceed 900s; raise to 25 min.
        const sawCompleted = await waitForAnyCompletedPhase(page, 1_500_000);
        record(a, "any-phase-reaches-completed", sawCompleted);
        a.screenshots.push(await shot(page, spec.id, "03_after_running"));

        // Determine final status
        const finalStatus = await page.evaluate(() => {
          const badge = document.querySelector('[data-testid="workflow-overall-status-badge"]');
          if (badge) {
            const s = (badge as HTMLElement).dataset.status ?? "";
            if (s) return s;
          }
          const cards = document.querySelectorAll('[data-testid^="phase-group-"]');
          const arr = Array.from(cards).map(c => (c as HTMLElement).dataset.status ?? "");
          if (arr.length && arr.every(s => s === "completed")) return "completed";
          if (arr.some(s => s === "failed")) return "failed";
          if (arr.some(s => s === "running" || s === "queued")) return "running";
          return "unknown";
        }).catch(() => "unknown");
        a.finalStatus = finalStatus;

        // ── #5  per-phase output file chips ─────────────────────────────────
        const previewCount = await page.locator('[data-testid^="phase-card-preview-btn-"]')
          .count().catch(() => 0);
        record(a, "per-phase-preview-chips-render", previewCount > 0,
          `${previewCount} preview chips`);

        if (previewCount > 0) {
          const firstPreview = page.locator('[data-testid^="phase-card-preview-btn-"]').first();
          await firstPreview.click().catch(() => {});
          await page.waitForTimeout(1500);
          const previewVisible = await page.locator(
            '[data-testid="step-output-preview"], pre, table, img'
          ).first().isVisible({ timeout: 5000 }).catch(() => false);
          record(a, "inline-step-output-preview-opens", previewVisible);
          a.screenshots.push(await shot(page, spec.id, "04_preview"));
        }

        // ── #6  findings endpoint ───────────────────────────────────────────
        const findingsResp = await page.request.get(
          `${BASE_URL}/api/workflows/runs/${runId}/findings`,
          { headers: { "x-e2e-test-token": E2E_TOKEN }, timeout: 30_000 }
        ).catch(() => null);
        const findingsStatus = findingsResp?.status() ?? -1;
        record(a, "findings-endpoint-returns-200",
          findingsStatus === 200, `HTTP ${findingsStatus}`);
        if (findingsStatus === 200) {
          const body: any = await findingsResp!.json().catch(() => ({}));
          const hasContent =
            (typeof body?.summary === "string" && body.summary.length > 20) ||
            (Array.isArray(body?.key_findings) && body.key_findings.length > 0);
          record(a, "findings-has-real-content",
            hasContent,
            hasContent ? undefined : `body.status=${body?.status}, keys=[${Object.keys(body).join(",")}]`);
        }

        // ── #7  methods-report endpoint ─────────────────────────────────────
        // Methods report generation calls Claude Sonnet + scans S3, can take 60s+
        const reportResp = await page.request.get(
          `${BASE_URL}/api/invocations/${runId}/methods-report`,
          { headers: { "x-e2e-test-token": E2E_TOKEN }, timeout: 120_000 }
        ).catch(() => null);
        const reportStatus = reportResp?.status() ?? -1;
        record(a, "methods-report-returns-200",
          reportStatus === 200, `HTTP ${reportStatus}`);
        if (reportStatus === 200) {
          const text = await reportResp!.text().catch(() => "");
          record(a, "methods-report-has-content",
            text.length > 500, `${text.length} chars`);
        }

        // ── #8  analyze-results + download-methods-report buttons ──────────
        const analyzeBtn = page.locator('[data-testid="button-analyze-results"]').first();
        const dlReportBtn = page.locator('[data-testid="button-download-methods-report"]').first();
        record(a, "analyze-results-btn-renders",
          await analyzeBtn.isVisible({ timeout: 8000 }).catch(() => false));
        record(a, "download-methods-report-btn-renders",
          await dlReportBtn.isVisible({ timeout: 8000 }).catch(() => false));
        a.screenshots.push(await shot(page, spec.id, "05_post_complete"));
      } else {
        // Skipped assertions for run-dependent steps (keep audit count stable)
        for (const n of [
          "first-phase-transitions-running",
          "any-phase-reaches-completed",
          "per-phase-preview-chips-render",
          "findings-endpoint-returns-200",
          "methods-report-returns-200",
          "analyze-results-btn-renders",
          "download-methods-report-btn-renders",
        ]) record(a, n, false, "skipped — no runId");
      }
    }
  } catch (err: any) {
    a.error = err?.message ?? String(err);
    record(a, "audit-completed-without-exception", false, a.error);
    await shot(page, spec.id, "99_error").catch(() => {});
  } finally {
    a.endTs = Date.now();
    SUITE.push(a);
  }

  return a;
}

// ---------------------------------------------------------------------------
// Final report — Assertion #9
// ---------------------------------------------------------------------------

function printSuiteReport() {
  console.log("\n\n========== TIER 0 AUDIT REPORT ==========");
  let totalPass = 0;
  let totalFail = 0;
  for (const a of SUITE) {
    const pass = a.assertions.filter(x => x.passed).length;
    const fail = a.assertions.length - pass;
    totalPass += pass;
    totalFail += fail;
    console.log(`\n[${a.id}] ${a.workflow}  pass=${pass} fail=${fail}  status=${a.finalStatus}  runId=${a.runId ?? "-"}`);
    for (const ass of a.assertions) {
      if (!ass.passed) console.log(`   FAIL  ${ass.name}${ass.note ? `  — ${ass.note}` : ""}`);
    }
  }
  console.log(`\nTOTAL  pass=${totalPass}  fail=${totalFail}`);

  // Write JSON dump for downstream tooling
  const out = path.join(SS_ROOT, `tier0_audit_${Date.now()}.json`);
  try {
    fs.writeFileSync(out, JSON.stringify(SUITE, null, 2));
    console.log(`Audit JSON: ${out}`);
  } catch { /* ignore */ }
}

// ---------------------------------------------------------------------------
// Tests — one per Tier 0 demo
// ---------------------------------------------------------------------------

test.describe("Tier 0 demo audit", () => {
  test.describe.configure({ mode: "serial" });

  for (const spec of DEMOS) {
    test(`${spec.id}: ${spec.workflow} — chat-stream + form prefill + phases + outputs`,
      async ({ page }) => {
        test.setTimeout(2_100_000); // 35 min per demo — accommodates Bug D cold-start + report gen
        const a = await auditDemo(page, spec);
        // The test passes if no assertions failed AND no exception was caught.
        const failed = a.assertions.filter(x => !x.passed);
        if (failed.length > 0) {
          // Don't hard-fail the worker — we want all 5 demos to run and the
          // suite report to surface every failure. Use expect to mark the
          // Playwright result while preserving the audit dump.
          expect.soft(failed, `${spec.id} had ${failed.length} failed assertions`).toEqual([]);
        }
      });
  }

  test.afterAll(() => {
    printSuiteReport();
  });
});
