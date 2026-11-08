/**
 * Design & generate capture — runs a REAL /api/generate design round and
 * captures the manual figures that need a completed run:
 *   i11-3-multi-objective.png   the Multi-objective view (now with the A2
 *                               "design goal, not a pass/fail gate" help +
 *                               Verdict-column tooltip, deployed 2026-10-13)
 *   t11-2-design-candidates.png the candidates / ranked rows
 *   t11-3-pareto.png            the Pareto trade-off view (verify the
 *                               non-dominated front actually renders)
 *
 * Honest: nothing mocked; if no candidates come back, the figures are skipped.
 * Run: cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *   npx playwright test e2e/design-capture.e2e.ts --project=chromium --retries=0
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 2 });
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const ASPIRIN = "CC(=O)Oc1ccccc1C(=O)O";

test("capture design multi-objective + pareto (I.11 / T.11)", async ({ page }) => {
  test.setTimeout(420_000); // a real GP design round can take a few minutes
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string, el?: import("@playwright/test").Locator) => {
    await (el ?? page).screenshot({ path: path.join(ASSETS, name) });
    log.push(`OK   ${name}`);
  };

  await page.goto(BASE_URL + "/design", { waitUntil: "domcontentloaded", timeout: 45_000 });
  await expect(page.getByTestId("design-generate")).toBeVisible({ timeout: 30_000 });

  // Seed = aspirin, default envelope. Fill the seed then run.
  const seed = page.getByTestId("dg-seed-smiles");
  if (await seed.isVisible().catch(() => false)) {
    await seed.fill(ASPIRIN);
  }
  await page.getByTestId("dg-run").click({ timeout: 15_000 });
  log.push("clicked dg-run");

  // Wait for a completed run: the Multi-objective view mounts only on results.
  const mobj = page.getByTestId("multi-objective-view");
  try {
    await mobj.waitFor({ state: "visible", timeout: 360_000 });
    log.push("multi-objective-view rendered");
  } catch {
    log.push("FAIL multi-objective-view never rendered (no candidates / run failed)");
    // eslint-disable-next-line no-console
    console.log("\n[design-capture]\n" + log.join("\n") + "\n");
    return;
  }
  await page.waitForTimeout(1500);

  // i11-3 — the whole Multi-objective view card (help line + Verdict tooltip live).
  await mobj.scrollIntoViewIfNeeded().catch(() => {});
  await shot("i11-3-multi-objective.png", mobj);

  // A2 fix sanity: the help line should mention "design goal" (not a pass/fail gate).
  const helpOk = await page.getByText(/design goal, not a pass\/fail gate/i).count().catch(() => 0);
  log.push(helpOk ? "A2 help line present ✓" : "NOTE A2 help line not found in DOM");

  // t11-2 — the candidates/ranked rows (same card; capture it again as the
  // candidates-focused figure so the manual's T.11 ref resolves).
  await shot("t11-2-design-candidates.png", mobj);

  // t11-3 — Pareto trade-off view. Verify the non-dominated front renders.
  const pareto = page.getByTestId("pareto-view");
  if (await pareto.isVisible().catch(() => false)) {
    await pareto.scrollIntoViewIfNeeded().catch(() => {});
    await page.waitForTimeout(800);
    // Count front vs dominated markers if the view tags them.
    const frontCount = await page.locator('[data-testid^="pareto-front"], [data-front="true"], .pareto-front-point').count().catch(() => 0);
    const domCount = await page.locator('[data-dominated="true"], .pareto-dominated-point').count().catch(() => 0);
    log.push(`pareto markers: front=${frontCount} dominated=${domCount}`);
    await shot("t11-3-pareto.png", pareto);
    if (frontCount === 0) log.push("WARN pareto: no non-dominated front markers detected — verify the figure is not all-dominated before wiring into the manual");
  } else {
    log.push("SKIP t11-3 (pareto-view not visible — single-objective run?)");
  }

  // eslint-disable-next-line no-console
  console.log("\n[design-capture]\n" + log.join("\n") + "\n");
});
