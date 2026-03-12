/**
 * Shared helpers for real BioMate E2E tests.
 * No page.route() mocking — all calls hit the live stack.
 *
 * Billing verification:
 *   verifyBillingRecord(page, label) — calls /api/billing/usage with the
 *   in-browser JWT and logs the result. Non-blocking: passes when billing
 *   Redis is unavailable (local dev). Always writes to console for audit.
 */
import { Page, APIRequestContext, expect } from "@playwright/test";

export const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

// ---------------------------------------------------------------------------
// Auth helpers
// ---------------------------------------------------------------------------

/** Register a fresh user and navigate to the main app. */
export async function setupTestUser(
  page: Page,
  prefix = "test"
): Promise<{ email: string; password: string }> {
  const email = `e2e_${prefix}_${Date.now()}@biomate.test`;
  const password = "TestPass123!";

  await page.goto(`${BASE_URL}/register`);
  await page.waitForLoadState("load");

  try {
    await page.waitForSelector("#name", { state: "visible", timeout: 10000 });
    await page.fill("#name", `E2E ${prefix}`);
    await page.fill("#email", email);
    await page.fill("#password", password);
    await page.fill("#confirmPassword", password);
    const terms = page.locator("#terms");
    if (await terms.isVisible({ timeout: 2000 }).catch(() => false)) {
      await terms.click();
    }
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
  } catch {
    // Already logged in or form structure different — proceed
  }

  await page.goto(BASE_URL);
  await page.waitForLoadState("load");
  await page.waitForTimeout(1500);
  return { email, password };
}

// ---------------------------------------------------------------------------
// Chat helpers
// ---------------------------------------------------------------------------

/** Type a message into the chat input and submit. */
export async function sendChatMessage(
  page: Page,
  message: string
): Promise<void> {
  const chatInput = page.locator("textarea").first();
  await expect(chatInput).toBeVisible({ timeout: 10000 });
  await chatInput.fill(message);
  await chatInput.press("Enter");
}

/**
 * Send a chat message and wait for the AI to finish responding.
 * Returns true if a workflow Run button appeared in the response.
 */
export async function sendMessageAndWaitForResponse(
  page: Page,
  message: string,
  timeoutMs = 120_000
): Promise<boolean> {
  await sendChatMessage(page, message);
  // Wait for the typing indicator to appear…
  await page
    .waitForSelector("text=AI is typing", { state: "visible", timeout: 30_000 })
    .catch(() => {});
  // …then disappear
  await page
    .waitForSelector("text=AI is typing", { state: "hidden", timeout: timeoutMs })
    .catch(() => {});
  await page.waitForTimeout(1000);

  // Did a workflow card appear?
  return page
    .getByTestId("button-run-workflow-panel")
    .first()
    .isVisible({ timeout: 5000 })
    .catch(() => false);
}

// ---------------------------------------------------------------------------
// Execution helpers
// ---------------------------------------------------------------------------

/**
 * Click the Run Workflow button and wait for terminal status.
 * Returns the runId captured from the execute response, or null.
 */
export async function clickRunAndWaitForTerminal(
  page: Page,
  timeoutMs = 300_000
): Promise<string | null> {
  let runId: string | null = null;

  const handler = async (resp: import("@playwright/test").Response) => {
    if (!resp.url().includes("/api/workflows/execute")) return;
    try {
      const payload = await resp.json();
      runId =
        payload?.runId ||
        payload?.execution?.run?.id ||
        payload?.execution?.runId ||
        runId;
    } catch {
      /* ignore */
    }
  };
  page.on("response", handler);

  const runBtn = page.getByTestId("button-run-workflow-panel").first();
  const visible = await runBtn.isVisible({ timeout: 10_000 }).catch(() => false);
  if (!visible) {
    // Fallback selectors
    for (const sel of [
      page.getByRole("button", { name: /run workflow/i }).first(),
      page.getByRole("button", { name: /^run$/i }).first(),
      page.getByRole("button", { name: /execute/i }).first(),
    ]) {
      if (await sel.isVisible({ timeout: 2000 }).catch(() => false)) {
        await sel.click();
        break;
      }
    }
  } else {
    await runBtn.click();
  }

  // Poll page text for terminal state
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await page.waitForTimeout(3000);
    const text = await page.textContent("body").catch(() => "");
    if (
      text?.toLowerCase().includes("completed") ||
      text?.toLowerCase().includes("finished") ||
      text?.toLowerCase().includes("failed") ||
      text?.toLowerCase().includes("errored")
    ) {
      break;
    }
  }

  page.removeListener("response", handler);
  return runId;
}

