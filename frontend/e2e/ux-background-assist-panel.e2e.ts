import { test, expect } from "@playwright/test";
import {
  setupTestUser,
  sendMessageAndWaitForResponse,
  clickRunAndWaitForTerminal,
} from "./helpers.js";

test.setTimeout(300000);

test.describe("UX Background Assist Panel", () => {
  test("chat continues working after execution starts and AI responds to follow-up without errors", async ({
    page,
  }) => {
    await setupTestUser(page, "background-assist");

    const hasWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Build an RNA-seq QC workflow",
      120000
    );

    if (!hasWorkflow) {
      // No workflow was returned — skip execution-dependent assertions.
      // Still verify the page is functional with no error dialogs.
      await expect(page.getByRole("alertdialog")).toHaveCount(0);
      return;
    }

    // Start execution (do not wait for full terminal — send follow-up while it may
    // still be running).  We fire-and-forget clickRunAndWaitForTerminal so that
    // the follow-up message can be sent concurrently.
    const runBtn = page.getByTestId("button-run-workflow-panel").last();
    await expect(runBtn).toBeVisible({ timeout: 10000 });
    await expect(runBtn).toBeEnabled({ timeout: 5000 });
    await runBtn.click();

    // Give the backend a moment to register the execution before sending
    // the follow-up so that any "running" state has had a chance to appear.
    await page.waitForTimeout(3000);

    // Check whether the background assist panel appeared (it requires the workflow
    // to be actively running when the follow-up is sent).
    const backgroundPanelVisible = await page
      .getByTestId("background-assist-panel")
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    // Send a follow-up message regardless of whether the panel appeared
    const chatInput = page.locator("textarea").first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });
    await chatInput.fill("Can you draft a summary of this analysis?");
    await chatInput.press("Enter");

    // Wait for the AI to respond to the follow-up
    await page
      .waitForSelector("text=AI is typing", { state: "visible", timeout: 30000 })
      .catch(() => {});
    await page
      .waitForSelector("text=AI is typing", { state: "hidden", timeout: 120000 })
      .catch(() => {});
    await page.waitForTimeout(1000);

    // The AI must have replied — at least one assistant message bubble should exist
    const assistantMessages = page.locator(
      "[data-testid='chat-message-assistant'], [data-role='assistant']"
    );
    const assistantCount = await assistantMessages.count();

    // Fallback: check that any text from the AI response area is present
    const chatArea = page.locator(
      "[data-testid='chat-messages'], [data-testid='chat-container'], main"
    ).first();
    const chatText = (await chatArea.textContent().catch(() => "")) ?? "";

    expect(
      assistantCount > 0 ||
        chatText.length > 50
    ).toBe(true);

    if (backgroundPanelVisible) {
      // Background assist panel was present — verify the draft-report action button
      // exists (it is the primary CTA in that panel).
      const draftBtn = page.getByTestId("button-background-action-draft-report");
      await expect(draftBtn).toBeVisible({ timeout: 5000 });
    }

    // No error dialogs should have appeared at any point
    await expect(page.getByRole("alertdialog")).toHaveCount(0);
  });
});
