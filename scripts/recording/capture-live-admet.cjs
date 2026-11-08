#!/usr/bin/env node
/**
 * Capture ONE real ADMET run on dev as a single continuous screencast (webm),
 * logging milestone offsets so the slide-builder can slice per-scene live-UI
 * clips (pre-run strip, RUNNING phase cards, COMPLETED summary/findings,
 * Outputs tab, Reproducibility record).
 *
 * Honesty: whatever the run produces is what gets recorded. Nothing mocked.
 * Running example compounds: aspirin / caffeine / ibuprofen (illustrative).
 *
 * Run (from frontend/):
 *   BIOMATE_URL=https://dev-public.biomate.ai node ../scripts/recording/capture-live-admet.cjs
 *
 * Output:
 *   recording/video/live-admet/session.webm
 *   recording/video/live-admet/milestones.json   { label: ms_from_context_create }
 */
const path = require("path");
const fs = require("fs");
// Use @playwright/test's chromium (matches the installed browser build, 1223).
const { chromium } = require(path.resolve(__dirname, "..", "..", "frontend", "node_modules", "@playwright", "test"));

const BASE_URL = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const EMAIL = "lifeifei163361@163.com";
const PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";

const OUT = path.resolve(__dirname, "..", "..", "recording/video/live-admet");
fs.mkdirSync(OUT, { recursive: true });

