/**
 * English UI screenshot audit — captures each user-facing surface on DEV
 * for element-by-element visual audit. Read-only (no writes/dispatches).
 * Run against dev: BIOMATE_URL=https://dev-public.biomate.ai npx playwright test en-ui-audit
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import * as fs from "fs";

const OUT = "/private/tmp/claude-501/-Users-kky-biomate-review/68177db6-d7aa-4237-b387-f3aab691085b/scratchpad/en_audit";
fs.mkdirSync(OUT, { recursive: true });

async function shot(page: any, name: string) {
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: false });
}

test.describe("en-ui-audit", () => {
  test.setTimeout(180000);

  test("capture all English surfaces", async ({ page }) => {
    await loginAsFixture(page);
    await page.setViewportSize({ width: 1440, height: 900 });

    // 1. Home / chat + expanded sidebar
    await page.goto(`${BASE_URL}/`);
    await page.waitForTimeout(2500);
    await shot(page, "01_home_chat");

    // 2. Workflows dialog (sidebar "Workflows")
    try {
      await page.getByTestId("button-workflows-nav").click();
      await page.waitForTimeout(1500);
      await shot(page, "02_workflows_dialog");
      await page.keyboard.press("Escape");
    } catch (e) { console.log("workflows dialog:", e); }

    // 3. Connectors dialog
    try {
      await page.getByTestId("button-connectors-nav").click().catch(async () => {
        await page.getByText("Connectors", { exact: false }).first().click();
      });
      await page.waitForTimeout(1500);
      await shot(page, "03_connectors_dialog");
      // 3b. Your connections tab if present
      const yc = page.getByText("Your connections", { exact: false }).first();
      if (await yc.isVisible().catch(() => false)) {
        await yc.click();
        await page.waitForTimeout(1000);
        await shot(page, "03b_your_connections");
      }
      await page.keyboard.press("Escape");
    } catch (e) { console.log("connectors:", e); }

    // 4. Settings dialog
    try {
      await page.getByText("Settings & API Keys", { exact: false }).first().click();
      await page.waitForTimeout(1500);
      await shot(page, "04_settings_dialog");
      await page.keyboard.press("Escape");
    } catch (e) { console.log("settings:", e); }

    // 5. Runs dashboard (the surface that 404'd in the ZH capture)
    try {
      await page.goto(`${BASE_URL}/dashboard`);
      await page.waitForTimeout(2500);
      await shot(page, "05_runs_dashboard");
    } catch (e) { console.log("dashboard:", e); }

    // 6. CRO library
    try {
      await page.goto(`${BASE_URL}/drug-discovery-cro`);
      await page.waitForTimeout(2500);
      await shot(page, "06_cro_library");
    } catch (e) { console.log("cro:", e); }

    // 7. Billing
    try {
      await page.goto(`${BASE_URL}/billing`);
      await page.waitForTimeout(2500);
      await shot(page, "07_billing");
    } catch (e) { console.log("billing:", e); }

    // 8. IND Report page
    try {
      await page.goto(`${BASE_URL}/`);
      await page.waitForTimeout(1500);
      await page.getByText("IND Report", { exact: false }).first().click().catch(() => {});
      await page.waitForTimeout(1500);
      await shot(page, "08_ind_report");
    } catch (e) { console.log("ind:", e); }

    console.log("SCREENSHOTS WRITTEN TO", OUT);
    expect(fs.readdirSync(OUT).length).toBeGreaterThan(3);
  });
});
