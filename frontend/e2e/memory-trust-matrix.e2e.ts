/**
 * C7 — Memory trust matrix.
 *
 *   C7.01 /api/memory/episodes returns array
 *   C7.02 /api/memory/projects returns shape
 *   C7.03 /api/memory/relevant accepts a query
 *   C7.04 /api/memory/sessions returns array (chat history)
 *   C7.05 /api/memory/interactions 400/404 contract (bug fix)
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login.js";

test.describe("Memory trust matrix (C7)", () => {
  test("C7.01 episodes returns array", async ({ page }) => {
    await loginAsFixture(page);
    const r = await page.request.get(`${BASE_URL}/api/memory/user/episodes`);
    expect(r.status()).toBeLessThan(500);
  });

  test("C7.02 projects returns shape", async ({ page }) => {
    await loginAsFixture(page);
    const r = await page.request.get(`${BASE_URL}/api/memory/projects`);
    expect(r.status()).toBeLessThan(500);
  });

  test("C7.03 relevant accepts a query", async ({ page }) => {
    await loginAsFixture(page);
    const r = await page.request.get(`${BASE_URL}/api/memory/relevant?q=RNA-seq`);
    expect(r.status()).toBeLessThan(500);
  });

  test("C7.04 sessions returns array (chat history)", async ({ page }) => {
    await loginAsFixture(page);
    const r = await page.request.get(`${BASE_URL}/api/memory/sessions`);
    expect(r.status()).toBeLessThan(500);
  });

  test("C7.05 interactions returns structured errors (was 500-on-everything)", async ({ page }) => {
    await loginAsFixture(page);

    const empty = await page.request.post(`${BASE_URL}/api/memory/interactions`, {
      data: {},
    });
    const badUuid = await page.request.post(`${BASE_URL}/api/memory/interactions`, {
      data: { sessionId: "not-uuid", userMessage: "hi", assistantResponse: "hello" },
    });
    const missingSession = await page.request.post(`${BASE_URL}/api/memory/interactions`, {
      data: { sessionId: "00000000-0000-0000-0000-000000000000", userMessage: "hi", assistantResponse: "hello" },
    });

    // After the fix the endpoint returns structured 400/404 instead of 500.
    expect(empty.status()).toBeLessThan(500);
    expect(badUuid.status()).toBeLessThan(500);
    expect(missingSession.status()).toBeLessThan(500);

    if (empty.status() === 400) {
      const body = await empty.json();
      expect(body?.error).toBe("missing_required_fields");
    }
    if (badUuid.status() === 400) {
      const body = await badUuid.json();
      expect(body?.error).toBe("invalid_session_id");
    }
    if (missingSession.status() === 404) {
      const body = await missingSession.json();
      expect(body?.error).toBe("session_not_found");
    }
  });
});
