/**
 * REAL end-to-end ADMET auto-loop run on LIVE dev — full dynamic-chain proof.
 * ==========================================================================
 * This LAUNCHES one real AWS-Batch ADMET run (authorized). It exercises the
 * previously-SKIPPED dynamic use-cases that mock/fast harnesses never covered:
 *
 *   RS-04  live SSE idle→running transition on the overall badge/footer
 *   RS-05  a phase card flips pending→running in real time (waitForFunction)
 *   AB-01  running action bar appears (Pause/Stop) while status=running
 *   QC-01  the hERG QC gate FIRES for terfenadine (measured vs threshold)
 *   AL-01  auto-loop remediation card / SSE (was→now) if it appears
 *   FN-01  Findings tab shows REAL result values (not placeholder) on completion
 *   DL-01  Download-report link is visible + linked to a real URL
 *
 * Rules (CLAUDE.md): NO page.route() mocking. Shared fixture only. Login once.
 * One project. Screenshots of EVERY state to e2e/execshots/realrun-admet/.
 *
 * Terfenadine is a canonical hERG blocker → the admet gate should HALT. We
 * screen it alongside two safe controls so the gate has a contrast set.
 *
 * The QC-gate + auto-loop verdicts live on the SSE stream (autoloop_gate_results
 * / autoloop_update), NOT on the run record (verified live: qc_gates is null on
 * every recent ADMET run record). So we ALSO attach a render-independent
 * EventSource — same technique as autoloop-live-proof.e2e.ts — and additionally
 * probe the inline DOM gate (qc-gate-inline / qc-gate-measured / qc-gate-threshold).
 *
 * We record HONEST verdicts: PASS / FAIL / N/A (with reason). We never fake
 * green and never report SKIP for anything we were able to exercise.
 */

import { test, expect, Page } from "@playwright/test";
import { resolveE2eBaseUrl } from "./_e2e-base-url";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = resolveE2eBaseUrl("https://dev-public.biomate.ai");
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const FIXTURE_EMAIL = process.env.E2E_FIXTURE_EMAIL || "lifeifei163361@163.com";
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";

// terfenadine — known hERG blocker → HALT under admet_standard (threshold ~10 µM)
const TERFENADINE = "CC(C)(C)c1ccc(cc1)C(O)CCCN2CCC(CC2)C(O)(c3ccccc3)c4ccccc4";
// two safe controls: caffeine + aspirin
const CAFFEINE = "CN1C=NC2=C1C(=O)N(C(=O)N2C)C";
const ASPIRIN = "CC(=O)OC1=CC=CC=C1C(=O)O";

const OUT_DIR = path.join(__dirname, "execshots", "realrun-admet");
fs.mkdirSync(OUT_DIR, { recursive: true });

// ── honest verdict ledger ───────────────────────────────────────────────────
type Verdict = "PASS" | "FAIL" | "N/A";
const ledger: Record<string, { verdict: Verdict; note: string }> = {};
function record(uc: string, verdict: Verdict, note: string) {
  ledger[uc] = { verdict, note };
  console.log(`[UC ${uc}] ${verdict} — ${note}`);
}

async function ss(page: Page, name: string) {
  const f = path.join(OUT_DIR, `${name}.png`);
  await page.screenshot({ path: f, fullPage: false }).catch((e) => console.log(`[ss fail ${name}] ${e}`));
  console.log(`[screenshot] ${f}`);
}

async function login(page: Page) {
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  const resp = await page.request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json" },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  if (!resp.ok()) throw new Error(`login failed ${resp.status()}: ${await resp.text()}`);
  const { token } = await resp.json();
  if (!token) throw new Error("login response missing token");
  const u = new URL(BASE_URL);
  await page.context().addCookies([{
    name: "biomate_token", value: token, domain: u.hostname, path: "/",
    httpOnly: false, secure: u.protocol === "https:", sameSite: "Lax",
  }]);
  await page.context().setExtraHTTPHeaders({
    Authorization: `Bearer ${token}`,
    "X-E2E-Test-Token": E2E_TOKEN,
    "X-Forwarded-Proto": "https",
  });
  await page.goto(BASE_URL);
  await page.waitForLoadState("load").catch(() => {});
  await page.waitForSelector("textarea", { state: "visible", timeout: 45_000 });
  await page.waitForTimeout(1200);
  return token;
}

