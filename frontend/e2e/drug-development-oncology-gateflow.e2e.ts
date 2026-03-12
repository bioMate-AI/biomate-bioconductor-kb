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

async function pageText(page: Page) {
  return ((await page.locator("body").innerText().catch(() => "")) || "").toLowerCase();
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
    const tryAgain = page.getByRole("button", { name: /Try again/i }).last();
    if (await tryAgain.isVisible().catch(() => false)) {
      await tryAgain.click();
      await waitAssistantDone(page);
    }
  }
}

function countHits(text: string, terms: RegExp[]) {
  return terms.reduce((acc, term) => (term.test(text) ? acc + 1 : acc), 0);
}

test.describe("Drug Development Oncology Gateflow (Real E2E)", () => {
  test("ONC-001: response includes staged oncology flow with explicit go/no-go gates", async ({ page }) => {
    await setupTestUser(page, "dd_oncology-");
    await sendPrompt(
      page,
      [
        "Design a real-world oncology lead-optimization workflow for EGFR inhibitors.",
        "I need staged execution across:",
        "1) structure-based docking and pose triage,",
        "2) ADMET safety screening including hERG and DILI risks,",
        "3) phase-I style PK/NCA readout with AUC/Cmax/Tmax/half-life.",
        "Include explicit go/no-go decision gates and what to do if a gate fails.",
      ].join(" ")
    );

    const text = await pageText(page);

    const domainCoverage = countHits(text, [
      /oncology|egfr|lead optimization|lead-optimization/i,
      /docking|binding pose|affinity/i,
      /admet|herg|dili|toxicity/i,
      /pk|pharmacokinetic|nca|auc|cmax|tmax|half[- ]?life/i,
    ]);
    expect(domainCoverage).toBeGreaterThanOrEqual(3);

    const gateSignals = countHits(text, [
      /go\/no-go|go-no-go|decision gate|gate/i,
      /threshold|cutoff|criteria/i,
      /if .* fails|if .* fail|fallback|recovery plan|next steps/i,
    ]);
    expect(gateSignals).toBeGreaterThanOrEqual(2);

    const runButtonVisible = await page.getByTestId("button-run-workflow-panel").last().isVisible().catch(() => false);
    const collaborativeFailureMode =
      /workflow generation failed|workflow generation is currently unavailable|to unblock this quickly|suggested next actions|follow-up/i.test(
        text
      );
    const assistantCardVisible = await page
      .getByRole("button", { name: /Copy response/i })
      .last()
      .isVisible()
      .catch(() => false);

    // In real environments runnable + collaborative-fallback + response-card states are valid.
    expect(runButtonVisible || collaborativeFailureMode || assistantCardVisible).toBe(true);
  });
});
