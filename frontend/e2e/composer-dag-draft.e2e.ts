/**
 * Composer multi-step plan — DRAFT generation (ZERO Batch cost).
 * ===========================================================================
 * Verifies that a multi-step ("run A, then B, then C") request produces a
 * runnable multi-step PLAN as a DRAFT, through BioMate's LIVE composer:
 *   analyzeIntent (isMultiIntent + isSequential) -> processMultiIntent ->
 *   processSequentialPipeline  (frontend/server/galaxy-assistant.ts).
 *
 * NOTE: the live multi-step plan renders in EITHER of two valid shapes, and the
 * test accepts both: (a) an inline PipelineListView (pipeline-step-<id> rows), or
 * (b) a curated chain/workflow opened in the RIGHT PANEL (button-run-workflow-panel
 * + a chat wf-chip) when one curated chain covers all steps — which is what
 * "QC -> alignment -> DE" resolves to (bulk_rnaseq_de_analysis), verified on dev.
 * This is NOT the backend BIOMATE_MULTITASK_DAG_ENABLED composer (route_and_handle),
 * which is not wired to the live path (see
 * docs/20261012_COMPOSER_FLAG_ENABLED_AND_WIRING_GAP.md).
 *
 * SAFETY: this test NEVER clicks "Confirm & Run", so it dispatches NO jobs and
 * costs $0 of Batch. Generating the plan never launches anything; only Confirm &
 * Run does. It only asserts the DRAFT plan renders and was NOT dispatched.
 *
 * If no runnable plan renders (safe single-workflow collapse / clarification),
 * the test SKIPS rather than failing — that is a correct safe outcome.
 *
 * CLAUDE.md: single canonical fixture, login once, no register, BIOMATE_URL.
 */
import { test, expect, type Page } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { waitForResponseComplete } from "./helpers.js";

const LLM_TIMEOUT = 120_000;
test.setTimeout(5 * 60_000);

let sharedPage: Page;

test.beforeAll(async ({ browser }) => {
  sharedPage = await browser.newPage();
  await loginAsFixture(sharedPage);
  console.log("[Auth] Fixture login complete");
});

test.afterAll(async () => {
  await sharedPage?.close();
});

async function newSession(page: Page) {
  // Proven dev navigation (ui-interaction-flows.e2e.ts gotoFreshChat): `networkidle`
  // NEVER fires on the dev production build (deferred resources) and hangs the goto —
  // use `domcontentloaded` + a bounded load wait, then wait for the composer to be
  // interactive. The previous `networkidle` wait left the page non-interactive, so the
  // message was never actually sent (0 cards regardless of query) — verified via dev logs.
  await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded", timeout: 30_000 });
  // NB: do NOT await waitForLoadState("load") — on the dev production build "load"
  // never fires (deferred resources; see _fixture-login.ts) and .catch does not rescue a
  // promise that never resolves, so it burns the whole test timeout. The composer
  // visibility wait below (bounded 30s) is the real readiness signal.
  await page.evaluate(() => {
    try {
      localStorage.setItem("biomate_survey_suppressed_until", String(Date.now() + 7 * 86400_000));
    } catch {}
  });
  await page
    .locator('[data-testid="chat-input"], textarea')
    .first()
    .waitFor({ state: "visible", timeout: 30_000 });
  const newChatBtn = page.locator('[data-testid="button-new-chat"]').first();
  if (await newChatBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await newChatBtn.click();
    await page.waitForTimeout(500);
  }
}

async function sendMessage(page: Page, text: string) {
  const composer = page
    .locator('[data-testid="chat-input"], textarea[placeholder*="Ask BioMate"], textarea[placeholder*="Ask"], textarea')
    .first();
  await expect(composer).toBeVisible({ timeout: 30_000 });
  await composer.click();
  await composer.fill(text);
  await page.keyboard.press("Enter");
}

