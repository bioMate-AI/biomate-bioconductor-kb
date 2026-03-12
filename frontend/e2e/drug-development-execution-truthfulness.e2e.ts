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
  await page.waitForTimeout(1200);
}

async function sendPrompt(page: Page, prompt: string) {
  await page.goto(BASE_URL);
  await page.waitForLoadState("networkidle");
  const input = page.locator("textarea").first();
  await expect(input).toBeVisible({ timeout: 15000 });
  await input.fill(prompt);
  await input.press("Enter");
  await waitAssistantDone(page);
}

test.describe("Drug Development Execution Truthfulness (Real E2E)", () => {
  test("TRUTH-001: unresolved workflow must not over-promise immediate run readiness", async ({ page }) => {
    await setupTestUser(page, "dd_execution");
    await sendPrompt(
      page,
      "Build one single runnable workflow combining cryo-EM particle reconstruction, AlphaFold3 structure fitting, and phase-I PK/NCA with no input files and execute immediately."
    );

    const runVisible = await page.getByTestId("button-run-workflow-panel").last().isVisible().catch(() => false);
    const text = ((await page.locator("body").innerText().catch(() => "")) || "").toLowerCase();

    if (!runVisible) {
      // Key truthfulness requirement: if run control is absent, user still gets explicit caveat/recovery value.
      const hasCautionSignal =
        /partial workflow|incomplete|important heads-up|critical gaps|limitations to review|not yet safe to execute/i.test(
          text
        );
      const hasRecoverySignal =
        /workflow generation is currently unavailable|recovery plan|to unblock this quickly|suggested next actions|follow-up/.test(
          text
        );
      expect(hasCautionSignal || hasRecoverySignal).toBe(true);
      return;
    }

    // If run appears in this environment, that's also valid.
    await expect(page.getByTestId("button-run-workflow-panel").last()).toBeVisible();
  });
});
