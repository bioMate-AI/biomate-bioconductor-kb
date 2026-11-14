/**
 * FULL end-to-end cold-start matrix — Data analysis + Molecule design & generate.
 *
 * Per example (no mocks):
 *   seed → send → clarify Confirm (panel MUST open) → Confirm & Run
 *   → poll to TERMINAL → After Run tabs (Outputs / Findings / Parameters)
 *   with real content (not stuck "Analysis in progress…" on failure;
 *   Outputs or Findings show substance on success).
 *
 * ONE-WRITER RULE (2026-11-13): never launch raw `npx playwright` for this
 * file from parallel agents — they pkill each other (EXIT 143) and wipe
 * evidence. Always use the flocked runner:
 *
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     ./e2e/run_coldstart_deep.sh
 *   BIOMATE_DEEP_FILTER='^design-rank-' ./e2e/run_coldstart_deep.sh
 *
 * Bypass only with BIOMATE_DEEP_ALLOW_PARALLEL=1 (debug). The suite refuses
 * to start if another process already holds /tmp/biomate_coldstart_deep.lock
 * without going through the runner.
 */
import { test, expect, type Page } from "@playwright/test";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { failedRunContentOk, gradeColdstartDeep } from "./lib/coldstart-deep-grade";
import {
  isHarnessTerminalStatus,
  normalizeRunsListResponse,
  pickRunIdFromExecuteResponse,
  pickRunIdFromRunRow,
  pickRunIdFromSessionPayload,
} from "./lib/coldstart-run-id";

const LOCK_DIR = process.env.BIOMATE_DEEP_LOCK_DIR || "/tmp/biomate_coldstart_deep.lock";
const VIA_RUNNER = process.env.BIOMATE_DEEP_VIA_RUNNER === "1";
const ALLOW_PARALLEL = process.env.BIOMATE_DEEP_ALLOW_PARALLEL === "1";

function assertSingleWriter() {
  if (ALLOW_PARALLEL) return;
  const ownerPath = path.join(LOCK_DIR, "owner");
  const ownerInHold = path.join(LOCK_DIR, "hold", "owner");
  // Hard gate: raw `npx playwright` from parallel agents caused EXIT 143 thrash.
  // Only ./e2e/run_coldstart_deep.sh sets VIA_RUNNER=1 under the mkdir lock.
  if (!VIA_RUNNER) {
    throw new Error(
      `coldstart-analysis-design-deep refused: set BIOMATE_DEEP_VIA_RUNNER=1 via ` +
        `./e2e/run_coldstart_deep.sh (exclusive lock). ` +
        `Override only with BIOMATE_DEEP_ALLOW_PARALLEL=1.`,
    );
  }
  if (!fs.existsSync(ownerPath) && !fs.existsSync(ownerInHold)) {
    throw new Error(
      `BIOMATE_DEEP_VIA_RUNNER=1 but lock owner missing under ${LOCK_DIR} — ` +
        `runner lock was dropped mid-suite.`,
    );
  }
}

assertSingleWriter();

const OUT = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "execshots",
  "coldstart-analysis-design-deep",
);
fs.mkdirSync(OUT, { recursive: true });

const ANSWER_TIMEOUT = 180_000;
const RUN_TIMEOUT = Number(process.env.BIOMATE_DEEP_RUN_TIMEOUT_MS || 45 * 60_000);
// Include paused — sequential pipelines / QC gates pause with a real runId;
// treating paused as non-terminal caused "no runId" soft-timeouts.
const TERMINAL = /completed|succeeded|failed|error|cancelled|canceled|interrupted|paused/i;
const PLACEHOLDER =
  /(?:Preparing the plan|Understanding your goal|Thinking|Analy[sz]ing|Searching|Working on it|Finding|Generating)\b[^\n]{0,80}$|…\s*$/i;

type Modality = "sm" | "pep" | "bio";
type Case =
  | { id: string; module: "analysis"; kind: "track"; track: string; index: number; expectsWorkflow?: boolean }
  | { id: string; module: "analysis"; kind: "domain"; domain: string; index: number; expectsWorkflow?: boolean }
  | { id: string; module: "design"; track: string; modality: Modality; index: number; expectsWorkflow?: boolean };

