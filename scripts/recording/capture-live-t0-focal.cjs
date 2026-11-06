#!/usr/bin/env node
/**
 * Capture HIGH-DPI, FOCAL cold-start screenshots for the T0 getting-started video.
 * The old T0 stills were full 2880x1800 cold-start dashboards — the UI text is tiny
 * in a slide, and scene 6 ("watch the lane appear") showed an EMPTY intent bar with
 * no lane chip at all. This captures the live dev UI and clips to the element each
 * scene is about:
 *
 *   t0-composer.png → the composer strip (chat input + attach-file / point-at-data
 *                     controls + instructions/experts toggles) — scene 5
 *   t0-lane.png     → the chat input WITH a real typed goal + the lane-preview chip
 *                     that appears before you send — scene 6 (the actual "aha")
 *   t0-overview.png → the whole cold start at deviceScaleFactor=3 — scene 2 overview
 *
 * Read-only: types a goal to surface the lane preview, never sends. No Batch spend.
 *
 * Run (from frontend/):
 *   BIOMATE_URL=https://dev-public.biomate.ai node ../scripts/recording/capture-live-t0-focal.cjs
 *
 * Output: recording/video/live-t0-focal/*.png  (+ capture-log.json)
 */
const path = require("path");
const fs = require("fs");
const { chromium } = require(path.resolve(__dirname, "..", "..", "frontend", "node_modules", "@playwright", "test"));

const BASE_URL = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const EMAIL = "lifeifei163361@163.com";
const PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";
const DSF = Number(process.env.CAPTURE_DSF || 3);
// T0's running example is an evidence/knowledge question → Instant lane (matches
// the scene-6 narration and the Instant-vs-Cloud teaching in scene 4).
const GOAL = "What is the evidence linking JAK1 to rheumatoid arthritis, and how strong is it?";

