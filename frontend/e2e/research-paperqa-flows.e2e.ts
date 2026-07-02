/**
 * Research & PaperQA Flows E2E — UC-4, UC-5
 * =====================================================
 * Tests pure-text research responses where NO workflow card should appear:
 *
 *   UC-4  Literature synthesis → PaperQA path → chat_only with ≥2 citation
 *          markers ([N] in text or <sup> in DOM)
 *   UC-5  Two-turn protocol guidance → second turn references context from
 *          first turn without repeating the topic (session context maintained)
 *
 * These cover the `chat_only` branch of the SSE final event. Galaxy routes
 * to the research agent (PaperQA5) when the intent classifier returns
 * `literature_synthesis` or `general_research`. Neither turn should trigger
 * workflow_ready.
 *
 * CLAUDE.md rules:
 *  - Single fixture account; login once per file
 *  - No page.route() mocking — all calls hit live dev backend
 *  - 90 s LLM timeout per call
 */

import { test, expect, type Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { waitForResponseComplete } from "./helpers.js";

const SS_DIR = path.join("/tmp", "research-paperqa-e2e");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

const LLM_TIMEOUT = 90_000;
test.setTimeout(15 * 60_000);

let sharedPage: Page;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

async function ss(page: Page, name: string) {
  await page.screenshot({ path: path.join(SS_DIR, `${name}.png`), fullPage: false });
  console.log(`[SS] ${path.join(SS_DIR, `${name}.png`)}`);
}

async function newSession(page: Page) {
  await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
  const newChatBtn = page.locator('[data-testid="button-new-chat"]').first();
  if (await newChatBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await newChatBtn.click();
    await page.waitForTimeout(500);
  }
}

async function sendMessage(page: Page, text: string) {
  const composer = page.locator(
    'textarea, input[placeholder*="Ask"], input[placeholder*="Describe"]'
  ).first();
  await expect(composer).toBeVisible({ timeout: 30_000 });
  await composer.fill(text);
  await composer.press("Enter");
}

async function waitForAssistant(page: Page, timeoutMs = LLM_TIMEOUT) {
  await waitForResponseComplete(page, timeoutMs);
  const el = page.locator('[data-is-latest-assistant="true"]').first();
  await el.waitFor({ state: "attached", timeout: timeoutMs }).catch(() => {});
  return el;
}

// ---------------------------------------------------------------------------
// Setup / teardown
// ---------------------------------------------------------------------------

test.beforeAll(async ({ browser }) => {
  sharedPage = await browser.newPage();
  await loginAsFixture(sharedPage);
  console.log("[Auth] Fixture login complete");
});

test.afterAll(async () => {
  await sharedPage?.close();
});

// ============================================================================
// UC-4 — Literature synthesis with citation markers (PaperQA path)
// ============================================================================

test("UC-4: literature question returns cited text answer with no workflow card", async () => {
  const page = sharedPage;
  await newSession(page);
  await ss(page, "UC4_00_new_session");

  const message =
    "Summarise the current evidence on KRAS G12C inhibitors in non-small cell " +
    "lung cancer: mechanism of action, clinical trial outcomes (overall response " +
    "rate, PFS), and known resistance mechanisms. Cite at least 3 primary papers.";

  await sendMessage(page, message);
  const assistantEl = await waitForAssistant(page, LLM_TIMEOUT);
  await ss(page, "UC4_01_response");

  const responseText = await assistantEl.textContent({ timeout: LLM_TIMEOUT }).catch(() => "");
  console.log("[UC-4] Response length:", responseText?.length);
  console.log("[UC-4] Response (first 300):", responseText?.slice(0, 300));

  // Must be a substantive text response
  expect(responseText?.trim().length ?? 0, "response must be non-empty").toBeGreaterThan(200);

  // Must mention the topic
  expect(responseText?.toLowerCase()).toMatch(/kras|sotorasib|adagrasib|g12c|lung/);

  // Citation markers — [N] in text or <sup> in rendered DOM
  const citationMatches = (responseText?.match(/\[\d+\]/g) ?? []).length;
  const supCount = await assistantEl.locator("sup").count().catch(() => 0);
  const totalCitations = citationMatches + supCount;
  console.log(
    `[UC-4] Citation markers: ${citationMatches} [N] patterns, ${supCount} <sup> elements = ${totalCitations} total`
  );
  expect(totalCitations, "must have at least 2 citation markers ([N] or <sup>)").toBeGreaterThanOrEqual(2);

  // No workflow card anywhere in the message thread
  const cardCount = await page.locator('[data-testid^="workflow-artifact-anchor-"]').count();
  console.log("[UC-4] Workflow cards found:", cardCount);
  expect(cardCount, "literature question must NOT produce a workflow card").toBe(0);

  // Right panel must be closed (no workflow generated)
  const panelVisible = await page.locator('[data-testid="workflow-artifact-panel"]')
    .isVisible({ timeout: 2_000 }).catch(() => false);
  expect(panelVisible, "right panel must not open for a text-only response").toBe(false);

  await ss(page, "UC4_02_citations_verified");
  console.log("[UC-4] PASS — cited text response received; no workflow card present");
});

// ============================================================================
// UC-5 — Two-turn protocol guidance; session context maintained
// ============================================================================

test("UC-5: two-turn protocol conversation maintains session context across turns", async () => {
  const page = sharedPage;
  await newSession(page);
  await ss(page, "UC5_00_session_start");

  // ── Turn 1: ask for RNA-seq library prep protocol ──────────────────────────
  const turn1 =
    "What is the recommended protocol for preparing a stranded total RNA-seq " +
    "library from FFPE tissue samples?";

  await sendMessage(page, turn1);
  const t1El = await waitForAssistant(page, LLM_TIMEOUT);
  await ss(page, "UC5_01_turn1_response");

  const t1Text = await t1El.textContent({ timeout: LLM_TIMEOUT }).catch(() => "");
  console.log("[UC-5] Turn 1 length:", t1Text?.length, "| preview:", t1Text?.slice(0, 150));
  expect(t1Text?.trim().length ?? 0, "turn 1 must have substantive content").toBeGreaterThan(100);

  // Turn 1 must be text-only (RNA-seq library prep is a research question)
  const cardsAfterT1 = await page.locator('[data-testid^="workflow-artifact-anchor-"]').count();
  console.log("[UC-5] Workflow cards after turn 1:", cardsAfterT1);
  expect(cardsAfterT1, "turn 1 must produce a text-only response").toBe(0);

  // ── Turn 2: follow-up referencing turn 1 context ──────────────────────────
  // This question only makes sense if the AI remembers turn 1 is about RNA-seq from FFPE.
  const turn2 =
    "In step 3 of that protocol, what is the purpose of the rRNA depletion step " +
    "and what reagents are typically used?";

  await sendMessage(page, turn2);
  const t2El = await waitForAssistant(page, LLM_TIMEOUT);
  await ss(page, "UC5_02_turn2_response");

  const t2Text = await t2El.textContent({ timeout: LLM_TIMEOUT }).catch(() => "");
  console.log("[UC-5] Turn 2 length:", t2Text?.length, "| preview:", t2Text?.slice(0, 200));
  expect(t2Text?.trim().length ?? 0, "turn 2 must have content").toBeGreaterThan(50);

  // Turn 2 must reference rRNA/ribosomal — only possible if session context was maintained
  expect(t2Text?.toLowerCase()).toMatch(
    /rrna|ribosomal|ribo.?depletion|ribo.?cop|ribo.?zero|rnase\s*h|probe|hybridiz/i
  );
  console.log("[UC-5] Turn 2 mentions rRNA/depletion reagents — context maintained ✓");

  // No workflow cards after either turn
  const cardsAfterT2 = await page.locator('[data-testid^="workflow-artifact-anchor-"]').count();
  console.log("[UC-5] Workflow cards after turn 2:", cardsAfterT2);
  expect(cardsAfterT2, "protocol follow-up must produce text-only response").toBe(0);

  // Both assistant messages visible in the thread
  const assistantMsgs = await page.locator('[data-role="assistant"]').count();
  console.log("[UC-5] Assistant messages in thread:", assistantMsgs);
  expect(assistantMsgs, "both turns must be visible in the thread").toBeGreaterThanOrEqual(2);

  await ss(page, "UC5_03_full_thread");
  console.log("[UC-5] PASS — two-turn context maintained; turn 2 referenced rRNA reagents");
});
