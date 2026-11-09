/**
 * t0 "Getting started" screenshot capture — matches Claude-design §2b (2026-10-19).
 *
 * Design restructured t0 to 5 scenes and specified exactly these assets (EN + ZH),
 * captured from the CURRENT dev UI, 1920-wide, light theme:
 *   assets/s1-1-sidebar.png      — fresh new-conversation screen (cards + message box)
 *   assets/live/t0-composer.png  — message box with the JAK1 question typed (EN)
 *   assets/live/t0-composer-zh.png — same, 中文 question
 *   assets/live/search-answer.png    — the real cited JAK1 answer (EN)
 *   assets/live/search-answer-zh.png — the real cited JAK1 answer (中文)
 *
 * Honest: only what renders is saved. Tight crops (no tiny-font full-page).
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     npx playwright test e2e/t0-getting-started-capture.e2e.ts --project=chromium
 */
import { test } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1920, height: 900 }, deviceScaleFactor: 2 });
const DECK = path.resolve(process.cwd(), "..", "reference/claude_design/tutorials_v2_design");
const Q_EN = "What is the evidence linking JAK1 to rheumatoid arthritis, and how strong is it?";
const Q_ZH = "JAK1 与类风湿关节炎相关的证据有哪些？证据有多强？";

async function settle(page: any, ms = 3500) { await page.waitForTimeout(ms); }

async function captureFlow(page: any, lang: "en" | "zh", log: string[]) {
  const q = lang === "en" ? Q_EN : Q_ZH;
  const suffix = lang === "en" ? "" : "-zh";
  const sidebarName = lang === "en" ? "assets/s1-1-sidebar.png" : "assets/s1-1-sidebar-zh.png";

  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 45_000 });
  await settle(page, 4500);

  // Switch the whole UI to Chinese: write the settings key the app uses
  // (biomate-user-settings.language = "chinese", the enum SETTINGS_LANG_MAP
  // expects), then reload so i18n re-resolves at module load. Doing this AFTER
  // the first load (not addInitScript) avoids the race with the app writing its
  // own settings on login, which left the chrome in English.
  if (lang === "zh") {
    await page.evaluate(() => {
      try {
        const raw = localStorage.getItem("biomate-user-settings");
        const s = raw ? JSON.parse(raw) : {};
        s.language = "chinese";
        localStorage.setItem("biomate-user-settings", JSON.stringify(s));
      } catch { /* ignore */ }
    });
    await page.reload({ waitUntil: "domcontentloaded", timeout: 45_000 });
    await settle(page, 4500);
  }

  // 1. Fresh new-conversation screen. Crop to the content column (heading + cards +
  //    composer) — the fixture's left sidebar is polluted with E2E projects, so it
  //    is kept out of frame; what the tutorial needs (cards + message box) is in.
  const content = page.locator('[data-testid="platform-sidebar"] + div').first();
  const target = (await content.count().catch(() => 0)) > 0 ? content.first() : page;
  await target.screenshot({ path: path.join(DECK, sidebarName) });
  log.push("OK   " + sidebarName);

  // 2. Type the goal into the pinned composer; capture the composer with it typed.
  const input = page.getByTestId("chat-input").first();
  if ((await input.count()) === 0) { log.push("FAIL [" + lang + "] chat-input not found"); return; }
  await input.click();
  await input.fill(q);
  await settle(page, 2500);
  // Tight clip over the message box only (input + send) — NOT the full-width
  // lane-preview, which sits far left and blows the crop out to the page width.
  const boxes: any[] = [];
  for (const t of ["chat-input", "chat-send-button"]) {
    const el = page.getByTestId(t).first();
    if ((await el.count()) > 0) { const b = await el.boundingBox(); if (b) boxes.push(b); }
  }
  if (boxes.length) {
    const pad = 18;
    const x0 = Math.max(0, Math.min(...boxes.map(b => b.x)) - pad);
    const y0 = Math.max(0, Math.min(...boxes.map(b => b.y)) - pad);
    const x1 = Math.max(...boxes.map(b => b.x + b.width)) + pad;
    const y1 = Math.max(...boxes.map(b => b.y + b.height)) + pad;
    await page.screenshot({ path: path.join(DECK, "assets/live/t0-composer" + suffix + ".png"), clip: { x: x0, y: y0, width: x1 - x0, height: y1 - y0 } });
    log.push("OK   assets/live/t0-composer" + suffix + ".png");
  } else { log.push("WARN [" + lang + "] no composer boxes"); }

  // 3. Send. The send button can stay disabled briefly (project-settings load),
  //    and clicking the clipped button is flaky — wait for it to be enabled, then
  //    submit with Enter (same handleSend path, no actionability requirement).
  await page.waitForSelector('[data-testid="chat-send-button"]:not([disabled])', { timeout: 20_000 }).catch(() => log.push("WARN [" + lang + "] send stayed disabled"));
  await input.click();
  await input.press("Enter");
  await settle(page, 4000);
  let answered = false;
  for (let i = 0; i < 30; i++) {
    await settle(page, 3000);
    const streaming = await page.getByTestId("chat-stop-button").count().catch(() => 0);
    const cites = await page.locator('a[href*="pubmed"], a[href*="doi.org"], [data-testid*="citation"], [data-testid*="source"]').count().catch(() => 0);
    const txt = (await page.locator("body").innerText().catch(() => "")).toLowerCase();
    if (streaming === 0 && (cites > 0 || /jak1|rheumatoid|类风湿/.test(txt))) { answered = true; break; }
  }
  log.push("[" + lang + "] " + (answered ? "answer rendered" : "WARN answer not clearly detected"));
  await settle(page, 2500);
  const msgs = page.getByTestId("chat-messages").first();
  if ((await msgs.count()) > 0) {
    await msgs.screenshot({ path: path.join(DECK, "assets/live/search-answer" + suffix + ".png") });
    log.push("OK   assets/live/search-answer" + suffix + ".png (chat-messages crop)");
  } else {
    const t2 = (await content.count().catch(() => 0)) > 0 ? content.first() : page;
    await t2.screenshot({ path: path.join(DECK, "assets/live/search-answer" + suffix + ".png") });
    log.push("OK   assets/live/search-answer" + suffix + ".png (content column)");
  }
}

test("t0 assets — EN", async ({ page }) => {
  test.setTimeout(240_000);
  await loginAsFixture(page);
  const log: string[] = [];
  try { await captureFlow(page, "en", log); } catch (e: any) { log.push("FAIL EN — " + (e?.message?.split("\n")[0] ?? e)); }
  console.log("\n[t0 EN]\n" + log.join("\n") + "\n");
});

test("t0 assets — ZH", async ({ page }) => {
  test.setTimeout(240_000);
  await loginAsFixture(page);
  const log: string[] = [];
  try { await captureFlow(page, "zh", log); } catch (e: any) { log.push("FAIL ZH — " + (e?.message?.split("\n")[0] ?? e)); }
  console.log("\n[t0 ZH]\n" + log.join("\n") + "\n");
});
