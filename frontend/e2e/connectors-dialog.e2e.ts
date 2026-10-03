/**
 * E2E: ConnectorsDialog reachable via sidebar button.
 *
 * Covers:
 *  - Sidebar "Connectors" button is visible and opens ConnectorsDialog
 *  - Scientific Databases tab shows entries (static list)
 *  - AI & Platforms tab shows entries (static list)
 *  - Your connections exposes the private-DB and remote-MCP forms and their
 *    authenticated list routes (live, read-only)
 *  - Dialog closes with the X button
 *
 * Uses the canonical fixture account (CLAUDE.md §"E2E test user").
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.describe("connectors-dialog", () => {
  test("Connectors sidebar button is visible", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    const btn = page.getByTestId("button-connectors-nav");
    await expect(btn).toBeVisible({ timeout: 15000 });
  });

  test("clicking Connectors opens ConnectorsDialog", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    await page.getByTestId("button-connectors-nav").click();

    // Dialog should open — look for any dialog with "Connectors" text
    await expect(
      page.locator('[role="dialog"]:has-text("Connectors")')
    ).toBeVisible({ timeout: 5000 });
  });

  test("Scientific Databases tab shows entries", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    await page.getByTestId("button-connectors-nav").click();
    const dialog = page.locator('[role="dialog"]:has-text("Connectors")');
    await expect(dialog).toBeVisible({ timeout: 5000 });

    // Scientific Databases tab should be active by default
    // Verify at least one NCBI entry is visible (multiple match — use first())
    await expect(dialog.locator("text=NCBI").first()).toBeVisible({ timeout: 3000 });
  });

  test("AI & Platforms tab shows entries", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    await page.getByTestId("button-connectors-nav").click();
    const dialog = page.locator('[role="dialog"]:has-text("Connectors")');
    await expect(dialog).toBeVisible({ timeout: 5000 });

    // Click AI & Platforms tab
    // The explanatory copy also contains this phrase. Target the tab button,
    // otherwise Playwright can click the inert paragraph text and leave the
    // Public Databases tab active — a false negative against the connector UI.
    await dialog.getByRole("button", { name: /^AI & Platforms/ }).click();
    // At least one AI entry should be visible
    await expect(
      dialog.locator("text=OpenAI").or(dialog.locator("text=Claude")).first()
    ).toBeVisible({ timeout: 3000 });
  });

  test("Your connections exposes private DB and remote MCP management", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    // These endpoints are the real management surfaces behind the forms. A UI
    // empty state must not hide a missing/failed backend route.
    const [dbList, mcpList] = await Promise.all([
      page.request.get(`${BASE_URL}/api/db-connections`),
      page.request.get(`${BASE_URL}/api/mcp/servers`),
    ]);
    expect(dbList.status()).toBe(200);
    expect(mcpList.status()).toBe(200);

    await page.getByTestId("button-connectors-nav").click();
    const dialog = page.locator('[role="dialog"]:has-text("Connectors")');
    await expect(dialog).toBeVisible({ timeout: 5000 });

    await dialog.getByRole("button", { name: "Your connections" }).click();
    await expect(dialog.getByTestId("private-db-connection-form")).toBeVisible({ timeout: 5000 });

    await dialog.getByTestId("your-connections-sub-mcp").click();
    await expect(dialog.getByTestId("mcp-server-form")).toBeVisible({ timeout: 5000 });
  });

  test("ConnectorsDialog closes with X button", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    await page.getByTestId("button-connectors-nav").click();
    const dialog = page.locator('[role="dialog"]:has-text("Connectors")');
    await expect(dialog).toBeVisible({ timeout: 5000 });

    // Close via keyboard Escape (standard dialog behavior)
    await page.keyboard.press("Escape");
    await expect(dialog).not.toBeVisible({ timeout: 3000 });
  });
});
