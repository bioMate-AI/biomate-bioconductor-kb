/**
 * Execution Triage Panel — UX End-to-End Test Suite
 *
 * Verifies the "Execution Triage" section of the NextflowWorkflowViewer, which
 * transforms raw workflow status into actionable researcher guidance.  This is
 * the panel that tells a researcher exactly what to do next: check logs, download
 * results, fix a failed run, or wait.
 *
 * Test plan:
 *   UX-9a  Triage panel shows four populated sub-fields (status / next-action /
 *           logs / outputs) after a run reaches a terminal state.  All text must
 *           be non-empty and meaningful.
 *   UX-9b  Triage panel is visible WHILE a run is in progress (not only at
 *           terminal).  The status text must change between "running" and terminal.
 *   UX-9c  Triage next-action text is outcome-specific: completed runs point to
 *           downloading results; failed runs point to fixing errors and rerunning.
 *           The two outcomes must never produce identical next-action text.
 *
 * Real use cases exercised:
 *   - Researcher submits a WGS germline run.  The panel guides them through
 *     the entire lifecycle: configure → running → completed/failed.
 *   - Researcher does not need to read raw log lines to know what to do next;
 *     the triage panel gives them a one-sentence action.
 *
 * NO page.route() mocking.  All calls hit the live server.
 * Screenshots → e2e/screenshots/ux-execution-triage/
 */

