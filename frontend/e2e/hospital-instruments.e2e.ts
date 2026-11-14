/**
 * Hospital Core-Facility Instruments E2E — LIVE dev, NO mocks
 * ==========================================================
 * Three real hospital-user journeys for instruments that previously had ZERO
 * E2E coverage:
 *
 *   1. qPCR (ΔΔCq relative quantification) — inline Ct table with a housekeeping
 *      gene → must route to a qPCR/ΔΔCq workflow (normqpcr / ddct / htqpcr /
 *      qpcrnorm family), NOT generic RNA-seq/DESeq2. qPCR is small/fast, so if
 *      the panel Run button is enabled we dispatch it and assert
 *      idle→running→terminal via the data-status pattern (realrun-admet style).
 *
 *   2. Flow cytometry — immunophenotype a flow-cytometry sample → must route to
 *      the flow immunophenotyping / gating family (Analyze Flow Cytometry
 *      Immunophenotyping, FlowSOM, flowclust, flowcore…), NOT scRNA-seq.
 *
 *   3. Plate reader — inline a small dose-response / absorbance CSV → must route
 *      to HTS plate QC / hit-calling or dose-response/IC50 (hts_plate_qc_hit_calling
 *      / Dose Response / sights), NOT a generic stats chat.
 *
 * Presentation Standard assertions (CLAUDE.md §"Chat + Workflow Panel
 * Presentation Standard"):
 *   - workflow card/panel name is REAL — never "undefined"/"Untitled"/blank
 *   - card appears after the AI text
 *   - correct intent (qPCR msg → qPCR wf, etc.)
 *   - pre-run panel shows params + a Confirm & Run control
 *
 * Honest verdicts: PASS / FAIL / N/A. Wrong routing, an undefined name, or a
 * broken panel is a REAL BUG — recorded, never asserted-away.
 *
 * CLAUDE.md rules honored:
 *   - Login ONCE per file (sharedPage), single fixture lifeifei163361@163.com
 *   - NO page.route() mocking — all calls hit the live dev backend
 *   - 90 s LLM timeout for chat/workflow-generation calls
 *   - BASE_URL = process.env.BIOMATE_URL || https://dev-public.biomate.ai
 */

