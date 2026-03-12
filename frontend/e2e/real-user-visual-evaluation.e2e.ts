import { setupTestUser } from "./helpers.js";
import { test, expect } from "@playwright/test";
import { writeFile } from "fs/promises";

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

test.setTimeout(420000);

interface EvaluationDimensions {
  landingChatVisible: boolean;
  sendAffordanceVisible: boolean;
  keyboardHintVisible: boolean;
  pendingResponseVisible: boolean;
  workflowCardVisible: boolean;
  runActionVisible: boolean;
  executionStateVisible: boolean;
  terminalStateReached: boolean;
  statusBadgeVisible: boolean;
  outputStateBadgeVisible: boolean;
  keyActionsVisible: boolean;
  postRunSurveyVisible: boolean;
  sessionPulseVisible: boolean;
}

interface DetailedEvidence {
  prompt: string;
  workflowTitle: string | null;
  workflowStatusText: string | null;
  parametersSectionVisible: boolean;
  outputSectionVisible: boolean;
  resultActions: {
    runWorkflowVisible: boolean;
    viewOrHideResultsVisible: boolean;
    downloadAllVisible: boolean;
    reportConfusionVisible: boolean;
  };
  chat: {
    latestUserMessage: string | null;
    latestAssistantExcerpt: string | null;
  };
}

