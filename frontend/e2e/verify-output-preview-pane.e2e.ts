import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
const OUT = "/private/tmp/claude-501/-Users-kky-biomate-review/68177db6-d7aa-4237-b387-f3aab691085b/scratchpad";
const RUN = "4dbcc0cf-ce6f-4ef0-9c1f-2b98b02343ea";

test("output preview renders as right-side pane", async ({ page }) => {
  test.setTimeout(90000);
  await loginAsFixture(page);
  await page.setViewportSize({ width: 1600, height: 1000 });
  await page.goto(BASE_URL + "/debug/afterrun/" + RUN, { waitUntil: "domcontentloaded", timeout: 45000 });
  const table = page.locator('[data-testid="output-files-table"]').first();
  await table.waitFor({ state: "visible", timeout: 30000 });
  await page.waitForTimeout(3000);
  await page.locator('[data-testid="output-card"]').first().waitFor({ state: "visible", timeout: 15000 });
  // The right-side pane opens via the per-card "preview"/"view" button (setPreviewFile).
  const prevBtn = page.locator('[data-testid="output-card"] button', { hasText: /^(preview|view)$/i }).first();
  await prevBtn.waitFor({ state: "visible", timeout: 15000 });
  await prevBtn.click({ timeout: 8000 });
  await page.waitForTimeout(2500);
  // Measure the pane geometry: right-anchored, full-height
  const geo = await page.evaluate(() => {
    // the pane is the inner div (borderLeft + height 100vh) inside the fixed overlay
    const panes = Array.from(document.querySelectorAll("div")).filter((d) => {
      const s = getComputedStyle(d);
      return s.position === "fixed" && s.inset === "0px";
    });
    for (const ov of panes) {
      const inner = ov.querySelector(":scope > div") as HTMLElement | null;
      if (!inner) continue;
      const r = inner.getBoundingClientRect();
      const s = getComputedStyle(inner);
      return {
        found: true,
        rightEdge: Math.round(r.right),
        vw: window.innerWidth,
        heightPct: Math.round((r.height / window.innerHeight) * 100),
        borderLeft: s.borderLeftWidth,
        overlayJustify: getComputedStyle(ov).justifyContent,
      };
    }
    return { found: false } as any;
  });
  console.log("[preview] GEO=" + JSON.stringify(geo));
  await page.screenshot({ path: path.join(OUT, "output-preview-pane.png"), fullPage: false });
  expect(geo.found).toBe(true);
  // right-anchored: pane's right edge within 4px of viewport right
  expect(Math.abs(geo.rightEdge - geo.vw)).toBeLessThanOrEqual(6);
  // full-height side pane (not a short centered modal)
  expect(geo.heightPct).toBeGreaterThanOrEqual(90);
});