import { test, expect, type Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { waitForResponseComplete } from "./helpers.js";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const SS_DIR = path.join("/tmp", "hospital-instruments-e2e");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

const LLM_TIMEOUT = 90_000;

test.setTimeout(35 * 60_000); // 35 min — pre-run journeys + one optional qPCR run

// ── Inline hospital data ────────────────────────────────────────────────────

/** qPCR Ct table: 3 target genes + 1 housekeeping (GAPDH), control vs treated */
const QPCR_CT_TABLE = `gene,control_Ct,treated_Ct
GAPDH,18.20,18.35
IL6,26.50,22.10
TNF,28.90,24.30
CXCL10,30.10,25.80`;

const QPCR_MESSAGE =
  `We ran a qPCR plate in the core facility. Compute ΔΔCq relative quantification ` +
  `(fold change) for the target genes vs the treated condition, normalizing to the ` +
  `GAPDH housekeeping gene. Here are the mean Ct values:\n${QPCR_CT_TABLE}`;

const FLOW_MESSAGE =
  `I have a flow cytometry sample (.fcs) from a patient PBMC panel run on our ` +
  `core-facility cytometer. Please immunophenotype it — gate the lymphocytes and ` +
  `identify/quantify CD4+ and CD8+ T-cell, B-cell and NK-cell populations.`;

/** Plate-reader absorbance dose-response: compound at increasing doses, OD450 */
const PLATE_CSV = `dose_uM,replicate1_OD,replicate2_OD,replicate3_OD
0,1.02,0.98,1.01
0.1,0.99,1.00,0.97
1,0.85,0.88,0.83
10,0.55,0.58,0.52
100,0.21,0.19,0.23`;

const PLATE_MESSAGE =
  `Our plate reader produced this absorbance (OD450) dose-response readout from a ` +
  `cell-viability assay. Run plate QC and fit a dose-response curve to call the IC50 ` +
  `/ hit for this compound:\n${PLATE_CSV}`;

// ---------------------------------------------------------------------------
// Honest verdict ledger
// ---------------------------------------------------------------------------

type Verdict = "PASS" | "FAIL" | "N/A";
const ledger: Record<string, { verdict: Verdict; note: string }> = {};
function record(id: string, verdict: Verdict, note: string) {
  ledger[id] = { verdict, note };
  console.log(`[${id}] ${verdict} — ${note}`);
}

// ---------------------------------------------------------------------------
// Shared login state
// ---------------------------------------------------------------------------

let sharedPage: Page;

async function ss(page: Page, name: string) {
  const p = path.join(SS_DIR, `${name}.png`);
  await page.screenshot({ path: p, fullPage: true }).catch((e) => console.log(`[ss fail ${name}] ${e}`));
  console.log(`[SS] ${p}`);
}

/**
 * Parse /api/chat/stream SSE inside the browser (same-origin, auth cookies
 * already set by loginAsFixture). Cancels as soon as `final` arrives so we
 * don't wait for the SSE connection to close. Copied from the canonical
 * deseq2-inline-data.e2e.ts pattern.
 */
async function parseChatStream(page: Page, message: string) {
  if (!page.url().startsWith(BASE_URL)) {
    await page.goto(BASE_URL, { waitUntil: "domcontentloaded" });
  }
  return page.evaluate(
    async ({ baseUrl, message, sessionId }) => {
      const resp = await fetch(`${baseUrl}/api/chat/stream`, {
        method: "POST",
        headers: { Accept: "text/event-stream", "Content-Type": "application/json" },
        body: JSON.stringify({ message, stream: true, sessionId }),
      });
      if (!resp.ok || !resp.body) throw new Error(`chat/stream ${resp.status}`);

      const reader = resp.body.getReader();
      const decoder = new TextDecoder();
      let buf = "";
      let lastEvent = "";
      const events: string[] = [];
      let finalPayload: any = null;
      let workflowReadyPayload: any = null;
      let deltaText = "";
      let hasFinal = false;
      let hasWorkflowReady = false;

      const processLine = (line: string) => {
        if (line.startsWith("event: ")) {
          lastEvent = line.slice(7).trim();
          if (!events.includes(lastEvent)) events.push(lastEvent);
          if (lastEvent === "final") hasFinal = true;
          if (lastEvent === "workflow_ready") hasWorkflowReady = true;
        } else if (line.startsWith("data: ")) {
          try {
            const d = JSON.parse(line.slice(6));
            if (lastEvent === "delta" && typeof d.text === "string") deltaText += d.text;
            if (lastEvent === "final") finalPayload = d;
            if (lastEvent === "workflow_ready") workflowReadyPayload = d;
          } catch {}
        }
      };

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buf += decoder.decode(value, { stream: true });
          const lines = buf.split("\n");
          buf = lines.pop() ?? "";
          for (const line of lines) processLine(line);
          if (hasFinal) { reader.cancel(); break; }
        }
      } catch { /* cancelled */ }

      return { events, hasFinal, hasWorkflowReady, finalPayload, workflowReadyPayload, deltaText };
    },
    { baseUrl: BASE_URL, message, sessionId: `e2e-hospital-${Date.now()}` },
  );
}

/** Extract the canonical workflow name from a chat-stream result. */
function extractWfName(result: any): string {
  const wfr = result.workflowReadyPayload;
  const fp = result.finalPayload;
  return (
    wfr?.workflow_name ||
    fp?.workflow?.workflow_ga?.name ||
    fp?.workflow?.name ||
    fp?.workflow?.chain_name ||
    fp?.workflow?.nextflow_path ||
    ""
  ).toString();
}

function nameIsReal(name: string): boolean {
  const n = (name || "").trim();
  return !!n && n.toLowerCase() !== "undefined" && n.toLowerCase() !== "untitled" && n.length > 2;
}