const ANALYSIS_TRACKS: Record<string, { n: number; expectsWorkflow: boolean }> = {
  "ad-hoc-compute": { n: 3, expectsWorkflow: false },
  "validated-workflows": { n: 3, expectsWorkflow: true },
  "try-sample-data": { n: 14, expectsWorkflow: true },
};
const ANALYSIS_DOMAINS = ["dd", "txn", "gen", "fgen", "str", "prot", "clin"] as const;
const DESIGN_TRACKS: Array<{ track: string; counts: Record<Modality, number> }> = [
  { track: "generate", counts: { sm: 3, pep: 3, bio: 3 } },
  { track: "fold-complex", counts: { sm: 3, pep: 3, bio: 3 } },
  { track: "predict-filter", counts: { sm: 4, pep: 4, bio: 3 } },
  { track: "optimise-properties-one-pass", counts: { sm: 3, pep: 3, bio: 3 } },
  { track: "rank-candidates", counts: { sm: 3, pep: 3, bio: 3 } },
];

const ALL_CASES: Case[] = [
  ...Object.entries(ANALYSIS_TRACKS).flatMap(([track, { n, expectsWorkflow }]) =>
    Array.from({ length: n }, (_, index) => ({
      id: `analysis-${track}-${index}`,
      module: "analysis" as const,
      kind: "track" as const,
      track,
      index,
      expectsWorkflow,
    })),
  ),
  ...ANALYSIS_DOMAINS.flatMap((domain) =>
    [0, 1, 2].map((index) => ({
      id: `analysis-domain-${domain}-${index}`,
      module: "analysis" as const,
      kind: "domain" as const,
      domain,
      index,
      expectsWorkflow: !(domain === "dd" && index === 2),
    })),
  ),
  ...DESIGN_TRACKS.flatMap(({ track, counts }) =>
    (["sm", "pep", "bio"] as Modality[]).flatMap((modality) =>
      Array.from({ length: counts[modality] }, (_, index) => ({
        id: `design-${track}-${modality}-${index}`,
        module: "design" as const,
        track,
        modality,
        index,
        expectsWorkflow: true,
      })),
    ),
  ),
];

const FILTER = process.env.BIOMATE_DEEP_FILTER ? new RegExp(process.env.BIOMATE_DEEP_FILTER) : null;
const CASES = FILTER ? ALL_CASES.filter((c) => FILTER.test(c.id)) : ALL_CASES;
// Keep catalog filename short — long BIOMATE_DEEP_FILTER regexes hit ENAMETOOLONG on macOS.
const catalogTag = FILTER
  ? require("crypto").createHash("sha1").update(FILTER.source).digest("hex").slice(0, 10)
  : "";
fs.writeFileSync(
  path.join(OUT, `catalog${catalogTag ? `-${catalogTag}` : ""}.json`),
  JSON.stringify({ total: CASES.length, filter: FILTER?.source ?? null, cases: CASES.map((c) => c.id) }, null, 2),
);

async function openModule(page: Page, module: "analysis" | "design") {
  await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded" });
  await page.getByTestId("cold-start-dashboard").waitFor({ state: "visible", timeout: 60_000 });
  const card = page.locator(`[data-testid="cold-module-card"][data-module-id="${module}"]`);
  await card.getByTestId("cold-module-expand").click();
  await card.getByTestId("cold-module-body").waitFor({ state: "visible", timeout: 15_000 });
}

async function seedCase(page: Page, c: Case): Promise<{ label: string }> {
  if (c.module === "analysis") {
    if (c.kind === "track") {
      await page.getByTestId(`cold-track-${c.track}`).click();
      const row = page.getByTestId("cold-example").nth(c.index);
      const label = (await row.innerText()).split("\n")[0].trim();
      await row.click();
      return { label };
    }
    await page.getByTestId("cold-track-validated-workflows").click();
    await page.getByTestId(`cold-domain-${c.domain}`).click();
    const row = page.getByTestId("cold-shape").nth(c.index);
    const label = (await row.innerText()).split("\n")[0].trim();
    await row.click();
    return { label };
  }
  await page.getByTestId(`cold-track-${c.track}`).click();
  await page.getByTestId(`cold-modality-${c.modality}`).click();
  const row = page.getByTestId("cold-example").nth(c.index);
  const label = (await row.innerText()).split("\n")[0].trim();
  await row.click();
  return { label };
}

