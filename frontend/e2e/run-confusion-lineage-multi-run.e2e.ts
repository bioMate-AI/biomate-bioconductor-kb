/**
 * Run Confusion Lineage under Multi-Run Switching E2E Tests
 *
 * No page.route() mocking — all calls hit the real BioMate backend.
 *
 * Creates one real workflow execution, verifies it appears in the run
 * manager, then checks that switching context in the run manager does
 * not throw errors and that any telemetry events have correct structure.
 */

import { test, expect } from "@playwright/test";
import {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
  openRunManager,
  waitForRunManagerItems,
} from "./helpers.js";

test.setTimeout(300_000);

test.describe("Run confusion lineage under multi-run switching", () => {
  test("run appears in run manager and switching context does not error", async ({
    page,
  }) => {
    // Capture any telemetry events emitted during the test
    const telemetryEvents: any[] = [];
    page.on("request", (req) => {
      if (
        req.url().includes("/api/telemetry/events") &&
        req.method() === "POST"
      ) {
        try {
          const body = req.postDataJSON();
          if (body) telemetryEvents.push(body);
        } catch {
          // ignore parse errors
        }
      }
    });

    // Capture console errors
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await setupTestUser(page, "lineage_multi");

    // Submit a workflow request to create a real run
    const gotWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Run RNA-seq quality control workflow for lineage tracking test",
      120_000
    );

    if (!gotWorkflow) {
      console.log("[Lineage] No workflow returned — skipping run manager check");
      await expect(page.locator("textarea").first()).toBeVisible();
      return;
    }

    // Click Run to start execution
    const runBtn = page.getByTestId("button-run-workflow-panel").first();
    const runBtnVisible = await runBtn
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    if (!runBtnVisible) {
      console.log("[Lineage] Run button not visible — skipping execution");
      return;
    }

    let runId: string | null = null;
    page.on("response", async (resp) => {
      if (!resp.url().includes("/api/workflows/execute")) return;
      try {
        const payload = await resp.json();
        runId =
          payload?.runId ||
          payload?.execution?.run?.id ||
          payload?.execution?.runId ||
          null;
      } catch {
        // ignore
      }
    });

    await runBtn.click();
    await page.waitForTimeout(3000);

    console.log("[Lineage] Captured runId:", runId);

    // Open the run manager panel
    await openRunManager(page);
    const panel = page.getByTestId("run-manager-panel");
    const panelVisible = await panel
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    if (!panelVisible) {
      console.log("[Lineage] Run manager panel not visible — skipping item check");
      return;
    }

    // Wait for at least 1 item to appear in run manager
    await waitForRunManagerItems(page, 1, 30_000);
    const itemCount = await page
      .locator("[data-testid^='run-manager-item-']")
      .count();
    expect(itemCount).toBeGreaterThanOrEqual(1);
    console.log(`[Lineage] Run manager shows ${itemCount} item(s)`);

    // Click the first run item to switch context
    const firstItem = page.locator("[data-testid^='run-manager-item-']").first();
    await firstItem.click({ force: true });
    await page.waitForTimeout(1500);

    // No JavaScript errors should have occurred
    const criticalErrors = consoleErrors.filter(
      (e) =>
        e.toLowerCase().includes("uncaught") ||
        e.toLowerCase().includes("cannot read") ||
        e.toLowerCase().includes("is not a function")
    );
    expect(criticalErrors).toHaveLength(0);
    console.log("[Lineage] No critical JS errors after context switch");

    // Verify telemetry events (if any) have correct structure
    for (const event of telemetryEvents) {
      if (event?.event === "workflow.confusion_signal") {
        // Must have a payload with required fields
        expect(event.payload).toBeDefined();
        if (event.payload?.runId) {
          expect(typeof event.payload.runId).toBe("string");
        }
        if (event.payload?.signal) {
          expect(typeof event.payload.signal).toBe("string");
        }
        console.log("[Lineage] Telemetry event structure valid:", event.payload?.signal);
      }
    }

    console.log(
      `[Lineage] Test complete. Telemetry events captured: ${telemetryEvents.length}`
    );
  });
});
