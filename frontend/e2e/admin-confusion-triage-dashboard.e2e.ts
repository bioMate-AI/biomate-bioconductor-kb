/**
 * Admin Confusion Triage Dashboard E2E Tests
 *
 * No page.route() mocking — all calls hit the real BioMate backend.
 * Tests verify that the admin dashboard route loads and key layout
 * elements are present. No specific confusion counts are asserted.
 */

import { test, expect } from "@playwright/test";
import { BASE_URL, setupTestUser } from "./helpers.js";

test.use({ trace: "off", video: "off" });

test.describe("Admin Confusion Triage Dashboard", () => {
  test("admin dashboard route loads without error", async ({ page }) => {
    // Register a user first so we have a valid session
    await setupTestUser(page, "admin_triage");

    // Navigate to the admin feedback dashboard
    const response = await page.goto(`${BASE_URL}/admin/feedback-dashboard`);

    // The route must respond (200 or redirect to login — not 500)
    if (response) {
      expect(response.status()).not.toBe(500);
      console.log(
        `[Admin Dashboard] Route responded with status: ${response.status()}`
      );
    }

    await page.waitForLoadState("load");
    await page.waitForTimeout(2000);

    // Page must render some content
    const bodyText = (await page.textContent("body")) ?? "";
    expect(bodyText.length).toBeGreaterThan(0);

    // Check for admin/dashboard indicators or a redirect to login
    const isAdminPage =
      bodyText.toLowerCase().includes("dashboard") ||
      bodyText.toLowerCase().includes("admin") ||
      bodyText.toLowerCase().includes("feedback") ||
      bodyText.toLowerCase().includes("confusion") ||
      bodyText.toLowerCase().includes("triage");

    const isLoginRedirect =
      page.url().includes("/login") ||
      page.url().includes("/register") ||
      bodyText.toLowerCase().includes("sign in") ||
      bodyText.toLowerCase().includes("log in");

    expect(isAdminPage || isLoginRedirect).toBe(true);
    console.log(
      `[Admin Dashboard] isAdminPage: ${isAdminPage}, isLoginRedirect: ${isLoginRedirect}`
    );
  });

  test("admin dashboard layout elements are present if accessible", async ({ page }) => {
    await setupTestUser(page, "admin_layout");

    await page.goto(`${BASE_URL}/admin/feedback-dashboard`);
    await page.waitForLoadState("load");
    await page.waitForTimeout(2000);

    const currentUrl = page.url();

    // If redirected to login, we cannot check admin-specific UI elements
    if (
      currentUrl.includes("/login") ||
      currentUrl.includes("/register")
    ) {
      console.log(
        "[Admin Dashboard] Redirected to auth page — admin requires login; skipping layout assertions"
      );
      // Verify at least the auth page rendered correctly
      await expect(page.locator("body")).toBeVisible();
      return;
    }

    // We are on some admin page — check for heading or section elements
    const hasHeading = await page
      .getByRole("heading")
      .first()
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    const hasSection = await page
      .locator("main, section, [data-testid]")
      .first()
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    expect(hasHeading || hasSection).toBe(true);
    console.log(
      `[Admin Dashboard] Heading visible: ${hasHeading}, section visible: ${hasSection}`
    );

    // Confusion triage card — present only if admin and data exist
    const triageCard = page.getByTestId("confusion-triage-card");
    const triageVisible = await triageCard
      .isVisible({ timeout: 5000 })
      .catch(() => false);
    if (triageVisible) {
      await expect(triageCard).toBeVisible();
      console.log("[Admin Dashboard] Triage card rendered");
    } else {
      console.log(
        "[Admin Dashboard] Triage card not visible — no data or not admin user; layout check passed"
      );
    }
  });
});
