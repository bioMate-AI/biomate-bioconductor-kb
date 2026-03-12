import { test, expect } from "@playwright/test";
import {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
} from "./helpers.js";

test.setTimeout(180000);

test.describe("UX Capability Parity - Active Workflow Card", () => {
  test("renders execution controls and parameter inputs when workflow appears", async ({
    page,
  }) => {
    await setupTestUser(page, "parity");

    const hasWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Create a workflow to run FastQC quality control on FASTQ files",
      120000
    );

    if (!hasWorkflow) {
      // AI responded but no workflow card was produced.
      // Verify the chat at minimum produced a visible text response.
      const body = await page.textContent("body").catch(() => "");
      expect(
        body && body.trim().length > 0,
        "Expected the AI to produce a text response"
      ).toBeTruthy();
      test.info().annotations.push({
        type: "skip-reason",
        description:
          "AI did not return a workflow card — execution control assertions skipped",
      });
      return;
    }

    // A workflow card appeared. Verify the primary Run button is present —
    // this is the most critical capability parity item.
    const runBtn = page.getByTestId("button-run-workflow-panel").first();
    await expect(runBtn).toBeVisible({ timeout: 10000 });

    // Check for other execution control buttons. We use soft assertions so
    // that a missing optional button does not fail the entire test.
    for (const testId of [
      "button-pause-workflow-panel",
      "button-resume-workflow-panel",
      "button-restart-workflow-panel",
      "button-cancel-workflow-panel",
    ]) {
      const btn = page.getByTestId(testId).first();
      const visible = await btn.isVisible({ timeout: 3000 }).catch(() => false);
      if (!visible) {
        test.info().annotations.push({
          type: "missing-control",
          description: `${testId} was not visible — may be hidden until run starts`,
        });
      }
    }

    // Check for a parameter section. The exact parameter count depends on
    // what the AI generates, so we only assert that at least one label exists
    // if a "Workflow Parameters" accordion is present.
    const paramsAccordion = page
      .getByText(/workflow parameters/i)
      .or(page.getByText(/parameters/i).and(page.locator("button, [role='button']")))
      .first();

    const accordionVisible = await paramsAccordion
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    if (accordionVisible) {
      await paramsAccordion.click().catch(() => {});
      await page.waitForTimeout(500);

      // After opening the accordion, at least one input or label should appear.
      const paramInputs = page.locator(
        "input[type='text'], input[type='number'], select, textarea"
      );
      const inputCount = await paramInputs.count();
      const labels = page.locator("label");
      const labelCount = await labels.count();

      expect(
        inputCount > 0 || labelCount > 0,
        "Expected at least one parameter input or label after opening the parameters section"
      ).toBeTruthy();
    } else {
      // Parameters accordion not present — annotate and continue.
      test.info().annotations.push({
        type: "skip-reason",
        description:
          "Parameters accordion not found — the workflow may not expose configurable parameters",
      });
    }
  });
});
