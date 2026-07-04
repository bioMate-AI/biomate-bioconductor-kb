/**
 * E2E: Project creation via real API.
 *
 * Covers:
 *  - "New Project" button opens CreateProjectDialog
 *  - Submitting a name creates the project via POST /api/projects (not localStorage)
 *  - The created project's ID is returned and the dialog closes
 *  - 401 is returned for unauthenticated project creation attempts
 *
 * Uses the canonical fixture account (CLAUDE.md §"E2E test user").
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const UNIQUE_NAME = `E2E Project ${Date.now()}`;

test.describe("project-create", () => {
  test("POST /api/projects requires auth", async ({ page }) => {
    const res = await page.request.post(`${BASE_URL}/api/projects`, {
      headers: { "Content-Type": "application/json" },
      data: { name: "Unauthorized attempt" },
    });
    // No auth cookie → must be 401
    expect(res.status()).toBe(401);
  });

  test("create project dialog opens from sidebar", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    // Find the "New Project" button in the sidebar projects section
    const newProjectBtn = page.getByTestId("button-new-project");
    await expect(newProjectBtn).toBeVisible({ timeout: 15000 });
    await newProjectBtn.click();

    await expect(page.getByTestId("input-project-name")).toBeVisible({
      timeout: 5000,
    });
  });

  test("project creation calls real API and succeeds", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    // Open CreateProjectDialog
    await page.getByTestId("button-new-project").click();
    await expect(page.getByTestId("input-project-name")).toBeVisible({
      timeout: 5000,
    });

    // Fill in name
    await page.getByTestId("input-project-name").fill(UNIQUE_NAME);

    // Intercept API call to verify it hits the real endpoint
    const apiCallPromise = page.waitForRequest(
      (req) =>
        req.url().includes("/api/projects") && req.method() === "POST"
    );

    // Submit
    await page.getByTestId("button-create-project").click();

    // Verify real API was called (not localStorage)
    const apiCall = await apiCallPromise;
    expect(apiCall.method()).toBe("POST");
    const body = JSON.parse(apiCall.postData() || "{}");
    expect(body.name).toBe(UNIQUE_NAME);

    // Dialog should close on success
    await expect(page.getByTestId("input-project-name")).not.toBeVisible({
      timeout: 10000,
    });
  });

  test("project created via API appears in GET /api/projects list", async ({
    page,
  }) => {
    await loginAsFixture(page);

    const uniqueName = `E2E List Test ${Date.now()}`;

    // Create via API directly
    const res = await page.request.post(`${BASE_URL}/api/projects`, {
      headers: { "Content-Type": "application/json" },
      data: { name: uniqueName },
    });
    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body.project.id).toBeTruthy();
    expect(body.project.name).toBe(uniqueName);

    // Verify it appears in GET list
    const listRes = await page.request.get(`${BASE_URL}/api/projects`);
    expect(listRes.ok()).toBe(true);
    const listBody = await listRes.json();
    const found = listBody.projects.some(
      (p: any) => p.name === uniqueName
    );
    expect(found).toBe(true);
  });
});
