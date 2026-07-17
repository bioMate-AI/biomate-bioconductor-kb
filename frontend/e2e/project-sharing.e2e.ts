/**
 * E2E: Project share link feature.
 *
 * Covers:
 *  PS1 — Owner generates a share token via POST /api/projects/:id/share-link
 *  PS2 — GET /api/projects/:id/share-link returns existing token and role
 *  PS3 — Public /api/join/:token preview returns project metadata (no auth)
 *  PS4 — /join/:token page renders for unauthenticated visitor with auth buttons
 *  PS5 — Authenticated user joins via POST /api/join/:token/accept
 *  PS6 — Owner revokes share link; GET returns null token
 *  PS7 — Revoked token returns 404 on public endpoint
 *
 * Tests run serially because they share projectId / shareToken state.
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

let projectId: string;
let shareToken: string;

test.describe.serial("project-sharing", () => {
  // ── Setup: create a project to share ────────────────────────────────────────
  test.beforeAll(async ({ browser }) => {
    const page = await browser.newPage();
    await loginAsFixture(page);
    const res = await page.request.post(`${BASE_URL}/api/projects`, {
      headers: { "Content-Type": "application/json" },
      data: { name: `E2E Share Test ${Date.now()}` },
    });
    expect(res.status()).toBe(201);
    const body = await res.json();
    projectId = body.project.id;
    await page.close();
  });

  // ── PS1: Generate ────────────────────────────────────────────────────────────
  test("PS1: owner generates a share token", async ({ page }) => {
    await loginAsFixture(page);
    const res = await page.request.post(
      `${BASE_URL}/api/projects/${projectId}/share-link`,
      { headers: { "Content-Type": "application/json" } }
    );
    // 201 on first creation, 200 if token already existed
    expect([200, 201]).toContain(res.status());
    const body = await res.json();
    expect(body.token).toBeTruthy();
    expect(typeof body.token).toBe("string");
    // 18 random bytes → 24-char base64url
    expect(body.token.length).toBeGreaterThanOrEqual(24);
    shareToken = body.token;
  });

  // ── PS2: Read back ───────────────────────────────────────────────────────────
  test("PS2: GET share-link returns existing token and role", async ({
    page,
  }) => {
    await loginAsFixture(page);
    const res = await page.request.get(
      `${BASE_URL}/api/projects/${projectId}/share-link`
    );
    expect(res.ok()).toBe(true);
    const body = await res.json();
    expect(body.token).toBe(shareToken);
    expect(body.role).toBe("viewer");
  });

  // ── PS2b: Idempotent — posting again returns same token ─────────────────────
  test("PS2b: POST share-link again returns the same token (idempotent)", async ({
    page,
  }) => {
    await loginAsFixture(page);
    const res = await page.request.post(
      `${BASE_URL}/api/projects/${projectId}/share-link`,
      { headers: { "Content-Type": "application/json" } }
    );
    expect(res.ok()).toBe(true);
    const body = await res.json();
    expect(body.token).toBe(shareToken);
  });

  // ── PS3: Public preview API ──────────────────────────────────────────────────
  test("PS3: public /api/join/:token returns project metadata without auth", async ({
    page,
  }) => {
    // Deliberately no loginAsFixture — this is the public endpoint
    const res = await page.request.get(`${BASE_URL}/api/join/${shareToken}`);
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.projectId).toBe(projectId);
    expect(body.projectName).toBeTruthy();
    expect(body.role).toBe("viewer");
  });

  // ── PS4: Join-page UI for unauthenticated visitor ───────────────────────────
  test("PS4: /join/:token page shows invite card + auth buttons for anonymous visitor", async ({
    page,
  }) => {
    // No cookies — anonymous context
    await page.goto(`${BASE_URL}/join/${shareToken}`);

    // Invite eyebrow text
    await expect(
      page.getByText("You've been invited to a project")
    ).toBeVisible({ timeout: 15000 });

    // Sign-in CTA
    await expect(page.getByText("Sign in to join")).toBeVisible();

    // Register CTA
    await expect(page.getByText(/Create account/)).toBeVisible();

    // Sign-in button should link to /login?next=...
    const loginBtn = page.getByRole("button", { name: "Sign in to join" });
    await loginBtn.click();
    await expect(page).toHaveURL(/\/login\?next=/, { timeout: 8000 });
  });

  // ── PS5: Authenticated join via API ─────────────────────────────────────────
  test("PS5: authenticated user joins project via accept endpoint", async ({
    page,
  }) => {
    await loginAsFixture(page);
    const res = await page.request.post(
      `${BASE_URL}/api/join/${shareToken}/accept`
    );
    expect(res.ok()).toBe(true);
    const body = await res.json();
    expect(body.projectId).toBe(projectId);
  });

  // ── PS5b: Join is idempotent ─────────────────────────────────────────────────
  test("PS5b: joining twice does not error (idempotent upsert)", async ({
    page,
  }) => {
    await loginAsFixture(page);
    const res = await page.request.post(
      `${BASE_URL}/api/join/${shareToken}/accept`
    );
    expect(res.ok()).toBe(true);
  });

  // ── PS6: Revoke ──────────────────────────────────────────────────────────────
  test("PS6: owner revokes share link; GET returns null token", async ({
    page,
  }) => {
    await loginAsFixture(page);

    const deleteRes = await page.request.delete(
      `${BASE_URL}/api/projects/${projectId}/share-link`
    );
    expect(deleteRes.ok()).toBe(true);

    // GET now returns null
    const getRes = await page.request.get(
      `${BASE_URL}/api/projects/${projectId}/share-link`
    );
    expect(getRes.ok()).toBe(true);
    const body = await getRes.json();
    expect(body.token).toBeNull();
  });

  // ── PS7: Revoked token is dead ───────────────────────────────────────────────
  test("PS7: revoked token returns 404 on public preview endpoint", async ({
    page,
  }) => {
    const res = await page.request.get(`${BASE_URL}/api/join/${shareToken}`);
    expect(res.status()).toBe(404);
  });

  // ── PS8: Non-owner cannot manage the share link ──────────────────────────────
  test("PS8: generate share-link for non-existent project returns 404", async ({
    page,
  }) => {
    await loginAsFixture(page);
    const res = await page.request.post(
      `${BASE_URL}/api/projects/00000000-0000-0000-0000-000000000000/share-link`,
      { headers: { "Content-Type": "application/json" } }
    );
    expect([403, 404]).toContain(res.status());
  });
});