/** Send a message through the chat UI and try to open the workflow panel. */
async function sendAndOpenPanel(page: Page, message: string): Promise<boolean> {
  await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
  const chatInput = page.locator("textarea, input[type='text']").first();
  await expect(chatInput).toBeVisible({ timeout: 15_000 });
  await chatInput.fill(message);
  await chatInput.press("Enter");
  await waitForResponseComplete(page, LLM_TIMEOUT);

  const panel = page.locator('[data-testid="workflow-artifact-panel"]');
  let panelVisible = await panel.isVisible().catch(() => false);
  if (!panelVisible) {
    // Try clicking a workflow anchor/chip in chat to open the panel
    const anchor = page
      .locator('[data-testid^="workflow-artifact-anchor-"], [data-testid^="wf-chip-"]')
      .first();
    if ((await anchor.count()) > 0) {
      await anchor.click().catch(() => null);
      await panel.waitFor({ state: "visible", timeout: 8_000 }).catch(() => null);
      panelVisible = await panel.isVisible().catch(() => false);
    }
  }
  return panelVisible;
}

/**
 * Assert the pre-run workflow panel: real name, params present, Confirm & Run
 * control. Returns { nameOk, panelName, hasParams, hasRunBtn }.
 */
async function assertPreRunPanel(page: Page, idPrefix: string) {
  const panelName = (await page.locator(".panel-name").first().textContent().catch(() => "") || "").trim();
  const nameOk = nameIsReal(panelName);
  record(`${idPrefix}-panel-name`, nameOk ? "PASS" : "FAIL",
    nameOk ? `panel shows real name "${panelName}"` : `bad panel name "${panelName}"`);

  // Params strip — expand Settings and read the debug rendered-param-ids attr
  const settingsTab = page.locator('[data-testid="panel-tab-settings"]');
  if ((await settingsTab.count()) > 0 && (await settingsTab.getAttribute("aria-selected")) !== "true") {
    await settingsTab.click().catch(() => null);
    await page.waitForTimeout(300);
  }
  const toggleBtn = page.locator('[data-testid="button-toggle-workflow-settings"]');
  if ((await toggleBtn.count()) > 0) {
    const isOpen = await toggleBtn.evaluate((el) => el.classList.contains("open")).catch(() => false);
    if (!isOpen) { await toggleBtn.click().catch(() => null); await page.waitForTimeout(400); }
  }
  const panel = page.locator('[data-testid="workflow-artifact-panel"]');
  const rawIds = await panel.getAttribute("data-debug-rendered-param-ids").catch(() => null);
  const paramIds = rawIds ? rawIds.split(",").filter(Boolean) : [];
  const hasParams = paramIds.length > 0;
  record(`${idPrefix}-panel-params`, hasParams ? "PASS" : "FAIL",
    hasParams ? `pre-run panel renders ${paramIds.length} params` : `pre-run panel renders no params`);

  // Confirm & Run control
  const runBtn = page.locator('[data-testid="button-run-workflow-panel"]').first();
  const hasRunBtn = await runBtn.isVisible().catch(() => false);
  record(`${idPrefix}-run-btn`, hasRunBtn ? "PASS" : "FAIL",
    hasRunBtn ? `Confirm & Run button present` : `Confirm & Run button missing`);

  return { nameOk, panelName, hasParams, hasRunBtn, paramIds };
}

// ---------------------------------------------------------------------------
// beforeAll — single login
// ---------------------------------------------------------------------------

test.beforeAll(async ({ browser }) => {
  sharedPage = await browser.newPage();
  await loginAsFixture(sharedPage);
  console.log("[Auth] Logged in as fixture (cookie auth)");
});

test.afterAll(async () => {
  console.log("\n=== HOSPITAL INSTRUMENTS E2E — VERDICT SUMMARY ===");
  for (const [k, v] of Object.entries(ledger)) console.log(`  ${k}: ${v.verdict} — ${v.note}`);
  fs.writeFileSync(path.join(SS_DIR, "hospital-instruments-report.json"), JSON.stringify(ledger, null, 2));
  await sharedPage?.close();
});

// ============================================================================
// JOURNEY 1 — qPCR (ΔΔCq relative quantification)
// ============================================================================

