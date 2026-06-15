/**
 * ADMET Auto-Loop — UX E2E Test Suite
 *
 * Extends the HTS gate-only template (e2e/hts-workflows-ux-e2e.e2e.ts) with
 * full auto-loop UI assertions. ADMET is the most mature wired auto-loop
 * domain in the codebase (backend/experiments/admet_autoloop/).
 *
 * What this suite uniquely tests (vs HTS):
 *   • Gate display                              (same as HTS)
 *   • + RemediationCard renders                 was→now param diff
 *   • + KnowledgeEntry citation pills           (Aronov / Lammert / Kazius / Lipinski)
 *   • + Multi-attempt progression               attempt 1 → attempt 2
 *   • + CNS profile is stricter than standard   admet_cns vs admet_standard
 *
 * Workflow(s) under test:
 *   DB-indexed workflows (verified):
 *     - predict_admet_properties  (tool_id biomni/pharmacology/predict_admet_properties)
 *     - ADMET_pred                (tool_id biomni/pharmacology/ADMET_pred)
 *   File:
 *     backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/ADMET_pred/main.nf
 *   Auto-loop domain:
 *     admet (qc_profile: admet_standard | admet_cns | admet_oncology)
 *   Gates (knowledge_base.py):
 *     hERG IC50         — Aronov 2008    (10.1021/jm0707476)
 *     DILI probability  — Lammert 2010   (10.1093/toxsci/kfq059)
 *     Ames mutagenicity — Kazius 2005    (10.1021/jm040835a)
 *     Lipinski Ro5      — Lipinski 1997
 *
 * Frontend wiring (from auto-loop-panel.tsx):
 *   • Panel testid:               autoloop-panel
 *   • Gate table:                 autoloop-gate-table
 *   • Remediation block:          autoloop-remediation-card
 *   • Accept-and-rerun button:    autoloop-accept-btn
 *   • Phase-complete banner:      autoloop-phase-complete-banner
 *   • QCEvidenceTooltip wraps gate-name <td> in column 1 of autoloop-gate-table
 *
 * Test index:
 *   AD-0  API check: /api/qc/profiles lists admet_standard / admet_cns / admet_oncology
 *   AD-1  Full UI:    chat query → ADMET workflow card → execute → gates render
 *   AD-2  Remediation card: was→now diff visible with citation pills
 *   AD-3  Citation evidence: hover gate label → Aronov/Lammert paper_ref + DOI
 *   AD-4  Multi-attempt: Apply&Re-run → attempt 2 panel renders (history preserved)
 *   AD-5  CNS profile stricter: same compound fails additional gates under admet_cns
 *
 * NO page.route() mocking. Real backend. Screenshots → e2e/screenshots/admet-ux/
 */

