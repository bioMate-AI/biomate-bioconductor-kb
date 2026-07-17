/**
 * E2E: Project authorization — what members can/cannot do vs owners.
 *
 * Tests the authorization boundary for every project sub-resource:
 *   AUTHZ1  Member can GET /api/projects/:id (project detail)
 *   AUTHZ2  Member can GET /api/projects/:id/members (member list)
 *   AUTHZ3  Member can GET /api/projects/:id/files  ← was broken: owner-only check
 *   AUTHZ4  Member can GET /api/projects/:id/sessions ← was broken: owner-only check
 *   AUTHZ5  Member CANNOT PATCH /api/projects/:id (update settings)
 *   AUTHZ6  Member CANNOT POST /api/projects/:id/archive
 *   AUTHZ7  Member CANNOT DELETE /api/projects/:id
 *   AUTHZ8  Member CANNOT POST /api/projects/:id/share-link (generate link)
 *   AUTHZ9  Member CANNOT DELETE /api/projects/:id/share-link (revoke link)
 *   AUTHZ10 Member CANNOT PATCH /api/projects/:id/members/:id (change role)
 *   AUTHZ11 Member CANNOT DELETE /api/projects/:id/members/:id (remove other member)
 *   AUTHZ12 Stranger (no membership) gets 404 on /api/projects/:id
 *   AUTHZ13 Stranger gets 404 on /api/projects/:id/files
 *   AUTHZ14 Unauthenticated gets 401 on all project routes
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL, E2E_TOKEN } from "./_fixture-login";

let projectId: string;
let shareToken: string;
let memberToken: string;
let memberUserId: string;
let strangerToken: string;

const memberEmail   = `e2e-authz-member-${Date.now()}@biomate-test.internal`;
const strangerEmail = `e2e-authz-stranger-${Date.now()}@biomate-test.internal`;
const testPassword  = "AuthzTest!2026";

// ── helpers ───────────────────────────────────────────────────────────────────

function memberHeaders() {
  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${memberToken}`,
    "X-E2E-Test-Token": E2E_TOKEN,
    "X-Forwarded-Proto": "https",
  };
}

function strangerHeaders() {
  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${strangerToken}`,
    "X-E2E-Test-Token": E2E_TOKEN,
    "X-Forwarded-Proto": "https",
  };
}

// ── setup ─────────────────────────────────────────────────────────────────────

test.describe.serial("project-authz", () => {
  test.beforeAll(async ({ browser }) => {
    const page = await browser.newPage();

    // 1. Owner creates project + share link
    await loginAsFixture(page);
    const proj = await page.request.post(`${BASE_URL}/api/projects`, {
      headers: { "Content-Type": "application/json" },
      data: { name: `E2E AUTHZ Test ${Date.now()}` },
    });
    expect(proj.status()).toBe(201);
    projectId = (await proj.json()).project.id;

    const link = await page.request.post(
      `${BASE_URL}/api/projects/${projectId}/share-link`,
      { headers: { "Content-Type": "application/json" } }
    );
    expect([200, 201]).toContain(link.status());
    shareToken = (await link.json()).token;

    // 2. Register member + stranger accounts
    const regMember = await page.request.post(`${BASE_URL}/api/auth/register`, {
      headers: { "Content-Type": "application/json" },
      data: { email: memberEmail, password: testPassword, fullName: "AUTHZ Member", termsAccepted: true },
    });
    expect(regMember.status()).toBe(201);
    const memberBody = await regMember.json();
    memberToken   = memberBody.token;
    memberUserId  = memberBody.user.id;

    const regStranger = await page.request.post(`${BASE_URL}/api/auth/register`, {
      headers: { "Content-Type": "application/json" },
      data: { email: strangerEmail, password: testPassword, fullName: "AUTHZ Stranger", termsAccepted: true },
    });
    expect(regStranger.status()).toBe(201);
    strangerToken = (await regStranger.json()).token;

    // 3. Member joins the project
    const join = await page.request.fetch(`${BASE_URL}/api/join/${shareToken}/accept`, {
      method: "POST",
      headers: memberHeaders(),
    });
    expect(join.ok()).toBe(true);

    await page.close();
  });

  // ── AUTHZ1: Member can fetch the project ─────────────────────────────────
  test("AUTHZ1: member can GET project detail", async ({ page }) => {
    const res = await page.request.fetch(`${BASE_URL}/api/projects/${projectId}`, {
      method: "GET", headers: memberHeaders(),
    });
    expect(res.ok()).toBe(true);
    const body = await res.json();
    expect(body.project.id).toBe(projectId);
    expect(body.isOwner).toBe(false);
  });

  // ── AUTHZ2: Member can list members ──────────────────────────────────────
  test("AUTHZ2: member can GET member list", async ({ page }) => {
    const res = await page.request.fetch(`${BASE_URL}/api/projects/${projectId}/members`, {
      method: "GET", headers: memberHeaders(),
    });
    expect(res.ok()).toBe(true);
    const { members } = await res.json();
    expect(Array.isArray(members)).toBe(true);
    expect(members.some((m: any) => m.user_id === memberUserId)).toBe(true);
  });

  // ── AUTHZ3: Member can list files ─────────────────────────────────────────
  test("AUTHZ3: member can GET project files list", async ({ page }) => {
    const res = await page.request.fetch(`${BASE_URL}/api/projects/${projectId}/files`, {
      method: "GET", headers: memberHeaders(),
    });
    // Must be 200 (empty list is fine) — NOT 404
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(Array.isArray(body.files)).toBe(true);
  });

  // ── AUTHZ4: Member can list sessions ──────────────────────────────────────
  test("AUTHZ4: member can GET project sessions", async ({ page }) => {
    const res = await page.request.fetch(`${BASE_URL}/api/projects/${projectId}/sessions`, {
      method: "GET", headers: memberHeaders(),
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(Array.isArray(body.sessions)).toBe(true);
  });

  // ── AUTHZ5: Member CANNOT update project settings ─────────────────────────
  test("AUTHZ5: member CANNOT PATCH project settings (404)", async ({ page }) => {
    const res = await page.request.fetch(`${BASE_URL}/api/projects/${projectId}`, {
      method: "PATCH",
      headers: memberHeaders(),
      data: { name: "Hijacked Name" },
    });
    expect([403, 404]).toContain(res.status());
  });

  // ── AUTHZ6: Member CANNOT archive project ────────────────────────────────
  test("AUTHZ6: member CANNOT archive project (404)", async ({ page }) => {
    const res = await page.request.fetch(`${BASE_URL}/api/projects/${projectId}/archive`, {
      method: "POST", headers: memberHeaders(),
    });
    expect([403, 404]).toContain(res.status());
  });

  // ── AUTHZ7: Member CANNOT delete project ─────────────────────────────────
  test("AUTHZ7: member CANNOT DELETE project (404)", async ({ page }) => {
    const res = await page.request.fetch(`${BASE_URL}/api/projects/${projectId}`, {
      method: "DELETE", headers: memberHeaders(),
    });
    expect([403, 404]).toContain(res.status());
  });

  // ── AUTHZ8: Member CANNOT generate a new share link ──────────────────────
  test("AUTHZ8: member CANNOT POST share-link (403/404)", async ({ page }) => {
    const res = await page.request.fetch(`${BASE_URL}/api/projects/${projectId}/share-link`, {
      method: "POST", headers: memberHeaders(),
    });
    expect([403, 404]).toContain(res.status());
  });

  // ── AUTHZ9: Member CANNOT revoke the share link ──────────────────────────
  test("AUTHZ9: member CANNOT DELETE share-link (403/404)", async ({ page }) => {
    const res = await page.request.fetch(`${BASE_URL}/api/projects/${projectId}/share-link`, {
      method: "DELETE", headers: memberHeaders(),
    });
    expect([403, 404]).toContain(res.status());
  });

  // ── AUTHZ10: Member CANNOT change another member's role ──────────────────
  test("AUTHZ10: member CANNOT PATCH another member's role (403/404)", async ({ page }) => {
    const res = await page.request.fetch(
      `${BASE_URL}/api/projects/${projectId}/members/${memberUserId}`,
      { method: "PATCH", headers: memberHeaders(), data: { role: "editor" } }
    );
    expect([403, 404]).toContain(res.status());
  });

  // ── AUTHZ11: Member CANNOT remove another member ─────────────────────────
  test("AUTHZ11: member CANNOT DELETE another member (403/404)", async ({ page }) => {
    // Try to remove themselves via the owner-remove endpoint (not /me)
    const res = await page.request.fetch(
      `${BASE_URL}/api/projects/${projectId}/members/${memberUserId}`,
      { method: "DELETE", headers: memberHeaders() }
    );
    expect([403, 404]).toContain(res.status());
  });

  // ── AUTHZ12: Stranger (no membership) gets 404 on project detail ──────────
  test("AUTHZ12: stranger gets 404 on project they never joined", async ({ page }) => {
    const res = await page.request.fetch(`${BASE_URL}/api/projects/${projectId}`, {
      method: "GET", headers: strangerHeaders(),
    });
    expect(res.status()).toBe(404);
  });

  // ── AUTHZ13: Stranger gets 404 on project files ───────────────────────────
  test("AUTHZ13: stranger gets 404 on project files", async ({ page }) => {
    const res = await page.request.fetch(`${BASE_URL}/api/projects/${projectId}/files`, {
      method: "GET", headers: strangerHeaders(),
    });
    expect(res.status()).toBe(404);
  });

  // ── AUTHZ14: Unauthenticated gets 401 everywhere ──────────────────────────
  test("AUTHZ14: unauthenticated requests get 401", async ({ page }) => {
    const noAuth = { "Content-Type": "application/json", "X-E2E-Test-Token": E2E_TOKEN };
    const routes = [
      ["GET",    `/api/projects/${projectId}`],
      ["GET",    `/api/projects/${projectId}/files`],
      ["GET",    `/api/projects/${projectId}/sessions`],
      ["GET",    `/api/projects/${projectId}/members`],
      ["POST",   `/api/projects/${projectId}/share-link`],
    ];
    for (const [method, path] of routes) {
      const res = await page.request.fetch(`${BASE_URL}${path}`, { method, headers: noAuth });
      expect([401, 403]).toContain(res.status());
    }
  });
});