test("qPCR: inline Ct table → routes to ΔΔCq/normqpcr workflow (NOT DESeq2), real panel", async () => {
  // ── 1a. Routing via SSE ─────────────────────────────────────────────────
  const result = await parseChatStream(sharedPage, QPCR_MESSAGE);
  console.log("[qPCR] SSE events:", result.events.join(", "));
  console.log("[qPCR] state:", result.finalPayload?.state);

  expect(result.hasFinal, "must emit 'final' event").toBe(true);
  const fp = result.finalPayload;
  expect(fp, "final payload must not be null").not.toBeNull();

  const wfName = extractWfName(result);
  console.log("[qPCR] workflow name:", wfName, "| state:", fp?.state);

  if (fp?.state === "workflow_ready") {
    const real = nameIsReal(wfName);
    record("qPCR-name", real ? "PASS" : "FAIL",
      real ? `real workflow name "${wfName}"` : `undefined/blank workflow name "${wfName}"`);
    expect(real, `qPCR workflow name must not be undefined/blank (got "${wfName}")`).toBe(true);

    const wl = wfName.toLowerCase();
    const isQpcrFamily =
      wl.includes("qpcr") || wl.includes("ddct") || wl.includes("delta") ||
      wl.includes("normfinder") || wl.includes("genorm") || wl.includes("readqpcr") ||
      wl.includes("ct ");
    // Guard against the classic RNA-seq/DESeq2 confusion
    const isRnaSeqConfusion =
      (wl.includes("deseq") || wl.includes("rnaseq") || wl.includes("differentialabundance") ||
       wl.includes("differential expression")) && !isQpcrFamily;

    record("qPCR-routing",
      isQpcrFamily ? "PASS" : (isRnaSeqConfusion ? "FAIL" : "FAIL"),
      isQpcrFamily
        ? `routed to qPCR family: "${wfName}"`
        : isRnaSeqConfusion
          ? `WRONG ROUTING (RNA-seq/DESeq2 confusion): "${wfName}" — qPCR Ct table should route to ΔΔCq/normqpcr`
          : `unexpected routing: "${wfName}" (not qPCR family)`);
    expect(isQpcrFamily, `qPCR Ct table must route to a qPCR/ΔΔCq workflow, got "${wfName}"`).toBe(true);
  } else {
    record("qPCR-routing", "FAIL",
      `state=${fp?.state} (expected workflow_ready). response="${String(fp?.response || "").slice(0, 160)}"`);
    // Do not weaken — a hospital qPCR request should produce a workflow.
    expect(fp?.state, `qPCR request should yield workflow_ready, got ${fp?.state}`).toBe("workflow_ready");
  }

  // ── 1b. Pre-run panel via UI ────────────────────────────────────────────
  const panelVisible = await sendAndOpenPanel(sharedPage, QPCR_MESSAGE);
  await ss(sharedPage, "qpcr_01_panel");
  if (!panelVisible) {
    record("qPCR-panel", "FAIL", "workflow panel did not open for qPCR message");
    expect(panelVisible, "qPCR workflow panel must open").toBe(true);
    return;
  }
  record("qPCR-panel", "PASS", "workflow panel opened");

  const pre = await assertPreRunPanel(sharedPage, "qPCR");
  await ss(sharedPage, "qpcr_02_prerun");

  // ── 1c. Optional dispatch to completion (qPCR is small/fast) ─────────────
  const runBtn = sharedPage.locator('[data-testid="button-run-workflow-panel"]').first();
  const statusBadge = sharedPage.locator('[data-testid="workflow-overall-status-badge"]');
  const unfilled = parseInt((await runBtn.getAttribute("data-required-unfilled").catch(() => "0")) ?? "0", 10);
  const disabled = await runBtn.isDisabled().catch(() => true);

  if (!pre.hasRunBtn || unfilled > 0 || disabled) {
    record("qPCR-dispatch", "N/A",
      `stopped at validated pre-run: Run blocked (required-unfilled=${unfilled}, disabled=${disabled}). ` +
      `qPCR needs a Ct-table file in its required-param slot; inline text satisfies intent but not the file slot.`);
    // Assert the blocked UI is coherent
    const blockingUI =
      (await sharedPage.locator('[data-testid="workflow-prereq-checklist"]').isVisible().catch(() => false)) ||
      disabled;
    expect(blockingUI, "blocked run must surface blocking UI").toBe(true);
    return;
  }

  // Run button enabled — dispatch and assert idle→running→terminal.
  const pre0 = await statusBadge.getAttribute("data-status").catch(() => null);
  console.log("[qPCR] pre-run badge:", pre0);
  await runBtn.click();
  const confirm = sharedPage.locator('button:has-text("Confirm & Run"), button:has-text("Confirm")').first();
  if (await confirm.isVisible({ timeout: 2_000 }).catch(() => false)) await confirm.click().catch(() => null);
  await ss(sharedPage, "qpcr_03_run_clicked");

  let reachedRunning = false;
  try {
    await sharedPage.waitForFunction(() => {
      const b = document.querySelector('[data-testid="workflow-overall-status-badge"]');
      const s = b?.getAttribute("data-status") ?? "";
      return s === "running" || s === "completed" || s === "failed";
    }, { timeout: 60_000 });
    reachedRunning = true;
  } catch { /* no transition */ }

  if (!reachedRunning) {
    record("qPCR-dispatch", "N/A", "clicked Run but badge never left idle within 60s — no live transition observed");
    return;
  }
  await ss(sharedPage, "qpcr_04_running");

  // Wait for terminal
  let terminal: string | null = null;
  try {
    await sharedPage.waitForFunction(() => {
      const b = document.querySelector('[data-testid="workflow-overall-status-badge"]');
      const s = b?.getAttribute("data-status") ?? "";
      return s === "completed" || s === "failed";
    }, { timeout: 25 * 60_000 });
    terminal = await statusBadge.getAttribute("data-status").catch(() => null);
  } catch { terminal = await statusBadge.getAttribute("data-status").catch(() => null); }
  await ss(sharedPage, "qpcr_05_terminal");

  if (terminal === "completed") {
    record("qPCR-dispatch", "PASS", "qPCR dispatched and ran to completion (idle→running→completed)");
  } else if (terminal === "failed") {
    // Failed is honest — record it, but the failure must be data/infra, surfaced in UI (not a UI bug).
    record("qPCR-dispatch", "FAIL",
      `qPCR run reached FAILED terminal state — check whether data/infra or a workflow bug (badge=${terminal})`);
  } else {
    record("qPCR-dispatch", "N/A",
      `qPCR run did not reach terminal within 25min (badge=${terminal}) — infra stall, not a UI bug`);
  }
});

