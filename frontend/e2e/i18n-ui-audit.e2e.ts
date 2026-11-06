/**
 * i18n + UI conformance capture-audit (2026-10-19).
 *
 * NOT an assertion test — a capture pass. For each locale (en, 中文) it logs in
 * as the shared fixture, forces the locale BEFORE the SPA loads (lib/i18n.ts
 * resolves the active locale ONCE at module load from the
 * `biomate-user-settings` localStorage key), and screenshots the reachable
 * surfaces that carry this session's i18n work:
 *   01 landing (cold-start dashboard + sidebar + composer)
 *   02 data hub (/files)
 *   03 Starred Workflows dialog
 *   04 Settings → API Keys tab
 *
 * Purpose: verify 中文 actually renders (no raw keys, no overflow/clipping) and
 * give the manual/deck a confirmed set of before-lock screenshots. Run with
 * BIOMATE_URL pointed at dev so login + navigation hit the same host.
 */
import { test } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import path from "path";
import fs from "fs";

// Tests run with cwd = frontend/; repo root is its parent.
const OUT = path.resolve(process.cwd(), "..", "docs/qa/20261019-i18n-ui-audit");

const LOCALES = [
  { code: "en" },
  { code: "zh" },
];

for (const loc of LOCALES) {
  test(`i18n UI audit — ${loc.code}`, async ({ page }) => {
    test.setTimeout(240_000);
    const dir = path.join(OUT, loc.code);
    fs.mkdirSync(dir, { recursive: true });

    // Force locale before any page script runs (i18n is resolved once at load).
    await page.addInitScript((language) => {
      try {
        localStorage.setItem(
          "biomate-user-settings",
          JSON.stringify({ language }),
        );
      } catch {}
    }, loc.code);

    await loginAsFixture(page);

    const shot = async (name: string) => {
      try {
        await page.screenshot({ path: path.join(dir, name), fullPage: false });
        console.log(`  ✓ ${loc.code}/${name}`);
      } catch (e) {
        console.log(`  ✗ ${loc.code}/${name}: ${(e as Error).message}`);
      }
    };
    const safeClick = async (testid: string, label: string) => {
      try {
        await page.getByTestId(testid).first().click({ timeout: 8000 });
        return true;
      } catch (e) {
        console.log(`  · click ${label} (${testid}) skipped: ${(e as Error).message}`);
        return false;
      }
    };

    // 1. Landing — force a fresh chat so the cold-start dashboard renders.
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
    await page.waitForTimeout(3500);
    await safeClick("button-new-chat", "new chat");
    await page.waitForTimeout(2500);
    await shot("01-landing.png");

    // 2. Data hub.
    await page.goto(BASE_URL + "/files", { waitUntil: "domcontentloaded", timeout: 60_000 });
    await page.waitForTimeout(3500);
    await shot("02-data-hub.png");

    // 3. Starred Workflows dialog (reopen landing first).
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
    await page.waitForTimeout(3000);
    if (await safeClick("button-workflows-nav", "starred workflows")) {
      await page.waitForTimeout(1200);
      await shot("03-starred-workflows.png");
      await page.keyboard.press("Escape").catch(() => {});
      await page.waitForTimeout(500);
    }

    // 4. Settings dialog — opens on the API Keys tab.
    let opened = await safeClick("button-settings", "settings");
    if (!opened) opened = await safeClick("button-settings-sidebar", "settings (sidebar)");
    if (opened) {
      await page.waitForTimeout(1200);
      await shot("04-settings-api.png");
      await page.keyboard.press("Escape").catch(() => {});
    }
  });
}
