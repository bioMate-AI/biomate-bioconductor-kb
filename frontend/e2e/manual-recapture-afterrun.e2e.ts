/**
 * Core-journey AFTER-RUN cluster re-capture (committee bucket C).
 *
 * All from the completed ADMET run fbd72e81 (readable findings) via
 * /debug/afterrun/:runId, which mounts the v2 merged AfterRunReport in
 * completed state. Honest: only completed-state figures come from here
 * (the debug route is completed-only); the failed-state figure is handled
 * separately. deviceScaleFactor=2 → 2× assets.
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 2 });
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const RUN = "fbd72e81-4bb7-488b-9eb8-ff045dad0b3d";

test("after-run completed cluster (Results + Outputs + Reproducibility)", async ({ page }) => {
  test.setTimeout(150_000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string, el?: import("@playwright/test").Locator) => {
    await (el ?? page).screenshot({ path: path.join(ASSETS, name) });
    log.push(`OK   ${name}`);
  };

  await page.goto(BASE_URL + `/debug/afterrun/${RUN}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
  await page.waitForTimeout(6500); // report + findings + lazy previews

  // --- Results tab (findings on top) — context incl. the Results/Reproducibility nav.
  await shot("t3-2-after-run-summary.png");

  // --- Outputs section — scroll to it, viewport crop (TIGHTER than the full tall
  //     element the committee flagged). Shows a few previews in Outputs context.
  const outputs = page.locator('[data-testid="output-files-table"]').first();
  if (await outputs.isVisible({ timeout: 5000 }).catch(() => false)) {
    await outputs.scrollIntoViewIfNeeded().catch(() => {});
    await page.waitForTimeout(1800);
    await shot("r5-outputs.png");
    await shot("t3-3-after-run-outputs.png");
    await shot("i08-1-outputs-tab.png"); // viewport crop = tighter than the 4942px strip
  } else {
    log.push("SKIP r5/t3-3/i08-1 (no outputs table)");
  }

  // --- Reproducibility record tab.
  const rec = page.getByTestId("after-tab-record");
  if ((await rec.count()) > 0) {
    await rec.click({ timeout: 8000 });
    await page.waitForTimeout(2800);
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(500);
    await shot("r6-reproducibility.png");
    await shot("t3-4-after-run-reproducibility.png");
  } else {
    log.push("SKIP r6/t3-4 (no record tab)");
  }

  // eslint-disable-next-line no-console
  console.log("\n[after-run completed cluster]\n" + log.join("\n") + "\n");
  expect(log.some((r) => r.startsWith("OK"))).toBe(true);
});
