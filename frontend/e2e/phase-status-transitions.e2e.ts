/**
 * Phase panel — status colours & live transitions (Stream 1 · §7).
 *
 * Verifies the workflow panel reflects LIVE status over real SSE: phase cards
 * and the overall badge move idle/ready → running → terminal (completed|failed),
 * which is what drives the pending-grey → running-blue → ok-green/err-red colour
 * updates in workflow-panel.css. No mocks — real backend, real run (CLAUDE.md
 * UX-E2E standard). Uses the shared fixture account.
 *
 * Run (against dev, not local):
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     E2E_FIXTURE_PASSWORD='WpmFixture!2026' \
 *     npx playwright test e2e/phase-status-transitions.e2e.ts
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const TERMINAL = ["completed", "failed", "ok", "error", "cancelled"];
// A workflow-generation + Batch run can take minutes; budget generously.
const RUN_TIMEOUT = 20 * 60 * 1000;

test.describe("phase panel status transitions", () => {
  test.setTimeout(RUN_TIMEOUT + 2 * 60 * 1000);

  test("phase cards + overall badge go idle → running → terminal live", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(BASE_URL, { waitUntil: "domcontentloaded" });

    // 1. Trigger a workflow from chat (ADMET — fast, deterministic routing).
    const input = page.locator(
      '[data-testid="chat-input"], textarea[placeholder*="Ask BioMate"], textarea[placeholder*="Ask"]',
    ).first();
    await input.waitFor({ state: "visible", timeout: 60_000 });
    await input.fill(
      "Screen aspirin and terfenadine for ADMET (hERG, DILI) with a deep-learning model.",
    );
    await input.press("Enter");

    // 2. The workflow panel appears; grab the overall status badge.
    const panel = page.locator('[data-testid="workflow-artifact-panel"]').first();
    await panel.waitFor({ state: "visible", timeout: 120_000 });
    const badge = page.locator('[data-testid="workflow-overall-status-badge"]').first();
    await badge.waitFor({ state: "attached", timeout: 120_000 });

    // Pre-run the overall badge must be non-terminal (idle/ready/pending).
    const preStatus = (await badge.getAttribute("data-status")) || "";
    expect(TERMINAL).not.toContain(preStatus.toLowerCase());

    // 3. Confirm & run.
    const runBtn = page.locator(
      'button:has-text("Confirm and run"), button:has-text("Confirm & Run"), button:has-text("Run workflow")',
    ).first();
    await runBtn.waitFor({ state: "visible", timeout: 60_000 });
    await runBtn.click();

    // 4a. Overall badge must enter "running" (live transition, not mocked).
    await expect
      .poll(async () => (await badge.getAttribute("data-status"))?.toLowerCase(), {
        timeout: 5 * 60 * 1000,
        message: "overall badge never entered running",
      })
      .toBe("running");

    // 4b. At least one phase card must flip pending → running.
    await page.waitForFunction(
      () =>
        Array.from(document.querySelectorAll('[data-testid^="phase-card-"]')).some(
          (el) => (el.getAttribute("data-status") || "").toLowerCase() === "running",
        ),
      undefined,
      { timeout: 5 * 60 * 1000 },
    );

    // 5. The run reaches a terminal state and the overall badge follows.
    await expect
      .poll(async () => (await badge.getAttribute("data-status"))?.toLowerCase(), {
        timeout: RUN_TIMEOUT,
        message: "run never reached a terminal state",
      })
      .toMatch(/completed|failed|error|cancelled|ok/);

    // Every phase card ends terminal (completed / failed / skipped) — none stuck running.
    const stuck = await page.evaluate(() =>
      Array.from(document.querySelectorAll('[data-testid^="phase-card-"]'))
        .map((el) => (el.getAttribute("data-status") || "").toLowerCase())
        .filter((s) => s === "running" || s === "submitted"),
    );
    expect(stuck, "phase cards left stuck in running").toHaveLength(0);
  });
});
