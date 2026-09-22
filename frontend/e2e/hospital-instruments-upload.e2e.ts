/**
 * Hospital Core-Facility Instruments — UPLOAD journeys E2E — LIVE dev, NO mocks
 * =============================================================================
 * Companion to hospital-instruments.e2e.ts. That file covers the *inline-data*
 * path (paste a Ct table / dose-response CSV into the chat). This file covers
 * the *upload* path: a hospital user who UPLOADS a data file (and a folder)
 * from their instrument instead of pasting the numbers.
 *
 * It also end-to-end validates the folder-upload feature shipped in PR #228
 * (frontend/client/src/lib/folder-drop.ts + the webkitdirectory folder input
 * `chat-attach-folder-input` in chat-input.tsx). NB: the standalone FileUpload
 * panel (`file-upload-folder-input`) is NOT rendered in the running app today
 * — the ONLY live folder-upload UI is the composer's webkitdirectory input, so
 * the folder journey drives that.
 *
 * Journeys:
 *   1. qPCR upload    — write a tiny Ct-values CSV to a temp path, upload it via
 *                       the composer file input, assert it shows as an
 *                       attachment, then ask for ΔΔCq → assert routing to the
 *                       qPCR/ΔΔCq family (NOT DESeq2), real pre-run panel.
 *   2. Plate upload   — tiny OD450 dose-response CSV → plate-QC / IC50 routing.
 *   3. Folder upload  — temp folder with 3 small files → composer folder input
 *                       (webkitdirectory, multiple setInputFiles) → assert all
 *                       files attach AND stage server-side.
 *
 * Honesty / non-weakening (CLAUDE.md):
 *   - UPLOAD + attachment + server-staging steps run and are asserted FIRST and
 *     SEPARATELY — they do NOT depend on /api/chat/stream, so they verify the
 *     upload path even if dev's chat-stream is down.
 *   - Routing steps DO depend on chat-stream. If chat-stream is down they FAIL
 *     honestly (that's a real signal), they are never asserted-away.
 *   - workflow name must be REAL — never "undefined"/"untitled"/blank.
 *   - correct routing for the data type (qPCR-family, plate-family); guarded
 *     against the DESeq2 / generic-stats misroute.
 *
 * CLAUDE.md rules honored:
 *   - Login ONCE per file (sharedPage), single fixture lifeifei163361@163.com
 *   - NO page.route() mocking — every call hits live dev
 *   - 90 s LLM timeout for chat/workflow-generation calls
 *   - BASE_URL = process.env.BIOMATE_URL || https://dev-public.biomate.ai
 */

