/**
 * E2E: Real two-user team workspace flow.
 *
 * Uses TWO accounts simultaneously:
 *   Owner  — fixture account (lifeifei163361@163.com)
 *   Member — freshly registered throwaway account (e2e-member-<ts>@biomate-test.internal)
 *
 * This proves the actual team features work across account boundaries, not
 * just for a single user calling their own endpoints.
 *
 * Sequence:
 *  TW1  Owner generates a share link for a new project
 *  TW2  Member registers a new account; gets a JWT
 *  TW3  Member sees the public join preview (unauthenticated API)
 *  TW4  Member accepts the invite → project appears in member's /api/projects
 *  TW5  Member appears in owner's member list with role=viewer
 *  TW6  Owner changes member's role to editor
 *  TW7  Member's role in owner's member list reflects the change
 *  TW8  Owner revokes share link; link goes dead but membership persists
 *  TW9  Member still sees the project after link revoked (membership survives)
 *  TW10 Owner removes member; project disappears from member's list
 *  TW11 Removed member cannot rejoin via old (revoked) token
 */
import { test, expect, type Page } from "@playwright/test";
import { loginAsFixture, BASE_URL, E2E_TOKEN } from "./_fixture-login";

let projectId: string;
let shareToken: string;
let memberToken: string;  // JWT for the second user
let memberUserId: string;

const memberEmail = `e2e-member-${Date.now()}@biomate-test.internal`;
const memberPassword = "MemberPass!2026";

// ── Helpers ──────────────────────────────────────────────────────────────────

async function ownerRequest(
  page: Page,
  method: string,
  path: string,
  body?: object
) {
  await loginAsFixture(page);
  return page.request.fetch(`${BASE_URL}${path}`, {
    method,
    headers: { "Content-Type": "application/json" },
    data: body,
  });
}