async function waitForAssistantSettled(page: Page) {
  await page.locator('[data-role="assistant"]').last().waitFor({ state: "visible", timeout: ANSWER_TIMEOUT });
  const ready = page.locator(
    '[data-testid="button-run-workflow-panel"], [data-testid="workflow-right-panel"], [data-testid="clarify-card"], [data-testid="workflow-artifact-panel"]',
  );
  const deadline = Date.now() + ANSWER_TIMEOUT;
  let last = "",
    stableSince = Date.now();
  while (Date.now() < deadline) {
    const now = (await page.locator('[data-role="assistant"]').allInnerTexts()).join("\n");
    if (now !== last) {
      last = now;
      stableSince = Date.now();
    }
    const busy =
      (await page.getByTestId("chat-stop-button").count()) > 0 || PLACEHOLDER.test(now.trim());
    if ((await ready.count()) > 0 && !busy) break;
    if (!busy && Date.now() - stableSince > 20_000) break;
    await page.waitForTimeout(2_000);
  }
}

async function pollWorkflowMeta(page: Page, sessionId?: string) {
  if (!sessionId) return { names: [] as string[], runId: undefined as string | undefined };
  let names: string[] = [];
  let runId: string | undefined;
  for (let i = 0; i < 18; i++) {
    const res = await page.request.get(`${BASE_URL}/api/sessions/${sessionId}`);
    if (res.ok()) {
      const session = await res.json();
      const msgs: any[] = session.messages ?? [];
      for (const m of msgs) {
        if (m.role !== "assistant") continue;
        const wf = m.metadata?.workflow;
        if (wf) {
          names.push(String(wf.name ?? wf.display_name ?? wf.workflow_type ?? "unnamed"));
        }
      }
      runId = runId || pickRunIdFromSessionPayload(session);
      if (names.length) break;
    }
    await page.waitForTimeout(5_000);
  }
  return { names, runId };
}

async function clarifyOpenPanel(page: Page, shotPrefix: string) {
  const card = page.getByTestId("clarify-card");
  if ((await card.count()) === 0) return { hadClarify: false as const, panelVisible: false };
  for (let step = 0; step < 8; step++) {
    const next = page.getByTestId("clarify-next");
    if ((await next.count()) === 0) break;
    const label = ((await next.innerText()) || "").trim();
    await next.click();
    if (/confirm/i.test(label)) break;
    await page.waitForTimeout(400);
  }
  await page.screenshot({ path: path.join(OUT, `${shotPrefix}-after-confirm.png`), fullPage: true }).catch(() => {});
  const visible =
    (await page.getByTestId("workflow-right-panel").first().isVisible().catch(() => false)) ||
    (await page.getByTestId("button-run-workflow-panel").first().isVisible().catch(() => false)) ||
    (await page.getByTestId("workflow-artifact-panel").first().isVisible().catch(() => false));
  return { hadClarify: true as const, panelVisible: visible };
}

async function ensurePanelOpen(page: Page) {
  if (await page.getByTestId("button-run-workflow-panel").first().isVisible().catch(() => false)) return true;
  if (await page.getByTestId("workflow-right-panel").first().isVisible().catch(() => false)) return true;
  const chip = page.locator('[data-testid="wf-chip"], [data-testid="workflow-chip"], .wf-chip').first();
  if (await chip.isVisible().catch(() => false)) {
    await chip.click().catch(() => {});
    await page.waitForTimeout(1000);
  }
  return (
    (await page.getByTestId("button-run-workflow-panel").first().isVisible().catch(() => false)) ||
    (await page.getByTestId("workflow-right-panel").first().isVisible().catch(() => false))
  );
}

/** Confirm anyway / fix paths — try to launch when blocked on missing required. */
async function clickConfirmAndRun(page: Page) {
  const confirm = page
    .getByTestId("button-run-workflow-panel")
    .or(page.getByRole("button", { name: /confirm\s*&?\s*run/i }));
  if ((await confirm.count()) === 0) return { clicked: false as const, reason: "no confirm button" };

  const btn = confirm.first();
  const disabled =
    (await btn.isDisabled().catch(() => false)) ||
    (await btn.getAttribute("aria-disabled").catch(() => null)) === "true";

  if (disabled) {
    // Do NOT force-click or Confirm-anyway for blocked required inputs (Cryo Movies
    // Path, etc.) — that manufactures the same execution error every run and
    // pollutes measurement. Record blocked-required as the real outcome.
    return { clicked: false as const, reason: "confirm_blocked_required" };
  }
  await btn.click();
  return { clicked: true as const, reason: "confirm" };
}

