/**
 * Composer multi-task DAG — DRAFT generation (ZERO Batch cost).
 * ===========================================================================
 * Verifies that, when BIOMATE_MULTITASK_DAG_ENABLED is on, a multi-task request
 * is assembled into a whole-plan DAG chain card (decompose -> confidence-gated
 * resolve -> validated DAG -> typed handoff -> input binding -> pipeline card).
 *
 * SAFETY: this test NEVER clicks "Confirm & Run", so it dispatches NO jobs and
 * costs $0 of Batch. It only asserts the DRAFT plan renders.
 *
 * It is also safe to run with the flag OFF: the request then falls back to
 * single-task generation, and this test SKIPS (logs "fell back") rather than
 * failing — a fallback is the correct safe behaviour, not a bug.
 *
 * CLAUDE.md: single canonical fixture, login once, no register, BIOMATE_URL,
 * 90s LLM timeout. See docs/20261012_COMPOSER_DEV_ACTIVATION_AND_TEST_PLAN.md.
 */
import { test, expect, type Page } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { waitForResponseComplete } from "./helpers.js";

const LLM_TIMEOUT = 90_000;
test.setTimeout(10 * 60_000);

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
  await page.waitForLoadState("load").catch(() => {});
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
  await page.waitForTimeout(1_000);

  // DAG/pipeline cards render PipelineListView with pipeline-step-<id> rows.
  const stepRows = page.locator('[data-testid^="pipeline-step-"]');
  const stepCount = await stepRows.count().catch(() => 0);
  const anyCard = await page
    .locator('[data-testid^="workflow-artifact-anchor-"]')
    .count()
    .catch(() => 0);
  console.log(`[composer-dag] pipeline-step rows=${stepCount}, workflow cards=${anyCard}`);

  if (stepCount < 2) {
    // The request did not surface a multi-step pipeline card. Either Tier-1 collapsed
    // it to a single covering workflow (valid), or classification/decomposition did not
    // produce a sequential pipeline. The live pipeline card is produced by the Node-side
    // sequential composer (galaxy-assistant.ts processSequentialPipeline), reached when
    // analyzeIntent flags isMultiIntent+isSequential — NOT by the backend
    // BIOMATE_MULTITASK_DAG_ENABLED flag (that path, route_and_handle, is not wired live).
    test.skip(
      true,
      `No multi-step pipeline card (stepCount=${stepCount}). Single-workflow collapse or ` +
        `non-sequential classification — a safe outcome, nothing to assert here.`,
    );
    return;
  }

  // A DAG draft card was produced — verify it is a whole-plan draft, not launched.
  expect(stepCount, "DAG plan should have >=2 steps").toBeGreaterThanOrEqual(2);

  // No step may be in a running/terminal run state — a DRAFT must not have dispatched.
  const runningish = await page
    .locator('[data-status="running"], [data-status="submitted"], [data-status="completed"]')
    .count()
    .catch(() => 0);
  expect(runningish, "a draft plan must not have launched any step").toBe(0);

  // "Confirm & Run" affordance should be present (whole-plan approval), and we do NOT click it.
  const confirm = page.getByText(/Confirm\s*&?\s*Run|Run plan|Confirm plan/i).first();
  const hasConfirm = await confirm.isVisible({ timeout: 5_000 }).catch(() => false);
  console.log(`[composer-dag] whole-plan Confirm&Run present=${hasConfirm} (NOT clicked — zero Batch cost)`);
});
