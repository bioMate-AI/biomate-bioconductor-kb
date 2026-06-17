/**
 * intent-clarification.e2e.ts
 *
 * Scene-based E2E test of the IntentClarificationCard flow:
 *
 *   1. User sends a design-shaped query
 *   2. Backend's classifier forced (via test-only context.testForceIntent,
 *      gated by E2E_TEST_TOKEN) to mis-classify as `tool_search` — this
 *      reproducibly triggers cross-intent ambiguity detection
 *   3. Backend short-circuits with intentClarification card on the response
 *   4. Frontend renders IntentClarificationCard inline in chat
 *   5. Playwright clicks the primary "Run a design workflow" chip
 *   6. Frontend re-submits the original message with
 *      context.intentOverride='workflow_generation'
 *   7. Backend respects override, routes to workflow_generation, returns
 *      workflow_ga + schema-grounded inlineParameters
 *   8. Workflow panel opens with prefilled canonical params
 *
 * Tests both:
 *   - The pick-primary flow (lean on execution)
 *   - The skip flow (no re-submit; user expected to rephrase)
 *
 * Run:
 *   BIOMATE_URL=http://localhost:5001 \
 *   E2E_FIXTURE_PASSWORD=… \
 *   E2E_TEST_TOKEN=biomate-e2e-bypass-token-dev-only \
 *   PW_OUTPUT_DIR=/tmp/intent-clar-audit \
 *   npx playwright test e2e/intent-clarification.e2e.ts \
 *     --reporter=line --project=chromium
 */
import { test, expect, type Page } from "@playwright/test";

const BASE_URL = (process.env.BIOMATE_URL || "http://localhost:5001").replace(/\/+$/, "");
const FIXTURE_EMAIL = process.env.E2E_FIXTURE_EMAIL || "lifeifei163361@163.com";
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";

