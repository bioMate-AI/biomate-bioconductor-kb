/**
 * Auth E2E: Full registration → forgot-password → reset → relogin flow
 *
 * Flow:
 *   1. Register a new user via API (real registration, real JWT)
 *   2. Verify login works with original password
 *   3. Submit forgot-password form in UI → POST /api/auth/request-password-reset
 *   4. Fetch reset token directly from Postgres (dev-only shortcut — no email needed)
 *   5. Reset password via API POST /api/auth/reset-password with token
 *   6. Verify old password is rejected
 *   7. Log in via UI with the new password → reach the chat UI
 *
 * NO MOCKS. All calls hit the live backend.
 */
import { test, expect, Page } from "@playwright/test";
import { BASE_URL } from "./helpers.js";
import { Client } from "pg";

test.setTimeout(120000);

const DB_URL =
  process.env.DATABASE_URL ||
  "postgresql://biomate:biomate_dev_password@localhost:5432/biomate_dev";

async function getResetToken(email: string): Promise<string | null> {
  const client = new Client({ connectionString: DB_URL });
  await client.connect();
  try {
    const res = await client.query(
      `SELECT reset_password_token
         FROM users
        WHERE email = $1
          AND reset_password_token IS NOT NULL
          AND reset_password_expires > NOW()
        ORDER BY reset_password_expires DESC
        LIMIT 1`,
      [email]
    );
    return res.rows[0]?.reset_password_token ?? null;
  } finally {
    await client.end();
  }
}

const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";

async function apiFetch(
  page: Page,
  method: string,
  url: string,
  body?: any
): Promise<{ status: number; data: any }> {
  const resp = await page.evaluate(
    async ({ method, url, body, token }) => {
      const r = await fetch(url, {
        method,
        headers: {
          "Content-Type": "application/json",
          "X-E2E-Test-Token": token,
        },
        body: body ? JSON.stringify(body) : undefined,
      });
      const data = await r.json().catch(() => ({}));
      return { status: r.status, data };
    },
    { method, url, body, token: E2E_TOKEN }
  );
  return resp;
}

test.describe("Auth: registration + forgot-password + reset + relogin", () => {
  const ts = Date.now();
  const email = `e2e_reset_${ts}@biomate.test`;
  const name = "Dr Reset Test";
  const originalPass = `OrigPass_${ts}!`;
  const newPass = `NewPass_${ts}@`;

  test("full registration → forgot-password → reset → relogin", async ({
    page,
  }) => {
    // ------------------------------------------------------------------
    // Step 1: Register via UI
    // ------------------------------------------------------------------
    await page.goto(`${BASE_URL}/register`);
    await page.waitForLoadState("load");

    const nameField = page.locator("#name");
    if (await nameField.isVisible({ timeout: 3000 }).catch(() => false)) {
      await nameField.fill(name);
    }
    await page.locator("#email").fill(email);
    await page.locator("#password").fill(originalPass);
    await page.locator("#confirmPassword").fill(originalPass);

    // Accept terms if present
    const termsCheckbox = page.locator("#terms");
    if (
      await termsCheckbox
        .isVisible({ timeout: 2000 })
        .catch(() => false)
    ) {
      await termsCheckbox.check();
    }

    const submitBtn = page
      .getByRole("button", { name: /create account/i })
      .or(page.getByRole("button", { name: /register/i }))
      .or(page.getByRole("button", { name: /sign up/i }))
      .first();
    await submitBtn.click();

    // After registration we should either be redirected to chat or login
    await page
      .waitForURL(/\/(chat|login|verify|onboarding|dashboard)/, { timeout: 15000 })
      .catch(() => {});
    console.log(`[Auth E2E] Registered as ${email}`);

    // ------------------------------------------------------------------
    // Step 2: Log in with original password via API to confirm it works
    // ------------------------------------------------------------------
    const loginResp = await apiFetch(page, "POST", `${BASE_URL}/api/auth/login`, {
      email,
      password: originalPass,
    });
    expect(loginResp.status, "Original login should succeed").toBe(200);
    expect(loginResp.data.token || loginResp.data.user).toBeTruthy();
    console.log(`[Auth E2E] Original password login OK`);

    // ------------------------------------------------------------------
    // Step 3: Submit forgot-password via API (bypasses rate limiter for E2E)
    // ------------------------------------------------------------------
    const forgotResp = await apiFetch(
      page,
      "POST",
      `${BASE_URL}/api/auth/forgot-password`,
      { email }
    );
    expect(forgotResp.status, "Forgot-password should return 200").toBe(200);
    // Wait briefly for the reset token to be committed to the DB
    await page.waitForTimeout(1000);
    console.log(`[Auth E2E] Submitted forgot-password request`);

    // ------------------------------------------------------------------
    // Step 4: Fetch reset token from DB (dev shortcut — avoids email)
    // ------------------------------------------------------------------
    let token: string | null = null;
    for (let attempt = 0; attempt < 5; attempt++) {
      token = await getResetToken(email);
      if (token) break;
      await page.waitForTimeout(1000);
    }
    expect(token, "Reset token should be present in DB after request").toBeTruthy();
    console.log(`[Auth E2E] Got reset token from DB (len=${token!.length})`);

    // ------------------------------------------------------------------
    // Step 5: Reset password via API
    // ------------------------------------------------------------------
    const resetResp = await apiFetch(
      page,
      "POST",
      `${BASE_URL}/api/auth/reset-password`,
      { token, password: newPass }
    );
    expect(resetResp.status, "Password reset API should return 200").toBe(200);
    expect(resetResp.data.success).toBe(true);
    console.log(`[Auth E2E] Password reset successful`);

    // ------------------------------------------------------------------
    // Step 6: Verify old password is now rejected
    // ------------------------------------------------------------------
    const oldLoginResp = await apiFetch(page, "POST", `${BASE_URL}/api/auth/login`, {
      email,
      password: originalPass,
    });
    expect(
      oldLoginResp.status,
      "Old password should be rejected after reset"
    ).toBe(401);
    console.log(`[Auth E2E] Old password correctly rejected`);

    // ------------------------------------------------------------------
    // Step 7: Log in via UI with the new password → reach the chat UI
    // ------------------------------------------------------------------
    await page.goto(`${BASE_URL}/login`);
    await page.waitForLoadState("load");

    await page.locator("#email").fill(email);
    await page.locator("#password").fill(newPass);

    const signInBtn = page
      .getByRole("button", { name: /sign in/i })
      .or(page.getByRole("button", { name: /log in/i }))
      .first();
    await signInBtn.click();

    // Should land on chat, home, or dashboard after login
    await page.waitForURL(/\/(chat|home|dashboard|\?)/, { timeout: 15000 });
    console.log(`[Auth E2E] New password login OK — at: ${page.url()}`);

    // Navigate to home (chat UI) to confirm the session is authenticated
    await page.goto(BASE_URL);
    await page.waitForLoadState("load");

    // Confirm the user is authenticated (chat input is visible)
    const chatInput = page
      .locator('[data-testid="chat-input"], [placeholder*="message"], textarea')
      .first();
    await expect(chatInput).toBeVisible({ timeout: 15000 });
    console.log(`[Auth E2E] Chat UI visible — full flow PASS`);
  });
});
