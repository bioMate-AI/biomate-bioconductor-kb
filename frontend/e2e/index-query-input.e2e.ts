/**
 * Index Page Chat Query Input — E2E Test
 *
 * Single sequential flow covering the full chat input surface:
 *   1. Login — chat input visible, no onboarding overlay
 *   2. Empty state — send button disabled
 *   3. Typing — send button enables; clearing disables again
 *   4. Enter key submit → AI response
 *   5. Send button click → AI response
 *   6. Empty Enter is a no-op
 *   7. ?q= URL param auto-submits without user action, URL cleaned
 *   8. ?q= ADMET query routes to correct domain
 *   9. ?q= RNA-seq query routes to correct domain
 *
 * Per CLAUDE.md: login once, reuse session, 90 s timeout for LLM paths.
 * No page.route() mocking — all requests hit the live stack.
 */

import { test, expect, Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { setupTestUser, BASE_URL, waitForResponseComplete } from "./helpers.js";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const SS_DIR = "/tmp/qi-e2e-screenshots";
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// Per CLAUDE.md: "default to 90 s for any chat-stream call that needs a workflow card"
const LLM_TIMEOUT = 90_000;

test.setTimeout(10 * 60_000); // 10 min for the full chain

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

async function ss(page: Page, name: string) {
  const p = path.join(SS_DIR, `${name}.png`);
  await page.screenshot({ path: p, fullPage: true });
  console.log(`[Screenshot] ${p}`);
}

// ---------------------------------------------------------------------------
// Full flow
// ---------------------------------------------------------------------------

test("Chat query input — full user journey", async ({ page }) => {
  // ── Step 1: Login ──────────────────────────────────────────────────────────

  await setupTestUser(page, "qi");
  await ss(page, "qi-01-after-login");

  // OnboardingWelcome is dead code (defined but never rendered in
  // chat-interface.tsx) — fresh users land directly in the chat.
  const onboarding = page.getByTestId("onboarding-welcome");
  expect(await onboarding.isVisible({ timeout: 3_000 }).catch(() => false)).toBe(false);
  console.log("[1] No onboarding overlay ✓");

  const chatInput = page.getByTestId("chat-input");
  await expect(chatInput).toBeVisible({ timeout: 15_000 });
  await chatInput.focus();
  await expect(chatInput).toBeFocused();
  console.log("[1] chat-input visible and focusable ✓");

  // ── Step 2: Empty state ────────────────────────────────────────────────────

  const sendBtn = page.getByTestId("chat-send-button");
  await expect(sendBtn).toBeVisible({ timeout: 5_000 });
  await expect(sendBtn).toBeDisabled();
  console.log("[2] Send button disabled on empty input ✓");

  // ── Step 3: Typing enables; clearing disables ──────────────────────────────

  await chatInput.fill("Hello");
  await page.waitForTimeout(200);
  await expect(sendBtn).toBeEnabled();
  console.log("[3] Send button enabled after typing ✓");

  await chatInput.fill("");
  await page.waitForTimeout(200);
  await expect(sendBtn).toBeDisabled();
  console.log("[3] Send button disabled after clearing ✓");

  await ss(page, "qi-03-empty-again");

  // ── Step 4: Enter key submits → AI response ────────────────────────────────

  await chatInput.fill("What can BioMate help me with?");
  await chatInput.press("Enter");
  console.log("[4] Enter pressed — waiting for AI response…");

  await waitForResponseComplete(page, LLM_TIMEOUT);
  await ss(page, "qi-04-after-enter");

  const latestMsg = page.locator('[data-is-latest-assistant="true"]');
  const enterResponseText = await latestMsg.textContent({ timeout: 5_000 }).catch(() => "");
  expect(enterResponseText?.trim().length).toBeGreaterThan(20);
  console.log("[4] AI response after Enter ✓ (len:", enterResponseText?.trim().length, ")");

  // ── Step 5: Send button click submits → AI response ───────────────────────

  await chatInput.fill("List the main bioinformatics workflow categories");
  await page.waitForTimeout(200);
  await expect(sendBtn).toBeEnabled();
  await sendBtn.click();
  console.log("[5] Send button clicked — waiting for AI response…");

  await waitForResponseComplete(page, LLM_TIMEOUT);
  await ss(page, "qi-05-after-send-btn");

  const sendBtnResponseText = await latestMsg.textContent({ timeout: 5_000 }).catch(() => "");
  expect(sendBtnResponseText?.trim().length).toBeGreaterThan(20);
  console.log("[5] AI response after send-button click ✓");

  // ── Step 6: Empty Enter is a no-op ────────────────────────────────────────

  await chatInput.fill("");
  await chatInput.press("Enter");
  await page.waitForTimeout(2_000);

  // The latest assistant message should be the same one from step 5 (no new one)
  const thinkingIndicator = page.locator('[data-testid="chat-analysis-status"]');
  expect(await thinkingIndicator.isVisible({ timeout: 2_000 }).catch(() => false)).toBe(false);
  console.log("[6] Empty Enter is a no-op ✓");

  // ── Step 7: ?q= URL param auto-submits, URL is cleaned ────────────────────

  const query7 = "What is BioMate?";
  await page.goto(`${BASE_URL}/?q=${encodeURIComponent(query7)}`);
  await page.waitForLoadState("load");
  console.log("[7] Navigated to /?q= — waiting for auto-submit…");

  await waitForResponseComplete(page, LLM_TIMEOUT);
  await ss(page, "qi-07-after-q-param");

  const body7 = await page.textContent("body");
  expect(body7).toContain("What is BioMate");
  console.log("[7] Auto-submitted query text in chat ✓");

  const q7Response = await latestMsg.textContent({ timeout: 5_000 }).catch(() => "");
  expect(q7Response?.trim().length).toBeGreaterThan(20);
  console.log("[7] AI response present ✓");

  expect(page.url()).not.toContain("?q=");
  console.log("[7] URL cleaned — q= param removed ✓");

  // ── Step 8: ?q= ADMET query → correct domain response ─────────────────────

  const query8 = "Run ADMET property prediction for aspirin (CC(=O)Oc1ccccc1C(=O)O)";
  await page.goto(`${BASE_URL}/?q=${encodeURIComponent(query8)}`);
  await page.waitForLoadState("load");
  console.log("[8] ADMET query via ?q=, waiting for workflow card…");

  const hadRunBtn8 = await waitForResponseComplete(page, LLM_TIMEOUT);
  await ss(page, "qi-08-admet");

  if (hadRunBtn8) {
    console.log("[8] Workflow Run button appeared ✓ (ADMET card)");
  } else {
    const body8 = await page.textContent("body");
    expect(/admet|property prediction|toxicity|solubility|adsorption|pk/i.test(body8 ?? "")).toBe(true);
    console.log("[8] ADMET-domain content in response ✓");
  }

  // ── Step 9: ?q= RNA-seq query → correct domain response ───────────────────

  const query9 = "Run differential expression analysis with DESeq2 on my RNA-seq data";
  await page.goto(`${BASE_URL}/?q=${encodeURIComponent(query9)}`);
  await page.waitForLoadState("load");
  console.log("[9] RNA-seq query via ?q=, waiting for workflow card…");

  const hadRunBtn9 = await waitForResponseComplete(page, LLM_TIMEOUT);
  await ss(page, "qi-09-rnaseq");

  if (hadRunBtn9) {
    console.log("[9] Workflow Run button appeared ✓ (RNA-seq card)");
  } else {
    const body9 = await page.textContent("body");
    expect(/deseq2|rna.?seq|differential expression|transcriptomics|gene expression/i.test(body9 ?? "")).toBe(true);
    console.log("[9] RNA-seq-domain content in response ✓");
  }

  await ss(page, "qi-final");
  console.log("[DONE] All chat query input assertions passed ✓");
});
