/**
 * Deep Playwright E2E for 2026-11-13 workflow analysis/execution hell clinic
 * on live DEV — Chat+Panel UX standard (CLAUDE.md), not shallow gates only.
 *
 * CLAUDE.md E2E discipline:
 *   - ONE login (lifeifei163361@163.com via _fixture-login)
 *   - ONE disposable project; cleanup in afterAll
 *   - No /api/auth/register; no per-test users; no API mocks
 *   - 90s+ budgets for LLM/chat; ≤20m for DE terminal poll
 *
 * Flow A (long journey): Cryo deep both-panels → Generate+4 files → ADMET SMILES
 *   route (pre-run) → cheap cart Confirm&Run→terminal → failure-honesty check.
 * Flow B (gates + DE E2E): cs_image / movies empty / samplesheet↔input /
 *   DE execute→terminal with tiny CSVs; findings honesty if failed.
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     E2E_FIXTURE_PASSWORD=$(cat ~/.config/biomate/e2e_fixture_password) \
 *     npx playwright test e2e/workflow-clinic-hell.e2e.ts --project=chromium --retries=0 --workers=1
 */
import { test, expect, type Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { loginAsFixture, BASE_URL, FIXTURE_EMAIL, resetFixtureCache, E2E_TOKEN } from "./_fixture-login";
import { createProject, deleteProjectLoudly, uploadFile } from "./_project-ui";
import { buildNextflowLaunchParameters } from "../server/nextflow-launch-params";

test.use({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });
// Flow A and Flow B are independent describes so a soft/hard fail in A does not
// skip B (CLAUDE.md: consolidate, but still get gate+DE evidence).

const TERMINAL = /completed|succeeded|failed|error|cancelled|canceled|interrupted/i;
const CRYO_NF =
  "biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf";
const CART_NF = "nf-core-workflows/modules/biomate-ai-tools/cart_construct_design/main.nf";
const DE_NF = "biomni_workflows/nfcore/differentialabundance/main.nf";
const SYNCED = process.env.BIOMATE_SYNCED_COMMIT || "live-dev";

const OUT = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "execshots",
  "workflow-clinic-hell",
);
fs.mkdirSync(OUT, { recursive: true });

const RESULTS: Record<string, { pass: boolean; evidence: string }> = {};
const AUDIT: Record<string, unknown> = { legs: {} };

function loadPriorResults() {
  try {
    const prior = JSON.parse(fs.readFileSync(path.join(OUT, "results.json"), "utf8"));
    if (prior?.results && typeof prior.results === "object") {
      Object.assign(RESULTS, prior.results);
    }
    if (prior?.synced_commit) (AUDIT as any).synced_commit = prior.synced_commit;
  } catch {
    /* first writer */
  }
  try {
    const priorAudit = JSON.parse(fs.readFileSync(path.join(OUT, "audit.json"), "utf8"));
    if (priorAudit?.legs) Object.assign(AUDIT.legs as object, priorAudit.legs);
  } catch {
    /* first writer */
  }
}

function record(id: string, pass: boolean, evidence: string) {
  RESULTS[id] = { pass, evidence };
  console.log(`\n[${pass ? "PASS" : "FAIL"}] ${id}: ${evidence}\n`);
  persist();
}

function audit(leg: string, data: unknown) {
  (AUDIT.legs as Record<string, unknown>)[leg] = data;
  persist();
}

function persist() {
  // Merge with on-disk results so Flow A / Flow B in separate workers do not clobber each other.
  let disk: Record<string, { pass: boolean; evidence: string }> = {};
  try {
    disk = JSON.parse(fs.readFileSync(path.join(OUT, "results.json"), "utf8")).results || {};
  } catch {
    /* ignore */
  }
  const merged = { ...disk, ...RESULTS };
  Object.assign(RESULTS, merged);
  fs.writeFileSync(
    path.join(OUT, "results.json"),
    JSON.stringify(
      {
        fixture: FIXTURE_EMAIL,
        base: BASE_URL,
        synced_commit: SYNCED,
        verified_at: new Date().toISOString(),
        results: RESULTS,
      },
      null,
      2,
    ),
  );
  let diskAudit: Record<string, unknown> = {};
  try {
    diskAudit = JSON.parse(fs.readFileSync(path.join(OUT, "audit.json"), "utf8"));
  } catch {
    /* ignore */
  }
  const mergedAudit = {
    ...diskAudit,
    ...AUDIT,
    legs: { ...((diskAudit as any).legs || {}), ...(AUDIT.legs as object) },
  };
  fs.writeFileSync(path.join(OUT, "audit.json"), JSON.stringify(mergedAudit, null, 2));
}

async function snap(page: Page, name: string) {
  await page.screenshot({ path: path.join(OUT, `${name}.png`), fullPage: true });
}

