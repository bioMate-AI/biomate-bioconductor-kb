/**
 * Billing Smoke Test — runs after every sync
 *
 * Verifies the full billing pipeline:
 *   1. Login as a real user → get JWT
 *   2. Send a chat message → triggers LLM call → cost_log.record()
 *   3. Poll Lago for the three expected events (llm_input_tokens, llm_output_tokens, llm)
 *   4. Verify field names are correct (tokens / value, not the old property names)
 *   5. Verify customer + active subscription exist in Lago for the user
 *
 * NO MOCKS. Hits live backend and live Lago instance.
 */
import { test, expect } from "@playwright/test";
import { BASE_URL } from "./helpers.js";

test.setTimeout(60000);

const LAGO_URL = process.env.LAGO_URL || "http://35.86.137.71:3000";
const LAGO_KEY = process.env.LAGO_API_KEY || "01b71711-be39-49af-8d14-87a4ee827157";
// Dedicated smoke test account — created once, password never changes
const TEST_EMAIL = "billing-smoke@biomate.test";
const TEST_PASS  = "SmokeTest2026!";
const TEST_UUID  = "bsmoke-0000-0000-0000-000000000001";

async function lagoGet(path: string) {
  const res = await fetch(`${LAGO_URL}${path}`, {
    headers: { Authorization: `Bearer ${LAGO_KEY}` },
  });
  return res.json();
}

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

  test("LLM call generates cost events in Lago", async ({ request }) => {
    // Skip if login failed
    if (!jwt) test.skip();

    // Send a chat message (short, just enough to trigger a real LLM call)
    const chatRes = await request.post(`${BASE_URL}/api/chat/stream`, {
      data: { message: "Say exactly: hello", sessionId },
      headers: { Authorization: `Bearer ${jwt}` },
    });
    expect(chatRes.status()).toBe(200);

    // Wait for Galaxy to process + forward events to Lago (async)
    await new Promise(r => setTimeout(r, 8000));

    // Poll Lago for recent events matching our subscription ID
    const expectedSubId = `bm_${TEST_UUID}_base`;
    const eventData = await lagoGet(`/api/v1/events?per_page=50`);
    const events: any[] = eventData.events || [];

    // Find events from this user posted in the last 60 seconds
    const cutoff = Date.now() - 60000;
    const sessionEvents = events.filter((e) =>
      e.external_subscription_id === expectedSubId &&
      new Date(e.created_at).getTime() > cutoff
    );

    expect(sessionEvents.length, "Expected 3 events (llm_input_tokens, llm_output_tokens, llm)").toBeGreaterThanOrEqual(3);

    const inputEvt  = sessionEvents.find((e) => e.code === "llm_input_tokens");
    const outputEvt = sessionEvents.find((e) => e.code === "llm_output_tokens");
    const llmEvt    = sessionEvents.find((e) => e.code === "llm");

    // Verify all three event types present
    expect(inputEvt,  "llm_input_tokens event missing").toBeTruthy();
    expect(outputEvt, "llm_output_tokens event missing").toBeTruthy();
    expect(llmEvt,    "llm aggregate event missing").toBeTruthy();

    // Verify field names (not the old broken property names)
    expect(inputEvt.properties.tokens,  "llm_input_tokens must use 'tokens' field").toBeGreaterThan(0);
    expect(outputEvt.properties.tokens, "llm_output_tokens must use 'tokens' field").toBeGreaterThan(0);
    expect(llmEvt.properties.value,     "llm must use 'value' field").toBeGreaterThan(0);

    // Verify value = input + output
    expect(llmEvt.properties.value).toBe(
      inputEvt.properties.tokens + outputEvt.properties.tokens
    );

    // Verify subscription ID format
    expect(inputEvt.external_subscription_id).toBe(expectedSubId);
  });

  test("Lago customer and active subscription exist for real user", async () => {
    const extId = `bm_${TEST_UUID}`;

    const custData = await lagoGet(`/api/v1/customers/${extId}`);
    const customer = custData.customer;
    expect(customer, "Lago customer not found").toBeTruthy();
    expect(customer.external_id).toBe(extId);

    const subData = await lagoGet(
      `/api/v1/subscriptions?external_customer_id=${extId}&status[]=active`
    );
    const subs: any[] = subData.subscriptions || [];
    expect(subs.length, "No active subscription found").toBeGreaterThan(0);
    expect(subs[0].plan_code).toBe("base");
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
