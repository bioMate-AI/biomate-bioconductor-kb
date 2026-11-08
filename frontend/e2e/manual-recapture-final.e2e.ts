/**
 * Final manual re-captures: t7-2 (members panel, fix live), i12-1 (connectors
 * where-it-runs from residency, A5 live), s1-1 (sidebar chat dots).
 * Run: BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/manual-recapture-final.e2e.ts --project=chromium --retries=0
 */
import { test } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1680, height: 1050 }, deviceScaleFactor: 2 });
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const MG_PROJECT = "3cd5292d-fcc4-4d78-8d41-53d6d3a5e77a";

test("final re-captures (t7-2, i12-1, s1-1)", async ({ page }) => {
  test.setTimeout(180_000);
  await loginAsFixture(page);
  const log: string[] = [];
  const contentCrop = async (name: string) => {
    const content = page.locator('[data-testid="platform-sidebar"] + div');
    const tgt = (await content.count().catch(() => 0)) > 0 ? content.first() : page;
    await tgt.screenshot({ path: path.join(ASSETS, name) });
    log.push(`OK   ${name}`);
  };

  // ── t7-2 members & roles (now on instructions tab) ───────────────────────
  try {
    await page.goto(`${BASE_URL}/projects?project=${MG_PROJECT}&tab=instructions`, { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(6000);
    const members = page.getByTestId("members-panel").first();
    if (await members.isVisible({ timeout: 8000 }).catch(() => false)) {
      await members.scrollIntoViewIfNeeded().catch(() => {});
      await page.waitForTimeout(1200);
      await members.screenshot({ path: path.join(ASSETS, "t7-2-members-roles.png") });
      log.push("OK   t7-2-members-roles.png");
    } else { log.push("SKIP t7-2 (members-panel not visible)"); }
  } catch (e: any) { log.push(`FAIL t7-2 — ${e?.message?.split("\n")[0] ?? e}`); }

  // ── i12-1 connectors (databases tab, where-it-runs from residency) ───────
  try {
    await page.goto(`${BASE_URL}/settings/connections`, { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(5000);
    const dbTab = page.getByTestId("connector-tab-databases");
    if (await dbTab.count() > 0) { await dbTab.click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(1500); }
    const dialog = page.getByTestId("connectors-dialog").first();
    if (await dialog.isVisible({ timeout: 8000 }).catch(() => false)) {
      await dialog.screenshot({ path: path.join(ASSETS, "i12-1-connectors-dialog.png") });
      log.push("OK   i12-1-connectors-dialog.png");
    } else { await contentCrop("i12-1-connectors-dialog.png"); }
  } catch (e: any) { log.push(`FAIL i12-1 — ${e?.message?.split("\n")[0] ?? e}`); }

  // ── s1-1 sidebar (chat history w/ status dots) ───────────────────────────
  try {
    await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(6000); // let sessionStatusMap fetch /api/workflows/runs
    // Report whether any colored dot rows exist (chats with a run).
    const chatBtns = page.locator('[data-testid^="button-chat-"]');
    const nChats = await chatBtns.count().catch(() => 0);
    // Sidebar is the leftmost column; clip it (width ~ 264 CSS px at the expanded width).
    await page.screenshot({ path: path.join(ASSETS, "s1-1-sidebar.png"), clip: { x: 0, y: 0, width: 272, height: 1050 } });
    log.push(`OK   s1-1-sidebar.png (chat rows=${nChats})`);
  } catch (e: any) { log.push(`FAIL s1-1 — ${e?.message?.split("\n")[0] ?? e}`); }

  // eslint-disable-next-line no-console
  console.log("\n[final-recapture]\n" + log.join("\n") + "\n");
});
