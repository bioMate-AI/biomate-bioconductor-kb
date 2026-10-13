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

// HIGH-DPI: the old pass captured at deviceScaleFactor=1 → blurry manual figures
// (see docs/20260922_USER_MANUAL_SCREENSHOT_AUDIT.md). deviceScaleFactor must be
// set at CONTEXT creation (setViewportSize can't change it), so it lives here.
// 2× renders the default chrome at effectively 2880px wide → crisp at print size.
test.use({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });

// Playwright runs from the frontend/ dir; assets live at ../docs/user-manual/assets.
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");

// Data-independent surfaces (no completed run / profiled dataset required).
const SHOTS: Array<{ name: string; route: string; note: string }> = [
  // Cold start + composer share one surface (composer is at the foot of `/`).
  { name: "i01-1-cold-start.png",   route: "/",                  note: "cold start (new-chat empty state): intent bar + module cards + composer" },
  { name: "i05-0-data-hub.png",     route: "/files",             note: "data hub — project picker (data is project-scoped)" },
  { name: "i10-1-models.png",       route: "/models",            note: "models surface" },
  { name: "i11-1-design.png",       route: "/design",            note: "design & generate surface" },
  { name: "capabilities.png",       route: "/capabilities",      note: "capabilities surface" },
  { name: "i13-1-cro-library.png",  route: "/drug-discovery-cro", note: "CRO library / drug-discovery campaigns" },
];

test("capture data-independent manual surfaces", async ({ page }) => {
  test.setTimeout(180_000);
  await loginAsFixture(page);

  const results: string[] = [];
  for (const shot of SHOTS) {
    try {
      // i01 cold-start is element-cropped to the content column (see below), which
      // needs a wider viewport so the column alone (viewport − 224px sidebar) is
      // ≥1440 CSS → ≥2880px at 2× DPR. Other (full-page) shots stay at 1440.
      const wide = shot.name.startsWith("i01-");
      await page.setViewportSize(wide ? { width: 1680, height: 1050 } : { width: 1440, height: 900 });
      await page.goto(BASE_URL + shot.route, { waitUntil: "domcontentloaded", timeout: 45_000 });
      // Production build defers resources; give the app a moment to render.
      await page.waitForTimeout(4500);
      // Viewport (above-the-fold) — readable for a manual, unlike a fullPage strip.
      // i01 cold-start: crop the PlatformLayout content column (the flex-1 div that
      // is the sibling right after the expanded sidebar) to drop the fixture-
      // polluted sidebar (many E2E/duplicate projects) + dead space (committee
      // bucket B). This route has NO <main> (the old locator("main") crop fell back
      // to full page and kept the sidebar). Falls back to page if not found.
      const content = page.locator('[data-testid="platform-sidebar"] + div');
      const tgt = wide && (await content.count().catch(() => 0)) > 0 ? content.first() : page;
      await tgt.screenshot({ path: path.join(ASSETS, shot.name) });
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
  // Crop the PlatformLayout content column (the flex-1 div that is the sibling
  // right after the expanded sidebar) to drop the fixture-polluted sidebar + dead
  // space (committee bucket B). This route has NO <main>, so the old
  // locator("main") crop fell back to full page and kept the sidebar. Falls back
  // to page if the content column isn't found.
  const shot = async (name: string) => {
    const content = page.locator('[data-testid="platform-sidebar"] + div');
    const target = (await content.count().catch(() => 0)) > 0 ? content.first() : page;
    await target.screenshot({ path: path.join(ASSETS, name) });
    log.push(`OK   ${name}`);
  };
  try {
    // Wide so the content column alone is ≥2880px at 2× DPR (high-res requirement).
    await page.setViewportSize({ width: 1680, height: 1050 });
    await page.goto(BASE_URL + "/files", { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(4000);
    // Target the CLEAN reader-facing demo project by name (committee bucket B:
    // avoid the "E2E File Tree 1789…" fixture name in the breadcrumb). Falls back
    // to the old E2E project, then the first card.
    const clean = page.getByText("MG PBMC — sample data demo").first();
    const preferred = (await clean.count()) > 0 ? clean : page.getByText(/E2E File Tree/i).first();
    const target = (await preferred.count()) > 0 ? preferred : page.locator('[data-testid^="project-card"], .cursor-pointer').first();
    await target.click({ timeout: 10_000 });
    await page.waitForTimeout(4000);
    await shot("i05-1-file-tree.png"); // file tree for the chosen project
    // Open a file by its NAME (clicking the row's dot doesn't select) → dataset object.
    // Prefer a REAL demo dataset (the counts matrix / a CSV) so the figure shows a
    // working table preview — not the internal preview_checks.json, whose preview
    // 400s and would put a red "Cannot read file" error in the manual (committee
    // bucket B: wrong content captured). Falls back to any previewable file.
    const demoData = page.getByText(/counts_matrix|sample_metadata|contrasts/i).first();
    const fileName = (await demoData.count()) > 0 ? demoData
      : page.getByText(/\.(fastq|fq|csv|tsv|txt|vcf|bam|h5ad|pdb|json)$/i).first();
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

// Capture the run-dependent after-run report from an EXISTING completed run
// (no fresh Batch run) via /debug/afterrun/:runId, which mounts the v2
// AfterRunReport (the MERGED "Results" view) in completed state. Set
// MANUAL_RUN_ID to a run that has findings + outputs. Default = the ADMET run.
const RUN_ID = process.env.MANUAL_RUN_ID || "c79a9ccc-2e9b-4fa6-94ce-a3f54aaaa950";
test("capture after-run report from an existing run (I.6/I.8/I.9)", async ({ page }) => {
  test.setTimeout(150_000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string, el?: import("@playwright/test").Locator) => {
    await (el ?? page).screenshot({ path: path.join(ASSETS, name) });
    log.push(`OK   ${name}`);
  };
  const clickTab = async (testid: string) => {
    const t = page.getByTestId(testid);
    if ((await t.count()) > 0) { await t.click({ timeout: 8_000 }); await page.waitForTimeout(2500); return true; }
    return false;
  };
  try {
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto(BASE_URL + `/debug/afterrun/${RUN_ID}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(6000); // AfterRunReport + findings fetch + lazy previews render
    // Merged "Results" tab is the landing tab: findings banner on top, then the
    // searchable inline Outputs gallery (no separate Outputs tab anymore).
    await shot("i09-1-three-tabs.png"); // now: the Results tab (findings banner + outputs below)
    const outputs = page.locator('[data-testid="output-files-table"]').first();
    if (await outputs.isVisible({ timeout: 4000 }).catch(() => false)) {
      await outputs.scrollIntoViewIfNeeded().catch(() => {});
      await page.waitForTimeout(1500);
      await shot("i08-1-outputs-tab.png", outputs); // the inline output-preview gallery (Results tab)
    }
    if (await clickTab("after-tab-record")) await shot("i09-2-reproducibility-record.png");
  } catch (e: any) {
    log.push(`FAIL after-run — ${e?.message?.split("\n")[0] ?? e}`);
  }
  // eslint-disable-next-line no-console
  console.log("\n[manual-screenshots after-run]\n" + log.join("\n") + "\n");
});
