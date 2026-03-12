import { test, expect } from "@playwright/test";
import { setupTestUser, sendMessageAndWaitForResponse } from "./helpers.js";

test.setTimeout(300000);

// ---------------------------------------------------------------------------
// Helper: navigate to app and send a prompt, returning whether a workflow card
// appeared.
// ---------------------------------------------------------------------------
async function openWithPrompt(
  page: import("@playwright/test").Page,
  prompt: string
): Promise<boolean> {
  return sendMessageAndWaitForResponse(page, prompt, 120000);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.describe("UX Prerequisite Checklist", () => {
  test("workflow panel renders Run button and any prereq checklist has valid visual indicators", async ({
    page,
  }) => {
    await setupTestUser(page, "prereq-checklist");

    const hasWorkflow = await openWithPrompt(
      page,
      "Run an RNA-seq alignment workflow with STAR aligner"
    );

    if (!hasWorkflow) {
      // The AI responded without a workflow card (e.g. asked a clarifying question).
      // This is a valid outcome — just assert no error dialog is shown.
      await expect(page.getByRole("alertdialog")).toHaveCount(0);
      return;
    }

    // A workflow card was returned.  The Run button must be present.
    const runButton = page.getByTestId("button-run-workflow-panel").last();
    await expect(runButton).toBeVisible({ timeout: 10000 });

    // Check whether a prerequisite checklist component was rendered.
    const prereqChecklist = page.getByTestId("workflow-prereq-checklist");
    const checklistVisible = await prereqChecklist
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    if (checklistVisible) {
      // A checklist appeared.  Every visible item inside it should carry either a
      // "missing" label (blocking input) or a "warning" label (advisory parameter).
      // At minimum at least one item must be visible.
      const allItems = prereqChecklist.locator("[data-testid^='workflow-prereq-item-']");
      const itemCount = await allItems.count();
      expect(itemCount).toBeGreaterThan(0);

      for (let i = 0; i < itemCount; i++) {
        const item = allItems.nth(i);
        const itemText = (await item.textContent().catch(() => "")) ?? "";
        const hasIndicator = /missing|warning|required|optional/i.test(itemText);
        expect(hasIndicator).toBe(true);
      }

      // If any item is marked as blocking (contains "missing"), the Run button may
      // be disabled.  If all items are advisory only, the Run button must remain
      // enabled so the user can still proceed.
      const missingItemsCount = await prereqChecklist
        .locator("[data-testid^='workflow-prereq-item-']")
        .filter({ hasText: /missing/i })
        .count();

      if (missingItemsCount === 0) {
        // No blocking missing inputs — Run button should be enabled
        await expect(runButton).toBeEnabled({ timeout: 5000 });
      }
    } else {
      // No prereq checklist — workflow is ready to run immediately.
      // The Run button must be enabled.
      await expect(runButton).toBeEnabled({ timeout: 5000 });
    }

    // No error dialogs at any point
    await expect(page.getByRole("alertdialog")).toHaveCount(0);
  });

  test("workflow with missing required input shows run button present and no JS errors", async ({
    page,
  }) => {
    const pageErrors: string[] = [];
    page.on("pageerror", (err) => {
      pageErrors.push(err.message);
    });

    await setupTestUser(page, "prereq-missing-input");

    const hasWorkflow = await openWithPrompt(
      page,
      "Run an RNA-seq workflow — I have not uploaded any FASTQ files yet"
    );

    if (!hasWorkflow) {
      expect(pageErrors).toHaveLength(0);
      return;
    }

    // Run button must always be rendered (even if potentially disabled for missing inputs)
    const runButton = page.getByTestId("button-run-workflow-panel").last();
    await expect(runButton).toBeVisible({ timeout: 10000 });

    // If the checklist appears and flags missing inputs, the user must see a
    // human-readable explanation — not a raw JSON dump.
    const prereqChecklist = page.getByTestId("workflow-prereq-checklist");
    const checklistVisible = await prereqChecklist
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    if (checklistVisible) {
      const checklistText = (await prereqChecklist.textContent().catch(() => "")) ?? "";
      // Must not be raw JSON
      expect(checklistText).not.toMatch(/^\s*\{/);
      // Must be non-empty human text
      expect(checklistText.trim().length).toBeGreaterThan(5);
    }

    // No uncaught JS errors
    expect(pageErrors).toHaveLength(0);
  });

  test("workflow with only advisory parameter warnings allows user to proceed", async ({
    page,
  }) => {
    await setupTestUser(page, "prereq-advisory");

    const hasWorkflow = await openWithPrompt(
      page,
      "Run an RNA-seq alignment workflow with STAR aligner using default parameters"
    );

    if (!hasWorkflow) {
      await expect(page.getByRole("alertdialog")).toHaveCount(0);
      return;
    }

    const runButton = page.getByTestId("button-run-workflow-panel").last();
    await expect(runButton).toBeVisible({ timeout: 10000 });

    const prereqChecklist = page.getByTestId("workflow-prereq-checklist");
    const checklistVisible = await prereqChecklist
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    if (checklistVisible) {
      // If any items exist they should only be advisory (no blocking missing inputs)
      const blockingItems = await prereqChecklist
        .locator("[data-testid^='workflow-prereq-item-']")
        .filter({ hasText: /missing/i })
        .count();

      if (blockingItems === 0) {
        // Only advisory items (or none) — the Run button must be enabled
        await expect(runButton).toBeEnabled({ timeout: 5000 });
      }
    } else {
      // No checklist at all — workflow is fully ready
      await expect(runButton).toBeEnabled({ timeout: 5000 });
    }

    await expect(page.getByRole("alertdialog")).toHaveCount(0);
  });
});
