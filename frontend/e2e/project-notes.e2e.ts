/**
 * project-notes.e2e.ts — live E2E for the Project Notes (LLM synthesis) surface.
 *
 * Covers the one project-module user path nothing else exercised: the
 * /projects/:id/notes page + GET/POST /api/projects/:id/notes[/refresh]
 * (one LLM call per refresh, ~$0.05 — no AWS Batch).
 *
 * Backend: frontend/server/notes-routes.ts. Page: client/src/pages/project-notes.tsx.
 * Single fixture, single project (per e2e discipline), cleaned up in afterAll.
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.describe.serial("project-notes", () => {
  let projectId = "";
  // A descriptive researchGoal gives the synthesiser real material even with no
  // completed runs yet (loadProjectContext includes project metadata).
  const RESEARCH_GOAL =
    "Bulk RNA-seq differential expression in mouse liver, iptacopan-treated vs " +
    "vehicle control, using nf-core/rnaseq then DESeq2. Focus: complement pathway genes.";

  test.beforeAll(async ({ browser }) => {
    const page = await browser.newPage();
    await loginAsFixture(page);
    const res = await page.request.post(`${BASE_URL}/api/projects`, {
      data: { name: "E2E Notes Synthesis", researchGoal: RESEARCH_GOAL, primaryDomain: "transcriptomics" },
    });
    expect(res.ok(), `create project failed: ${res.status()}`).toBeTruthy();
    projectId = (await res.json()).project.id;
    await page.close();
  });

  test.afterAll(async ({ browser }) => {
    if (!projectId) return;
    const page = await browser.newPage();
    await loginAsFixture(page);
    await page.request.delete(`${BASE_URL}/api/projects/${projectId}`).catch(() => {});
    await page.close();
  });

  test("PN1: GET /notes returns 404 before any synthesis exists", async ({ page }) => {
    await loginAsFixture(page);
    const res = await page.request.get(`${BASE_URL}/api/projects/${projectId}/notes`);
    expect(res.status(), "expected 404 for a project with no synthesis yet").toBe(404);
  });

  test("PN2: notes page renders the empty state", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/projects/${projectId}/notes`, { waitUntil: "load" });
    await expect(page.getByTestId("project-notes-page")).toBeVisible({ timeout: 20_000 });
    // No synthesis yet → empty state + a refresh button, download disabled.
    await expect(page.getByTestId("notes-empty")).toBeVisible({ timeout: 15_000 });
    await expect(page.getByTestId("button-refresh-synthesis")).toBeVisible();
    await expect(page.getByTestId("button-download-md")).toBeDisabled();
  });

  test("PN3: Refresh synthesis triggers an LLM synthesis and renders markdown", async ({ page }) => {
    test.setTimeout(120_000); // LLM call
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/projects/${projectId}/notes`, { waitUntil: "load" });
    await expect(page.getByTestId("project-notes-page")).toBeVisible({ timeout: 20_000 });

    await page.getByTestId("button-refresh-synthesis").click();

    // Content must appear (LLM); if the backend errors it surfaces notes-error.
    const content = page.getByTestId("notes-content");
    const errorBox = page.getByTestId("notes-error");
    await expect(content.or(errorBox)).toBeVisible({ timeout: 90_000 });

    // Assert the happy path: real markdown content, no error.
    await expect(errorBox, "notes synthesis returned an error").toHaveCount(0);
    await expect(content).toBeVisible();
    const text = (await content.textContent()) ?? "";
    expect(text.trim().length, "synthesis content is empty").toBeGreaterThan(40);

    // Download button now enabled; meta timestamp shown.
    await expect(page.getByTestId("button-download-md")).toBeEnabled();
    await expect(page.getByTestId("notes-meta")).toBeVisible();
    console.log(`[PN3] synthesis rendered (${text.trim().length} chars)`);
  });

  test("PN4: GET /notes now returns the saved synthesis", async ({ page }) => {
    await loginAsFixture(page);
    const res = await page.request.get(`${BASE_URL}/api/projects/${projectId}/notes`);
    expect(res.ok(), `expected 200 after refresh, got ${res.status()}`).toBeTruthy();
    const body = await res.json();
    const note = body?.note ?? body;
    expect(note?.content, "no content field in notes response").toBeTruthy();
    expect(String(note.content).length).toBeGreaterThan(40);
  });
});