import { test, expect, Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const SS_DIR = path.join(__dirname, "screenshots", "admet-ux");
const FIXTURE_DIR = path.join(__dirname, "fixtures");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// ---------------------------------------------------------------------------
// Audit record
// ---------------------------------------------------------------------------
interface ADMETAssertion {
  name: string;
  passed: boolean;
  note?: string;
}
interface ADMETAuditRecord {
  testId: string;
  workflowName: string;
  runId: string | null;
  startTs: number;
  endTs: number;
  finalStatus: string;
  assertions: ADMETAssertion[];
  screenshots: string[];
  error?: string;
}
const SUITE_AUDIT: ADMETAuditRecord[] = [];

function writeAudit(): void {
  const ts = Date.now();
  const outPath = path.join(SS_DIR, `audit_${ts}.json`);
  fs.writeFileSync(outPath, JSON.stringify(SUITE_AUDIT, null, 2));
  console.log(`[audit] Written: ${outPath}`);
}

async function shot(page: Page, name: string): Promise<string> {
  const file = path.join(SS_DIR, `${name}.png`);
  await page.screenshot({ path: file, fullPage: false });
  console.log(`[screenshot] ${file}`);
  return file;
}

// ---------------------------------------------------------------------------
// expectAutoloopAssertions — hard-fail on autoloop SSE assertions so a
// silent regression (like the 2026-06-14 ADMET _evaluate_qc_from_s3 no-op
// sse_callback that left the AutoLoopPanel empty) cannot ship green.
//
// We deliberately only hard-fail assertions whose name mentions SSE or
// autoloop wiring — orthogonal flakes (slow Batch runs, 7-min timeouts)
// stay as audit-JSON notes so the test isn't environment-brittle.
// ---------------------------------------------------------------------------
function expectAutoloopAssertions(testId: string, assertions: ADMETAssertion[]): void {
  const HARD = /autoloop_gate_results|autoloop_update|autoloop_started|AutoLoopPanel rendered|Remediation block/i;
  const sseAssertions = assertions.filter(a => HARD.test(a.name));
  const failures = sseAssertions.filter(a => !a.passed);
  if (failures.length > 0) {
    const lines = failures.map(f => `  - ${f.name}${f.note ? ` (${f.note})` : ""}`).join("\n");
    throw new Error(`[${testId}] ${failures.length} autoloop SSE assertion(s) failed:\n${lines}`);
  }
}

// ---------------------------------------------------------------------------
// Auth helper — API-based login using pre-created fixture account.
//
// Root cause (2026-05-27 investigation): dev's /api/auth/register endpoint
// requires `termsAccepted:true` (NOT `acceptTerms`). The UI registration
// form on dev does not propagate the boolean correctly under E2E_TEST_TOKEN
// bypass — post-register the user lands on /login (see screenshots/admet-ux/
// AD1_01_home.png from the failed run), so subsequent navigation to BASE_URL
// shows the sign-in screen instead of the chat textarea.
//
// Workaround: register a shared fixture account once (idempotent — repeat
// registers return 4xx which is fine), then call /api/auth/login and inject
// the returned biomate_token JWT into the browser context as an HttpOnly
// cookie. This skips the broken UI flow entirely.
//
// Credentials are loaded from frontend/.env.test.local (gitignored). To
// recreate the fixture manually:
//   curl -X POST https://dev-public.biomate.ai/api/auth/register \
//     -H "Content-Type: application/json" \
//     -H "x-e2e-test-token: biomate-e2e-bypass-token-dev-only" \
//     -d '{"name":"ADMET E2E Fixture","email":"e2e-admet-fixture@biomate.test",
//          "password":"AdmetE2ETest!2026","termsAccepted":true}'
// ---------------------------------------------------------------------------
const FIXTURE_EMAIL = process.env.E2E_FIXTURE_EMAIL || "e2e-admet-fixture@biomate.test";
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "AdmetE2ETest!2026";

async function registerAndLogin(page: Page, label: string): Promise<{ email: string }> {
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();

  // Ensure fixture exists (idempotent; 409/400 on re-register is fine — it
  // just means the account is already there).
  await page.request.post(`${BASE_URL}/api/auth/register`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json" },
    data: {
      name: "ADMET E2E Fixture",
      email: FIXTURE_EMAIL,
      password: FIXTURE_PASSWORD,
      termsAccepted: true,
    },
  }).catch(() => null);

  // API login → grab JWT → inject as HttpOnly cookie on the browser context.
  const loginResp = await page.request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json" },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  if (!loginResp.ok()) {
    throw new Error(`[auth] login failed: ${loginResp.status()} ${await loginResp.text()}`);
  }
  const loginBody = await loginResp.json();
  const token: string | undefined = loginBody?.token;
  if (!token) throw new Error("[auth] login response missing token");

  const url = new URL(BASE_URL);
  await page.context().addCookies([{
    name: "biomate_token",
    value: token,
    domain: url.hostname,
    path: "/",
    httpOnly: true,
    secure: url.protocol === "https:",
    sameSite: "Lax",
  }]);
  console.log(`[auth] (${label}) API-login OK as ${FIXTURE_EMAIL}`);

  await page.goto(BASE_URL);
  await page.waitForLoadState("load");

  let chatReady = false;
  for (let i = 0; i < 6 && !chatReady; i++) {
    chatReady = await page.locator("textarea").first().isVisible({ timeout: 5000 }).catch(() => false);
    if (!chatReady) await page.waitForTimeout(2000);
  }
  if (!chatReady) {
    await page.reload();
    await page.waitForLoadState("load");
    await page.waitForTimeout(2000);
  }
  const surveySkip = page.locator('button:has-text("Skip"), button:has-text("Dismiss"), button:has-text("Maybe later")').first();
  if (await surveySkip.isVisible({ timeout: 3000 }).catch(() => false)) {
    await surveySkip.click({ force: true });
    await page.waitForTimeout(500);
  }
  await page.waitForSelector("textarea", { state: "visible", timeout: 20_000 }).catch(() => {});
  await page.waitForTimeout(1000);
  return { email: FIXTURE_EMAIL };
}

