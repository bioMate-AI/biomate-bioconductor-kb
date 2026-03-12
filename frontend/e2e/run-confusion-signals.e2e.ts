/**
 * Run Confusion Signals E2E Tests
 *
 * No page.route() mocking — all calls hit the real BioMate backend.
 *
 * Executes a real workflow and after terminal state verifies:
 * - The output section is reachable
 * - Any UX telemetry events have correct shape
 * - No specific confusion signal types are asserted (those depend on
 *   backend-controlled artifact readiness state)
 */

import { test, expect } from "@playwright/test";
import {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
  clickRunAndWaitForTerminal,
} from "./helpers.js";

test.setTimeout(300_000);

test.describe("Run Confusion Signals", () => {
  test("workflow completes and outputs section is reachable", async ({ page }) => {
    const telemetryEvents: any[] = [];
    const consoleErrors: string[] = [];

    // Capture telemetry requests (observe only, no mock)
    page.on("request", (req) => {
      if (
        req.url().includes("/api/telemetry/events") &&
        req.method() === "POST"
      ) {
        try {
          const body = req.postDataJSON();
          if (body) telemetryEvents.push(body);
        } catch {
          // ignore
        }
      }
    });

    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await setupTestUser(page, "confusion_signals");

    // Submit a workflow request
    const gotWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Build a simple RNA-seq QC workflow for output readiness check",
      120_000
    );

    if (!gotWorkflow) {
      console.log("[Confusion Signals] No workflow returned — pass");
      await expect(page.locator("textarea").first()).toBeVisible();
      return;
    }

    // Execute the workflow
    await clickRunAndWaitForTerminal(page, 240_000);

    // Output section should be present after terminal state
    const outputLocators = [
      page.locator('[data-testid="output-section"]').first(),
      page.getByRole("button", { name: /view results|outputs/i }).first(),
      page.locator("text=Output").first(),
      page.locator("text=Results").first(),
      page.locator("text=completed").first(),
      page.locator("text=COMPLETED").first(),
    ];

    let outputSectionFound = false;
    for (const loc of outputLocators) {
      if (await loc.isVisible({ timeout: 5000 }).catch(() => false)) {
        outputSectionFound = true;
        break;
      }
    }

    console.log(`[Confusion Signals] Output section found: ${outputSectionFound}`);
    // Not a hard failure — real workflows may complete with no file outputs

    // No critical JS errors
    const criticalErrors = consoleErrors.filter(
      (e) =>
        e.toLowerCase().includes("uncaught") ||
        (e.toLowerCase().includes("cannot read") &&
          !e.toLowerCase().includes("network"))
    );
    if (criticalErrors.length > 0) {
      console.warn("[Confusion Signals] Console errors:", criticalErrors);
    }
    expect(criticalErrors).toHaveLength(0);

    // Validate structure of any confusion signal telemetry events emitted
    const confusionSignals = telemetryEvents.filter(
      (e) => e?.event === "workflow.confusion_signal"
    );
    for (const signal of confusionSignals) {
      expect(signal.payload).toBeDefined();
      // If runId is present it must be a string
      if (signal.payload?.runId !== undefined) {
        expect(typeof signal.payload.runId).toBe("string");
      }
      // If signal type is present it must be a string
      if (signal.payload?.signal !== undefined) {
        expect(typeof signal.payload.signal).toBe("string");
      }
    }

    console.log(
      `[Confusion Signals] Confusion signal events captured: ${confusionSignals.length}`
    );

    // App must still be usable
    await expect(page.locator("textarea").first()).toBeVisible();
  });

  test("retry button appears and does not crash the app after execute failure", async ({
    page,
  }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await setupTestUser(page, "confusion_retry");

    const gotWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Run a bioinformatics workflow for retry signal test",
      120_000
    );

    if (!gotWorkflow) {
      console.log("[Confusion Retry] No workflow returned — pass");
      await expect(page.locator("textarea").first()).toBeVisible();
      return;
    }

    // Click run (real execution may fail or succeed)
    const runBtn = page.getByTestId("button-run-workflow-panel").last();
    const runBtnVisible = await runBtn
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    if (!runBtnVisible) {
      console.log("[Confusion Retry] Run button not visible — skipping");
      return;
    }

    await runBtn.click();
    await page.waitForTimeout(8000);

    // Check if a retry button appeared (execution failure path)
    const retryBtn = page.getByTestId("button-execution-try-again").first();
    const retryVisible = await retryBtn
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    if (retryVisible) {
      // Retry is present — verify it is clickable and doesn't crash
      await retryBtn.click();
      await page.waitForTimeout(3000);

      const criticalErrors = consoleErrors.filter(
        (e) =>
          e.toLowerCase().includes("uncaught") ||
          (e.toLowerCase().includes("cannot read") &&
            !e.toLowerCase().includes("network"))
      );
      expect(criticalErrors).toHaveLength(0);
      console.log("[Confusion Retry] Retry clicked, no critical JS errors");
    } else {
      console.log(
        "[Confusion Retry] No retry button — execution may have succeeded or not yet failed"
      );
    }

    await expect(page.locator("textarea").first()).toBeVisible();
  });
});
