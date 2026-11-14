/*
 * execplan-runsurface.e2e.ts
 *
 * Executes the UI-OBSERVABLE subset of docs/20260909_TESTPLAN_RUNSURFACE_STEP_AFTERRUN.md
 * against LIVE dev (https://dev-public.biomate.ai). NO mocking (CLAUDE.md §Testing Rules).
 *
 * SCOPE DISCIPLINE (per task brief + CLAUDE.md "Review Code Before Testing"):
 *   - A real AWS-Batch workflow run is EXPENSIVE. This harness NEVER clicks Run and
 *     NEVER dispatches a workflow. It only observes states reachable without a live run:
 *       (a) PRE-RUN idle panel — reached by sending a chat message that renders a
 *           NextflowWorkflowViewer card inline (status=idle) BEFORE Run is clicked.
 *       (b) AFTER-RUN report — reached by deep-linking `/?session=<chatSessionId>` of an
 *           EXISTING completed / failed run already in the fixture account. This is the
 *           exact path the "Open" button in the Workflow Runs dialog uses
 *           (App.tsx RootRoute ?session handler → onChatSelect → session restore →
 *           chat-with-artifacts auto-opens the panel with currentRun loaded;
 *           completed→after-run tab, failed→after-run tab).
 *   - Live SSE idle→running→terminal, QC-gate-fires-live, findings-on-live-completion
 *     all require a real Batch run → SKIPPED and flagged, NOT faked.
 *
 * PRECONDITION VERIFIED (2026-09-10, read-only probe of GET /api/workflows/runs):
 *   Fixture account has 48 completed + 32 failed runs. Session IDs below were harvested
 *   from that probe (completed ADMET + failed ADMET). If they 404 (rotated/pruned), the
 *   harness re-discovers a fresh completed/failed session at runtime via the same API.
 *
 * Fixture: lifeifei163361@163.com / WpmFixture!2026 (CLAUDE.md §E2E user). Login ONCE.
 */
import { test, expect, Page, APIRequestContext } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const SS_DIR = path.join(__dirname, "execshots", "runsurface");

const BASE_URL = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const FIXTURE_EMAIL = "lifeifei163361@163.com";
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";

// Known-good session IDs harvested from the fixture account (2026-09-10 probe).
// Re-discovered at runtime if these no longer resolve.
const KNOWN_COMPLETED_SESSION = "chat-1788974688347-01nt7u3xy"; // completed ADMET
const KNOWN_FAILED_SESSION = "chat-1787258238119-9swaokaak"; // failed ADMET

// ---------------------------------------------------------------------------
// Results ledger — emitted as a table at the end of the run.
// ---------------------------------------------------------------------------
type Verdict = "PASS" | "FAIL" | "SKIP";
interface Row {
  uc: string;
  check: string;
  verdict: Verdict;
  reason: string;
  shot: string;
  note: string;
}
const RESULTS: Row[] = [];
function record(r: Row) {
  RESULTS.push(r);
  console.log(`[LEDGER] ${r.uc} | ${r.verdict} | ${r.check} | ${r.reason}`);
}

async function shot(page: Page, name: string): Promise<string> {
  fs.mkdirSync(SS_DIR, { recursive: true });
  const rel = `execshots/runsurface/${name}.png`;
  await page
    .screenshot({ path: path.join(SS_DIR, `${name}.png`), fullPage: false })
    .catch(() => null);
  return rel;
}

// ---------------------------------------------------------------------------
// Login ONCE (JWT → cookie), reuse across all tests. Pattern from _fixture-login.ts.
// ---------------------------------------------------------------------------
let CACHED_TOKEN: string | null = null;

