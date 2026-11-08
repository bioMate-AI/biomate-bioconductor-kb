#!/usr/bin/env node
/**
 * Capture HIGH-DPI, FOCAL screenshots of the live Data hub (/files) for the T4 video:
 *   t4-data-hub.png      → the two-pane Data hub (file tree + dataset detail) in a project
 *   t4-dataset-object.png→ a dataset opened as an object (header + Preview/Quality/Lineage/… tabs)
 *   t4-quality.png       → the Quality tab detail (shape / effective N / notes / verdict)
 *
 * Read-only: picks a project that already has a dataset, opens it, reads the tabs.
 * Nothing uploaded or deleted. deviceScaleFactor=3.
 *
 * Run (from frontend/):
 *   BIOMATE_URL=https://dev-public.biomate.ai node ../scripts/recording/capture-live-t4-focal.cjs
 * Output: recording/video/live-t4-focal/*.png (+ capture-log.json)
 */
const path = require("path");
const fs = require("fs");
const { chromium } = require(path.resolve(__dirname, "..", "..", "frontend", "node_modules", "@playwright", "test"));
const BASE_URL = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const EMAIL = "lifeifei163361@163.com";
const PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";
const DSF = Number(process.env.CAPTURE_DSF || 3);
const OUT = path.resolve(__dirname, "..", "..", "recording/video/live-t4-focal");
fs.mkdirSync(OUT, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = [];
const note = (m) => { log.push(m); console.log("[t4focal] " + m); };
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
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"] });
  const api = await browser.newContext();
  const resp = await api.request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "Content-Type": "application/json", "X-E2E-Test-Token": E2E_TOKEN },
    data: { email: EMAIL, password: PASSWORD } });
  if (!resp.ok()) throw new Error(`login failed ${resp.status()}`);
  const token = (await resp.json()).token; await api.close();
  const host = new URL(BASE_URL).hostname;
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: DSF,
    extraHTTPHeaders: { Authorization: `Bearer ${token}`, "X-E2E-Test-Token": E2E_TOKEN, "X-Forwarded-Proto": "https" } });
  await ctx.addCookies([{ name: "biomate_token", value: token, domain: host, path: "/", httpOnly: false, secure: true, sameSite: "Lax" }]);
  const page = await ctx.newPage();
  const shotEl = async (name, sel) => {
    try {
      const loc = page.locator(sel).first();
      if (!(await loc.count())) { note(`SKIP ${name} — no ${sel}`); return false; }
      await loc.scrollIntoViewIfNeeded().catch(() => {}); await sleep(400);
      await loc.screenshot({ path: path.join(OUT, name) });
      note(`OK ${name} (el ${sel}) @ ${DSF}x`); return true;
    } catch (e) { note(`ERR ${name} — ${e.message.split("\n")[0]}`); return false; }
  };
  const shotPage = async (name, clip) => { try { await page.screenshot({ path: path.join(OUT, name), clip }); note(`OK ${name} (page clip)`); return true; } catch (e) { note(`ERR ${name} — ${e.message.split("\n")[0]}`); return false; } };
  const dumpIds = async (tag) => {
    const ids = [...new Set(await page.evaluate(() => Array.from(document.querySelectorAll("[data-testid]")).map(e => e.getAttribute("data-testid"))))].sort();
    note(`${tag} testids: ` + JSON.stringify(ids.filter(x => /file|dataset|tree|quality|preview|lineage|consumer|version|origin|tab|detail|hub/i.test(x)).slice(0, 30)));
    return ids;
  };

  // Upload a readable demo CSV so the dataset object shows a real Preview +
  // Quality (the seeded editor.txt is a 1-byte Blocked file that can't teach it).
  const CSV = process.env.T4_CSV || path.resolve(__dirname, "..", "..", "..", "jak1_assay_demo.csv");
  const captured = {};
  try {
    await page.goto(`${BASE_URL}/files`, { waitUntil: "commit", timeout: 60000 });
    await page.getByTestId("data-hub").first().waitFor({ state: "visible", timeout: 90000 });
    await sleep(3000);
    // pick the first project
    const proj = page.locator('[data-testid^="data-hub-project-"]:not([data-testid="data-hub-project-grid"])').first();
    await proj.click().catch(() => {});
    await sleep(3000);

    // upload the demo CSV (idempotent-ish: a re-run just adds another version/row)
    if (fs.existsSync(CSV)) {
      try {
        await page.getByTestId("project-files-input").setInputFiles(CSV);
        note("uploaded " + path.basename(CSV));
        // wait for a row referencing the csv name to appear + profile
        await page.waitForFunction(() => /jak1_assay_demo/i.test(document.body.innerText || ""), undefined, { timeout: 45000 }).catch(() => {});
      } catch (e) { note("upload failed: " + e.message.split("\n")[0]); }
    } else { note("CSV not found at " + CSV + " — will capture whatever dataset exists"); }
    await sleep(6000); // let the profiler finish (quality dot)
    await dumpIds("hub");

    // ── DATA HUB (two-pane) ──────────────────────────────────────────────────
    captured.hub =
      (await shotEl("t4-data-hub.png", '[data-testid="data-hub"]')) ||
      (await shotPage("t4-data-hub.png"));

    // open the CSV dataset: find the file-open whose row mentions jak1_assay_demo
    const openedCsv = await page.evaluate(() => {
      const rows = Array.from(document.querySelectorAll('[data-testid^="file-open-"]'));
      for (const el of rows) {
        const container = el.closest('[class],li,tr,div');
        const txt = (container && container.textContent || "").toLowerCase();
        if (txt.includes("jak1_assay_demo")) { el.scrollIntoView(); el.click(); return true; }
      }
      return false;
    });
    if (!openedCsv) { const open = page.locator('[data-testid^="file-open-"]').first(); if (await open.count()) await open.click().catch(() => {}); }
    await sleep(2800);
    await dumpIds("object");

    // ── DATASET OBJECT (header + tabs) ───────────────────────────────────────
    captured.object =
      (await shotEl("t4-dataset-object.png", '[data-testid="dataset-object"]')) ||
      (await shotEl("t4-dataset-object.png", '[data-testid="dataset-detail"]')) ||
      (await shotEl("t4-dataset-object.png", '[data-testid="file-detail"]')) ||
      (await shotPage("t4-dataset-object.png"));

    // ── QUALITY TAB ──────────────────────────────────────────────────────────
    // click a tab/button labelled Quality
    try { await page.getByRole("tab", { name: /quality/i }).first().click({ timeout: 5000 }); }
    catch { try { await page.getByRole("button", { name: /^quality$/i }).first().click({ timeout: 5000 }); } catch { await page.getByText(/^Quality$/).first().click({ timeout: 5000 }).catch(() => {}); } }
    await sleep(1800); await dumpIds("quality");
    captured.quality =
      (await shotEl("t4-quality.png", '[data-testid="dataset-quality"]')) ||
      (await shotEl("t4-quality.png", '[data-testid="quality-tab"]')) ||
      (await shotEl("t4-quality.png", '[data-testid="dataset-object"]')) ||
      (await shotEl("t4-quality.png", '[data-testid="dataset-detail"]')) ||
      (await shotPage("t4-quality.png"));
  } catch (e) {
    note("CAPTURE ERROR: " + (e && e.message ? e.message.split("\n")[0] : e));
    try { await page.screenshot({ path: path.join(OUT, "_fail-state.png"), fullPage: true }); } catch {}
  }
  fs.writeFileSync(path.join(OUT, "capture-log.json"), JSON.stringify({ dsf: DSF, captured, log }, null, 2));
  await ctx.close(); await browser.close();
  console.log("\n=== t4 focal capture done ===\n" + log.join("\n"));
})();