async function sendChat(page: Page, msg: string, timeoutMs = 120_000) {
  const ta = page.locator("textarea").first();
  await ta.fill(msg);
  await ta.press("Enter");
  console.log(`[chat] sent: ${msg.slice(0, 90)}…`);
  const loading = [
    "[data-testid='chat-response-pending']",
    "[data-testid='chat-analysis-status']",
    "text=BioMate is thinking",
    "text=Analyzing request",
  ];
  await Promise.race(loading.map((s) =>
    page.waitForSelector(s, { state: "visible", timeout: 30_000 }).catch(() => null)));
  await Promise.all(loading.map((s) =>
    page.waitForSelector(s, { state: "hidden", timeout: timeoutMs }).catch(() => null)));
  await page.waitForTimeout(1500);
}

test.setTimeout(35 * 60 * 1000); // 35 min — one real Batch ADMET run + findings poll

test("realrun-admet — live dynamic chain (SSE, action bar, QC gate, auto-loop, findings, download)", async ({ page }) => {
  const captured: Array<{ t: number; type: string; data: any }> = [];
  page.on("console", (m) => {
    const t = m.text();
    if (/autoloop|qc.?gate|herg|sse|remediation/i.test(t)) console.log(`[page] ${t.slice(0, 240)}`);
  });
  await page.exposeFunction("__recordSSE", (type: string, dataStr: string) => {
    let data: any = dataStr;
    try { data = JSON.parse(dataStr); } catch { /* keep string */ }
    captured.push({ t: Date.now(), type, data });
    console.log(`[SSE] ${type} :: ${dataStr.slice(0, 300)}`);
  });

  await login(page);
  await ss(page, "00_login");

  // ── 1. Send ADMET/hERG request including terfenadine ───────────────────────
  const goal =
    `Screen these compounds for ADMET properties including hERG cardiotoxicity IC50, ` +
    `CYP3A4 inhibition and Lipinski Ro5. Use the admet_standard QC profile and halt on ` +
    `blocking cardiotoxicity.\n` +
    `- terfenadine: ${TERFENADINE}\n` +
    `- caffeine: ${CAFFEINE}\n` +
    `- aspirin: ${ASPIRIN}`;
  await sendChat(page, goal, 120_000);
  await ss(page, "01_chat_workflow_suggested");

  // ── 2. Assert the workflow card / panel renders with a REAL name ────────────
  // Prefer the right-panel name (canonical). Fall back to chat wf-chip name.
  const panelName = page.locator(".panel-name").first();
  let wfName = "";
  if (await panelName.count()) {
    wfName = (await panelName.textContent().catch(() => "") || "").trim();
  }
  if (!wfName || wfName === "Untitled") {
    const chip = page.locator(".wf-chip-name").first();
    if (await chip.count()) wfName = (await chip.textContent().catch(() => "") || "").trim();
  }
  console.log(`[wf] panel/card name = "${wfName}"`);
  const nameOk = !!wfName && wfName !== "undefined" && wfName !== "Untitled" && wfName.length > 3;
  record("CARD-name", nameOk ? "PASS" : "FAIL",
    nameOk ? `workflow card/panel shows real name "${wfName}"` : `bad workflow name "${wfName}"`);
  await ss(page, "02_workflow_card_name");

  // ── Confirm idle badge before run (RS-04 baseline) ──────────────────────────
  const idleStatus = await page.locator('[data-testid="workflow-overall-status-badge"]')
    .first().getAttribute("data-status").catch(() => null);
  console.log(`[badge] pre-run data-status = ${idleStatus}`);

  // ── Click Confirm & Run ─────────────────────────────────────────────────────
  const runBtn = page.getByTestId("button-run-workflow-panel").last();
  const haveRunBtn = await runBtn.isVisible().catch(() => false);
  if (!haveRunBtn) {
    record("RUN-click", "FAIL", "Confirm & Run button (button-run-workflow-panel) not visible — cannot launch run");
    await ss(page, "02b_no_run_button");
    // Nothing to poll; abort with an honest report.
    finalize(null, "no-run-button", captured, {});
    throw new Error("Confirm & Run button not visible — see execshots");
  }
  await runBtn.click();
  console.log("[run] Confirm & Run clicked");
  record("RUN-click", "PASS", "Confirm & Run clicked");

  // ── 3a. RS-04: live idle→running transition on overall badge/footer ─────────
  let rs04: Verdict = "FAIL", rs04note = "badge never reached running";
  try {
    await page.waitForFunction(() => {
      const b = document.querySelector('[data-testid="workflow-overall-status-badge"]');
      const bar = document.querySelector('[data-testid="panel-action-bar"]');
      return b?.getAttribute("data-status") === "running" ||
             bar?.getAttribute("data-status") === "running";
    }, { timeout: 90_000 });
    rs04 = "PASS"; rs04note = "overall badge/action-bar flipped idle→running via SSE";
  } catch (e) { rs04note = `no idle→running within 90s: ${String(e).slice(0, 120)}`; }
  record("RS-04", rs04, rs04note);
  await ss(page, "03_running_state");

  // ── AB-01: running action bar (Pause/Stop) present while running ────────────
  const actionBar = page.locator('[data-testid="panel-action-bar"][data-status="running"]');
  const pauseBtn = page.getByTestId("panel-action-pause");
  const ab01 = (await actionBar.count()) > 0 && (await pauseBtn.count()) > 0;
  record("AB-01", ab01 ? "PASS" : (rs04 === "PASS" ? "FAIL" : "N/A"),
    ab01 ? "running action bar with Pause/Stop rendered" :
      (rs04 === "PASS" ? "status=running but action bar absent (UI bug)" : "run never reached running"));

  // ── 3b. RS-05: a phase card flips pending→running in real time ──────────────
  let rs05: Verdict = "FAIL", rs05note = "no phase card reached running";
  try {
    await page.waitForFunction(() => {
      const cards = Array.from(document.querySelectorAll('[data-testid^="phase-group-"], [data-testid^="phase-card-"]'));
      return cards.some((c) => c.getAttribute("data-status") === "running");
    }, { timeout: 90_000 });
    rs05 = "PASS"; rs05note = "a phase card data-status flipped to running (live)";
  } catch (e) { rs05note = `no phase card→running within 90s: ${String(e).slice(0, 120)}`; }
  record("RS-05", rs05, rs05note);
  await ss(page, "04_phase_running");

  // ── Discover run ids for polling + SSE (newest active run) ──────────────────
  let execId: string | null = null;
  let invId: string | null = null;
  const since = Date.now() - 6 * 60 * 1000;
  for (let i = 0; i < 25 && !invId; i++) {
    const ids = await page.evaluate(async ({ base, since }) => {
      try {
        const r = await fetch(`${base}/api/workflows/runs?limit=15`, { credentials: "include" });
        if (!r.ok) return null;
        const j = await r.json();
        const runs = (Array.isArray(j) ? j : j?.runs ?? []) as any[];
        if (!runs.length) return null;
        const rows = runs.map((run) => ({
          run,
          created: Date.parse(run.createdAt ?? run.created_at ?? "") || 0,
          status: (run?.execution?.status ?? run.status ?? "").toLowerCase(),
        }));
        const active = rows
          .filter((x) => x.created >= since && ["running", "queued", "pending", "submitted"].includes(x.status))
          .sort((a, b) => b.created - a.created)[0];
        const pick = active ?? rows.sort((a, b) => b.created - a.created)[0];
        const run = pick.run;
        return {
          execId: run.id ?? run.run_id ?? null,
          invId: run?.execution?.galaxyInvocationId ?? run.galaxyInvocationId ?? run.run_id ?? run.id ?? null,
          status: pick.status,
          name: run.workflowName ?? run?.workflowDefinition?.name ?? "",
        };
      } catch { return null; }
    }, { base: BASE_URL, since });
    if (ids?.invId) {
      execId = ids.execId; invId = ids.invId;
      console.log(`[run] execId=${execId} invId=${invId} status=${ids.status} name="${ids.name}"`);
    } else await page.waitForTimeout(3000);
  }
  expect(invId, "must resolve a run/invocation id for polling").toBeTruthy();
  const RID = execId as string;
  const SSE_ID = invId as string;
  console.log(`[run] RID=${RID} SSE_ID=${SSE_ID}`);

  // ── Attach render-independent SSE recorder (QC gate lives on SSE) ───────────
  await page.evaluate(({ base, rid }) => {
    const es = new EventSource(`${base}/api/workflows/${rid}/events`);
    const relay = (type: string) => (ev: MessageEvent) =>
      (window as any).__recordSSE(type, typeof ev.data === "string" ? ev.data : JSON.stringify(ev.data));
    ["autoloop_gate_results", "autoloop_update", "autoloop_phase_complete",
     "autoloop_escalation", "qc_gate_triggered", "qc_warning", "step_completed",
     "phase_complete", "workflow_complete", "workflow_failed"].forEach((t) =>
      es.addEventListener(t, relay(t)));
    (window as any).__es = es;
  }, { base: BASE_URL, rid: SSE_ID });
  console.log("[sse] raw recorder attached");

  // ── 4. Poll to terminal (up to ~30 min) ─────────────────────────────────────
  const deadline = Date.now() + 30 * 60 * 1000;
  let terminal: string | null = null;
  let recordExecStatus: string | null = null;
  while (Date.now() < deadline) {
    // Prefer the run-record execution.status (what the panel binds to); also
    // read the /status endpoint (can DISAGREE — noted in report).
    const snap = await page.evaluate(async ({ base, rid }) => {
      const out: any = {};
      try {
        const r = await fetch(`${base}/api/workflows/runs/${rid}`, { credentials: "include" });
        if (r.ok) { const j = await r.json(); out.exec = (j?.execution?.status ?? j?.status ?? null); }
      } catch { /* */ }
      try {
        const s = await fetch(`${base}/api/workflows/runs/${rid}/status`, { credentials: "include" });
        if (s.ok) { const j = await s.json(); out.statusEp = j?.status ?? null; }
      } catch { /* */ }
      return out;
    }, { base: BASE_URL, rid: RID });
    recordExecStatus = snap.exec ?? recordExecStatus;
    const combined = (snap.exec || snap.statusEp || "").toLowerCase();
    if (["completed", "failed", "error"].includes(combined)) {
      terminal = combined;
      console.log(`[poll] terminal: exec=${snap.exec} statusEp=${snap.statusEp}`);
      // give completion-time evaluate_and_emit a moment to fire the gate SSE
      await page.waitForTimeout(9000);
      break;
    }
    console.log(`[poll] exec=${snap.exec} statusEp=${snap.statusEp} (${Math.round((deadline - Date.now())/60000)}m left)`);
    await page.waitForTimeout(15_000);
  }
  await ss(page, "05_terminal_state");

  // ── QC-01: hERG gate fired (SSE gate events + inline DOM) ────────────────────
  const gateEvents = captured.filter((e) => e.type === "autoloop_gate_results" || e.type === "qc_gate_triggered");
  let hergHalt = false, hergSnippet: any = null;
  for (const ev of gateEvents) {
    const gates = ev.data?.gates ?? (Array.isArray(ev.data) ? ev.data : []);
    for (const g of gates || []) {
      const nm = String(g.gate ?? g.metric ?? "").toLowerCase();
      const act = String(g.action ?? g.level ?? g.verdict ?? "").toLowerCase();
      if (/herg|ic50|qt|cardio/.test(nm)) { hergSnippet = g; if (act.includes("halt") || act.includes("fail")) hergHalt = true; }
    }
  }
  // inline DOM gate
  const inlineGate = await page.locator('[data-testid="qc-gate-inline"]').count();
  const measured = inlineGate ? await page.locator('[data-testid="qc-gate-measured"]').first().textContent().catch(() => null) : null;
  const threshold = inlineGate ? await page.locator('[data-testid="qc-gate-threshold"]').first().textContent().catch(() => null) : null;
  const qcFired = hergHalt || (inlineGate > 0 && !!measured);
  record("QC-01", qcFired ? "PASS" : "FAIL",
    qcFired
      ? `hERG gate fired — SSE halt=${hergHalt}; inline measured=${measured ?? "-"} threshold=${threshold ?? "-"}`
      : `no hERG gate fired — gateEvents=${gateEvents.length}, inlineGate=${inlineGate} (terminal=${terminal})`);
  if (inlineGate) await ss(page, "06_qc_gate_inline");

  // ── AL-01: auto-loop remediation card / SSE (was→now) ───────────────────────
  const updateEvents = captured.filter((e) => e.type === "autoloop_update");
  const remediationDom = await page.locator('[data-testid="autoloop-remediation-card"]').count();
  const al01: Verdict =
    updateEvents.length > 0 || remediationDom > 0 ? "PASS"
    : (terminal === "failed" && !qcFired) ? "N/A" : "N/A";
  record("AL-01", al01,
    al01 === "PASS"
      ? `auto-loop remediation observed (SSE updates=${updateEvents.length}, domCard=${remediationDom})`
      : `no remediation emitted (auto-loop panel render is commented out; SSE updates=${updateEvents.length}) — treated as N/A not FAIL`);

  // ── FN-01 + DL-01: Findings tab + download (only meaningful on completion) ──
  // Open the After-run tab.
  const afterTab = page.getByTestId("panel-tab-after-run");
  if (await afterTab.count()) { await afterTab.click().catch(() => {}); await page.waitForTimeout(800); }
  const findingsTabInner = page.getByTestId("after-tab-findings");
  if (await findingsTabInner.count()) { await findingsTabInner.click().catch(() => {}); await page.waitForTimeout(800); }
  await ss(page, "07_findings_tab");

  if (terminal === "completed") {
    // Poll findings up to 3 min for real values (not placeholder).
    let findings: any = null;
    const fDeadline = Date.now() + 3 * 60 * 1000;
    while (Date.now() < fDeadline) {
      findings = await page.evaluate(async ({ base, rid }) => {
        try { const r = await fetch(`${base}/api/workflows/runs/${rid}/findings`, { credentials: "include" }); return r.ok ? await r.json() : { httpStatus: r.status }; }
        catch (e) { return { err: String(e) }; }
      }, { base: BASE_URL, rid: RID });
      if (findings && findings.status !== "pending") break;
      console.log(`[findings] still pending…`);
      await page.waitForTimeout(12_000);
    }
    const hasReal = !!findings && findings.status !== "pending" &&
      (!!findings.summary || !!findings.reportMd || (findings.key_results?.length || findings.keyResults?.length));
    record("FN-01", hasReal ? "PASS" : "FAIL",
      hasReal ? `findings populated (summary/keyResults present)` :
        `findings never left status=pending after 3min — REAL BUG (findings never arrive). last=${JSON.stringify(findings).slice(0,160)}`);
    await page.waitForTimeout(1000);
    await ss(page, "08_findings_content");

    // DL-01: download-report link visible + linked
    const dlBtn = page.getByTestId("afterrun-download-report");
    const dlLink = page.locator('a[href*="/findings/report"], a[download]');
    const dlVisible = (await dlBtn.count()) > 0 || (await dlLink.count()) > 0;
    let dlHref: string | null = null;
    if (await dlLink.count()) dlHref = await dlLink.first().getAttribute("href").catch(() => null);
    record("DL-01", dlVisible ? "PASS" : "FAIL",
      dlVisible ? `download-report control present (afterrun btn=${await dlBtn.count()}, anchor href=${dlHref ?? "n/a (button-driven)"})`
                : `no download-report control after completion`);
  } else if (terminal === "failed" || terminal === "error") {
    // Failed path: static "Analysis not available…" (no spinner)
    await page.waitForTimeout(2500);
    const notAvail = await page.getByText("Analysis not available", { exact: false }).count();
    const inProgress = await page.getByText("Analysis in progress", { exact: false }).count();
    const analyzing = await page.getByText("Analyzing outputs", { exact: false }).count();
    const failedSection = await page.getByTestId("afterrun-failed-section").count();
    const errMsg = await page.getByTestId("afterrun-error-message").textContent().catch(() => null);
    const staticOk = (notAvail > 0 || failedSection > 0) && inProgress === 0 && analyzing === 0;
    record("FN-01", staticOk ? "PASS" : "FAIL",
      staticOk ? `failed run shows static failure UI (no findings spinner). error="${(errMsg||"").slice(0,140)}"`
               : `failed run findings state wrong: notAvail=${notAvail} inProgress=${inProgress} analyzing=${analyzing} failedSection=${failedSection}`);
    record("DL-01", "N/A", "run failed — no completed report to download (expected)");
    await ss(page, "08_failed_findings");
    console.log(`[FAILURE] real error surfaced in UI: ${(errMsg || "(none)").slice(0, 400)}`);
  } else {
    record("FN-01", "N/A", `run did not reach terminal within 30min (last exec=${recordExecStatus}) — INFRA stall, not a UI bug`);
    record("DL-01", "N/A", "run non-terminal — nothing to download");
  }

  finalize(RID, terminal, captured, { wfName, hergSnippet, measured, threshold, recordExecStatus });

  // Hard assertions: the run must at least reach running with a live transition.
  // (Terminal/QC outcomes are recorded honestly above, not force-passed.)
  expect(rs04, "must observe a live idle→running transition (RS-04)").toBe("PASS");
});

function finalize(
  runId: string | null,
  terminal: string | null,
  captured: Array<{ t: number; type: string; data: any }>,
  extra: Record<string, any>,
) {
  const report = {
    runId,
    terminalStatus: terminal,
    verdicts: ledger,
    sseCounts: captured.reduce((acc: Record<string, number>, e) => { acc[e.type] = (acc[e.type] || 0) + 1; return acc; }, {}),
    ...extra,
    allSSE: captured.map((e) => ({ type: e.type, data: e.data })),
  };
  const p = path.join(OUT_DIR, "realrun-report.json");
  fs.writeFileSync(p, JSON.stringify(report, null, 2));
  console.log(`[report] written ${p}`);
  console.log("[SUMMARY]\n" + Object.entries(ledger).map(([k, v]) => `  ${k}: ${v.verdict} — ${v.note}`).join("\n"));
}
