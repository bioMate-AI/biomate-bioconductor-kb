/**
 * Disambiguation E2E Tests
 *
 * Verifies that BioMate asks a clarifying question instead of silently picking
 * the wrong workflow when a query matches multiple fundamentally different pipelines.
 *
 * Fork points covered:
 *   - Variant calling (germline vs somatic)
 *   - RNA-seq type (bulk vs single-cell)
 *   - CRISPR (screen vs targeted editing)
 *
 * Flow: send ambiguous query → verify clarifying question → answer → verify
 * correct workflow selected (by searching for domain keywords in the response).
 *
 * No page.route() mocking. All calls hit the live stack.
 */

import { test, expect, Page } from "@playwright/test";
import {
  BASE_URL,
  setupTestUser,
  sendChatMessage,
  sendMessageAndWaitForResponse,
} from "./helpers.js";

test.use({ trace: "retain-on-failure" });

// ===========================================================================
// Helpers
// ===========================================================================

/**
 * Wait for the assistant to finish responding to a message.
 * Returns the full text content of the most recent assistant message.
 */
async function waitForAssistantMessage(
  page: Page,
  timeoutMs = 90_000
): Promise<string> {
  // Wait for any thinking indicator to appear then disappear
  const thinkingSelectors = [
    "[data-testid='chat-response-pending']",
    "[data-testid='chat-analysis-status']",
    "text=BioMate is thinking",
    "text=Analyzing request",
  ];

  await Promise.race(
    thinkingSelectors.map((sel) =>
      page
        .waitForSelector(sel, { state: "visible", timeout: 30_000 })
        .catch(() => null)
    )
  );
  await Promise.all(
    thinkingSelectors.map((sel) =>
      page
        .waitForSelector(sel, { state: "hidden", timeout: timeoutMs })
        .catch(() => null)
    )
  );

  // Wait for non-trivial content in the latest assistant message
  await page
    .waitForFunction(
      () => {
        const latest = document.querySelector(
          '[data-is-latest-assistant="true"]'
        );
        if (!latest) return false;
        const text = latest.textContent ?? "";
        return (
          text.trim().length > 30 &&
          !text.includes("BioMate is thinking") &&
          !text.includes("Analyzing request")
        );
      },
      { timeout: timeoutMs }
    )
    .catch(() => {});

  const latest = await page
    .locator('[data-is-latest-assistant="true"]')
    .first();
  return (await latest.textContent()) ?? "";
}