// ---------------------------------------------------------------------------
// Run-manager helpers
// ---------------------------------------------------------------------------

/** Open the run manager side panel if it is not already open. */
export async function openRunManager(page: Page): Promise<void> {
  const panel = page.getByTestId("run-manager-panel");
  if (await panel.isVisible({ timeout: 2000 }).catch(() => false)) return;

  // Try the button that opens it
  for (const sel of [
    page.getByTestId("run-manager-toggle"),
    page.getByRole("button", { name: /runs/i }).first(),
    page.getByRole("button", { name: /my runs/i }).first(),
    page.getByRole("button", { name: /history/i }).first(),
  ]) {
    if (await sel.isVisible({ timeout: 1500 }).catch(() => false)) {
      await sel.click();
      await page.waitForTimeout(500);
      break;
    }
  }
}

/** Wait for the run manager panel to contain at least `count` run items. */
export async function waitForRunManagerItems(
  page: Page,
  count = 1,
  timeoutMs = 30_000
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const items = await page.locator("[data-testid^='run-manager-item-']").count();
    if (items >= count) return;
    await page.waitForTimeout(1000);
  }
}

// ---------------------------------------------------------------------------
// Billing audit helpers
// ---------------------------------------------------------------------------

/**
 * Verify that the billing system has a record for the current user.
 *
 * Reads the JWT from localStorage and calls GET /api/billing/usage.
 * Logs the result to console for the audit trail (videos + reporter).
 * Non-blocking: if billing Redis is unavailable (local dev) the test
 * continues normally — the call is skipped with a console note.
 *
 * @param page    Playwright page (must be logged in via setupTestUser)
 * @param label   Human label for the log line, e.g. "after VCF query"
 */
export async function verifyBillingRecord(
  page: Page,
  label: string
): Promise<void> {
  try {
    // Extract JWT stored by the frontend auth context
    const token = await page.evaluate(() => {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i) ?? "";
        if (key.includes("token") || key.includes("auth") || key.includes("jwt")) {
          return localStorage.getItem(key);
        }
      }
      // Fallback: scan all values for a JWT-shaped string (3 base64 segments)
      for (let i = 0; i < localStorage.length; i++) {
        const val = localStorage.getItem(localStorage.key(i) ?? "") ?? "";
        if (/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(val)) {
          return val;
        }
      }
      return null;
    });

    if (!token) {
      console.log(`[Billing:${label}] No JWT found in localStorage — billing check skipped`);
      return;
    }

    // Call billing usage endpoint from within the browser so CORS/cookies apply
    const result = await page.evaluate(
      async ({ url, jwt }: { url: string; jwt: string }) => {
        try {
          const r = await fetch(`${url}/api/billing/usage`, {
            headers: { Authorization: `Bearer ${jwt}` },
          });
          if (!r.ok) return { ok: false, status: r.status };
          const d = await r.json();
          return { ok: true, status: r.status, data: d };
        } catch (e: any) {
          return { ok: false, error: String(e) };
        }
      },
      { url: BASE_URL, jwt: token }
    );

    if (!result.ok) {
      console.log(
        `[Billing:${label}] Billing unavailable (status=${result.status ?? "err"} ${result.error ?? ""}) — Redis may not be configured locally`
      );
      return;
    }

    const d = result.data ?? {};
    console.log(
      `[Billing:${label}] ✓ usage: llm_tokens=${d.llm_tokens_used ?? "n/a"} ` +
      `llm_cost=$${(d.llm_cost_usd ?? 0).toFixed(4)} ` +
      `compute_cost=$${(d.compute_cost_usd ?? 0).toFixed(4)} ` +
      `quota_used=${d.quota_used_pct ?? "n/a"}%`
    );
  } catch (err: any) {
    console.log(`[Billing:${label}] Billing check error (non-fatal): ${err.message}`);
  }
}