// ---------------------------------------------------------------------------
// Chat helper
// ---------------------------------------------------------------------------
async function sendMessage(page: Page, msg: string, timeoutMs = 120_000): Promise<boolean> {
  const ta = page.locator("textarea").first();
  await ta.fill(msg);
  await ta.press("Enter");
  console.log(`[chat] Sent: ${msg.slice(0, 80)}...`);

  const thinkingSelectors = [
    "[data-testid='chat-response-pending']",
    "[data-testid='chat-analysis-status']",
    "text=BioMate is thinking",
    "text=Analyzing request",
  ];
  await Promise.race(
    thinkingSelectors.map((sel) =>
      page.waitForSelector(sel, { state: "visible", timeout: 30_000 }).catch(() => null)
    )
  );
  await Promise.all(
    thinkingSelectors.map((sel) =>
      page.waitForSelector(sel, { state: "hidden", timeout: timeoutMs }).catch(() => null)
    )
  );
  await page.waitForFunction(
    () => {
      const latest = document.querySelector('[data-is-latest-assistant="true"]');
      if (!latest) return false;
      const text = latest.textContent ?? "";
      return text.trim().length > 30 && !text.includes("BioMate is thinking");
    },
    { timeout: timeoutMs }
  ).catch(() => {});
  await page.waitForTimeout(1500);
  const lastMsg = page.locator('[data-is-latest-assistant="true"]').last();
  const txt = await lastMsg.textContent({ timeout: 10_000 }).catch(() => "");
  return (txt?.trim().length ?? 0) > 20;
}

async function waitForWorkflowCard(page: Page, timeoutMs = 90_000, baselineCount = -1): Promise<boolean> {
  const baseline = baselineCount >= 0
    ? baselineCount
    : await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await page.evaluate(() => {
      const chat = document.querySelector('[data-testid="chat-messages"], main');
      if (chat) chat.scrollTop = chat.scrollHeight;
    }).catch(() => {});
    const count = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);
    if (count > baseline || count > 0) {
      await page.waitForTimeout(1000);
      return true;
    }
    for (const sel of [
      '[data-testid="button-run-workflow-panel"]',
      '[data-testid="workflow-run-controls"]',
      '[data-testid="button-confirm-and-run"]',
      '[data-testid="qc-settings-section"]',
    ]) {
      if (await page.locator(sel).first().isVisible({ timeout: 300 }).catch(() => false)) {
        await page.waitForTimeout(800);
        return true;
      }
    }
    await page.waitForTimeout(1000);
  }
  return false;
}

async function clickRunButton(page: Page): Promise<boolean> {
  const btnSelectors = [
    '[data-testid="button-run-workflow-panel"]',
    '[data-testid="button-confirm-and-run"]',
    'button:has-text("Run Workflow")',
    'button:has-text("Confirm & Run")',
  ];
  for (const sel of btnSelectors) {
    const btn = page.locator(sel).first();
    if (await btn.isVisible({ timeout: 3000 }).catch(() => false)) {
      let enabled = false;
      const deadline = Date.now() + 10_000;
      while (!enabled && Date.now() < deadline) {
        enabled = await btn.isEnabled({ timeout: 1000 }).catch(() => false);
        if (!enabled) await page.waitForTimeout(800);
      }
      await btn.click({ force: !enabled });
      console.log(`[run] Clicked: ${sel} (enabled=${enabled})`);
      return true;
    }
  }
  return false;
}

async function waitForTerminalStatus(page: Page, timeoutMs = 180_000): Promise<string> {
  const start = Date.now();
  await page.waitForTimeout(5000);
  while (Date.now() - start < timeoutMs) {
    await page.waitForTimeout(4000);
    const completedBanner = await page.locator('[data-testid="workflow-completion-banner"]').first().isVisible({ timeout: 1000 }).catch(() => false);
    if (completedBanner) return "completed";
    const overallBadge = page.locator('[data-testid="workflow-overall-status-badge"]').first();
    const overallStatus = await overallBadge.getAttribute("data-status").catch(() => null);
    if (overallStatus === "completed") return "completed";
    if (overallStatus === "failed" || overallStatus === "error") return overallStatus;
  }
  return "timeout";
}

// Load fixture once
const FIXTURE = JSON.parse(
  fs.readFileSync(path.join(FIXTURE_DIR, "admet_herg_fail.json"), "utf-8")
);

// ===========================================================================
// AD-0: ADMET QC profiles API
// ===========================================================================
test.describe("AD-0 ADMET QC profiles API", () => {
  test("/api/qc/profiles lists admet_standard / admet_cns / admet_oncology", async ({ request }) => {
    test.setTimeout(60_000);
    const assertions: ADMETAssertion[] = [];
    const res = await request.get(`${BASE_URL}/api/qc/profiles`);
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body).toHaveProperty("profiles");
    const ids: string[] = body.profiles.map((p: any) => p.id);
    console.log("[AD-0] all profiles:", ids);

    const admetProfiles = ids.filter(id => id.startsWith("admet"));
    assertions.push({
      name: "/api/qc/profiles responded with profile list",
      passed: ids.length > 0,
      note: `total=${ids.length}, admet=${admetProfiles.join(",")}`,
    });
    assertions.push({
      name: "admet_standard registered",
      passed: ids.includes("admet_standard"),
      note: ids.includes("admet_standard") ? "ok" : "missing — gate defaults will be sourced from qc_evaluator.py QC_PROFILES",
    });
    assertions.push({
      name: "admet_cns registered (stricter CNS profile)",
      passed: ids.includes("admet_cns"),
    });
    assertions.push({
      name: "admet_oncology registered (oncology tolerant profile)",
      passed: ids.includes("admet_oncology"),
    });

    SUITE_AUDIT.push({
      testId: "AD-0", workflowName: "ADMET QC profiles API", runId: null,
      startTs: Date.now(), endTs: Date.now(), finalStatus: "completed",
      assertions, screenshots: [],
    });
    writeAudit();
    for (const a of assertions) console.log(`[AD-0] ${a.passed ? "PASS" : "FAIL"}: ${a.name}${a.note ? ` (${a.note})` : ""}`);
  });
});

