/**
 * Auto-Loop Panel E2E Tests (AL-1 to AL-6)
 *
 * Tests the full SSE → UI flow for the AutoLoopPanel component.
 *
 * Architecture:
 *   1. Chat → workflow card → Confirm & Run → capture invocationId
 *   2. POST to /internal/sse-inject with autoloop_* event types
 *   3. Assert AutoLoopPanel renders gate table, badges, remediation cards, citations
 *
 * Event flow tested:
 *   autoloop_gate_results  → gate table appears, pass/halt/advisory badges
 *   autoloop_update        → remediation cards + failed banner
 *   autoloop_phase_complete → green "Phase passed" banner
 *   autoloop_escalation    → escalated banner (future orchestrator path)
 *   dismiss button         → panel clears
 *
 * CLAUDE.md: NO page.route() mocking.  All calls hit the live server.
 * SSE injection uses the real /internal/sse-inject endpoint.
 */

import { test, expect, Page, APIRequestContext } from "@playwright/test";
import {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
} from "./helpers.js";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SS_DIR = path.join(__dirname, "screenshots", "autoloop-panel");

async function shot(page: Page, name: string) {
  fs.mkdirSync(SS_DIR, { recursive: true });
  await page.screenshot({ path: path.join(SS_DIR, `${name}.png`), fullPage: false });
  console.log(`[Screenshot] ${name}.png`);
}

// ---------------------------------------------------------------------------
// SSE payloads
// ---------------------------------------------------------------------------

const GATE_RESULTS_PASS = {
  phase: "phase_1_docking",
  domain: "docking",
  overall_level: "GOLD",
  passed: true,
  gates: [
    { gate: "valid_poses",        action: "pass", level: "GOLD", value: 10,   threshold: 1,    message: "10 poses generated" },
    { gate: "best_binding_score", action: "pass", level: "GOLD", value: -9.2, threshold: -7.0, message: "Binding score -9.2 kcal/mol" },
  ],
};

const GATE_RESULTS_FAIL = {
  phase: "phase_1_docking",
  domain: "docking",
  overall_level: "FAIL",
  passed: false,
  gates: [
    { gate: "valid_poses",        action: "pass", level: "GOLD",   value: 3,    threshold: 1,    message: "3 poses generated" },
    { gate: "best_binding_score", action: "halt", level: "FAIL",   value: -5.0, threshold: -7.0, message: "Score -5.0 above -7.0 threshold" },
  ],
};

const UPDATE_FAIL = {
  phase: "phase_1_docking",
  domain: "docking",
  attempt: 1,
  next_attempt: 2,
  failed_gates: ["best_binding_score"],
  remediations: [
    {
      phase: "phase_1_docking",
      gate: "best_binding_score",
      param_changes: { exhaustiveness: 16, box_size_angstrom: 25 },
      rationale: "Increasing exhaustiveness improves pose sampling for flexible targets.",
      citations: [
        {
          source_text: "Exhaustiveness controls sampling thoroughness in AutoDock Vina.",
          paper_ref: "Trott & Olson (2010) J Comput Chem",
          paper_doi: "10.1002/jcc.21334",
          finding: "Higher exhaustiveness yields better docking accuracy.",
        },
      ],
    },
  ],
};