import { test, expect, type Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import * as os from "os";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { waitForResponseComplete } from "./helpers.js";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const SS_DIR = path.join("/tmp", "hospital-instruments-upload-e2e");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

const LLM_TIMEOUT = 90_000;

test.setTimeout(20 * 60_000);

// ── Sample instrument data (written to real temp files, then uploaded) ──────

/**
 * qPCR Ct table for the GENERIC base-R 2^-ddCt path:
 *   - first column = gene (includes the GAPDH housekeeping gene for normalization)
 *   - remaining columns = per-sample Ct values; each column name carries
 *     'control' or 'treated' so the workflow's auto-grouping picks up 2 groups
 *     of 2 replicates each (4 samples total).
 */
const QPCR_CT_CSV = `gene,control_1_Ct,control_2_Ct,treated_1_Ct,treated_2_Ct
GAPDH,18.20,18.31,18.35,18.28
IL6,26.50,26.62,22.10,22.31
TNF,28.90,29.05,24.30,24.18
CXCL10,30.10,30.22,25.80,25.61
`;

const QPCR_MESSAGE =
  `I uploaded our core-facility qPCR export (Ct values, control vs treated). ` +
  `Analyze these qPCR results with ΔΔCq normalization — compute fold change for ` +
  `the target genes normalizing to the GAPDH housekeeping gene.`;

/** Plate-reader absorbance dose-response: compound at increasing doses, OD450 */
const PLATE_OD_CSV = `dose_uM,replicate1_OD450,replicate2_OD450,replicate3_OD450
0,1.02,0.98,1.01
0.1,0.99,1.00,0.97
1,0.85,0.88,0.83
10,0.55,0.58,0.52
100,0.21,0.19,0.23
`;

const PLATE_MESSAGE =
  `I uploaded our plate-reader OD450 dose-response export from a cell-viability ` +
  `assay. Run plate QC and fit a dose-response curve to call the IC50 / hit for ` +
  `this compound.`;

// ---------------------------------------------------------------------------
// Temp file helpers
// ---------------------------------------------------------------------------

const TMP_ROOT = fs.mkdtempSync(path.join(os.tmpdir(), "hosp-upload-"));

function writeTempFile(name: string, contents: string): string {
  const p = path.join(TMP_ROOT, name);
  fs.writeFileSync(p, contents);
  return p;
}

/** Create a temp folder with N small files; return { dir, filePaths, names }. */
function makeTempFolder(folderName: string, files: Record<string, string>) {
  const dir = path.join(TMP_ROOT, folderName);
  fs.mkdirSync(dir, { recursive: true });
  const filePaths: string[] = [];
  const names: string[] = [];
  for (const [name, contents] of Object.entries(files)) {
    const p = path.join(dir, name);
    fs.writeFileSync(p, contents);
    filePaths.push(p);
    names.push(name);
  }
  return { dir, filePaths, names };
}

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

function nameIsReal(name: string): boolean {
  const n = (name || "").trim();
  return !!n && n.toLowerCase() !== "undefined" && n.toLowerCase() !== "untitled" && n.length > 2;
}

// ---------------------------------------------------------------------------
// Composer helpers
// ---------------------------------------------------------------------------

/**
 * Open a FRESH chat composer on the landing page and return the input locator.
 * Always navigates to `/` (rather than reusing an in-conversation composer):
 * the landing composer reliably renders both hidden inputs
 * (chat-attach-file-input / chat-attach-folder-input), whereas an
 * in-conversation view left over from a prior test can render a different
 * composer state.
 */
async function openComposer(page: Page) {
  await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
  const chatInput = page.locator('[data-testid="chat-input"], textarea').first();
  await expect(chatInput).toBeVisible({ timeout: 20_000 });
  return chatInput;
}

/**
 * Attach a single file to the composer via the hidden file input
 * (chat-attach-file-input). Playwright can setInputFiles on hidden inputs.
 * Asserts the attachment chip appears with the filename. Returns true on
 * success. This does NOT depend on /api/chat/stream.
 */
async function attachFileToComposer(page: Page, filePath: string): Promise<boolean> {
  await openComposer(page);
  const fileInput = composerFileInput(page);
  await fileInput.waitFor({ state: "attached", timeout: 10_000 });
  await fileInput.setInputFiles(filePath);
  return attachmentChipVisible(page, path.basename(filePath), 10_000);
}

/**
 * The composer's hidden single-file input. Prefers the stable testid
 * (chat-attach-file-input, present once this branch ships) and falls back to
 * the structural selector (a file input WITHOUT webkitdirectory) so the test
 * also runs against the currently-deployed dev bundle that predates the testid.
 */
function composerFileInput(page: Page) {
  return page.locator(
    '[data-testid="chat-attach-file-input"], ' +
      'input[type="file"]:not([webkitdirectory]):not([data-testid="file-upload-folder-input"])',
  ).first();
}

/** The composer's hidden webkitdirectory folder input, with structural fallback. */
function composerFolderInput(page: Page) {
  return page.locator(
    '[data-testid="chat-attach-folder-input"], input[type="file"][webkitdirectory]',
  ).first();
}

/**
 * True when a file with `fname` is shown as a composer attachment. Prefers the
 * stable testid+data-filename chip; falls back to matching the visible file
 * name text inside the attachment strip on the deployed bundle.
 */
async function attachmentChipVisible(page: Page, fname: string, timeout = 10_000): Promise<boolean> {
  const byTestId = page.locator(`[data-testid="composer-attached-file"][data-filename="${fname}"]`);
  const byText = page.locator(`span:has-text("${fname}")`);
  return Promise.race([
    byTestId.waitFor({ state: "visible", timeout }).then(() => true).catch(() => false),
    byText.first().waitFor({ state: "visible", timeout }).then(() => true).catch(() => false),
  ]);
}

/**
 * Directly stage a file server-side via the real upload endpoint
 * (/api/datasets/upload — the same endpoint the composer calls on send for
 * files ≤100 MiB). Proves the upload/staging path independent of the UI and of
 * chat-stream. Returns the parsed response (dataset_id / galaxy_dataset_id /
 * s3_uri) or throws.
 */
async function stageFileServerSide(page: Page, filePath: string) {
  const buf = fs.readFileSync(filePath);
  const name = path.basename(filePath);
  const resp = await page.request.post(`${BASE_URL}/api/datasets/upload`, {
    multipart: {
      file: { name, mimeType: "text/csv", buffer: buf },
      description: "e2e hospital-upload journey",
    },
    timeout: 120_000,
  });
  if (!resp.ok()) throw new Error(`upload ${name} → HTTP ${resp.status()}: ${await resp.text().catch(() => "")}`);
  return resp.json();
}

/**
 * Parse /api/chat/stream SSE inside the browser (same-origin, auth cookies set
 * by loginAsFixture). Cancels as soon as `final` arrives. The message carries
 * the uploaded-dataset context line the composer would append on send, so the
 * router sees a real uploaded file, not just prose.
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
      let hasFinal = false;

      const processLine = (line: string) => {
        if (line.startsWith("event: ")) {
          lastEvent = line.slice(7).trim();
          if (!events.includes(lastEvent)) events.push(lastEvent);
          if (lastEvent === "final") hasFinal = true;
        } else if (line.startsWith("data: ")) {
          try {
            const d = JSON.parse(line.slice(6));
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

      return { events, hasFinal, finalPayload, workflowReadyPayload };
    },
    { baseUrl: BASE_URL, message, sessionId: `e2e-hosp-upload-${Date.now()}` },
  );
}

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

/** Build the message the composer would send after a successful upload. */
function withUploadedContext(message: string, staged: any, fileName: string): string {
  const dsId = staged?.dataset_id ?? "n/a";
  const gxId = staged?.galaxy_dataset_id ? `, galaxy_dataset_id=${staged.galaxy_dataset_id}` : "";
  const s3 = staged?.s3_uri ? `, s3_uri=${staged.s3_uri}` : "";
  return (
    `${message}\n\n[Attached files: ${fileName}]\n` +
    `[Uploaded datasets: ${fileName}: dataset_id=${dsId}${gxId}${s3}]`
  );
}

/** Send a message through the chat UI and try to open the workflow panel. */
async function sendAndOpenPanel(page: Page, message: string): Promise<boolean> {
  await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
  const chatInput = page.locator('[data-testid="chat-input"], textarea').first();
  await expect(chatInput).toBeVisible({ timeout: 15_000 });
  await chatInput.fill(message);
  await chatInput.press("Enter");
  await waitForResponseComplete(page, LLM_TIMEOUT);

  const panel = page.locator('[data-testid="workflow-artifact-panel"]');
  let panelVisible = await panel.isVisible().catch(() => false);
  if (!panelVisible) {
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

/** Assert the pre-run workflow panel: real name + Confirm & Run control. */
async function assertPreRunPanel(page: Page, idPrefix: string) {
  const panelName = (await page.locator(".panel-name").first().textContent().catch(() => "") || "").trim();
  const nameOk = nameIsReal(panelName);
  record(`${idPrefix}-panel-name`, nameOk ? "PASS" : "FAIL",
    nameOk ? `panel shows real name "${panelName}"` : `bad panel name "${panelName}"`);

  const runBtn = page.locator('[data-testid="button-run-workflow-panel"]').first();
  const hasRunBtn = await runBtn.isVisible().catch(() => false);
  record(`${idPrefix}-run-btn`, hasRunBtn ? "PASS" : "FAIL",
    hasRunBtn ? `Confirm & Run button present` : `Confirm & Run button missing`);

  return { nameOk, panelName, hasRunBtn };
}

// ---------------------------------------------------------------------------
// beforeAll / afterAll
// ---------------------------------------------------------------------------

test.beforeAll(async ({ browser }) => {
  sharedPage = await browser.newPage();
  await loginAsFixture(sharedPage);
  console.log("[Auth] Logged in as fixture (cookie auth)");
});

test.afterAll(async () => {
  console.log("\n=== HOSPITAL INSTRUMENTS UPLOAD E2E — VERDICT SUMMARY ===");
  for (const [k, v] of Object.entries(ledger)) console.log(`  ${k}: ${v.verdict} — ${v.note}`);
  fs.writeFileSync(path.join(SS_DIR, "hospital-instruments-upload-report.json"), JSON.stringify(ledger, null, 2));
  try { fs.rmSync(TMP_ROOT, { recursive: true, force: true }); } catch {}
  await sharedPage?.close();
});

// ============================================================================
// JOURNEY 1 — qPCR file UPLOAD → ΔΔCq routing
// ============================================================================

test("qPCR upload: Ct CSV uploads + attaches + stages, then routes to ΔΔCq family (NOT DESeq2)", async () => {
  const filePath = writeTempFile("qpcr_ct_export.csv", QPCR_CT_CSV);

  // ── 1a. Attach in the composer (UI). Does NOT need chat-stream. ──────────
  const attached = await attachFileToComposer(sharedPage, filePath);
  await ss(sharedPage, "qpcr_01_attached");
  record("qPCR-upload-attach", attached ? "PASS" : "FAIL",
    attached ? "uploaded Ct CSV shows as a composer attachment chip" : "attachment chip did not appear after setInputFiles");
  expect(attached, "uploaded qPCR CSV must appear as a composer attachment").toBe(true);

  // ── 1b. Server-side staging (real upload endpoint). No chat-stream. ──────
  const staged = await stageFileServerSide(sharedPage, filePath);
  const stagedOk = !!(staged?.dataset_id || staged?.galaxy_dataset_id || staged?.s3_uri);
  record("qPCR-upload-stage", stagedOk ? "PASS" : "FAIL",
    stagedOk ? `staged: dataset_id=${staged?.dataset_id ?? "?"} galaxy=${staged?.galaxy_dataset_id ?? "?"}`
             : `upload endpoint returned no dataset ref: ${JSON.stringify(staged).slice(0, 160)}`);
  expect(stagedOk, "qPCR upload must return a server-side dataset reference").toBe(true);

  // ── 1c. Routing via chat-stream (uploaded file bound in context). ───────
  const msg = withUploadedContext(QPCR_MESSAGE, staged, "qpcr_ct_export.csv");
  const result = await parseChatStream(sharedPage, msg);
  console.log("[qPCR] SSE events:", result.events.join(", "), "| state:", result.finalPayload?.state);
  expect(result.hasFinal, "must emit 'final' event").toBe(true);
  const fp = result.finalPayload;
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
    const isRnaSeqConfusion =
      (wl.includes("deseq") || wl.includes("rnaseq") || wl.includes("differentialabundance") ||
       wl.includes("differential expression")) && !isQpcrFamily;
    record("qPCR-routing", isQpcrFamily ? "PASS" : "FAIL",
      isQpcrFamily
        ? `routed to qPCR family: "${wfName}"`
        : isRnaSeqConfusion
          ? `WRONG ROUTING (RNA-seq/DESeq2 confusion): "${wfName}" — uploaded Ct CSV should route to ΔΔCq/normqpcr`
          : `unexpected routing: "${wfName}" (not qPCR family)`);
    expect(isQpcrFamily, `uploaded qPCR Ct CSV must route to a qPCR/ΔΔCq workflow, got "${wfName}"`).toBe(true);
  } else {
    record("qPCR-routing", "FAIL",
      `state=${fp?.state} (expected workflow_ready). response="${String(fp?.response || "").slice(0, 160)}"`);
    expect(fp?.state, `qPCR upload request should yield workflow_ready, got ${fp?.state}`).toBe("workflow_ready");
  }

  // ── 1d. Pre-run panel via UI ────────────────────────────────────────────
  const panelVisible = await sendAndOpenPanel(sharedPage, msg);
  await ss(sharedPage, "qpcr_02_panel");
  if (!panelVisible) {
    record("qPCR-panel", "FAIL", "workflow panel did not open for uploaded qPCR message");
    expect(panelVisible, "qPCR workflow panel must open").toBe(true);
    return;
  }
  record("qPCR-panel", "PASS", "workflow panel opened");
  const preRun = await assertPreRunPanel(sharedPage, "qPCR");
  await ss(sharedPage, "qpcr_03_prerun");

  // ── 1e. DISPATCH the workflow → run to a terminal state ─────────────────
  //   The inline-data path fails at Nextflow launch (no file). Only an UPLOADED
  //   Ct table exercises the generalized base-R 2^-ddCt path end-to-end. So we
  //   actually LAUNCH the run here and assert it reaches a terminal state.
  //   COMPLETED = the generalization works on a real uploaded Ct table (PASS).
  //   FAILED    = honest signal; we surface the panel/SSE error, do NOT weaken.
  if (!preRun.hasRunBtn) {
    record("qPCR-dispatch", "FAIL", "Confirm & Run button not present — cannot dispatch");
    expect(preRun.hasRunBtn, "must have a run button to dispatch the qPCR workflow").toBe(true);
    return;
  }

  const runBtn = sharedPage.locator('[data-testid="button-run-workflow-panel"]').last();
  await runBtn.click();
  console.log("[qPCR dispatch] Confirm & Run clicked");
  record("qPCR-dispatch-click", "PASS", "Confirm & Run clicked to dispatch qPCR run");

  // Live idle→running transition on the overall status badge (or action bar).
  let ranToRunning = false;
  try {
    await sharedPage.waitForFunction(() => {
      const b = document.querySelector('[data-testid="workflow-overall-status-badge"]');
      const bar = document.querySelector('[data-testid="panel-action-bar"]');
      return b?.getAttribute("data-status") === "running" ||
             bar?.getAttribute("data-status") === "running";
    }, { timeout: 120_000 });
    ranToRunning = true;
  } catch (e) {
    console.log(`[qPCR dispatch] no idle→running within 120s: ${String(e).slice(0, 160)}`);
  }
  record("qPCR-dispatch-running", ranToRunning ? "PASS" : "FAIL",
    ranToRunning ? "overall badge/action-bar flipped idle→running via SSE"
                 : "run never reached running within 120s");
  await ss(sharedPage, "qpcr_04_running");

  // Discover the newest active run id (same pattern as realrun-admet.e2e.ts).
  let RID: string | null = null;
  const since = Date.now() - 6 * 60 * 1000;
  for (let i = 0; i < 25 && !RID; i++) {
    const ids = await sharedPage.evaluate(async ({ base, since }) => {
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
          status: pick.status,
          name: run.workflowName ?? run?.workflowDefinition?.name ?? "",
        };
      } catch { return null; }
    }, { base: BASE_URL, since });
    if (ids?.execId) {
      RID = ids.execId;
      console.log(`[qPCR dispatch] run RID=${RID} status=${ids.status} name="${ids.name}"`);
    } else {
      await sharedPage.waitForTimeout(3000);
    }
  }
  expect(RID, "must resolve a run id for the dispatched qPCR run").toBeTruthy();

  // Poll to a terminal state (up to ~15 min for a small Ct-table run).
  const deadline = Date.now() + 15 * 60 * 1000;
  let terminal: string | null = null;
  let lastExec: string | null = null;
  while (Date.now() < deadline) {
    const snap = await sharedPage.evaluate(async ({ base, rid }) => {
      const out: any = {};
      try {
        const r = await fetch(`${base}/api/workflows/runs/${rid}`, { credentials: "include" });
        if (r.ok) { const j = await r.json(); out.exec = (j?.execution?.status ?? j?.status ?? null); out.err = j?.execution?.error ?? j?.error ?? null; }
      } catch { /* */ }
      try {
        const s = await fetch(`${base}/api/workflows/runs/${rid}/status`, { credentials: "include" });
        if (s.ok) { const j = await s.json(); out.statusEp = j?.status ?? null; }
      } catch { /* */ }
      return out;
    }, { base: BASE_URL, rid: RID });
    lastExec = snap.exec ?? lastExec;
    const combined = (snap.exec || snap.statusEp || "").toLowerCase();
    if (["completed", "failed", "error"].includes(combined)) {
      terminal = combined;
      (globalThis as any).__qpcrRunError = snap.err;
      console.log(`[qPCR dispatch] terminal: exec=${snap.exec} statusEp=${snap.statusEp} err=${String(snap.err || "").slice(0, 300)}`);
      break;
    }
    console.log(`[qPCR dispatch] exec=${snap.exec} statusEp=${snap.statusEp} (${Math.round((deadline - Date.now()) / 60000)}m left)`);
    await sharedPage.waitForTimeout(15_000);
  }
  await ss(sharedPage, "qpcr_05_terminal");

  const runError = (globalThis as any).__qpcrRunError;
  if (terminal === "completed") {
    record("qPCR-dispatch-terminal", "PASS",
      "uploaded Ct table ran the generalized normqpcr workflow to COMPLETED (base-R 2^-ddCt path validated end-to-end)");
    // Honest terminal assertion: the uploaded Ct table must reach COMPLETED.
    expect(terminal, "uploaded qPCR Ct table must run the generalized normqpcr workflow to COMPLETED").toBe("completed");
  } else if (terminal === "failed" || terminal === "error") {
    record("qPCR-dispatch-terminal", "FAIL",
      `uploaded Ct table run FAILED — generalized normqpcr path did not complete. error="${String(runError || "(none surfaced)").slice(0, 400)}"`);
    console.log(`[qPCR dispatch][FAILURE] real error: ${String(runError || "(none)").slice(0, 600)}`);
    // Do NOT weaken: a real failure is the honest signal. Assert COMPLETED so
    // the run outcome is reflected truthfully in the test result.
    expect(terminal, `uploaded qPCR Ct table run must reach COMPLETED, got ${terminal}. error=${String(runError || "").slice(0, 200)}`).toBe("completed");
  } else {
    record("qPCR-dispatch-terminal", "FAIL",
      `dispatched qPCR run did not reach a terminal state within 15min (last exec=${lastExec}) — INFRA stall`);
    expect(terminal, `dispatched qPCR run must reach a terminal state (last exec=${lastExec})`).toBeTruthy();
  }
});

