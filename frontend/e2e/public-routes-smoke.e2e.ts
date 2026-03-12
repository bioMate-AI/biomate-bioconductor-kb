import { test, expect } from "@playwright/test";

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

async function expectNotFound(page: import("@playwright/test").Page) {
  await expect(page.getByText("404 Page Not Found")).toHaveCount(0);
}

test.describe("Public Routes Smoke", () => {
  test("header navigation routes resolve to intended pages", async ({ page }) => {
    await page.goto(`${BASE_URL}/home`);
    await page.waitForLoadState("networkidle");
    await expect(page.getByText("Chat Your Way to")).toBeVisible({ timeout: 15000 });
    await expectNotFound(page);
    const headerNav = page.getByRole("navigation");

    await headerNav.getByRole("button", { name: "About" }).click();
    await expect(page).toHaveURL(/\/about$/);
    await expect(page.getByText("Accelerating biomedical research")).toBeVisible({ timeout: 10000 });
    await expectNotFound(page);

    await headerNav.getByRole("button", { name: "Pricing" }).click();
    await expect(page).toHaveURL(/\/pricing$/);
    await expect(page.getByText("Simple, Usage-Based Pricing")).toBeVisible({ timeout: 10000 });
    await expectNotFound(page);

    await headerNav.getByRole("button", { name: "Blog" }).click();
    await expect(page).toHaveURL(/\/blog$/);
    await expect(page.getByText("BioMate Blog")).toBeVisible({ timeout: 10000 });
    await expectNotFound(page);

    await headerNav.getByRole("button", { name: "Contact" }).click();
    await expect(page).toHaveURL(/\/contact$/);
    await expect(page.getByText("Get in Touch")).toBeVisible({ timeout: 10000 });
    await expectNotFound(page);
  });

  test("footer legal links resolve to legal pages", async ({ page }) => {
    await page.goto(`${BASE_URL}/home`);
    await page.waitForLoadState("networkidle");
    const footer = page.getByRole("contentinfo");

    await footer.getByRole("button", { name: "Privacy Policy" }).click();
    await expect(page).toHaveURL(/\/privacy$/);
    await expect(page.getByRole("heading", { name: "Privacy Policy" })).toBeVisible({ timeout: 10000 });
    await expectNotFound(page);

    await page.goto(`${BASE_URL}/home`);
    await page.waitForLoadState("networkidle");
    await page.getByRole("contentinfo").getByRole("button", { name: "Terms of Service" }).click();
    await expect(page).toHaveURL(/\/terms$/);
    await expect(page.getByRole("heading", { name: "Terms of Service" })).toBeVisible({ timeout: 10000 });
    await expectNotFound(page);
  });
});
