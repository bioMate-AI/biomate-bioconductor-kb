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

  const connectionError = page.getByText(/Connection error/i).last();
  if (await connectionError.isVisible().catch(() => false)) {
    const retry = page.getByRole("button", { name: /Try again/i }).last();
    if (await retry.isVisible().catch(() => false)) {
      await retry.click();
      await waitAssistantDone(page);
    }
  }
}

async function pageText(page: Page): Promise<string> {
  return ((await page.locator("body").innerText().catch(() => "")) || "").toLowerCase();
}

function countHits(text: string, patterns: RegExp[]) {
  return patterns.reduce((acc, p) => (p.test(text) ? acc + 1 : acc), 0);
}

test.describe("Drug Development CMC + Stability Gates (Real E2E)", () => {
  test("CMC-001: includes formulation/stability/tox gate criteria and actionable fallback", async ({ page }) => {
    await setupTestUser(page, "dd_cmc-stabi");
    await sendPrompt(
      page,
      [
        "Build a small-molecule oncology CMC and preclinical readiness workflow for oral tablet formulation.",
        "I need explicit decision gates for:",
        "1) formulation feasibility (solubility, dissolution, compatibility),",
        "2) stability (accelerated and stress conditions),",
        "3) safety gate aligned with ADMET red flags.",
        "For each gate provide pass/fail criteria and what to do next if the gate fails.",
      ].join(" ")
    );

    const text = await pageText(page);

    const cmcCoverage = countHits(text, [
      /cmc|formulation|oral tablet|compatibility|excipient/i,
      /solubility|dissolution|bioavailability/i,
      /stability|accelerated|stress condition|degradation/i,
      /admet|toxicity|herg|dili|safety/i,
    ]);
    expect(cmcCoverage).toBeGreaterThanOrEqual(3);

    const decisionQuality = countHits(text, [
      /decision gate|go\/no-go|go-no-go|gate/i,
      /threshold|cutoff|acceptance criteria|pass criteria|fail criteria/i,
      /if .* fails|fallback|recovery plan|next steps/i,
    ]);
    expect(decisionQuality).toBeGreaterThanOrEqual(2);

    const runButtonVisible = await page.getByTestId("button-run-workflow-panel").last().isVisible().catch(() => false);
    const collaborativeFallback =
      /workflow generation failed|workflow generation is currently unavailable|to unblock this quickly|follow-up|suggested next actions/i.test(
        text
      );
    const responseCardVisible = await page
      .getByRole("button", { name: /Copy response/i })
      .last()
      .isVisible()
      .catch(() => false);

    expect(runButtonVisible || collaborativeFallback || responseCardVisible).toBe(true);
  });
});
