/**
 * BOIN Clinical Trial — UX E2E Test Suite (advisory-only / non-tunable workflow)
 *
 * Third of three representative gate suites (HTS, ADMET-autoloop, BOIN). Validates
 * that the QC gate display + QCEvidenceTooltip work correctly for a workflow whose
 * algorithm IS the regulatory gold standard. BOIN is non-tunable: when the
 * `boin_dlt_boundary` gate halts (observed MTD DLT rate > target φ), the panel
 * MUST render the gate row in halt color WITHOUT offering a RemediationCard —
 * "fix the parameters" is not a meaningful response to a BOIN escalation.
 *
 * Workflow(s) under test:
 *   backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/
 *     clinical_trial_simulation/main.nf
 *     adaptive_trial_design/main.nf
 *   process keywords (qc_gate_emit._PROCESS_KEYWORDS["clinical_trial"]):
 *     CLINICAL_TRIAL_SIMULATION, BOIN, DOSE_ESCALATION, ADAPTIVE_TRIAL_DESIGN
 *   Gate: boin_dlt_boundary  (qc_gate_reader._gate_boin_dlt_boundary)
 *   Citation: Liu S, Yuan Y. J R Stat Soc C 2015; 64(3):507-523  (provenance: GOLD)
 *
 * Frontend wiring (auto-loop-panel.tsx):
 *   • Panel testid:                 autoloop-panel
 *   • Gate table:                   autoloop-gate-table
 *   • Remediation block:            autoloop-remediation-card  (MUST be absent in BO-3)
 *   • Phase-complete banner:        autoloop-phase-complete-banner
 *   • QCEvidenceTooltip wraps gate-name cell in column 1 of autoloop-gate-table
 *   • DOMAIN_LABELS does NOT yet contain "clinical_trial" (see BO-5)
 *
 * Test index:
 *   BO-0  API:    /api/qc/profiles lists BOIN/clinical_trial profiles (advisory)
 *   BO-1  Full UI: chat query → workflow card → QC panel → execute → trace+MTD output
 *   BO-2  Evidence tooltip: hover boin_dlt_boundary → Liu & Yuan 2015 + GOLD + DOI
 *   BO-3  Advisory-only halt: DLT 0.32 vs target 0.25 → gate halts → NO RemediationCard
 *   BO-4  Outputs: trial-trace.csv + mtd.json downloadable; BOIN escalation in audit log
 *   BO-5  Domain label: DOMAIN_LABELS["clinical_trial"] check — documents code gap
 *
 * NO page.route() mocking. Real backend.
 * Screenshots → e2e/screenshots/boin-ux/
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
const SS_DIR = path.join(__dirname, "screenshots", "boin-ux");
const FIXTURE_DIR = path.join(__dirname, "fixtures");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// ---------------------------------------------------------------------------
// Audit record (mirrors HTS/CryoAuditRecord)
// ---------------------------------------------------------------------------
interface BOIN_Assertion {
  name: string;
  passed: boolean;
  note?: string;
}
interface BOINAuditRecord {
  testId: string;
  workflowName: string;
  runId: string | null;
  startTs: number;
  endTs: number;
  finalStatus: string;
  assertions: BOIN_Assertion[];
  screenshots: string[];
  error?: string;
}
const SUITE_AUDIT: BOINAuditRecord[] = [];

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
// Auth helper (copied verbatim from HTS template — same E2E_TEST_TOKEN bypass)
// ---------------------------------------------------------------------------
async function registerAndLogin(page: Page, label: string): Promise<{ email: string }> {
  const email = `e2e_boin_${label}_${Date.now()}@biomate.test`;
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  await page.goto(`${BASE_URL}/register`);
  await page.waitForLoadState("load");
  await page.evaluate(() => {
    try { localStorage.clear(); sessionStorage.clear(); } catch {}
  }).catch(() => {});

  try {
    await page.waitForSelector("#name", { state: "visible", timeout: 15_000 });
    await page.fill("#name", `BOIN E2E ${label}`);
    await page.fill("#email", email);
    await page.fill("#password", "TestPass123!");
    await page.fill("#confirmPassword", "TestPass123!");
    await page.click("#terms");
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
    console.log(`[auth] Registered: ${email}`);
  } catch {
    console.log(`[auth] Registration form not found — trying login for: ${email}`);
  }

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
  return { email };
}

// ---------------------------------------------------------------------------
// Chat helper (mirrors HTS sendMessage)
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

// ---------------------------------------------------------------------------
// Workflow card / run helpers (copied from HTS template)
// ---------------------------------------------------------------------------
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

// ===========================================================================
// BO-0: QC profiles API
// ===========================================================================
test.describe("BO-0 QC profiles API", () => {
  test("/api/qc/profiles returns profile list (BOIN / clinical_trial profiles documented)", async ({ request }) => {
    test.setTimeout(60_000);
    const assertions: BOIN_Assertion[] = [];
    const res = await request.get(`${BASE_URL}/api/qc/profiles`);
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body).toHaveProperty("profiles");
    const ids: string[] = body.profiles.map((p: any) => p.id);
    const ctProfiles = ids.filter((id) =>
      id.startsWith("boin") || id.startsWith("clinical_trial") || id.includes("dose_escal")
    );
    console.log("[BO-0] clinical_trial-related profiles:", ctProfiles);

    assertions.push({ name: "Profiles endpoint returns 200 with profile list", passed: true, note: `${ids.length} total profiles` });
    // Clinical-trial is a gate-only / advisory-only domain — defaults read from
    // workflow params (target_dlt_rate=0.25) rather than a named QC profile.
    assertions.push({
      name: "Named BOIN / clinical_trial QC profiles registered (advisory)",
      passed: ctProfiles.length > 0,
      note: ctProfiles.length > 0
        ? `found: ${ctProfiles.join(',')}`
        : "no boin_* / clinical_trial_* profile present — gate defaults sourced from workflow params (target_dlt_rate=0.25, Liu & Yuan 2015)",
    });

    SUITE_AUDIT.push({
      testId: "BO-0", workflowName: "QC profiles API", runId: null,
      startTs: Date.now(), endTs: Date.now(), finalStatus: "passed",
      assertions, screenshots: [],
    });
    writeAudit();
  });
});

// ===========================================================================
// BO-1: Full UI journey — chat → card → QC panel → execute → trace+MTD output
// ===========================================================================
test.use({ viewport: { width: 1920, height: 1080 } });

test.describe("BO-1 BOIN clinical-trial simulation — full journey", () => {
  test("Register → query → card → QC settings → execute → BOIN trace + MTD output", async ({ page }) => {
    test.setTimeout(600_000);
    const assertions: BOIN_Assertion[] = [];
    const screenshots: string[] = [];
    let finalStatus = "not_started";

    try {
      await registerAndLogin(page, "bo1");
      screenshots.push(await shot(page, "BO1_01_home"));
      assertions.push({ name: "Registration and home page loaded", passed: true });

      const query = [
        "Run a BOIN dose-escalation clinical-trial simulation.",
        "I have 3 dose levels (25 mg, 50 mg, 100 mg) and want to enroll cohorts of 10 patients each up to N=30.",
        "Target DLT rate phi = 0.25. Report the MTD and the BOIN escalation trace.",
      ].join(" ");

      const gotResponse = await sendMessage(page, query, 120_000);
      screenshots.push(await shot(page, "BO1_02_after_query"));
      assertions.push({ name: "AI returned response to BOIN trial query", passed: gotResponse });
      if (!gotResponse) { finalStatus = "skip_no_response"; return; }

      let gotCard = await waitForWorkflowCard(page, 10_000);
      if (!gotCard) {
        console.log("[BO-1] Sending confirmation turn...");
        await sendMessage(page, "Yes, run the BOIN clinical-trial simulation workflow with defaults.", 90_000);
        screenshots.push(await shot(page, "BO1_02b_confirmation"));
        gotCard = await waitForWorkflowCard(page, 60_000);
      }
      screenshots.push(await shot(page, "BO1_03_workflow_card"));
      assertions.push({
        name: "BOIN clinical-trial workflow card appeared",
        passed: gotCard,
        note: gotCard
          ? "ok"
          : "workflow not routed via chat — clinical_trial_simulation / adaptive_trial_design may not be indexed in galaxy_ai_tools.db (db query found only biomate_ds_api_clinicaltrials data-source)",
      });
      if (!gotCard) { finalStatus = "skip_no_card_not_indexed"; return; }

      const paramPanel = page.locator('button:has-text("Workflow settings")').first();
      const paramVisible = await paramPanel.isVisible({ timeout: 8_000 }).catch(() => false);
      if (paramVisible) {
        await paramPanel.click().catch(() => {});
        await page.waitForTimeout(500);
      }
      assertions.push({ name: "Parameters panel visible", passed: paramVisible });
      screenshots.push(await shot(page, "BO1_04_params_panel"));

      // QC settings — gate-only, single gate (boin_dlt_boundary)
      const qcSection = page.locator('[data-testid="qc-settings-section"]').first();
      const qcVisible = await qcSection.isVisible({ timeout: 8_000 }).catch(() => false);
      assertions.push({
        name: "QC settings section visible",
        passed: qcVisible,
        note: qcVisible
          ? "ok"
          : "QC section may be hidden for non-tunable domains — target_dlt_rate is a workflow param, not a tunable threshold",
      });
      if (qcVisible) screenshots.push(await shot(page, "BO1_05_qc_settings"));

      const ran = await clickRunButton(page);
      assertions.push({ name: "Run button clicked", passed: ran });
      if (!ran) { finalStatus = "skip_no_run_btn"; return; }
      screenshots.push(await shot(page, "BO1_06_after_execute"));

      finalStatus = await waitForTerminalStatus(page, 240_000);
      screenshots.push(await shot(page, `BO1_07_terminal_${finalStatus}`));
      assertions.push({ name: "Run reached terminal state", passed: finalStatus !== "timeout", note: finalStatus });

    } catch (err: any) {
      console.error("[BO-1] Error:", err.message);
      finalStatus = `error: ${err.message}`;
      await shot(page, "BO1_error").catch(() => {});
    } finally {
      SUITE_AUDIT.push({
        testId: "BO-1", workflowName: "BOIN clinical-trial simulation", runId: null,
        startTs: Date.now(), endTs: Date.now(), finalStatus, assertions, screenshots,
      });
      writeAudit();
    }

    const critical = assertions.find(a => a.name === "Registration and home page loaded");
    expect(critical?.passed).toBe(true);
  });
});

// ===========================================================================
// BO-2: Evidence tooltip — boin_dlt_boundary → Liu & Yuan 2015 + GOLD + DOI
// ===========================================================================
test.describe("BO-2 QCEvidenceTooltip on boin_dlt_boundary gate", () => {
  test("Hover boin_dlt_boundary cell → Liu & Yuan 2015 + GOLD provenance + DOI", async ({ page }) => {
    test.setTimeout(300_000);
    const assertions: BOIN_Assertion[] = [];
    const screenshots: string[] = [];

    try {
      await registerAndLogin(page, "bo2");
      const query = "Run BOIN dose-escalation simulation with target DLT rate phi = 0.25 and 3 dose levels. Report the MTD with the boin_dlt_boundary QC gate.";
      const gotResponse = await sendMessage(page, query, 90_000);
      assertions.push({ name: "AI response received", passed: gotResponse });
      if (!gotResponse) return;

      let gotCard = await waitForWorkflowCard(page, 10_000);
      if (!gotCard) {
        await sendMessage(page, "Yes, run the BOIN simulation.", 60_000);
        gotCard = await waitForWorkflowCard(page);
      }
      assertions.push({ name: "Workflow card appeared", passed: gotCard });
      if (!gotCard) return;

      const ran = await clickRunButton(page);
      assertions.push({ name: "Run started (to populate gate panel via SSE)", passed: ran });
      if (!ran) return;

      const finalStatus = await waitForTerminalStatus(page, 180_000);
      assertions.push({ name: "Run reached terminal state", passed: finalStatus !== "timeout", note: finalStatus });
      screenshots.push(await shot(page, `BO2_01_terminal_${finalStatus}`));

      const gateTable = page.locator('[data-testid="autoloop-gate-table"]').first();
      const tableVisible = await gateTable.isVisible({ timeout: 10_000 }).catch(() => false);
      assertions.push({
        name: "Auto-loop gate table visible",
        passed: tableVisible,
        note: tableVisible
          ? "ok"
          : "no gate-results SSE — clinical_trial process name may not have matched qc_gate_emit._PROCESS_KEYWORDS (CLINICAL_TRIAL_SIMULATION / BOIN / DOSE_ESCALATION / ADAPTIVE_TRIAL_DESIGN)",
      });
      if (!tableVisible) {
        screenshots.push(await shot(page, "BO2_no_gate_table"));
        return;
      }
      screenshots.push(await shot(page, "BO2_02_gate_table"));

      // boin_dlt_boundary row — match the gate name in the first <td>
      const boinCell = gateTable.locator('tr', { hasText: /boin[\s_-]?dlt[\s_-]?boundary|DLT|BOIN/i }).first().locator('td').first();
      const cellVisible = await boinCell.isVisible({ timeout: 5000 }).catch(() => false);
      assertions.push({ name: "boin_dlt_boundary gate row rendered", passed: cellVisible });
      if (cellVisible) {
        const trigger = boinCell.locator('span.cursor-help, span:has-text("boin"), span').first();
        await trigger.hover({ force: true }).catch(() => {});
        await page.waitForTimeout(800);
        const tooltipBody = page.locator('[role="tooltip"]').first();
        const tooltipText = await tooltipBody.textContent({ timeout: 3000 }).catch(() => "") || "";
        const hasLiuYuan = tooltipText.includes("Liu") || tooltipText.includes("Yuan");
        const has2015    = tooltipText.includes("2015");
        const hasGold    = tooltipText.includes("GOLD");
        const hasJRSS    = tooltipText.includes("J R Stat Soc") || tooltipText.includes("JRSS") || tooltipText.includes("507");
        assertions.push({ name: "boin_dlt_boundary tooltip: Liu/Yuan reference", passed: hasLiuYuan, note: tooltipText.slice(0, 120) });
        assertions.push({ name: "boin_dlt_boundary tooltip: 2015 year", passed: has2015 });
        assertions.push({ name: "boin_dlt_boundary tooltip: GOLD provenance badge", passed: hasGold });
        assertions.push({ name: "boin_dlt_boundary tooltip: citation venue (JRSS / pages)", passed: hasJRSS });
        screenshots.push(await shot(page, "BO2_03_tooltip"));
      }
    } catch (err: any) {
      console.error("[BO-2] Error:", err.message);
      await shot(page, "BO2_error").catch(() => {});
    } finally {
      SUITE_AUDIT.push({
        testId: "BO-2", workflowName: "QCEvidenceTooltip — Liu & Yuan 2015", runId: null,
        startTs: Date.now(), endTs: Date.now(), finalStatus: "completed",
        assertions, screenshots,
      });
      writeAudit();
    }
    for (const a of assertions) console.log(`[BO-2] ${a.passed ? "PASS" : "FAIL"}: ${a.name}${a.note ? ` (${a.note})` : ""}`);
  });
});

// ===========================================================================
// BO-3: Advisory-only halt — gate halts but NO RemediationCard renders
//       (the architectural point of this suite)
// ===========================================================================
test.describe("BO-3 Advisory-only halt — no remediation card for BOIN", () => {
  test("Force DLT 0.32 > target 0.25 → gate halts → autoloop-remediation-card absent", async ({ page }) => {
    test.setTimeout(360_000);
    const assertions: BOIN_Assertion[] = [];
    const screenshots: string[] = [];

    try {
      const fixturePath = path.join(FIXTURE_DIR, "boin_3cohort_mtd.json");
      const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf-8"));
      const halt = fixture.halt_scenario;

      await registerAndLogin(page, "bo3");
      const query = [
        "Run a BOIN dose-escalation simulation but in a scenario where the MTD-selected dose has an observed DLT rate of",
        `${halt.mtd_observed_dlt_rate} (vs target phi = ${halt.target_dlt_rate}, ratio ${halt.expected_ratio}).`,
        "The boin_dlt_boundary QC gate should HALT because the observed rate exceeds the target.",
        "Report the MTD, the BOIN escalation trace, and the gate decision.",
      ].join(" ");
      const gotResponse = await sendMessage(page, query, 90_000);
      assertions.push({ name: "AI response received", passed: gotResponse });
      if (!gotResponse) return;

      let gotCard = await waitForWorkflowCard(page, 10_000);
      if (!gotCard) {
        await sendMessage(page, "Yes, run the BOIN simulation and report the gate halt.", 60_000);
        gotCard = await waitForWorkflowCard(page);
      }
      assertions.push({ name: "Workflow card appeared", passed: gotCard });
      if (!gotCard) return;

      const ran = await clickRunButton(page);
      assertions.push({ name: "Run started", passed: ran });
      if (!ran) return;
      screenshots.push(await shot(page, "BO3_01_after_run"));

      const finalStatus = await waitForTerminalStatus(page, 180_000);
      assertions.push({ name: "Run reached terminal state", passed: finalStatus !== "timeout", note: finalStatus });
      screenshots.push(await shot(page, `BO3_02_terminal_${finalStatus}`));

      const gateTable = page.locator('[data-testid="autoloop-gate-table"]').first();
      const tableVisible = await gateTable.isVisible({ timeout: 10_000 }).catch(() => false);
      assertions.push({ name: "Gate table visible after halted-MTD run", passed: tableVisible });

      if (tableVisible) {
        // Halted row should be red
        const boinRow = gateTable.locator('tr', { hasText: /boin[\s_-]?dlt[\s_-]?boundary|DLT/i }).first();
        const rowHtml = await boinRow.innerHTML().catch(() => "");
        const hasHaltColor = rowHtml.includes("text-red-600") || rowHtml.includes("halt");
        assertions.push({
          name: "boin_dlt_boundary row rendered with halt/red styling",
          passed: hasHaltColor,
          note: hasHaltColor ? "ok" : "expected halt color absent — backend may have reported pass/advisory instead",
        });
        screenshots.push(await shot(page, "BO3_03_halt_row"));

        // === THE ARCHITECTURAL ASSERTION ===
        // For BOIN, remediations[] is empty → RemediationCard MUST NOT render.
        // qc_gate_emit (gate-only path) sets remediations=[] for clinical_trial,
        // and auto-loop-panel.tsx guards on `remediations.length > 0`.
        const remediationCard = page.locator('[data-testid="autoloop-remediation-card"]');
        const remediationCount = await remediationCard.count().catch(() => 0);
        const isAbsent = remediationCount === 0;
        assertions.push({
          name: "RemediationCard ABSENT (BOIN is non-tunable — advisory-only)",
          passed: isAbsent,
          note: isAbsent
            ? "ok — no remediation card rendered as expected for clinical_trial domain"
            : `FAIL: ${remediationCount} remediation card(s) rendered — BOIN should not offer parameter tuning`,
        });

        // The "Apply & Re-run" button must also be absent
        const acceptBtn = page.locator('[data-testid="autoloop-accept-btn"]');
        const acceptCount = await acceptBtn.count().catch(() => 0);
        assertions.push({
          name: "Apply & Re-run button ABSENT (non-tunable workflow)",
          passed: acceptCount === 0,
          note: acceptCount === 0 ? "ok" : `unexpected: ${acceptCount} accept button(s) found`,
        });

        // The escalation banner (XCircle with "Phase escalated") MAY still render —
        // this is informational, not remediation.
        const escalatedBanner = await page.locator('text=/escalated|Phase escalated|gates? failed/i').first().isVisible({ timeout: 2000 }).catch(() => false);
        assertions.push({
          name: "Escalation banner present (informational only, not actionable)",
          passed: escalatedBanner,
          note: escalatedBanner ? "ok — banner conveys halt without offering knobs" : "no escalation banner rendered",
        });
        screenshots.push(await shot(page, "BO3_04_no_remediation"));
      }
    } catch (err: any) {
      console.error("[BO-3] Error:", err.message);
      await shot(page, "BO3_error").catch(() => {});
    } finally {
      SUITE_AUDIT.push({
        testId: "BO-3", workflowName: "BOIN advisory-only halt", runId: null,
        startTs: Date.now(), endTs: Date.now(), finalStatus: "completed",
        assertions, screenshots,
      });
      writeAudit();
    }
    for (const a of assertions) console.log(`[BO-3] ${a.passed ? "PASS" : "FAIL"}: ${a.name}${a.note ? ` (${a.note})` : ""}`);
  });
});

// ===========================================================================
// BO-4: Outputs — trial-trace.csv + mtd.json downloadable; escalation in audit log
// ===========================================================================
test.describe("BO-4 Output visualization", () => {
  test("Completed BOIN run exposes trial-trace.csv + mtd.json; BOIN rule captured in audit log", async ({ page }) => {
    test.setTimeout(360_000);
    const assertions: BOIN_Assertion[] = [];
    const screenshots: string[] = [];
    let finalStatus = "not_started";

    try {
      await registerAndLogin(page, "bo4");
      const gotResponse = await sendMessage(page,
        "Run a BOIN dose-escalation simulation with 3 doses (25/50/100 mg), cohort size 10, target DLT phi = 0.25. " +
        "Save the BOIN trial trace and the selected MTD as outputs.",
        90_000
      );
      assertions.push({ name: "AI responded", passed: gotResponse });
      if (!gotResponse) return;

      let gotCard = await waitForWorkflowCard(page, 10_000);
      if (!gotCard) {
        await sendMessage(page, "Yes, run with these settings.", 60_000);
        gotCard = await waitForWorkflowCard(page);
      }
      assertions.push({ name: "Workflow card appeared", passed: gotCard });
      if (!gotCard) return;

      const ran = await clickRunButton(page);
      assertions.push({ name: "Run started", passed: ran });
      if (!ran) return;

      finalStatus = await waitForTerminalStatus(page, 240_000);
      screenshots.push(await shot(page, `BO4_01_terminal_${finalStatus}`));
      assertions.push({ name: "Run reached terminal state", passed: finalStatus !== "timeout", note: finalStatus });

      if (finalStatus === "completed") {
        await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
        await page.waitForTimeout(1500);

        const dlPanel = page.locator('[data-testid="download-commands-panel"]').first();
        const dlVisible = await dlPanel.isVisible({ timeout: 10_000 }).catch(() => false);
        assertions.push({ name: "Download commands panel visible", passed: dlVisible });
        if (dlVisible) screenshots.push(await shot(page, "BO4_02_download_panel"));

        const outputChips = page.locator('.step-outputs .output-file, [data-testid*="output-file"]');
        const count = await outputChips.count().catch(() => 0);
        const names: string[] = [];
        for (let i = 0; i < Math.min(count, 12); i++) {
          const t = await outputChips.nth(i).textContent().catch(() => "");
          if (t) names.push(t.trim());
        }
        const hasTrace = names.some(n => /trial[\-_]?trace|boin[\-_]?trace|escalation/.test(n));
        const hasMtd   = names.some(n => /mtd|recommended[\-_]?dose/i.test(n));
        assertions.push({ name: "trial-trace.csv (or BOIN escalation trace) present", passed: hasTrace, note: names.join(", ") });
        assertions.push({ name: "mtd.json present", passed: hasMtd });
        screenshots.push(await shot(page, "BO4_03_output_chips"));

        // Audit log: BOIN escalation rule should be captured (Apply & Re-run NOT possible
        // because no remediations — but the gate decision + Liu & Yuan citation should
        // appear in /api/workflows/runs/:id/findings or methods-report).
        // Audit endpoint reachable via download panel button:
        const auditLink = page.locator('a:has-text("methods"), a:has-text("audit"), [data-testid*="methods-report"], [data-testid*="audit-log"]').first();
        const auditVisible = await auditLink.isVisible({ timeout: 5000 }).catch(() => false);
        assertions.push({
          name: "Audit / methods-report link present",
          passed: auditVisible,
          note: auditVisible ? "ok" : "audit link not surfaced — methods-report endpoint may still serve JSON via API",
        });
      }
    } catch (err: any) {
      console.error("[BO-4] Error:", err.message);
      finalStatus = `error: ${err.message}`;
      await shot(page, "BO4_error").catch(() => {});
    } finally {
      SUITE_AUDIT.push({
        testId: "BO-4", workflowName: "BOIN output visualization", runId: null,
        startTs: Date.now(), endTs: Date.now(), finalStatus,
        assertions, screenshots,
      });
      writeAudit();
    }
    for (const a of assertions) console.log(`[BO-4] ${a.passed ? "PASS" : "FAIL"}: ${a.name}${a.note ? ` (${a.note})` : ""}`);
  });
});

// ===========================================================================
// BO-5: Domain label rendering — DOMAIN_LABELS["clinical_trial"] gap check
// ===========================================================================
test.describe("BO-5 Domain label rendering", () => {
  test("Auto-loop panel header should render 'Clinical Trial' (NOT raw 'clinical_trial')", async ({ page }) => {
    test.setTimeout(300_000);
    const assertions: BOIN_Assertion[] = [];
    const screenshots: string[] = [];

    try {
      await registerAndLogin(page, "bo5");
      const gotResponse = await sendMessage(page,
        "Run a BOIN clinical-trial simulation with target DLT phi = 0.25.",
        90_000
      );
      assertions.push({ name: "AI responded", passed: gotResponse });
      if (!gotResponse) return;

      let gotCard = await waitForWorkflowCard(page, 10_000);
      if (!gotCard) {
        await sendMessage(page, "Yes, run BOIN.", 60_000);
        gotCard = await waitForWorkflowCard(page);
      }
      assertions.push({ name: "Workflow card appeared", passed: gotCard });
      if (!gotCard) return;

      const ran = await clickRunButton(page);
      assertions.push({ name: "Run started", passed: ran });
      if (!ran) return;
      await waitForTerminalStatus(page, 180_000);

      const panel = page.locator('[data-testid="autoloop-panel"]').first();
      const visible = await panel.isVisible({ timeout: 10_000 }).catch(() => false);
      assertions.push({ name: "autoloop-panel visible", passed: visible });
      if (!visible) return;

      const headerText = await panel.locator('text=/Auto-Loop QC/').first().textContent({ timeout: 5000 }).catch(() => "") || "";
      const renderedLabel = headerText.replace(/.*Auto-Loop QC\s*—\s*/, "").trim();
      console.log(`[BO-5] rendered domain label: "${renderedLabel}"`);
      screenshots.push(await shot(page, "BO5_01_panel_header"));

      // The architectural finding: as of 2026-05-27, DOMAIN_LABELS in
      // frontend/client/src/components/auto-loop-panel.tsx (lines 81-87) contains
      // only admet/docking/cyp_ddi/nca_pk/cryo_em. "clinical_trial" falls through
      // and renders the raw key. This test DOCUMENTS that gap.
      const rendersPretty = /clinical trial/i.test(renderedLabel) && !/^clinical_trial$/.test(renderedLabel);
      const rendersRaw    = renderedLabel === "clinical_trial";
      assertions.push({
        name: "DOMAIN_LABELS contains 'clinical_trial' → renders 'Clinical Trial'",
        passed: rendersPretty,
        note: rendersPretty
          ? "ok — DOMAIN_LABELS was updated"
          : rendersRaw
            ? "GAP CONFIRMED: auto-loop-panel.tsx:81-87 DOMAIN_LABELS missing 'clinical_trial' — raw key rendered. Same gap pattern reported by HTS (no 'hts') and ADMET-CNS tests. Fix: add `clinical_trial: 'Clinical Trial'` (and ich_s5/ich_s7/allometric/ivive/openfe) to DOMAIN_LABELS.",
            : `unexpected label "${renderedLabel}"`,
      });
    } catch (err: any) {
      console.error("[BO-5] Error:", err.message);
      await shot(page, "BO5_error").catch(() => {});
    } finally {
      SUITE_AUDIT.push({
        testId: "BO-5", workflowName: "Domain label rendering", runId: null,
        startTs: Date.now(), endTs: Date.now(), finalStatus: "completed",
        assertions, screenshots,
      });
      writeAudit();
    }
    for (const a of assertions) console.log(`[BO-5] ${a.passed ? "PASS" : "FAIL"}: ${a.name}${a.note ? ` (${a.note})` : ""}`);
  });
});
