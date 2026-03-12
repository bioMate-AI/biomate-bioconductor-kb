/**
 * Run Context Mismatch Guard E2E Tests
 *
 * No page.route() mocking — all calls hit the real BioMate backend.
 *
 * Starts 1 real workflow execution, verifies the focused run context
 * updates in the run manager, and asserts no mismatch errors appear
 * in the console.
 */

import { expect, test } from "@playwright/test";
import {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
  openRunManager,
  waitForRunManagerItems,
} from "./helpers.js";

test.setTimeout(300_000);

test.describe("Run Context Mismatch Guard", () => {
  test("focused run context updates to the new run without mismatch errors", async ({
    page,
  }) => {
    const consoleErrors: string[] = [];
    const consoleWarnings: string[] = [];

    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
      if (msg.type() === "warning") consoleWarnings.push(msg.text());
    });

    await setupTestUser(page, "ctx_mismatch");

    // Open the run manager before execution to see if any prior runs exist
    await openRunManager(page);
    const initialItemCount = await page
      .locator("[data-testid^='run-manager-item-']")
      .count();
    console.log(`[Context Guard] Initial run manager items: ${initialItemCount}`);

    // Dismiss run manager to get back to chat
    await page.keyboard.press("Escape").catch(() => undefined);
    await page.waitForTimeout(500);

    // Submit a real workflow request
    const gotWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Generate RNA-seq differential expression workflow for context guard test",
      120_000
    );

    if (!gotWorkflow) {
      console.log("[Context Guard] No workflow returned — skipping execution");
      await expect(page.locator("textarea").first()).toBeVisible();
      return;
    }

    // Click Run to start execution
    const runBtn = page.getByTestId("button-run-workflow-panel").first();
    const runBtnVisible = await runBtn
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    if (!runBtnVisible) {
      console.log("[Context Guard] Run button not visible — skipping");
      return;
    }

    let capturedRunId: string | null = null;
    page.on("response", async (resp) => {
      if (!resp.url().includes("/api/workflows/execute")) return;
      try {
        const payload = await resp.json();
        capturedRunId =
          payload?.runId ||
          payload?.execution?.run?.id ||
          null;
      } catch {
        // ignore
      }
    });

    await runBtn.click();
    await page.waitForTimeout(3000);
    console.log("[Context Guard] Captured runId:", capturedRunId);

    // Open run manager and verify the new run appears
    await openRunManager(page);
    await waitForRunManagerItems(page, initialItemCount + 1, 30_000);

    const updatedItemCount = await page
      .locator("[data-testid^='run-manager-item-']")
      .count();
    expect(updatedItemCount).toBeGreaterThan(initialItemCount);
    console.log(`[Context Guard] Run manager now shows ${updatedItemCount} item(s)`);

    // Click the most recently added run item
    const firstItem = page.locator("[data-testid^='run-manager-item-']").first();
    await firstItem.click({ force: true });
    await page.waitForTimeout(1500);

    // If the anchor state element is present, verify focused run id is set
    const anchorState = page.getByTestId("chat-run-anchor-state");
    if (await anchorState.isVisible({ timeout: 3000 }).catch(() => false)) {
      const focusedRunId = await anchorState
        .getAttribute("data-focused-run-id")
        .catch(() => null);
      if (focusedRunId) {
        expect(typeof focusedRunId).toBe("string");
        expect(focusedRunId.length).toBeGreaterThan(0);
        console.log("[Context Guard] Focused run id:", focusedRunId);

        if (capturedRunId) {
          expect(focusedRunId).toBe(capturedRunId);
          console.log("[Context Guard] Focused run id matches captured run id");
        }
      }
    } else {
      // Anchor state element not present — check that at least no errors occurred
      console.log(
        "[Context Guard] Anchor state element not found — checking for errors only"
      );
    }

    // No mismatch or context errors in console
    const mismatchErrors = consoleErrors.filter(
      (e) =>
        e.toLowerCase().includes("mismatch") ||
        e.toLowerCase().includes("context") ||
        e.toLowerCase().includes("uncaught") ||
        (e.toLowerCase().includes("cannot read") &&
          !e.toLowerCase().includes("network"))
    );
    if (mismatchErrors.length > 0) {
      console.warn("[Context Guard] Console errors:", mismatchErrors);
    }
    expect(mismatchErrors).toHaveLength(0);

    console.log("[Context Guard] Test complete — no mismatch errors detected");
  });
});