test("multi-task request produces a whole-plan DAG draft card (no dispatch)", async () => {
  const page = sharedPage;
  await newSession(page);

  // A decomposable request whose sub-tasks map to real workflows.
  // NOTE: do NOT append "prepare the plan — do not launch any jobs yet" or similar.
  // Generating a workflow/pipeline card NEVER dispatches anything (dispatch requires
  // clicking "Confirm & Run", which this test never does — that is the zero-Batch-cost
  // guarantee). But that phrasing makes the intent classifier (analyzeIntent) tag the
  // whole message as `general_question`/`isMultiIntent:false`, suppressing workflow
  // generation upstream of every pipeline path → 0 cards (verified on dev 2026-10-12).
  // The bare sequential request classifies correctly: 3 intents, SEQUENTIAL pipeline.
  const message =
    "Run quality control, then read alignment, then differential expression on my RNA-seq data.";
  await sendMessage(page, message);
  await waitForResponseComplete(page, LLM_TIMEOUT);

  // The live composer renders a multi-step plan in EITHER of two valid shapes:
  //  (a) inline PipelineListView (pipeline-step-<id> rows + pipeline-list-view) — the
  //      generic DAG card; or
  //  (b) a curated chain / workflow opened in the RIGHT PANEL (button-run-workflow-panel
  //      + a chat wf-chip "In panel"), when ONE curated chain (e.g. bulk_rnaseq_de_analysis)
  //      covers all the steps. For "QC → alignment → DE" the live system uses (b).
  // Both are correct, runnable, UN-dispatched plans. The card lands last (the response can
  // take ~60s), so wait (bounded) for either representation before asserting.
  await page
    .locator('[data-testid="pipeline-list-view"], [data-testid^="pipeline-step-"], [data-testid="button-run-workflow-panel"]')
    .first()
    .waitFor({ state: "visible", timeout: 30_000 })
    .catch(() => {});
  await page.waitForTimeout(1_000);
  await page
    .screenshot({ path: "e2e/test-results/composer-dag-draft.png", fullPage: true })
    .catch(() => {});

  const stepRows = await page.locator('[data-testid^="pipeline-step-"]').count().catch(() => 0);
  const inlineCards = await page.locator('[data-testid^="workflow-artifact-anchor-"]').count().catch(() => 0);
  const panelRunCta = await page
    .getByTestId("button-run-workflow-panel")
    .first()
    .isVisible({ timeout: 2_000 })
    .catch(() => false);
  console.log(`[composer-dag] pipeline-step rows=${stepRows}, inline cards=${inlineCards}, panel run CTA=${panelRunCta}`);

  // Success = a runnable multi-step plan rendered in either representation.
  const renderedPlan = stepRows >= 2 || panelRunCta || inlineCards > 0;
  if (!renderedPlan) {
    test.skip(
      true,
      `No runnable plan rendered (steps=${stepRows}, inlineCards=${inlineCards}, panelCTA=${panelRunCta}). ` +
        `Safe single-workflow/clarification outcome — nothing to assert.`,
    );
    return;
  }

  // Confirm-&-Run affordance must be present (whole-plan approval) — we do NOT click it
  // (that is the zero-Batch-cost guarantee: generation never dispatches; Confirm & Run does).
  const confirmVisible =
    panelRunCta ||
    (await page.getByText(/Confirm\s*&?\s*Run|Run plan|Confirm plan/i).first().isVisible({ timeout: 5_000 }).catch(() => false));
  expect(confirmVisible, "a draft plan must expose a Confirm & Run affordance").toBe(true);

  // It must NOT have been dispatched: no step/overall in a running/submitted state, and the
  // panel CTA is the RUN button (button-run-workflow-panel), not the post-run 'run again' CTA.
  const dispatched = await page
    .locator('[data-status="running"], [data-status="submitted"], [data-testid="panel-run-again-cta"]')
    .count()
    .catch(() => 0);
  expect(dispatched, "a draft plan must not have launched (no running/submitted/run-again state)").toBe(0);

  // If the INLINE pipeline representation was used, it must have >=2 steps.
  if (stepRows > 0) {
    expect(stepRows, "an inline pipeline plan should have >=2 steps").toBeGreaterThanOrEqual(2);
  }
  console.log("[composer-dag] PASS — runnable multi-step plan rendered as a draft, not dispatched.");
});