async function extractRunId(page: Page, sessionId?: string): Promise<string | undefined> {
  // Badge / panel root / URL
  const fromDom =
    (await page
      .locator('[data-testid="workflow-artifact-panel"][data-run-id], [data-testid="workflow-overall-status-badge"][data-run-id], [data-run-id]')
      .first()
      .getAttribute("data-run-id")
      .catch(() => null)) ||
    (await page.locator("[data-testid='workflow-run-id']").first().textContent().catch(() => null));
  if (fromDom?.trim()) return fromDom.trim();

  const url = page.url();
  const m = url.match(/run[s]?[/=]([0-9a-f-]{36})/i);
  if (m) return m[1];

  // Poll session + runs API (server returns a bare array — not {runs:[...]}).
  for (let i = 0; i < 30; i++) {
    if (sessionId) {
      const res = await page.request.get(`${BASE_URL}/api/sessions/${sessionId}`);
      if (res.ok()) {
        const fromSession = pickRunIdFromSessionPayload(await res.json().catch(() => null));
        if (fromSession) return fromSession;
      }
      const bySession = await page.request
        .get(`${BASE_URL}/api/workflows/runs?limit=5&chatSessionId=${encodeURIComponent(sessionId)}`)
        .catch(() => null);
      if (bySession?.ok()) {
        const list = normalizeRunsListResponse(await bySession.json().catch(() => null));
        const id = pickRunIdFromRunRow(list[0]);
        if (id) return id;
      }
    }
    const runs = await page.request.get(`${BASE_URL}/api/workflows/runs?limit=5`).catch(() => null);
    if (runs?.ok()) {
      const list = normalizeRunsListResponse(await runs.json().catch(() => null));
      const id = pickRunIdFromRunRow(list[0]);
      if (id) return id;
    }
    await page.waitForTimeout(2_000);
  }
  return undefined;
}