// aspirin, caffeine, ibuprofen
const ADMET_PROMPT =
  "Run the Predict ADMET Properties workflow on these SMILES and rank them by " +
  "developability: CC(=O)Oc1ccccc1C(=O)O, CN1C=NC2=C1C(=O)N(C(=O)N2C)C, " +
  "CC(C)Cc1ccc(C(C)C(=O)O)cc1";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const browser = await chromium.launch({
    headless: true,
    channel: process.env.PLAYWRIGHT_CHANNEL || (process.platform === "darwin" ? "chrome" : undefined),
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage",
      "--autoplay-policy=no-user-gesture-required"],
  });

  // Login via Playwright HTTP stack (bypasses CSRF; works before hydration).
  const api = await browser.newContext();
  const resp = await api.request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "Content-Type": "application/json", "X-E2E-Test-Token": E2E_TOKEN },
    data: { email: EMAIL, password: PASSWORD },
  });
  if (!resp.ok()) throw new Error(`login failed ${resp.status()}: ${await resp.text()}`);
  const token = (await resp.json()).token;
  if (!token) throw new Error("no token in login response");
  await api.close();

  const host = new URL(BASE_URL).hostname;
  const ctx = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    recordVideo: { dir: OUT, size: { width: 1920, height: 1080 } },
    extraHTTPHeaders: {
      Authorization: `Bearer ${token}`,
      "X-E2E-Test-Token": E2E_TOKEN,
      "X-Forwarded-Proto": "https",
    },
  });
  const t0 = Date.now();
  await ctx.addCookies([
    { name: "biomate_token", value: token, domain: host, path: "/", httpOnly: false, secure: true, sameSite: "Lax" },
  ]);

  const milestones = {};
  const mark = (label) => { milestones[label] = Date.now() - t0; console.log(`[mark] ${label} @ ${milestones[label]}ms`); };

  const page = await ctx.newPage();
  try {
    await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded", timeout: 60000 });
    mark("page_loaded");

    const input = page.getByTestId("chat-input");
    await input.waitFor({ state: "visible", timeout: 45000 });
    await sleep(3500); // hydration settle (deferred prod bundle)
    await input.click();
    await input.fill(ADMET_PROMPT);
    const sendReady = page.locator('[data-testid="chat-send-button"]:not([disabled])');
    await sendReady.waitFor({ state: "visible", timeout: 30000 });
    await sendReady.click({ timeout: 15000 });
    mark("submitted");

    // pre-run panel (Confirm & run) — LLM gen up to 180s
    const confirm = page.getByRole("button", { name: /confirm.*run/i });
    await confirm.first().waitFor({ timeout: 180000 });
    await sleep(2500);
    mark("prerun_ready");
    // dwell on pre-run: gentle scroll of the panel to reveal the param strip
    await sleep(5000);
    await page.mouse.wheel(0, 260).catch(() => {});
    await sleep(2500);
    await page.mouse.wheel(0, -260).catch(() => {});
    await sleep(1500);
    mark("prerun_end");

    // safety gate: only spend Batch if ADMET
    const bodyText = (await page.locator("body").innerText()).toLowerCase();
    if (!/admet/.test(bodyText)) {
      mark("ABORT_not_admet");
      throw new Error("generated workflow is NOT ADMET — aborting, no Batch spend");
    }

    const confirmBtn = page.getByRole("button", { name: /confirm.*run/i }).first();
    await confirmBtn.scrollIntoViewIfNeeded().catch(() => {});
    await confirmBtn.click({ timeout: 30000 }).catch(async () => { await confirmBtn.click({ force: true }); });
    mark("confirmed");

    // RUNNING — capture the live phase-card motion window
    try {
      await page.waitForFunction(() => !!document.querySelector('[data-status="running"]'), undefined, { timeout: 300000 });
      mark("running");
      await sleep(16000); // dwell to capture pending->running->completed card flips
      mark("running_end");
    } catch { mark("running_not_observed"); }

    // Terminal — up to ~24 min
    await page.waitForFunction(
      () => /Run again|COMPLETED|Completed|FAILED|Failed|Restart/.test(document.body.innerText || ""),
      undefined,
      { timeout: 24 * 60 * 1000 },
    );
    mark("terminal");
    await sleep(4000);

    // Summary / findings tab
    const summaryTab = page.getByTestId("after-tab-summary");
    if (await summaryTab.count()) { await summaryTab.first().click().catch(() => {}); }
    await sleep(1500);
    mark("summary");
    await sleep(8000);
    mark("summary_end");

    // Outputs tab
    const outTab = page.getByTestId("after-tab-outputs");
    if (await outTab.count()) {
      await outTab.first().click().catch(() => {});
      await sleep(2000);
      mark("outputs");
      await sleep(5000);
      await page.mouse.wheel(0, 300).catch(() => {});
      await sleep(3000);
      await page.mouse.wheel(0, -300).catch(() => {});
      await sleep(1500);
      mark("outputs_end");
    } else { mark("outputs_missing"); }

    // Reproducibility record tab
    const recTab = page.getByTestId("after-tab-record");
    if (await recTab.count()) {
      await recTab.first().click().catch(() => {});
      await sleep(2000);
      mark("record");
      await sleep(5000);
      await page.mouse.wheel(0, 320).catch(() => {});
      await sleep(3000);
      await page.mouse.wheel(0, -320).catch(() => {});
      await sleep(1500);
      mark("record_end");
    } else { mark("record_missing"); }

    const runId = await page.evaluate(() => {
      const m = (window.location.href || "").match(/[0-9a-f-]{36}/);
      return m ? m[0] : window.location.href;
    });
    milestones.runId = runId;
    milestones.href = page.url();
    mark("done");
  } catch (e) {
    milestones.error = String(e && e.message ? e.message : e);
    console.error("CAPTURE ERROR:", milestones.error);
  }

  const video = page.video();
  await ctx.close(); // finalizes the webm
  const videoPath = video ? await video.path().catch(() => null) : null;
  await browser.close();

  // normalize the webm filename
  let finalWebm = videoPath;
  if (videoPath && fs.existsSync(videoPath)) {
    finalWebm = path.join(OUT, "session.webm");
    fs.renameSync(videoPath, finalWebm);
  }
  milestones.video = finalWebm;
  fs.writeFileSync(path.join(OUT, "milestones.json"), JSON.stringify(milestones, null, 2));
  console.log("\n=== milestones ===\n" + JSON.stringify(milestones, null, 2));
  console.log("video ->", finalWebm);
})();