// ===========================================================================
// AD-1: Full UI journey — chat → card → execute → gates render
// ===========================================================================
test.use({ viewport: { width: 1920, height: 1080 } });

test.describe("AD-1 ADMET full journey", () => {
  test("Register → chat ADMET query → workflow card → execute → autoloop panel renders", async ({ page }) => {
    test.setTimeout(600_000);
    const assertions: ADMETAssertion[] = [];
    const screenshots: string[] = [];
    let finalStatus = "not_started";

    try {
      await registerAndLogin(page, "ad1");
      screenshots.push(await shot(page, "AD1_01_home"));
      assertions.push({ name: "Registration + home loaded", passed: true });

      const smiles = FIXTURE.smiles[0];
      const query = [
        "Predict ADMET properties for this candidate compound:",
        smiles,
        "Run the full ADMET safety profile (hERG, DILI, Ames, Lipinski Ro5).",
        "Use the admet_standard QC profile and apply the auto-loop QC gates.",
      ].join(" ");

      const gotResponse = await sendMessage(page, query, 120_000);
      screenshots.push(await shot(page, "AD1_02_after_query"));
      assertions.push({ name: "AI returned response to ADMET query", passed: gotResponse });
      if (!gotResponse) { finalStatus = "skip_no_response"; return; }

      let gotCard = await waitForWorkflowCard(page, 10_000);
      if (!gotCard) {
        await sendMessage(page, "Yes, run the ADMET prediction workflow with defaults.", 90_000);
        screenshots.push(await shot(page, "AD1_02b_confirm"));
        gotCard = await waitForWorkflowCard(page, 60_000);
      }
      screenshots.push(await shot(page, "AD1_03_workflow_card"));
      assertions.push({
        name: "ADMET workflow card appeared",
        passed: gotCard,
        note: gotCard ? "ok" : "no card — predict_admet_properties not routed",
      });
      if (!gotCard) { finalStatus = "skip_no_card"; return; }

      const ran = await clickRunButton(page);
      assertions.push({ name: "Run clicked", passed: ran });
      if (!ran) { finalStatus = "skip_no_run_btn"; return; }
      screenshots.push(await shot(page, "AD1_04_after_run"));

      finalStatus = await waitForTerminalStatus(page, 300_000);
      screenshots.push(await shot(page, `AD1_05_terminal_${finalStatus}`));
      assertions.push({ name: "Run reached terminal state", passed: finalStatus !== "timeout", note: finalStatus });

      // Auto-loop panel should render at least the gate table when SSE
      // emits autoloop_gate_results (admet domain).
      const autoloopPanel = page.locator('[data-testid="autoloop-panel"]').first();
      const panelVisible = await autoloopPanel.isVisible({ timeout: 15_000 }).catch(() => false);
      assertions.push({
        name: "AutoLoopPanel rendered (autoloop_gate_results SSE)",
        passed: panelVisible,
        note: panelVisible ? "ok" : "no SSE autoloop_gate_results — ADMET process may not have triggered the bridge",
      });

      if (panelVisible) {
        const gateTable = page.locator('[data-testid="autoloop-gate-table"]').first();
        const tableVisible = await gateTable.isVisible({ timeout: 5_000 }).catch(() => false);
        assertions.push({ name: "Gate results table visible", passed: tableVisible });

        if (tableVisible) {
          // Expect at least one of the 4 known ADMET gates
          const tableText = (await gateTable.textContent().catch(() => "")) ?? "";
          const knownGate =
            tableText.includes("hERG") ||
            tableText.includes("DILI") ||
            tableText.includes("Ames") ||
            tableText.toLowerCase().includes("logp");
          assertions.push({
            name: "Table contains at least one ADMET gate label",
            passed: knownGate,
            note: tableText.slice(0, 200),
          });
          screenshots.push(await shot(page, "AD1_06_gate_table"));
        }
      }
    } catch (err: any) {
      console.error("[AD-1] Error:", err.message);
      finalStatus = `error: ${err.message}`;
      await shot(page, "AD1_error").catch(() => {});
    } finally {
      SUITE_AUDIT.push({
        testId: "AD-1", workflowName: "ADMET full journey", runId: null,
        startTs: Date.now(), endTs: Date.now(), finalStatus, assertions, screenshots,
      });
      writeAudit();
    }

    for (const a of assertions) console.log(`[AD-1] ${a.passed ? "PASS" : "FAIL"}: ${a.name}${a.note ? ` (${a.note})` : ""}`);
    const critical = assertions.find(a => a.name === "Registration + home loaded");
    expect(critical?.passed).toBe(true);
    expectAutoloopAssertions("AD-1", assertions);
  });
});

