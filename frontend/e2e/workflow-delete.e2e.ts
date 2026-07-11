/**
 * E2E: Delete personal workflow from My Imports.
 *
 * Covers:
 *  - DELETE /api/workflows/personal/:id requires auth (401 gate)
 *  - Upload a workflow, then delete it via UI trash button → row disappears
 *  - DELETE API endpoint removes the workflow from the personal list
 *
 * Uses the canonical fixture account (CLAUDE.md §"E2E test user").
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import path from "path";

const NF_STUB = [
  "nextflow.enable.dsl=2",
  "",
  "workflow {",
  "  Channel.of('Delete E2E') | view { it }",
  "}",
].join("\n");

test.describe("workflow-delete", () => {
  test("DELETE /api/workflows/personal/:id requires auth", async ({ page }) => {
    const res = await page.request.delete(
      `${BASE_URL}/api/workflows/personal/nonexistent-id`
    );
    expect(res.status()).toBe(401);
  });

  test("deleting a workflow removes it from My Imports list", async ({
    page,
  }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    // Step 1: Upload a workflow via Import Workflow tab
    await page.getByTestId("button-import-workflow").click();
    await expect(page.getByTestId("workflow-upload-modal")).toBeVisible({
      timeout: 5000,
    });

    const wfName = `Delete E2E ${Date.now()}`;
    await page.getByTestId("workflow-name-input").fill(wfName);
    await page.getByTestId("workflow-file-input").setInputFiles({
      name: "delete_e2e.nf",
      mimeType: "text/plain",
      buffer: Buffer.from(NF_STUB),
    });
    await expect(page.getByTestId("workflow-upload-submit")).toBeEnabled({
      timeout: 2000,
    });
    await page.getByTestId("workflow-upload-submit").click();

    // Wait for success state
    await expect(
      page.locator(
        '[data-testid="workflow-upload-modal"] .text-green-700,' +
          '[data-testid="workflow-upload-modal"] .text-green-400'
      )
    ).toBeVisible({ timeout: 10000 });

    // Step 2: Navigate to My Imports tab
    await page.getByTestId("tab-my-imports").click();
    await expect(page.getByTestId("personal-workflows-list")).toBeVisible({
      timeout: 5000,
    });

    // Find the row for our uploaded workflow
    const wfRow = page
      .getByTestId("personal-workflows-list")
      .locator(`li:has-text("${wfName}")`);
    await expect(wfRow).toBeVisible({ timeout: 5000 });

    // Find the delete button within the row
    // The data-testid is button-delete-personal-<id>, so use within-row locator
    const deleteBtn = wfRow.locator('[data-testid^="button-delete-personal-"]');
    await expect(deleteBtn).toBeVisible();

    // Step 3: Click delete and accept the confirm dialog
    page.once("dialog", (dialog) => dialog.accept());
    await deleteBtn.click();

    // Step 4: Row should disappear
    await expect(wfRow).not.toBeVisible({ timeout: 8000 });
  });

  test("DELETE /api/workflows/personal/:id returns 404 for non-owned workflow", async ({
    page,
  }) => {
    await loginAsFixture(page);

    // Try to delete a random non-existent ID
    const res = await page.request.delete(
      `${BASE_URL}/api/workflows/personal/00000000-0000-0000-0000-000000000099`
    );
    // Owned by nobody → 404 (not 500)
    expect(res.status()).toBe(404);
  });
});
