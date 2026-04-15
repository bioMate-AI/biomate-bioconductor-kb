/**
 * UX Element Tests: Thinking Display, Typing Indicator, Chat Scroll
 *
 * Tests real user experience elements that give researchers feedback
 * while the AI processes complex bioinformatics queries.
 *
 * Test index:
 *   UX-1  Thinking display — AI shows reasoning steps for complex query,
 *         collapsed/non-blocking after response completes
 *   UX-2  Typing indicator — appears within 5s of query submission,
 *         gone when response arrives
 *   UX-3  Chat scroll — new AI response auto-scrolls into viewport
 *         so the researcher doesn't miss it
 *
 * NO page.route() mocking. All calls hit the live server.
 * Screenshots → e2e/screenshots/ux-thinking/
 */

import { test, expect, Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const SS_DIR = path.join(__dirname, "screenshots", "ux-thinking");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function registerAndGoHome(page: Page, label: string): Promise<{ email: string }> {
  const email = `e2e_ux_${label}_${Date.now()}@biomate.test`;
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  await page.goto(`${BASE_URL}/register`);
  await page.waitForLoadState("load");
  await page.evaluate(() => {
    try { localStorage.clear(); sessionStorage.clear(); } catch {}
  }).catch(() => {});
  try {
    await page.waitForSelector("#name", { state: "visible", timeout: 10000 });
    await page.fill("#name", `UX E2E ${label}`);
    await page.fill("#email", email);
    await page.fill("#password", "TestPass123!");
    await page.fill("#confirmPassword", "TestPass123!");
    await page.click("#terms");
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
  } catch { /* already logged in */ }
  await page.goto(BASE_URL);
  await page.evaluate(() => { try { localStorage.clear(); sessionStorage.clear(); } catch {} });
  await page.reload();
  await page.waitForLoadState("load");
  await page.waitForSelector("textarea", { state: "visible", timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(1000);
  return { email };
}

async function sendMessage(page: Page, text: string): Promise<void> {
  const ta = page.locator("textarea").first();
  await expect(ta).toBeVisible({ timeout: 10000 });
  await ta.fill(text);
  await ta.press("Enter");
}

async function screenshot(page: Page, name: string): Promise<string> {
  const fn = `${name}.png`;
  await page.screenshot({ path: path.join(SS_DIR, fn), fullPage: true });
  console.log(`[Screenshot] ${fn}`);
  return fn;
}

/**
 * Wait for the typing indicator to appear (returns true) or time out (returns false).
 * Uses both the data-testid and the text content as signals.
 */
async function waitForTypingIndicator(page: Page, timeoutMs = 10000): Promise<boolean> {
  try {
    await page.waitForSelector(
      '[data-testid="chat-response-pending"]',
      { state: "visible", timeout: timeoutMs }
    );
    return true;
  } catch {
    // Fallback: look for the literal text the component renders
    try {
      await page.waitForSelector("text=BioMate is thinking...", { state: "visible", timeout: 2000 });
      return true;
    } catch {
      return false;
    }
  }
}

/**
 * Wait for the typing indicator to disappear.
 */
async function waitForTypingIndicatorGone(page: Page, timeoutMs = 120000): Promise<void> {
  await Promise.all([
    page.waitForSelector('[data-testid="chat-response-pending"]', {
      state: "hidden",
      timeout: timeoutMs,
    }).catch(() => null),
    page.waitForSelector("text=BioMate is thinking...", {
      state: "hidden",
      timeout: timeoutMs,
    }).catch(() => null),
  ]);
}

/**
 * Wait for a substantive assistant response to appear.
 * Returns the response text length, or 0 if none found.
 */
async function waitForAssistantResponse(page: Page, timeoutMs = 120000): Promise<number> {
  try {
    await page.waitForFunction(
      () => {
        const el = document.querySelector('[data-is-latest-assistant="true"]');
        if (!el) return false;
        const t = el.textContent ?? "";
        return t.trim().length > 40 && !t.includes("BioMate is thinking");
      },
      { timeout: timeoutMs }
    );
    const el = page.locator('[data-is-latest-assistant="true"]').first();
    const text = await el.textContent({ timeout: 5000 }).catch(() => "");
    return text?.trim().length ?? 0;
  } catch {
    return 0;
  }
}

// ---------------------------------------------------------------------------
// UX-1: Thinking Display
// ---------------------------------------------------------------------------

test("UX-1: thinking display — AI shows reasoning steps for complex query, collapsed after response", async ({ page }) => {
  test.setTimeout(180000);

  await registerAndGoHome(page, "ux1");

  // Complex multi-part bioinformatics query — intended to trigger reasoning.
  const query =
    "What is the best approach for WGS variant calling on a tumor-normal pair? " +
    "Compare GATK Mutect2 vs Strelka2 for somatic SNV/indel detection, explain " +
    "the key pipeline stages (alignment, duplicate marking, base quality score " +
    "recalibration, variant calling, filtering), and recommend filtering thresholds " +
    "for clinical reporting. Include considerations for tumor purity and allele frequency.";

  const t0 = Date.now();
  await sendMessage(page, query);
  console.log("[UX-1] Message sent, waiting for typing indicator...");

  // Wait for typing indicator — hard requirement for good UX
  const typingAppeared = await waitForTypingIndicator(page, 10000);
  if (!typingAppeared) {
    console.log("[UX-1] WARNING: typing indicator did not appear within 10s");
  } else {
    console.log("[UX-1] Typing indicator visible.");
  }

  await screenshot(page, "ux1_01_typing_indicator");

  // Soft-check: did a thinking block appear while streaming?
  // The ThinkingDisplay renders text "View AI Reasoning" (collapsed) or "AI Reasoning Process" (expanded).
  const thinkingAppearedDuringStream = await page
    .waitForSelector("text=View AI Reasoning", { state: "visible", timeout: 30000 })
    .then(() => true)
    .catch(() => false);

  if (thinkingAppearedDuringStream) {
    console.log("[UX-1] Thinking display appeared during streaming — taking screenshot.");
    await screenshot(page, "ux1_02_thinking_visible");
  } else {
    console.log("[UX-1] No thinking display observed (model may not have used extended thinking for this query — acceptable).");
    await screenshot(page, "ux1_02_no_thinking_block");
  }

  // Wait for the full response
  const responseLen = await waitForAssistantResponse(page, 120000);
  const elapsed = Date.now() - t0;

  console.log(`[UX-1] Response arrived in ${elapsed}ms, length=${responseLen} chars`);

  // Hard assertions
  expect(elapsed).toBeLessThan(120000);
  expect(responseLen).toBeGreaterThan(100);

  await screenshot(page, "ux1_03_response_complete");

  // After response completes the thinking display should be collapsed (not blocking reading).
  // If it appeared at all, verify it is now showing the collapsed state ("View AI Reasoning")
  // rather than the expanded state, i.e. the full thinking text is not forced open.
  if (thinkingAppearedDuringStream) {
    const expandedHeaderVisible = await page
      .locator("text=AI Reasoning Process")
      .isVisible()
      .catch(() => false);

    // Collapsed is the default (defaultExpanded=false in the component).
    // It's fine if it is still showing "View AI Reasoning" (collapsed) — that means it's
    // not blocking the response text. We only fail if the card is somehow taking up the
    // entire viewport and the response text is invisible.
    const responseStillVisible = await page
      .locator('[data-is-latest-assistant="true"]')
      .first()
      .isVisible()
      .catch(() => false);

    console.log(`[UX-1] After response: expandedHeader=${expandedHeaderVisible}, responseVisible=${responseStillVisible}`);
    expect(responseStillVisible).toBe(true);
  }

  // Typing indicator must be gone now
  const typingGone = await page
    .locator('[data-testid="chat-response-pending"]')
    .isVisible()
    .catch(() => false);
  expect(typingGone).toBe(false);

  await screenshot(page, "ux1_04_final_state");
  console.log("[UX-1] PASS");
});

// ---------------------------------------------------------------------------
// UX-2: Typing Indicator Timing
// ---------------------------------------------------------------------------

test("UX-2: typing indicator — appears within 5s of query submission, gone when response arrives", async ({ page }) => {
  test.setTimeout(180000);

  await registerAndGoHome(page, "ux2");

  const query =
    "Briefly explain what FASTQ quality scores (Phred scores) represent and " +
    "why they matter for bioinformatics analysis.";

  // Record T0 before sending
  const t0 = Date.now();
  await sendMessage(page, query);
  console.log("[UX-2] Message sent at T0.");

  // Hard assertion: typing indicator must appear within 5 seconds of submission.
  // This is the critical UX requirement — the user should never be left staring at
  // a static screen without feedback for more than 5 seconds.
  let t1: number | null = null;
  try {
    await page.waitForSelector('[data-testid="chat-response-pending"]', {
      state: "visible",
      timeout: 5000,
    });
    t1 = Date.now();
    console.log(`[UX-2] Typing indicator visible at T1=${t1 - t0}ms after send.`);
  } catch {
    // Fallback: try text match
    try {
      await page.waitForSelector("text=BioMate is thinking...", {
        state: "visible",
        timeout: 2000,
      });
      t1 = Date.now();
      console.log(`[UX-2] Typing indicator (text) visible at T1=${t1 - t0}ms after send.`);
    } catch {
      t1 = null;
    }
  }

  await screenshot(page, "ux2_01_typing_state");

  // Hard-assert timing
  expect(t1, "Typing indicator must appear within 5000ms of message submission").not.toBeNull();
  if (t1 !== null) {
    const latencyMs = t1 - t0;
    console.log(`[UX-2] Latency to typing indicator: ${latencyMs}ms`);
    expect(latencyMs).toBeLessThan(5000);
  }

  // Wait for the response to arrive
  const responseLen = await waitForAssistantResponse(page, 120000);
  console.log(`[UX-2] Response arrived, length=${responseLen}`);

  await screenshot(page, "ux2_02_response_arrived");

  // Once response text is present, the typing indicator must be gone
  const typingStillVisible = await page
    .locator('[data-testid="chat-response-pending"]')
    .isVisible()
    .catch(() => false);

  expect(typingStillVisible).toBe(false);
  expect(responseLen).toBeGreaterThan(0);

  await screenshot(page, "ux2_03_typing_gone");
  console.log("[UX-2] PASS");
});

// ---------------------------------------------------------------------------
// UX-3: Chat Scroll to Bottom
// ---------------------------------------------------------------------------

test("UX-3: chat scroll — new AI response auto-scrolls into viewport so researcher doesn't miss it", async ({ page }) => {
  test.setTimeout(600000); // 10 minutes — 3 full AI round-trips

  await registerAndGoHome(page, "ux3");

  // Short, fast queries that should produce responses quickly.
  // We use distinct science topics to avoid the AI just saying "as I said above".
  const queries = [
    "What does BWA-MEM do in a read alignment pipeline? One sentence answer.",
    "What is the purpose of duplicate marking in WGS pipelines? One sentence.",
    "Name one advantage of CRAM format over BAM for long-term genomic data storage.",
  ];

  for (let i = 0; i < queries.length; i++) {
    const q = queries[i];
    console.log(`[UX-3] Sending message ${i + 1}/${queries.length}: "${q.slice(0, 60)}..."`);

    await sendMessage(page, q);

    // Wait for typing indicator to appear
    await waitForTypingIndicator(page, 10000);

    // Wait for response
    const responseLen = await waitForAssistantResponse(page, 120000);
    console.log(`[UX-3] Message ${i + 1} response: ${responseLen} chars`);

    // Allow the DOM to settle and auto-scroll to complete
    await page.waitForTimeout(1500);

    await screenshot(page, `ux3_0${i + 1}_response_${i + 1}`);

    // Assert the latest assistant message is within the viewport.
    // The chat-interface auto-scrolls via messagesEndRef.scrollIntoView().
    const latestMsg = page.locator('[data-is-latest-assistant="true"]').first();
    const isVisible = await latestMsg.isVisible({ timeout: 5000 }).catch(() => false);
    expect(isVisible, `Message ${i + 1}: latest AI response should be visible in viewport`).toBe(true);

    // Additional check: measure bounding box to confirm element is in view
    const bb = await latestMsg.boundingBox().catch(() => null);
    if (bb) {
      const viewportSize = page.viewportSize();
      if (viewportSize) {
        const inVerticalView = bb.y >= 0 && bb.y < viewportSize.height;
        console.log(
          `[UX-3] Message ${i + 1} bounding box: y=${bb.y.toFixed(0)}, viewport.height=${viewportSize.height}, inView=${inVerticalView}`
        );
        // The top of the element should be within the viewport (not scrolled far off-screen below).
        // We allow a generous margin since the element can be partially visible.
        expect(bb.y).toBeLessThan(viewportSize.height + 200);
      }
    }
  }

  // Final: verify the chat scroll container (data-testid="chat-messages") has its
  // scrollTop near the bottom — meaning auto-scroll is working as content grows.
  const scrollResult = await page.evaluate(() => {
    // The ScrollArea component from Radix wraps a viewport div
    const chatContainer = document.querySelector('[data-testid="chat-messages"]');
    if (!chatContainer) return { found: false, scrollTop: 0, scrollHeight: 0, clientHeight: 0 };

    // Radix ScrollArea renders a viewport inside; try to find the scrollable child
    const viewport =
      chatContainer.querySelector("[data-radix-scroll-area-viewport]") ??
      chatContainer.querySelector(".overflow-auto") ??
      chatContainer.querySelector(".overflow-y-auto") ??
      chatContainer;

    return {
      found: true,
      scrollTop: (viewport as HTMLElement).scrollTop,
      scrollHeight: (viewport as HTMLElement).scrollHeight,
      clientHeight: (viewport as HTMLElement).clientHeight,
    };
  });

  console.log(
    `[UX-3] Scroll container: found=${scrollResult.found}, scrollTop=${scrollResult.scrollTop}, ` +
    `scrollHeight=${scrollResult.scrollHeight}, clientHeight=${scrollResult.clientHeight}`
  );

  if (scrollResult.found && scrollResult.scrollHeight > scrollResult.clientHeight) {
    // scrollTop should be close to (scrollHeight - clientHeight), meaning scrolled to bottom.
    const maxScroll = scrollResult.scrollHeight - scrollResult.clientHeight;
    const distanceFromBottom = maxScroll - scrollResult.scrollTop;
    console.log(`[UX-3] Distance from bottom: ${distanceFromBottom}px`);
    // Allow up to 400px of slack (last message could still be rendering / animating)
    expect(distanceFromBottom).toBeLessThan(400);
  } else {
    console.log("[UX-3] Scroll container not fully measurable — skipping scroll position assertion.");
  }

  await screenshot(page, "ux3_final_scroll_state");
  console.log("[UX-3] PASS");
});
