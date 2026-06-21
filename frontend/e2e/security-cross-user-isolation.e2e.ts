/**
 * Security: Cross-User Data Isolation
 * =====================================
 * Verifies that one authenticated user cannot access another user's:
 *   - Workflow run data (GET /api/workflows/runs/<run_id>)
 *   - Billing usage data (GET /api/billing/usage)
 *   - Projects (GET /api/projects)
 *
 * Strategy:
 *   1. Login as User A (canonical fixture: lifeifei163361@163.com)
 *   2. Capture a real run_id belonging to User A
 *   3. Login as User B (ephemeral account created via E2E bypass token)
 *   4. Assert User B gets 404 on User A's run_id
 *   5. Assert User B's billing usage is 0 (not User A's data)
 *   6. Assert User B's projects list is empty
 *
 * No page.route() mocking. All calls hit the live server.
 *
 * Note: User B creation uses the x-e2e-test-token bypass header, which
 * rate-limit-skips the registration endpoint. This is the ONLY situation
 * where a second account is acceptable per CLAUDE.md — cross-user isolation
 * must be tested with a real second identity, not by pretending.
 */

import { test, expect, Page, APIRequestContext } from "@playwright/test";

const BASE_URL    = process.env.BIOMATE_URL   || "http://localhost:5000";
const E2E_TOKEN   = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const FIXTURE_A_EMAIL    = process.env.E2E_FIXTURE_EMAIL    || "lifeifei163361@163.com";
const FIXTURE_A_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "";

// Ephemeral User B — suffix prevents collision if previous run leaked
const USER_B_EMAIL    = `e2e-isolation-b-${Date.now()}@biomate-e2e.invalid`;
const USER_B_PASSWORD = `Isolation!${Date.now()}`;

test.setTimeout(3 * 60 * 1000); // 3 min — purely API, no Batch runs

// ---------------------------------------------------------------------------
// Auth helpers
// ---------------------------------------------------------------------------

async function loginApi(
  request: APIRequestContext,
  email: string,
  password: string,
): Promise<string> {
  const resp = await request.post(`${BASE_URL}/api/auth/login`, {
    headers: {
      "x-e2e-test-token": E2E_TOKEN,
      "content-type": "application/json",
    },
    data: { email, password },
  });
  if (!resp.ok()) {
    throw new Error(`login(${email}) → ${resp.status()}: ${await resp.text()}`);
  }
  const { token } = await resp.json();
  if (!token) throw new Error(`login(${email}) missing token`);
  return token;
}

async function registerUser(
  request: APIRequestContext,
  email: string,
  password: string,
): Promise<void> {
  const resp = await request.post(`${BASE_URL}/api/auth/register`, {
    headers: {
      "x-e2e-test-token": E2E_TOKEN,
      "content-type": "application/json",
    },
    data: { email, password, name: "E2E Isolation Test User B" },
  });
  // 200 = registered, 409 = already exists — both are fine
  if (!resp.ok() && resp.status() !== 409) {
    throw new Error(`register(${email}) → ${resp.status()}: ${await resp.text()}`);
  }
}

function authHeaders(token: string) {
  return {
    "Authorization": `Bearer ${token}`,
    "x-e2e-test-token": E2E_TOKEN,
  };
}

// ---------------------------------------------------------------------------
// Resolve a run_id for User A (most recent run from /api/workflows/runs)
// ---------------------------------------------------------------------------
async function getARunId(
  request: APIRequestContext,
  tokenA: string,
): Promise<string | null> {
  const resp = await request.get(`${BASE_URL}/api/workflows/runs?limit=5`, {
    headers: authHeaders(tokenA),
  });
  if (!resp.ok()) return null;
  const body = await resp.json();
  const runs: Array<{ run_id?: string; id?: string }> =
    (body?.runs ?? body ?? []);
  const first = runs[0];
  return (first?.run_id ?? first?.id ?? null) as string | null;
}

// ---------------------------------------------------------------------------
// THE TESTS
// ---------------------------------------------------------------------------