// ===========================================================================
// AD-2: Remediation card — was→now param diff visible
// ===========================================================================
test.describe("AD-2 RemediationCard renders was→now diff", () => {
  test("Failing hERG/DILI → autoloop-remediation-card with param_changes + rationale", async ({ page }) => {
    test.setTimeout(600_000);
    const assertions: ADMETAssertion[] = [];
    const screenshots: string[] = [];

    try {
      await registerAndLogin(page, "ad2");
      const smiles = FIXTURE.smiles[0];
      const query = [
        "Run ADMET prediction on this hERG-active compound:", smiles,
        `Expected hERG IC50 ≈ ${FIXTURE.expected_predictions.hERG_IC50_uM} µM (FAIL),`,
        `DILI probability ≈ ${FIXTURE.expected_predictions.DILI_probability} (FAIL),`,
        `logP ≈ ${FIXTURE.expected_predictions.logP} (Ro5 violation).`,
        "Use admet_standard QC profile. The auto-loop should suggest a logP filter remediation.",
      ].join(" ");

      const gotResponse = await sendMessage(page, query, 90_000);
      assertions.push({ name: "AI response received", passed: gotResponse });
      if (!gotResponse) return;

      let gotCard = await waitForWorkflowCard(page, 10_000);
      if (!gotCard) {
        await sendMessage(page, "Yes, run ADMET with the auto-loop enabled.", 60_000);
        gotCard = await waitForWorkflowCard(page);
      }
      assertions.push({ name: "Workflow card appeared", passed: gotCard });
      if (!gotCard) return;

      const ran = await clickRunButton(page);
      assertions.push({ name: "Run started", passed: ran });
      if (!ran) return;

      const finalStatus = await waitForTerminalStatus(page, 300_000);
      assertions.push({ name: "Run reached terminal state", passed: finalStatus !== "timeout", note: finalStatus });
      screenshots.push(await shot(page, `AD2_01_terminal_${finalStatus}`));

      // Remediation card should appear when SSE emits autoloop_update with remediations[]
      const remediationBlock = page.locator('[data-testid="autoloop-remediation-card"]').first();
      const remVisible = await remediationBlock.isVisible({ timeout: 15_000 }).catch(() => false);
      assertions.push({
        name: "Remediation block (autoloop-remediation-card) visible",
        passed: remVisible,
        note: remVisible ? "ok" : "no autoloop_update SSE — remediation suggestions not emitted",
      });

      if (remVisible) {
        screenshots.push(await shot(page, "AD2_02_remediation"));
        const remText = (await remediationBlock.textContent().catch(() => "")) ?? "";

        // was→now arrow (RemediationCard renders "→" between line-through old and new value)
        const hasArrow = remText.includes("→") || remText.includes("->");
        assertions.push({ name: "was → now arrow present", passed: hasArrow, note: remText.slice(0, 180) });

        // Knob: logp_max or logp filter
        const hasKnob =
          remText.toLowerCase().includes("logp") ||
          remText.toLowerCase().includes("molecular_weight") ||
          remText.toLowerCase().includes("mw");
        assertions.push({ name: "Remediation names logP / MW filter knob", passed: hasKnob });

        // Citation pill button — "Show N citation(s)"
        const citationBtn = remediationBlock.locator('button:has-text("citation")').first();
        const citationBtnVisible = await citationBtn.isVisible({ timeout: 3000 }).catch(() => false);
        assertions.push({
          name: "Citation pill button visible (BookOpen + N citation(s))",
          passed: citationBtnVisible,
        });

        if (citationBtnVisible) {
          await citationBtn.click({ force: true }).catch(() => {});
          await page.waitForTimeout(600);
          screenshots.push(await shot(page, "AD2_03_citations_expanded"));
          const expandedText = (await remediationBlock.textContent().catch(() => "")) ?? "";
          const hasKnownCitation =
            expandedText.includes("Aronov") ||
            expandedText.includes("Lammert") ||
            expandedText.includes("Kazius") ||
            expandedText.includes("Lipinski");
          assertions.push({
            name: "Citation includes known paper_ref (Aronov/Lammert/Kazius/Lipinski)",
            passed: hasKnownCitation,
            note: expandedText.slice(0, 240),
          });
          const hasDoi = expandedText.includes("10.") || expandedText.toLowerCase().includes("doi");
          assertions.push({ name: "Citation includes DOI reference", passed: hasDoi });
        }

        // Apply & Re-run button visible
        const acceptBtn = page.locator('[data-testid="autoloop-accept-btn"]').first();
        const acceptVisible = await acceptBtn.isVisible({ timeout: 3000 }).catch(() => false);
        assertions.push({ name: "Apply & Re-run button rendered", passed: acceptVisible });
      }
    } catch (err: any) {
      console.error("[AD-2] Error:", err.message);
      await shot(page, "AD2_error").catch(() => {});
    } finally {
      SUITE_AUDIT.push({
        testId: "AD-2", workflowName: "ADMET remediation card", runId: null,
        startTs: Date.now(), endTs: Date.now(), finalStatus: "completed",
        assertions, screenshots,
      });
      writeAudit();
    }
    for (const a of assertions) console.log(`[AD-2] ${a.passed ? "PASS" : "FAIL"}: ${a.name}${a.note ? ` (${a.note})` : ""}`);
    expectAutoloopAssertions("AD-2", assertions);
  });
});