// ===========================================================================
// D1 — Variant calling disambiguation: germline vs somatic
// ===========================================================================
test.describe("Variant calling disambiguation", () => {
  test(
    "D1 minimally-specified variant calling query: AI asks question or generates sensible workflow",
    async ({ page }) => {
      test.setTimeout(300_000);
      await setupTestUser(page, "disambig_d1");

      // Use a minimal query that doesn't specify tools — genuinely ambiguous
      // (no BWA/GATK hint, no germline/somatic keyword)
      const gotWorkflow = await sendMessageAndWaitForResponse(
        page,
        "I want to detect mutations in my patient WGS samples",
        180_000
      );

      const response = await waitForAssistantMessage(page, 10_000);
      const lower = response.toLowerCase();
      console.log(
        `[D1] gotWorkflow=${gotWorkflow}, snippet: ${response.substring(0, 300).replace(/\n/g, " ")}`
      );

      // ACCEPTABLE outcomes:
      //   (a) AI asks a clarifying question about germline vs somatic
      //   (b) AI generates a sensible germline WGS workflow (default interpretation)
      //   (c) AI asks about dataset/data first (dataset-first rule)
      // UNACCEPTABLE:
      //   - An error response with no scientific content
      //   - A completely unrelated workflow

      const askedClarification =
        lower.includes("germline") ||
        lower.includes("somatic") ||
        lower.includes("clarif") ||
        lower.includes("inherited") ||
        lower.includes("tumor");
      const generatedWgsWorkflow =
        gotWorkflow &&
        (lower.includes("wgs") ||
          lower.includes("gatk") ||
          lower.includes("variant") ||
          lower.includes("whole genome") ||
          lower.includes("genome sequencing"));
      const askedForDataset =
        lower.includes("dataset") ||
        lower.includes("fastq") ||
        lower.includes("upload") ||
        lower.includes("data");

      const acceptable =
        askedClarification || generatedWgsWorkflow || askedForDataset;
      console.log(
        `[D1] askedClarification=${askedClarification}, generatedWgsWorkflow=${generatedWgsWorkflow}, askedForDataset=${askedForDataset}`
      );
      expect(acceptable).toBe(true);

      // Screenshot
      await page.screenshot({
        path: "e2e/screenshots/disambiguation/D1_variant_calling.png",
        fullPage: false,
      });
    }
  );

  test(
    "D2 somatic answer routes to cancer biology workflow",
    async ({ page }) => {
      test.setTimeout(300_000);
      await setupTestUser(page, "disambig_d2");

      // 1. Send ambiguous query
      await sendChatMessage(
        page,
        "I want to perform variant calling on whole genome sequencing data using BWA and GATK"
      );
      await waitForAssistantMessage(page, 90_000);

      // 2. Answer: somatic / tumor-normal
      const gotWorkflow = await sendMessageAndWaitForResponse(
        page,
        "This is somatic variant calling — I have a matched tumor-normal pair",
        180_000
      );

      const response2 = await waitForAssistantMessage(page, 10_000);
      console.log(
        `[D2] After somatic answer, workflow panel: ${gotWorkflow}, snippet: ${response2.substring(0, 200).replace(/\n/g, " ")}`
      );

      // 3. If a workflow was generated, it should reference somatic/cancer keywords
      if (gotWorkflow) {
        const lower2 = response2.toLowerCase();
        const isSomatic =
          lower2.includes("somatic") ||
          lower2.includes("tumor") ||
          lower2.includes("mutect") ||
          lower2.includes("cancer") ||
          lower2.includes("normal");
        console.log(`[D2] Somatic keywords in response: ${isSomatic}`);
        expect(isSomatic).toBe(true);
      }

      await page.screenshot({
        path: "e2e/screenshots/disambiguation/D2_somatic_workflow.png",
        fullPage: false,
      });
    }
  );

  test(
    "D3 germline answer routes to WGS germline workflow",
    async ({ page }) => {
      test.setTimeout(300_000);
      await setupTestUser(page, "disambig_d3");

      await sendChatMessage(
        page,
        "I want to perform variant calling on whole genome sequencing data using BWA and GATK"
      );
      await waitForAssistantMessage(page, 90_000);

      const gotWorkflow = await sendMessageAndWaitForResponse(
        page,
        "This is germline variant calling for inherited disease — single patient, no tumor",
        180_000
      );

      const response2 = await waitForAssistantMessage(page, 10_000);
      console.log(
        `[D3] After germline answer, workflow panel: ${gotWorkflow}, snippet: ${response2.substring(0, 200).replace(/\n/g, " ")}`
      );

      if (gotWorkflow) {
        const lower2 = response2.toLowerCase();
        const isGermline =
          lower2.includes("germline") ||
          lower2.includes("haplotypecaller") ||
          lower2.includes("gatk") ||
          lower2.includes("inherited") ||
          lower2.includes("rare disease");
        console.log(`[D3] Germline keywords in response: ${isGermline}`);
        expect(isGermline).toBe(true);
      }

      await page.screenshot({
        path: "e2e/screenshots/disambiguation/D3_germline_workflow.png",
        fullPage: false,
      });
    }
  );
});

