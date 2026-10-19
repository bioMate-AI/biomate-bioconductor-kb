/**
 * t0 "Getting started" END-TO-END screenshot capture (2026-10-19, rev2).
 *
 * Captures the real doorway flow against dev, honestly (only what renders):
 *   cold start (heading + 4 cards) → type a real goal → detected route
 *   (lane-preview — the current affordance that REPLACED "see how it's handled")
 *   → send → the real cited evidence answer.
 *
 * Quality rules (from review feedback 2026-10-19):
 *   - TIGHT element/clip crops, never full-page (full-page shrinks the font).
 *   - Left sidebar is never in frame (fixture project list is polluted).
 *   - deviceScaleFactor 2 for sharp text.
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     npx playwright test e2e/t0-getting-started-capture.e2e.ts --project=chromium
 */
import { test } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1440, height: 980 }, deviceScaleFactor: 2 });
const ASSETS = path.resolve(process.cwd(), "..", "reference/claude_design/tutorials_handoff/assets/live");
const QUERY = "What is the evidence linking JAK1 to rheumatoid arthritis?";

async function settle(page: any, ms = 3500) { await page.waitForTimeout(ms); }

test("t0 end-to-end doorway (tight crops)", async ({ page }) => {
  test.setTimeout(240_000);
  await loginAsFixture(page);
  const log: string[] = [];

  // Element crop by testid (drops sidebar + empty space; fills the frame).
  const shotEl = async (testid: string, name: string, padding = 12) => {
    const el = page.getByTestId(testid).first();
    if ((await el.count()) === 0) { log.push("SKIP " + name + " (no " + testid + ")"); return false; }
    await el.scrollIntoViewIfNeeded().catch(() => {});
    await el.screenshot({ path: path.join(ASSETS, name) }).catch(async (e) => {
      log.push("WARN element shot failed for " + name + " — " + e?.message?.split("\n")[0]);
    });
    log.push("OK   " + name + " (crop " + testid + ")");
    return true;
  };

  // Tight clip over the union bbox of several testids (+ padding) — for the
  // composer, which has no single wrapper element.
  const shotUnion = async (testids: string[], name: string, pad = 16) => {
    const boxes: any[] = [];
    for (const t of testids) {
      const el = page.getByTestId(t).first();
      if ((await el.count()) > 0) { const b = await el.boundingBox(); if (b) boxes.push(b); }
    }
    if (boxes.length === 0) { log.push("SKIP " + name + " (no union boxes)"); return false; }
    const x0 = Math.min(...boxes.map(b => b.x)) - pad;
    const y0 = Math.min(...boxes.map(b => b.y)) - pad;
    const x1 = Math.max(...boxes.map(b => b.x + b.width)) + pad;
    const y1 = Math.max(...boxes.map(b => b.y + b.height)) + pad;
    await page.screenshot({ path: path.join(ASSETS, name), clip: { x: Math.max(0, x0), y: Math.max(0, y0), width: x1 - x0, height: y1 - y0 } });
    log.push("OK   " + name + " (clip " + testids.join("+") + ")");
    return true;
  };

  try {
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 45_000 });
    await settle(page, 4500);

    // 1. Cold start — tight crop of heading + the four cards (incl. the corrected
    //    "Molecule design & generate" label).
    await shotEl("cold-start-dashboard", "t0-coldstart.png");

    // 2. Type the real goal into the pinned composer; the route/lane preview appears.
    const input = page.getByTestId("chat-input").first();
    if ((await input.count()) === 0) { log.push("FAIL chat-input not found"); throw new Error("no chat-input"); }
    await input.click();
    await input.fill(QUERY);
    await settle(page, 2500);
    const lane = page.getByTestId("lane-preview");
    if ((await lane.count()) > 0) {
      log.push("lane-preview text = " + JSON.stringify((await lane.first().innerText().catch(() => "")).slice(0, 80)));
    } else { log.push("WARN lane-preview not rendered after typing"); }
    // Tight composer crop: lane-preview + input + send.
    await shotUnion(["lane-preview", "chat-input", "chat-send-button"], "t0-composer.png");
    await shotUnion(["lane-preview", "chat-input", "chat-send-button"], "t0-lane.png");

    // 3. Send and wait for the cited evidence answer, then crop the messages area.
    await page.getByTestId("chat-send-button").first().click({ timeout: 10_000 });
    await settle(page, 4000);
    let answered = false;
    for (let i = 0; i < 28; i++) {
      await settle(page, 3000);
      const streaming = await page.getByTestId("chat-stop-button").count().catch(() => 0);
      const cites = await page.locator('a[href*="pubmed"], a[href*="doi.org"], [data-testid*="citation"], [data-testid*="source"]').count().catch(() => 0);
      const txt = (await page.locator("body").innerText().catch(() => "")).toLowerCase();
      if (streaming === 0 && (cites > 0 || /jak1|rheumatoid/.test(txt))) { answered = true; break; }
    }
    log.push(answered ? "answer rendered" : "WARN answer not clearly detected (captured anyway)");
    await settle(page, 2000);
    // Crop the messages container (the cited answer), not the whole page.
    if (!(await shotEl("chat-messages", "t0-answer.png"))) {
      // fallback: crop the content column (still no sidebar), not full page
      const content = page.locator('[data-testid="platform-sidebar"] + div').first();
      if ((await content.count()) > 0) { await content.screenshot({ path: path.join(ASSETS, "t0-answer.png") }); log.push("OK   t0-answer.png (content column)"); }
    }
  } catch (e: any) {
    log.push("FAIL — " + (e?.message?.split("\n")[0] ?? e));
  }
  console.log("\n[t0 e2e capture rev2]\n" + log.join("\n") + "\n");
});
