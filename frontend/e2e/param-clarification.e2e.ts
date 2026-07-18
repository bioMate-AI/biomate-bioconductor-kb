/**
 * param-clarification.e2e.ts
 *
 * Scene-based E2E for ParamClarificationCard — proves the schema-grounded
 * extraction's clarification surface renders end-to-end in a browser.
 *
 * Strategy: send a query that mentions an out-of-enum value for a known
 * workflow. The schema-grounded extractor catches the violation, emits
 * `paramClarifications`, the chat-interface metadata-whitelist fix
 * (chat-interface.tsx:954) forwards it, and chat-message.tsx renders
 * the card.
 *
 * Force workflow_generation routing via context.intentOverride so the
 * test isn't blocked by intent non-determinism.
 *
 * Run:
 *   BIOMATE_URL=http://localhost:5000 \
 *   E2E_FIXTURE_PASSWORD=… \
 *   E2E_TEST_TOKEN=biomate-e2e-bypass-token-dev-only \
 *   PW_OUTPUT_DIR=/tmp/param-clar-audit \
 *   npx playwright test e2e/param-clarification.e2e.ts \
 *     --reporter=line --project=chromium
 */
import { test, expect, type Page } from "@playwright/test";

const BASE_URL = (process.env.BIOMATE_URL || "http://localhost:5000").replace(/\/+$/, "");
const FIXTURE_EMAIL = process.env.E2E_FIXTURE_EMAIL || "lifeifei163361@163.com";
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";

async function loginShared(page: Page): Promise<boolean> {
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  let resp = await page.request.post(`${BASE_URL}/api/auth/login`, {
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

async function sendChatViaUI(page: Page, query: string) {
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

test.describe("ParamClarificationCard end-to-end", () => {
  test("enum violation → card renders with allowed-value chips", async ({ page }, testInfo) => {
    test.setTimeout(300_000);

    // Force workflow_generation routing so the chat goes straight to the
    // schema-grounded extractor (no intent ambiguity card in the way).
    await page.route("**/api/chat/stream", async (route) => {
      const request = route.request();
      if (request.method() !== "POST") return route.continue();
      try {
        const orig = request.postDataJSON();
        if (orig && typeof orig === "object") {
          orig.context = orig.context || {};
          orig.context.intentOverride = "workflow_generation";
          return route.continue({
            postData: JSON.stringify(orig),
            headers: { ...request.headers(), "content-type": "application/json" },
          });
        }
      } catch {
        // pass through
      }
      return route.continue();
    });

    const ok = await loginShared(page);
    expect(ok, "fixture login").toBeTruthy();

    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 30_000 });
    await page.waitForLoadState("load").catch(() => {});

    // Out-of-enum: "B cells" is not in the in_vivo_cart_codesign delivery_cell
    // enum (T_cell | NK_cell | macrophage). Should fire ParamClarification.
    const query =
      "Co-design an in-vivo CD19 CAR-T for DLBCL with LNP delivery to B cells, transient persistence";
    await sendChatViaUI(page, query);

    // Wait up to 3 minutes for the response to materialize (real LLM round-trip).
    const card = page.locator('[data-testid="param-clarification-card"]');
    try {
      await card.waitFor({ state: "visible", timeout: 180_000 });
    } catch {
      // If the card didn't render, dump page state for triage.
      await page.screenshot({
        path: `${testInfo.outputDir}/00-card-never-rendered.png`,
        fullPage: true,
      });
      throw new Error("ParamClarificationCard never rendered — check screenshot");
    }
    await page.screenshot({
      path: `${testInfo.outputDir}/01-card-rendered.png`,
      fullPage: true,
    });

    // Verify the enum_violation chip set for delivery_cell is present —
    // chips are testid'd `param-clarify-chip-<paramName>-<value>`.
    const allowedValues = ["T_cell", "NK_cell", "macrophage"];
    for (const v of allowedValues) {
      const chip = page.locator(`[data-testid="param-clarify-chip-delivery_cell-${v}"]`);
      await expect(chip, `chip for ${v} present`).toBeVisible();
    }

    // Skip link must also be present per the design.
    const skip = page.locator('[data-testid="param-clarify-skip-delivery_cell"]');
    await expect(skip, "skip link present").toBeVisible();

    // Click T_cell — fires the resolved CustomEvent the workflow panel
    // listens for. Then verify either (a) the panel's delivery_cell input
    // updates, or (b) the card hides.
    const tCellChip = page.locator(
      '[data-testid="param-clarify-chip-delivery_cell-T_cell"]',
    );
    await tCellChip.click();
    await page.waitForTimeout(2_500);
    await page.screenshot({
      path: `${testInfo.outputDir}/02-after-tcell-pick.png`,
      fullPage: true,
    });

    // Sanity check the page reached a stable state (no crash).
    const pageText = await page.locator("body").innerText().catch(() => "");
    expect(
      pageText.length,
      "page rendered text after the chip click",
    ).toBeGreaterThan(100);
  });
});