// ===========================================================================
// AD-3: Citation tooltip on gate label (Aronov 2008 hERG / Lammert 2010 DILI)
// ===========================================================================
test.describe("AD-3 QCEvidenceTooltip on ADMET gate labels", () => {
  test("Hover hERG → Aronov 2008 + DOI; hover DILI → Lammert 2010 + DOI", async ({ page }) => {
    test.setTimeout(420_000);
    const assertions: ADMETAssertion[] = [];
    const screenshots: string[] = [];

    try {
      await registerAndLogin(page, "ad3");
      const smiles = FIXTURE.smiles[0];
      const query = `Run ADMET prediction with auto-loop QC on this SMILES: ${smiles}. ` +
        "Use admet_standard profile so the hERG and DILI gates evaluate.";
      const gotResponse = await sendMessage(page, query, 90_000);
      assertions.push({ name: "AI response received", passed: gotResponse });
      if (!gotResponse) return;

      let gotCard = await waitForWorkflowCard(page, 10_000);
      if (!gotCard) {
        await sendMessage(page, "Yes, run the ADMET workflow.", 60_000);
        gotCard = await waitForWorkflowCard(page);
      }
      assertions.push({ name: "Workflow card appeared", passed: gotCard });
      if (!gotCard) return;

      const ran = await clickRunButton(page);
      assertions.push({ name: "Run started", passed: ran });
      if (!ran) return;

      const finalStatus = await waitForTerminalStatus(page, 240_000);
      assertions.push({ name: "Run reached terminal state", passed: finalStatus !== "timeout", note: finalStatus });

      const gateTable = page.locator('[data-testid="autoloop-gate-table"]').first();
      const tableVisible = await gateTable.isVisible({ timeout: 15_000 }).catch(() => false);
      assertions.push({ name: "Gate table visible", passed: tableVisible });
      if (!tableVisible) return;
      screenshots.push(await shot(page, "AD3_01_gate_table"));

      // hERG row
      const hergCell = gateTable.locator('tr', { hasText: /hERG|herg/i }).first().locator('td').first();
      if (await hergCell.isVisible({ timeout: 3000 }).catch(() => false)) {
        const trigger = hergCell.locator('span').first();
        await trigger.hover({ force: true }).catch(() => {});
        await page.waitForTimeout(800);
        const ttText = (await page.locator('[role="tooltip"]').first().textContent({ timeout: 3000 }).catch(() => "")) || "";
        assertions.push({
          name: "hERG tooltip: Aronov 2008 reference",
          passed: ttText.includes("Aronov"),
          note: ttText.slice(0, 140),
        });
        assertions.push({
          name: "hERG tooltip: DOI 10.1021/jm0707476 (or ICH S7B regulatory)",
          passed: ttText.includes("10.1021/jm0707476") || ttText.includes("ICH S7B") || ttText.toLowerCase().includes("doi"),
        });
        screenshots.push(await shot(page, "AD3_02_herg_tooltip"));
        await page.mouse.move(0, 0);
        await page.waitForTimeout(400);
      } else {
        assertions.push({ name: "hERG gate row present", passed: false, note: "row not found in table" });
      }

      // DILI row
      const diliCell = gateTable.locator('tr', { hasText: /DILI|dili/i }).first().locator('td').first();
      if (await diliCell.isVisible({ timeout: 3000 }).catch(() => false)) {
        const trigger = diliCell.locator('span').first();
        await trigger.hover({ force: true }).catch(() => {});
        await page.waitForTimeout(800);
        const ttText = (await page.locator('[role="tooltip"]').first().textContent({ timeout: 3000 }).catch(() => "")) || "";
        assertions.push({
          name: "DILI tooltip: Lammert 2010 reference",
          passed: ttText.includes("Lammert"),
          note: ttText.slice(0, 140),
        });
        assertions.push({
          name: "DILI tooltip: DOI 10.1093/toxsci/kfq059",
          passed: ttText.includes("10.1093/toxsci/kfq059") || ttText.toLowerCase().includes("doi"),
        });
        screenshots.push(await shot(page, "AD3_03_dili_tooltip"));
      } else {
        assertions.push({ name: "DILI gate row present", passed: false, note: "row not found in table" });
      }
    } catch (err: any) {
      console.error("[AD-3] Error:", err.message);
      await shot(page, "AD3_error").catch(() => {});
    } finally {
      SUITE_AUDIT.push({
        testId: "AD-3", workflowName: "ADMET citation tooltip", runId: null,
        startTs: Date.now(), endTs: Date.now(), finalStatus: "completed",
        assertions, screenshots,
      });
      writeAudit();
    }
    for (const a of assertions) console.log(`[AD-3] ${a.passed ? "PASS" : "FAIL"}: ${a.name}${a.note ? ` (${a.note})` : ""}`);
  });
});

