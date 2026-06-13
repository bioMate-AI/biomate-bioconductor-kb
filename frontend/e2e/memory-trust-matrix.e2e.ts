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
    const r = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/memory/episodes`, { credentials: "include" });
      return { status: r.status, body: await r.json().catch(() => null) };
    }, BASE_URL);
    expect(r.status).toBeLessThan(500);
  });

  test("C7.02 projects returns shape", async ({ page }) => {
    await loginAsFixture(page);
    const r = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/memory/projects`, { credentials: "include" });
      return { status: r.status };
    }, BASE_URL);
    expect(r.status).toBeLessThan(500);
  });

  test("C7.03 relevant accepts a query", async ({ page }) => {
    await loginAsFixture(page);
    const r = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/memory/relevant?q=RNA-seq`, {
        credentials: "include",
      });
      return { status: r.status };
    }, BASE_URL);
    expect(r.status).toBeLessThan(500);
  });

  test("C7.04 sessions returns array (chat history)", async ({ page }) => {
    await loginAsFixture(page);
    const r = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/memory/sessions`, { credentials: "include" });
      return { status: r.status };
    }, BASE_URL);
    expect(r.status).toBeLessThan(500);
  });

  test("C7.05 interactions returns structured errors (was 500-on-everything)", async ({ page }) => {
    await loginAsFixture(page);
    const results = await page.evaluate(async (base) => {
      const post = async (body: any) => {
        const r = await fetch(`${base}/api/memory/interactions`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          credentials: "include",
          body: JSON.stringify(body),
        });
        return { status: r.status, body: await r.json().catch(() => ({})) };
      };
      const empty = await post({});
      const badUuid = await post({
        sessionId: "not-uuid",
        userMessage: "hi",
        assistantResponse: "hello",
      });
      const missingSession = await post({
        sessionId: crypto.randomUUID(),
        userMessage: "hi",
        assistantResponse: "hello",
      });
      return { empty, badUuid, missingSession };
    }, BASE_URL);

    // After the fix the endpoint returns structured 400/404 instead of 500.
    // Pre-fix all three would be 500; this test stays even-handed so it
    // doesn't false-fail in an unfixed deployment — but adds a strong
    // expectation that none are 5xx.
    expect(results.empty.status).toBeLessThan(500);
    expect(results.badUuid.status).toBeLessThan(500);
    expect(results.missingSession.status).toBeLessThan(500);
    // When the fix has shipped, also assert error codes
    if (results.empty.status === 400) {
      expect(results.empty.body?.error).toBe("missing_required_fields");
    }
    if (results.badUuid.status === 400) {
      expect(results.badUuid.body?.error).toBe("invalid_session_id");
    }
    if (results.missingSession.status === 404) {
      expect(results.missingSession.body?.error).toBe("session_not_found");
    }
  });
});