async function memberRequest(
  page: Page,
  method: string,
  path: string,
  body?: object
) {
  return page.request.fetch(`${BASE_URL}${path}`, {
    method,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${memberToken}`,
      "X-E2E-Test-Token": E2E_TOKEN,
      "X-Forwarded-Proto": "https",
    },
    data: body,
  });
}

// ── Suite ─────────────────────────────────────────────────────────────────────

test.describe.serial("project-team (two-user)", () => {

  // ── TW1: Owner creates project + share link ────────────────────────────────
  test("TW1: owner creates project and generates share link", async ({ page }) => {
    await loginAsFixture(page);

    const proj = await page.request.post(`${BASE_URL}/api/projects`, {
      headers: { "Content-Type": "application/json" },
      data: { name: `E2E Team Test ${Date.now()}` },
    });
    expect(proj.status()).toBe(201);
    projectId = (await proj.json()).project.id;
    expect(projectId).toBeTruthy();

    const link = await page.request.post(
      `${BASE_URL}/api/projects/${projectId}/share-link`,
      { headers: { "Content-Type": "application/json" } }
    );
    expect([200, 201]).toContain(link.status());
    shareToken = (await link.json()).token;
    expect(shareToken.length).toBeGreaterThanOrEqual(24);
  });

  // ── TW2: Register a fresh member account ──────────────────────────────────
  test("TW2: register a fresh member account", async ({ page }) => {
    const res = await page.request.post(`${BASE_URL}/api/auth/register`, {
      headers: { "Content-Type": "application/json" },
      data: {
        email: memberEmail,
        password: memberPassword,
        fullName: "E2E Team Member",
        termsAccepted: true,
      },
    });
    expect(res.status()).toBe(201);
    const body = await res.json();
    memberToken = body.token;
    memberUserId = body.user?.id;
    expect(memberToken).toBeTruthy();
    expect(memberUserId).toBeTruthy();
  });

  // ── TW3: Public join preview — member sees project name without auth ───────
  test("TW3: unauthenticated join preview returns project info", async ({ page }) => {
    const res = await page.request.get(`${BASE_URL}/api/join/${shareToken}`);
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.projectId).toBe(projectId);
    expect(body.projectName).toBeTruthy();
    expect(body.role).toBe("viewer");
  });

  // ── TW4: Member accepts invite → project appears in their list ────────────
  test("TW4: member accepts invite; project appears in their /api/projects", async ({ page }) => {
    const accept = await memberRequest(page, "POST", `/api/join/${shareToken}/accept`);
    expect(accept.ok()).toBe(true);
    const acceptBody = await accept.json();
    expect(acceptBody.projectId).toBe(projectId);

    // Now the project must appear in member's own project list
    const list = await memberRequest(page, "GET", "/api/projects");
    expect(list.ok()).toBe(true);
    const { projects } = await list.json();
    const found = (projects as any[]).find((p: any) => p.id === projectId);
    expect(found).toBeTruthy();
    // userId should be the owner's id, not the member's
    expect(found.userId).not.toBe(memberUserId);
  });

  // ── TW5: Member appears in owner's member list ────────────────────────────
  test("TW5: member appears in owner's member list with role=viewer", async ({ page }) => {
    const res = await ownerRequest(page, "GET", `/api/projects/${projectId}/members`);
    expect(res.ok()).toBe(true);
    const { members } = await res.json();
    const memberRow = (members as any[]).find((m: any) => m.user_id === memberUserId);
    expect(memberRow).toBeTruthy();
    expect(memberRow.role).toBe("viewer");
    expect(memberRow.email).toBe(memberEmail);
  });

  // ── TW6: Owner changes member's role to editor ────────────────────────────
  test("TW6: owner changes member role from viewer to editor", async ({ page }) => {
    const res = await ownerRequest(
      page,
      "PATCH",
      `/api/projects/${projectId}/members/${memberUserId}`,
      { role: "editor" }
    );
    expect(res.ok()).toBe(true);
  });

  // ── TW7: Owner's member list reflects the role change ─────────────────────
  test("TW7: member list shows updated role=editor", async ({ page }) => {
    const res = await ownerRequest(page, "GET", `/api/projects/${projectId}/members`);
    expect(res.ok()).toBe(true);
    const { members } = await res.json();
    const memberRow = (members as any[]).find((m: any) => m.user_id === memberUserId);
    expect(memberRow).toBeTruthy();
    expect(memberRow.role).toBe("editor");
  });

  // ── TW8: Owner revokes share link; link returns 404 ───────────────────────
  test("TW8: owner revokes share link; public preview returns 404", async ({ page }) => {
    const del = await ownerRequest(page, "DELETE", `/api/projects/${projectId}/share-link`);
    expect(del.ok()).toBe(true);

    const preview = await page.request.get(`${BASE_URL}/api/join/${shareToken}`);
    expect(preview.status()).toBe(404);
  });

  // ── TW9: Member still sees project after link revoked (membership survives) ─
  test("TW9: member still sees project after share link revoked", async ({ page }) => {
    const list = await memberRequest(page, "GET", "/api/projects");
    expect(list.ok()).toBe(true);
    const { projects } = await list.json();
    const found = (projects as any[]).find((p: any) => p.id === projectId);
    expect(found).toBeTruthy();
  });

  // ── TW10: Owner removes member; project disappears from member's list ──────
  test("TW10: owner removes member; project disappears from member's list", async ({ page }) => {
    const del = await ownerRequest(
      page,
      "DELETE",
      `/api/projects/${projectId}/members/${memberUserId}`
    );
    expect(del.ok()).toBe(true);

    // Member's project list no longer contains the project
    const list = await memberRequest(page, "GET", "/api/projects");
    expect(list.ok()).toBe(true);
    const { projects } = await list.json();
    const found = (projects as any[]).find((p: any) => p.id === projectId);
    expect(found).toBeUndefined();
  });

  // ── TW11: Removed member cannot rejoin via old (revoked) token ─────────────
  test("TW11: removed member cannot rejoin via revoked token (404)", async ({ page }) => {
    // Token was revoked in TW8; membership was removed in TW10.
    // Trying to accept should fail — token is dead.
    const res = await memberRequest(page, "POST", `/api/join/${shareToken}/accept`);
    expect(res.status()).toBe(404);
  });

  // ── TW12: Member self-leave flow (separate project) ───────────────────────
  test("TW12: member can leave a project they joined via a new active link", async ({ page }) => {
    // Owner creates a new link
    await loginAsFixture(page);
    const newLink = await page.request.post(
      `${BASE_URL}/api/projects/${projectId}/share-link`,
      { headers: { "Content-Type": "application/json" } }
    );
    expect([200, 201]).toContain(newLink.status());
    const newToken = (await newLink.json()).token;

    // Member joins again
    const join = await memberRequest(page, "POST", `/api/join/${newToken}/accept`);
    expect(join.ok()).toBe(true);

    // Member leaves
    const leave = await memberRequest(
      page,
      "DELETE",
      `/api/projects/${projectId}/members/me`
    );
    expect(leave.status()).toBe(200);

    // Project is gone from member's list
    const list = await memberRequest(page, "GET", "/api/projects");
    const { projects } = await list.json();
    expect((projects as any[]).find((p: any) => p.id === projectId)).toBeUndefined();
  });
});