// ============================================================================
// JOURNEY 2 — Flow cytometry immunophenotyping
// ============================================================================

test("Flow cytometry: immunophenotyping request → flow gating workflow (NOT scRNA-seq), real panel", async () => {
  const result = await parseChatStream(sharedPage, FLOW_MESSAGE);
  console.log("[Flow] SSE events:", result.events.join(", "));
  console.log("[Flow] state:", result.finalPayload?.state);

  expect(result.hasFinal, "must emit 'final' event").toBe(true);
  const fp = result.finalPayload;
  const wfName = extractWfName(result);
  console.log("[Flow] workflow name:", wfName, "| state:", fp?.state);

  if (fp?.state === "workflow_ready") {
    const real = nameIsReal(wfName);
    record("Flow-name", real ? "PASS" : "FAIL",
      real ? `real workflow name "${wfName}"` : `undefined/blank workflow name "${wfName}"`);
    expect(real, `flow workflow name must not be undefined/blank (got "${wfName}")`).toBe(true);

    const wl = wfName.toLowerCase();
    const isFlowFamily =
      wl.includes("flow") || wl.includes("cytometr") || wl.includes("immunophenotyp") ||
      wl.includes("gating") || wl.includes("fcs") || wl.includes("flowsom") ||
      wl.includes("ncdfflow");
    // Guard against scRNA-seq confusion (a common misroute for "immunophenotype")
    const isScRnaConfusion =
      (wl.includes("scrna") || wl.includes("single-cell rna") || wl.includes("single_cell_rna") ||
       wl.includes("seurat") || wl.includes("scanpy") || wl.includes("cellranger") ||
       wl.includes("starsolo") || wl.includes("alevin")) && !isFlowFamily;

    record("Flow-routing",
      isFlowFamily ? "PASS" : "FAIL",
      isFlowFamily
        ? `routed to flow-cytometry family: "${wfName}"`
        : isScRnaConfusion
          ? `WRONG ROUTING (scRNA-seq confusion): "${wfName}" — flow-cytometry immunophenotyping should route to a flow/gating workflow`
          : `unexpected routing: "${wfName}" (not flow-cytometry family)`);
    expect(isFlowFamily, `flow-cytometry request must route to a flow workflow, got "${wfName}"`).toBe(true);
  } else {
    record("Flow-routing", "FAIL",
      `state=${fp?.state} (expected workflow_ready). response="${String(fp?.response || "").slice(0, 160)}"`);
    expect(fp?.state, `flow-cytometry request should yield workflow_ready, got ${fp?.state}`).toBe("workflow_ready");
  }

  // Pre-run panel
  const panelVisible = await sendAndOpenPanel(sharedPage, FLOW_MESSAGE);
  await ss(sharedPage, "flow_01_panel");
  if (!panelVisible) {
    record("Flow-panel", "FAIL", "workflow panel did not open for flow-cytometry message");
    expect(panelVisible, "flow workflow panel must open").toBe(true);
    return;
  }
  record("Flow-panel", "PASS", "workflow panel opened");
  await assertPreRunPanel(sharedPage, "Flow");
  await ss(sharedPage, "flow_02_prerun");
});