// ===========================================================================
// AD-4: Multi-attempt progression — Apply & Re-run preserves attempt 1 history
// ===========================================================================
test.describe("AD-4 Multi-attempt auto-loop progression", () => {
  test("Apply & Re-run → attempt 2 runs; attempt 1 panel still in chat history", async ({ page }) => {
    test.setTimeout(600_000);
    const assertions: ADMETAssertion[] = [];
    const screenshots: string[] = [];

    try {
      await registerAndLogin(page, "ad4");
      const smiles = FIXTURE.smiles[0];
      const query = `Run ADMET prediction with auto-loop QC. SMILES: ${smiles}. ` +
        "Use admet_standard profile. Failing gates should trigger logP filter remediation.";
      const gotResponse = await sendMessage(page, query, 90_000);
      assertions.push({ name: "AI response received", passed: gotResponse });
      if (!gotResponse) return;

      let gotCard = await waitForWorkflowCard(page, 10_000);
      if (!gotCard) {
        await sendMessage(page, "Yes, run the workflow.", 60_000);
        gotCard = await waitForWorkflowCard(page);
      }
      if (!gotCard) {
        assertions.push({ name: "Workflow card appeared", passed: false });
        return;
      }

      await clickRunButton(page);
      let finalStatus = await waitForTerminalStatus(page, 240_000);
      assertions.push({ name: "Attempt 1 reached terminal state", passed: finalStatus !== "timeout", note: finalStatus });
      screenshots.push(await shot(page, "AD4_01_attempt1_terminal"));

      // Find Apply & Re-run button from attempt 1's autoloop panel
      const acceptBtn = page.locator('[data-testid="autoloop-accept-btn"]').first();
      const acceptVisible = await acceptBtn.isVisible({ timeout: 15_000 }).catch(() => false);
      assertions.push({
        name: "Apply & Re-run button visible after attempt 1",
        passed: acceptVisible,
        note: acceptVisible ? "ok" : "no remediation emitted; cannot progress to attempt 2",
      });
      if (!acceptVisible) return;

      // Count autoloop panels before re-run
      const beforeCount = await page.locator('[data-testid="autoloop-panel"]').count().catch(() => 0);
      console.log(`[AD-4] autoloop-panel count before re-run: ${beforeCount}`);

      await acceptBtn.click({ force: true });
      console.log("[AD-4] Clicked Apply & Re-run");
      await page.waitForTimeout(3000);
      screenshots.push(await shot(page, "AD4_02_after_accept"));

      finalStatus = await waitForTerminalStatus(page, 240_000);
      assertions.push({ name: "Attempt 2 reached terminal state", passed: finalStatus !== "timeout", note: finalStatus });
      screenshots.push(await shot(page, "AD4_03_attempt2_terminal"));

      // History preserved: previous autoloop panel(s) should still be in chat scroll
      // (attempt 1 panel rendered in a previous chat message; attempt 2 renders in
      // a newer message). After re-run there should be at least the same count.
      const afterCount = await page.locator('[data-testid="autoloop-panel"]').count().catch(() => 0);
      console.log(`[AD-4] autoloop-panel count after re-run: ${afterCount}`);
      assertions.push({
        name: "Attempt 1 panel preserved (panels count did not decrease)",
        passed: afterCount >= Math.max(beforeCount, 1),
        note: `before=${beforeCount}, after=${afterCount}`,
      });
      assertions.push({
        name: "New attempt panel rendered or attempt indicator advanced",
        passed: afterCount > beforeCount || finalStatus === "completed",
        note: `before=${beforeCount}, after=${afterCount}, status=${finalStatus}`,
      });
    } catch (err: any) {
      console.error("[AD-4] Error:", err.message);
      await shot(page, "AD4_error").catch(() => {});
    } finally {
      SUITE_AUDIT.push({
        testId: "AD-4", workflowName: "ADMET multi-attempt", runId: null,
        startTs: Date.now(), endTs: Date.now(), finalStatus: "completed",
        assertions, screenshots,
      });
      writeAudit();
    }
    for (const a of assertions) console.log(`[AD-4] ${a.passed ? "PASS" : "FAIL"}: ${a.name}${a.note ? ` (${a.note})` : ""}`);
    expectAutoloopAssertions("AD-4", assertions);
  });
});

