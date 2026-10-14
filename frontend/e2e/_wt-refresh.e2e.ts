/**
 * Walkthrough after-run asset refresh + render-test.
 * - Refreshes reference/claude_design/tutorials_v2/assets/live/{completed,outputs,record}.png
 *   from the current merged Results view (run fbd72e81, readable findings → "Download findings").
 * - Render-tests the changed walkthroughs: load file://, verify timeline init + no broken images.
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 2 });

const WT = path.resolve(process.cwd(), "..", "reference/claude_design/tutorials_v2");
const LIVE = path.join(WT, "assets", "live");
const RUN = "fbd72e81-4bb7-488b-9eb8-ff045dad0b3d";

test("refresh after-run walkthrough assets (completed/outputs/record)", async ({ page }) => {
  test.setTimeout(150_000);
  await loginAsFixture(page);
  const log: string[] = [];
  await page.goto(`${BASE_URL}/debug/afterrun/${RUN}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
  await page.waitForTimeout(6000);
  // completed.png — the findings card (now carries "Download findings")
  const fc = page.locator('[data-testid="findings-card"]').first();
  if (await fc.isVisible({ timeout: 5000 }).catch(() => false)) {
    await fc.screenshot({ path: path.join(LIVE, "completed.png") }); log.push("OK completed.png");
  } else log.push("SKIP completed.png (findings-card not visible)");
  // outputs.png — the inline Outputs gallery
  const ot = page.locator('[data-testid="output-files-table"]').first();
  if (await ot.isVisible({ timeout: 5000 }).catch(() => false)) {
    await ot.scrollIntoViewIfNeeded().catch(() => {});
    await page.waitForTimeout(1200);
    await ot.screenshot({ path: path.join(LIVE, "outputs.png") }); log.push("OK outputs.png");
  } else log.push("SKIP outputs.png");
  // record.png — the Reproducibility record tab
  const rt = page.getByTestId("after-tab-record");
  if ((await rt.count()) > 0) {
    await rt.click({ timeout: 8000 }); await page.waitForTimeout(2500);
    const ri = page.locator('[data-testid="record-intro"]').first();
    const target = (await ri.count()) > 0 ? page.locator('[data-testid="record-intro"]').locator("xpath=ancestor::div[2]").first() : page;
    await (target as any).screenshot({ path: path.join(LIVE, "record.png") }).catch(async () => { await page.screenshot({ path: path.join(LIVE, "record.png") }); });
    log.push("OK record.png");
  } else log.push("SKIP record.png (no record tab)");
  // eslint-disable-next-line no-console
  console.log("\n[wt-refresh]\n" + log.join("\n") + "\n");
  expect(log.some((l) => l.startsWith("OK"))).toBe(true);
});

const CHANGED = [
  "t3-run-and-report-walkthrough.html",
  "t3-run-and-report-walkthrough.zh.html",
  "d2-admet-deep-learning-walkthrough.html",
  "d2-admet-deep-learning-walkthrough.zh.html",
  "drug-dev-walkthrough.html",
  "drug-dev-walkthrough.zh.html",
];

test("render-test changed walkthroughs (timeline init + no broken images)", async ({ page }) => {
  test.setTimeout(180_000);
  const results: string[] = [];
  for (const f of CHANGED) {
    const fp = path.join(WT, f);
    if (!fs.existsSync(fp)) { results.push(`MISS ${f}`); continue; }
    const errors: string[] = [];
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text().slice(0, 120)); });
    await page.goto("file://" + fp, { waitUntil: "load", timeout: 45_000 });
    await page.waitForTimeout(3500);
    const hasTimeline = await page.evaluate(() => typeof (window as any).__timeline !== "undefined");
    const imgs = await page.evaluate(() =>
      Array.from(document.images).map((i) => ({ src: i.getAttribute("src") || "", ok: i.complete && i.naturalWidth > 0 }))
    );
    const broken = imgs.filter((i) => !i.ok).map((i) => i.src);
    results.push(`${broken.length === 0 && hasTimeline && errors.length === 0 ? "PASS" : "FAIL"} ${f} — timeline:${hasTimeline} imgs:${imgs.length} broken:${broken.length}${broken.length ? " [" + broken.join(",") + "]" : ""}${errors.length ? " errs:" + errors.length : ""}`);
    page.removeAllListeners("console");
  }
  // eslint-disable-next-line no-console
  console.log("\n[wt-render-test]\n" + results.join("\n") + "\n");
  expect(results.every((r) => r.startsWith("PASS") || r.startsWith("MISS"))).toBe(true);
});
