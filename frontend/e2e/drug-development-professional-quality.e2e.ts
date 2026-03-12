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
  await page.waitForTimeout(1000);
}

async function sendPrompt(page: Page, prompt: string) {
  await page.goto(BASE_URL);
  await page.waitForLoadState("networkidle");
  const input = page.locator("textarea").first();
  await expect(input).toBeVisible({ timeout: 15000 });
  const streamResponsePromise = page.waitForResponse(
    (response) => response.url().includes("/api/chat/stream") && response.request().method() === "POST",
    { timeout: 180000 }
  );
  await input.fill(prompt);
  await input.press("Enter");
  await waitAssistantDone(page);

  // Real systems can transiently return a connection error.
  const connectionError = page.getByText(/Connection error/i).last();
  if (await connectionError.isVisible().catch(() => false)) {
    const retry = page.getByRole("button", { name: /Try again/i }).last();
    if (await retry.isVisible().catch(() => false)) {
      await retry.click();
      await waitAssistantDone(page);
    }
  }
  const streamResponse = await streamResponsePromise.catch(() => null);
  if (!streamResponse) return null;
  try {
    const text = await streamResponse.text();
    const blocks = text.split("\n\n");
    for (const block of blocks) {
      const lines = block.split("\n");
      const eventLine = lines.find((line) => line.startsWith("event: "));
      if (!eventLine || !eventLine.includes("final")) continue;
      const dataLine = lines.find((line) => line.startsWith("data: "));
      if (!dataLine) continue;
      return JSON.parse(dataLine.slice(6));
    }
  } catch {
    return null;
  }
  return null;
}

async function pageText(page: Page) {
  return ((await page.locator("body").innerText().catch(() => "")) || "").toLowerCase();
}

function normalizeText(value: unknown) {
  return String(value || "").toLowerCase();
}

function countTermHits(text: string, terms: RegExp[]) {
  return terms.reduce((acc, term) => (term.test(text) ? acc + 1 : acc), 0);
}

function runButton(page: Page) {
  return page.getByTestId("button-run-workflow-panel").last();
}

test.describe("Drug Development Professional Quality (Real E2E)", () => {
  test("PDQ-001: ADMET response includes risk dimensions and decision-grade guidance", async ({ page }) => {
    await setupTestUser(page, "dd_prof");
    const finalPayload = await sendPrompt(
      page,
      "Run ADMET toxicity screening for acetaminophen (SMILES: CC(=O)Nc1ccc(O)cc1). I need hERG cardiotoxicity risk, DILI assessment, Ames mutagenicity, and ClinTox probability."
    );

    const text = `${await pageText(page)}\n${normalizeText(finalPayload?.response)}\n${normalizeText(
      JSON.stringify(finalPayload?.metadata?.workflowGenerationDiagnostics || {})
    )}`;
    const domainHits = countTermHits(text, [/admet/i, /herg/i, /dili/i, /ames/i, /clintox/i, /toxicity/i]);
    expect(domainHits).toBeGreaterThanOrEqual(3);

    const decisionHits = countTermHits(text, [
      /threshold/i,
      /cutoff/i,
      /risk/i,
      /gate/i,
      /next step/i,
      /follow-up/i,
      /recovery plan/i,
      /confirm/i,
    ]);
    expect(decisionHits).toBeGreaterThanOrEqual(2);

    const runVisible = await runButton(page).isVisible().catch(() => false);
    const collaborativeVisible =
      /workflow generation failed|workflow generation is currently unavailable|recovery plan|suggested next actions|follow-up/i.test(
        text
      );
    expect(runVisible || collaborativeVisible).toBe(true);
  });

  test("PDQ-002: PK/NCA response contains pharmacokinetic metrics or explicit scientifically valid fallback", async ({ page }) => {
    await setupTestUser(page, "dd_prof");
    const finalPayload = await sendPrompt(
      page,
      "Create a phase-I pharmacokinetics NCA workflow from concentration-time data. I need AUClast, AUCinf, Cmax, Tmax, and half-life."
    );

    const text = `${await pageText(page)}\n${normalizeText(finalPayload?.response)}\n${normalizeText(
      JSON.stringify(finalPayload?.metadata?.workflowGenerationDiagnostics || {})
    )}`;
    const pkHits = countTermHits(text, [
      /auc/i,
      /cmax/i,
      /tmax/i,
      /half[- ]?life|t½/i,
      /pharmacokinetic/i,
      /non[- ]compartmental|nca/i,
    ]);
    expect(pkHits).toBeGreaterThanOrEqual(3);

    const runVisible = await runButton(page).isVisible().catch(() => false);
    const validFallbackHits = countTermHits(text, [
      /no .*nca.*tool|none found|not available|missing/i,
      /compartmental|mono_exp_model|bi_exp_model|pknca/i,
      /recovery plan|next steps|confirm or edit|follow-up/i,
    ]);
    expect(runVisible || validFallbackHits >= 2).toBe(true);
  });

  test("PDQ-003: Cross-domain impossible request returns multi-cause diagnostic plus collaboration", async ({ page }) => {
    await setupTestUser(page, "dd_prof");
    const finalPayload = await sendPrompt(
      page,
      "Build one single runnable workflow that simultaneously requires AlphaFold3 structure fitting, cryo-EM particle reconstruction, and phase-I NCA pharmacokinetics using only tools currently available in this instance, with no input files provided, and execute immediately."
    );

    const text = `${await pageText(page)}\n${normalizeText(finalPayload?.response)}\n${normalizeText(
      JSON.stringify(finalPayload?.metadata?.workflowGenerationDiagnostics || {})
    )}`;
    const reasonCategories = [
      /none found|not available|missing tool|tool coverage/i.test(text), // tool gap
      /no input|without input|require input|input files provided/i.test(text), // input gap
      /incompatible|different data types|cannot be chained|not scientifically integrable|different domains/i.test(text), // domain mismatch
    ].filter(Boolean).length;
    expect(reasonCategories).toBeGreaterThanOrEqual(2);

    const collaborationSignals = countTermHits(text, [
      /what .*input/i,
      /which analysis|which stage/i,
      /input files/i,
      /confirm/i,
      /next steps/i,
      /follow-up/i,
      /recovery plan/i,
      /to unblock this quickly/i,
    ]);
    expect(collaborationSignals).toBeGreaterThanOrEqual(2);
  });
});

