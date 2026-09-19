/**
 * User-manual screenshot capture (see docs/user-manual/assets/README.md).
 *
 * Captures REAL screenshots of the live UI into docs/user-manual/assets/.
 * Honesty rule: only what actually renders is saved; nothing is mocked. Surfaces
 * that need a completed run / profiled data are NOT captured here (kept as
 * placeholders in the chapters) — this pass covers the data-independent surfaces.
 *
 * Run against dev:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     npx playwright test e2e/manual-screenshots.spec.ts --project=chromium
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

// Playwright runs from the frontend/ dir; assets live at ../docs/user-manual/assets.
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");

// Data-independent surfaces (no completed run / profiled dataset required).
const SHOTS: Array<{ name: string; route: string; note: string }> = [
  // Cold start + composer share one surface (composer is at the foot of `/`).
  { name: "i01-1-cold-start.png",   route: "/",             note: "cold start (new-chat empty state): intent bar + module cards + composer" },
  { name: "i05-empty-files.png",    route: "/files",        note: "data hub / file tree" },
  { name: "i10-1-models.png",       route: "/models",       note: "models surface" },
  { name: "i11-1-design.png",       route: "/design",       note: "design & generate surface" },
  { name: "capabilities.png",       route: "/capabilities", note: "capabilities surface" },
];

test("capture data-independent manual surfaces", async ({ page }) => {
  test.setTimeout(180_000);
  await loginAsFixture(page);

  const results: string[] = [];
  for (const shot of SHOTS) {
    try {
      await page.setViewportSize({ width: 1440, height: 900 });
      await page.goto(BASE_URL + shot.route, { waitUntil: "domcontentloaded", timeout: 45_000 });
      // Production build defers resources; give the app a moment to render.
      await page.waitForTimeout(4500);
      // Viewport (above-the-fold) — readable for a manual, unlike a fullPage strip.
      await page.screenshot({ path: path.join(ASSETS, shot.name) });
      results.push(`OK   ${shot.name}  (${shot.route})`);
    } catch (e: any) {
      results.push(`FAIL ${shot.name}  (${shot.route}) — ${e?.message?.split("\n")[0] ?? e}`);
    }
  }
  // eslint-disable-next-line no-console
  console.log("\n[manual-screenshots]\n" + results.join("\n") + "\n");
  // At least the data hub should render for the pass to be meaningful.
  expect(results.some((r) => r.startsWith("OK"))).toBe(true);
});
