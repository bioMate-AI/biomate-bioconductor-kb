/** Capture merged After-run "Results" view stills (real completed run) and
 *  refresh the stale 3-tab manual assets. */
import { test } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const RUN = "c79a9ccc-2e9b-4fa6-94ce-a3f54aaaa950"; // completed ADMET run w/ findings + outputs
const ASSETS = "../docs/user-manual/assets";

test("capture merged Results view + refresh manual stills", async ({ page }) => {
  test.setTimeout(150_000);
  await loginAsFixture(page);
  await page.goto(`${BASE_URL}/debug/afterrun/${RUN}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
  await page
    .locator('[data-testid="findings-card"], [data-testid="output-card"]')
    .first()
    .waitFor({ state: "visible", timeout: 60_000 })
    .catch(() => {});
  await page.waitForTimeout(6_000); // findings poll + lazy previews settle

  // Full merged view
  await page.screenshot({ path: `${ASSETS}/r-merged-results-view.png`, fullPage: true });

  // Findings banner crop → the "summary"-type stills
  const findings = page.locator('[data-testid="findings-card"]').first();
  if (await findings.isVisible().catch(() => false)) {
    await findings.screenshot({ path: `${ASSETS}/t3-2-after-run-summary.png` }).catch(() => {});
  }

  // Outputs gallery crop → the "outputs"-type stills (reused in several pages)
  const outputs = page.locator('[data-testid="output-files-table"]').first();
  if (await outputs.isVisible().catch(() => false)) {
    for (const name of ["t3-3-after-run-outputs.png", "r5-outputs.png", "i08-1-outputs-tab.png"]) {
      await outputs.screenshot({ path: `${ASSETS}/${name}` }).catch(() => {});
    }
  }
  console.log(`[stills] findings=${await findings.isVisible().catch(() => false)} outputs=${await outputs.isVisible().catch(() => false)}`);
});