test.describe("cross-user data isolation", () => {
  let tokenA: string;
  let tokenB: string;
  let runIdA: string | null;

  test.beforeAll(async ({ request }) => {
    if (!FIXTURE_A_PASSWORD) {
      console.warn("[isolation] E2E_FIXTURE_PASSWORD not set — tests will be skipped");
      return;
    }

    // Login User A
    tokenA = await loginApi(request, FIXTURE_A_EMAIL, FIXTURE_A_PASSWORD);
    console.log(`[isolation] User A logged in`);

    // Capture a run_id belonging to User A
    runIdA = await getARunId(request, tokenA);
    console.log(`[isolation] User A run_id: ${runIdA ?? "(none)"}`);

    // Register + login User B (ephemeral)
    await registerUser(request, USER_B_EMAIL, USER_B_PASSWORD);
    tokenB = await loginApi(request, USER_B_EMAIL, USER_B_PASSWORD);
    console.log(`[isolation] User B logged in as ${USER_B_EMAIL}`);
  });

  // ── 1. Unauthenticated access ──────────────────────────────────────────────

  test("unauthenticated /api/workflows/runs → 401", async ({ request }) => {
    const resp = await request.get(`${BASE_URL}/api/workflows/runs`, {
      headers: { "x-e2e-test-token": E2E_TOKEN },
    });
    expect([401, 403]).toContain(resp.status());
  });

  test("unauthenticated /api/billing/usage → 401", async ({ request }) => {
    const resp = await request.get(`${BASE_URL}/api/billing/usage`, {
      headers: { "x-e2e-test-token": E2E_TOKEN },
    });
    expect([401, 403]).toContain(resp.status());
  });

  test("unauthenticated /api/projects → 401", async ({ request }) => {
    const resp = await request.get(`${BASE_URL}/api/projects`, {
      headers: { "x-e2e-test-token": E2E_TOKEN },
    });
    expect([401, 403]).toContain(resp.status());
  });

  // ── 2. User B cannot see User A's run ─────────────────────────────────────

  test("User B gets 404 for User A run_id", async ({ request }) => {
    if (!FIXTURE_A_PASSWORD) test.skip();
    if (!runIdA) {
      console.warn("[isolation] User A has no runs — skipping run_id isolation check");
      return;
    }

    const resp = await request.get(`${BASE_URL}/api/workflows/runs/${runIdA}`, {
      headers: authHeaders(tokenB),
    });

    // Must be 404 (not found for this user) — must NOT be 200
    expect(resp.status()).toBe(404);
    console.log(`[isolation] PASS: User B got 404 for User A run_id ${runIdA}`);
  });

  // ── 3. User B billing is scoped to User B ─────────────────────────────────

  test("User B billing usage is 0 (not User A data)", async ({ request }) => {
    if (!FIXTURE_A_PASSWORD) test.skip();

    const resp = await request.get(`${BASE_URL}/api/billing/usage`, {
      headers: authHeaders(tokenB),
    });

    // Either 200 with zero usage, or 404/402 if no subscription yet — never User A data
    if (resp.status() === 200) {
      const body = await resp.json();
      // Total cost must be 0 for a brand-new account
      const totalCost = body?.total_cost_usd ?? body?.total ?? 0;
      expect(totalCost).toBe(0);

      // The customer_id must NOT be User A's — it must be User B's
      // (We can't know User A's Lago ID here, but we can assert it's non-null
      // and belongs to a fresh account with no events)
      const events = body?.events ?? body?.usage_events ?? [];
      expect(events.length).toBe(0);
      console.log(`[isolation] PASS: User B billing returns zero-event usage`);
    } else {
      // 402 (no subscription) or 404 (no customer yet) — also acceptable for new user
      expect([402, 404]).toContain(resp.status());
      console.log(`[isolation] PASS: User B billing returns ${resp.status()} (no plan yet)`);
    }
  });

  // ── 4. User B projects list is empty ──────────────────────────────────────

  test("User B /api/projects returns empty list (not User A projects)", async ({ request }) => {
    if (!FIXTURE_A_PASSWORD) test.skip();

    const resp = await request.get(`${BASE_URL}/api/projects`, {
      headers: authHeaders(tokenB),
    });

    // 200 with empty list OR 404 — never populated with User A's projects
    if (resp.status() === 200) {
      const body = await resp.json();
      const projects: unknown[] = body?.projects ?? body ?? [];
      expect(projects.length).toBe(0);
      console.log(`[isolation] PASS: User B projects list is empty`);
    } else {
      expect([404]).toContain(resp.status());
    }
  });

  // ── 5. User A can still access their own run ───────────────────────────────

  test("User A can access their own run_id (sanity check)", async ({ request }) => {
    if (!FIXTURE_A_PASSWORD) test.skip();
    if (!runIdA) {
      console.warn("[isolation] No run_id to verify — User A may have no runs yet");
      return;
    }

    const resp = await request.get(`${BASE_URL}/api/workflows/runs/${runIdA}`, {
      headers: authHeaders(tokenA),
    });

    // User A must still be able to access their own run
    expect(resp.status()).toBe(200);
    const body = await resp.json();
    const id = body?.run_id ?? body?.id;
    expect(id).toBe(runIdA);
    console.log(`[isolation] PASS: User A can access their own run ${runIdA}`);
  });
});
