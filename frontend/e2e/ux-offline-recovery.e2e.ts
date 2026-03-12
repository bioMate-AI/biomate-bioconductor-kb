import { setupTestUser } from "./helpers.js";
import { test, expect } from "@playwright/test";

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

test.describe("UX Offline Recovery", () => {
  test("shows and clears offline banner on network transitions", async ({ page }) => {
    await setupTestUser(page, "ux_off");
    await page.goto(BASE_URL);
    await page.waitForLoadState("networkidle");

    const offlineBanner = page.getByTestId("offline-banner");
    await expect(offlineBanner).toHaveCount(0);

    await page.context().setOffline(true);
    await expect(offlineBanner).toBeVisible({ timeout: 10000 });
    await expect(page.getByTestId("offline-retry-guidance")).toBeVisible();

    await page.context().setOffline(false);
    await expect(offlineBanner).toHaveCount(0, { timeout: 10000 });
  });
});
