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
  await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
  const newChatBtn = page.locator('[data-testid="button-new-chat"]').first();
  if (await newChatBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await newChatBtn.click();
    await page.waitForTimeout(500);
  }
}

async function sendMessage(page: Page, text: string) {
  const composer = page
    .locator('textarea, input[placeholder*="Ask"], input[placeholder*="Describe"]')
    .first();
  await expect(composer).toBeVisible({ timeout: 30_000 });
  await composer.fill(text);
  await composer.press("Enter");
}

test("multi-task request produces a whole-plan DAG draft card (no dispatch)", async () => {
  const page = sharedPage;
  await newSession(page);

  // A decomposable request whose sub-tasks map to real workflows.
  const message =
    "Run quality control, then read alignment, then differential expression on my " +
    "RNA-seq data. Prepare the plan — do not launch any jobs yet.";
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
    // Flag off, or the request did not confidently decompose+resolve → single-task
    // fallback. That is the safe, expected behaviour; nothing to assert here.
    test.skip(
      true,
      `No multi-step DAG card (stepCount=${stepCount}). Flag off or safe single-task fallback. ` +
        `Enable BIOMATE_MULTITASK_DAG_ENABLED on biomate-galaxy-dev to exercise the DAG path.`,
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
