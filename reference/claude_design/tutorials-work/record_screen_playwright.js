#!/usr/bin/env node
/**
 * record_screen_playwright.js
 *
 * Playwright-based per-step screen recorder for bioc tutorials.
 *
 * Replaces the older make_video.py CDP-screencast approach (puppeteer-core
 * has ESM-on-Linux issues + chromium spawn flakiness in this sandbox).
 *
 * Pipeline:
 *   1. Setup browser at 2560×1440 (1440p) with deviceScaleFactor:2 →
 *      renders internally at 5120×2880, downsamples to 1440p — sharp.
 *   2. PRE-record context (no video): goto, open picker, select tour,
 *      wait until tour callout 1 is visible. Then CLOSE this context.
 *   3. RECORD context (video on): same URL, programmatically auto-open
 *      the tutorial via localStorage so the picker never appears in the
 *      captured video. Wait for callout 1, then step through.
 *
 * Why two contexts?
 *   playwright's recordVideo starts at context creation. The picker UI
 *   would otherwise be the first ~5 seconds of every video. Splitting
 *   lets us land directly on tour step 1.
 *
 * Inputs:
 *   --key   <bioc_kb|bioc_sc|bioc_methyl>   tour to record
 *   --html  URL                             served prototype page
 *   --label "BIO — Bioconductor · KB ..."   picker label
 *   --steps N                               number of tour steps
 *   --tour-id <bioc-kb-routing>             tour id (for localStorage trigger)
 *
 * Reads:
 *   clips/<key>/timings.json (from generate_vo.py)
 *
 * Writes:
 *   clips/<key>/screen.webm   — direct-to-tour video, NO picker
 *   clips/<key>/step_NN.png   — per-step still (just before advance)
 */
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

function argOf(name, fallback) {
  const i = process.argv.indexOf('--' + name);
  return (i > -1 && process.argv[i + 1]) ? process.argv[i + 1] : fallback;
}

// Map tour key → tour id used by the design prototype's Tour.jsx registry.
// If --tour-id is passed it overrides this map.
const TOUR_ID = {
  bioc_kb:     'bioc-kb-routing',
  bioc_sc:     'bioc-sc-routing',
  bioc_methyl: 'bioc-methyl-routing',
};

// Capture resolution. 1920×1200 with DSF=2 → chromium renders internally at
// 3840×2400 and downsamples — visibly sharper than 1280×800 without the
// chromium-spawn / context-timeout issues we hit at 2560×1440 + DSF=2.
const W = 2560;
const H = 1440;
const DSF = 2;