async function pollRunTerminal(page: Page, runId: string) {
  const deadline = Date.now() + RUN_TIMEOUT;
  let last = "";
  let error = "";
  while (Date.now() < deadline) {
    const res = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}`);
    if (res.ok()) {
      const j = await res.json().catch(() => ({}));
      // ExecutionRun nests status under execution.status
      last = String(
        j.status || j.state || j.run_status || j.execution?.status || "",
      ).toLowerCase();
      error = String(
        j.error || j.error_message || j.message || j.execution?.errorMessage || "",
      ).slice(0, 500);
      if (isHarnessTerminalStatus(last)) return { status: last, error, timedOut: false as const };
    }
    // UI badge as backup
    const badge = await page
      .locator('[data-testid="workflow-overall-status-badge"]')
      .first()
      .getAttribute("data-status")
      .catch(() => null);
    if (badge && isHarnessTerminalStatus(badge)) return { status: badge, error, timedOut: false as const };
    await page.waitForTimeout(8_000);
  }
  return { status: last || "unknown", error, timedOut: true as const };
}

async function auditAfterRunTabs(page: Page, runFailed: boolean) {
  // Prefer explicit After Run tab
  const afterTab = page.locator('[data-testid="panel-tab-after-run"]').first();
  if ((await afterTab.count()) > 0) {
    await afterTab.click({ timeout: 8_000 }).catch(() => {});
    await page.waitForTimeout(1500);
  }

  const tabs = {
    outputs: page.locator('[data-testid="after-tab-outputs"], button:has-text("Outputs")').first(),
    findings: page.locator('[data-testid="after-tab-findings"], button:has-text("Findings")').first(),
    parameters: page.locator('[data-testid="after-tab-parameters"], button:has-text("Parameters")').first(),
  };

  const tabResults: Record<string, { visible: boolean; clicked: boolean; text: string }> = {};
  for (const [name, loc] of Object.entries(tabs)) {
    const visible = await loc.isVisible().catch(() => false);
    let clicked = false;
    if (visible) {
      await loc.click().catch(() => {});
      await page.waitForTimeout(800);
      clicked = true;
    }
    const panelText =
      (await page.getByTestId("workflow-right-panel").innerText().catch(() => "")) ||
      (await page.getByTestId("workflow-artifact-panel").innerText().catch(() => "")) ||
      (await page.locator("body").innerText().catch(() => ""));
    tabResults[name] = { visible, clicked, text: panelText.slice(0, 2500) };
  }

  const findingsBody = tabResults.findings?.text || "";
  const outputsBody = tabResults.outputs?.text || "";
  const paramsBody = tabResults.parameters?.text || "";

  // Diagnosis banner alone is NOT tab content — prior audits marked outputs/findings/params
  // all Ok from the same truncated RUN FAILED strip without ever opening Findings.
  const diagnosisOnly =
    /RUN FAILED|AI diagnosis|The run stopped before completing/i.test(outputsBody) &&
    !/\.(csv|pdf|png|tsv|html|sdf|pdb)\b/i.test(outputsBody) &&
    !/Download report|Key Results/i.test(outputsBody);

  const failSnippetMatch = (outputsBody + "\n" + findingsBody).match(
    /RUN FAILED[\s\S]{0,400}|Process \w[\w:/\- ]{0,80} failed:[\s\S]{0,300}|ERROR:[^\n]{0,240}/i,
  );
  const failSnippet = (failSnippetMatch?.[0] || "").replace(/\s+/g, " ").trim().slice(0, 400);

  const stuckInProgress =
    /Analysis in progress|Analyzing outputs/i.test(findingsBody) &&
    (await page.locator('[data-testid="findings-loading"]').isVisible().catch(() => false));

  const findingsOk = runFailed
    ? !!tabResults.findings?.clicked &&
      !/Analysis in progress/i.test(findingsBody) &&
      !stuckInProgress &&
      (/Analysis not available|did not complete|failed|error|RUN FAILED/i.test(findingsBody) ||
        findingsBody.length > 40)
    : !!tabResults.findings?.clicked &&
      (/Download report|Key Results|summary|Finding|result|metric|score|gene|compound/i.test(findingsBody) ||
        findingsBody.length > 80);

  const outputsOk =
    !!tabResults.outputs?.clicked &&
    !diagnosisOnly &&
    (/\.(csv|pdf|png|tsv|html|sdf|pdb)\b|No output|download|bytes|\d+\s*B\b/i.test(outputsBody) ||
      (/output|file/i.test(outputsBody) && outputsBody.length > 80));

  const paramsOk =
    !!tabResults.parameters?.clicked &&
    (/param|SMILES|input|genome|threshold|value|setting/i.test(paramsBody) || paramsBody.length > 40);

  // After-run shell present?
  const afterShell =
    (await afterTab.isVisible().catch(() => false)) ||
    tabResults.outputs.visible ||
    tabResults.findings.visible ||
    /After run|Outputs|Findings/i.test(
      (await page.getByTestId("workflow-right-panel").innerText().catch(() => "")) || "",
    );

  return {
    afterShell,
    diagnosisOnly,
    failSnippet,
    findingsOk,
    outputsOk,
    paramsOk,
    stuckInProgress,
    tabResults: {
      outputs: {
        visible: tabResults.outputs.visible,
        clicked: tabResults.outputs.clicked,
        head: outputsBody.slice(0, 400),
      },
      findings: {
        visible: tabResults.findings.visible,
        clicked: tabResults.findings.clicked,
        head: findingsBody.slice(0, 400),
      },
      parameters: {
        visible: tabResults.parameters.visible,
        clicked: tabResults.parameters.clicked,
        head: paramsBody.slice(0, 400),
      },
    },
  };
}

test.describe.configure({ mode: "parallel" });

test("catalog layout matches filter slice", async ({ page }) => {
  test.skip(!!FILTER && CASES.length === 0, "filter matched zero cases");
  await loginAsFixture(page);
  if (!FILTER || FILTER.test("analysis-")) {
    await openModule(page, "analysis");
    for (const [track, { n }] of Object.entries(ANALYSIS_TRACKS)) {
      if (FILTER && !FILTER.test(`analysis-${track}`)) continue;
      await page.getByTestId(`cold-track-${track}`).click();
      if (track !== "validated-workflows") {
        await expect(page.getByTestId("cold-example"), track).toHaveCount(n);
      }
    }
  }
  if (!FILTER || FILTER.test("design-")) {
    await openModule(page, "design");
    for (const { track, counts } of DESIGN_TRACKS) {
      if (FILTER && !FILTER.test(`design-${track}`)) continue;
      await page.getByTestId(`cold-track-${track}`).click();
      for (const mod of ["sm", "pep", "bio"] as Modality[]) {
        await page.getByTestId(`cold-modality-${mod}`).click();
        await expect(page.getByTestId("cold-example"), `${track}/${mod}`).toHaveCount(counts[mod]);
      }
    }
  }
});

for (const c of CASES) {
  test(`e2e ${c.id}`, async ({ page }) => {
    test.setTimeout(ANSWER_TIMEOUT + RUN_TIMEOUT + 120_000);
    await loginAsFixture(page);
    await openModule(page, c.module);

    const sent: { url: string; body: string }[] = [];
    page.on("request", (req) => {
      if (req.method() === "POST" && /chat|stream|upload|files|nextflow|execute|run/.test(req.url())) {
        sent.push({ url: req.url(), body: (req.postData() || "").slice(0, 4000) });
      }
    });

    const { label } = await seedCase(page, c);
    const composer = page.getByTestId("chat-input");
    await expect(composer).not.toHaveValue("", { timeout: 90_000 });
    const prompt = await composer.inputValue();
    await page.screenshot({ path: path.join(OUT, `${c.id}-seeded.png`) }).catch(() => {});

    await page.getByTestId("chat-send-button").click();
    await waitForAssistantSettled(page);

    const answer = (await page.locator('[data-role="assistant"]').allInnerTexts()).join("\n---\n");
    const chatReq = sent.find((x) => /\/api\/chat\/stream/.test(x.url));
    const sessionId = chatReq
      ? (() => {
          try {
            return JSON.parse(chatReq.body).context?.sessionId as string | undefined;
          } catch {
            return chatReq.body.match(/"sessionId":"([^"]+)"/)?.[1];
          }
        })()
      : undefined;

    const clarify = await clarifyOpenPanel(page, c.id);
    await ensurePanelOpen(page);
    const meta = await pollWorkflowMeta(page, sessionId);

    // Instant / ad-hoc: may never show Confirm & Run — still require a settled answer.
    const isInstant = c.module === "analysis" && c.kind === "track" && c.track === "ad-hoc-compute";

    let launch = { clicked: false as boolean, reason: "skipped" };
    let runId: string | undefined;
    let term = { status: "n/a", error: "", timedOut: false as boolean };
    let after: Awaited<ReturnType<typeof auditAfterRunTabs>> | null = null;

    if (!isInstant && (c.expectsWorkflow !== false || meta.names.length || clarify.hadClarify)) {
      const panelOk = await ensurePanelOpen(page);
      expect.soft(panelOk || clarify.panelVisible, `panel never opened for ${c.id}`).toBe(true);

      if (clarify.hadClarify) {
        expect.soft(clarify.panelVisible, `Confirm and configure left panel closed (${c.id})`).toBe(true);
      }

      // Capture execute / chain / pipeline POST so runId is available even when
      // DOM / session sync lag (product now also sets data-run-id).
      const executeWait = page
        .waitForResponse(
          (r) =>
            r.request().method() === "POST" &&
            /\/api\/workflows\/(execute|chain|pipeline)/i.test(r.url()) &&
            r.status() < 500,
          { timeout: 90_000 },
        )
        .catch(() => null);

      launch = await clickConfirmAndRun(page);
      await page.screenshot({ path: path.join(OUT, `${c.id}-launched.png`), fullPage: true }).catch(() => {});

      if (launch.clicked) {
        // Wait for running / terminal / paused badge OR execute response (whichever first)
        const runDeadline = Date.now() + 90_000;
        let badgeAfterConfirm: string | null = null;
        while (Date.now() < runDeadline) {
          if (!runId) {
            const settled = await Promise.race([
              executeWait.then((r) => ({ kind: "exec" as const, r })),
              page.waitForTimeout(500).then(() => ({ kind: "tick" as const, r: null })),
            ]);
            if (settled.kind === "exec" && settled.r) {
              const body = await settled.r.json().catch(() => null);
              runId = pickRunIdFromExecuteResponse(body) || runId;
            }
          }
          badgeAfterConfirm = await page
            .locator('[data-testid="workflow-overall-status-badge"]')
            .first()
            .getAttribute("data-status")
            .catch(() => null);
          if (badgeAfterConfirm === "running" || isHarnessTerminalStatus(badgeAfterConfirm) || runId) break;
          // Confirm still showing + idle near end → launch never started
          const confirmStill =
            (await page.getByTestId("button-run-workflow-panel").count().catch(() => 0)) > 0;
          if (confirmStill && (!badgeAfterConfirm || badgeAfterConfirm === "idle") && Date.now() > runDeadline - 15_000) {
            break;
          }
          await page.waitForTimeout(2_500);
        }

        runId = runId || (await extractRunId(page, sessionId)) || meta.runId;

        // Honest measurement: Confirm clicked but panel stayed idle and no runId
        // → not a soft-pass "completed" path; treat as launch no-op.
        const stillIdle =
          !runId &&
          (!badgeAfterConfirm || badgeAfterConfirm === "idle") &&
          (await page.getByTestId("button-run-workflow-panel").count().catch(() => 0)) > 0;
        if (stillIdle) {
          launch = { clicked: false, reason: "confirm_noop" };
          term = { status: "n/a", error: "confirm_noop_no_run", timedOut: false };
        } else if (runId) {
          term = await pollRunTerminal(page, runId);
        } else {
          // Poll UI badge only (shorter — do not burn 20m on missing plumbing)
          const uiDeadline = Date.now() + Math.min(RUN_TIMEOUT, 5 * 60_000);
          while (Date.now() < uiDeadline) {
            const badge = await page
              .locator('[data-testid="workflow-overall-status-badge"]')
              .first()
              .getAttribute("data-status")
              .catch(() => null);
            if (badge && isHarnessTerminalStatus(badge)) {
              term = { status: badge, error: "", timedOut: false };
              // Late DOM surfacing of data-run-id
              runId = (await extractRunId(page, sessionId)) || runId;
              break;
            }
            await page.waitForTimeout(8_000);
          }
          if (!isHarnessTerminalStatus(term.status)) {
            term = { status: term.status || "unknown", error: "no runId", timedOut: true };
          }
        }

        await page.screenshot({ path: path.join(OUT, `${c.id}-terminal.png`), fullPage: true }).catch(() => {});

        if (launch.clicked) {
          const failed = /fail|error/i.test(term.status);
          after = await auditAfterRunTabs(page, failed);
          // API often leaves error empty — promote After Run fail strip into terminal.error
          if (failed && !term.error && after?.failSnippet) {
            term = { ...term, error: after.failSnippet };
          }
          await page.screenshot({ path: path.join(OUT, `${c.id}-after-run.png`), fullPage: true }).catch(() => {});
        }
      }
    }

    const buildInfo = await page
      .request.get(`${BASE_URL}/build-info.json`)
      .then(async (r) => (r.ok() ? await r.json() : null))
      .catch(() => null);

    const result = {
      id: c.id,
      label,
      prompt: prompt.slice(0, 500),
      sessionId,
      workflowNames: meta.names,
      answerHead: answer.slice(0, 3000),
      clarify,
      launch,
      runId,
      terminal: term,
      after,
      buildInfo,
      timedOutInProgress: PLACEHOLDER.test(answer.trim().slice(-160)),
    };
    // Use-case grade (2026-11-13 audit): do NOT treat honest-fail / wrong-route as PASS.
    const wfJoined = meta.names.join(" ");
    const promptAsName =
      meta.names.length > 0 &&
      meta.names.some((n) => n.length > 40 && prompt.toLowerCase().includes(n.slice(0, 30).toLowerCase()));
    const chatMissingLie =
      /completed/i.test(term.status) && /missing.*(data|file|input)|Findings are not available yet/i.test(answer);
    const wrongRoute =
      /binding affinity|dock|pose/i.test(label + prompt) && /cro submission|wuxi/i.test(wfJoined);
    const useCasePass =
      launch.clicked &&
      /completed|succeeded/i.test(term.status) &&
      !!after?.afterShell &&
      !!after?.outputsOk &&
      !after?.stuckInProgress &&
      !promptAsName &&
      !chatMissingLie &&
      !wrongRoute &&
      meta.names.length > 0 &&
      !/\bundefined\b/i.test(wfJoined);
    const grade = gradeColdstartDeep({
      launch,
      terminal: term,
      after,
      useCasePass,
    });
    (result as any).grade = grade;
    (result as any).useCasePass = useCasePass;
    // Never upgrade truncated UI into a specific root-cause string in the grade field.
    (result as any).errorObserved = (term.error || after?.failSnippet || "").slice(0, 400);
    fs.writeFileSync(path.join(OUT, `${c.id}.json`), JSON.stringify(result, null, 2));

    expect.soft(answer.trim().length + meta.names.join("").length, "empty response").toBeGreaterThan(40);
    expect.soft(result.timedOutInProgress, "still preparing").toBe(false);
    expect.soft(answer + meta.names.join(" "), "undefined").not.toMatch(/\bundefined\b/i);

    if (isInstant) {
      // Instant path: non-empty settled answer is the deliverable (no After Run shell).
      expect.soft(answer.trim().length, "instant empty").toBeGreaterThan(80);
      return;
    }

    if (c.expectsWorkflow) {
      expect
        .soft(
          meta.names.length > 0 || clarify.hadClarify || /license|credential|upload|attach/i.test(answer),
          `no workflow/clarify for ${c.id}`,
        )
        .toBe(true);
      expect.soft(promptAsName, `workflow name is the user prompt (${c.id})`).toBe(false);
      expect.soft(wrongRoute, `wrong workflow for intent (${c.id}: ${wfJoined})`).toBe(false);
    }

    if (launch.clicked) {
      expect.soft(term.timedOut, `run did not reach terminal (${c.id})`).toBe(false);
      expect.soft(TERMINAL.test(term.status), `non-terminal status ${term.status}`).toBe(true);
      expect.soft(after?.afterShell, `After Run shell missing (${c.id})`).toBe(true);
      expect.soft(after?.stuckInProgress, `Findings stuck spinning (${c.id})`).toBe(false);
      if (/fail|error/i.test(term.status)) {
        // Findings tab is often absent on failed runs; fail strip on Outputs is enough.
        expect.soft(failedRunContentOk(after), `failed-run After Run empty (${c.id})`).toBe(true);
        expect.soft(useCasePass, `failed run must not grade REAL_PASS (${c.id})`).toBe(false);
        expect.soft(grade === "HONEST_FAIL" || grade === "DISHONEST_FAIL", `failed grade (${c.id})`).toBe(true);
      } else {
        const contentOk = !!(after && (after.outputsOk || after.findingsOk || after.paramsOk));
        expect.soft(contentOk, `After Run tabs empty/wrong (${c.id})`).toBe(true);
      }
      if (/completed|succeeded/i.test(term.status) && c.expectsWorkflow !== false) {
        expect.soft(useCasePass, `completed but not a real use-case pass (${c.id} grade=${grade})`).toBe(true);
        expect.soft(chatMissingLie, `chat says missing inputs while completed (${c.id})`).toBe(false);
        expect.soft(!!after?.tabResults?.findings?.visible, `Findings tab never opened (${c.id})`).toBe(true);
      }
    } else if (c.expectsWorkflow !== false) {
      const bodyText = answer + (await page.locator("body").innerText().catch(() => ""));
      const blockedHonest =
        launch.reason === "confirm_blocked_required" ||
        launch.reason === "confirm_noop" ||
        /license|credential|402|quota|subscribe|Movies Path|missing required|Fix now|required param|Cannot start this workflow|Cannot run yet/i.test(
          bodyText,
        );
      expect
        .soft(blockedHonest, `never launched and no honest block UI (${c.id}): ${launch.reason}`)
        .toBe(true);
      // BLOCKED_REQUIRED is a valid measured outcome — do not treat as launch failure.
      if (launch.reason === "confirm_blocked_required") {
        expect.soft(grade === "BLOCKED_REQUIRED", `expected BLOCKED_REQUIRED (${c.id})`).toBe(true);
      }
      if (launch.reason === "confirm_noop") {
        expect.soft(grade === "NO_LAUNCH", `expected NO_LAUNCH for confirm_noop (${c.id})`).toBe(true);
      }
    }
  });
}
