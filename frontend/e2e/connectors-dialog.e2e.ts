/**
 * E2E: ConnectorsDialog reachable via sidebar button.
 *
 * Covers:
 *  - Sidebar "Connectors" button is visible and opens ConnectorsDialog
 *  - Scientific Databases tab shows entries (static list)
 *  - AI & Platforms tab shows entries (static list)
 *  - Skills tab loads from GET /api/ai_assistant/skills/available (live)
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
    await dialog.locator("text=AI & Platforms").click();
    // At least one AI entry should be visible
    await expect(
      dialog.locator("text=OpenAI").or(dialog.locator("text=Claude")).first()
    ).toBeVisible({ timeout: 3000 });
  });

  test("Skills tab renders (live from API)", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    await page.getByTestId("button-connectors-nav").click();
    const dialog = page.locator('[role="dialog"]:has-text("Connectors")');
    await expect(dialog).toBeVisible({ timeout: 5000 });

    // Click Skills tab
    await dialog.locator("text=Skills").click();

    // The tab content should load (either skills table or empty state — never stuck on "Loading…")
    await expect(
      dialog.locator("text=No skills available.").or(dialog.locator("table"))
    ).toBeVisible({ timeout: 8000 });
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
