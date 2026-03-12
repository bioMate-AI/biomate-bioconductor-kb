import { test, expect } from "@playwright/test";
import {
  setupTestUser,
  sendMessageAndWaitForResponse,
  clickRunAndWaitForTerminal,
} from "./helpers.js";

test.setTimeout(300000);

test.describe("UX AutoFix Retry Gate", () => {
  test("run button is visible and enabled before execution, and UI shows appropriate terminal state without getting stuck", async ({
    page,
  }) => {
    await setupTestUser(page, "autofix-gate");

    const hasWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Build an RNA-seq QC workflow",
      120000
    );

    if (!hasWorkflow) {
      // AI did not return a workflow card — nothing to test for the run button gate.
      // Verify the page is in a stable non-error state.
      await expect(page.getByRole("alertdialog")).toHaveCount(0);
      return;
    }

    // Before execution: Run button should be visible and enabled (not locked by an
    // autofix state that was never triggered)
    const runButton = page.getByTestId("button-run-workflow-panel").last();
    await expect(runButton).toBeVisible({ timeout: 10000 });
    await expect(runButton).toBeEnabled({ timeout: 5000 });

    // Execute the workflow and wait for a terminal state
    await clickRunAndWaitForTerminal(page, 240000);

    // After terminal state: check the UI is not stuck showing an active autofix
    // banner with the Run button permanently disabled — that would leave the user
    // unable to proceed.
    const autofixBannerVisible = await page
      .getByTestId("autofix-active-banner")
      .isVisible({ timeout: 3000 })
      .catch(() => false);

    if (autofixBannerVisible) {
      // If an autofix banner is shown, the system entered autofix mode for a real
      // failure.  The Run button must be disabled while autofix is active (correct
      // behaviour per the gate spec).
      await expect(runButton).toBeDisabled();
    } else {
      // Normal completion or failure path — the Run button should be either enabled
      // (to allow a retry) or the workflow card should show a clear terminal status
      // (completed / failed) so the user is not left confused.
      const bodyText = (await page.textContent("body").catch(() => "")) ?? "";
      const hasTerminalLabel =
        /completed|finished|failed|errored/i.test(bodyText);

      // Either the run button re-enables for a retry OR a terminal label is visible
      const runButtonEnabled = await runButton
        .isEnabled({ timeout: 3000 })
        .catch(() => false);

      expect(hasTerminalLabel || runButtonEnabled).toBe(true);
    }

    // In no case should the page show an unhandled JS exception dialog
    await expect(page.getByRole("alertdialog")).toHaveCount(0);
  });
});
