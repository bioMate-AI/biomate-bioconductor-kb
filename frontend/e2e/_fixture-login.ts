/**
 * Shared E2E fixture login per CLAUDE.md §"E2E test user" and §"E2E plan
 * discipline".
 *
 * Single canonical account: lifeifei163361@163.com. Per-worker cookie cache so
 * successive tests in the same worker reuse ONE login round-trip.
 *
 * Pattern (CLAUDE.md canonical): API login → the browser context holds the
 * `biomate_token` session cookie — exactly what a real browser holds after the
 * login form. The browser then authenticates every same-origin request with
 * that cookie (auth-middleware.ts reads `req.cookies.biomate_token`; the client
 * uses `credentials: 'include'`), and `page.request.*` shares the same cookie jar.
 *
 * 2026-11-12 (audit "Test quality"): this helper used to put
 * `Authorization: Bearer …` (+ x-e2e / x-forwarded-proto) on EVERY request of
 * the context via setExtraHTTPHeaders. Those headers also went to presigned S3
 * URLs, which S3 rejects ("Only one auth mechanism allowed"), so nine specs
 * grew `page.route(/amazonaws\.com/)` header-stripping workarounds. A cookie is
 * scoped to the app's host, so S3 never sees it: no workaround needed.
 *
 * Returns the JWT for the rare spec that must talk to the API from a separate
 * APIRequestContext — prefer `page.request` (cookie session) instead.
 *
 * IMPORTANT per CLAUDE.md §"E2E plan discipline" rule 3: do NOT call
 * `/api/auth/register` from this harness — the fixture user is already
 * registered. Registration round-trip testing belongs in
 * `server/auth-fixes-*.test.ts`, NOT here.
 *
 * WHY page.request.post() not page.evaluate()+fetch(): page.request uses
 * Playwright's HTTP stack, works before the React app has loaded, and stores
 * the server's Set-Cookie in this browser context's cookie jar.
 */
import { type BrowserContext, type Page } from "@playwright/test";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

function readPasswordFile(): string | undefined {
  try {
    const p = path.join(os.homedir(), ".config", "biomate", "e2e_fixture_password");
    const v = fs.readFileSync(p, "utf8").trim();
    return v || undefined;
  } catch {
    return undefined;
  }
}

export const FIXTURE_EMAIL = process.env.E2E_FIXTURE_EMAIL || "lifeifei163361@163.com";
// Never a literal in the repo: env var, else ~/.config/biomate/e2e_fixture_password (CLAUDE.md:
// "do not commit the password"). Missing → a clear failure at login, not a guessed value.
export const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || readPasswordFile() || "";
export const E2E_TOKEN =
  process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
// Precedence: BASE_URL > PLAYWRIGHT_BASE_URL > BIOMATE_URL > localhost (shell BASE_URL must win).
export const BASE_URL = (
  process.env.BASE_URL ||
  process.env.PLAYWRIGHT_BASE_URL ||
  process.env.BIOMATE_URL ||
  "http://localhost:5000"
).replace(/\/+$/, "");
export const SESSION_COOKIE = "biomate_token";

type Cookie = Awaited<ReturnType<BrowserContext["cookies"]>>[number];
let cached: { cookie: Cookie; token: string } | null = null;

/**
 * Plain-HTTP tunnels to a production-mode server (forceHTTPS) need
 * X-Forwarded-Proto. That is a transport concern of the tunnel, not auth, and it
 * only applies when BASE_URL is http on a non-localhost host. An https URL (dev)
 * gets no extra headers from this helper.
 */
async function applyTransport(ctx: BrowserContext): Promise<void> {
  const u = new URL(BASE_URL);
  const local = u.hostname === "localhost" || u.hostname === "127.0.0.1";
  if (u.protocol === "http:" && !local) {
    await ctx.setExtraHTTPHeaders({ "X-Forwarded-Proto": "https", "X-E2E-Test-Token": E2E_TOKEN });
  }
}

export async function loginAsFixture(page: Page): Promise<string> {
  const ctx = page.context();
  await applyTransport(ctx);
  if (cached) {
    await ctx.addCookies([cached.cookie]);
    return cached.token;
  }

  const resp = await page.request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "Content-Type": "application/json", "X-E2E-Test-Token": E2E_TOKEN },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  if (!resp.ok()) {
    const body = await resp.json().catch(() => ({}));
    throw new Error(`loginAsFixture failed (${resp.status()}) for ${FIXTURE_EMAIL}: ${JSON.stringify(body)}`);
  }
  const body = await resp.json();
  const token: string | undefined = body.token;
  if (!token) throw new Error(`loginAsFixture: no token in response for ${FIXTURE_EMAIL}`);

  // The server's own Set-Cookie (httpOnly, sameSite=lax, Secure on https) is now in
  // the context jar. If it is absent (a Secure cookie over a plain-http tunnel), add
  // the same session cookie with the app's flags (Secure only on https).
  let cookie = (await ctx.cookies(BASE_URL)).find((c) => c.name === SESSION_COOKIE && c.value === token);
  if (!cookie) {
    const u = new URL(BASE_URL);
    await ctx.addCookies([{
      name: SESSION_COOKIE, value: token, domain: u.hostname, path: "/",
      httpOnly: true, secure: u.protocol === "https:", sameSite: "Lax",
    }]);
    cookie = (await ctx.cookies(BASE_URL)).find((c) => c.name === SESSION_COOKIE);
  }
  if (!cookie) throw new Error("loginAsFixture: session cookie not set in the browser context");

  // Prove the cookie alone authenticates (no Authorization header anywhere).
  const me = await page.request.get(`${BASE_URL}/api/auth/me`);
  if (!me.ok()) throw new Error(`loginAsFixture: cookie session rejected by /api/auth/me (${me.status()})`);

  cached = { cookie, token };
  return token;
}

export function resetFixtureCache(): void {
  cached = null;
}
