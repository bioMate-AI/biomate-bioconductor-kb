#!/usr/bin/env node
/**
 * Record the auto-playing drug-dev walkthrough page (window.__timeline/__done)
 * to a 1920x1080 webm — once per language — injecting that language's per-scene
 * durations so the visual timeline matches the narration tightly, and capturing
 * the embedded live-UI <video> clips as they play.
 *
 * Uses @playwright/test's chromium via system Chrome (matches the installed
 * browser toolchain on darwin). Serves reference/claude_design/ statically so
 * /tutorials/drug-dev-walkthrough.html and its assets/live/*.webm resolve.
 *
 * Run (from repo root or anywhere):
 *   node scripts/recording/record-walkthrough-live.cjs
 *
 * Output per language L in {en,zh}:
 *   recording/video/drug-dev-L-raw.webm
 *   recording/audio/drug-dev-shared/record_meta_L.json  { t_scene0_ms, timeline, total_seconds, video }
 */
const path = require("path");
const fs = require("fs");
const http = require("http");
const { chromium } = require(path.resolve(__dirname, "..", "..", "frontend", "node_modules", "@playwright", "test"));

const ROOT = path.resolve(__dirname, "..", "..");
const WEBROOT = path.join(ROOT, "reference/claude_design");
const VIDEO_OUT = path.join(ROOT, "recording/video");
const META_OUT = path.join(ROOT, "recording/audio/drug-dev-shared");
const BUFFER_S = 1.3; // tail gap per scene (narration must fit before next scene)
const PORT = 7786;

fs.mkdirSync(VIDEO_OUT, { recursive: true });
fs.mkdirSync(META_OUT, { recursive: true });

const MIME = { ".html": "text/html", ".css": "text/css", ".js": "application/javascript",
  ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".svg": "image/svg+xml",
  ".webm": "video/webm", ".mp4": "video/mp4", ".json": "application/json", ".woff2": "font/woff2" };

function startServer() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      let rel = decodeURIComponent(req.url.split("?")[0]);
      let fp = path.join(WEBROOT, rel);
      if (!fp.startsWith(WEBROOT)) { res.writeHead(403); return res.end(); }
      fs.stat(fp, (err, st) => {
        if (err || !st.isFile()) { res.writeHead(404); return res.end("not found: " + rel); }
        res.writeHead(200, { "Content-Type": MIME[path.extname(fp)] || "application/octet-stream" });
        fs.createReadStream(fp).pipe(res);
      });
    });
    srv.listen(PORT, () => resolve(srv));
  });
}

function durationsFor(lang) {
  const timing = JSON.parse(fs.readFileSync(path.join(ROOT, `recording/audio/drug-dev-${lang}`, "timing.json")));
  return timing.map((t) => Math.max(2, t.duration_ms / 1000 + BUFFER_S));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function recordLang(browser, lang) {
  const durations = durationsFor(lang);
  const ctx = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    recordVideo: { dir: VIDEO_OUT, size: { width: 1920, height: 1080 } },
  });
  await ctx.addInitScript((d) => { window.__sceneDurations = d; }, durations);
  const page = await ctx.newPage();
  const t0 = Date.now();
  await page.goto(`http://localhost:${PORT}/tutorials/drug-dev-walkthrough.html`, { waitUntil: "networkidle", timeout: 60000 });

  // wait for timeline published + scene 0 active
  let tScene0 = null, timeline = null, total = null;
  const deadline = Date.now() + 40000;
  while (Date.now() < deadline) {
    const st = await page.evaluate(() => {
      const a = document.querySelector(".scene.active");
      const scenes = Array.prototype.slice.call(document.querySelectorAll(".scene"));
      return {
        hasTL: Array.isArray(window.__timeline),
        activeIsFirst: !!a && scenes.indexOf(a) === 0,
        timeline: window.__timeline || null,
        total: window.__totalSeconds || null,
        injected: Array.isArray(window.__sceneDurations) ? window.__sceneDurations.length : -1,
        nscenes: scenes.length,
      };
    });
    if (st.hasTL && st.activeIsFirst) {
      tScene0 = Date.now() - t0; timeline = st.timeline; total = st.total;
      console.log(`[${lang}] scene0 active @ ${tScene0}ms; injected ${st.injected}/${st.nscenes}; total ${total}s`);
      break;
    }
    await sleep(15);
  }
  if (tScene0 === null) { await ctx.close(); throw new Error(`[${lang}] scene 0 never active`); }

  // poll until __done
  const doneDeadline = Date.now() + (total + 90) * 1000;
  while (Date.now() < doneDeadline) {
    if (await page.evaluate(() => window.__done === true)) break;
    await sleep(120);
  }
  const tDone = Date.now() - t0;
  console.log(`[${lang}] __done @ ${tDone}ms (${((tDone - tScene0) / 1000).toFixed(1)}s after scene0)`);
  await page.waitForTimeout(900);

  const video = page.video();
  await ctx.close();
  const vpath = await video.path();
  const dst = path.join(VIDEO_OUT, `drug-dev-${lang}-raw.webm`);
  if (fs.existsSync(dst)) fs.unlinkSync(dst);
  fs.renameSync(vpath, dst);

  const meta = { t_scene0_ms: tScene0, t_done_ms: tDone, timeline, total_seconds: total, video: dst };
  fs.writeFileSync(path.join(META_OUT, `record_meta_${lang}.json`), JSON.stringify(meta, null, 2));
  console.log(`[${lang}] video -> ${dst}`);
}

// System Chrome (`channel:"chrome"`) can fail its CDP handshake on macOS when the
// user already has Chrome running. Prefer the bundled "Chrome for Testing" binary
// if present; fall back to the channel. Override with PLAYWRIGHT_EXECUTABLE/_CHANNEL.
function resolveLaunch() {
  if (process.env.PLAYWRIGHT_EXECUTABLE) return { executablePath: process.env.PLAYWRIGHT_EXECUTABLE };
  if (process.env.PLAYWRIGHT_CHANNEL) return { channel: process.env.PLAYWRIGHT_CHANNEL };
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
  const srv = await startServer();
  const browser = await chromium.launch({
    headless: true,
    ...resolveLaunch(),
    timeout: 60000,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage",
      "--autoplay-policy=no-user-gesture-required"],
  });
  try {
    for (const lang of (process.argv[2] ? [process.argv[2]] : ["en", "zh"])) {
      await recordLang(browser, lang);
    }
  } finally {
    await browser.close();
    srv.close();
  }
})();
