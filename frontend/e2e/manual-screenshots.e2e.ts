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
  { name: "i05-0-data-hub.png",     route: "/files",        note: "data hub — project picker (data is project-scoped)" },
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

// Drill into an existing project WITH files (no new run needed) to capture the
// file tree + dataset object + quality tab for I.5. Uses whatever real data the
// fixture already has; each step is best-effort (skips if the DOM differs).
test("capture data-hub drill-in (I.5)", async ({ page }) => {
  test.setTimeout(120_000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string) => {
    await page.screenshot({ path: path.join(ASSETS, name) });
    log.push(`OK   ${name}`);
  };
  try {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto(BASE_URL + "/files", { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(4000);
    // Prefer a project that clearly has files; fall back to the first card.
    const preferred = page.getByText(/E2E File Tree/i).first();
    const target = (await preferred.count()) > 0 ? preferred : page.locator('[data-testid^="project-card"], .cursor-pointer').first();
    await target.click({ timeout: 10_000 });
    await page.waitForTimeout(4000);
    await shot("i05-1-file-tree.png"); // file tree for the chosen project
    // Open a file by its NAME (clicking the row's dot doesn't select) → dataset object.
    const fileName = page.getByText(/\.(fastq|fq|csv|tsv|txt|vcf|bam|h5ad|pdb|json)$/i).first();
    if ((await fileName.count()) > 0) {
      await fileName.click({ timeout: 8_000 });
      await page.waitForTimeout(3500);
      await shot("i05-2-dataset-header.png"); // dataset object header (quality/version)
      const qTab = page.getByTestId("dataset-tab-quality");
      if ((await qTab.count()) > 0) {
        await qTab.click({ timeout: 8_000 });
        await page.waitForTimeout(3000);
        await shot("i05-3-quality-tab.png"); // perception quality panel
      } else { log.push("SKIP i05-3 (no quality tab)"); }
    } else { log.push("SKIP i05-2/3 (no file rows in this project)"); }
  } catch (e: any) {
    log.push(`FAIL drill-in — ${e?.message?.split("\n")[0] ?? e}`);
  }
  // eslint-disable-next-line no-console
  console.log("\n[manual-screenshots drill-in]\n" + log.join("\n") + "\n");
});
