import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const Q = "Predict ADMET properties (hERG, DILI, oral bioavailability) for aspirin CC(=O)OC1=CC=CC=C1C(=O)O and acetaminophen CC(=O)Nc1ccc(O)cc1.";
test("w3-1 EN step row", async ({ page }) => {
  test.setTimeout(600000);
  await loginAsFixture(page);
  await page.setViewportSize({ width: 1600, height: 1100 });
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60000 });
  const input = page.getByTestId("chat-input");
  await input.waitFor({ state: "visible", timeout: 45000 }); await page.waitForTimeout(3000);
  await input.click(); await input.fill(Q);
  const sr = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await sr.waitFor({ state: "visible", timeout: 30000 }); await sr.click();
  const confirm = page.getByRole("button", { name: /confirm.*run/i }).first();
  await confirm.waitFor({ timeout: 200000 });
  await confirm.click({ timeout: 20000 }).catch(async () => confirm.click({ force: true }));
  // open Phases tab
  await page.getByRole("tab", { name: /Phases/i }).click({ timeout: 10000 }).catch(() => {});
  // poll for a completed step (data-status=completed on a step row) up to ~9 min
  let ok = false;
  for (let i = 0; i < 54; i++) {
    const n = await page.locator('[data-status="completed"]').count().catch(() => 0);
    if (n > 0) { ok = true; break; }
    await page.waitForTimeout(10000);
  }
  console.log("[w31] completed step present: " + ok);
  if (ok) {
    await page.waitForTimeout(2000);
    const row = page.locator('[data-status="completed"]').first();
    await row.scrollIntoViewIfNeeded().catch(() => {});
    const box = await row.boundingBox();
    if (box) {
      await page.screenshot({ path: path.join(ASSETS, "w3-1-step-row.png"), clip: { x: Math.max(0, box.x - 10), y: Math.max(0, box.y - 10), width: Math.min(1590, box.width + 20), height: box.height + 20 } });
      console.log("[w31] captured w3-1-step-row.png");
    }
  }
  expect(true).toBe(true);
});
