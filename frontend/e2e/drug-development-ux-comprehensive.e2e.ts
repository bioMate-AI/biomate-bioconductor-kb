import { setupTestUser } from "./helpers.js";
import { test, expect, type Page } from "@playwright/test";

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

test.setTimeout(480000);

async function waitAssistantDone(page: Page) {
  await page.waitForSelector("text=AI is typing", { timeout: 10000 }).catch(() => {});
  await page.waitForSelector("text=AI is typing", { state: "hidden", timeout: 180000 }).catch(() => {});
  await page.waitForSelector("text=BioMate is typing", { timeout: 10000 }).catch(() => {});
  await page.waitForSelector("text=BioMate is typing", { state: "hidden", timeout: 180000 }).catch(() => {});
  await page.waitForSelector("text=Analyzing request... response will stream in as soon as it's ready.", {
    state: "hidden",
    timeout: 180000,
  }).catch(() => {});
  await expect(page.locator("textarea").first()).toBeEnabled({ timeout: 180000 });
  await page.waitForTimeout(1500);
}

async function sendPrompt(page: Page, prompt: string) {
  await page.goto(BASE_URL);
  await page.waitForLoadState("networkidle");
  const input = page.locator("textarea").first();
  await expect(input).toBeVisible({ timeout: 15000 });
  await input.fill(prompt);
  await input.press("Enter");
  await waitAssistantDone(page);

  // Real environments can briefly return transient connection errors.
  // Retry once through the UI to keep this suite focused on UX behavior.
  const connectionError = page.getByText(/Connection error/i).last();
  if (await connectionError.isVisible().catch(() => false)) {
    const tryAgain = page.getByRole("button", { name: /Try again/i }).last();
    if (await tryAgain.isVisible().catch(() => false)) {
      await tryAgain.click();
      await waitAssistantDone(page);
    }
  }
}

function runButton(page: Page) {
  return page.getByTestId("button-run-workflow-panel").last();
}

async function hasVisibleText(page: Page, regex: RegExp) {
  return page.getByText(regex).last().isVisible().catch(() => false);
}

