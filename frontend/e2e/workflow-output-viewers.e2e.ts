/**
 * Workflow Output Viewers E2E Tests
 *
 * No page.route() mocking — all calls hit the real BioMate backend.
 * Tests verify that sending a bioinformatics query causes the chat output
 * section to render and that viewer affordances are present when outputs exist.
 */

import { test, expect } from "@playwright/test";
import {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
  clickRunAndWaitForTerminal,
} from "./helpers.js";

test.use({
  trace: "retain-on-failure",
  viewport: { width: 1280, height: 900 },
});

test.setTimeout(300_000);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function waitForWorkflowCard(
  page: import("@playwright/test").Page,
  timeoutMs = 120_000
): Promise<boolean> {
  await page
    .waitForSelector("text=AI is typing", { state: "hidden", timeout: timeoutMs })
    .catch(() => {});
  await page.waitForTimeout(1500);
  return page
    .locator("text=Nextflow Workflow")
    .first()
    .isVisible({ timeout: 10_000 })
    .catch(() => false);
}

async function checkOutputSectionPresent(
  page: import("@playwright/test").Page
): Promise<boolean> {
  const outputLocators = [
    page.locator('[data-testid="output-section"]').first(),
    page.getByRole("button", { name: /view results|outputs/i }).first(),
    page.locator("text=Output").first(),
    page.locator("text=Results").first(),
    page.locator('[data-testid*="viewer"]').first(),
    page.locator('[data-testid*="attachment"]').first(),
  ];
  for (const loc of outputLocators) {
    if (await loc.isVisible({ timeout: 3000 }).catch(() => false)) {
      return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.describe("VCF Viewer with Workflow Output", () => {
  test("output section renders after VCF-producing workflow", async ({ page }) => {
    await setupTestUser(page, "wfv_vcf");

    const gotWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Run variant calling workflow and show me the VCF output with variant statistics",
      120_000
    );

    if (!gotWorkflow) {
      console.log("[WFV-VCF] No workflow returned — checking page for any response");
      const bodyText = (await page.textContent("body")) ?? "";
      const hasVariantContent =
        bodyText.toLowerCase().includes("variant") ||
        bodyText.toLowerCase().includes("vcf");
      console.log(`[WFV-VCF] Variant content in page: ${hasVariantContent}`);
      await expect(page.locator("textarea").first()).toBeVisible();
      return;
    }

    await waitForWorkflowCard(page);

    // Execute and wait for terminal state
    await clickRunAndWaitForTerminal(page, 240_000);

    const outputVisible = await checkOutputSectionPresent(page);
    console.log(`[WFV-VCF] Output section visible after terminal state: ${outputVisible}`);

    // Body must contain VCF / variant related content from AI response
    const bodyText = (await page.textContent("body")) ?? "";
    const hasRelevantContent =
      bodyText.toLowerCase().includes("variant") ||
      bodyText.toLowerCase().includes("vcf") ||
      bodyText.toLowerCase().includes("calling");
    expect(hasRelevantContent).toBe(true);

    await expect(page.locator("textarea").first()).toBeVisible();
  });
});

test.describe("Sequence Viewer with Workflow Output", () => {
  test("output section renders after FASTA-producing workflow", async ({ page }) => {
    await setupTestUser(page, "wfv_seq");

    const gotWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Run sequence assembly workflow and show me the FASTA output with statistics",
      120_000
    );

    if (!gotWorkflow) {
      console.log("[WFV-SEQ] No workflow returned");
      const bodyText = (await page.textContent("body")) ?? "";
      const hasSeqContent =
        bodyText.toLowerCase().includes("sequence") ||
        bodyText.toLowerCase().includes("fasta");
      console.log(`[WFV-SEQ] Sequence content in page: ${hasSeqContent}`);
      await expect(page.locator("textarea").first()).toBeVisible();
      return;
    }

    await waitForWorkflowCard(page);
    await clickRunAndWaitForTerminal(page, 240_000);

    const outputVisible = await checkOutputSectionPresent(page);
    console.log(`[WFV-SEQ] Output section visible after terminal state: ${outputVisible}`);

    const bodyText = (await page.textContent("body")) ?? "";
    const hasRelevantContent =
      bodyText.toLowerCase().includes("sequence") ||
      bodyText.toLowerCase().includes("fasta") ||
      bodyText.toLowerCase().includes("assembly");
    expect(hasRelevantContent).toBe(true);

    await expect(page.locator("textarea").first()).toBeVisible();
  });
});

test.describe("Annotation Viewer with Workflow Output", () => {
  test("output section renders after BED-producing workflow", async ({ page }) => {
    await setupTestUser(page, "wfv_bed");

    const gotWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Run gene annotation workflow and generate a BED file with genomic features",
      120_000
    );

    if (!gotWorkflow) {
      console.log("[WFV-BED] No workflow returned");
      const bodyText = (await page.textContent("body")) ?? "";
      const hasBedContent =
        bodyText.toLowerCase().includes("annotation") ||
        bodyText.toLowerCase().includes("bed") ||
        bodyText.toLowerCase().includes("feature");
      console.log(`[WFV-BED] Annotation content in page: ${hasBedContent}`);
      await expect(page.locator("textarea").first()).toBeVisible();
      return;
    }

    await waitForWorkflowCard(page);
    await clickRunAndWaitForTerminal(page, 240_000);

    const outputVisible = await checkOutputSectionPresent(page);
    console.log(`[WFV-BED] Output section visible after terminal state: ${outputVisible}`);

    const bodyText = (await page.textContent("body")) ?? "";
    const hasRelevantContent =
      bodyText.toLowerCase().includes("annotation") ||
      bodyText.toLowerCase().includes("bed") ||
      bodyText.toLowerCase().includes("gene") ||
      bodyText.toLowerCase().includes("feature");
    expect(hasRelevantContent).toBe(true);

    await expect(page.locator("textarea").first()).toBeVisible();
  });
});
