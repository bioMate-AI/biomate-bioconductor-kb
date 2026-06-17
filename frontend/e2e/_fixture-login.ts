/**
 * Shared E2E fixture login per CLAUDE.md §"E2E test user" and §"E2E plan
 * discipline".
 *
 * Single canonical account: lifeifei163361@163.com. Per-worker cookie
 * cache so successive tests in the same worker reuse one login round-trip.
 *
 * Pattern: call `loginAsFixture(page)` at the start of any test that needs
 * an authenticated session. Idempotent in-worker.
 *
 * IMPORTANT per CLAUDE.md §"E2E plan discipline" rule 3: do NOT call
 * `/api/auth/register` from this harness — the fixture user is already
 * registered. Calling register costs rate-limit credit at best and 4xx
 * at worst. Registration round-trip testing belongs in
 * `server/auth-fixes-*.test.ts`, NOT here.
 */
import { type Page } from "@playwright/test";

export const FIXTURE_EMAIL = "lifeifei163361@163.com";
export const FIXTURE_PASSWORD =
  process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";
export const E2E_TOKEN =
  process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
export const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

let cachedCookies: any[] | null = null;

async function fetchTokenInBrowser(page: Page): Promise<string | null> {
  return await page.evaluate(
    async ({ baseUrl, email, password, token }) => {
      // Login only — fixture user is already registered (CLAUDE.md rule 3).
      const r = await fetch(`${baseUrl}/api/auth/login`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-E2E-Test-Token": token,
        },
        credentials: "include",
        body: JSON.stringify({ email, password }),
      });
      if (!r.ok) return null;
      const body = await r.json().catch(() => ({}));
      return body.token ?? null;
    },
    {
      baseUrl: BASE_URL,
      email: FIXTURE_EMAIL,
      password: FIXTURE_PASSWORD,
      token: E2E_TOKEN,
    }
  );
}

export async function loginAsFixture(page: Page): Promise<void> {
  if (cachedCookies) {
    await page.context().addCookies(cachedCookies);
    await page.goto(BASE_URL);
    return;
  }
  await page.goto(BASE_URL);
  const token = await fetchTokenInBrowser(page);
  if (!token) {
    throw new Error(
      `loginAsFixture failed for ${FIXTURE_EMAIL} — confirm E2E_FIXTURE_PASSWORD ` +
        `env or that the dev backend has X-E2E-Test-Token bypass enabled.`
    );
  }
  cachedCookies = (await page.context().storageState()).cookies;
  await page.goto(BASE_URL);
}

export function resetFixtureCache(): void {
  cachedCookies = null;
}
