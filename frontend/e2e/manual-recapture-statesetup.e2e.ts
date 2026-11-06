/**
 * Re-capture of the STATE-SETUP / navigation manual screenshot cluster
 * (committee bucket C "all other screenshots"). Drives the real fixture into
 * each required state and captures at 2x via the B recipe (content-column crop,
 * clean MG demo project). HONESTY: only truthful states are captured; a state
 * that can't be reached is logged as a skip, never faked.
 *
 * Run: cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *   npx playwright test e2e/manual-recapture-statesetup.e2e.ts --project=chromium
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1680, height: 1050 }, deviceScaleFactor: 2 });

const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const MG_ID = "3cd5292d-fcc4-4d78-8d41-53d6d3a5e77a";
const MG_NAME = "MG PBMC — sample data demo";

function contentCol(page: import("@playwright/test").Page) {
  return page.locator('[data-testid="platform-sidebar"] + div');
}
async function shotContent(page: import("@playwright/test").Page, name: string, log: string[]) {
  const c = contentCol(page);
  const tgt = (await c.count().catch(() => 0)) > 0 ? c.first() : page;
  await tgt.screenshot({ path: path.join(ASSETS, name) });
  log.push(`OK   ${name}`);
}
// --- Datasets: data-hub two-pane + dataset preview / lineage / versions ---
test("datasets (i05-0, t10-1, t10-2, t10-4)", async ({ page }) => {
  test.setTimeout(150_000);
  await loginAsFixture(page);
  const log: string[] = [];
  try {
    await page.goto(BASE_URL + "/files", { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(4500);
    // Select the clean demo project from the picker (avoids the 138-project clutter in the crop).
    const card = page.getByText(MG_NAME).first();
    if ((await card.count()) > 0) { await card.click({ timeout: 10_000 }); await page.waitForTimeout(4000); }
    else log.push("WARN could not find MG project card");
    // Open the rich counts matrix so the right pane shows a real dataset object.
    const file = page.getByText(/counts_matrix/i).first();
    if ((await file.count()) > 0) {
      await file.click({ timeout: 8_000 });
      await page.waitForTimeout(3500);
      await shotContent(page, "i05-0-data-hub.png", log);          // two-pane: tree + open dataset
      // Preview tab is the default; capture the dataset object preview.
      const prev = page.getByTestId("dataset-tab-preview");
      if ((await prev.count()) > 0) { await prev.click({ timeout: 6000 }).catch(() => {}); await page.waitForTimeout(1500); }
      await shotContent(page, "t10-1-dataset-preview.png", log);   // CSV headers + rows
      // Lineage tab
      const lin = page.getByTestId("dataset-tab-lineage");
      if ((await lin.count()) > 0) {
        await lin.click({ timeout: 6000 }); await page.waitForTimeout(2500);
        await shotContent(page, "t10-2-dataset-lineage.png", log);
      } else log.push("SKIP t10-2 (no lineage tab)");
      // Versions tab — add a v2 note (append-only) if only v1 exists, so the
      // figure shows a real version history (committee: "missing v2 entry").
      const ver = page.getByTestId("dataset-tab-versions");
      if ((await ver.count()) > 0) {
        await ver.click({ timeout: 6000 }); await page.waitForTimeout(2000);
        const noteInput = page.getByPlaceholder(/Add a version note/i).first();
        const addVerBtn = page.getByTestId("dataset-version-add-button").first();
        const hasV2 = (await page.getByText(/^v2\b/).count()) > 0;
        if (!hasV2 && (await noteInput.count()) > 0 && (await addVerBtn.count()) > 0) {
          await noteInput.fill("Re-derived after QC review (demo)");
          await page.waitForTimeout(400);
          if (await addVerBtn.isEnabled().catch(() => false)) {
            await addVerBtn.click({ timeout: 6000 }); await page.waitForTimeout(2500);
            log.push("added v2 version note");
          }
        }
        await shotContent(page, "t10-4-dataset-versions.png", log);
      } else log.push("SKIP t10-4 (no versions tab)");
    } else log.push("SKIP i05-0/t10-* (no counts_matrix file row)");
  } catch (e: any) { log.push(`FAIL datasets — ${e?.message?.split("\n")[0] ?? e}`); }
  // eslint-disable-next-line no-console
  console.log("\n[statesetup datasets]\n" + log.join("\n") + "\n");
});

// --- Sidebar with chat history + colored run-status dots ---
test("sidebar (s1-1)", async ({ page }) => {
  test.setTimeout(90_000);
  await loginAsFixture(page);
  const log: string[] = [];
  try {
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(5000);
    const sb = page.locator('[data-testid="platform-sidebar"]').first();
    if ((await sb.count()) > 0 && (await sb.isVisible().catch(() => false))) {
      await sb.screenshot({ path: path.join(ASSETS, "s1-1-sidebar.png") });
      log.push("OK   s1-1-sidebar.png");
    } else log.push("SKIP s1-1 (sidebar not visible — may be collapsed)");
  } catch (e: any) { log.push(`FAIL sidebar — ${e?.message?.split("\n")[0] ?? e}`); }
  // eslint-disable-next-line no-console
  console.log("\n[statesetup sidebar]\n" + log.join("\n") + "\n");
});

// --- Instruments (Connectors dialog → Instruments sub-tab) ---
test("instruments (t6-1)", async ({ page }) => {
  test.setTimeout(90_000);
  await loginAsFixture(page);
  const log: string[] = [];
  try {
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(5000);
    const connectors = page.getByText(/^Connectors$/i).first();
    if ((await connectors.count()) === 0) { log.push("SKIP t6-1 (no Connectors entry in sidebar — may be collapsed)"); }
    else {
      await connectors.click({ timeout: 8000 });
      await page.waitForTimeout(2500);
      // Databases tab → "Instruments" sub-view button
      const instrBtn = page.getByRole("button", { name: /^Instruments$/i }).first();
      if ((await instrBtn.count()) > 0) { await instrBtn.click({ timeout: 6000 }).catch(() => {}); await page.waitForTimeout(2000); }
      else log.push("WARN no Instruments sub-button");
      // Register a demo instrument if none exist, so the row renders with its
      // status + residency badge (committee: "No instruments registered yet").
      // LC-MS = 'file' kind, on-prem residency → needs only name + type.
      if ((await page.getByText(/No instruments registered yet/i).count()) > 0) {
        const addBtn = page.getByTestId("button-add-instrument").first();
        if ((await addBtn.count()) > 0) {
          await addBtn.click({ timeout: 6000 }); await page.waitForTimeout(800);
          await page.getByTestId("input-instrument-name").fill("Lab LC-MS (demo)");
          await page.getByTestId("select-instrument-type").selectOption("lcms").catch(() => {});
          await page.waitForTimeout(500);
          const submit = page.getByTestId("button-submit-instrument").first();
          if ((await submit.count()) > 0 && (await submit.isEnabled().catch(() => false))) {
            await submit.click({ timeout: 6000 }); await page.waitForTimeout(2800);
            log.push("registered demo LC-MS instrument");
          } else log.push("WARN submit disabled — instrument not registered (t6-1 stays empty-state)");
        }
      }
      // Crop the content column (drop the polluted sidebar) — this is a full page, not a dialog.
      await shotContent(page, "t6-1-instruments-tab.png", log);
    }
  } catch (e: any) { log.push(`FAIL instruments — ${e?.message?.split("\n")[0] ?? e}`); }
  // eslint-disable-next-line no-console
  console.log("\n[statesetup instruments]\n" + log.join("\n") + "\n");
});

// --- Project collaboration: overview, standing instructions, members & roles ---
test("collab (t7-0, t7-1, t7-2)", async ({ page }) => {
  test.setTimeout(120_000);
  await loginAsFixture(page);
  const log: string[] = [];
  try {
    await page.goto(BASE_URL + `/projects?project=${MG_ID}&tab=instructions`, { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(5500);
    // Overview — top of the Instructions page (standing card at top).
    await shotContent(page, "t7-0-project-overview.png", log);
    // Standing instructions card — clip from the card top to just above the next
    // card ("Output requirements"), cropped to the content column. (cardAround
    // matched a tiny inner element; a viewport clip is reliable + 2x.)
    const stH = page.getByRole("heading", { name: /Standing instructions/i }).first();
    const outH = page.getByRole("heading", { name: /Output requirements/i }).first();
    const col = await contentCol(page).first().boundingBox().catch(() => null);
    const stBox = await stH.boundingBox().catch(() => null);
    if (stBox && col) {
      const top = Math.max(0, stBox.y - 46);
      const outBox = await outH.boundingBox().catch(() => null);
      const bottom = outBox && outBox.y > top ? outBox.y - 26 : top + 360;
      await page.screenshot({
        path: path.join(ASSETS, "t7-1-standing-instructions.png"),
        clip: { x: col.x, y: top, width: col.width, height: Math.max(240, bottom - top) },
      });
      log.push("OK   t7-1-standing-instructions.png (clip)");
    } else log.push("SKIP t7-1 (standing card bbox not found)");
    // Members & roles sits below the long Skills list — scroll to load it, then
    // generate the share link so Copy/Revoke render, then clip the members card.
    await page.mouse.wheel(0, 7000); await page.waitForTimeout(1200);
    const gen = page.getByRole("button", { name: /Generate share link/i }).first();
    if ((await gen.count()) > 0) { await gen.click({ timeout: 6000 }).catch(() => {}); await page.waitForTimeout(2500); }
    const memH = page.getByText(/Members & roles/i).first();
    if ((await memH.count()) > 0) {
      await memH.scrollIntoViewIfNeeded().catch(() => {});
      await page.waitForTimeout(900);
      const col2 = await contentCol(page).first().boundingBox().catch(() => null);
      const mBox = await memH.boundingBox().catch(() => null);
      if (mBox && col2) {
        const top = Math.max(0, mBox.y - 58);
        await page.screenshot({
          path: path.join(ASSETS, "t7-2-members-roles.png"),
          clip: { x: col2.x, y: top, width: col2.width, height: 540 },
        });
        log.push("OK   t7-2-members-roles.png (owner view: invite+role+share link+Copy/Revoke; real Editor/Viewer rows need invited accounts)");
      } else log.push("SKIP t7-2 (members bbox not found)");
    } else log.push("SKIP t7-2 (no Members & roles section after scroll)");
  } catch (e: any) { log.push(`FAIL collab — ${e?.message?.split("\n")[0] ?? e}`); }
  // eslint-disable-next-line no-console
  console.log("\n[statesetup collab]\n" + log.join("\n") + "\n");
  expect(true).toBe(true);
});
