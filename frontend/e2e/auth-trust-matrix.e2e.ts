/**
 * C6 — Auth trust matrix.
 *
 * Tests the auth surface a fixture user actually touches:
 *   C6.01 /api/auth/me returns the fixture user after loginAsFixture
 *   C6.02 invalid credentials → 4xx
 *   C6.03 /api/auth/logout clears the cookie (next /me → 4xx or anon)
 *   C6.04 /api/auth/config returns shape (may be auth-gated)
 *   C6.05 register-or-login idempotency
 */
import { test, expect } from "@playwright/test";
import {
  loginAsFixture, FIXTURE_EMAIL, FIXTURE_PASSWORD, E2E_TOKEN, BASE_URL,
  resetFixtureCache,
} from "./_fixture-login.js";

test.describe("Auth trust matrix (C6)", () => {
  test("C6.01 /api/auth/me returns the fixture user", async ({ page }) => {
    await loginAsFixture(page);
    const me = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/auth/me`, { credentials: "include" });
      return { status: r.status, body: await r.json().catch(() => ({})) };
    }, BASE_URL);
    expect(me.status).toBe(200);
    const email = me.body?.email ?? me.body?.user?.email;
    expect(email).toBe(FIXTURE_EMAIL);
  });

  test("C6.02 invalid credentials → 4xx", async ({ page }) => {
    await page.goto(BASE_URL);
    const r = await page.evaluate(
      async ({ base, token, email }) => {
        const resp = await fetch(`${base}/api/auth/login`, {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-E2E-Test-Token": token },
          credentials: "include",
          body: JSON.stringify({ email, password: "definitely-not-the-password-xyz" }),
        });
        return resp.status;
      },
      { base: BASE_URL, token: E2E_TOKEN, email: FIXTURE_EMAIL }
    );
    expect([400, 401, 403]).toContain(r);
  });

  test("C6.03 logout clears the cookie", async ({ page }) => {
    await loginAsFixture(page);
    await page.evaluate(async (base) => {
      await fetch(`${base}/api/auth/logout`, { method: "POST", credentials: "include" });
    }, BASE_URL);
    const after = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/auth/me`, { credentials: "include" });
      return r.status;
    }, BASE_URL);
    expect(after).toBeLessThan(500);
    if (after === 200) {
      const body = await page.evaluate(async (base) => {
        const r = await fetch(`${base}/api/auth/me`, { credentials: "include" });
        return r.ok ? await r.json() : null;
      }, BASE_URL);
      const email = body?.email ?? body?.user?.email;
      expect(email).not.toBe(FIXTURE_EMAIL);
    }
    resetFixtureCache();
  });

  test("C6.04 /api/auth/config returns shape (any non-5xx)", async ({ page }) => {
    await page.goto(BASE_URL);
    const r = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/auth/config`);
      return { status: r.status, body: await r.json().catch(() => ({})) };
    }, BASE_URL);
    expect(r.status).toBeLessThan(500);
    expect(typeof r.body).toBe("object");
  });

  // C6.05 register-or-login idempotency — COVERAGE NOTE:
  //
  // Per CLAUDE.md §"E2E plan discipline" rule 3 (NEVER call
  // /api/auth/register from an e2e harness) and rule 7 (Coverage map >
  // coverage maximalism), this case has been moved out of the e2e
  // matrix. Registration round-trip behaviour is unit-tested at
  // `server/auth-fixes-20260612.test.ts` and `server/auth-service.test.ts`
  // — running it here would only burn registerLimiter credit and slow
  // the matrix down with zero added confidence.
  test.skip("C6.05 register-idempotency — covered by server/auth-fixes-20260612.test.ts", async () => {});
});
