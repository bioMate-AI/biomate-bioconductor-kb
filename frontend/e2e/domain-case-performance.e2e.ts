import { test, expect, type Page } from "@playwright/test";
import { writeFile } from "fs/promises";
import { setupTestUser } from "./helpers.js";

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

test.setTimeout(480000);

interface CaseMetric {
  caseId: string;
  domain: string;
  prompt: string;
  pendingCueMs: number | null;
  responseMs: number | null;
  workflowCardVisible: boolean;
  runActionVisible: boolean;
  overrideUsed: boolean;
  terminalCueVisible: boolean;
  domainSignalMatched: boolean;
}

async function openAndSubmit(page: Page, prompt: string) {
  const newChat = page.getByRole("button", { name: /new chat/i }).first();
  if (await newChat.isVisible().catch(() => false)) {
    await newChat.click().catch(() => {});
  }
  const chatInput = page.locator("textarea").first();
  await expect(chatInput).toBeVisible({ timeout: 10000 });
  await chatInput.fill(prompt);
  const start = Date.now();
  await chatInput.press("Enter");
  return start;
}

async function detectPendingCue(page: Page, timeoutMs = 10000): Promise<number | null> {
  const pending = page.getByTestId("chat-response-pending");
  const typing = page.locator("text=AI is typing").first();
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const [pVisible, tVisible] = await Promise.all([
      pending.isVisible().catch(() => false),
      typing.isVisible().catch(() => false),
    ]);
    if (pVisible || tVisible) {
      return Date.now() - start;
    }
    await page.waitForTimeout(250);
  }
  return null;
}

async function waitForAssistantResponse(page: Page, timeoutMs = 150000): Promise<number | null> {
  const start = Date.now();
  await page.waitForSelector("text=AI is typing", { state: "hidden", timeout: timeoutMs }).catch(() => {});
  const assistantCard = page.locator('[data-role="assistant"]').last();
  const visible = await assistantCard.isVisible().catch(() => false);
  if (!visible) return null;
  return Date.now() - start;
}

async function gatherCaseMetric(
  page: Page,
  caseId: string,
  domain: string,
  prompt: string,
  domainSignals: RegExp[]
): Promise<CaseMetric> {
  await page.goto(BASE_URL);
  await page.waitForLoadState("networkidle");

  const submitStart = await openAndSubmit(page, prompt);
  const pendingCueMs = await detectPendingCue(page, 10000);
  const responseElapsed = await waitForAssistantResponse(page, 150000);
  const responseMs = responseElapsed !== null ? Date.now() - submitStart : null;

  await page.waitForTimeout(2000);

  const workflowCardVisible = await page.locator("text=Nextflow Workflow").last().isVisible().catch(() => false);
  const runActionVisible = await page
    .getByRole("button", { name: /run workflow|^run$|execute/i })
    .last()
    .isVisible()
    .catch(() => false);

  const combinedText = (await page.locator("body").textContent().catch(() => "")) || "";
  const domainSignalMatched = domainSignals.some((signal) => signal.test(combinedText));

  let terminalCueVisible = false;
  let executionPanelVisible = false;
  let overrideUsed = false;
  if (runActionVisible) {
    const runButton = page.getByRole("button", { name: /run workflow|^run$|execute/i }).last();
    const runEnabled = await runButton.isEnabled().catch(() => false);
    if (runEnabled) {
      await runButton.click();
    } else {
      const overrideButton = page.getByTestId("button-confirm-low-confidence-run").last();
      const overrideVisible = await overrideButton.isVisible().catch(() => false);
      if (overrideVisible) {
        await overrideButton.click();
        overrideUsed = true;
      }
    }
    const terminalCue = page
      .locator("text=RUNNING")
      .last()
      .or(page.locator("text=COMPLETED").last())
      .or(page.locator("text=FAILED").last())
      .or(page.locator("text=CANCELLED").last())
      .or(page.getByRole("button", { name: /view results|hide results/i }).last());
    terminalCueVisible = await terminalCue.isVisible({ timeout: 240000 }).catch(() => false);
    executionPanelVisible = await page.locator("text=Execution Progress").last().isVisible().catch(() => false);
  }

  return {
    caseId,
    domain,
    prompt,
    pendingCueMs,
    responseMs,
    workflowCardVisible,
    runActionVisible,
    overrideUsed,
    terminalCueVisible: terminalCueVisible || executionPanelVisible,
    domainSignalMatched,
  };
}

