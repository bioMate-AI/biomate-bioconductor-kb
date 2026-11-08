/**
 * Capture the COMPLETED-state figures from the real ADMET run launched by
 * real-run-capture.e2e.ts (runId below, completed + succeeded, 6 outputs +
 * inline findings). Uses /debug/viewer/:runId which mounts the viewer in
 * completed state — now with REAL findings/outputs (not the empty debug stub).
 */
import { test } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1440, height: 1100 }, deviceScaleFactor: 2 });
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const RUN_ID = process.env.MANUAL_RUN_ID || "c40459b2-4dd0-407e-bbbd-e985df4ce0fc";

test("capture completed ADMET run (findings/outputs/repro/full-step)", async ({ page }) => {
  test.setTimeout(180_000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string) => { await page.screenshot({ path: path.join(ASSETS, name) }); log.push("OK   " + name); };
  const clickText = async (label: RegExp, timeout = 8000) => {
    const el = page.getByText(label, { exact: false }).first();
    if ((await el.count()) > 0) { await el.click({ timeout }); return true; }
    return false;
  };
  try {
    await page.goto(BASE_URL + `/debug/viewer/${RUN_ID}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(6500);
    await shot("r3-completed-summary.png"); // After run → Summary (real findings)

    // Findings card close-up if present.
    const fc = page.getByTestId("findings-card");
    if ((await fc.count()) > 0) { await fc.first().scrollIntoViewIfNeeded().catch(() => {}); await page.waitForTimeout(1200); await shot("r4-findings.png"); }
    else { log.push("SKIP r4-findings (no findings-card)"); }

    // Outputs tab.
    const outTab = page.getByTestId("after-tab-outputs");
    if ((await outTab.count()) > 0) { await outTab.click({ timeout: 8000 }); await page.waitForTimeout(2500); await shot("r5-outputs.png"); }
    else if (await clickText(/^Outputs$/)) { await page.waitForTimeout(2500); await shot("r5-outputs.png"); }
    else log.push("SKIP r5-outputs");

    // Reproducibility record tab.
    const recTab = page.getByTestId("after-tab-record");
    if ((await recTab.count()) > 0) { await recTab.click({ timeout: 8000 }); await page.waitForTimeout(2500); await shot("r6-reproducibility.png"); }
    else if (await clickText(/Reproducibility record/)) { await page.waitForTimeout(2500); await shot("r6-reproducibility.png"); }
    else log.push("SKIP r6-reproducibility");

    // Full step view: Phases tab → a step's Details → full-step-view-dialog.
    if (await clickText(/^Phases$/)) {
      await page.waitForTimeout(2500);
      await shot("r7-phases-completed.png");
      const details = page.getByRole("button", { name: /details|full step/i });
      if ((await details.count()) > 0) {
        await details.first().click({ timeout: 8000 });
        await page.waitForTimeout(3000);
        await shot("w3-1-full-step-view.png");
      } else { log.push("SKIP full step view (no Details button on steps)"); }
    } else { log.push("SKIP phases tab"); }
  } catch (e: any) { log.push("FAIL complete-capture — " + (e?.message?.split("\n")[0] ?? e)); }
  // eslint-disable-next-line no-console
  console.log("\n[real-run-complete]\n" + log.join("\n") + "\n");
});
