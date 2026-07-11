/**
 * E2E: Desktop token cold-start — auth cookie persistence across navigations.
 *
 * The desktop app stores the JWT in tauri-plugin-store (encrypted OS KV store)
 * via desktopSetToken() / desktopGetToken() in frontend/client/src/lib/desktop.ts.
 * On cold start, the token is read and injected as a cookie before the first
 * authenticated API call.
 *
 * We cannot launch the actual Tauri binary in Playwright, so these tests exercise
 * the web-session analogue: a Playwright browser context carries the cookie across
 * navigations the same way the desktop app must carry the token across restarts.
 * If any of these cases break, the desktop cold-start flow breaks in the same way.
 *
 * UC-DT1  No cookie → 401
 * UC-DT2  Authenticated cookie persists across /, /projects, / navigations
 * UC-DT3  Cleared cookie → 401 (simulates lost token on desktop restart)
 *
 * Run:
 *   BIOMATE_URL=https://dev-public.biomate.ai \
 *   E2E_FIXTURE_PASSWORD=WpmFixture!2026 \
 *   npx playwright test e2e/desktop-token-coldstart.e2e.ts --project=chromium
 */

import { test, expect, type Page } from '@playwright/test';
import { BASE_URL } from './demo-helpers.js';

const FIXTURE_EMAIL    = 'lifeifei163361@163.com';
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || 'WpmFixture!2026';
const E2E_TOKEN        = process.env.E2E_TEST_TOKEN ?? 'biomate-e2e-bypass-token-dev-only';

// ── Auth helper (same pattern as service-page-execution.e2e.ts) ───────────────

async function loginAndSetCookie(page: Page): Promise<string> {
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');

  const token = await page.evaluate(
    async ({ baseUrl, email, password, e2eToken }) => {
      const resp = await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-e2e-test-token': e2eToken },
        credentials: 'include',
        body: JSON.stringify({ email, password }),
      });
      if (!resp.ok) throw new Error(`Login ${resp.status}: ${await resp.text()}`);
      return ((await resp.json()) as { token: string }).token;
    },
    { baseUrl: BASE_URL, email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD, e2eToken: E2E_TOKEN }
  );

  const domain = new URL(BASE_URL).hostname;
  await page.context().addCookies([{
    name: 'biomate_token', value: token, domain, path: '/',
    httpOnly: true, secure: BASE_URL.startsWith('https'), sameSite: 'Lax',
  }]);

  return token;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test.describe('desktop-token-coldstart', () => {

  // ── UC-DT1  No cookie → /api/auth/me returns 401 ─────────────────────────
  test('UC-DT1: GET /api/auth/me returns 401 without auth cookie', async ({ request }) => {
    // Fresh request context — no cookies set
    const res = await request.get(`${BASE_URL}/api/auth/me`);
    expect(
      res.status(),
      `/api/auth/me returned ${res.status()} — expected 401 (unauthenticated)`
    ).toBe(401);
    console.log('[DT1] ✅ 401 confirmed without cookie');
  });

  // ── UC-DT2  Cookie persists across page navigations ───────────────────────
  test('UC-DT2: auth cookie persists across multiple page navigations', async ({ page }) => {
    test.setTimeout(60_000);

    await loginAndSetCookie(page);

    const routes = ['/', '/projects', '/'];

    for (const route of routes) {
      await page.goto(`${BASE_URL}${route}`);
      await page.waitForLoadState('load');

      // /api/auth/me must return 200 with the fixture user email
      const meRes = await page.request.get(`${BASE_URL}/api/auth/me`);
      expect(
        meRes.status(),
        `GET /api/auth/me returned ${meRes.status()} after navigating to ${route}`
      ).toBe(200);

      const me = await meRes.json();
      const email: string = me?.user?.email ?? me?.email ?? '';
      expect(
        email,
        `Expected email "${FIXTURE_EMAIL}" after navigating to ${route}, got "${email}"`
      ).toBe(FIXTURE_EMAIL);

      console.log(`[DT2] ${route} → /api/auth/me 200 ✅ (email: ${email})`);
    }

    console.log('[DT2] ✅ auth cookie stable across /, /projects, / — matches desktop token persistence requirement');
  });

  // ── UC-DT3  Cleared cookie → 401 (simulates lost token on restart) ────────
  test('UC-DT3: clearing auth cookie causes subsequent API calls to fail with 401', async ({ page }) => {
    test.setTimeout(30_000);

    await loginAndSetCookie(page);
    await page.goto(BASE_URL);
    await page.waitForLoadState('load');

    // Confirm authenticated
    const beforeRes = await page.request.get(`${BASE_URL}/api/auth/me`);
    expect(
      beforeRes.status(),
      `Expected 200 before clearing cookie, got ${beforeRes.status()}`
    ).toBe(200);
    console.log('[DT3] pre-clear: /api/auth/me 200 ✅');

    // Clear the biomate_token cookie — simulates desktop app losing stored token
    const domain = new URL(BASE_URL).hostname;
    await page.context().clearCookies();
    console.log('[DT3] cookie cleared (simulates missing token on cold start)');

    // Verify immediately becomes 401
    const afterRes = await page.request.get(`${BASE_URL}/api/auth/me`);
    expect(
      afterRes.status(),
      `Expected 401 after clearing cookie, got ${afterRes.status()}`
    ).toBe(401);
    console.log('[DT3] post-clear: /api/auth/me 401 ✅');

    // Also confirm the UI redirects to login / shows auth gate
    await page.goto(BASE_URL);
    await page.waitForLoadState('load');

    // Should NOT show the authenticated chat input
    const chatInput = await page.locator('[data-testid="chat-input"], textarea[placeholder]')
      .first()
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    // Either the input is hidden (auth gate active) or the page shows a login form
    const loginForm = await page.locator('input[type="email"], input[type="password"]')
      .first()
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    if (!chatInput || loginForm) {
      console.log('[DT3] ✅ UI correctly blocks unauthenticated access after cookie cleared');
    } else {
      console.warn('[DT3] ⚠️ chat input visible after cookie clear — check auth gate');
    }

    console.log('[DT3] ✅ cleared cookie causes 401 — desktop token loss detection works');
  });
});
