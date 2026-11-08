#!/usr/bin/env node
/**
 * Capture HIGH-DPI, FOCAL screenshots of the live /design (Design & Generate)
 * flow for the T1 video. Runs ONE small-molecule generate on an aspirin seed
 * (backend generation, not Batch GPU) and clips the elements each scene needs:
 *
 *   t1-form.png    → the Design & Generate form (modality + seed SMILES +
 *                    scaffold policy + MW/logP/TPSA window) — pre-generate
 *   t1-results.png → the ranked multi-objective candidates table
 *   t1-pareto.png  → the Pareto trade-off chart + rejection summary
 *
 * deviceScaleFactor=3 so each crop is sharp and large in the slide. Honesty:
 * whatever the generator returns is what gets captured; nothing mocked.
 *
 * Run (from frontend/):
 *   BIOMATE_URL=https://dev-public.biomate.ai node ../scripts/recording/capture-live-t1-focal.cjs
 *
 * Output: recording/video/live-t1-focal/*.png  (+ capture-log.json)
 */
const path = require("path");
const fs = require("fs");
const { chromium } = require(path.resolve(__dirname, "..", "..", "frontend", "node_modules", "@playwright", "test"));

const BASE_URL = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const EMAIL = "lifeifei163361@163.com";
const PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";
const DSF = Number(process.env.CAPTURE_DSF || 3);
const SEED = "CC(=O)Oc1ccccc1C(=O)O"; // aspirin — familiar, illustrative only

const OUT = path.resolve(__dirname, "..", "..", "recording/video/live-t1-focal");
fs.mkdirSync(OUT, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = [];
const note = (m) => { log.push(m); console.log("[t1focal] " + m); };

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

  // viewport-space union clip over testid anchors, padded + clamped.
  const clipUnion = async (ids, pad) => page.evaluate(({ ids, pad }) => {
    const rects = [];
    for (const id of ids) for (const el of document.querySelectorAll(`[data-testid="${id}"]`)) {
      const r = el.getBoundingClientRect(); if (r.width > 0 && r.height > 0) rects.push(r);
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

  const shotClip = async (name, ids, pad) => {
    try {
      const clip = await clipUnion(ids, pad);
      if (!clip || clip.width < 40 || clip.height < 20) { note(`SKIP ${name} — no clip`); return false; }
      await page.screenshot({ path: path.join(OUT, name), clip });
      note(`OK ${name} ${clip.width}x${clip.height}(css) @ ${DSF}x`); return true;
    } catch (e) { note(`ERR ${name} — ${e.message.split("\n")[0]}`); return false; }
  };
  const shotEl = async (name, sel) => {
    try {
      const loc = page.locator(sel).first();
      if (!(await loc.count())) { note(`SKIP ${name} — no ${sel}`); return false; }
      await loc.scrollIntoViewIfNeeded().catch(() => {}); await sleep(400);
      await loc.screenshot({ path: path.join(OUT, name) });
      note(`OK ${name} (el ${sel}) @ ${DSF}x`); return true;
    } catch (e) { note(`ERR ${name} — ${e.message.split("\n")[0]}`); return false; }
  };

  const captured = {};
  try {
    await page.goto(`${BASE_URL}/design`, { waitUntil: "commit", timeout: 60000 });
    await page.getByTestId("design-generate").first().waitFor({ state: "visible", timeout: 90000 });
    await sleep(3500);

    // ensure small-molecule modality + stay policy + aspirin seed
    await page.getByTestId("dg-modality-small_molecule").click().catch(() => {});
    await sleep(300);
    await page.getByTestId("dg-policy-stay").click().catch(() => {});
    const seed = page.getByTestId("dg-seed-smiles");
    await seed.click().catch(() => {});
    await seed.fill(SEED).catch(() => {});
    await sleep(800);

    // ── FORM (pre-generate) ──────────────────────────────────────────────
    captured.form = await shotClip("t1-form.png",
      ["dg-modality", "dg-seed-smiles", "dg-scaffold-policy", "dg-mw", "dg-logp", "dg-tpsa", "dg-envelope"],
      { l: 14, r: 14, t: 16, b: 18 });
    if (!captured.form) captured.form = await shotEl("t1-form.png", '[data-testid="constraints-composer"]');

    // ── GENERATE ─────────────────────────────────────────────────────────
    await page.getByTestId("dg-run").click({ timeout: 15000 });
    note("clicked Generate & rank");
    // wait for results: a candidates table / rows / pareto to appear
    let ready = false;
    for (let i = 0; i < 60; i++) { // up to ~2 min
      const has = await page.evaluate(() => {
        const ids = Array.from(document.querySelectorAll("[data-testid]")).map(e => e.getAttribute("data-testid"));
        return ids.some(x => /result|candidate|pareto|ranked|rejection|dg-results|verdict/i.test(x)) ||
               /BM-0001|Accepted|Rejected|Pareto|candidates/.test(document.body.innerText || "");
      });
      if (has) { ready = true; break; }
      await sleep(2000);
    }
    note("results ready: " + ready);
    await sleep(1500);
    // dump the new testids so we can tighten crops
    const idsNow = [...new Set(await page.evaluate(() => Array.from(document.querySelectorAll("[data-testid]")).map(e => e.getAttribute("data-testid"))))].sort();
    captured.testids_after = idsNow;
    note("testids after generate: " + JSON.stringify(idsNow.filter(x => /result|candidate|pareto|reject|verdict|row|why|score|trade/i.test(x))));

    // ── RESULTS: the multi-objective ranked view (each goal its own column) ─
    // make sure the table view (not grid) is active, then clip the whole view.
    await page.getByTestId("hit-view-table").click().catch(() => {});
    await sleep(600);
    captured.results =
      (await shotEl("t1-results.png", '[data-testid="multi-objective-view"]')) ||
      (await shotEl("t1-results.png", '[data-testid="hit-table"]'));

    // ── PARETO trade-off chart ─────────────────────────────────────────────
    // Clip the chart + axes only (element screenshot of pareto-view catches the
    // fixed "Platform" nav that overlaps its top). Scroll it up first.
    await page.getByTestId("pareto-svg").scrollIntoViewIfNeeded().catch(() => {});
    await sleep(500);
    captured.pareto =
      (await shotClip("t1-pareto.png", ["pareto-svg", "pareto-x-axis", "pareto-y-axis"], { l: 14, r: 14, t: 14, b: 40 })) ||
      (await shotEl("t1-pareto.png", '[data-testid="pareto-svg"]'));

    // ── REJECTION profile (safety gate — flagged, never hidden) ────────────
    captured.rejection = await shotEl("t1-rejection.png", '[data-testid="rejection-profile"]');

    // capture the honest generator provenance string for the narration
    captured.status_text = await page.evaluate(() => {
      const e = document.querySelector('[data-testid="dg-status"]'); return e ? (e.textContent || "").replace(/\s+/g, " ").trim() : null;
    });
    note("status: " + captured.status_text);
  } catch (e) {
    note("CAPTURE ERROR: " + (e && e.message ? e.message.split("\n")[0] : e));
    try { await page.screenshot({ path: path.join(OUT, "_fail-state.png"), fullPage: true }); } catch {}
  }
  fs.writeFileSync(path.join(OUT, "capture-log.json"), JSON.stringify({ dsf: DSF, captured, log }, null, 2));
  await ctx.close(); await browser.close();
  console.log("\n=== t1 focal capture done ===\n" + log.join("\n"));
})();