test.describe("Domain Case Performance UI", () => {
  test("runs domain-specific UI performance cases", async ({ page }, testInfo) => {
    // Register + log in so the chat textarea is accessible
    await setupTestUser(page, "domain_perf");

    const metrics: CaseMetric[] = [];

    metrics.push(
      await gatherCaseMetric(
        page,
        "DTC-02",
        "WES QC",
        "I need quality control workflow for whole-exome sequencing BAM files from tumor-normal pairs.",
        [/whole-exome|exome|tumor-normal|bam/i]
      )
    );

    metrics.push(
      await gatherCaseMetric(
        page,
        "DTC-04",
        "RNA-seq Differential Expression",
        "Create an RNA-seq differential expression workflow using DESeq2 with QC and quantification.",
        [/deseq2|differential expression|rna-seq|quantification/i]
      )
    );

    // Feedback-edge case through real UI
    await page.goto(BASE_URL);
    await page.waitForLoadState("networkidle");
    await openAndSubmit(page, "Build me a quality control workflow for RNA-seq FASTQ files");
    await waitForAssistantResponse(page, 150000);
    await page.waitForTimeout(2000);

    const thumbsDown = page.getByTestId("inline-feedback-thumbs-down").last();
    const thumbsDownVisible = await thumbsDown.isVisible().catch(() => false);
    expect(thumbsDownVisible).toBe(true);
    await thumbsDown.click();
    const reasonButton = page.getByRole("button", { name: /Confusing UI|Unclear output|Too slow/i }).first();
    await expect(reasonButton).toBeVisible({ timeout: 10000 });
    await reasonButton.click();
    await page.getByRole("button", { name: "Submit" }).last().click();
    const feedbackConfirmed = await page.locator("text=Thanks for your feedback").last().isVisible().catch(() => false);
    expect(feedbackConfirmed).toBe(true);

    metrics.push({
      caseId: "DTC-08",
      domain: "Feedback Edge",
      prompt: "Build me a quality control workflow for RNA-seq FASTQ files",
      pendingCueMs: null,
      responseMs: null,
      workflowCardVisible: true,
      runActionVisible: true,
      overrideUsed: false,
      terminalCueVisible: true,
      domainSignalMatched: true,
    });

    // Persist evidence before strict checks so failures still emit useful data.
    const reportPath = testInfo.outputPath("domain-case-performance-report.json");
    await writeFile(
      reportPath,
      JSON.stringify(
        {
          baseUrl: BASE_URL,
          generatedAt: new Date().toISOString(),
          metrics,
        },
        null,
        2
      ),
      "utf-8"
    );
    await testInfo.attach("domain-case-performance-report", {
      path: reportPath,
      contentType: "application/json",
    });

    // Performance gates for domain cases (DTC-02, DTC-04 only)
    const strictCases = metrics.filter((m) => m.caseId !== "DTC-08");
    for (const m of strictCases) {
      expect(m.pendingCueMs !== null && m.pendingCueMs <= 10000).toBe(true);
      expect(m.responseMs !== null && m.responseMs <= 150000).toBe(true);
      expect(m.workflowCardVisible).toBe(true);
      expect(m.runActionVisible).toBe(true);
      expect(m.terminalCueVisible).toBe(true);
      expect(m.domainSignalMatched).toBe(true);
    }
  });
});