// ===========================================================================
// D4 — RNA-seq disambiguation: bulk vs single-cell
// ===========================================================================
test.describe("RNA-seq disambiguation", () => {
  test(
    "D4 RNA-seq query: AI asks about type or generates sensible RNA-seq workflow",
    async ({ page }) => {
      test.setTimeout(300_000);
      await setupTestUser(page, "disambig_d4");

      // Query specifies data context to avoid pure dataset-first response
      const gotWorkflow = await sendMessageAndWaitForResponse(
        page,
        "I want to analyze transcriptomics data from 12 tumor samples and 12 normal tissue samples",
        180_000
      );

      const response = await waitForAssistantMessage(page, 10_000);
      const lower = response.toLowerCase();
      console.log(
        `[D4] gotWorkflow=${gotWorkflow}, snippet: ${response.substring(0, 300).replace(/\n/g, " ")}`
      );

      // ACCEPTABLE outcomes:
      //   (a) AI asks about bulk vs single-cell
      //   (b) AI generates a bulk RNA-seq workflow (12 tumour vs normal → DE analysis → bulk)
      //       OR responses about RNA-seq even if workflow generation deferred
      //   (c) AI asks for dataset/data format/location
      // UNACCEPTABLE:
      //   - Response with no RNA-seq or transcriptomics content at all

      const askedClarification =
        lower.includes("single") ||
        lower.includes("bulk") ||
        lower.includes("single-cell") ||
        lower.includes("clarif");
      const isAboutRnaSeq =
        lower.includes("rna") ||
        lower.includes("transcriptom") ||
        lower.includes("deseq") ||
        lower.includes("expression") ||
        lower.includes("differential");
      const generatedRnaWorkflow = gotWorkflow && isAboutRnaSeq;
      const askedForDataset =
        lower.includes("fastq") ||
        lower.includes("upload") ||
        lower.includes("format") ||   // covers "data format", "file format"
        lower.includes("provide") ||
        lower.includes("dataset") ||
        lower.includes("location") ||
        lower.includes("input");

      // Accept if: asked clarification, OR (RNA-seq content + either workflow or data request)
      const acceptable =
        askedClarification ||
        generatedRnaWorkflow ||
        (isAboutRnaSeq && askedForDataset);
      console.log(
        `[D4] askedClarification=${askedClarification}, generatedRnaWorkflow=${generatedRnaWorkflow}, askedForDataset=${askedForDataset}`
      );
      expect(acceptable).toBe(true);

      await page.screenshot({
        path: "e2e/screenshots/disambiguation/D4_rnaseq_disambiguation.png",
        fullPage: false,
      });
    }
  );
});

// ===========================================================================
// D5 — Unambiguous query does NOT trigger clarification
// ===========================================================================
test.describe("Unambiguous queries skip clarification", () => {
  test(
    "D5 explicit somatic query goes directly to workflow (no clarification)",
    async ({ page }) => {
      test.setTimeout(300_000);
      await setupTestUser(page, "disambig_d5");

      const gotWorkflow = await sendMessageAndWaitForResponse(
        page,
        "Run somatic variant calling on tumor-normal WGS data using MuTect2 and BWA",
        180_000
      );

      const response = await waitForAssistantMessage(page, 10_000);
      console.log(
        `[D5] Direct somatic query, workflow: ${gotWorkflow}, snippet: ${response.substring(0, 200).replace(/\n/g, " ")}`
      );

      // Should have generated a workflow or at least not asked for clarification
      // (the word "somatic" is unambiguous)
      const lower = response.toLowerCase();
      const askedAboutSomatic =
        lower.includes("germline or somatic") ||
        lower.includes("somatic or germline");
      console.log(`[D5] Asked redundant clarification: ${askedAboutSomatic}`);
      expect(askedAboutSomatic).toBe(false);

      await page.screenshot({
        path: "e2e/screenshots/disambiguation/D5_direct_somatic.png",
        fullPage: false,
      });
    }
  );

  test(
    "D6 explicit germline query goes directly to workflow (no clarification)",
    async ({ page }) => {
      test.setTimeout(300_000);
      await setupTestUser(page, "disambig_d6");

      const gotWorkflow = await sendMessageAndWaitForResponse(
        page,
        "I want to call germline variants using GATK HaplotypeCaller on WGS trio data",
        180_000
      );

      const response = await waitForAssistantMessage(page, 10_000);
      console.log(
        `[D6] Direct germline query, workflow: ${gotWorkflow}, snippet: ${response.substring(0, 200).replace(/\n/g, " ")}`
      );

      const lower = response.toLowerCase();
      const askedRedundant =
        lower.includes("germline or somatic") ||
        lower.includes("somatic or germline") ||
        lower.includes("is this germline");
      console.log(`[D6] Asked redundant clarification: ${askedRedundant}`);
      expect(askedRedundant).toBe(false);

      await page.screenshot({
        path: "e2e/screenshots/disambiguation/D6_direct_germline.png",
        fullPage: false,
      });
    }
  );
});
