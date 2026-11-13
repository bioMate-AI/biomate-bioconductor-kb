/**
 * Autoloop LIVE PROOF — SSE-capture validation
 * =============================================
 * Goal: prove the deployed completion-time fix (autoloop_bridge.evaluate_and_emit)
 * fires autoloop_gate_results + autoloop_update SSE for a real ADMET Batch run
 * that trips the hERG halt (terfenadine).
 *
 * Why not rely only on the DOM panel: the <AutoLoopPanel> render in the live
 * NextflowWorkflowViewer is currently COMMENTED OUT (nextflow-workflow-viewer.tsx
 * ~L825-837 "commented out until QC loop is stable"). The SSE listeners still
 * populate state, and /internal/sse-inject → sseManager.injectRawEvent forwards
 * the events to the browser stream by invocation_id. So the render-independent
 * proof is: subscribe to /api/workflows/{runId}/events and record the raw
 * autoloop_gate_results / autoloop_update events + verify the run record's
 * qc_gates field. We ALSO screenshot the panel and probe the DOM selectors so we
 * can report whether the UI renders.
 *
 * NO page.route() mocking. One real Batch run.
 */

import { test, expect, Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";
import { resolveE2eBaseUrl } from "./_e2e-base-url";
const BASE_URL = resolveE2eBaseUrl("https://dev-public.biomate.ai");

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);


const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const FIXTURE_EMAIL    = process.env.E2E_FIXTURE_EMAIL    || "lifeifei163361@163.com";
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";

// terfenadine — hERG IC50 ≈ 0.01 µM predicted → HALT under admet_standard (threshold 10 µM)
const TERFENADINE_SMILES =
  "CC(C)(C)c1ccc(cc1)C(O)CCCN2CCC(CC2)C(O)(c3ccccc3)c4ccccc4";

const OUT_DIR = path.join(__dirname, "screenshots", "autoloop-live-proof");
fs.mkdirSync(OUT_DIR, { recursive: true });

async function ss(page: Page, name: string) {
  const f = path.join(OUT_DIR, `${name}.png`);
  await page.screenshot({ path: f, fullPage: false });
  console.log(`[screenshot] ${f}`);
}

async function login(page: Page) {
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  const loginResp = await page.request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json" },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  if (!loginResp.ok()) throw new Error(`login failed ${loginResp.status()}: ${await loginResp.text()}`);
  const { token } = await loginResp.json();
  if (!token) throw new Error("login response missing token");
  const u = new URL(BASE_URL);
  await page.context().addCookies([{
    name: "biomate_token", value: token, domain: u.hostname, path: "/",
    httpOnly: true, secure: u.protocol === "https:", sameSite: "Lax",
  }]);
  await page.goto(BASE_URL);
  await page.waitForLoadState("load");
  await page.waitForSelector("textarea", { state: "visible", timeout: 30_000 });
  await page.waitForTimeout(1000);
}

async function sendAndWait(page: Page, msg: string, timeoutMs = 120_000): Promise<void> {
  const ta = page.locator("textarea").first();
  await ta.fill(msg);
  await ta.press("Enter");
  console.log(`[chat] sent: ${msg.slice(0, 80)}…`);
  const loading = [
    "[data-testid='chat-response-pending']",
    "[data-testid='chat-analysis-status']",
    "text=BioMate is thinking",
    "text=Analyzing request",
  ];
  await Promise.race(loading.map(s =>
    page.waitForSelector(s, { state: "visible", timeout: 30_000 }).catch(() => null)));
  await Promise.all(loading.map(s =>
    page.waitForSelector(s, { state: "hidden", timeout: timeoutMs }).catch(() => null)));
  await page.waitForFunction(() => {
    const el = document.querySelector('[data-is-latest-assistant="true"]');
    const t = el?.textContent ?? "";
    return t.length > 30 && !t.includes("thinking");
  }, { timeout: timeoutMs }).catch(() => {});
  await page.waitForTimeout(1500);
}

test.setTimeout(25 * 60 * 1000); // 25 min — one real Batch ADMET run

