import { test, expect } from "@playwright/test";

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

test.describe("Checkout Flow Smoke", () => {
  test("pricing plan handoff routes to correct checkout plans", async ({ page }) => {
    await page.goto(`${BASE_URL}/pricing`);
    await page.waitForLoadState("networkidle");
    await expect(page.getByText("Simple, Usage-Based Pricing")).toBeVisible({ timeout: 10000 });
    const main = page.getByRole("main");

    // Pro -> /checkout/pro
    await main.getByRole("button", { name: "Start Free Trial" }).first().click();
    await expect(page).toHaveURL(/\/checkout\/pro$/);
    await expect(page.getByRole("heading", { name: "Complete your subscription" })).toBeVisible({
      timeout: 10000,
    });
    await expect(page.getByText("Pro Plan")).toBeVisible({ timeout: 10000 });

    // Team -> /checkout/team
    await page.goto(`${BASE_URL}/pricing`);
    await page.waitForLoadState("networkidle");
    await page.getByRole("main").getByRole("button", { name: "Start Free Trial" }).nth(1).click();
    await expect(page).toHaveURL(/\/checkout\/team$/);
    await expect(page.getByText("Team Plan")).toBeVisible({ timeout: 10000 });
  });

  test("unknown checkout plan falls back to Pro defaults", async ({ page }) => {
    await page.goto(`${BASE_URL}/checkout/unknown`);
    await page.waitForLoadState("networkidle");
    await expect(page.getByRole("heading", { name: "Complete your subscription" })).toBeVisible({
      timeout: 10000,
    });
    await expect(page.getByText("Pro Plan")).toBeVisible({ timeout: 10000 });
    await expect(page.getByText("$49/mo")).toBeVisible({ timeout: 10000 });
  });

  test("checkout submit redirects to dashboard after payment form completion", async ({ page }) => {
    await page.goto(`${BASE_URL}/checkout/pro`);
    await page.waitForLoadState("networkidle");

    await page.locator("#cardNumber").fill("4242 4242 4242 4242");
    await page.locator("#cardName").fill("Dr Test User");
    await page.locator("#expiryDate").fill("12/30");
    await page.locator("#cvv").fill("123");
    await page.locator("#billingAddress").fill("123 Science Ave");
    await page.locator("#city").fill("BioCity");
    await page.locator("#zipCode").fill("94102");
    await page.locator("#country").fill("United States");

    await page.getByRole("main").getByRole("button", { name: "Start Free Trial" }).click();
    await expect(page).toHaveURL(/\/dashboard$/, { timeout: 10000 });
    await expect(page.getByText("Welcome back, Dr. Smith")).toBeVisible({ timeout: 10000 });
  });
});
