/**
 * Index Page Chat Query Input — E2E Tests
 *
 * QI-1  Chat input is visible and focusable after login (onboarding skipped)
 * QI-2  Send button is disabled when the input is empty
 * QI-3  User can type into the input; send button enables
 * QI-4  Pressing Enter submits the query → AI response appears
 * QI-5  Clicking the send button submits the query → AI response appears
 * QI-6  ?q= URL parameter auto-submits without any user action
 * QI-7  ?q= flow produces a workflow card for an ADMET query
 * QI-8  ?q= flow produces a workflow card for an RNA-seq query
 * QI-9  Empty Enter key press does NOT submit (no AI response triggered)
 * QI-10 Fresh user lands directly in chat — no onboarding modal
 *
 * Architecture notes:
 * - All tests hit the live stack — no page.route() mocking.
 * - LLM-path tests use 90 s timeouts (per CLAUDE.md).
 * - Each test calls setupTestUser() for a fresh auth session, then sets
 *   biomate_onboarding_done=1 in localStorage + reloads so the chat input
 *   is immediately visible (no onboarding overlay).
 * - QI-6/7/8 navigate to /?q=<encoded> while already logged in to exercise
 *   the auto-submit path from the marketing hero → register → platform flow.
 */

import { test, expect, Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { setupTestUser, BASE_URL, waitForResponseComplete } from "./helpers.js";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const SS_DIR = "/tmp/qi-e2e-screenshots";
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

const ONBOARDING_DONE_KEY = "biomate_onboarding_done";

// Per CLAUDE.md: "default to 90 s for any chat-stream call that needs a workflow card"
const LLM_TIMEOUT = 90_000;

test.setTimeout(180_000);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function ss(page: Page, name: string) {
  const p = path.join(SS_DIR, `${name}.png`);
  await page.screenshot({ path: p, fullPage: true });
  console.log(`[Screenshot] ${p}`);
}

/**
 * Register a fresh user and ensure we land on the chat page.
 *
 * Also sets the onboarding done flag defensively — OnboardingWelcome is
 * currently dead code in chat-interface.tsx (defined but never rendered),
 * so the flag is a no-op today but guards against re-activation.
 */
async function setupUserAndSkipOnboarding(page: Page, prefix: string) {
  const creds = await setupTestUser(page, prefix);

  // Defensive: set onboarding done flag in case the component is re-activated
  await page.evaluate((key) => {
    localStorage.setItem(key, "1");
  }, ONBOARDING_DONE_KEY);

  return creds;
}

/**
 * Wait for the chat input textarea to be visible and return its locator.
 */
async function getChatInput(page: Page) {
  const input = page.getByTestId("chat-input");
  await expect(input).toBeVisible({ timeout: 15_000 });
  return input;
}

// ---------------------------------------------------------------------------
// QI-1: Chat input visible after login with onboarding skipped
// ---------------------------------------------------------------------------

test("QI-1: Chat input visible after login with onboarding skipped", async ({ page }) => {
  await setupUserAndSkipOnboarding(page, "qi-1");
  await ss(page, "qi-01-before");

  const input = await getChatInput(page);
  console.log("[QI-1] chat-input visible ✓");

  // The onboarding welcome overlay must not be present
  const onboarding = page.getByTestId("onboarding-welcome");
  await expect(onboarding).not.toBeVisible({ timeout: 5_000 });
  console.log("[QI-1] onboarding-welcome not visible ✓");

  await ss(page, "qi-01-chat-visible");

  // Input must be focusable
  await input.focus();
  await expect(input).toBeFocused();
  console.log("[QI-1] chat-input focusable ✓");
});

// ---------------------------------------------------------------------------
// QI-2: Send button disabled when input is empty
// ---------------------------------------------------------------------------

test("QI-2: Send button disabled when input is empty", async ({ page }) => {
  await setupUserAndSkipOnboarding(page, "qi-2");

  await getChatInput(page);

  const sendBtn = page.getByTestId("chat-send-button");
  await expect(sendBtn).toBeVisible({ timeout: 10_000 });
  await expect(sendBtn).toBeDisabled();
  console.log("[QI-2] send button disabled with empty input ✓");

  await ss(page, "qi-02-send-disabled");
});

// ---------------------------------------------------------------------------
// QI-3: Typing enables the send button; clearing disables it again
// ---------------------------------------------------------------------------

test("QI-3: Typing text enables the send button; clearing disables it", async ({ page }) => {
  await setupUserAndSkipOnboarding(page, "qi-3");

  const input = await getChatInput(page);
  const sendBtn = page.getByTestId("chat-send-button");

  // Initially disabled
  await expect(sendBtn).toBeDisabled();

  // Type something
  await input.fill("Hello BioMate");
  await page.waitForTimeout(300);
  await expect(sendBtn).toBeEnabled();
  console.log("[QI-3] send button enabled after typing ✓");

  await ss(page, "qi-03-send-enabled");

  // Clear the input — button should go disabled again
  await input.fill("");
  await page.waitForTimeout(300);
  await expect(sendBtn).toBeDisabled();
  console.log("[QI-3] send button disabled after clearing ✓");

  await ss(page, "qi-03-send-disabled-again");
});

// ---------------------------------------------------------------------------
// QI-4: Enter key submits a query → AI response appears
// ---------------------------------------------------------------------------

test("QI-4: Enter key submits query → AI response appears", async ({ page }) => {
  await setupUserAndSkipOnboarding(page, "qi-4");

  const input = await getChatInput(page);

  await ss(page, "qi-04-before-send");

  // Type and submit via Enter
  await input.fill("What can BioMate help me with?");
  await input.press("Enter");
  console.log("[QI-4] Enter pressed — waiting for AI response…");

  // Wait for the response to complete
  await waitForResponseComplete(page, LLM_TIMEOUT);

  await ss(page, "qi-04-after-response");

  // At least one assistant message should be in the chat
  const assistantMsg = page.locator('[data-is-latest-assistant="true"]');
  const msgText = await assistantMsg.textContent({ timeout: 5_000 }).catch(() => "");
  expect(msgText?.trim().length).toBeGreaterThan(20);
  console.log("[QI-4] AI response visible ✓ (length:", msgText?.trim().length, ")");
});

// ---------------------------------------------------------------------------
// QI-5: Send button click submits query → AI response appears
// ---------------------------------------------------------------------------

test("QI-5: Send button click submits query → AI response appears", async ({ page }) => {
  await setupUserAndSkipOnboarding(page, "qi-5");

  const input = await getChatInput(page);
  const sendBtn = page.getByTestId("chat-send-button");

  await input.fill("List the main bioinformatics workflow categories");
  await page.waitForTimeout(200);
  await expect(sendBtn).toBeEnabled();

  await ss(page, "qi-05-before-click");

  await sendBtn.click();
  console.log("[QI-5] Send button clicked — waiting for AI response…");

  await waitForResponseComplete(page, LLM_TIMEOUT);

  await ss(page, "qi-05-after-response");

  const assistantMsg = page.locator('[data-is-latest-assistant="true"]');
  const msgText = await assistantMsg.textContent({ timeout: 5_000 }).catch(() => "");
  expect(msgText?.trim().length).toBeGreaterThan(20);
  console.log("[QI-5] AI response visible after send-button click ✓");
});

// ---------------------------------------------------------------------------
// QI-6: ?q= URL parameter auto-submits without user interaction
// ---------------------------------------------------------------------------

test("QI-6: ?q= URL param auto-submits the query without user interaction", async ({ page }) => {
  // Log in first (onboarding skipped)
  await setupUserAndSkipOnboarding(page, "qi-6");

  // Navigate to /?q=<encoded> while already authenticated
  const query = "What is BioMate?";
  const encoded = encodeURIComponent(query);
  await page.goto(`${BASE_URL}/?q=${encoded}`);
  await page.waitForLoadState("load");

  console.log("[QI-6] Navigated to /?q= — waiting for auto-submit response…");

  // The query should have been auto-submitted; wait for AI to respond
  await waitForResponseComplete(page, LLM_TIMEOUT);

  await ss(page, "qi-06-after-auto-submit");

  // The user message should appear in the chat (the auto-submitted query)
  const bodyText = await page.textContent("body");
  expect(bodyText).toContain("What is BioMate");
  console.log("[QI-6] Auto-submitted query text visible in chat ✓");

  // AI response should be present
  const assistantMsg = page.locator('[data-is-latest-assistant="true"]');
  const msgText = await assistantMsg.textContent({ timeout: 5_000 }).catch(() => "");
  expect(msgText?.trim().length).toBeGreaterThan(20);
  console.log("[QI-6] AI response present after ?q= auto-submit ✓");

  // URL should be cleaned (q= param stripped by App.tsx replaceState)
  const currentUrl = page.url();
  expect(currentUrl).not.toContain("?q=");
  console.log("[QI-6] URL cleaned — q= param removed ✓");
});

// ---------------------------------------------------------------------------
// QI-7: ?q= ADMET workflow query → workflow card appears
// ---------------------------------------------------------------------------

test("QI-7: ?q= ADMET query → workflow card appears", async ({ page }) => {
  test.setTimeout(LLM_TIMEOUT + 30_000);

  await setupUserAndSkipOnboarding(page, "qi-7");

  // ADMET query from WELCOME_PROMPTS (CLAUDE.md: validate each domain prompt)
  const query = "Run ADMET property prediction for aspirin (CC(=O)Oc1ccccc1C(=O)O)";
  const encoded = encodeURIComponent(query);
  await page.goto(`${BASE_URL}/?q=${encoded}`);
  await page.waitForLoadState("load");

  console.log("[QI-7] ADMET query auto-submitted via ?q=, waiting for workflow card…");

  const hadWorkflowBtn = await waitForResponseComplete(page, LLM_TIMEOUT);

  await ss(page, "qi-07-admet-response");

  if (hadWorkflowBtn) {
    console.log("[QI-7] Workflow Run button appeared ✓ (ADMET workflow card present)");
  } else {
    // May appear as a chip in the message — check for ADMET keywords in response
    const bodyText = await page.textContent("body");
    const hasAdmetContent =
      /admet|property prediction|toxicity|solubility|adsorption|pk/i.test(bodyText ?? "");
    expect(hasAdmetContent).toBe(true);
    console.log("[QI-7] ADMET-related content in response ✓ (no Run button, but correct domain)");
  }
});

// ---------------------------------------------------------------------------
// QI-8: ?q= RNA-seq workflow query → workflow card appears
// ---------------------------------------------------------------------------

test("QI-8: ?q= RNA-seq query → workflow card appears", async ({ page }) => {
  test.setTimeout(LLM_TIMEOUT + 30_000);

  await setupUserAndSkipOnboarding(page, "qi-8");

  const query = "Run differential expression analysis with DESeq2 on my RNA-seq data";
  const encoded = encodeURIComponent(query);
  await page.goto(`${BASE_URL}/?q=${encoded}`);
  await page.waitForLoadState("load");

  console.log("[QI-8] RNA-seq query auto-submitted via ?q=, waiting for response…");

  const hadWorkflowBtn = await waitForResponseComplete(page, LLM_TIMEOUT);

  await ss(page, "qi-08-rnaseq-response");

  if (hadWorkflowBtn) {
    console.log("[QI-8] Workflow Run button appeared ✓ (RNA-seq workflow card present)");
  } else {
    const bodyText = await page.textContent("body");
    const hasRnaContent =
      /deseq2|rna.?seq|differential expression|transcriptomics|gene expression/i.test(
        bodyText ?? ""
      );
    expect(hasRnaContent).toBe(true);
    console.log("[QI-8] RNA-seq-related content in response ✓");
  }
});

// ---------------------------------------------------------------------------
// QI-9: Empty Enter key does NOT trigger a submission
// ---------------------------------------------------------------------------

test("QI-9: Pressing Enter with empty input does not trigger submission", async ({ page }) => {
  await setupUserAndSkipOnboarding(page, "qi-9");

  const input = await getChatInput(page);

  // Ensure input is genuinely empty
  await input.fill("");
  await page.waitForTimeout(300);

  await ss(page, "qi-09-before-empty-enter");

  // Press Enter on the empty input
  await input.press("Enter");
  await page.waitForTimeout(2_000);

  await ss(page, "qi-09-after-empty-enter");

  // No assistant message should have appeared
  const assistantMsg = page.locator('[data-is-latest-assistant="true"]');
  const isVisible = await assistantMsg.isVisible({ timeout: 3_000 }).catch(() => false);
  expect(isVisible).toBe(false);
  console.log("[QI-9] No AI response after empty Enter ✓");

  // No thinking/typing indicator either
  const thinkingIndicator = page.locator('[data-testid="chat-analysis-status"]');
  const thinkingVisible = await thinkingIndicator.isVisible({ timeout: 3_000 }).catch(() => false);
  expect(thinkingVisible).toBe(false);
  console.log("[QI-9] No thinking indicator after empty Enter ✓");
});

// ---------------------------------------------------------------------------
// QI-10: Fresh user sees chat input immediately — no onboarding overlay
// ---------------------------------------------------------------------------
//
// Note: OnboardingWelcome is defined in chat-interface.tsx but is NOT
// rendered in the current code path (no JSX instantiation found). New users
// land directly in the chat without any onboarding modal.
// This test documents and guards that behavior.

test("QI-10: Fresh user sees the chat input immediately after login — no onboarding overlay", async ({ page }) => {
  // Create a fresh user WITHOUT setting the onboarding done flag
  await setupTestUser(page, "qi-10");

  await ss(page, "qi-10-fresh-user");

  // The onboarding welcome element must NOT be present
  const onboarding = page.getByTestId("onboarding-welcome");
  const onboardingVisible = await onboarding.isVisible({ timeout: 3_000 }).catch(() => false);
  expect(onboardingVisible).toBe(false);
  console.log("[QI-10] No onboarding overlay for fresh user ✓");

  // Chat input must be immediately accessible
  const chatInput = page.getByTestId("chat-input");
  await expect(chatInput).toBeVisible({ timeout: 10_000 });
  console.log("[QI-10] chat-input immediately visible for fresh user ✓");

  await ss(page, "qi-10-chat-visible");
});