test("autoloop live proof — terfenadine hERG halt SSE fires end-to-end", async ({ page }) => {
  const captured: Array<{ t: number; type: string; data: any }> = [];

  // Surface page console + install a raw-SSE recorder as soon as we know the runId.
  page.on("console", (m) => {
    const txt = m.text();
    if (/autoloop|qc.?gate|QC Gate|sse|evaluate_and_emit/i.test(txt)) {
      console.log(`[page.console] ${txt.slice(0, 300)}`);
    }
  });
  // Bridge captured SSE events out of the page into node.
  await page.exposeFunction("__recordSSE", (type: string, dataStr: string) => {
    let data: any = dataStr;
    try { data = JSON.parse(dataStr); } catch { /* keep string */ }
    captured.push({ t: Date.now(), type, data });
    console.log(`[SSE captured] ${type} :: ${dataStr.slice(0, 400)}`);
  });

  await login(page);
  await ss(page, "00_login");

  const goal =
    `Screen terfenadine (SMILES ${TERFENADINE_SMILES}) for ADMET properties ` +
    `including hERG IC50, CYP3A4 inhibition and Lipinski Ro5. ` +
    `Use the admet_standard QC profile and halt on blocking cardiotoxicity.`;
  await sendAndWait(page, goal, 120_000);
  await ss(page, "01_workflow_card");

  const runBtn = page.getByTestId("button-run-workflow-panel").last();
  await expect(runBtn).toBeVisible({ timeout: 20_000 });
  await runBtn.click();
  console.log("[proof] run clicked");
  await ss(page, "02_run_started");

  // Discover BOTH ids from the API:
  //  - execId    = execution_run.id           → used for /status and /runs/:id polls
  //  - invId      = execution.galaxyInvocationId → used for the SSE stream + backend _sse_emit key
  // The live viewer subscribes with invocationId (nextflow-workflow-viewer.tsx:1995),
  // and the backend _sse_emit uses invocation_id=run_id (the Galaxy run id) — these match.
  // IMPORTANT: /api/workflows/runs is NOT reliably sorted newest-first, so
  // runs[0] can be a STALE completed run from a prior session. Select the
  // NEWEST run by createdAt whose status is running/queued (i.e. the one we
  // just launched), and only fall back to newest-overall if none is active.
  let execId: string | null = null;
  let invId: string | null = null;
  const launchTs = Date.now() - 5 * 60 * 1000; // runs created within the last 5 min
  for (let i = 0; i < 25 && !invId; i++) {
    const ids = await page.evaluate(async ({ base, since }) => {
      try {
        const r = await fetch(`${base}/api/workflows/runs?limit=15`, { credentials: "include" });
        if (!r.ok) return null;
        const j = await r.json();
        const runs = (j?.runs ?? j ?? []) as any[];
        if (!runs.length) return null;
        const withTs = runs.map((run) => ({
          run,
          created: Date.parse(run.createdAt ?? run.created_at ?? 0) || 0,
          status: (run?.execution?.status ?? run.status ?? "").toLowerCase(),
        }));
        // Prefer the newest recently-created active run (our fresh launch).
        const active = withTs
          .filter(x => x.created >= since && ["running", "queued", "pending", "submitted"].includes(x.status))
          .sort((a, b) => b.created - a.created)[0];
        const pick = active ?? withTs.sort((a, b) => b.created - a.created)[0];
        const run = pick.run;
        return {
          execId: run.id ?? run.run_id ?? null,
          invId: run?.execution?.galaxyInvocationId ?? run.galaxyInvocationId ?? run.run_id ?? run.id ?? null,
          status: pick.status,
          created: pick.created,
        };
      } catch { return null; }
    }, { base: BASE_URL, since: launchTs });
    if (ids?.invId) {
      execId = ids.execId; invId = ids.invId;
      console.log(`[proof] selected run status=${ids.status} createdAt=${new Date(ids.created).toISOString()}`);
    }
    if (!invId) await page.waitForTimeout(3000);
  }
  console.log(`[proof] execId = ${execId}  invId = ${invId}`);
  expect(invId, "must resolve a galaxy invocation id for the SSE stream").toBeTruthy();
  const RID = execId as string;      // for status / run-record polls
  const SSE_ID = invId as string;    // for the events stream

  // Attach a SECOND EventSource in the page pointed at the run's stream, and
  // pipe every autoloop/qc event back to node via __recordSSE. This is
  // render-independent — it proves the backend emitted the SSE regardless of
  // whether the AutoLoopPanel JSX is mounted.
  await page.evaluate(({ base, rid }) => {
    const es = new EventSource(`${base}/api/workflows/${rid}/events`);
    const relay = (type: string) => (ev: MessageEvent) =>
      (window as any).__recordSSE(type, typeof ev.data === "string" ? ev.data : JSON.stringify(ev.data));
    ["autoloop_gate_results", "autoloop_update", "autoloop_phase_complete",
     "autoloop_escalation", "qc_gate_triggered", "qc_warning"].forEach(t =>
      es.addEventListener(t, relay(t)));
    (window as any).__proofES = es;
  }, { base: BASE_URL, rid: SSE_ID });
  console.log("[proof] raw-SSE recorder attached");

  // Wait for the halt gate event OR a terminal state — up to 18 min.
  const deadline = Date.now() + 18 * 60 * 1000;
  let sawGate = false;
  let terminalStatus: string | null = null;
  while (Date.now() < deadline) {
    if (captured.some(e => e.type === "autoloop_gate_results" || e.type === "qc_gate_triggered")) {
      sawGate = true;
    }
    // Poll run status
    const status = await page.evaluate(async ({ base, rid }) => {
      try {
        const r = await fetch(`${base}/api/workflows/runs/${rid}/status`, { credentials: "include" });
        if (!r.ok) return null;
        const j = await r.json();
        return j?.status ?? null;
      } catch { return null; }
    }, { base: BASE_URL, rid: RID });
    if (status && ["completed", "failed", "error"].includes(status)) {
      terminalStatus = status;
      // give the completion-time evaluate_and_emit a few seconds to fire SSE
      await page.waitForTimeout(8000);
      if (captured.some(e => e.type === "autoloop_gate_results" || e.type === "qc_gate_triggered")) sawGate = true;
      break;
    }
    if (sawGate) {
      // keep going a little to also catch the autoloop_update remediation
      await page.waitForTimeout(4000);
      if (captured.some(e => e.type === "autoloop_update")) break;
    }
    await page.waitForTimeout(6000);
  }

  await ss(page, "03_after_wait");

  // Probe the DOM panel selectors (may be absent — panel render is commented out).
  const domProbe = {
    gateTable: await page.locator('[data-testid="autoloop-gate-table"]').count(),
    autoloopPanel: await page.locator('[data-testid="autoloop-panel"]').count(),
    qcGateInline: await page.locator('[data-testid="qc-gate-inline"]').count(),
    remediation: await page.locator('[data-testid="autoloop-remediation-card"]').count(),
  };
  console.log("[proof] DOM probe:", JSON.stringify(domProbe));

  // Fetch the run record for qc_gates.
  const runRecord = await page.evaluate(async ({ base, rid }) => {
    try {
      const r = await fetch(`${base}/api/workflows/runs/${rid}`, { credentials: "include" });
      if (!r.ok) return { httpStatus: r.status };
      return await r.json();
    } catch (e) { return { err: String(e) }; }
  }, { base: BASE_URL, rid: RID });

  const gateEvents = captured.filter(e => e.type === "autoloop_gate_results");
  const updateEvents = captured.filter(e => e.type === "autoloop_update");
  const qcTrig = captured.filter(e => e.type === "qc_gate_triggered");

  // Look for a halt verdict on an hERG gate in the captured gate events.
  let hergHalt = false;
  let hergGateSnippet: any = null;
  for (const ev of gateEvents) {
    const gates = ev.data?.gates ?? [];
    for (const g of gates) {
      const gateName = String(g.gate ?? "").toLowerCase();
      const action = String(g.action ?? g.level ?? "").toLowerCase();
      if (/herg|ic50|qt|cardio/.test(gateName)) {
        hergGateSnippet = g;
        if (action.includes("halt")) hergHalt = true;
      }
    }
  }

  const report = {
    runId: RID,
    terminalStatus,
    sawGate,
    hergHalt,
    hergGateSnippet,
    counts: {
      autoloop_gate_results: gateEvents.length,
      autoloop_update: updateEvents.length,
      qc_gate_triggered: qcTrig.length,
      total_captured: captured.length,
    },
    domProbe,
    qc_gates_in_run_record: (runRecord as any)?.qc_gates ?? (runRecord as any)?.qcGates ?? null,
    run_record_status: (runRecord as any)?.status ?? (runRecord as any)?.execution?.status ?? null,
    remediation_sample: updateEvents[0]?.data?.remediations ?? null,
    all_events: captured.map(e => ({ type: e.type, data: e.data })),
  };
  const reportPath = path.join(OUT_DIR, "proof-report.json");
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log(`[proof] report written: ${reportPath}`);
  console.log("[proof] SUMMARY:", JSON.stringify({
    runId: RID, terminalStatus, sawGate, hergHalt, counts: report.counts, domProbe,
    qc_gates: report.qc_gates_in_run_record,
  }, null, 2));

  // Assertions: the fix is proven if the gate SSE fired with an hERG halt.
  expect(sawGate, "autoloop_gate_results OR qc_gate_triggered must have fired").toBeTruthy();
  expect(hergHalt, "hERG gate must have verdict=halt for terfenadine").toBeTruthy();
});