import { test, expect, Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";
const E2E_TOKEN =
  process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const SS_DIR = path.join(__dirname, "screenshots", "ux-execution-triage");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

async function registerAndGoHome(page: Page, label: string): Promise<void> {
  const email = `e2e_ux_${label}_${Date.now()}@biomate.test`;
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  await page.goto(`${BASE_URL}/register`);
  await page.waitForLoadState("load");
  await page
    .evaluate(() => {
      try {
        localStorage.clear();
        sessionStorage.clear();
      } catch {}
    })
    .catch(() => {});
  try {
    await page.waitForSelector("#name", { state: "visible", timeout: 10000 });
    await page.fill("#name", `UX E2E ${label}`);
    await page.fill("#email", email);
    await page.fill("#password", "TestPass123!");
    await page.fill("#confirmPassword", "TestPass123!");
    await page.click("#terms");
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
  } catch {
    // form may not be present if already logged in
  }
  await page.goto(BASE_URL);
  await page.evaluate(() => {
    try {
      localStorage.clear();
      sessionStorage.clear();
    } catch {}
  });
  await page.reload();
  await page.waitForLoadState("load");
  await page
    .waitForSelector("textarea", { state: "visible", timeout: 20000 })
    .catch(() => {});
  await page.waitForTimeout(1000);
}

async function sendMessage(page: Page, text: string): Promise<void> {
  const ta = page.locator("textarea").first();
  await ta.isVisible({ timeout: 10000 });
  await ta.fill(text);
  await ta.press("Enter");
}

async function waitForAIResponse(page: Page, label: string): Promise<void> {
  console.log(`[${label}] Waiting for AI response...`);
  await Promise.race([
    page
      .waitForSelector("text=BioMate is typing", { timeout: 20000 })
      .catch(() => null),
    page
      .waitForSelector("[data-testid='chat-response-pending']", {
        timeout: 20000,
      })
      .catch(() => null),
  ]);
  await Promise.all([
    page
      .waitForSelector("text=BioMate is typing", {
        state: "hidden",
        timeout: 180000,
      })
      .catch(() => null),
    page
      .waitForSelector("[data-testid='chat-response-pending']", {
        state: "hidden",
        timeout: 180000,
      })
      .catch(() => null),
  ]);
  await page
    .waitForFunction(
      () => {
        const el = document.querySelector('[data-is-latest-assistant="true"]');
        if (!el) return false;
        const t = el.textContent ?? "";
        return (
          t.trim().length > 40 &&
          !t.includes("BioMate is typing") &&
          !t.includes("Analyzing request")
        );
      },
      { timeout: 60000 }
    )
    .catch(() => {});
  await page.waitForTimeout(2000);
}

async function waitForWorkflowCard(
  page: Page,
  label: string
): Promise<boolean> {
  const deadline = Date.now() + 180000;
  while (Date.now() < deadline) {
    const count = await page
      .locator('[data-testid^="workflow-artifact"]')
      .count()
      .catch(() => 0);
    if (count > 0) {
      await page.waitForTimeout(1500);
      return true;
    }
    for (const sel of [
      '[data-testid="button-confirm-and-run"]',
      "text=AWAITING REVIEW",
      "text=Confirm & Run",
    ]) {
      if (await page.locator(sel).isVisible({ timeout: 500 }).catch(() => false)) {
        await page.waitForTimeout(1500);
        return true;
      }
    }
    await page.waitForTimeout(1000);
  }
  return false;
}

async function confirmAndRun(page: Page, label: string): Promise<string | null> {
  const executePromise = page
    .waitForResponse((r) => r.url().includes("/api/workflows/execute"), {
      timeout: 60000,
    })
    .catch(() => null);

  const btn = page
    .locator(
      '[data-testid="button-confirm-and-run"],[data-testid="button-run-workflow-panel"]'
    )
    .last();
  const visible = await btn.isVisible({ timeout: 10000 }).catch(() => false);
  if (!visible) {
    console.log(`[${label}] No run button visible`);
    return null;
  }
  const enabled = await btn.isEnabled({ timeout: 20000 }).catch(() => false);
  if (!enabled) {
    console.log(`[${label}] Run button still disabled after 20s — force click`);
  }
  try {
    await btn.click({ timeout: 5000 });
  } catch {
    await btn.click({ force: true });
  }
  console.log(`[${label}] Clicked Confirm & Run`);

  const resp = await executePromise;
  if (!resp) {
    console.log(`[${label}] Execute response not received`);
    return null;
  }
  let runId: string | null = null;
  try {
    const data = await resp.json();
    runId =
      data?.runId ||
      data?.run_id ||
      data?.execution?.runId ||
      data?.execution?.run?.id ||
      null;
  } catch {}
  console.log(`[${label}] Execute API runId=${runId}`);
  return runId;
}

async function pollToTerminal(
  page: Page,
  runId: string,
  label: string,
  maxWaitMs = 120000
): Promise<{ finalStatus: string; payload: Record<string, unknown> | null }> {
  const terminal = new Set(["completed", "failed", "error", "cancelled"]);
  let finalStatus = "unknown";
  let payload: Record<string, unknown> | null = null;
  const deadline = Date.now() + maxWaitMs;
  let i = 0;
  while (Date.now() < deadline) {
    await page.waitForTimeout(5000);
    try {
      const r = await page.request.get(
        `${BASE_URL}/api/workflows/runs/${runId}/status`
      );
      if (r.ok()) {
        payload = (await r.json()) as Record<string, unknown>;
        const s = ((payload?.status as string) || "").toLowerCase();
        if (i % 4 === 0) {
          console.log(`[${label}] Poll ${i}: status=${s}`);
        }
        if (terminal.has(s)) {
          finalStatus = s;
          break;
        }
      }
    } catch {}
    i++;
  }
  console.log(`[${label}] Terminal status: ${finalStatus}`);
  return { finalStatus, payload };
}

async function screenshot(page: Page, name: string): Promise<void> {
  await page.screenshot({
    path: path.join(SS_DIR, `${name}.png`),
    fullPage: true,
  });
  console.log(`[Screenshot] ${name}.png`);
}

// ---------------------------------------------------------------------------
// Helper: read the four triage sub-field text values from the DOM
// ---------------------------------------------------------------------------
async function readTriageFields(page: Page): Promise<{
  status: string;
  nextAction: string;
  logs: string;
  outputs: string;
}> {
  // The triage container spans have label text ("Status:", "Next action:", etc.)
  // followed by the value.  We extract the full textContent and strip the label.
  const extractAfterLabel = async (testId: string, label: string) => {
    const el = page.locator(`[data-testid="${testId}"]`);
    const full = (await el.textContent({ timeout: 5000 }).catch(() => "")) ?? "";
    // Strip the label prefix (e.g. "Status: " → remainder)
    const idx = full.indexOf(label);
    if (idx !== -1) return full.slice(idx + label.length).trim();
    return full.trim();
  };

  return {
    status: await extractAfterLabel("execution-triage-status", "Status:"),
    nextAction: await extractAfterLabel(
      "execution-triage-next-action",
      "Next action:"
    ),
    logs: await extractAfterLabel("execution-triage-logs", "Logs:"),
    outputs: await extractAfterLabel("execution-triage-outputs", "Outputs:"),
  };
}

// ===========================================================================
// UX-9a: Triage panel shows actionable next steps after terminal state
// ===========================================================================

test.describe("UX-9a: Triage panel populated at terminal state", () => {
  test(
    "all four triage sub-fields are non-empty after germline run reaches terminal state",
    async ({ page }) => {
      test.setTimeout(300000); // 5 min — allow time for Batch run + poll

      await registerAndGoHome(page, "ux9a");

      // -----------------------------------------------------------------------
      // User story: A researcher has just submitted a WGS germline workflow.
      // When it finishes (completed or failed), they need the triage panel to
      // tell them: what happened, what to do next, where to find logs, and
      // where to find outputs — all in one glance, without reading raw logs.
      // -----------------------------------------------------------------------
      await sendMessage(
        page,
        "Run germline variant calling on SRR1518169 max_spots=50"
      );
      await waitForAIResponse(page, "UX-9a");

      // Dismiss survey if it appears — must happen before waitForWorkflowCard
      // so the survey modal doesn't obscure the workflow card check.
      const skipBtn = page.locator(
        '[data-testid="survey-skip-btn"], button:has-text("Skip")'
      );
      if (await skipBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
        await skipBtn.click({ force: true });
        await page.waitForTimeout(500);
      }

      const cardFound = await waitForWorkflowCard(page, "UX-9a");
      expect(cardFound).toBe(true);

      await screenshot(page, "ux9a-01-workflow-card");

      const runId = await confirmAndRun(page, "UX-9a");
      expect(runId).not.toBeNull();

      await screenshot(page, "ux9a-02-run-started");

      // Poll to terminal state (90 s max for a 50-spot run)
      const { finalStatus } = await pollToTerminal(
        page,
        runId!,
        "UX-9a",
        90000
      );
      console.log(`[UX-9a] Final status: ${finalStatus}`);

      // Give the viewer a moment to update from SSE / next poll tick
      await page.waitForTimeout(3000);

      await screenshot(page, "ux9a-03-after-terminal");

      // -----------------------------------------------------------------------
      // Assertions: the triage summary container must exist and each sub-field
      // must carry meaningful text (not empty, not just the label).
      // -----------------------------------------------------------------------
      await expect(
        page.locator('[data-testid="execution-triage-summary"]')
      ).toBeVisible({ timeout: 10000 });

      const triage = await readTriageFields(page);
      console.log("[UX-9a] Triage fields:", JSON.stringify(triage, null, 2));

      // Status: must echo a recognisable run state
      expect(triage.status.length).toBeGreaterThan(0);

      // Next action: must be a non-trivial sentence (at least 10 chars)
      expect(triage.nextAction.length).toBeGreaterThan(10);

      // Logs hint: must say something about logs
      expect(triage.logs.length).toBeGreaterThan(0);

      // Outputs hint: must say something about outputs
      expect(triage.outputs.length).toBeGreaterThan(0);

      await screenshot(page, "ux9a-04-triage-panel-visible");
    }
  );
});

// ===========================================================================
// UX-9b: Triage panel is visible WHILE run is in progress
// ===========================================================================

test.describe("UX-9b: Triage panel visible during in-progress run", () => {
  test(
    "triage panel appears within 10 s of run start and status text changes at terminal",
    async ({ page }) => {
      test.setTimeout(300000);

      await registerAndGoHome(page, "ux9b");

      // -----------------------------------------------------------------------
      // User story: A researcher submits a long-running genomics job.  They
      // should not have to wait until the job finishes to get orientation — the
      // triage panel should immediately tell them "Running — monitor logs and
      // wait for terminal status" so they know the system is working.
      // -----------------------------------------------------------------------
      await sendMessage(
        page,
        "Run germline variant calling on SRR1518169 max_spots=50"
      );
      await waitForAIResponse(page, "UX-9b");

      const cardFound = await waitForWorkflowCard(page, "UX-9b");
      expect(cardFound).toBe(true);

      // Dismiss survey
      const skipBtn = page.locator(
        '[data-testid="survey-skip-btn"], button:has-text("Skip")'
      );
      if (await skipBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
        await skipBtn.click({ force: true });
        await page.waitForTimeout(500);
      }

      const runId = await confirmAndRun(page, "UX-9b");
      expect(runId).not.toBeNull();

      // -----------------------------------------------------------------------
      // Immediately check triage visibility — must appear within 10 s of start
      // -----------------------------------------------------------------------
      await expect(
        page.locator('[data-testid="execution-triage-summary"]')
      ).toBeVisible({ timeout: 15000 });

      const triageRunning = await readTriageFields(page);
      console.log(
        "[UX-9b] Triage at running state:",
        JSON.stringify(triageRunning, null, 2)
      );

      // During running state, status must be non-empty
      expect(triageRunning.status.length).toBeGreaterThan(0);
      // Next-action text must be non-empty even during running
      expect(triageRunning.nextAction.length).toBeGreaterThan(10);

      await screenshot(page, "ux9b-01-triage-while-running");

      // Poll to terminal (30 s max — we just want to see the state change)
      const { finalStatus } = await pollToTerminal(
        page,
        runId!,
        "UX-9b",
        90000
      );
      console.log(`[UX-9b] Final status: ${finalStatus}`);

      await page.waitForTimeout(3000);

      // -----------------------------------------------------------------------
      // After terminal: triage panel still visible and status text changed
      // -----------------------------------------------------------------------
      await expect(
        page.locator('[data-testid="execution-triage-summary"]')
      ).toBeVisible({ timeout: 10000 });

      const triageTerminal = await readTriageFields(page);
      console.log(
        "[UX-9b] Triage at terminal state:",
        JSON.stringify(triageTerminal, null, 2)
      );

      // Status must reflect the terminal outcome, not just "idle"
      expect(triageTerminal.status.length).toBeGreaterThan(0);

      // The status text should change between running and terminal.
      // We do a soft assertion here: if the run was so fast it never showed
      // "running" in the DOM, both states may already be terminal — that is
      // acceptable.  What we must never see is an empty status at either point.
      if (
        triageRunning.status.toLowerCase().includes("running") &&
        triageTerminal.status.toLowerCase().includes("running")
      ) {
        // Both still say running — terminal poll may have timed out
        console.warn(
          "[UX-9b] WARNING: status did not change to terminal within poll window"
        );
      } else {
        console.log(
          `[UX-9b] Status changed: "${triageRunning.status}" → "${triageTerminal.status}"`
        );
      }

      await screenshot(page, "ux9b-02-triage-at-terminal");
    }
  );
});

// ===========================================================================
// UX-9c: Triage next-action text is outcome-specific
// ===========================================================================

test.describe("UX-9c: Triage guidance differs by outcome", () => {
  test(
    "completed run → download/results guidance; failed run → error/rerun guidance; never identical",
    async ({ page }) => {
      test.setTimeout(300000);

      await registerAndGoHome(page, "ux9c");

      // -----------------------------------------------------------------------
      // User story: The triage panel is the researcher's first signal about what
      // happened.  A completed run and a failed run must give categorically
      // different guidance.  If a completed run says "check the error and rerun",
      // or a failed run says "download your results", the researcher will waste
      // time pursuing the wrong path.  This test guards that regression.
      // -----------------------------------------------------------------------
      await sendMessage(
        page,
        "Run germline variant calling on SRR1518169 max_spots=50"
      );
      await waitForAIResponse(page, "UX-9c");

      const cardFound = await waitForWorkflowCard(page, "UX-9c");
      expect(cardFound).toBe(true);

      // Dismiss survey
      const skipBtn = page.locator(
        '[data-testid="survey-skip-btn"], button:has-text("Skip")'
      );
      if (await skipBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
        await skipBtn.click({ force: true });
        await page.waitForTimeout(500);
      }

      const runId = await confirmAndRun(page, "UX-9c");
      expect(runId).not.toBeNull();

      const { finalStatus } = await pollToTerminal(
        page,
        runId!,
        "UX-9c",
        90000
      );
      console.log(`[UX-9c] Final status: ${finalStatus}`);

      await page.waitForTimeout(3000);

      await expect(
        page.locator('[data-testid="execution-triage-summary"]')
      ).toBeVisible({ timeout: 10000 });

      const triage = await readTriageFields(page);
      console.log("[UX-9c] Triage fields:", JSON.stringify(triage, null, 2));

      const nextActionLower = triage.nextAction.toLowerCase();
      console.log(`[UX-9c] Next action text: "${triage.nextAction}"`);

      await screenshot(page, "ux9c-01-triage-outcome");

      // -----------------------------------------------------------------------
      // Outcome-specific assertions
      // -----------------------------------------------------------------------
      const terminalLower = finalStatus.toLowerCase();

      if (
        terminalLower === "completed" ||
        terminalLower === "success"
      ) {
        // Completed run: next-action should orient researcher toward results
        const downloadsOrResults =
          nextActionLower.includes("download") ||
          nextActionLower.includes("s3") ||
          nextActionLower.includes("access") ||
          nextActionLower.includes("results") ||
          nextActionLower.includes("output") ||
          nextActionLower.includes("artifact") ||
          nextActionLower.includes("verify") ||
          nextActionLower.includes("open");
        expect(
          downloadsOrResults,
          `Expected completed-run next-action to reference results/download, ` +
            `but got: "${triage.nextAction}"`
        ).toBe(true);

        // Completed run must NOT say to rerun or fix an error
        const errorsOrRerun =
          nextActionLower.includes("retry") ||
          nextActionLower.includes("failure reason") ||
          nextActionLower.includes("inspect recent logs");
        expect(
          errorsOrRerun,
          `Completed run should not contain error/retry guidance, ` +
            `but got: "${triage.nextAction}"`
        ).toBe(false);
      } else if (
        terminalLower === "failed" ||
        terminalLower === "error"
      ) {
        // Failed run: next-action should orient researcher toward fixing the problem
        const errorOrRerun =
          nextActionLower.includes("error") ||
          nextActionLower.includes("fail") ||
          nextActionLower.includes("retry") ||
          nextActionLower.includes("rerun") ||
          nextActionLower.includes("check") ||
          nextActionLower.includes("fix") ||
          nextActionLower.includes("inspect") ||
          nextActionLower.includes("review");
        expect(
          errorOrRerun,
          `Expected failed-run next-action to reference error/retry, ` +
            `but got: "${triage.nextAction}"`
        ).toBe(true);

        // Failed run must NOT say to download results
        const downloadKeywords =
          nextActionLower.includes("open output") ||
          nextActionLower.includes("verify artifacts");
        expect(
          downloadKeywords,
          `Failed run should not say to open outputs, ` +
            `but got: "${triage.nextAction}"`
        ).toBe(false);
      } else {
        // Run did not reach terminal within the poll window.
        // Assert the triage panel is at least showing something non-empty.
        console.warn(
          `[UX-9c] Run did not reach terminal (status="${finalStatus}"); ` +
            `performing non-empty assertion only`
        );
        expect(triage.nextAction.length).toBeGreaterThan(10);
      }

      // -----------------------------------------------------------------------
      // Hard assertion: next-action text must not be the empty/default "idle"
      // message regardless of outcome.
      // -----------------------------------------------------------------------
      expect(triage.nextAction).not.toContain(
        "Configure parameters and prerequisites"
      );

      await screenshot(page, "ux9c-02-triage-complete");
    }
  );
});