const OUT = path.resolve(__dirname, "..", "..", "recording/video/live-t0-focal");
fs.mkdirSync(OUT, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = [];
const note = (m) => { log.push(m); console.log("[t0focal] " + m); };

function resolveLaunch() {
  if (process.env.PLAYWRIGHT_EXECUTABLE) return { executablePath: process.env.PLAYWRIGHT_EXECUTABLE };
  try {
    const cache = path.join(require("os").homedir(), "Library/Caches/ms-playwright");
    for (const d of fs.readdirSync(cache).filter((x) => x.startsWith("chromium-")).sort().reverse()) {
      const exe = path.join(cache, d, "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing");
      if (fs.existsSync(exe)) return { executablePath: exe };
    }
  } catch {}
  return { channel: process.platform === "darwin" ? "chrome" : undefined };
}

(async () => {
  const browser = await chromium.launch({ headless: true, ...resolveLaunch(), timeout: 60000,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] });

  const api = await browser.newContext();
  const resp = await api.request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "Content-Type": "application/json", "X-E2E-Test-Token": E2E_TOKEN },
    data: { email: EMAIL, password: PASSWORD } });
  if (!resp.ok()) throw new Error(`login failed ${resp.status()}: ${await resp.text()}`);
  const token = (await resp.json()).token; if (!token) throw new Error("no token");
  await api.close();

  const host = new URL(BASE_URL).hostname;
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: DSF,
    extraHTTPHeaders: { Authorization: `Bearer ${token}`, "X-E2E-Test-Token": E2E_TOKEN, "X-Forwarded-Proto": "https" } });
  await ctx.addCookies([{ name: "biomate_token", value: token, domain: host, path: "/", httpOnly: false, secure: true, sameSite: "Lax" }]);
  const page = await ctx.newPage();

  // Union clip of a set of testid anchors, clamped to the viewport, padded.
  const clipUnion = async (ids, pad) => page.evaluate(({ ids, pad }) => {
    const rects = [];
    for (const id of ids) {
      for (const el of document.querySelectorAll(`[data-testid="${id}"]`)) {
        const r = el.getBoundingClientRect();
        if (r.width > 0 && r.height > 0) rects.push(r);
      }
    }
    if (!rects.length) return null;
    const p = pad || {};
    let left = Math.min(...rects.map(r => r.left)) - (p.l ?? 16);
    let right = Math.max(...rects.map(r => r.right)) + (p.r ?? 16);
    let top = Math.min(...rects.map(r => r.top)) - (p.t ?? 14);
    let bottom = Math.max(...rects.map(r => r.bottom)) + (p.b ?? 14);
    left = Math.max(0, left); top = Math.max(0, top);
    right = Math.min(window.innerWidth, right); bottom = Math.min(window.innerHeight, bottom);
    return { x: Math.round(left), y: Math.round(top), width: Math.round(right - left), height: Math.round(bottom - top) };
  }, { ids, pad });

  const shot = async (name, ids, pad) => {
    try {
      const clip = await clipUnion(ids, pad);
      if (!clip || clip.width < 40 || clip.height < 20) { note(`SKIP ${name} — no clip`); return false; }
      await page.screenshot({ path: path.join(OUT, name), clip });
      note(`OK ${name} ${clip.width}x${clip.height}(css) @ ${DSF}x`);
      return true;
    } catch (e) { note(`ERR ${name} — ${e.message.split("\n")[0]}`); return false; }
  };

  const captured = {};
  try {
    await page.goto(`${BASE_URL}/`, { waitUntil: "commit", timeout: 60000 });
    const input = page.getByTestId("chat-input");
    await input.waitFor({ state: "visible", timeout: 90000 });
    await sleep(4000);

    // ── OVERVIEW (scene 2) — whole cold start at 3x ──────────────────────
    try {
      const ds = page.getByTestId("cold-start-dashboard");
      if (await ds.count()) { captured.overview = true; await ds.first().screenshot({ path: path.join(OUT, "t0-overview.png") }); note("OK t0-overview (cold-start-dashboard element)"); }
      else { await page.screenshot({ path: path.join(OUT, "t0-overview.png") }); note("OK t0-overview (full page)"); }
    } catch (e) { note("ERR overview " + e.message.split("\n")[0]); }

    // ── COMPOSER (scene 5) — the input + attach/point-at-data controls ───
    captured.composer = await shot("t0-composer.png",
      ["chat-attach-file-button", "chat-attach-folder-button", "composer-instructions-toggle",
       "composer-experts-toggle", "chat-input", "chat-send-button"],
      { l: 18, r: 18, t: 26, b: 18 });

    // ── LANE PREVIEW (scene 6) — type a real goal, capture input + chip ──
    await input.click();
    await input.fill(GOAL);
    // wait for the lane-preview chip to render
    let laneOk = false;
    try { await page.getByTestId("lane-preview").first().waitFor({ state: "visible", timeout: 12000 }); laneOk = true; }
    catch { try { await page.getByTestId("lane-preview-chip").first().waitFor({ state: "visible", timeout: 6000 }); laneOk = true; } catch {} }
    note("lane-preview visible: " + laneOk);
    await sleep(1200);
    captured.lane = await shot("t0-lane.png",
      ["chat-input", "lane-preview", "lane-preview-chip", "lane-preview-why", "chat-send-button"],
      { l: 18, r: 18, t: 22, b: 18 });
    // dump the lane-preview text so narration can match what's actually shown
    captured.lane_text = await page.evaluate(() => {
      const el = document.querySelector('[data-testid="lane-preview"]') || document.querySelector('[data-testid="lane-preview-chip"]');
      return el ? (el.textContent || "").trim().replace(/\s+/g, " ").slice(0, 240) : null;
    });
    note("lane text: " + (captured.lane_text || "(none)"));
  } catch (e) {
    note("CAPTURE ERROR: " + (e && e.message ? e.message.split("\n")[0] : e));
    try { await page.screenshot({ path: path.join(OUT, "_fail-state.png") }); } catch {}
  }

  fs.writeFileSync(path.join(OUT, "capture-log.json"), JSON.stringify({ dsf: DSF, captured, log }, null, 2));
  await ctx.close(); await browser.close();
  console.log("\n=== t0 focal capture done ===\n" + log.join("\n"));
})();
