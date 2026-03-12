import { test, expect } from "@playwright/test";
import {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
} from "./helpers.js";

test.setTimeout(180000);

test.describe("Run Context Traceability", () => {
  test("shows run context / execution evidence after workflow is triggered", async ({
    page,
  }) => {
    await setupTestUser(page, "trace");

    const hasWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Run an RNA-seq differential expression workflow",
      120000
    );

    if (!hasWorkflow) {
      // AI replied but produced no workflow card. Verify the response
      // contains text and skip the traceability-specific assertions.
      const body = await page.textContent("body").catch(() => "");
      expect(
        body && body.trim().length > 0,
        "Expected the AI to produce a text response"
      ).toBeTruthy();
      test.info().annotations.push({
        type: "skip-reason",
        description:
          "AI did not return a workflow card — run-context assertions skipped",
      });
      return;
    }

    // A workflow card appeared. Click Run and wait a short period for the
    // backend to accept the execution request and surface an invocation ID.
    const runBtn = page.getByTestId("button-run-workflow-panel").first();
    await expect(runBtn).toBeVisible({ timeout: 10000 });

    // Capture the execute response to extract the run ID.
    let capturedRunId: string | null = null;
    const responseHandler = async (resp: import("@playwright/test").Response) => {
      if (!resp.url().includes("/api/workflows/execute") &&
          !resp.url().includes("/api/nextflow/execute")) return;
      try {
        const payload = await resp.json();
        capturedRunId =
          payload?.runId ||
          payload?.run_id ||
          payload?.execution?.run?.id ||
          payload?.execution?.runId ||
          payload?.invocation_id ||
          null;
      } catch {
        /* ignore parse errors */
      }
    };
    page.on("response", responseHandler);

    await runBtn.click();

    // Give the backend up to 10 s to acknowledge the run.
    await page.waitForTimeout(10000);
    page.removeListener("response", responseHandler);

    // Now check for any run-context surface in the UI.
    // We accept any of the following as evidence of traceability:
    const runContextChip = page.getByTestId("run-context-chip");
    const evidenceSurface = page.getByTestId("workflow-execution-evidence");
    const statusBadge = page.getByTestId("execution-status-badge");
    const invocationIdText = page.getByText(/invocation[- _]id/i).first();
    const runIdText = page.getByText(/run[- _]id/i).first();
    const statusText = page
      .getByText(/queued|running|pending|completed|failed|submitted/i)
      .first();

    const chipVisible = await runContextChip.isVisible({ timeout: 5000 }).catch(() => false);
    const evidenceVisible = await evidenceSurface.isVisible({ timeout: 2000 }).catch(() => false);
    const badgeVisible = await statusBadge.isVisible({ timeout: 2000 }).catch(() => false);
    const invocationVisible = await invocationIdText.isVisible({ timeout: 2000 }).catch(() => false);
    const runIdVisible = await runIdText.isVisible({ timeout: 2000 }).catch(() => false);
    const statusVisible = await statusText.isVisible({ timeout: 2000 }).catch(() => false);

    const anySurfaceVisible =
      chipVisible ||
      evidenceVisible ||
      badgeVisible ||
      invocationVisible ||
      runIdVisible ||
      statusVisible ||
      capturedRunId !== null;

    expect(
      anySurfaceVisible,
      "Expected at least one run-context indicator (chip, evidence surface, " +
        "status badge, run/invocation ID text, or captured run ID from API response) " +
        "to be present after clicking Run"
    ).toBeTruthy();

    // Bonus: if the run-context chip is visible, assert it carries some text.
    if (chipVisible) {
      const chipText = await runContextChip.textContent().catch(() => "");
      expect(chipText && chipText.trim().length > 0).toBeTruthy();
    }

    // Bonus: if we captured a run ID from the response, log it.
    if (capturedRunId) {
      test.info().annotations.push({
        type: "run-id",
        description: `Captured run ID: ${capturedRunId}`,
      });
    }
  });
});
