/**
 * Capture the FAILED after-run block (committee w2-failed-run) via the new
 * DebugAfterRun ?status= param (shipped in 88f65f82e). Uses the real failed
 * crispr run 0cdfde83 (404 at launch). 2x via the pinned deviceScaleFactor.
 */
import { test } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const FAILED_RUN = "0cdfde83-942f-4161-94b5-e972dc43740d";

test("capture failed after-run block (w2-failed-run)", async ({ page }) => {
  test.setTimeout(120_000);
  await loginAsFixture(page);
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto(
    `${BASE_URL}/debug/afterrun/${FAILED_RUN}?status=failed&wf=${encodeURIComponent("nf-core/crisprseq")}`,
    { waitUntil: "domcontentloaded", timeout: 45_000 },
  );
  await page.waitForTimeout(6000); // AfterRunReport + failed block render
  // Tight crop: the failed block (badge + tabs + "Analysis not available" + no-outputs)
  // sits in the top ~470 CSS px; clip to drop the committee-flagged empty space below.
  await page.screenshot({
    path: path.join(ASSETS, "w2-failed-run.png"),
    clip: { x: 0, y: 0, width: 1440, height: 470 },
  });
  // eslint-disable-next-line no-console
  console.log("[failed-capture] wrote w2-failed-run.png");
});