// ============================================================================
// JOURNEY 2 — Plate-reader file UPLOAD → dose-response / plate-QC routing
// ============================================================================

test("Plate upload: OD450 dose-response CSV uploads + attaches + stages, then routes to plate-QC/IC50", async () => {
  const filePath = writeTempFile("plate_od450_export.csv", PLATE_OD_CSV);

  // ── 2a. Attach in the composer (UI). ────────────────────────────────────
  const attached = await attachFileToComposer(sharedPage, filePath);
  await ss(sharedPage, "plate_01_attached");
  record("Plate-upload-attach", attached ? "PASS" : "FAIL",
    attached ? "uploaded OD450 CSV shows as a composer attachment chip" : "attachment chip did not appear after setInputFiles");
  expect(attached, "uploaded plate CSV must appear as a composer attachment").toBe(true);

  // ── 2b. Server-side staging. ────────────────────────────────────────────
  const staged = await stageFileServerSide(sharedPage, filePath);
  const stagedOk = !!(staged?.dataset_id || staged?.galaxy_dataset_id || staged?.s3_uri);
  record("Plate-upload-stage", stagedOk ? "PASS" : "FAIL",
    stagedOk ? `staged: dataset_id=${staged?.dataset_id ?? "?"} galaxy=${staged?.galaxy_dataset_id ?? "?"}`
             : `upload endpoint returned no dataset ref: ${JSON.stringify(staged).slice(0, 160)}`);
  expect(stagedOk, "plate upload must return a server-side dataset reference").toBe(true);

  // ── 2c. Routing via chat-stream. ────────────────────────────────────────
  const msg = withUploadedContext(PLATE_MESSAGE, staged, "plate_od450_export.csv");
  const result = await parseChatStream(sharedPage, msg);
  console.log("[Plate] SSE events:", result.events.join(", "), "| state:", result.finalPayload?.state);
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
        : `unexpected routing: "${wfName}" — uploaded dose-response readout should route to HTS plate-QC / dose-response`);
    expect(isPlateFamily, `uploaded plate dose-response must route to a plate-QC/dose-response workflow, got "${wfName}"`).toBe(true);
  } else {
    record("Plate-routing", "FAIL",
      `state=${fp?.state} (expected workflow_ready). response="${String(fp?.response || "").slice(0, 160)}"`);
    expect(fp?.state, `plate upload request should yield workflow_ready, got ${fp?.state}`).toBe("workflow_ready");
  }

  // ── 2d. Pre-run panel via UI ────────────────────────────────────────────
  const panelVisible = await sendAndOpenPanel(sharedPage, msg);
  await ss(sharedPage, "plate_02_panel");
  if (!panelVisible) {
    record("Plate-panel", "FAIL", "workflow panel did not open for uploaded plate message");
    expect(panelVisible, "plate workflow panel must open").toBe(true);
    return;
  }
  record("Plate-panel", "PASS", "workflow panel opened");
  await assertPreRunPanel(sharedPage, "Plate");
  await ss(sharedPage, "plate_03_prerun");
});