test.describe("Real User Visual Evaluation", () => {
  test("runs real biomate flow and evaluates UI clarity", async ({ page }, testInfo) => {
    await setupTestUser(page, "ruve");
    const log: string[] = [];
    const startedAt = new Date().toISOString();
    const push = (m: string) => {
      log.push(`[${new Date().toISOString()}] ${m}`);
      console.log(m);
    };

    const dimensions: EvaluationDimensions = {
      landingChatVisible: false,
      sendAffordanceVisible: false,
      keyboardHintVisible: false,
      pendingResponseVisible: false,
      workflowCardVisible: false,
      runActionVisible: false,
      executionStateVisible: false,
      terminalStateReached: false,
      statusBadgeVisible: false,
      outputStateBadgeVisible: false,
      keyActionsVisible: false,
      postRunSurveyVisible: false,
      sessionPulseVisible: false,
    };

    const screenshots: Record<string, string> = {};
    const capture = async (name: string) => {
      const path = testInfo.outputPath(`${name}.png`);
      await page.screenshot({ path, fullPage: true });
      screenshots[name] = path;
    };

    push("Step 1: Open BioMate UI");
    await page.goto(BASE_URL);
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(1500);
    await capture("01-landing");

    const chatInput = page.locator("textarea").first();
    dimensions.landingChatVisible = await chatInput.isVisible().catch(() => false);
    expect(dimensions.landingChatVisible, "Chat composer should be visible on landing").toBe(true);
    const sendButton = page.getByTestId("chat-send-button");
    dimensions.sendAffordanceVisible = await sendButton.isVisible().catch(() => false);
    expect(dimensions.sendAffordanceVisible, "Send affordance should be visible").toBe(true);
    const helperTextVisible = await page
      .locator("text=Press Enter to send. Shift+Enter for a new line.")
      .first()
      .isVisible()
      .catch(() => false);
    const sendTitle = await sendButton.getAttribute("title").catch(() => null);
    dimensions.keyboardHintVisible = helperTextVisible || Boolean(sendTitle);

    push("Step 2: Ask for a real QC workflow");
    const prompt = "Build me a quality control workflow for RNA-seq FASTQ files";
    await chatInput.fill(prompt);
    await chatInput.press("Enter");
    const pendingResponse = page.getByTestId("chat-response-pending");
    const typingIndicator = page.locator("text=AI is typing").first();
    let pendingVisible = false;
    for (let i = 0; i < 10; i++) {
      const [pendingBannerVisible, typingVisible] = await Promise.all([
        pendingResponse.isVisible().catch(() => false),
        typingIndicator.isVisible().catch(() => false),
      ]);
      if (pendingBannerVisible || typingVisible) {
        pendingVisible = true;
        break;
      }
      await page.waitForTimeout(500);
    }
    dimensions.pendingResponseVisible = pendingVisible;

    await page.waitForSelector("text=AI is typing", { state: "hidden", timeout: 120000 }).catch(() => {});
    await page.waitForTimeout(2500);
    await capture("02-workflow-generated");

    const workflowCardTitle = page.locator("text=Nextflow Workflow").first();
    dimensions.workflowCardVisible = await workflowCardTitle.isVisible().catch(() => false);
    expect(dimensions.workflowCardVisible, "Workflow card should be rendered").toBe(true);

    const runButton = page
      .getByRole("button", { name: /run workflow/i })
      .last()
      .or(page.getByRole("button", { name: /^run$/i }).last())
      .or(page.getByRole("button", { name: /execute/i }).last());

    dimensions.runActionVisible = await runButton.isVisible().catch(() => false);
    expect(dimensions.runActionVisible, "Run action should be visible").toBe(true);

    push("Step 3: Execute workflow and observe terminal state");
    const runEnabled = await runButton.isEnabled().catch(() => false);
    if (!runEnabled) {
      push("Run button disabled; requesting prerequisite recovery runnable variant");
      await chatInput.fill(
        "My current workflow run is blocked by missing prerequisites. Please generate a runnable demo path with sample/test inputs and a workflow variant that can produce one visualizable report and downloadable outputs."
      );
      await chatInput.press("Enter");
      await page.waitForSelector("text=AI is typing", { state: "hidden", timeout: 120000 }).catch(() => {});
      await page.waitForTimeout(1500);
    }
    await expect(runButton).toBeEnabled({ timeout: 120000 });
    await runButton.click();

    const terminalIndicators = [
      page.locator("text=RUNNING").first(),
      page.locator("text=COMPLETED").first(),
      page.locator("text=FAILED").first(),
      page.locator("text=CANCELLED").first(),
      page.getByRole("button", { name: /hide results|view results/i }).first(),
      page.getByTestId("post-run-survey-dialog"),
      page.getByTestId("session-end-pulse-dialog"),
    ];

    let terminalReached = false;
    for (let i = 0; i < 120; i++) {
      const visibleStates = await Promise.all(
        terminalIndicators.map((indicator) => indicator.isVisible().catch(() => false))
      );
      if (visibleStates.some(Boolean)) {
        terminalReached = true;
        break;
      }
      await page.waitForTimeout(2000);
    }

    expect(terminalReached, "Terminal state indicators should become visible").toBe(true);
    const stateBadgeVisible = await Promise.all(
      terminalIndicators.slice(0, 4).map((i) => i.isVisible().catch(() => false))
    ).then((arr) => arr.some(Boolean));
    const terminalBadgeVisible = await Promise.all(
      terminalIndicators.slice(1, 4).map((i) => i.isVisible().catch(() => false))
    ).then((arr) => arr.some(Boolean));
    dimensions.executionStateVisible = stateBadgeVisible;
    dimensions.terminalStateReached = terminalBadgeVisible;
    dimensions.statusBadgeVisible = stateBadgeVisible;
    await capture("03-terminal-state");

    const outputStateBadge = page.getByTestId("output-result-state-badge").first();
    dimensions.outputStateBadgeVisible = await outputStateBadge.isVisible().catch(() => false);

    const keyActions = [
      page.getByRole("button", { name: /view results|hide results/i }).first(),
      page.getByRole("button", { name: /download all/i }).first(),
      page.getByRole("button", { name: /report confusion/i }).first(),
      page.getByTestId("button-copy-response-icon").first(),
      page.getByTestId("button-copy-workflow-icon").first(),
      page.getByTestId("button-download-outputs-icon").first(),
    ];
    dimensions.keyActionsVisible = Boolean(
      await Promise.all(keyActions.map((l) => l.isVisible().catch(() => false))).then((arr) => arr.some(Boolean))
    );

    const surveyDialog = page.getByTestId("post-run-survey-dialog");
    dimensions.postRunSurveyVisible = await surveyDialog.isVisible().catch(() => false);
    if (dimensions.postRunSurveyVisible) {
      push("Step 4: Submit post-run survey");
      await surveyDialog.getByRole("button", { name: "Yes" }).nth(0).click();
      await surveyDialog.getByRole("button", { name: "Yes" }).nth(1).click();
      await surveyDialog.getByRole("button", { name: "Yes" }).nth(2).click();
      await surveyDialog.getByRole("button", { name: "Submit" }).click();
    }

    const sessionPulse = page.getByTestId("session-end-pulse-dialog");
    dimensions.sessionPulseVisible = await sessionPulse.isVisible().catch(() => false);
    if (dimensions.sessionPulseVisible) {
      push("Step 5: Dismiss session pulse");
      await sessionPulse.getByRole("button", { name: "Skip" }).click();
    }

    await capture("04-final-ui");

    const workflowTitleText = await page
      .locator("text=Nextflow Workflow")
      .first()
      .textContent()
      .catch(() => null);
    const visibleStatusText = await Promise.all([
      page.locator("text=RUNNING").first().isVisible().then((v) => (v ? "RUNNING" : null)).catch(() => null),
      page.locator("text=COMPLETED").first().isVisible().then((v) => (v ? "COMPLETED" : null)).catch(() => null),
      page.locator("text=FAILED").first().isVisible().then((v) => (v ? "FAILED" : null)).catch(() => null),
      page.locator("text=CANCELLED").first().isVisible().then((v) => (v ? "CANCELLED" : null)).catch(() => null),
      page.locator("text=IDLE").first().isVisible().then((v) => (v ? "IDLE" : null)).catch(() => null),
    ]).then((vals) => vals.find((v) => v !== null) || null);

    const latestUserMessage = await page
      .locator("p")
      .filter({ hasText: prompt })
      .first()
      .textContent()
      .catch(() => null);
    const latestAssistantExcerpt = await page
      .locator("p")
      .filter({ hasText: "Great!" })
      .first()
      .textContent()
      .then((t) => (t ? t.slice(0, 220) : null))
      .catch(() => null);

    const detailedEvidence: DetailedEvidence = {
      prompt,
      workflowTitle: workflowTitleText,
      workflowStatusText: visibleStatusText,
      parametersSectionVisible: await page.locator("text=Parameters").first().isVisible().catch(() => false),
      outputSectionVisible: await page.locator("text=Output Results").first().isVisible().catch(() => false),
      resultActions: {
        runWorkflowVisible: dimensions.runActionVisible,
        viewOrHideResultsVisible: await page.getByRole("button", { name: /view results|hide results/i }).first().isVisible().catch(() => false),
        downloadAllVisible: await page.getByRole("button", { name: /download all/i }).first().isVisible().catch(() => false),
        reportConfusionVisible: await page.getByRole("button", { name: /report confusion/i }).first().isVisible().catch(() => false),
      },
      chat: {
        latestUserMessage,
        latestAssistantExcerpt,
      },
    };

    const criticalChecks = [
      dimensions.landingChatVisible,
      dimensions.sendAffordanceVisible,
      dimensions.workflowCardVisible,
      dimensions.runActionVisible,
      dimensions.executionStateVisible,
      dimensions.statusBadgeVisible,
      dimensions.keyActionsVisible,
    ];
    expect(criticalChecks.every(Boolean), "Critical real-user UX checks must pass").toBe(true);

    const report = {
      suite: "real-user-visual-evaluation",
      baseUrl: BASE_URL,
      startedAt,
      finishedAt: new Date().toISOString(),
      dimensions,
      detailedEvidence,
      logs: log,
      screenshots,
      notes: {
        outputState: dimensions.outputStateBadgeVisible
          ? "Output state badge visible"
          : "Output state badge not detected in this run",
        postRunFeedbackSurface: dimensions.postRunSurveyVisible || dimensions.sessionPulseVisible,
      },
    };

    const reportPath = testInfo.outputPath("real-user-visual-evaluation-report.json");
    await writeFile(reportPath, JSON.stringify(report, null, 2), "utf-8");
    await testInfo.attach("real-user-visual-evaluation-report", {
      path: reportPath,
      contentType: "application/json",
    });
  });
});
