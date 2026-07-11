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
 *
 * WHY page.request.post() not page.evaluate()+fetch():
 *   On dev (NODE_ENV=production), the server has CSRF protection enabled.
 *   Browser-side fetch (page.evaluate) sends no CSRF token → 500/403.
 *   page.request.post() uses Playwright's HTTP stack (not the browser's)
 *   and bypasses CSRF. It also works regardless of whether the React app
 *   has loaded, avoiding the page.goto hang on macOS 11 / bundled chromium.
 */
import { type Page } from "@playwright/test";

export const FIXTURE_EMAIL = "lifeifei163361@163.com";
export const FIXTURE_PASSWORD =
  process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";
export const E2E_TOKEN =
  process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
export const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

let cachedCookies: any[] | null = null;

export async function loginAsFixture(page: Page): Promise<void> {
  if (cachedCookies) {
    // Re-apply cookies + headers to this context (each test worker gets a
    // fresh browser context so neither are inherited from the prior run).
    await page.context().addCookies(cachedCookies);
    const biomate = cachedCookies.find((c) => c.name === "biomate_token");
    if (biomate?.value) {
      await page.context().setExtraHTTPHeaders({
        Authorization: `Bearer ${biomate.value}`,
        "X-E2E-Test-Token": E2E_TOKEN,
        "X-Forwarded-Proto": "https",
      });
    }
    return;
  }

  // Use page.request (Playwright native HTTP, not in-browser fetch) so this
  // works regardless of whether the React app loads: the production build on
  // dev has deferred resources that prevent the load/domcontentloaded event,
  // causing page.goto + page.evaluate to hang indefinitely.
  const resp = await page.request.post(`${BASE_URL}/api/auth/login`, {
    headers: {
      "Content-Type": "application/json",
      "X-E2E-Test-Token": E2E_TOKEN,
    },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });

  if (!resp.ok()) {
    const body = await resp.json().catch(() => ({}));
    throw new Error(
      `loginAsFixture failed (${resp.status()}) for ${FIXTURE_EMAIL}: ` +
        JSON.stringify(body)
    );
  }

  const body = await resp.json();
  const token: string | undefined = body.token;
  if (!token) {
    throw new Error(
      `loginAsFixture: no token in response for ${FIXTURE_EMAIL}`
    );
  }

  // 1. addCookies → page.request.* picks up biomate_token from the context
  //    cookie jar (page.request uses context cookies, not extraHTTPHeaders).
  const url = new URL(BASE_URL);
  await page.context().addCookies([
    {
      name: "biomate_token",
      value: token,
      domain: url.hostname,
      path: "/",
      httpOnly: false,
      secure: false,
      sameSite: "Lax",
    },
  ]);

  // 2. setExtraHTTPHeaders → browser-initiated fetch/XHR and page.goto send
  //    Authorization so the React app works AND the forceHTTPS middleware
  //    doesn't 301-redirect HTTP tunnel requests.
  await page.context().setExtraHTTPHeaders({
    Authorization: `Bearer ${token}`,
    "X-E2E-Test-Token": E2E_TOKEN,
    "X-Forwarded-Proto": "https",
  });

  cachedCookies = (await page.context().storageState()).cookies;
}

export function resetFixtureCache(): void {
  cachedCookies = null;
}