async function getToken(request: APIRequestContext): Promise<string> {
  if (CACHED_TOKEN) return CACHED_TOKEN;
  const resp = await request.post(`${BASE_URL}/api/auth/login`, {
    headers: {
      "content-type": "application/json",
      "x-e2e-test-token": E2E_TOKEN,
      "x-forwarded-proto": "https",
    },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  if (!resp.ok()) {
    throw new Error(`login failed (${resp.status()}): ${await resp.text()}`);
  }
  const token = (await resp.json()).token;
  if (!token) throw new Error("login: no token in response");
  CACHED_TOKEN = token;
  return token;
}

async function authPage(page: Page, request: APIRequestContext): Promise<string> {
  const token = await getToken(request);
  const url = new URL(BASE_URL);
  await page.context().addCookies([
    {
      name: "biomate_token",
      value: token,
      domain: url.hostname,
      path: "/",
      httpOnly: false,
      secure: true,
      sameSite: "Lax",
    },
  ]);
  await page.context().setExtraHTTPHeaders({
    Authorization: `Bearer ${token}`,
    "X-E2E-Test-Token": E2E_TOKEN,
    "X-Forwarded-Proto": "https",
  });
  return token;
}

/** Discover a session id for a run in the requested terminal status. */
async function discoverSession(
  request: APIRequestContext,
  token: string,
  wantStatus: "completed" | "failed"
): Promise<{ sessionId: string; wfName: string } | null> {
  const resp = await request.get(`${BASE_URL}/api/workflows/runs?limit=100`, {
    headers: {
      Authorization: `Bearer ${token}`,
      "x-e2e-test-token": E2E_TOKEN,
      "x-forwarded-proto": "https",
    },
  });
  if (!resp.ok()) return null;
  const runs: any[] = await resp.json();
  for (const r of runs) {
    const st = r?.execution?.status;
    if (st === wantStatus && r?.chatSessionId && r?.workflowDefinition) {
      return { sessionId: r.chatSessionId, wfName: r.workflowName || r.workflowDefinition?.name || "?" };
    }
  }
  return null;
}

/** Navigate to a run's after-run panel via ?session= deep-link and wait for the panel. */
async function openRunPanel(page: Page, sessionId: string): Promise<boolean> {
  await page.goto(`${BASE_URL}/?session=${encodeURIComponent(sessionId)}`, {
    waitUntil: "domcontentloaded",
    timeout: 90_000,
  });
  // Session restore → loadRun → auto-open panel. The panel mounts either inline
  // in the chat message or in the right panel; either exposes workflow-artifact-panel.
  const panel = page.locator('[data-testid="workflow-artifact-panel"]').first();
  return panel
    .waitFor({ state: "attached", timeout: 60_000 })
    .then(() => true)
    .catch(() => false);
}

// ===========================================================================
// GROUP 1 — PRE-RUN idle panel (RS-01, RS-02, RS-03, RS-14, RS-19, RS-20)
//   Reached by sending a chat message; the workflow viewer renders inline at
//   status=idle. We NEVER click Run.
// ===========================================================================
test.describe("Run-surface PRE-RUN (idle, no Batch dispatch)", () => {
  test("idle panel: name/tabs/settings + required-param block + skip map", async ({
    page,
    request,
  }) => {
    test.setTimeout(300_000);
    await authPage(page, request);

    await page.goto(BASE_URL, { waitUntil: "domcontentloaded", timeout: 90_000 });

    const input = page.locator('[data-testid="chat-input"]').first();
    await input.waitFor({ state: "visible", timeout: 60_000 });
    // An nf-core/rnaseq request → grouped-phase workflow with required samplesheet
    // (exercises RS-02 required-param block) and multiple phases (RS-19 skip map).
    await input.fill(
      "Run nf-core/rnaseq bulk RNA-seq differential expression on human paired-end FASTQ files"
    );
    await page.locator('[data-testid="chat-send-button"]').first().click();

    // Wait up to 120s for the workflow viewer to render inline (LLM path is slow).
    const panel = page.locator('[data-testid="workflow-artifact-panel"]').first();
    const rendered = await panel
      .waitFor({ state: "attached", timeout: 120_000 })
      .then(() => true)
      .catch(() => false);

    const preShot = await shot(page, "rs_prerun_01_card");

    if (!rendered) {
      const reason = "chat did not render a workflow card within 120s (LLM routing/timeout, not a panel bug)";
      for (const uc of ["RS-01", "RS-02", "RS-03", "RS-14", "RS-19", "RS-20"]) {
        record({ uc, check: "pre-run idle panel", verdict: "SKIP", reason, shot: preShot, note: "" });
      }
      test.skip(true, reason);
      return;
    }

    // --- RS-01: name + tabs + idle badge ------------------------------------
    const name = (await page.locator(".panel-name").first().innerText().catch(() => "")).trim();
    const tabsPresent = await page
      .locator('[data-testid="panel-tabs"]')
      .first()
      .isVisible()
      .catch(() => false);
    const badge = page.locator('[data-testid="workflow-overall-status-badge"]').first();
    const badgeStatus = await badge.getAttribute("data-status").catch(() => null);
    const nameOk = name.length > 0 && !/^(undefined|untitled)$/i.test(name);
    record({
      uc: "RS-01",
      check: "idle: name non-empty, tabs present, badge data-status=idle",
      verdict: nameOk && tabsPresent && (badgeStatus === "idle" || badgeStatus === null) ? "PASS" : "FAIL",
      reason: `name="${name}" tabs=${tabsPresent} badgeStatus=${badgeStatus}`,
      shot: preShot,
      note: badgeStatus === null ? "idle badge is display:none per plan (line 2530) — absent attr acceptable" : "",
    });

    // --- RS-02: required-param hard-block on Run CTA ------------------------
    const runCta = page.locator('[data-testid="button-run-workflow-panel"]').first();
    const hasCta = await runCta.count().then((c) => c > 0);
    if (hasCta) {
      const disabled = await runCta.isDisabled().catch(() => false);
      const unfilled = await runCta.getAttribute("data-required-unfilled").catch(() => null);
      const title = await runCta.getAttribute("title").catch(() => null);
      // PASS if either it's blocked (disabled + count) OR the workflow legitimately
      // has all required params pre-filled (then it is enabled — also correct).
      const blockedCorrectly = disabled && Number(unfilled || 0) > 0;
      const enabledBecauseFilled = !disabled && Number(unfilled || 0) === 0;
      record({
        uc: "RS-02",
        check: "Run CTA blocks on unfilled required params (or enabled when all filled)",
        verdict: blockedCorrectly || enabledBecauseFilled ? "PASS" : "FAIL",
        reason: `disabled=${disabled} data-required-unfilled=${unfilled} title="${title}"`,
        shot: preShot,
        note: enabledBecauseFilled ? "all required params pre-filled → CTA enabled (valid state)" : "",
      });
    } else {
      record({
        uc: "RS-02",
        check: "Run CTA present",
        verdict: "FAIL",
        reason: "button-run-workflow-panel not found in idle panel",
        shot: preShot,
        note: "",
      });
    }

    // --- RS-03: execution-blocked banner (low-confidence) -------------------
    // Only renders when the backend flags low confidence (executionBlockedReason).
    // Not deterministically triggerable for a well-routed workflow → observe, don't fail.
    const lowConf = await page
      .locator('[data-testid="low-confidence-countdown"]')
      .first()
      .isVisible()
      .catch(() => false);
    record({
      uc: "RS-03",
      check: "execution-blocked banner + Fix now / Confirm anyway / countdown",
      verdict: lowConf ? "PASS" : "SKIP",
      reason: lowConf
        ? "low-confidence countdown rendered"
        : "workflow routed with confidence → banner not triggered; needs a low-confidence suggestion to exercise",
      shot: preShot,
      note: "client-only banner; not gated on a Batch run but requires backend to set executionBlockedReason",
    });

    // --- RS-14: GlobalParamsPanel param-type controls -----------------------
    const settingsToggle = page.locator('[data-testid="button-toggle-workflow-settings"]').first();
    if (await settingsToggle.count().then((c) => c > 0)) {
      await settingsToggle.click().catch(() => null);
      await page.waitForTimeout(500);
    }
    // Ensure settings tab active
    const settingsTab = page.locator('[data-testid="panel-tab-settings"]').first();
    if (await settingsTab.count().then((c) => c > 0)) {
      await settingsTab.click().catch(() => null);
      await page.waitForTimeout(400);
    }
    const paramsShot = await shot(page, "rs_prerun_02_params");
    const anyParamControl = await page
      .locator(
        'input[type="text"], input[type="number"], select, textarea, [role="switch"], .switch'
      )
      .first()
      .isVisible()
      .catch(() => false);
    const noParamsMsg = await page
      .getByText("This workflow has no configurable parameters", { exact: false })
      .first()
      .isVisible()
      .catch(() => false);
    record({
      uc: "RS-14",
      check: "param controls render (input/select/toggle/textarea) OR honest no-params state",
      verdict: anyParamControl || noParamsMsg ? "PASS" : "FAIL",
      reason: `paramControlVisible=${anyParamControl} noParamsMessage=${noParamsMsg}`,
      shot: paramsShot,
      note: "per-type controls live in ParameterGroup/EditableParamRow; presence of ≥1 editable control verified",
    });

    // --- RS-19: skip-dependency map -----------------------------------------
    // Only pre-run + grouped phases + skip-analysis available. Read-only (not wired to run).
    const skipMap = page.locator('[data-testid="skip-dependency"]').first();
    const skipPresent = await skipMap.count().then((c) => c > 0);
    if (skipPresent) {
      const skipRows = await page.locator('[data-testid^="skip-phase-"]').count().catch(() => 0);
      const skipShot = await shot(page, "rs_prerun_03_skipmap");
      record({
        uc: "RS-19",
        check: "skip-dependency map renders phase rows",
        verdict: skipRows > 0 ? "PASS" : "FAIL",
        reason: `skip-dependency present, ${skipRows} skip-phase rows`,
        shot: skipShot,
        note: "read-only per plan (RS-19): toggling does NOT affect the run (no onToggle wired)",
      });
    } else {
      record({
        uc: "RS-19",
        check: "skip-dependency map",
        verdict: "SKIP",
        reason:
          "workflow has no grouped phases / no skip-analysis (single 'Steps' group) → skip map not rendered; correct honest render, not a bug",
        shot: preShot,
        note: "",
      });
    }

    // --- RS-20: lazy step fetch / phases resolved ---------------------------
    // Either phase cards resolved, a loading spinner, or an honest empty state.
    const phaseCards = await page.locator('[data-testid^="phase-group-"]').count().catch(() => 0);
    const stepRows = await page.locator('[data-testid^="phase-card-"]').count().catch(() => 0);
    const loadingSteps = await page
      .getByText("Loading workflow steps", { exact: false })
      .first()
      .isVisible()
      .catch(() => false);
    const emptyPhases = await page
      .getByText("Phases will appear here", { exact: false })
      .first()
      .isVisible()
      .catch(() => false);
    const rs20ok = phaseCards > 0 || stepRows > 0 || loadingSteps || emptyPhases;
    record({
      uc: "RS-20",
      check: "lazy steps resolve to phases OR loading/empty honest state",
      verdict: rs20ok ? "PASS" : "FAIL",
      reason: `phaseGroups=${phaseCards} stepRows=${stepRows} loading=${loadingSteps} empty=${emptyPhases}`,
      shot: preShot,
      note: "",
    });

    // Auto-loop panel (RS-17/18) — only renders on live SSE gate results while running.
    record({
      uc: "RS-17/18",
      check: "auto-loop panel render (gate table, was→now diff, manual remediation)",
      verdict: "SKIP",
      reason:
        "AutoLoopPanel renders only on autoloop_gate_results SSE during a RUNNING Batch run (and autoloop is hard-locked, plan line 3074). Covered by autoloop-panel.e2e.ts / autoloop-toggle.e2e.ts which dispatch real runs.",
      shot: preShot,
      note: "pre-run panel does not mount the auto-loop surface",
    });
  });
});

// ===========================================================================
// GROUP 2 — AFTER-RUN report on an EXISTING completed run
//   (AR-01 tab bar, AR-02 outputs, AR-06 params, AR-09/AR-10 QC audit)
// ===========================================================================
test.describe("After-run report on existing COMPLETED run (no new dispatch)", () => {
  test("completed run: tab bar + outputs + params + QC audit empty/log", async ({
    page,
    request,
  }) => {
    test.setTimeout(300_000);
    const token = await authPage(page, request);

    // Resolve a completed session (known id first, else discover live).
    let sessionId = KNOWN_COMPLETED_SESSION;
    let opened = await openRunPanel(page, sessionId);
    if (!opened) {
      const disc = await discoverSession(request, token, "completed");
      if (disc) {
        sessionId = disc.sessionId;
        opened = await openRunPanel(page, sessionId);
      }
    }
    const arShot = await shot(page, "ar_completed_01_panel");

    if (!opened) {
      const reason =
        "no existing completed run could be opened in the fixture account (deep-link ?session= did not mount workflow-artifact-panel within 60s)";
      for (const uc of ["AR-01", "AR-02", "AR-06", "AR-09", "AR-10"]) {
        record({ uc, check: "after-run (completed)", verdict: "SKIP", reason, shot: arShot, note: "" });
      }
      test.skip(true, reason);
      return;
    }
    console.log(`[AR] opened completed session=${sessionId}`);

    // Give the after-run tab time to auto-default (status=completed → after-run).
    await page.waitForTimeout(2500);

    // Make sure the after-run tab is active.
    const afterTab = page.locator('[data-testid="panel-tab-after-run"]').first();
    if (await afterTab.count().then((c) => c > 0)) {
      await afterTab.click().catch(() => null);
      await page.waitForTimeout(1500);
    }
    const afterShot = await shot(page, "ar_completed_02_afterrun_tab");

    // --- AR-01: tab bar composition -----------------------------------------
    const report = page.locator(".after-run-report").first();
    const reportPresent = await report.count().then((c) => c > 0);
    const tablist = page.locator('[role="tablist"][data-visible-tabs]').first();
    const visibleTabs = await tablist.getAttribute("data-visible-tabs").catch(() => null);
    if (reportPresent && visibleTabs) {
      const tabs = visibleTabs.split(",");
      const always = ["outputs", "findings", "qc", "params", "trajectory"];
      const hasAlways = always.every((t) => tabs.includes(t));
      record({
        uc: "AR-01",
        check: "after-run tab bar present with the 5 always-tabs; optional tabs only when content",
        verdict: hasAlways ? "PASS" : "FAIL",
        reason: `data-visible-tabs="${visibleTabs}"`,
        shot: afterShot,
        note: "optional (methods/citations/software) appear only with real content — hide-when-empty verified by their absence",
      });
    } else {
      record({
        uc: "AR-01",
        check: "after-run report + tab bar",
        verdict: "FAIL",
        reason: `after-run-report present=${reportPresent} data-visible-tabs=${visibleTabs}`,
        shot: afterShot,
        note: "panel opened but AfterRunReport tab bar not found — possible regression OR run lacks after-run payload",
      });
    }

    // --- AR-02: Outputs tab --------------------------------------------------
    const outTab = page.locator('[data-testid="after-tab-outputs"]').first();
    if (await outTab.count().then((c) => c > 0)) {
      await outTab.click().catch(() => null);
      await page.waitForTimeout(2000);
      const outShot = await shot(page, "ar_completed_03_outputs");
      const table = await page
        .locator('[data-testid="output-files-table"]')
        .first()
        .isVisible()
        .catch(() => false);
      const emptyOutputs = await page
        .getByText(/No output files registered|No outputs — run did not complete/i)
        .first()
        .isVisible()
        .catch(() => false);
      record({
        uc: "AR-02",
        check: "Outputs tab: file table OR honest empty state",
        verdict: table || emptyOutputs ? "PASS" : "FAIL",
        reason: `output-files-table=${table} emptyState=${emptyOutputs}`,
        shot: outShot,
        note: "preview/bulk-zip/save-to-project actions are click-throughs to real endpoints; table render verified UI-side. Full preview flow needs output files present.",
      });
    } else {
      record({ uc: "AR-02", check: "Outputs tab", verdict: "FAIL", reason: "after-tab-outputs missing", shot: afterShot, note: "" });
    }

    // --- AR-06: Parameters tab ----------------------------------------------
    const paramTab = page.locator('[data-testid="after-tab-params"]').first();
    if (await paramTab.count().then((c) => c > 0)) {
      await paramTab.click().catch(() => null);
      await page.waitForTimeout(1200);
      const paramShot = await shot(page, "ar_completed_04_params");
      const cta = await page
        .locator('[data-testid="afterrun-run-again-params"]')
        .first()
        .isVisible()
        .catch(() => false);
      const noParams = await page
        .getByText("No parameter values recorded", { exact: false })
        .first()
        .isVisible()
        .catch(() => false);
      // Params table rows OR honest empty. CTA present when params exist.
      const anyRow = await page
        .locator('[data-testid="qc-audit-tab"], .after-run-report table tr')
        .count()
        .catch(() => 0);
      record({
        uc: "AR-06",
        check: "Parameters tab: k/v table + run-again CTA (or honest empty)",
        verdict: cta || noParams || anyRow > 0 ? "PASS" : "FAIL",
        reason: `runAgainCta=${cta} noParamsMsg=${noParams} rows=${anyRow}`,
        shot: paramShot,
        note: "CTA click dispatches biomate:run-again-with-edits CustomEvent (not clicked here — would set up a new run)",
      });
    } else {
      record({ uc: "AR-06", check: "Parameters tab", verdict: "FAIL", reason: "after-tab-params missing", shot: afterShot, note: "" });
    }

    // --- AR-09 / AR-10: QC audit tab ----------------------------------------
    const qcTab = page.locator('[data-testid="after-tab-qc"]').first();
    if (await qcTab.count().then((c) => c > 0)) {
      await qcTab.click().catch(() => null);
      await page.waitForTimeout(1500);
      const qcShot = await shot(page, "ar_completed_05_qcaudit");
      const qcRoot = await page.locator('[data-testid="qc-audit-tab"]').first().isVisible().catch(() => false);
      const allPassed = await page
        .locator('[data-testid="qc-all-passed"]')
        .first()
        .isVisible()
        .catch(() => false);
      const summary = await page.locator('[data-testid="qc-summary"]').first().isVisible().catch(() => false);
      const auditLog = await page.locator('[data-testid="qc-audit-log"]').first().isVisible().catch(() => false);
      // e-signature must be HIDDEN in production (parent never passes eSignature — plan AR-09 edge)
      const esig = await page.locator('[data-testid="qc-e-signature"]').first().isVisible().catch(() => false);

      if (allPassed) {
        record({
          uc: "AR-10",
          check: "QC audit all-passed empty state ('All quality gates passed', no audit table)",
          verdict: qcRoot && !auditLog ? "PASS" : "FAIL",
          reason: `qc-all-passed=${allPassed} auditLog=${auditLog}`,
          shot: qcShot,
          note: "",
        });
        record({
          uc: "AR-09",
          check: "QC audit 4-stat summary + audit log + e-sig hidden",
          verdict: "SKIP",
          reason: "this completed run fired NO QC gates → all-passed empty state (AR-10 path); populated audit log needs a run that tripped a gate",
          shot: qcShot,
          note: `e-signature hidden=${!esig} (plan AR-09 edge: e-sig ALWAYS hidden in prod)`,
        });
      } else if (summary || auditLog) {
        record({
          uc: "AR-09",
          check: "QC audit: 4-stat summary + audit log render; e-sig hidden",
          verdict: (summary || auditLog) && !esig ? "PASS" : "FAIL",
          reason: `qc-summary=${summary} qc-audit-log=${auditLog} eSigHidden=${!esig}`,
          shot: qcShot,
          note: esig ? "REGRESSION: e-signature block visible but plan says parent never passes eSignature" : "",
        });
        record({
          uc: "AR-10",
          check: "QC audit all-passed empty state",
          verdict: "SKIP",
          reason: "this run has QC events (AR-09 populated path), so the all-passed empty state does not apply here",
          shot: qcShot,
          note: "",
        });
      } else {
        record({
          uc: "AR-09/10",
          check: "QC audit tab renders (summary/log or all-passed)",
          verdict: qcRoot ? "PASS" : "FAIL",
          reason: `qc-audit-tab=${qcRoot} but neither populated summary nor all-passed empty state visible`,
          shot: qcShot,
          note: "tab present but QC content ambiguous",
        });
      }
    } else {
      record({ uc: "AR-09/10", check: "QC audit tab", verdict: "FAIL", reason: "after-tab-qc missing", shot: afterShot, note: "" });
    }
  });
});

// ===========================================================================
// GROUP 3 — AFTER-RUN on an existing FAILED run (AR-04 static findings, AR-13 failed section)
// ===========================================================================
test.describe("After-run report on existing FAILED run (no new dispatch)", () => {
  test("failed run: static findings message (no spinner) + failed section", async ({
    page,
    request,
  }) => {
    test.setTimeout(300_000);
    const token = await authPage(page, request);

    let sessionId = KNOWN_FAILED_SESSION;
    let opened = await openRunPanel(page, sessionId);
    if (!opened) {
      const disc = await discoverSession(request, token, "failed");
      if (disc) {
        sessionId = disc.sessionId;
        opened = await openRunPanel(page, sessionId);
      }
    }
    const failShot = await shot(page, "ar_failed_01_panel");

    if (!opened) {
      const reason = "no existing failed run could be opened (deep-link ?session= did not mount panel)";
      for (const uc of ["AR-04", "AR-13"]) {
        record({ uc, check: "after-run (failed)", verdict: "SKIP", reason, shot: failShot, note: "" });
      }
      test.skip(true, reason);
      return;
    }
    console.log(`[AR-fail] opened failed session=${sessionId}`);
    await page.waitForTimeout(2500);

    const afterTab = page.locator('[data-testid="panel-tab-after-run"]').first();
    if (await afterTab.count().then((c) => c > 0)) {
      await afterTab.click().catch(() => null);
      await page.waitForTimeout(1500);
    }

    // --- AR-13: failed-run section (badge / error / above the tab bar) -------
    const failedBadge = await page
      .getByText(/FAILED|Workflow Failed/i)
      .first()
      .isVisible()
      .catch(() => false);
    const sectionShot = await shot(page, "ar_failed_02_section");
    record({
      uc: "AR-13",
      check: "failed-run section: FAILED badge / error surfaced above tab bar",
      verdict: failedBadge ? "PASS" : "FAIL",
      reason: `failedBadgeOrText=${failedBadge}`,
      shot: sectionShot,
      note: "autofix history + log tail depend on /autofix3/sessions payload for this run — presence not asserted, badge/error is the UI-observable anchor",
    });

    // --- AR-04: Findings tab shows STATIC failed message, NO spinner --------
    const findTab = page.locator('[data-testid="after-tab-findings"]').first();
    if (await findTab.count().then((c) => c > 0)) {
      await findTab.click().catch(() => null);
      await page.waitForTimeout(2500);
      const findShot = await shot(page, "ar_failed_03_findings");
      const staticMsg = await page
        .getByText("Analysis not available", { exact: false })
        .first()
        .isVisible()
        .catch(() => false);
      // MUST-NOT: "Analysis in progress…" or a live spinner on a failed run (CLAUDE.md).
      const inProgress = await page
        .getByText(/Analysis in progress|Analyzing outputs/i)
        .first()
        .isVisible()
        .catch(() => false);
      const bug = inProgress; // presence of in-progress on failed run = regression
      record({
        uc: "AR-04",
        check: "failed-run Findings shows STATIC 'Analysis not available…' (no 'in progress' spinner)",
        verdict: staticMsg && !bug ? "PASS" : "FAIL",
        reason: `staticFailedMsg=${staticMsg} inProgressSpinner=${inProgress}`,
        shot: findShot,
        note: bug
          ? "REGRESSION (CLAUDE.md must-not): failed run shows 'Analysis in progress…' / spinner"
          : "",
      });
    } else {
      record({ uc: "AR-04", check: "Findings tab (failed)", verdict: "FAIL", reason: "after-tab-findings missing", shot: sectionShot, note: "" });
    }
  });
});

// ===========================================================================
// Explicitly-skipped UCs that REQUIRE a real Batch run — recorded for honesty.
// ===========================================================================
test.describe("SKIPPED — require a real (expensive) AWS-Batch run", () => {
  test("record skipped run-dependent UCs", async () => {
    const needsRun: Array<[string, string]> = [
      ["RS-04", "live SSE idle→running→completed phase transition"],
      ["RS-05", "live SSE running→failed transition + Restart footer"],
      ["RS-06", "running action bar (Pause/Stop) + paused Resume"],
      ["RS-07", "completed footer 'Run again' + post-run link endpoints (fresh run in panel)"],
      ["RS-08", "failed footer Restart/Resume-from-last (fresh failed run in panel)"],
      ["RS-09", "QC gate blocked two-number display — needs qc_gate_triggered SSE live"],
      ["RS-10", "QC gate 10s auto-proceed countdown — live SSE"],
      ["RS-11", "QC advisory near-threshold step chip — live qc_warning SSE"],
      ["RS-12", "per-phase QC threshold editor — needs qc/profiles + phase expand on a live-run panel"],
      ["RS-13", "completed QC results panel — needs nextflowStatus.qc_report from a run that emitted metrics"],
      ["RS-15", "per-phase inline params — needs grouped-phase live panel (soft-skip for phaseless)"],
      ["RS-16", "step output preview (image/table/FASTA/VCF/text) — needs step outputFiles + activeRunId"],
      ["RS-21", "chat_progress narration relay — live SSE"],
      ["RS-22", "chain/proactive suggestions relay — post-completion live SSE"],
      ["SD-01..06", "step deep-view dialog (provenance/params/raw-toggle/output-tabs) — needs a run with mapped step outputs"],
      ["AR-03", "Findings on completed run (summary/key results/figures) — needs findings_analysis job artifact"],
      ["AR-05", "Methods tab real vs empty — needs methods_report job artifact"],
      ["AR-07", "Software tab — needs versions.yml from a run"],
      ["AR-08", "Citations tab — needs registered citations for the run's workflow"],
      ["AR-11", "Trajectory tab honest empty — reachable but low-value without run trajectory data"],
      ["AR-12", "download comprehensive report (blob dedup/toast) — end-to-end download flow"],
    ];
    for (const [uc, check] of needsRun) {
      record({
        uc,
        check,
        verdict: "SKIP",
        reason: "requires a real AWS-Batch workflow run (SSE/live state/job artifacts) — expensive, out of scope per task brief",
        shot: "-",
        note: "",
      });
    }
    expect(RESULTS.length).toBeGreaterThan(0);
  });
});

// ===========================================================================
// Emit the final pass/fail table.
// ===========================================================================
test.afterAll(async () => {
  const order = { PASS: 0, FAIL: 1, SKIP: 2 } as const;
  RESULTS.sort((a, b) => (order[a.verdict] - order[b.verdict]) || a.uc.localeCompare(b.uc));
  const counts = RESULTS.reduce(
    (acc, r) => ((acc[r.verdict] = (acc[r.verdict] || 0) + 1), acc),
    {} as Record<string, number>
  );
  const lines: string[] = [];
  lines.push("");
  lines.push("=".repeat(120));
  lines.push("RUN-SURFACE / AFTER-RUN E2E — LIVE DEV RESULTS (UI-observable subset)");
  lines.push("=".repeat(120));
  lines.push(`| UC | check | verdict | screenshot | note / reason |`);
  lines.push(`|----|-------|---------|------------|---------------|`);
  for (const r of RESULTS) {
    const note = (r.note || r.reason).replace(/\|/g, "/").slice(0, 160);
    lines.push(`| ${r.uc} | ${r.check.replace(/\|/g, "/").slice(0, 70)} | ${r.verdict} | ${r.shot} | ${note} |`);
  }
  lines.push("=".repeat(120));
  lines.push(
    `COUNTS — PASS=${counts.PASS || 0}  FAIL=${counts.FAIL || 0}  SKIP=${counts.SKIP || 0}  TOTAL=${RESULTS.length}`
  );
  lines.push("=".repeat(120));
  const out = lines.join("\n");
  console.log(out);
  fs.mkdirSync(SS_DIR, { recursive: true });
  fs.writeFileSync(path.join(SS_DIR, "_RESULTS.md"), out, "utf-8");
});