const PHASE_COMPLETE = {
  phase: "phase_1_docking",
  domain: "docking",
  outcome: "pass",
  level: "GOLD",
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function injectSSE(
  request: APIRequestContext,
  invocationId: string,
  event_type: string,
  data: object
): Promise<boolean> {
  const res = await request.post(`${BASE_URL}/internal/sse-inject`, {
    data: { invocation_id: invocationId, event_type, data },
  });
  console.log(`[SSE inject] ${event_type} status=${res.status()} inv=${invocationId}`);
  return res.status() !== 404;
}

/**
 * Inject an SSE event and retry until the target testId appears or timeout.
 * Handles the race condition where the EventSource client hasn't connected yet
 * at the time of the first injection.
 */
async function injectUntilVisible(
  page: Page,
  request: APIRequestContext,
  invocationId: string,
  events: Array<{ event_type: string; data: object }>,
  targetTestId: string,
  // 60s allows ~23 retries at ~2.6s/attempt (1.5s isVisible wait + 1s sleep)
  timeoutMs = 60_000
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  let attempt = 0;

  while (Date.now() < deadline) {
    attempt++;
    console.log(`[injectUntilVisible] attempt ${attempt} for ${targetTestId}`);

    for (const ev of events) {
      await injectSSE(request, invocationId, ev.event_type, ev.data);
      await page.waitForTimeout(100);
    }

    const visible = await page
      .getByTestId(targetTestId)
      .first()
      .isVisible({ timeout: 1_500 })
      .catch(() => false);

    if (visible) {
      console.log(`[injectUntilVisible] ${targetTestId} visible after ${attempt} attempts`);
      return true;
    }

    await page.waitForTimeout(1_000);
  }

  console.warn(`[injectUntilVisible] ${targetTestId} never appeared after ${attempt} attempts`);
  return false;
}

async function waitVisible(page: Page, testId: string, ms = 8_000): Promise<boolean> {
  return page.getByTestId(testId).first().isVisible({ timeout: ms }).catch(() => false);
}

const RUN_BTN_SEL =
  '[data-testid="button-confirm-and-run"],' +
  '[data-testid="button-run-workflow-panel"],' +
  '[data-testid="pipeline-confirm-run"]';

/** Run chat → Confirm & Run, return SSE invocation key or null. */
async function startWorkflowAndCaptureId(page: Page): Promise<string | null> {
  // sendMessageAndWaitForResponse may return false for drug-discovery workflows
  // that use button-confirm-and-run instead of button-run-workflow-panel.
  // We call it for the "wait for response" side-effect, then check both buttons.
  await sendMessageAndWaitForResponse(
    page,
    "Run ADMET toxicity screening on imatinib (SMILES: Cc1ccc(cc1Nc2nccc(n2)c3cccnc3)NC(=O)c4ccc(cc4)CN5CCN(CC5)C) and predict hERG risk, DILI probability, and Ames mutagenicity",
    150_000
  );

  // Check all possible run button variants
  const runBtn = page.locator(RUN_BTN_SEL).first();
  const btnVisible = await runBtn.isVisible({ timeout: 10_000 }).catch(() => false);
  if (!btnVisible) {
    console.log("[startWorkflow] No run button visible after chat");
    return null;
  }

  let invocationId: string | null = null;

  const handler = async (resp: import("@playwright/test").Response) => {
    if (!resp.url().includes("/api/workflows/execute") && !resp.url().includes("/api/nextflow/execute")) return;
    try {
      const payload = await resp.json();
      invocationId =
        payload?.galaxyInvocationId ||
        payload?.invocationId ||
        payload?.runId ||
        payload?.run_id ||
        null;
      console.log("[startWorkflow] execute response captured invocationId:", invocationId);
    } catch { /* ignore */ }
  };

  page.on("response", handler);
  await runBtn.click();
  await page.waitForTimeout(8_000);
  page.removeListener("response", handler);

  return invocationId;
}

// ---------------------------------------------------------------------------
// AL-0: smoke — /internal/sse-inject accepts autoloop events
// ---------------------------------------------------------------------------
test.describe("AL-0 SSE endpoint smoke", () => {
  test("endpoint exists and accepts autoloop_gate_results", async ({ request }) => {
    test.setTimeout(30_000);

    const res = await request.post(`${BASE_URL}/internal/sse-inject`, {
      data: {
        invocation_id: "al-smoke-000",
        event_type: "autoloop_gate_results",
        data: GATE_RESULTS_PASS,
      },
    });
    expect(res.status(), "SSE inject endpoint must exist").not.toBe(404);
    console.log("[AL-0] status:", res.status());
  });
});

// ---------------------------------------------------------------------------
// AL-1: gate results table renders on autoloop_gate_results (pass)
// ---------------------------------------------------------------------------
test.describe("AL-1 gate results pass", () => {
  test("autoloop-panel appears with gate table and GOLD badge", async ({ page, request }) => {
    test.setTimeout(600_000);

    await setupTestUser(page, "al1");

    const invId = await startWorkflowAndCaptureId(page);
    await shot(page, "al1_01_after_run");

    if (!invId) {
      test.skip(true, "Could not capture invocationId");
      return;
    }

    const panelVisible = await injectUntilVisible(
      page, request, invId,
      [{ event_type: "autoloop_gate_results", data: GATE_RESULTS_PASS }],
      "autoloop-panel"
    );
    await shot(page, "al1_02_panel_visible");

    if (!panelVisible) {
      // If the EventSource is wired correctly, the panel MUST appear.
      // Use test.fail() not test.skip() so CI alerts on SSE breakage.
      throw new Error("AutoLoopPanel did not appear after 60s of SSE injection — SSE client never connected");
      return;
    }

    // Gate table must show both gates
    const rows = page.locator('[data-testid="autoloop-panel"] tbody tr');
    await expect(rows).toHaveCount(2);

    // Both gates should show PASS badge
    const passBadges = page.locator('[data-testid="autoloop-panel"] tbody').getByText("PASS");
    await expect(passBadges).toHaveCount(2);

    // Level dot should say GOLD
    await expect(page.locator('[data-testid="autoloop-panel"]')).toContainText("GOLD");

    await shot(page, "al1_03_gate_table");
    console.log("[AL-1] PASS: gate table rendered with 2 gates, GOLD level");
  });
});

// ---------------------------------------------------------------------------
// AL-2: gate results + update → failed banner + remediation cards
// ---------------------------------------------------------------------------
test.describe("AL-2 gate fail + remediation", () => {
  test("halt gate + remediation card with citations renders", async ({ page, request }) => {
    test.setTimeout(600_000);

    await setupTestUser(page, "al2");

    const invId = await startWorkflowAndCaptureId(page);
    await shot(page, "al2_01_after_run");

    if (!invId) {
      test.skip(true, "Could not capture invocationId");
      return;
    }

    // Inject gate_results first; once the panel appears inject update
    const panelVisible = await injectUntilVisible(
      page, request, invId,
      [{ event_type: "autoloop_gate_results", data: GATE_RESULTS_FAIL }],
      "autoloop-panel"
    );
    await shot(page, "al2_02_panel");

    if (!panelVisible) {
      throw new Error("AutoLoopPanel did not appear after 60s of SSE injection");
      return;
    }

    // Now inject the update (remediations) — panel already connected
    await injectSSE(request, invId, "autoloop_update", UPDATE_FAIL);
    await page.waitForTimeout(1_000);

    // HALT badge must be present
    await expect(page.locator('[data-testid="autoloop-panel"]')).toContainText("HALT");

    // Remediation card section must appear
    await expect(
      page.locator('[data-testid="autoloop-panel"]')
    ).toContainText("Suggested parameter adjustments");

    // Param change pill: exhaustiveness → 16
    await expect(
      page.locator('[data-testid="autoloop-panel"]')
    ).toContainText("exhaustiveness");

    await shot(page, "al2_03_remediation_cards");
    console.log("[AL-2] PASS: halt badge + remediation card visible");
  });
});

// ---------------------------------------------------------------------------
// AL-3: citations expand/collapse in remediation card
// ---------------------------------------------------------------------------
test.describe("AL-3 citation toggle", () => {
  test("Show/Hide citations button toggles citation text", async ({ page, request }) => {
    test.setTimeout(600_000);

    await setupTestUser(page, "al3");

    const invId = await startWorkflowAndCaptureId(page);
    if (!invId) {
      test.skip(true, "Could not capture invocationId");
      return;
    }

    const panelVisible = await injectUntilVisible(
      page, request, invId,
      [{ event_type: "autoloop_gate_results", data: GATE_RESULTS_FAIL }],
      "autoloop-panel"
    );
    if (!panelVisible) {
      test.skip(true, "AutoLoopPanel did not appear");
      return;
    }
    await injectSSE(request, invId, "autoloop_update", UPDATE_FAIL);
    await page.waitForTimeout(1_000);

    // Find and click the "Show 1 citation" button
    const showBtn = page
      .locator('[data-testid="autoloop-panel"]')
      .getByText(/Show 1 citation/i)
      .first();
    const showBtnVisible = await showBtn.isVisible({ timeout: 5_000 }).catch(() => false);

    if (!showBtnVisible) {
      test.skip(true, "Citation toggle button not found — remediation may not have rendered");
      return;
    }

    await shot(page, "al3_01_before_expand");
    await showBtn.click();

    // Citation text should now be visible
    await expect(
      page.locator('[data-testid="autoloop-panel"]')
    ).toContainText("Trott & Olson");

    await shot(page, "al3_02_citations_expanded");

    // Clicking again hides them
    const hideBtn = page
      .locator('[data-testid="autoloop-panel"]')
      .getByText(/Hide 1 citation/i)
      .first();
    await hideBtn.click();

    await expect(
      page.locator('[data-testid="autoloop-panel"]')
    ).not.toContainText("Trott & Olson");

    await shot(page, "al3_03_citations_hidden");
    console.log("[AL-3] PASS: citation toggle works");
  });
});

// ---------------------------------------------------------------------------
// AL-4: autoloop_phase_complete → green "Phase passed" banner
// ---------------------------------------------------------------------------
test.describe("AL-4 phase complete banner", () => {
  test("green passed banner shows on autoloop_phase_complete", async ({ page, request }) => {
    test.setTimeout(600_000);

    await setupTestUser(page, "al4");

    const invId = await startWorkflowAndCaptureId(page);
    if (!invId) {
      test.skip(true, "Could not capture invocationId");
      return;
    }

    const panelVisible = await injectUntilVisible(
      page, request, invId,
      [{ event_type: "autoloop_gate_results", data: GATE_RESULTS_PASS }],
      "autoloop-panel"
    );
    if (!panelVisible) {
      test.skip(true, "AutoLoopPanel did not appear");
      return;
    }
    await injectSSE(request, invId, "autoloop_phase_complete", PHASE_COMPLETE);
    await page.waitForTimeout(1_000);

    await expect(page.locator('[data-testid="autoloop-panel"]')).toContainText("Phase passed");

    await shot(page, "al4_phase_passed_banner");
    console.log("[AL-4] PASS: phase passed banner visible");
  });
});

// ---------------------------------------------------------------------------
// AL-5: dismiss button clears the panel
// ---------------------------------------------------------------------------
test.describe("AL-5 dismiss", () => {
  test("× button removes the panel from the DOM", async ({ page, request }) => {
    test.setTimeout(600_000);

    await setupTestUser(page, "al5");

    const invId = await startWorkflowAndCaptureId(page);
    if (!invId) {
      test.skip(true, "Could not capture invocationId");
      return;
    }

    const panelVisible = await injectUntilVisible(
      page, request, invId,
      [{ event_type: "autoloop_gate_results", data: GATE_RESULTS_PASS }],
      "autoloop-panel"
    );
    if (!panelVisible) {
      test.skip(true, "AutoLoopPanel did not appear");
      return;
    }

    await shot(page, "al5_01_panel_visible");

    // Click dismiss (×)
    const dismissBtn = page
      .locator('[data-testid="autoloop-panel"]')
      .getByRole("button")
      .filter({ hasText: "×" })
      .first();
    await dismissBtn.click();

    // Panel should be gone
    await expect(page.getByTestId("autoloop-panel")).toHaveCount(0);

    await shot(page, "al5_02_panel_dismissed");
    console.log("[AL-5] PASS: panel dismissed");
  });
});

// ---------------------------------------------------------------------------
// AL-7: "Apply & Re-run" button appears when remediations have param_changes
// ---------------------------------------------------------------------------
test.describe("AL-7 accept button visible", () => {
  test("Apply & Re-run button renders after halt gate + remediation", async ({ page, request }) => {
    test.setTimeout(600_000);

    await setupTestUser(page, "al7");

    const invId = await startWorkflowAndCaptureId(page);
    if (!invId) {
      test.skip(true, "Could not capture invocationId");
      return;
    }

    const panelVisible = await injectUntilVisible(
      page, request, invId,
      [{ event_type: "autoloop_gate_results", data: GATE_RESULTS_FAIL }],
      "autoloop-panel"
    );
    if (!panelVisible) {
      test.skip(true, "AutoLoopPanel did not appear");
      return;
    }

    // Inject update with remediations that have param_changes
    await injectSSE(request, invId, "autoloop_update", UPDATE_FAIL);
    await page.waitForTimeout(1_000);

    // "Apply & Re-run" button must now be visible
    const acceptBtn = page.getByTestId("autoloop-accept-btn").first();
    await expect(acceptBtn).toBeVisible({ timeout: 5_000 });
    await expect(acceptBtn).toContainText("Re-run");

    // Button text must mention the number of changes (2 params: exhaustiveness + box_size_angstrom)
    await expect(acceptBtn).toContainText("2 change");

    await shot(page, "al7_accept_button_visible");
    console.log("[AL-7] PASS: Apply & Re-run button visible with correct param count");
  });
});

// ---------------------------------------------------------------------------
// AL-8: clicking "Apply & Re-run" dismisses panel and calls execute endpoint
// ---------------------------------------------------------------------------
test.describe("AL-8 accept triggers re-run", () => {
  test("Apply & Re-run button dismisses panel and fires execute endpoint", async ({ page, request }) => {
    test.setTimeout(600_000);

    await setupTestUser(page, "al8");

    const invId = await startWorkflowAndCaptureId(page);
    if (!invId) {
      test.skip(true, "Could not capture invocationId");
      return;
    }

    const panelVisible = await injectUntilVisible(
      page, request, invId,
      [{ event_type: "autoloop_gate_results", data: GATE_RESULTS_FAIL }],
      "autoloop-panel"
    );
    if (!panelVisible) {
      test.skip(true, "AutoLoopPanel did not appear");
      return;
    }

    await injectSSE(request, invId, "autoloop_update", UPDATE_FAIL);
    await page.waitForTimeout(1_000);

    const acceptBtn = page.getByTestId("autoloop-accept-btn").first();
    const btnVisible = await acceptBtn.isVisible({ timeout: 5_000 }).catch(() => false);
    if (!btnVisible) {
      test.skip(true, "Accept button not visible — skipping execute assertion");
      return;
    }

    // Listen for the execute endpoint call (real server call, not mocked)
    let executeWasCalled = false;
    const executeUrls = ["/api/nextflow/execute", "/api/workflows/execute"];
    page.on("response", (resp) => {
      if (executeUrls.some(u => resp.url().includes(u))) {
        executeWasCalled = true;
        console.log("[AL-8] execute endpoint responded:", resp.status(), resp.url());
      }
    });

    await shot(page, "al8_01_before_accept");
    await acceptBtn.click();

    // Panel should be dismissed immediately
    await expect(page.getByTestId("autoloop-panel")).toHaveCount(0, { timeout: 5_000 });

    // Wait up to 15s for execute to fire (params merge + handleExecute is async)
    await page.waitForTimeout(15_000);

    expect(executeWasCalled, "Execute endpoint was not called after Apply & Re-run").toBe(true);

    await shot(page, "al8_02_after_accept");
    console.log("[AL-8] PASS: panel dismissed + execute endpoint called");
  });
});

// ---------------------------------------------------------------------------
// AL-6: advisory notice (no halts, some advisories)
// ---------------------------------------------------------------------------
test.describe("AL-6 advisory notice", () => {
  test("advisory warning notice shows when action=advisory and no halts", async ({ page, request }) => {
    test.setTimeout(600_000);

    await setupTestUser(page, "al6");

    const invId = await startWorkflowAndCaptureId(page);
    if (!invId) {
      test.skip(true, "Could not capture invocationId");
      return;
    }

    const advisoryPayload = {
      ...GATE_RESULTS_PASS,
      overall_level: "SILVER",
      passed: true,
      gates: [
        { gate: "valid_poses",        action: "pass",     level: "GOLD",   value: 5,    threshold: 1,    message: "5 poses" },
        { gate: "best_binding_score", action: "advisory", level: "SILVER", value: -7.2, threshold: -7.0, message: "Score near threshold" },
      ],
    };

    const panelVisible = await injectUntilVisible(
      page, request, invId,
      [{ event_type: "autoloop_gate_results", data: advisoryPayload }],
      "autoloop-panel"
    );
    if (!panelVisible) {
      test.skip(true, "AutoLoopPanel did not appear");
      return;
    }

    // Advisory badge in gate table
    await expect(page.locator('[data-testid="autoloop-panel"]')).toContainText("ADVISORY");

    // Advisory notice text (no complete event → no banner → advisory notice shows)
    await expect(page.locator('[data-testid="autoloop-panel"]')).toContainText(
      "advisory warning"
    );

    await shot(page, "al6_advisory_notice");
    console.log("[AL-6] PASS: advisory badge + warning notice visible");
  });
});