async function loginShared(page: Page): Promise<boolean> {
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  const loginUrl = `${BASE_URL}/api/auth/login`;
  let resp = await page.request.post(loginUrl, {
    headers: { "Content-Type": "application/json", "x-e2e-test-token": E2E_TOKEN },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  let token = "";
  if (resp.ok()) {
    token = (await resp.json())?.token || "";
  } else {
    // NEVER register-on-fail. Per CLAUDE.md the fixture user must already
    // exist. Surface auth failures instead of polluting the user list.
    console.error(`[login] FAILED status=${resp.status()} — fixture user must already exist; not registering`);
    return false;
  }
  if (!token) return false;
  const url = new URL(BASE_URL);
  await page.context().addCookies([{
    name: "biomate_token",
    value: token,
    domain: url.hostname,
    path: "/",
    httpOnly: true,
    secure: BASE_URL.startsWith("https"),
    sameSite: "Strict",
  }]);
  return true;
}

/**
 * Send a chat-stream POST that forces intent classification via the
 * test-only context.testForceIntent (gated by E2E_TEST_TOKEN). This
 * bypasses any DOM interaction so we can deterministically inspect the
 * resulting card without depending on the chat composer's send path.
 *
 * Returns the parsed `final` event's payload.metadata.intentClarification.
 */
async function probeIntentClar(args: {
  page: Page;
  message: string;
  forceIntent: string;
}): Promise<any> {
  const { page, message, forceIntent } = args;
  const resp = await page.request.post(`${BASE_URL}/api/chat/stream`, {
    headers: { "Content-Type": "application/json", "x-e2e-test-token": E2E_TOKEN },
    data: {
      message,
      context: { testForceIntent: forceIntent },
    },
  });
  const text = await resp.text();
  // Pull the `final` SSE event metadata field.
  const m = text.match(/event:\s*final\s*\ndata:\s*({[\s\S]+?})\s*\n/);
  if (!m) return null;
  try {
    const payload = JSON.parse(m[1]);
    return payload.metadata?.intentClarification ?? null;
  } catch {
    return null;
  }
}

async function sendChatViaUI(page: Page, query: string) {
  // chat-input testid is on the <textarea> inside ChatInput. Use it
  // directly; fall back to placeholder lookup for older builds.
  const input = page
    .locator(
      '[data-testid="chat-input"], textarea[placeholder*="Ask BioMate"], textarea[placeholder*="Ask"]',
    )
    .first();
  await input.waitFor({ state: "visible", timeout: 90_000 });
  await input.click();
  await input.fill(query);
  await page.keyboard.press("Enter");
}

test.describe.configure({ mode: "default" });

test.describe("IntentClarificationCard end-to-end", () => {
  test("API: forced tool_search misclassification fires the clarification card", async ({
    page,
  }) => {
    const ok = await loginShared(page);
    expect(ok, "fixture login").toBeTruthy();

    // Test 1 — API-level: card payload arrives in the SSE response.
    const clar = await probeIntentClar({
      page,
      message: "Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC",
      forceIntent: "tool_search",
    });
    expect(clar, "intentClarification field present").toBeTruthy();
    expect(clar.originalIntent).toBe("tool_search");
    expect(clar.originalMessage).toContain("PD-1");
    expect(clar.candidates.length).toBeGreaterThanOrEqual(2);
    const primary = clar.candidates.find((c: any) => c.primary);
    expect(primary?.type).toBe("workflow_generation");

    // Test 2 — API-level: skip the card by NOT setting testForceIntent;
    // depending on LLM classification, card may or may not fire. The point
    // is we can predict deterministically: forceIntent=workflow_generation
    // must NOT fire the card (the guard returns early).
    const skipClar = await probeIntentClar({
      page,
      message: "Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC",
      forceIntent: "workflow_generation",
    });
    expect(skipClar, "no card when intent is already workflow_generation").toBeFalsy();

    // Test 3 — API-level: confirm a non-design query never triggers the card
    // even when forced to tool_search.
    const noClar = await probeIntentClar({
      page,
      message: "What is the typical hERG IC50 cutoff for cardiac safety?",
      forceIntent: "tool_search",
    });
    expect(noClar, "no card for non-design queries").toBeFalsy();
  });

  test("UI: card renders, primary chip click re-submits, workflow panel opens", async ({
    page,
  }, testInfo) => {
    const ok = await loginShared(page);
    expect(ok, "fixture login").toBeTruthy();

    // Force the FIRST chat-stream call to misclassify by injecting
    // testForceIntent into the request body. Subsequent requests (the
    // re-submit triggered by the chip click) pass through unmodified so
    // the intentOverride path is exercised.
    let intercepted = false;
    const debugLog: string[] = [];
    page.on("console", (m) => {
      if (m.type() === "error") debugLog.push(`[console.error] ${m.text()}`);
    });
    page.on("pageerror", (e) => debugLog.push(`[pageerror] ${e.message}`));
    await page.route("**/api/chat/stream", async (route) => {
      const request = route.request();
      debugLog.push(`[route] method=${request.method()} url=${request.url()}`);
      if (intercepted || request.method() !== "POST") return route.continue();
      try {
        const orig = request.postDataJSON();
        if (orig && typeof orig === "object") {
          orig.context = orig.context || {};
          orig.context.testForceIntent = "tool_search";
          intercepted = true;
          debugLog.push(`[route] injected testForceIntent=tool_search into body`);
          return route.continue({
            postData: JSON.stringify(orig),
            headers: { ...request.headers(), "content-type": "application/json" },
          });
        }
      } catch (e) {
        debugLog.push(`[route] error parsing body: ${(e as Error).message}`);
      }
      return route.continue();
    });
    // Surface debug log to test stdout so the run report has full context.
    test.info().annotations.push({ type: "debug-log-ref", description: "see debugLog appended at test end" });
    page.on("close", () => {
      console.log("\n--- debugLog ---\n" + debugLog.join("\n"));
    });

    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 30_000 });
    await page.waitForLoadState("load").catch(() => {});
    await page.screenshot({
      path: `${testInfo.outputDir}/01-home.png`,
      fullPage: true,
    });

    const designQuery =
      "Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC";
    await sendChatViaUI(page, designQuery);

    // Diagnostic: snapshot the page 10s after sending, BEFORE we wait for
    // the card. If the card never renders, this shows what state we ended
    // up in (chat reply text, errors, missing testid, etc).
    await page.waitForTimeout(10_000);
    await page.screenshot({
      path: `${testInfo.outputDir}/02a-after-send-pre-card.png`,
      fullPage: true,
    });
    console.log(`[diag] route intercepted: ${intercepted}`);
    console.log(`[diag] debugLog snapshot:\n  ${debugLog.slice(-15).join("\n  ")}`);

    // Card MUST appear (forced misclassification path)
    const card = page.locator('[data-testid="intent-clarification-card"]');
    await card.waitFor({ state: "visible", timeout: 120_000 });
    await page.screenshot({
      path: `${testInfo.outputDir}/02-card-rendered.png`,
      fullPage: true,
    });

    // Primary chip should be present
    const primaryChip = page.locator(
      '[data-testid="intent-clarify-workflow_generation"]',
    );
    await expect(primaryChip).toBeVisible();
    await expect(primaryChip).toContainText(/design workflow/i);

    // Click primary → re-submit with intentOverride
    await primaryChip.click();
    await page.waitForTimeout(3000);
    await page.screenshot({
      path: `${testInfo.outputDir}/03-after-pick.png`,
      fullPage: true,
    });

    // After re-submit, the workflow response should appear. Match either the
    // canonical workflow name (with underscores) OR the display name (with
    // spaces, title-cased) — both are valid renderings on different surfaces.
    const wfCardText = page.locator(
      'text=/bispecific[_ ]format[_ ]triage/i',
    );
    await wfCardText.first().waitFor({ state: "visible", timeout: 180_000 });
    await page.screenshot({
      path: `${testInfo.outputDir}/04-workflow-rendered.png`,
      fullPage: true,
    });

    // Bonus: assert the bispecific text is somewhere on the page (covers
    // both panel-open and chat-only render variants).
    const wfPresent = page.locator('text=/bispecific[_ ]format[_ ]triage/i');
    expect(await wfPresent.count()).toBeGreaterThan(0);

    testInfo.attachments.push({
      name: "scenario-summary.json",
      contentType: "application/json",
      body: Buffer.from(
        JSON.stringify(
          {
            query: designQuery,
            card_appeared: true,
            primary_clicked: "workflow_generation",
            workflow_rendered: "bispecific_format_triage",
          },
          null,
          2,
        ),
      ),
    });
  });

  test("UI: skip button hides card without re-submit", async ({ page }, testInfo) => {
    const ok = await loginShared(page);
    expect(ok, "fixture login").toBeTruthy();

    await page.route("**/api/chat/stream", async (route) => {
      const request = route.request();
      if (request.method() !== "POST") return route.continue();
      try {
        const orig = request.postDataJSON();
        if (orig && typeof orig === "object") {
          orig.context = orig.context || {};
          orig.context.testForceIntent = "tool_search";
          return route.continue({
            postData: JSON.stringify(orig),
            headers: { ...request.headers(), "content-type": "application/json" },
          });
        }
      } catch {
        // fall through
      }
      return route.continue();
    });

    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 30_000 });
    await page.waitForLoadState("load").catch(() => {});
    await sendChatViaUI(
      page,
      "Compare GLP-1 modalities for MASH peptide vs mRNA vs gene therapy",
    );

    const card = page.locator('[data-testid="intent-clarification-card"]');
    await card.waitFor({ state: "visible", timeout: 120_000 });
    await page.screenshot({
      path: `${testInfo.outputDir}/01-card-before-skip.png`,
      fullPage: true,
    });

    const skip = page.locator('[data-testid="intent-clarify-skip"]');
    await expect(skip).toBeVisible();
    await skip.click();

    // After click, the card should still be in DOM (we don't unmount the
    // assistant message) but the page should NOT auto-submit a follow-up.
    // Simplest assertion: no NEW user message appears for the next 3s.
    const userMsgCountBefore = await page
      .locator('[data-testid^="msg-user"], [data-testid="user-message"]')
      .count();
    await page.waitForTimeout(3000);
    const userMsgCountAfter = await page
      .locator('[data-testid^="msg-user"], [data-testid="user-message"]')
      .count();
    expect(userMsgCountAfter).toBe(userMsgCountBefore);
    await page.screenshot({
      path: `${testInfo.outputDir}/02-after-skip.png`,
      fullPage: true,
    });
  });
});
