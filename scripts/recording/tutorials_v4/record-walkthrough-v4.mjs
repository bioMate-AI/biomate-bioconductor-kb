// Record a v4 walkthrough deck (window.__timeline / __done contract) to webm @1920x1080.
// Usage: node record_v4.mjs "<url?rec=1>" "<outDir>"
// Prints JSON: {video, t_scene0_ms, timeline, total} to stdout.
import { chromium } from 'playwright';
import fs from 'fs';

const URL = process.argv[2];
const OUT = process.argv[3];
const W = 1920, H = 1080;
fs.mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({
  headless: true,
  args: ['--no-sandbox','--disable-setuid-sandbox','--disable-dev-shm-usage','--use-gl=angle','--enable-webgl','--ignore-gpu-blocklist'],
});
const t0 = process.hrtime.bigint();
const nowMs = () => Number((process.hrtime.bigint() - t0) / 1000000n);
const ctx = await browser.newContext({
  viewport: { width: W, height: H },
  deviceScaleFactor: 1,
  recordVideo: { dir: OUT, size: { width: W, height: H } },
});
const page = await ctx.newPage();
await page.goto(URL, { waitUntil: 'networkidle', timeout: 60000 });
await page.evaluate(() => document.fonts && document.fonts.ready).catch(()=>{});

// wait for timeline + scene 0 active
let t_scene0 = null, timeline = null, total = null;
const dl = Date.now() + 30000;
while (Date.now() < dl) {
  const st = await page.evaluate(() => {
    const a = document.querySelector('.scene.active');
    const scenes = Array.prototype.slice.call(document.querySelectorAll('.scene'));
    return { hasTL: Array.isArray(window.__timeline), activeFirst: !!a && scenes.indexOf(a) === 0,
             timeline: window.__timeline || null, total: window.__total || null };
  });
  if (st.hasTL && st.activeFirst) { t_scene0 = nowMs(); timeline = st.timeline; total = st.total; break; }
  await page.waitForTimeout(12);
}
if (t_scene0 === null) { console.error('scene0 never active'); process.exit(2); }

const dl2 = Date.now() + (total + 60) * 1000;
while (Date.now() < dl2) {
  if (await page.evaluate(() => window.__done === true)) break;
  await page.waitForTimeout(100);
}
await page.waitForTimeout(900); // hold last frame
const vid = await page.video().path();
await ctx.close();   // finalizes webm
await browser.close();
console.log(JSON.stringify({ video: vid, t_scene0_ms: t_scene0, timeline, total }));