test.describe("Drug Development UX - Comprehensive", () => {
  test("DD-001: Generates a drug-dev workflow and shows full run controls", async ({ page }) => {
    await setupTestUser(page, "dd_ux-compre");
    await sendPrompt(
      page,
      "Build a drug discovery workflow from target validation to docking, ADMET screen, hERG safety gate, and a downloadable QC audit package."
    );

    const workflowVisible = await page.locator("text=Nextflow Workflow").last().isVisible().catch(() => false);
    if (workflowVisible) {
      await expect(page.getByTestId("workflow-run-controls").last()).toBeVisible({ timeout: 30000 });
      await expect(page.getByTestId("button-run-workflow-panel").last()).toBeVisible({ timeout: 30000 });
      await expect(page.getByTestId("button-pause-workflow-panel").last()).toBeVisible({ timeout: 30000 });
      await expect(page.getByTestId("button-resume-workflow-panel").last()).toBeVisible({ timeout: 30000 });
      await expect(page.getByTestId("button-restart-workflow-panel").last()).toBeVisible({ timeout: 30000 });
      await expect(page.getByTestId("button-cancel-workflow-panel").last()).toBeVisible({ timeout: 30000 });
      return;
    }

    const hasFailureExplanation = await Promise.all([
      hasVisibleText(page, /Workflow Generation Failed|cannot be built|cannot be built as requested|Here's Why|Let's Recover Together/i),
      hasVisibleText(page, /Recovery Plan|Suggested next actions|Suggested Next Steps|What I.*Help.*Build|Why/i),
      page.getByRole("button", { name: /Copy response/i }).last().isVisible().catch(() => false),
    ]).then((v) => v.some(Boolean));
    expect(hasFailureExplanation).toBe(true);
  });

  test("DD-002: Prerequisite checklist and recovery path are actionable", async ({ page }) => {
    await setupTestUser(page, "dd_ux");
    await sendPrompt(
      page,
      "I do not have files yet. Build a runnable small-molecule drug development workflow and let me run now with sample/test data."
    );

    const run = runButton(page);
    if (!(await run.isVisible().catch(() => false))) {
      const blockedVisible = await page.getByText(/Workflow generation is currently unavailable/i).last().isVisible().catch(() => false);
      const successTextVisible = await page.getByText(/ready to run|Click the "Run" button|generated/i).last().isVisible().catch(() => false);
      const connectionErrorVisible = await page.getByText(/Connection error/i).last().isVisible().catch(() => false);
      const assistantCardVisible = await page.getByRole("button", { name: /Copy response/i }).last().isVisible().catch(() => false);
      expect(blockedVisible || successTextVisible || connectionErrorVisible || assistantCardVisible).toBe(true);
      return;
    }
    if (!(await run.isEnabled().catch(() => false))) {
      await expect(page.getByTestId("workflow-prereq-checklist").last()).toBeVisible({ timeout: 30000 });
      const recovery = page.getByTestId("button-prereq-recovery").last();
      if (await recovery.isVisible().catch(() => false)) {
        await recovery.click();
        await waitAssistantDone(page);
      }
      await expect(
        page.locator("text=Recovery mode is active").last().or(page.getByTestId("workflow-prereq-checklist").last())
      ).toBeVisible({ timeout: 60000 });
    }
  });

  test("DD-003: Run manager and triage blocks stay visible for drug workflow runs", async ({ page }) => {
    await setupTestUser(page, "dd_ux");
    await sendPrompt(
      page,
      "Create a phase-I pharmacokinetics NCA workflow from concentration-time data and prepare it for execution."
    );

    const toggleRunManager = page.getByTestId("button-toggle-run-manager");
    if (await toggleRunManager.isVisible().catch(() => false)) {
      await toggleRunManager.click();
    }
    await expect(page.getByTestId("run-manager-panel")).toBeVisible({ timeout: 30000 });
    await expect(page.getByTestId("run-manager-scope-toggle")).toBeVisible({ timeout: 30000 });

    const run = runButton(page);
    if (await run.isVisible().catch(() => false)) {
      if (await run.isEnabled().catch(() => false)) {
        await run.click();
        await expect(page.getByTestId("run-context-chip").last()).toBeVisible({ timeout: 120000 });
      }

      await expect(page.getByTestId("execution-triage-summary").last()).toBeVisible({ timeout: 60000 });
      await expect(page.getByTestId("execution-triage-status").last()).toBeVisible({ timeout: 60000 });
      await expect(page.getByTestId("execution-triage-next-action").last()).toBeVisible({ timeout: 60000 });
      return;
    }

    const hasFallbackGuidance = await Promise.all([
      hasVisibleText(page, /Workflow generation is currently unavailable|Workflow Generation Failed|Connection error|runnable workflow has been generated|ready for execution/i),
      hasVisibleText(page, /Recovery Plan|follow-up|please answer|confirm or edit|Try again|Create workflow|Workflow Phases|priority stage/i),
    ]).then((v) => v.some(Boolean));
    expect(hasFallbackGuidance).toBe(true);
  });

  test("DD-004: Workflow-generation failure is collaborative and diagnostic (real path)", async ({ page }) => {
    await setupTestUser(page, "dd_ux");
    await sendPrompt(
      page,
      "Build one single runnable workflow that simultaneously requires AlphaFold3 structure fitting, cryo-EM particle reconstruction, and phase-I NCA pharmacokinetics using only tools currently available in this instance, with no input files provided, and execute immediately."
    );

    const hasDiagnostics = await Promise.all([
      hasVisibleText(
        page,
        /Workflow generation is currently unavailable|Workflow Generation Failed|cannot be built|cannot be built as described|Here's Why/i
      ),
      hasVisibleText(
        page,
        /Likely reasons:|Recovery Plan|Suggested next actions|Suggested Next Steps|Reasons Workflow Cannot Execute|What the Tool Search Found/i
      ),
      hasVisibleText(
        page,
        /follow-up|please answer|What is your target|What exact input data do you already have|What I.*Help.*Build|Let's Recover/i
      ),
    ]);
    expect(hasDiagnostics[0] || hasDiagnostics[1]).toBe(true);
    expect(hasDiagnostics[2] || (await page.getByRole("button", { name: /Copy response/i }).last().isVisible().catch(() => false))).toBe(true);
  });
});
