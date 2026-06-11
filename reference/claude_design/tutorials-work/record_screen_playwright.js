#!/usr/bin/env node
/**
 * record_screen_playwright.js
 *
 * Playwright-based per-step screen recorder for bioc tutorials.
 *
 * Replaces the older make_video.py CDP-screencast approach (puppeteer-core
 * has ESM-on-Linux issues + chromium spawn flakiness in this sandbox).
 * Playwright already has its own bundled chromium that works.
 *
 * Inputs:
 *   --key   <bioc_kb|bioc_sc|bioc_methyl>   tour to record
 *   --html  path                            URL (defaults to localhost:8000)
 *   --label "BIO — Bioconductor · KB ..."  picker label
 *   --steps N                               number of tour steps
 *
 * Reads:
 *   clips/<key>/timings.json (from generate_vo.py)
 *
 * Writes:
 *   clips/<key>/screen.webm   — single uncut tour video
 *   clips/<key>/step_NN.png   — per-step still (last frame of each hold)
 *
 * Then a separate ffmpeg pass muxes screen.webm + combined.mp3 → final mp4.
 *
 * Usage:
 *   node record_screen_playwright.js \
 *     --key bioc_kb \
 *     --html "http://localhost:8000/Research%20Agent%20UI.html" \
 *     --label "BIO — Bioconductor · KB routing" \
 *     --steps 21
 */
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

function argOf(name, fallback) {
  const i = process.argv.indexOf('--' + name);
  return (i > -1 && process.argv[i + 1]) ? process.argv[i + 1] : fallback;
}

(async () => {
  const KEY    = argOf('key', 'bioc_kb');
  const HTML   = argOf('html', 'http://localhost:8000/Research%20Agent%20UI.html');
  const LABEL  = argOf('label', 'BIO — Bioconductor · KB routing');
  const NSTEPS = parseInt(argOf('steps', '21'), 10);

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
  if (holds.length !== NSTEPS) {
    console.warn(`[warn] timings has ${holds.length} steps; --steps was ${NSTEPS}. Using timings.`);
  }
  const realNSteps = holds.length;

  const LEAD_IN_MS = 800;
  const TRAIL_MS   = 1500;
  const totalMs    = LEAD_IN_MS + holds.reduce((a,b) => a+b, 0) + TRAIL_MS;
  console.log(`[${KEY}] ${realNSteps} steps, total ~${(totalMs/1000).toFixed(1)}s`);

  const videoDir = path.join(OUT_DIR, '_video_tmp');
  fs.mkdirSync(videoDir, { recursive: true });

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
  });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    recordVideo: { dir: videoDir, size: { width: 1280, height: 800 } },
  });
  const page = await context.newPage();
  page.on('pageerror', err => console.log('[page error]', err.message.slice(0, 200)));

  try {
    console.log(`[${KEY}] goto`, HTML);
    await page.goto(HTML, { waitUntil: 'load', timeout: 30_000 });
    await page.waitForTimeout(2500);

    // Open the tutorial picker
    console.log(`[${KEY}] opening tutorial picker…`);
    await page.locator('.tut-btn').first().click();
    await page.waitForSelector('.tour-picker', { timeout: 10_000 });
    await page.waitForTimeout(500);

    // Select the matching tour by label
    console.log(`[${KEY}] selecting`, LABEL.slice(0, 50));
    await page.locator('.tour-picker-item').filter({ hasText: LABEL.slice(0, 30) }).click();
    await page.waitForSelector('.tour-callout', { timeout: 10_000 });
    await page.waitForTimeout(LEAD_IN_MS);

    // Step through; hold per the timings file; advance with Next button
    for (let i = 0; i < realNSteps; i++) {
      const hold = holds[i];
      console.log(`[${KEY}] step ${i+1}/${realNSteps} · hold ${hold}ms`);

      // Per-step still — captured 200ms before advancing
      await page.waitForTimeout(Math.max(hold - 200, 200));
      const stillPath = path.join(OUT_DIR, `step_${String(i+1).padStart(2,'0')}.png`);
      await page.screenshot({ path: stillPath, fullPage: false });

      // Advance — skip the very last step (Done button closes tour).
      // The tour-callout re-mounts on each step transition, so a stale
      // Playwright locator misses. Dispatch the click via DOM inside the
      // page context so we always hit the currently-mounted button.
      if (i < realNSteps - 1) {
        const advanced = await page.evaluate(() => {
          const callouts = document.querySelectorAll('.tour-callout');
          // Take the visible one (in case stale clones linger)
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
        // Allow re-render of the next callout
        await page.waitForTimeout(400);
      }
    }

    await page.waitForTimeout(TRAIL_MS);
  } finally {
    await context.close();
    await browser.close();
  }

  // Playwright wrote video.webm inside videoDir; move to the canonical name
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
