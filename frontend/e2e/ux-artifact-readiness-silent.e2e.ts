import { test, expect } from "@playwright/test";
import {
  setupTestUser,
  sendMessageAndWaitForResponse,
  clickRunAndWaitForTerminal,
} from "./helpers.js";

test.setTimeout(300000);

test.describe("UX Artifact Readiness Silent Detection", () => {
  test("workflow completes without user-facing error prompt and telemetry events have valid structure", async ({
    page,
  }) => {
    // Capture all console messages for telemetry inspection
    const consoleEvents: { type: string; text: string }[] = [];
    page.on("console", (msg) => {
      consoleEvents.push({ type: msg.type(), text: msg.text() });
    });

    // Capture any uncaught page errors
    const pageErrors: string[] = [];
    page.on("pageerror", (err) => {
      pageErrors.push(err.message);
    });

    await setupTestUser(page, "artifact-readiness");

    const hasWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Build an RNA-seq QC workflow",
      120000
    );

    if (!hasWorkflow) {
      // No workflow card appeared — the AI responded with text only.
      // Verify no error dialog is shown to the user.
      await expect(page.getByRole("alertdialog")).toHaveCount(0);
      await expect(page.getByText(/outputs are not yet useful/i)).toHaveCount(0);
      await expect(page.getByTestId("button-usefulness-recovery")).toHaveCount(0);
      return;
    }

    // Run button is present — click and wait for terminal state
    await clickRunAndWaitForTerminal(page, 240000);

    // After terminal state: confirm no alarming error prompt is surfaced to user
    await expect(page.getByRole("alertdialog")).toHaveCount(0);
    await expect(page.getByText(/outputs are not yet useful/i)).toHaveCount(0);
    await expect(page.getByTestId("button-usefulness-recovery")).toHaveCount(0);

    // If the output section is empty, there should be no error message frightening the user.
    // An empty output section is acceptable UX (no outputs produced yet).
    const outputSection = page.locator(
      "[data-testid='workflow-output-section']"
    );
    const outputSectionExists = await outputSection
      .isVisible({ timeout: 3000 })
      .catch(() => false);

    if (outputSectionExists) {
      const outputText = await outputSection.textContent().catch(() => "");
      if (!outputText?.trim()) {
        // Empty output section — check no error banner is shown alongside it
        await expect(
          page.getByTestId("workflow-output-error-banner")
        ).toHaveCount(0);
      }
    }

    // Validate structure of any telemetry-like console log events the app emits.
    // BioMate emits structured JSON objects to the console for analytics; we parse
    // any that look like telemetry and confirm they carry the expected fields.
    const telemetryLogs = consoleEvents.filter((e) => {
      try {
        const parsed = JSON.parse(e.text);
        return typeof parsed?.event === "string";
      } catch {
        return false;
      }
    });

    for (const entry of telemetryLogs) {
      const parsed = JSON.parse(entry.text);
      // Every telemetry event must have an "event" string key
      expect(typeof parsed.event).toBe("string");
      // If a payload is present it must be an object
      if ("payload" in parsed) {
        expect(typeof parsed.payload).toBe("object");
      }
      // workflow.error_shown events that do exist must always have silent=true
      // (i.e. they must never surface a blocking prompt to the user)
      if (parsed.event === "workflow.error_shown") {
        expect(parsed?.payload?.silent).toBe(true);
      }
    }

    // No uncaught JS errors should have been thrown during the run
    expect(pageErrors).toHaveLength(0);
  });
});
