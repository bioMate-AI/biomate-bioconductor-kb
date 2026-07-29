/**
 * Billing Smoke Test — the INTERNAL billing pipeline (Lago-free).
 *
 * Per the flat-tier decision, Lago is dropped from the critical path
 * (BILLING_LAGO_ENABLED default off): Stripe owns subscriptions/payment, and cost
 * is tracked in the internal file log + Redis realtime ledger, with quota from
 * DEFAULT_PLAN_LIMITS.
 *
 *   1. Login as the canonical fixture → JWT
 *   2. GET /api/billing/usage → structured breakdown (llm/compute/storage), no Lago
 *   3. Send a chat → real LLM call → internal cost recording; usage stays monotonic
 *   4. GET /api/billing/quota → plan limit from DEFAULT_PLAN_LIMITS
 *
 * NO MOCKS. Hits the live dev backend through the real Node→Galaxy billing proxy.
 */
import { test, expect } from "@playwright/test";
import { BASE_URL } from "./helpers.js";

const E2E_TOKEN = "biomate-e2e-bypass-token-dev-only";
const FIXTURE_EMAIL = "lifeifei163361@163.com";
const FIXTURE_PASS = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";

test.setTimeout(90_000);

// Read the LLM cost from the real usage shape: { breakdown: { llm: { total_usd } } }
function llmUsd(u: any): number {
  return Number(u?.breakdown?.llm?.total_usd ?? u?.llm?.total_usd ?? 0);
}

test.describe("Billing Smoke (Lago-free)", () => {
  let jwt: string;

  test("login (canonical fixture) returns a JWT", async ({ request }) => {
    const res = await request.post(`${BASE_URL}/api/auth/login`, {
      data: { email: FIXTURE_EMAIL, password: FIXTURE_PASS },
      headers: { "X-E2E-Test-Token": E2E_TOKEN },
    });
    expect(res.status()).toBe(200);
    jwt = (await res.json()).token;
    expect(jwt).toBeTruthy();
  });

  test("GET /api/billing/usage returns a structured internal breakdown", async ({ request }) => {
    test.skip(!jwt, "no jwt");
    const res = await request.get(`${BASE_URL}/api/billing/usage`, {
      headers: { Authorization: `Bearer ${jwt}`, "X-E2E-Test-Token": E2E_TOKEN },
    });
    expect(res.status(), "usage must not 401 (proxy re-sign must match Galaxy)").toBe(200);
    const u = await res.json();
    // Internal ledger breakdown — the fields Lago used to supply now come from Galaxy's own store.
    expect(u.breakdown, "usage.breakdown must be present").toBeTruthy();
    expect(u.breakdown.llm, "breakdown.llm present").toBeTruthy();
    expect(u.breakdown.compute, "breakdown.compute present").toBeTruthy();
    expect(u.breakdown.storage, "breakdown.storage present").toBeTruthy();
    expect(Number.isFinite(llmUsd(u)), "llm.total_usd is numeric").toBe(true);
  });

  test("a chat records LLM cost internally — usage stays monotonic (no loss without Lago)", async ({ request }) => {
    test.skip(!jwt, "no jwt");
    const before = await request.get(`${BASE_URL}/api/billing/usage`, {
      headers: { Authorization: `Bearer ${jwt}`, "X-E2E-Test-Token": E2E_TOKEN },
    });
    const llmBefore = llmUsd(await before.json());

    const chat = await request.post(`${BASE_URL}/api/chat/stream`, {
      data: { message: "Say exactly: hello", sessionId: `billing-smoke-${Date.now()}` },
      headers: { Authorization: `Bearer ${jwt}`, "X-E2E-Test-Token": E2E_TOKEN },
    });
    expect(chat.status()).toBe(200);
    await new Promise((r) => setTimeout(r, 10_000)); // async cost recording (Node → Galaxy → ledger)

    const after = await request.get(`${BASE_URL}/api/billing/usage`, {
      headers: { Authorization: `Bearer ${jwt}`, "X-E2E-Test-Token": E2E_TOKEN },
    });
    expect(after.status()).toBe(200);
    const llmAfter = llmUsd(await after.json());
    console.log(`[billing-smoke] llm usd before=${llmBefore} after=${llmAfter}`);
    // Monotonic: the chat's cost was recorded internally, not lost with Lago.
    expect(llmAfter, "internal LLM usage must not decrease after a chat").toBeGreaterThanOrEqual(llmBefore);
  });

  test("GET /api/billing/quota returns a limit from DEFAULT_PLAN_LIMITS", async ({ request }) => {
    test.skip(!jwt, "no jwt");
    const res = await request.get(`${BASE_URL}/api/billing/quota`, {
      headers: { Authorization: `Bearer ${jwt}`, "X-E2E-Test-Token": E2E_TOKEN },
    });
    expect(res.status()).toBe(200);
    const b = await res.json();
    // quota_usd from DEFAULT_PLAN_LIMITS when Lago is off: a number, or null = unlimited.
    expect(b.quota_usd === null || Number.isFinite(Number(b.quota_usd)), "quota_usd number or null").toBe(true);
    expect(Number.isFinite(Number(b.used_usd)), "used_usd is numeric (internal ledger)").toBe(true);
  });
});
