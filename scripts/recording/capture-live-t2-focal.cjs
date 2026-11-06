#!/usr/bin/env node
/**
 * Capture HIGH-DPI, FOCAL screenshots of the live /models area for the T2 video:
 *   t2-registry.png     → the Registry tab (model rows: name/family/origin/used-by)
 *   t2-model-object.png → a model shown as an object (Evidence/Lineage/Used by/Versions)
 *   t2-run.png          → the "Run a model" (inference) form
 *   t2-rounds.png       → the Rounds (closed-loop) empty-state with its honesty rules
 *
 * Read-only: navigates tabs, opens one model, captures. Nothing is trained/run.
 * deviceScaleFactor=3. Honesty: whatever the live screen shows is captured as-is
 * (incl. "not evaluated" / stub labels).
 *
 * Run (from frontend/):
 *   BIOMATE_URL=https://dev-public.biomate.ai node ../scripts/recording/capture-live-t2-focal.cjs
 * Output: recording/video/live-t2-focal/*.png (+ capture-log.json)
 */
const path = require("path");
const fs = require("fs");
const { chromium } = require(path.resolve(__dirname, "..", "..", "frontend", "node_modules", "@playwright", "test"));
const BASE_URL = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const EMAIL = "lifeifei163361@163.com";
const PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";
const DSF = Number(process.env.CAPTURE_DSF || 3);
const OUT = path.resolve(__dirname, "..", "..", "recording/video/live-t2-focal");
fs.mkdirSync(OUT, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = [];
const note = (m) => { log.push(m); console.log("[t2focal] " + m); };
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
  const clickTab = async (label) => {
    try { await page.getByRole("button", { name: new RegExp("^" + label + "$", "i") }).first().click({ timeout: 8000 }); await sleep(1400); return true; }
    catch { try { await page.getByText(new RegExp("^" + label + "$", "i")).first().click({ timeout: 6000 }); await sleep(1400); return true; } catch { return false; } }
  };
  const dumpIds = async (tag) => {
    const ids = [...new Set(await page.evaluate(() => Array.from(document.querySelectorAll("[data-testid]")).map(e => e.getAttribute("data-testid"))))].sort();
    note(`${tag} testids: ` + JSON.stringify(ids.filter(x => /registry|model|run|round|evidence|lineage|version|object|track|used|floor|infer|domain/i.test(x))));
    return ids;
  };

  const captured = {};
  try {
    await page.goto(`${BASE_URL}/models`, { waitUntil: "commit", timeout: 60000 });
    await page.getByTestId("models-panel").first().waitFor({ state: "visible", timeout: 90000 });
    await sleep(3500);

    // ── REGISTRY ───────────────────────────────────────────────────────────
    await clickTab("Registry"); await dumpIds("registry");
    captured.registry =
      (await shotEl("t2-registry.png", '[data-testid="registry-table"]')) ||
      (await shotEl("t2-registry.png", '[data-testid="models-panel"]'));

    // open the first model row to get the object view
    const row = page.locator('[data-testid^="registry-row-"], [data-testid^="model-row-"]').first();
    if (await row.count()) { await row.click().catch(() => {}); await sleep(1500); }
    else { // fallback: click a model name link if present
      await page.getByText(/Boltz-2|AlphaFold2|OpenFold2|Evo2/).first().click({ timeout: 6000 }).catch(() => {});
      await sleep(1500);
    }
    await dumpIds("model-object");
    captured.model_object =
      (await shotEl("t2-model-object.png", '[data-testid="model-object"]')) ||
      (await shotEl("t2-model-object.png", '[data-testid="model-detail"]')) ||
      (await shotEl("t2-model-object.png", '[data-testid="models-panel"]'));

    // reload to leave the model-object view and get a clean track bar.
    // tab order: track-0 Train, track-1 House style, track-2 Rounds, track-3 Run a model, track-4 Registry.
    await page.goto(`${BASE_URL}/models`, { waitUntil: "commit", timeout: 60000 });
    await page.getByTestId("models-panel").first().waitFor({ state: "visible", timeout: 60000 });
    await sleep(2500);

    // ── RUN A MODEL (inference) ──────────────────────────────────────────────
    await page.getByTestId("models-track-3").click().catch(() => {});
    await sleep(1500); await dumpIds("run");
    captured.run =
      (await shotEl("t2-run.png", '[data-testid="run-pretrained"]')) ||
      (await shotEl("t2-run.png", '[data-testid="models-panel"]'));

    // ── ROUNDS (closed loop, empty state) ────────────────────────────────────
    await page.getByTestId("models-track-2").click().catch(() => {});
    await sleep(1500); await dumpIds("rounds");
    captured.rounds =
      (await shotEl("t2-rounds.png", '[data-testid="track-optimise"]')) ||
      (await shotEl("t2-rounds.png", '[data-testid="models-panel"]'));
  } catch (e) {
    note("CAPTURE ERROR: " + (e && e.message ? e.message.split("\n")[0] : e));
    try { await page.screenshot({ path: path.join(OUT, "_fail-state.png"), fullPage: true }); } catch {}
  }
  fs.writeFileSync(path.join(OUT, "capture-log.json"), JSON.stringify({ dsf: DSF, captured, log }, null, 2));
  await ctx.close(); await browser.close();
  console.log("\n=== t2 focal capture done ===\n" + log.join("\n"));
})();