// ============================================================================
// JOURNEY 3 — FOLDER upload (validates PR #228 folder-drop feature end-to-end)
// ============================================================================

test("Folder upload: multi-file folder attaches via webkitdirectory input AND stages server-side", async () => {
  // A tiny run folder like a plate reader / sequencer might drop.
  const { dir, filePaths, names } = makeTempFolder("run_folder", {
    "well_A1.csv": "dose_uM,OD450\n0,1.01\n10,0.55\n",
    "well_A2.csv": "dose_uM,OD450\n0,0.99\n10,0.58\n",
    "run_metadata.txt": "instrument=PlateReader-X\noperator=core-facility\n",
  });

  // ── 3a. Attach the whole folder via the composer webkitdirectory input. ─
  //   A webkitdirectory input takes a DIRECTORY path; Playwright expands it to
  //   every file inside — exactly what the browser does when a user picks a
  //   folder. This drives the same code path as the "Select a folder" button.
  await openComposer(sharedPage);
  const folderInput = composerFolderInput(sharedPage);
  await folderInput.waitFor({ state: "attached", timeout: 10_000 });
  await folderInput.setInputFiles(dir);
  await ss(sharedPage, "folder_01_attached");

  // Every file in the folder should surface as its own attachment chip.
  const attachedNames: string[] = [];
  for (const n of names) {
    if (await attachmentChipVisible(sharedPage, n, 10_000)) attachedNames.push(n);
  }
  const allAttached = attachedNames.length === names.length;
  record("Folder-upload-attach", allAttached ? "PASS" : "FAIL",
    allAttached
      ? `all ${names.length} folder files attached: ${attachedNames.join(", ")}`
      : `only ${attachedNames.length}/${names.length} folder files attached (${attachedNames.join(", ")})`);
  expect(allAttached, `all folder files must attach via webkitdirectory input (got ${attachedNames.length}/${names.length})`).toBe(true);

  // ── 3b. Each folder file stages server-side (the real upload path). ─────
  let stagedCount = 0;
  for (const p of filePaths) {
    try {
      const staged = await stageFileServerSide(sharedPage, p);
      if (staged?.dataset_id || staged?.galaxy_dataset_id || staged?.s3_uri) stagedCount++;
    } catch (e) {
      console.log(`[Folder] stage failed for ${path.basename(p)}: ${e}`);
    }
  }
  const allStaged = stagedCount === filePaths.length;
  record("Folder-upload-stage", allStaged ? "PASS" : "FAIL",
    allStaged
      ? `all ${filePaths.length} folder files staged server-side`
      : `only ${stagedCount}/${filePaths.length} folder files staged`);
  expect(allStaged, `every folder file must stage via /api/datasets/upload (got ${stagedCount}/${filePaths.length})`).toBe(true);
});