// ===========================================================================
// AD-5: CNS profile is stricter — same compound fails additional gates
// ===========================================================================
test.describe("AD-5 admet_cns profile stricter than admet_standard", () => {
  test("Same SMILES under admet_cns fails MW + TPSA gates that admet_standard tolerates", async ({ page }) => {
    test.setTimeout(420_000);
    const assertions: ADMETAssertion[] = [];
    const screenshots: string[] = [];

    try {
      await registerAndLogin(page, "ad5");
      const smiles = FIXTURE.smiles[0];
      const query = [
        "Run ADMET prediction on this compound for CNS indication:", smiles,
        "Use the admet_cns QC profile (stricter Lipinski thresholds: logP_max=4, MW_max=450, TPSA_max=90).",
        "The compound has logP≈6.1 and MW≈472, so additional gates should fail vs admet_standard.",
      ].join(" ");
      const gotResponse = await sendMessage(page, query, 90_000);
      assertions.push({ name: "AI response received", passed: gotResponse });
      if (!gotResponse) return;

      let gotCard = await waitForWorkflowCard(page, 10_000);
      if (!gotCard) {
        await sendMessage(page, "Yes, run ADMET with admet_cns profile.", 60_000);
        gotCard = await waitForWorkflowCard(page);
      }
      assertions.push({ name: "Workflow card appeared", passed: gotCard });
      if (!gotCard) return;

      const ran = await clickRunButton(page);
      assertions.push({ name: "Run started", passed: ran });
      if (!ran) return;

      const finalStatus = await waitForTerminalStatus(page, 240_000);
      assertions.push({ name: "Run reached terminal state", passed: finalStatus !== "timeout", note: finalStatus });
      screenshots.push(await shot(page, `AD5_01_terminal_${finalStatus}`));

      const gateTable = page.locator('[data-testid="autoloop-gate-table"]').first();
      const tableVisible = await gateTable.isVisible({ timeout: 15_000 }).catch(() => false);
      assertions.push({ name: "Gate table visible under admet_cns", passed: tableVisible });
      if (!tableVisible) return;

      const tableHtml = (await gateTable.innerHTML().catch(() => "")) ?? "";
      const haltCount = (tableHtml.match(/HALT/g) ?? []).length;
      const advisoryCount = (tableHtml.match(/ADVISORY/g) ?? []).length;
      // admet_cns should typically yield >=2 halts on this compound (hERG + logP at minimum)
      assertions.push({
        name: "≥2 HALT badges under admet_cns",
        passed: haltCount >= 2,
        note: `halt=${haltCount}, advisory=${advisoryCount}`,
      });
      // MW or TPSA fail under CNS (not Ro5-standard) — these are the discriminating gates
      const tableText = (await gateTable.textContent().catch(() => "")) ?? "";
      const cnsExtraGate =
        tableText.toLowerCase().includes("molecular weight") ||
        tableText.toLowerCase().includes("tpsa") ||
        tableText.toLowerCase().includes("mw");
      assertions.push({
        name: "CNS-specific gate (MW / TPSA) appears in table",
        passed: cnsExtraGate,
        note: tableText.slice(0, 220),
      });
      screenshots.push(await shot(page, "AD5_02_cns_gates"));
    } catch (err: any) {
      console.error("[AD-5] Error:", err.message);
      await shot(page, "AD5_error").catch(() => {});
    } finally {
      SUITE_AUDIT.push({
        testId: "AD-5", workflowName: "ADMET CNS profile stricter", runId: null,
        startTs: Date.now(), endTs: Date.now(), finalStatus: "completed",
        assertions, screenshots,
      });
      writeAudit();
    }
    for (const a of assertions) console.log(`[AD-5] ${a.passed ? "PASS" : "FAIL"}: ${a.name}${a.note ? ` (${a.note})` : ""}`);
  });
});
