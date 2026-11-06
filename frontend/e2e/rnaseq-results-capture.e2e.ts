import { test } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
test("capture RNA-seq DE Results", async ({ page }) => {
  test.setTimeout(120000);
  await loginAsFixture(page);
  await page.setViewportSize({ width: 1440, height: 1100 });
  await page.goto(BASE_URL + "/debug/afterrun/4dbcc0cf-ce6f-4ef0-9c1f-2b98b02343ea", { waitUntil: "domcontentloaded", timeout: 45000 });
  await page.waitForTimeout(10000); // findings load async
  await page.screenshot({ path: path.join(ASSETS, "rnaseq-results.png"), clip: { x: 0, y: 108, width: 1440, height: 600 } });
  console.log("[rnaseq] wrote rnaseq-results.png");
});