(async () => {
  const KEY    = argOf('key', 'bioc_kb');
  const HTML   = argOf('html', 'http://localhost:8000/Research%20Agent%20UI.html');
  const LABEL  = argOf('label', 'BIO — Bioconductor · KB routing');
  const NSTEPS = parseInt(argOf('steps', '21'), 10);
  const TID    = argOf('tour-id', TOUR_ID[KEY] || '');

  const BASE     = path.resolve(__dirname);
  const OUT_DIR  = path.join(BASE, 'clips', KEY);
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const timingsPath = path.join(OUT_DIR, 'timings.json');
  if (!fs.existsSync(timingsPath)) {
    console.error('Missing', timingsPath, '— run generate_vo.py first.');
    process.exit(1);
  }
  const timings = JSON.parse(fs.readFileSync(timingsPath, 'utf8'));
  const holds = timings.steps.map(s => s.hold_ms);
  const realNSteps = holds.length;
  if (holds.length !== NSTEPS) {
    console.warn(`[warn] timings has ${holds.length} steps; --steps was ${NSTEPS}. Using timings.`);
  }

  const LEAD_IN_MS = 800;
  const TRAIL_MS   = 1500;
  console.log(`[${KEY}] ${realNSteps} steps · target ${W}×${H} @ ${DSF}x`);

  const videoDir = path.join(OUT_DIR, '_video_tmp');
  fs.mkdirSync(videoDir, { recursive: true });

  // Use system Google Chrome — the downloaded chromium-headless-shell requires
  // AVFAudio.framework which is not present on macOS 11 (Big Sur / Darwin 20.x).
  const browser = await chromium.launch({
    channel: 'chrome',
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
  });

  /**
   * Auto-launch the tour by clicking the picker programmatically inside
   * the page (no human-visible picker dialog). Falls back to the manual
   * .tut-btn → .tour-picker-item path if the programmatic hook fails.
   */
  async function startTour(page, label) {
    // Try the design's own helper first — many prototypes expose a
    // window.startDemo() / window.DEMO_TOURS[id].steps loader.
    const ok = await page.evaluate(([tourId, lbl]) => {
      try {
        // Path 1: directly invoke if there's a startDemo helper.
        if (typeof window.__tourReset === 'function') window.__tourReset();
        if (typeof window.startDemo === 'function' && tourId) {
          window.startDemo(tourId);
          return true;
        }
      } catch { /* fall through */ }
      return false;
    }, [TID, label]).catch(() => false);

    if (!ok) {
      // Path 2: click the picker programmatically and select.
      await page.locator('.tut-btn').first().click();
      await page.waitForSelector('.tour-picker', { timeout: 10_000 });
      await page.locator('.tour-picker-item').filter({ hasText: label.slice(0, 30) }).click();
    }
    await page.waitForSelector('.tour-callout', { timeout: 10_000 });
  }

  try {
    // ── Pass 1: warm context (no video). Confirm the tour starts cleanly.
    console.log(`[${KEY}] warm pass (no video)…`);
    const warmCtx = await browser.newContext({
      viewport: { width: W, height: H },
      deviceScaleFactor: DSF,
    });
    const warm = await warmCtx.newPage();
    warm.on('pageerror', err => console.log('[warm pageerror]', err.message.slice(0, 200)));
    await warm.goto(HTML, { waitUntil: 'load', timeout: 30_000 });
    await warm.waitForTimeout(2000);
    await startTour(warm, LABEL);
    console.log(`[${KEY}] warm pass OK · tour callout visible`);
    await Promise.race([
      warmCtx.close(),
      new Promise(r => setTimeout(r, 5_000)),
    ]).catch(err => console.log(`[${KEY}] warm close warning:`, err.message.slice(0, 100)));

    // ── Pass 2: record context. Same URL, same auto-tour, video ON.
    console.log(`[${KEY}] record pass (video on)…`);
    const ctx = await browser.newContext({
      viewport: { width: W, height: H },
      deviceScaleFactor: DSF,
      recordVideo: { dir: videoDir, size: { width: W, height: H } },
    });
    const page = await ctx.newPage();
    page.on('pageerror', err => console.log('[page error]', err.message.slice(0, 200)));

    await page.goto(HTML, { waitUntil: 'load', timeout: 30_000 });
    await page.waitForTimeout(1500);
    await startTour(page, LABEL);
    await page.waitForTimeout(LEAD_IN_MS);

    // Step through, hold per the timings file, advance via DOM dispatch.
    for (let i = 0; i < realNSteps; i++) {
      const hold = holds[i];
      console.log(`[${KEY}] step ${i+1}/${realNSteps} · hold ${hold}ms`);

      await page.waitForTimeout(Math.max(hold - 200, 200));
      const stillPath = path.join(OUT_DIR, `step_${String(i+1).padStart(2,'0')}.png`);
      await page.screenshot({ path: stillPath, fullPage: false });

      if (i < realNSteps - 1) {
        const advanced = await page.evaluate(() => {
          const callouts = document.querySelectorAll('.tour-callout');
          for (const c of callouts) {
            const rect = c.getBoundingClientRect();
            if (rect.width === 0 || rect.height === 0) continue;
            const btn = c.querySelector('.btn.primary');
            if (btn) { btn.click(); return true; }
          }
          return false;
        });
        if (!advanced) {
          console.log(`[${KEY}] advance failed at step ${i+1}: no visible callout button`);
        }
        await page.waitForTimeout(400);
      }
    }

    await page.waitForTimeout(TRAIL_MS);
    // Save reference to the page-video before the context goes away — we need
    // to await its path AFTER context.close() so playwright finalizes the file.
    const vid = page.video();
    // Some pages with lingering promises cause ctx.close() to hit the default
    // 30s timeout. Swallow it — the video is still finalized inside the temp
    // dir and we pick it up below.
    await Promise.race([
      ctx.close(),
      new Promise(r => setTimeout(r, 8_000)),
    ]).catch(err => console.log(`[${KEY}] ctx.close warning:`, err.message.slice(0, 100)));
    // Best-effort path (won't throw if file isn't ready yet).
    if (vid) {
      try { await vid.path(); } catch { /* ignore */ }
    }
  } finally {
    await browser.close().catch(() => {});
  }

  // Move the produced webm to the canonical name.
  const webms = fs.readdirSync(videoDir).filter(f => f.endsWith('.webm'));
  if (webms.length === 0) {
    console.error(`[${KEY}] no webm produced`);
    process.exit(2);
  }
  const src = path.join(videoDir, webms[0]);
  const dst = path.join(OUT_DIR, 'screen.webm');
  fs.renameSync(src, dst);
  fs.rmSync(videoDir, { recursive: true, force: true });
  console.log(`[${KEY}] → ${dst}`);
})().catch(err => {
  console.error('[fatal]', err);
  process.exit(1);
});