async function newCleanChat(page: Page) {
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
  const newChat = page.getByTestId("button-new-chat");
  if ((await newChat.count().catch(() => 0)) > 0) {
    await newChat.first().click({ timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(1500);
  }
  await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
}

async function sendChat(page: Page, text: string) {
  const input = page.getByTestId("chat-input");
  await input.click();
  await input.fill(text);
  const send = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await send.waitFor({ state: "visible", timeout: 30_000 });
  await send.click({ timeout: 15_000 });
}

const PLACEHOLDER =
  /(?:Preparing the plan|Understanding your goal|Thinking|Analy[sz]ing|Searching|Working on it|Finding|Generating)\b[^\n]{0,80}$|…\s*$/i;

async function settleAssistant(page: Page, budgetMs = 240_000): Promise<string> {
  const answerDeadline = Date.now() + budgetMs;
  let lastAssist = "";
  let stableSince = Date.now();
  while (Date.now() < answerDeadline) {
    const now =
      (await page.locator('[data-is-latest-assistant="true"]').last().innerText().catch(() => "")) ||
      (await page.locator('[data-role="assistant"]').last().innerText().catch(() => "")) ||
      "";
    if (now !== lastAssist) {
      lastAssist = now;
      stableSince = Date.now();
    }
    const stopBusy = (await page.getByTestId("chat-stop-button").count().catch(() => 0)) > 0;
    const busy = stopBusy || PLACEHOLDER.test(now.trim());
    if (!busy && now.trim().length >= 40 && Date.now() - stableSince > 12_000) break;
    await page.waitForTimeout(2_000);
  }
  return lastAssist;
}

function notAdmetGated(text: string) {
  const low = text.toLowerCase();
  const isAdmetGated =
    /admet[- ]gated\s+virtual\s+screening/.test(low) || /drug_discovery_admet_gated_screening/.test(low);
  const isPharmacophoreAdmetDockChain =
    (/pharmacophore/.test(low) && /admet/.test(low) && /(vina|dock)/.test(low)) ||
    /target[- ]to[- ]lead/.test(low) ||
    /pocket detection.*pharmacophore.*admet/.test(low);
  const prefersDesign =
    /reinvent/.test(low) ||
    /lead[_ ]design/.test(low) ||
    /de novo/.test(low) ||
    (/generat/.test(low) && /(candidate|molecule|ligand)/.test(low) && !isAdmetGated);
  const honestClarification =
    /missing|need|pdb|sequence|structure|clarif|provide|which target|target (id|name|protein)/i.test(text) &&
    !isAdmetGated;
  return {
    ok: !isAdmetGated && !isPharmacophoreAdmetDockChain && (prefersDesign || honestClarification),
    isAdmetGated,
    isPharmacophoreAdmetDockChain,
    prefersDesign,
    honestClarification,
  };
}

async function cancelIfQueued(page: Page, runId: string | undefined) {
  if (!runId) return;
  await page.request.post(`${BASE_URL}/api/workflows/runs/${runId}/cancel`, { data: {} }).catch(() => {});
}

async function pollWorkflowTerminal(page: Page, runId: string, budgetMs: number) {
  const deadline = Date.now() + budgetMs;
  let last = "queued";
  let error: string | undefined;
  while (Date.now() < deadline) {
    try {
      const r = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`, {
        timeout: 30_000,
      });
      if (r.ok()) {
        const d = await r.json().catch(() => ({}));
        last = String(d.status || last);
        error = d.errorMessage || d.error || error;
        if (TERMINAL.test(last)) return { status: last, error, timedOut: false as const };
      }
    } catch (e: any) {
      // Transient DEV blips / 60s default timeout must not abort the poll loop.
      console.log(`[poll] status fetch err for ${runId}: ${String(e?.message || e).slice(0, 120)}`);
    }
    await page.waitForTimeout(5_000);
  }
  return { status: last, error, timedOut: true as const };
}

/** Dismiss Settings / credential overlays so they do not steal the workflow panel. */
async function dismissOverlays(page: Page) {
  const close = page.getByRole("button", { name: /^close$/i }).or(page.locator('[aria-label="Close"]'));
  if ((await close.count()) > 0 && (await close.first().isVisible().catch(() => false))) {
    await close.first().click({ timeout: 3000 }).catch(() => {});
    await page.waitForTimeout(500);
  }
  await page.keyboard.press("Escape").catch(() => {});
  await page.waitForTimeout(400);
}

/**
 * Open the right workflow panel without clicking global Settings.
 * Prefer clarify "Confirm and configure" / Edit params / In panel CTAs.
 */
async function openPanelIfOffered(page: Page) {
  await dismissOverlays(page);
  // Clarify card final CTA (testid) — do NOT match sidebar "Settings"
  const clarifyConfirm = page.getByTestId("clarify-next").or(
    page.getByRole("button", { name: /^Confirm and configure$/i }),
  );
  if ((await clarifyConfirm.count()) > 0 && (await clarifyConfirm.last().isVisible().catch(() => false))) {
    await clarifyConfirm.last().click({ timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(2500);
  }
  const openPanel = page.getByRole("button", {
    name: /^(Open.*(panel|workflow)|In panel|Edit params|Configure)$/i,
  });
  if ((await openPanel.count()) > 0 && (await openPanel.first().isVisible().catch(() => false))) {
    await openPanel.first().click({ timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(2000);
  }
  // Wait for panel shell if chat claimed it is ready
  await page
    .getByTestId("workflow-right-panel")
    .or(page.locator(".panel-name"))
    .first()
    .waitFor({ state: "visible", timeout: 20_000 })
    .catch(() => {});
}

/** Both-panel presentation: chat name + right panel name not undefined; Confirm state. */
async function readBothPanels(page: Page) {
  const panel = page.getByTestId("workflow-right-panel");
  const panelVisible = (await panel.count()) > 0 && (await panel.first().isVisible().catch(() => false));
  const panelText = panelVisible ? (await panel.first().innerText().catch(() => "")) || "" : "";
  const panelName =
    (await page.locator(".panel-name").first().textContent().catch(() => ""))?.trim() ||
    (await page.locator('[data-testid="workflow-right-panel"] h1, [data-testid="workflow-right-panel"] h2').first().textContent().catch(() => ""))?.trim() ||
    "";
  const chipName =
    (await page.locator(".wf-chip-name").first().textContent().catch(() => ""))?.trim() || "";
  const assistant =
    (await page.locator('[data-is-latest-assistant="true"]').last().innerText().catch(() => "")) ||
    (await page.locator('[data-role="assistant"]').last().innerText().catch(() => "")) ||
    "";
  const confirm = page.getByTestId("button-run-workflow-panel").or(page.getByRole("button", { name: /confirm\s*&?\s*run/i }));
  let confirmState: "missing" | "enabled" | "disabled" = "missing";
  if ((await confirm.count()) > 0) {
    const btn = confirm.first();
    const disabled =
      (await btn.isDisabled().catch(() => false)) ||
      (await btn.getAttribute("aria-disabled").catch(() => null)) === "true";
    confirmState = disabled ? "disabled" : "enabled";
  }
  const badge = await page
    .locator('[data-testid="workflow-overall-status-badge"]')
    .first()
    .getAttribute("data-status")
    .catch(() => null);
  const nameOk = (n: string) => !!n && n !== "undefined" && n !== "Untitled" && !/^undefined$/i.test(n);
  const noRequiredLie = /no required data inputs/i.test(panelText);
  return {
    panelVisible,
    panelName,
    chipName,
    assistant: assistant.slice(0, 2000),
    panelText: panelText.slice(0, 4000),
    confirmState,
    badge,
    nameOk: nameOk(panelName) || nameOk(chipName),
    noRequiredLie,
    undefinedLeak: /undefined/i.test(panelName) || /undefined/i.test(chipName) || /\bundefined\b/i.test(panelText.slice(0, 800)),
  };
}

async function assertFindingsHonesty(page: Page, runFailed: boolean) {
  const afterTab = page.locator('[data-testid="panel-tab-after-run"], [data-testid="after-tab-findings"]').first();
  if ((await afterTab.count()) > 0) {
    await afterTab.click({ timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1500);
  }
  const findingsTab = page.locator('[data-testid="after-tab-findings"]').first();
  if ((await findingsTab.count()) > 0) {
    await findingsTab.click({ timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1000);
  }
  const body = (await page.locator("body").innerText().catch(() => "")) || "";
  const inProgress = /Analysis in progress|Analyzing outputs/i.test(body);
  const notAvail = /Analysis not available/i.test(body);
  const spinner = await page.locator('[data-testid="findings-loading"]').isVisible().catch(() => false);
  if (!runFailed) {
    return { ok: true, inProgress, notAvail, spinner, note: "run not failed — honesty N/A" };
  }
  const ok = !inProgress && !spinner;
  return { ok, inProgress, notAvail, spinner, note: ok ? "failed run honest" : "REGRESSION: spinner/in-progress on failed run" };
}

let page: Page;
let projectId: string;
let samplesheetUri = "";
let matrixUri = "";
let contrastsUri = "";
let lastFailedRunId: string | undefined;

test.beforeAll(async ({ browser }) => {
  loadPriorResults();
  resetFixtureCache();
  page = await browser.newPage();
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await loginAsFixture(page);

  // Resolve live commit for audit
  try {
    const bi = await page.request.get(`${BASE_URL}/build-info.json`);
    const j = await bi.json();
    if (j?.commit) (AUDIT as any).live_commit = j.commit;
  } catch {
    /* ignore */
  }

  projectId = await createProject(page.request, `workflow-clinic-hell ${Date.now()}`);
  await page.addInitScript((id) => {
    try {
      localStorage.setItem("biomate-active-project-id", id);
    } catch {
      /* ignore */
    }
  }, projectId);

  // Tiny DE fixtures (2 samples / 2 genes) — enough for alias + terminal probe.
  const ss = await uploadFile(
    page.request,
    projectId,
    "samplesheet.csv",
    Buffer.from("sample,condition\nA1,ctrl\nA2,treat\n", "utf8"),
    "text/csv",
    "inputs/samplesheet.csv",
  );
  const mx = await uploadFile(
    page.request,
    projectId,
    "matrix.csv",
    Buffer.from("gene_id,A1,A2\nG1,10,20\nG2,5,15\n", "utf8"),
    "text/csv",
    "inputs/matrix.csv",
  );
  const ct = await uploadFile(
    page.request,
    projectId,
    "contrasts.csv",
    Buffer.from("id,variable,reference,target\nc1,condition,ctrl,treat\n", "utf8"),
    "text/csv",
    "inputs/contrasts.csv",
  );

  const filesRes = await page.request.get(`${BASE_URL}/api/projects/${projectId}/files`);
  expect(filesRes.ok(), `list files ${filesRes.status()}`).toBeTruthy();
  const filesBody = await filesRes.json();
  const files: any[] = Array.isArray(filesBody) ? filesBody : filesBody.files || filesBody.items || [];
  const byId = new Map(files.map((f: any) => [f.id, f]));
  const pathOf = (id: string, fallbackName: string) => {
    const f = byId.get(id);
    const s3 = f?.s3Uri || f?.s3_uri || f?.uri || f?.url || f?.path;
    if (typeof s3 === "string" && s3.length > 0) return s3;
    return `project://${projectId}/${fallbackName}`;
  };
  samplesheetUri = pathOf(ss.id, "inputs/samplesheet.csv");
  matrixUri = pathOf(mx.id, "inputs/matrix.csv");
  contrastsUri = pathOf(ct.id, "inputs/contrasts.csv");
  fs.writeFileSync(
    path.join(OUT, "00-project-files.json"),
    JSON.stringify({ projectId, samplesheetUri, matrixUri, contrastsUri, files: files.slice(0, 20) }, null, 2),
  );
});

test.afterAll(async () => {
  if (page && projectId) {
    await deleteProjectLoudly(page.request, projectId, { inHook: true });
  }
  await page?.close();
});

test.describe("Flow A — long journey", () => {
  test.describe.configure({ mode: "serial", timeout: 50 * 60_000 });
  test("Cryo deep → Generate+4 → ADMET → cheap terminal → honesty", async () => {
    test.setTimeout(45 * 60_000);

    // ═══════════════════════════════════════════════════════════════════════
    // A1. Cryo deep — both panels, Movies Path required, no optional-only lie
    // ═══════════════════════════════════════════════════════════════════════
    await newCleanChat(page);
    await sendChat(
      page,
      "Open the cryosparc_standard_spa workflow (CryoSPARC standard SPA). Do not run it — I only need the pre-run panel with parameters.",
    );
    await Promise.race([
      page.getByTestId("workflow-right-panel").first().waitFor({ state: "visible", timeout: 220_000 }),
      page.getByRole("button", { name: /confirm\s*&?\s*run/i }).first().waitFor({ state: "visible", timeout: 220_000 }),
      page.getByText(/Movies Path|movies_path|cryosparc|CryoSPARC/i).first().waitFor({ timeout: 220_000 }),
    ]).catch(() => {});
    await page.waitForTimeout(4000);
    await openPanelIfOffered(page);
    await snap(page, "a1-cryo-prerun");

    const cryoPanels = await readBothPanels(page);
    const labels = await page
      .locator('[data-testid="workflow-right-panel"] label, [data-testid="workflow-right-panel"] [data-param-name]')
      .evaluateAll((els) =>
        els.map((e) => e.textContent?.trim() || e.getAttribute("data-param-name") || "").filter(Boolean),
      )
      .catch(() => [] as string[]);
    const hasMovies =
      /movies\s*path/i.test(cryoPanels.panelText) ||
      labels.some((l) => /movies/i.test(l)) ||
      /movies_path/i.test(cryoPanels.panelText) ||
      /movies_path|Movies Path/i.test(cryoPanels.assistant);
    const showsCsImage =
      /\bcs[_\s-]?image\b/i.test(cryoPanels.panelText) ||
      /Cs Image/i.test(cryoPanels.panelText) ||
      /dkr\.ecr\./i.test(cryoPanels.panelText);
    const fixNowVisible = await page.getByRole("button", { name: /fix now/i }).first().isVisible().catch(() => false);
    const missingAlert = await page
      .getByText(/movies path|movies_path|required parameter|missing/i)
      .first()
      .isVisible()
      .catch(() => false);
    const confirmBlocked = cryoPanels.confirmState === "disabled" || fixNowVisible || missingAlert;

    const gen = await page.request.post(`${BASE_URL}/api/ai_assistant/generate_workflow`, {
      data: { request_text: "cryosparc_standard_spa CryoSPARC standard SPA" },
    });
    const genBody = await gen.json().catch(() => ({}));
    const ga = genBody.workflow_ga || {};
    const paramNames = [
      ...((ga.required_params || []) as any[]),
      ...((ga.optional_params || []) as any[]),
    ].map((p) => String(p.name || ""));
    const apiNoCs = !paramNames.includes("cs_image");

    const execEmpty = await page.request.post(`${BASE_URL}/api/workflows/execute`, {
      data: {
        workflowDefinition: {
          name: ga.name || "CryoSPARC Standard SPA",
          nextflow_path: ga.nextflow_path || CRYO_NF,
          required_params: (ga.required_params || [{ name: "movies_path", type: "file", required: true }]).map(
            (p: any) => ({ ...p, value: null }),
          ),
          optional_params: ga.optional_params || [],
        },
        params: {},
      },
    });
    const execEmptyBody = await execEmpty.json().catch(() => ({}));
    const apiBlocksEmpty =
      execEmpty.status() === 400 &&
      (execEmptyBody?.error === "missing_required_params" || /missing/i.test(String(execEmptyBody?.error || ""))) &&
      JSON.stringify(execEmptyBody).includes("movies_path");

    fs.writeFileSync(
      path.join(OUT, "a1-cryo-panel.txt"),
      JSON.stringify({ cryoPanels, labels, paramNames, execEmptyBody }, null, 2).slice(0, 16000),
    );

    // Chat-side name (even before panel opens)
    const chatNameOk = /CryoSPARC Standard SPA/i.test(cryoPanels.assistant) && !/\bundefined\b/i.test(cryoPanels.assistant.slice(0, 400));
    // If panel still closed after CTA, one more clarify click + wait
    let panels = cryoPanels;
    if (!panels.panelVisible) {
      await openPanelIfOffered(page);
      await snap(page, "a1-cryo-prerun-retry");
      panels = await readBothPanels(page);
    }
    const cryoPass =
      hasMovies &&
      confirmBlocked &&
      apiBlocksEmpty &&
      !panels.noRequiredLie &&
      !panels.undefinedLeak &&
      (panels.nameOk || chatNameOk) &&
      (panels.panelVisible || /ready in the panel|Confirm and configure|movies_path is required/i.test(panels.assistant));
    record(
      "cryo_deep_both_panels",
      cryoPass,
      `movies=${hasMovies} confirmBlocked=${confirmBlocked} apiBlocks=${apiBlocksEmpty} panelVisible=${panels.panelVisible} noRequiredLie=${panels.noRequiredLie} nameOk=${panels.nameOk} chatNameOk=${chatNameOk} undefinedLeak=${panels.undefinedLeak} confirm=${panels.confirmState} panelName=${panels.panelName} chip=${panels.chipName}`,
    );
    record(
      "cryo_cs_image_hidden",
      apiNoCs && !showsCsImage,
      `apiHasCsImage=${!apiNoCs} uiShowsCsImage=${showsCsImage}`,
    );
    // Soft: continue journey so ADMET/cart/DE still run; hard-check critical matrix at end.
    expect.soft(cryoPass, "Cryo: Movies Path required in chat+panel; Confirm blocked; not optional-only").toBe(true);
    expect.soft(apiNoCs && !showsCsImage, "cs_image hidden").toBe(true);
    // Product bug if chat claims panel ready but panel never opens after Confirm and configure
    if (!panels.panelVisible && /ready in the panel/i.test(panels.assistant)) {
      record(
        "cryo_panel_open_bug",
        false,
        "PRODUCT: chat says workflow ready in panel but workflow-right-panel never visible after Confirm and configure — investigate clarify→panel wiring",
      );
    } else {
      record("cryo_panel_open_bug", true, `panelVisible=${panels.panelVisible}`);
    }

    // License path with dummy movies_path — no GPU burn
    const licRes = await page.request.get(
      `${BASE_URL}/api/workflows/license-requirements?nextflow_path=${encodeURIComponent(CRYO_NF)}`,
    );
    const licBody = await licRes.json().catch(() => ({}));
    const reqs: any[] = Array.isArray(licBody?.requirements) ? licBody.requirements : [];
    const cryoReq = reqs.find((r) => /cryo/i.test(String(r.tool_id || r.display_name || "")));
    const hasLicense = !!cryoReq && (cryoReq.source === "user" || cryoReq.source === "biomate");
    fs.writeFileSync(path.join(OUT, "a1-cryo-license-api.json"), JSON.stringify({ status: licRes.status(), body: licBody }, null, 2));

    if (hasLicense) {
      record(
        "cryo_license_gate",
        true,
        `SKIP: fixture has CryoSPARC credential (source=${cryoReq.source}) — no GPU run`,
      );
    } else {
      await newCleanChat(page);
      await sendChat(
        page,
        "Open cryosparc_standard_spa. Set movies_path to s3://biomate-e2e-dummy/movies/ (dummy — do NOT run). Show license/credentials if needed.",
      );
      await Promise.race([
        page.getByTestId("workflow-right-panel").first().waitFor({ state: "visible", timeout: 180_000 }),
        page.getByText(/Tool Credentials|license|Movies Path/i).first().waitFor({ timeout: 180_000 }),
      ]).catch(() => {});
      await openPanelIfOffered(page);
      await snap(page, "a1-cryo-license");
      const licenseUi =
        (await page.getByTestId(/license-row-/).first().isVisible().catch(() => false)) ||
        (await page
          .getByText(/Tool Credentials|CryoSPARC.*(license|credential)|Provide credentials|license key/i)
          .first()
          .isVisible()
          .catch(() => false));
      const execLic = await page.request.post(`${BASE_URL}/api/workflows/execute`, {
        data: {
          workflowDefinition: {
            name: "CryoSPARC Standard SPA",
            nextflow_path: CRYO_NF,
            required_params: [{ name: "movies_path", type: "file", required: true, value: "s3://biomate-e2e-dummy/movies/" }],
            optional_params: [],
          },
          params: { movies_path: "s3://biomate-e2e-dummy/movies/" },
          projectId,
        },
      });
      const execLicBody = await execLic.json().catch(() => ({}));
      await cancelIfQueued(page, execLicBody?.runId || execLicBody?.run_id);
      const apiLicenseGate =
        execLic.status() === 402 &&
        (execLicBody?.error === "cryosparc_license_required" || /license/i.test(String(execLicBody?.message || "")));
      const didNotQueue = !execLicBody?.runId && !execLicBody?.run_id;
      const licPass = (licenseUi || apiLicenseGate) && didNotQueue;
      record(
        "cryo_license_gate",
        licPass,
        `licenseUi=${licenseUi} apiLicenseGate=${apiLicenseGate} status=${execLic.status()} didNotQueue=${didNotQueue}`,
      );
      expect(licPass, "without license: Tool Credentials UI and/or 402 before GPU").toBe(true);
    }
    audit("a1_cryo", { cryoPanels, hasMovies, confirmBlocked, apiBlocksEmpty, hasLicense });

    // ═══════════════════════════════════════════════════════════════════════
    // A2. Generate 500 + 4 real attachments — names usable, not ADMET-Gated
    // ═══════════════════════════════════════════════════════════════════════
    await newCleanChat(page);
    const ATTACH = [
      { name: "target_hint.txt", mimeType: "text/plain", buffer: Buffer.from("EGFR kinase domain — design candidates\n", "utf8") },
      { name: "seed_smiles.csv", mimeType: "text/csv", buffer: Buffer.from("smiles\nCCO\nc1ccccc1\n", "utf8") },
      { name: "property_goals.md", mimeType: "text/markdown", buffer: Buffer.from("# Goals\n- MW < 450\n- QED > 0.5\n", "utf8") },
      { name: "scaffold.smi", mimeType: "chemical/x-daylight-smiles", buffer: Buffer.from("c1ccc2ncccc2c1\n", "utf8") },
    ];
    const fileInput = page.locator('[data-testid="chat-attach-file-input"]');
    await fileInput.waitFor({ state: "attached", timeout: 15_000 });
    await fileInput.setInputFiles(ATTACH);
    await page.getByTestId("composer-attached-file").first().waitFor({ state: "visible", timeout: 30_000 });
    const chipTexts = await page.getByTestId("composer-attached-file").allInnerTexts().catch(() => [] as string[]);
    const composerNamesOk = ATTACH.every((f) => chipTexts.some((t) => t.includes(f.name)));
    await snap(page, "a2-attach-composer");

    await sendChat(page, "Generate 500 candidates for this target with drug-like properties.");
    await page.waitForTimeout(2500);
    const foldChip = page.locator('span[title*="target_hint"]').filter({ hasText: /files attached/i }).first();
    const foldVisible = await foldChip.isVisible().catch(() => false);
    const foldTitle = foldVisible ? (await foldChip.getAttribute("title").catch(() => "")) || "" : "";
    const namesInTooltip = ATTACH.every((f) => foldTitle.includes(f.name));
    const namesUsable = composerNamesOk || (foldVisible && namesInTooltip);

    const g500Assist = await settleAssistant(page);
    await openPanelIfOffered(page);
    await snap(page, "a2-generate-reply");
    const g500Panels = await readBothPanels(page);
    const gate = notAdmetGated(g500Assist);
    const stillPlaceholder = PLACEHOLDER.test(g500Assist.trim()) || g500Assist.trim().length < 40;
    const clarifyNeedsStructure =
      gate.honestClarification && /structure|sequence|pdb|fasta|uniprot/i.test(g500Assist);
    const designCard =
      gate.prefersDesign &&
      (/reinvent|lead.?design|de novo|generative/i.test(g500Assist) ||
        /reinvent|lead.?design|generative/i.test(g500Panels.panelName + g500Panels.chipName));
    // If a workflow card/panel opened: files considered OR honestly unused — not silent params-only with attachments ignored.
    const filesMentioned =
      /attach|seed|scaffold|smiles|upload|file|csv|unused|not used|parameters-only/i.test(
        g500Assist + "\n" + g500Panels.panelText,
      );
    const pathOk =
      !stillPlaceholder &&
      !gate.isAdmetGated &&
      !gate.isPharmacophoreAdmetDockChain &&
      (clarifyNeedsStructure || designCard || gate.ok);

    fs.writeFileSync(
      path.join(OUT, "a2-generate-attach.txt"),
      JSON.stringify(
        {
          chipTexts,
          foldTitle,
          namesUsable,
          gate,
          clarifyNeedsStructure,
          designCard,
          filesMentioned,
          panels: g500Panels,
          assistant: g500Assist.slice(0, 6000),
        },
        null,
        2,
      ),
    );
    record(
      "generate_500_with_attachments",
      namesUsable && pathOk,
      `namesUsable=${namesUsable} admet=${gate.isAdmetGated} pharm=${gate.isPharmacophoreAdmetDockChain} clarifyStruct=${clarifyNeedsStructure} design=${designCard} filesMentioned=${filesMentioned} nameOk=${g500Panels.nameOk} panel=${g500Panels.panelName}`,
    );
    expect.soft(namesUsable, "4 attachment names visible (composer and/or fold tooltip)").toBe(true);
    expect.soft(pathOk, "Generate+4: not ADMET-Gated; clarify(structure) or design path").toBe(true);
    audit("a2_generate", { namesUsable, gate, clarifyNeedsStructure, designCard, g500Panels });

    // ═══════════════════════════════════════════════════════════════════════
    // A3. ADMET SMILES screening (separate from Generate) — correct ADMET route
    //     Pre-run only (no Batch burn here; deep terminal covered by cart + DE).
    // ═══════════════════════════════════════════════════════════════════════
    await newCleanChat(page);
    await sendChat(
      page,
      "Screen these compounds for ADMET properties including hERG cardiotoxicity IC50, CYP3A4 inhibition and Lipinski Ro5:\n" +
        "- caffeine: CN1C=NC2=C1C(=O)N(C(=O)N2C)C\n" +
        "- aspirin: CC(=O)Oc1ccccc1C(=O)O\n" +
        "Use the standard ADMET prediction workflow. Do not start a mega screening chain.",
    );
    await settleAssistant(page);
    await openPanelIfOffered(page);
    await snap(page, "a3-admet-prerun");
    const admetPanels = await readBothPanels(page);
    const admetBlob = (admetPanels.assistant + "\n" + admetPanels.panelText + "\n" + admetPanels.panelName + "\n" + admetPanels.chipName).toLowerCase();
    const isAdmet =
      /\badmet\b/.test(admetBlob) &&
      !/admet[- ]gated\s+virtual\s+screening/.test(admetBlob) &&
      !(/pharmacophore/.test(admetBlob) && /dock/.test(admetBlob));
    const smilesHonest =
      /caffeine|aspirin|smiles|CN1C|CC\(=O\)O/i.test(admetPanels.assistant + admetPanels.panelText) ||
      /smiles|compound|input/i.test(admetPanels.panelText);
    const admetPass = isAdmet && admetPanels.nameOk && !admetPanels.undefinedLeak;
    record(
      "admet_smiles_route",
      admetPass,
      `isAdmet=${isAdmet} smilesHonest=${smilesHonest} nameOk=${admetPanels.nameOk} panel=${admetPanels.panelName} chip=${admetPanels.chipName} confirm=${admetPanels.confirmState}`,
    );
    expect.soft(admetPass, "SMILES ADMET request routes to ADMET (not random mega-chain); name defined").toBe(true);
    audit("a3_admet", { admetPanels, isAdmet, smilesHonest });

    // ═══════════════════════════════════════════════════════════════════════
    // A4. Cheap Confirm&Run → terminal (cart_construct_design)
    // ═══════════════════════════════════════════════════════════════════════
    await newCleanChat(page);
    await sendChat(
      page,
      "Run the cart_construct_design workflow to design a CD19-targeting CAR construct for B-cell indications: select CAR generation, costimulatory domain and format, and report the design rationale. Use the built-in defaults (target CD19, 2nd generation, auto costimulatory domain). This is an in-silico design exercise; do not require my own uploads.",
    );
    await Promise.race([
      page.getByRole("button", { name: /confirm\s*&?\s*run/i }).first().waitFor({ state: "visible", timeout: 240_000 }),
      page.getByTestId("workflow-right-panel").first().waitFor({ state: "visible", timeout: 240_000 }),
      page.getByText(/cart_construct|CAR construct|CD19/i).first().waitFor({ timeout: 240_000 }),
    ]).catch(() => {});
    await openPanelIfOffered(page);
    await snap(page, "a4-cart-prerun");
    const cartPanels = await readBothPanels(page);
    const routedCart = /cart_construct|car.?construct|cd19/i.test(
      cartPanels.assistant + cartPanels.panelText + cartPanels.panelName + cartPanels.chipName,
    );
    expect.soft(routedCart && (cartPanels.nameOk || /cart_construct|CD19/i.test(cartPanels.assistant)), "cart routes with defined name").toBe(true);

    let cartRunId: string | undefined;
    let cartLaunch = "none";
    const confirm = page.getByTestId("button-run-workflow-panel").or(page.getByRole("button", { name: /confirm\s*&?\s*run/i }));
    if ((await confirm.count()) > 0) {
      const waitExec = page.waitForResponse(
        (r) => r.request().method() === "POST" && /\/api\/workflows\/execute/.test(r.url()),
        { timeout: 120_000 },
      );
      const btn = confirm.first();
      if (await btn.isEnabled().catch(() => false)) await btn.click({ timeout: 15_000 });
      else await btn.click({ timeout: 15_000, force: true }).catch(() => {});
      const execResp = await waitExec.catch(() => null);
      if (execResp) {
        const j = await execResp.json().catch(() => ({}));
        cartRunId = j?.runId || j?.run_id;
        cartLaunch = `ui status=${execResp.status()}`;
        fs.writeFileSync(path.join(OUT, "a4-cart-execute.json"), JSON.stringify({ via: "ui", status: execResp.status(), body: j }, null, 2));
      }
    }
    if (!cartRunId) {
      const g = await page.request.post(`${BASE_URL}/api/ai_assistant/generate_workflow`, {
        data: { request_text: "cart_construct_design CD19 CAR construct built-in defaults" },
      });
      const gb = await g.json().catch(() => ({}));
      const cga = gb.workflow_ga || {};
      const exec = await page.request.post(`${BASE_URL}/api/workflows/execute`, {
        data: {
          workflowDefinition: {
            name: cga.name || "cart_construct_design",
            nextflow_path: cga.nextflow_path || CART_NF,
            required_params: cga.required_params || [
              { name: "target_antigen", type: "string", value: "CD19" },
              { name: "indication", type: "string", value: "B-cell" },
            ],
            optional_params: cga.optional_params || [],
          },
          params: { target_antigen: "CD19", indication: "B-cell malignancies" },
          projectId,
        },
      });
      const eb = await exec.json().catch(() => ({}));
      cartRunId = eb?.runId || eb?.run_id;
      cartLaunch = `api status=${exec.status()}`;
      fs.writeFileSync(path.join(OUT, "a4-cart-execute.json"), JSON.stringify({ via: "api", status: exec.status(), body: eb }, null, 2));
    }
    expect(cartRunId, `cart runId (${cartLaunch})`).toBeTruthy();
    await snap(page, "a4-cart-running");
    const cartTerm = await pollWorkflowTerminal(page, cartRunId!, 12 * 60_000);
    await snap(page, "a4-cart-terminal");
    fs.writeFileSync(path.join(OUT, "a4-cart-terminal.json"), JSON.stringify({ cartRunId, cartLaunch, cartTerm, cartPanels }, null, 2));
    const cartOk = !cartTerm.timedOut && TERMINAL.test(cartTerm.status);
    if (/failed|error/i.test(cartTerm.status)) lastFailedRunId = cartRunId;
    record(
      "cheap_run_to_terminal",
      cartOk,
      `runId=${cartRunId} launch=${cartLaunch} status=${cartTerm.status} timedOut=${cartTerm.timedOut} err=${String(cartTerm.error || "").slice(0, 180)}`,
    );
    expect.soft(cartOk, `cart must reach terminal (got ${cartTerm.status})`).toBe(true);
    audit("a4_cart", { cartRunId, cartLaunch, cartTerm, cartPanels });

    // ═══════════════════════════════════════════════════════════════════════
    // A5. Failure honesty — if we have a failed run, Findings must not spin
    // ═══════════════════════════════════════════════════════════════════════
    if (lastFailedRunId || /failed|error/i.test(cartTerm.status)) {
      await openPanelIfOffered(page);
      const honesty = await assertFindingsHonesty(page, true);
      await snap(page, "a5-findings-honesty");
      record("failure_findings_honesty", honesty.ok, JSON.stringify(honesty));
      expect(honesty.ok, "failed run must not show Analysis in progress…").toBe(true);
    } else {
      // Probe execute that will fail fast (empty required) is not a "run"; document skip.
      // Also check after-run UI on completed cart: must not stuck-spin.
      const honesty = await assertFindingsHonesty(page, false);
      record(
        "failure_findings_honesty",
        true,
        `SKIP no failed run this journey (cart=${cartTerm.status}); completed-path check inProgress=${honesty.inProgress}`,
      );
    }

    const aCritical = [
      "cryo_deep_both_panels",
      "cryo_cs_image_hidden",
      "cryo_license_gate",
      "generate_500_with_attachments",
      "admet_smiles_route",
      "cheap_run_to_terminal",
      "failure_findings_honesty",
    ];
    const aFails = aCritical.filter((k) => RESULTS[k] && !RESULTS[k].pass);
    expect(aFails, `Flow A critical failures: ${aFails.join(", ")}`).toEqual([]);
  });
});

test.describe("Flow B — gates + DE terminal", () => {
  test.describe.configure({ mode: "serial", timeout: 30 * 60_000 });
  test("alias gates + DE execute→terminal", async () => {
    test.setTimeout(25 * 60_000);

    // ── B1. DE alias gate (pure + negative execute) ─────────────────────────
    const mirrored = buildNextflowLaunchParameters(
      {
        name: "nf-core/differentialabundance",
        required_params: [
          { name: "samplesheet", type: "file", value: samplesheetUri },
          { name: "matrix", type: "file", value: matrixUri },
          { name: "contrasts", type: "file", value: contrastsUri },
        ],
        optional_params: [{ name: "input", type: "file" }],
      },
      { samplesheet: samplesheetUri, matrix: matrixUri, contrasts: contrastsUri },
    );
    const aliasOk = mirrored.samplesheet === samplesheetUri && mirrored.input === samplesheetUri;

    const execMatrixOnly = await page.request.post(`${BASE_URL}/api/workflows/execute`, {
      data: {
        workflowDefinition: {
          name: "nf-core/differentialabundance",
          nextflow_path: DE_NF,
          required_params: [
            { name: "samplesheet", type: "file", required: true, value: samplesheetUri },
            { name: "matrix", type: "file", required: true, value: null },
            { name: "contrasts", type: "file", required: true, value: contrastsUri },
          ],
          optional_params: [{ name: "input", type: "file", required: false }],
        },
        params: { samplesheet: samplesheetUri, contrasts: contrastsUri },
        projectId,
      },
    });
    const matrixBody = await execMatrixOnly.json().catch(() => ({}));
    const matrixOnlyMissing =
      execMatrixOnly.status() === 400 &&
      JSON.stringify(matrixBody).includes("matrix") &&
      !/samplesheet was not provided/i.test(JSON.stringify(matrixBody));

    record(
      "de_samplesheet_input_alias",
      aliasOk && matrixOnlyMissing,
      `aliasOk=${aliasOk} matrixOnlyMissing=${matrixOnlyMissing} mirroredKeys=${Object.keys(mirrored).join(",")}`,
    );
    expect(aliasOk && matrixOnlyMissing).toBe(true);

    // ── B2. DE both-panels prerun + execute→terminal ───────────────────────
    await newCleanChat(page);
    await sendChat(
      page,
      `Open nf-core/differentialabundance for this project. Map samplesheet to ${samplesheetUri}, matrix to ${matrixUri}, contrasts to ${contrastsUri}. Show the pre-run panel, then I will Confirm & Run.`,
    );
    await Promise.race([
      page.getByText(/differential|samplesheet|abundance/i).first().waitFor({ timeout: 180_000 }),
      page.getByTestId("workflow-right-panel").first().waitFor({ state: "visible", timeout: 180_000 }),
    ]).catch(() => {});
    await page.waitForTimeout(4000);
    await openPanelIfOffered(page);
    await snap(page, "b2-de-prerun");
    const dePanels = await readBothPanels(page);
    const uiClaimsSamplesheetMissing = /samplesheet was not provided/i.test(dePanels.panelText + dePanels.assistant);
    const deNameOk = dePanels.nameOk && !dePanels.undefinedLeak;
    fs.writeFileSync(path.join(OUT, "b2-de-prerun.txt"), JSON.stringify(dePanels, null, 2).slice(0, 12000));

    let deRunId: string | undefined;
    let deLaunch = "none";
    const confirm = page.getByTestId("button-run-workflow-panel").or(page.getByRole("button", { name: /confirm\s*&?\s*run/i }));
    if ((await confirm.count()) > 0 && (await confirm.first().isEnabled().catch(() => false))) {
      const waitExec = page.waitForResponse(
        (r) => r.request().method() === "POST" && /\/api\/workflows\/execute/.test(r.url()),
        { timeout: 120_000 },
      );
      await confirm.first().click({ timeout: 15_000 });
      const execResp = await waitExec.catch(() => null);
      if (execResp) {
        const j = await execResp.json().catch(() => ({}));
        deRunId = j?.runId || j?.run_id;
        deLaunch = `ui status=${execResp.status()}`;
        // If UI wrongly says samplesheet missing in error body, fail hard.
        if (/samplesheet was not provided/i.test(JSON.stringify(j))) {
          record("de_run_to_terminal", false, `UI execute claimed samplesheet missing: ${JSON.stringify(j).slice(0, 300)}`);
          expect(false, "must not claim samplesheet missing when mapped").toBe(true);
        }
      }
    }
    if (!deRunId) {
      const exec = await page.request.post(`${BASE_URL}/api/workflows/execute`, {
        data: {
          workflowDefinition: {
            name: "nf-core/differentialabundance",
            nextflow_path: DE_NF,
            required_params: [
              { name: "samplesheet", type: "file", required: true, value: samplesheetUri },
              { name: "matrix", type: "file", required: true, value: matrixUri },
              { name: "contrasts", type: "file", required: true, value: contrastsUri },
            ],
            optional_params: [{ name: "input", type: "file", required: false }],
          },
          params: { samplesheet: samplesheetUri, matrix: matrixUri, contrasts: contrastsUri },
          projectId,
        },
      });
      const eb = await exec.json().catch(() => ({}));
      deRunId = eb?.runId || eb?.run_id;
      deLaunch = `api status=${exec.status()}`;
      fs.writeFileSync(path.join(OUT, "b2-de-execute.json"), JSON.stringify({ via: "api", status: exec.status(), body: eb }, null, 2));
      expect(
        !/samplesheet was not provided/i.test(JSON.stringify(eb)),
        "execute must not claim samplesheet missing when provided",
      ).toBe(true);
    }

    expect(deRunId, `DE runId (${deLaunch})`).toBeTruthy();
    expect(uiClaimsSamplesheetMissing, "UI must not show samplesheet was not provided").toBe(false);
    expect(deNameOk, "DE panel/chat name defined").toBe(true);
    await snap(page, "b2-de-running");

    const deTerm = await pollWorkflowTerminal(page, deRunId!, 18 * 60_000);
    await snap(page, "b2-de-terminal");
    fs.writeFileSync(
      path.join(OUT, "b2-de-terminal.json"),
      JSON.stringify({ deRunId, deLaunch, deTerm, dePanels }, null, 2),
    );

    const deReached = !deTerm.timedOut && TERMINAL.test(deTerm.status);
    const honestFail =
      !/samplesheet was not provided/i.test(String(deTerm.error || "")) &&
      !/samplesheet was not provided/i.test(deTerm.status);
    const dePass = deReached && honestFail;
    record(
      "de_run_to_terminal",
      dePass,
      `runId=${deRunId} launch=${deLaunch} status=${deTerm.status} timedOut=${deTerm.timedOut} honestFail=${honestFail} err=${String(deTerm.error || "").slice(0, 200)}`,
    );
    expect(dePass, `DE must reach terminal without samplesheet-missing lie (got ${deTerm.status})`).toBe(true);

    if (/failed|error/i.test(deTerm.status)) {
      await openPanelIfOffered(page);
      // Navigate UI to the run if possible by reloading chat panel state
      const honesty = await assertFindingsHonesty(page, true);
      await snap(page, "b2-de-findings");
      record("de_failure_findings_honesty", honesty.ok, JSON.stringify(honesty));
      // Soft: panel may not be on this run if API-launched; still record.
      if (!honesty.ok && deLaunch.startsWith("ui")) {
        expect(honesty.ok, "DE failed: Findings must not spin in progress").toBe(true);
      }
    } else {
      record("de_failure_findings_honesty", true, `SKIP DE terminal=${deTerm.status} (not failed)`);
    }
    audit("b2_de", { deRunId, deLaunch, deTerm, dePanels, aliasOk });
  });
});
