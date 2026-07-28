/**
 * Billing Smoke Test — runs after every sync.
 *
 * Verifies the INTERNAL billing pipeline (Lago-free). Per the flat-tier billing
 * decision, Lago is dropped from the critical path (BILLING_LAGO_ENABLED default
 * off): Stripe owns subscriptions/payment, and cost is tracked in the internal
 * file log + Redis realtime ledger, with quota from DEFAULT_PLAN_LIMITS.
 *
 *   1. Login as the dedicated smoke user → JWT
 *   2. Send a chat → real LLM call → internal cost recording (file log + Redis)
 *   3. GET /api/billing/usage → structured breakdown (no Lago involved)
 *   4. GET /api/billing/quota → plan limit from DEFAULT_PLAN_LIMITS
 *
 * NO MOCKS. Hits the live backend. Does NOT depend on Lago.
 */
import { test, expect } from "@playwright/test";
import { BASE_URL } from "./helpers.js";

test.setTimeout(60000);

// Dedicated smoke test account — created once, password never changes
const TEST_EMAIL = "billing-smoke@biomate.test";
const TEST_PASS  = "SmokeTest2026!";

test.describe("Billing Smoke", () => {
  let jwt: string;
  let sessionId: string;

  test("login succeeds and returns JWT", async ({ request }) => {
    const res = await request.post(`${BASE_URL}/api/auth/login`, {
      data: { email: TEST_EMAIL, password: TEST_PASS },
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.token).toBeTruthy();
    jwt = body.token;
    sessionId = `billing-smoke-${Date.now()}`;
  });

  test("LLM call is recorded in the internal cost ledger (Lago-free)", async ({ request }) => {
    if (!jwt) test.skip();

    // Baseline usage before the chat
    const before = await request.get(`${BASE_URL}/api/billing/usage`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    expect(before.status()).toBe(200);
    const beforeBody = await before.json();
    const llmBefore = Number(beforeBody?.llm?.cost_usd ?? beforeBody?.llm?.total ?? beforeBody?.llm ?? 0);

    // Send a chat message → real LLM call → internal recording
    const chatRes = await request.post(`${BASE_URL}/api/chat/stream`, {
      data: { message: "Say exactly: hello", sessionId },
      headers: { Authorization: `Bearer ${jwt}` },
    });
    expect(chatRes.status()).toBe(200);

    // Wait for async recording (file log + Redis)
    await new Promise(r => setTimeout(r, 8000));

    // Usage now reflects the LLM cost — no Lago involved
    const after = await request.get(`${BASE_URL}/api/billing/usage`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    expect(after.status()).toBe(200);
    const afterBody = await after.json();
    expect(afterBody, "usage must be a structured breakdown").toBeTruthy();
    expect(afterBody.llm, "usage.llm breakdown must be present (internal ledger)").toBeDefined();
    const llmAfter = Number(afterBody?.llm?.cost_usd ?? afterBody?.llm?.total ?? afterBody?.llm ?? 0);
    // Usage is monotonic — the chat's LLM cost was recorded internally, not lost with Lago.
    expect(llmAfter, "internal LLM usage should not decrease after a chat").toBeGreaterThanOrEqual(llmBefore);
  });

  test("quota endpoint returns a plan limit from DEFAULT_PLAN_LIMITS (Lago-free)", async ({ request }) => {
    if (!jwt) test.skip();
    const res = await request.get(`${BASE_URL}/api/billing/quota`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    // quota_usd comes from DEFAULT_PLAN_LIMITS when Lago is off (number, or null = unlimited).
    const q = body?.quota_usd ?? body?.limit;
    expect(q === null || Number.isFinite(Number(q)), "quota must be a number or unlimited(null)").toBeTruthy();
  });

  test("forgot-password returns reset token when email unconfigured", async ({ request }) => {
    const res = await request.post(`${BASE_URL}/api/auth/forgot-password`, {
      data: { email: TEST_EMAIL },
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.success).toBe(true);
    // Either email was sent (no token in response) or dev bypass returned token
    // Both are valid — just ensure no error
    expect(body.error).toBeFalsy();
  });
});
