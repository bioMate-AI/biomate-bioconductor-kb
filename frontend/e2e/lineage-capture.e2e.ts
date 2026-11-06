/**
 * Capture the dataset-object + LINEAGE/versions figures for T10, using an ADMET
 * run output that was saved into an active project (so it has provenance back to
 * run c40459b2). Active project → useActiveProject won't clear it; deep-link
 * /files?file=<id> opens the DatasetObject.
 */
import { test } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 2 });
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const PROJECT_ID = process.env.PROJECT_ID || "060f8039-f0b0-46fb-bd87-3047b4c8e5f8";
const FILE_ID = process.env.FILE_ID || "8f0a2fb9-31af-4baa-8052-5dd3ca0dbb24"; // predict_admet_properties_results.json

test("capture dataset lineage/versions (T10)", async ({ page }) => {
  test.setTimeout(150_000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string) => { await page.screenshot({ path: path.join(ASSETS, name) }); log.push("OK   " + name); };
  const tab = async (tid: string, name: string) => {
    const t = page.getByTestId(tid);
    if ((await t.count()) > 0) { await t.first().click({ timeout: 8000 }); await page.waitForTimeout(3000); await shot(name); return true; }
    log.push("SKIP " + tid); return false;
  };
  try {
    await page.addInitScript((pid) => { try { localStorage.setItem("biomate-active-project-id", pid as string); } catch { /* ignore */ } }, PROJECT_ID);
    await page.goto(BASE_URL + `/files?file=${FILE_ID}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(6000);
    const obj = page.getByTestId("dataset-object");
    if ((await obj.count()) === 0) { log.push("SKIP dataset-object did not mount"); }
    else {
      await shot("t10-0-dataset-object.png");            // header / metadata
      await tab("dataset-tab-preview", "t10-1-dataset-preview.png");
      await tab("dataset-tab-lineage", "t10-2-dataset-lineage.png");   // Produced by run c40459b2
      await tab("dataset-tab-consumers", "t10-3-dataset-consumers.png");
      await tab("dataset-tab-versions", "t10-4-dataset-versions.png");
      await tab("dataset-tab-origin", "t10-5-dataset-origin.png");
    }
  } catch (e: any) { log.push("FAIL lineage-capture — " + (e?.message?.split("\n")[0] ?? e)); }
  // eslint-disable-next-line no-console
  console.log("\n[lineage-capture]\n" + log.join("\n") + "\n");
});