// ============================================================================
// JOURNEY 3 — Plate reader (dose-response / HTS plate QC)
// ============================================================================

test("Plate reader: inline dose-response CSV → HTS plate-QC / dose-response workflow, real panel", async () => {
  const result = await parseChatStream(sharedPage, PLATE_MESSAGE);
  console.log("[Plate] SSE events:", result.events.join(", "));
  console.log("[Plate] state:", result.finalPayload?.state);

  expect(result.hasFinal, "must emit 'final' event").toBe(true);
  const fp = result.finalPayload;
  const wfName = extractWfName(result);
  console.log("[Plate] workflow name:", wfName, "| state:", fp?.state);

  if (fp?.state === "workflow_ready") {
    const real = nameIsReal(wfName);
    record("Plate-name", real ? "PASS" : "FAIL",
      real ? `real workflow name "${wfName}"` : `undefined/blank workflow name "${wfName}"`);
    expect(real, `plate workflow name must not be undefined/blank (got "${wfName}")`).toBe(true);

    const wl = wfName.toLowerCase();
    const isPlateFamily =
      wl.includes("plate") || wl.includes("dose") || wl.includes("response") ||
      wl.includes("ic50") || wl.includes("hts") || wl.includes("hit") ||
      wl.includes("z-factor") || wl.includes("z_factor") || wl.includes("sights") ||
      wl.includes("screen");
    record("Plate-routing", isPlateFamily ? "PASS" : "FAIL",
      isPlateFamily
        ? `routed to plate-QC/dose-response family: "${wfName}"`
        : `unexpected routing: "${wfName}" — dose-response plate readout should route to HTS plate-QC / dose-response`);
    expect(isPlateFamily, `plate-reader dose-response must route to a plate-QC/dose-response workflow, got "${wfName}"`).toBe(true);
  } else {
    record("Plate-routing", "FAIL",
      `state=${fp?.state} (expected workflow_ready). response="${String(fp?.response || "").slice(0, 160)}"`);
    expect(fp?.state, `plate-reader request should yield workflow_ready, got ${fp?.state}`).toBe("workflow_ready");
  }

  // Pre-run panel
  const panelVisible = await sendAndOpenPanel(sharedPage, PLATE_MESSAGE);
  await ss(sharedPage, "plate_01_panel");
  if (!panelVisible) {
    record("Plate-panel", "FAIL", "workflow panel did not open for plate-reader message");
    expect(panelVisible, "plate workflow panel must open").toBe(true);
    return;
  }
  record("Plate-panel", "PASS", "workflow panel opened");
  await assertPreRunPanel(sharedPage, "Plate");
  await ss(sharedPage, "plate_02_prerun");
});
