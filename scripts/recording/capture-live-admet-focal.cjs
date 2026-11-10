#!/usr/bin/env node
/**
 * Capture ONE real ADMET run on dev and save HIGH-DPI, FOCAL screenshots of the
 * workflow-panel elements that matter for each flagship-video live-UI scene:
 *
 *   prerun     → Parameters strip (Smiles List + Admet Model Type) + Confirm & Run
 *   running    → QC GATES list + the RUNNING phase card (N timepoints for motion)
 *   completed  → "Completed" badge + Findings Summary values
 *   outputs    → the 6-file Outputs table (names + view/dl)
 *   record     → reproducibility record fields (run id) + Outputs+checksums table
 *
 * deviceScaleFactor=3 so each tight focal crop is rendered at 3x — displaying it
 * in the slide frame magnifies the UI text while staying sharp (NOT an upscale of
 * a small crop). Every crop is taken from the right-hand panel (x > panel.left),
 * so the left chat column — including the honest "exit 1" line — is never in frame.
 *
 * Honesty: whatever the run produces is what gets captured. Nothing mocked.
 * Example compounds: aspirin / caffeine / ibuprofen (illustrative, not a campaign).
 *
 * Run (from frontend/):
 *   BIOMATE_URL=https://dev-public.biomate.ai node ../scripts/recording/capture-live-admet-focal.cjs
 *
 * Output: recording/video/live-admet-focal/*.png  (+ capture-log.json)
 */
const path = require("path");
const fs = require("fs");
const { chromium } = require(path.resolve(__dirname, "..", "..", "frontend", "node_modules", "@playwright", "test"));

const BASE_URL = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const EMAIL = "lifeifei163361@163.com";
const PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";
const DSF = Number(process.env.CAPTURE_DSF || 3);

const OUT = path.resolve(__dirname, "..", "..", "recording/video/live-admet-focal");
fs.mkdirSync(OUT, { recursive: true });

const ADMET_PROMPT =
  "Run the Predict ADMET Properties workflow on these SMILES and rank them by " +
  "developability: CC(=O)Oc1ccccc1C(=O)O, CN1C=NC2=C1C(=O)N(C(=O)N2C)C, " +
  "CC(C)Cc1ccc(C(C)C(=O)O)cc1";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = [];
const note = (m) => { log.push(m); console.log("[focal] " + m); };

// System Chrome (`channel:"chrome"`) can fail its CDP handshake on macOS when the
// user already has Chrome running. Prefer the bundled "Chrome for Testing" binary
// if present (version-agnostic glob of the ms-playwright cache); fall back to the
// channel. Override with PLAYWRIGHT_EXECUTABLE / PLAYWRIGHT_CHANNEL.
function resolveLaunch() {
  if (process.env.PLAYWRIGHT_EXECUTABLE) return { executablePath: process.env.PLAYWRIGHT_EXECUTABLE };
  if (process.env.PLAYWRIGHT_CHANNEL) return { channel: process.env.PLAYWRIGHT_CHANNEL };
  try {
    const cache = path.join(require("os").homedir(), "Library/Caches/ms-playwright");
    const dirs = fs.readdirSync(cache).filter((d) => d.startsWith("chromium-")).sort();
    for (const d of dirs.reverse()) {
      const exe = path.join(cache, d, "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing");
      if (fs.existsSync(exe)) return { executablePath: exe };
    }
  } catch {}
  return { channel: process.platform === "darwin" ? "chrome" : undefined };
}

(async () => {
  const browser = await chromium.launch({
    headless: true,
    ...resolveLaunch(),
    timeout: 60000,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage",
      "--autoplay-policy=no-user-gesture-required"],
  });

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
    viewport: { width: 1440, height: 1000 },
    deviceScaleFactor: DSF,
    extraHTTPHeaders: {
      Authorization: `Bearer ${token}`,
      "X-E2E-Test-Token": E2E_TOKEN,
      "X-Forwarded-Proto": "https",
    },
  });
  await ctx.addCookies([
    { name: "biomate_token", value: token, domain: host, path: "/", httpOnly: false, secure: true, sameSite: "Lax" },
  ]);

  const page = await ctx.newPage();

  // Browser-side helpers: compute a viewport-space clip rect (CSS px) from a set
  // of anchors. Anchor kinds: {testid}, {text} (exact leaf match), {testidPrefix}.
  await page.addInitScript(() => {
    window.__panelRect = () => {
      const p = document.querySelector('[data-testid="workflow-artifact-panel"]');
      if (!p) return null;
      const r = p.getBoundingClientRect();
      return { x: r.left, y: r.top, w: r.width, h: r.height, right: r.right, bottom: r.bottom };
    };
    window.__findByText = (txt) => {
      const out = [];
      const all = document.querySelectorAll('[data-testid="workflow-artifact-panel"] *');
      for (const el of all) {
        // leaf-ish: no element children carrying the same text, visible
        const t = (el.textContent || "").trim();
        if (t === txt) {
          const r = el.getBoundingClientRect();
          if (r.width > 0 && r.height > 0) out.push(el);
        }
      }
      // smallest matching element wins (most specific)
      out.sort((a, b) => (a.getBoundingClientRect().height * a.getBoundingClientRect().width) -
                         (b.getBoundingClientRect().height * b.getBoundingClientRect().width));
      return out[0] || null;
    };
  });

  // Clip rect from a union of DOM rects, clamped to the panel + viewport, padded.
  const clipFrom = async (spec) => {
    return await page.evaluate((spec) => {
      const panel = window.__panelRect();
      if (!panel) return null;
      const rects = [];
      for (const a of spec.anchors) {
        let els = [];
        if (a.testid) els = Array.from(document.querySelectorAll(`[data-testid="${a.testid}"]`));
        else if (a.testidPrefix) els = Array.from(document.querySelectorAll(`[data-testid^="${a.testidPrefix}"]`));
        else if (a.text) { const e = window.__findByText(a.text); if (e) els = [e]; }
        for (const el of els) {
          const r = el.getBoundingClientRect();
          if (r.width > 0 && r.height > 0) {
            rects.push({ top: r.top, bottom: r.bottom + (a.padBottom || 0), left: r.left, right: r.right });
          }
        }
      }
      if (!rects.length) return null;
      let top = Math.min(...rects.map(r => r.top));
      let bottom = Math.max(...rects.map(r => r.bottom));
      const padX = spec.padX ?? 14, padT = spec.padTop ?? 10, padB = spec.padB ?? 12;
      // X spans (most) of the panel width for a clean card look, unless tightX
      let left = spec.tightX ? Math.min(...rects.map(r => r.left)) - padX : panel.x + 10;
      let right = spec.tightX ? Math.max(...rects.map(r => r.right)) + padX : panel.right - 10;
      top -= padT; bottom += padB;
      // clamp to viewport
      top = Math.max(top, 0); bottom = Math.min(bottom, window.innerHeight);
      left = Math.max(left, panel.x + 2); right = Math.min(right, panel.right - 2);
      return { x: Math.round(left), y: Math.round(top), width: Math.round(right - left), height: Math.round(bottom - top) };
    }, spec);
  };

  const shotClip = async (name, spec) => {
    try {
      const clip = await clipFrom(spec);
      if (!clip || clip.width < 40 || clip.height < 20) { note(`SKIP ${name} — no/degenerate clip ${JSON.stringify(clip)}`); return false; }
      await page.screenshot({ path: path.join(OUT, name), clip });
      note(`OK ${name} ${clip.width}x${clip.height} (css) @ ${DSF}x`);
      return true;
    } catch (e) { note(`ERR ${name} — ${e.message.split("\n")[0]}`); return false; }
  };

  const shotEl = async (name, selector) => {
    try {
      const loc = page.locator(selector).first();
      if (!(await loc.count())) { note(`SKIP ${name} — no element ${selector}`); return false; }
      await loc.scrollIntoViewIfNeeded().catch(() => {});
      await sleep(300);
      await loc.screenshot({ path: path.join(OUT, name) });
      note(`OK ${name} (element ${selector}) @ ${DSF}x`);
      return true;
    } catch (e) { note(`ERR ${name} — ${e.message.split("\n")[0]}`); return false; }
  };

  const captured = {};
  try {
    // Dev can be slow to fire load/DCL (deferred prod bundle + long-lived SSE),
    // so commit the navigation fast, then gate on the chat-input actually being
    // visible with a generous timeout rather than the page load lifecycle.
    await page.goto(`${BASE_URL}/`, { waitUntil: "commit", timeout: 60000 });
    const input = page.getByTestId("chat-input");
    await input.waitFor({ state: "visible", timeout: 90000 });
    await sleep(4000);
    await input.click();
    await input.fill(ADMET_PROMPT);
    const sendReady = page.locator('[data-testid="chat-send-button"]:not([disabled])');
    await sendReady.waitFor({ state: "visible", timeout: 30000 });
    await sendReady.click({ timeout: 15000 });
    note("submitted ADMET request");

    // ── PRE-RUN ──────────────────────────────────────────────────────────
    const confirm = page.getByRole("button", { name: /confirm.*run/i });
    await confirm.first().waitFor({ timeout: 180000 });
    await sleep(3000);
    // ensure Required parameters open + scrolled to top of panel body
    await page.getByTestId("workflow-overall-status-badge").first().scrollIntoViewIfNeeded().catch(() => {});
    await sleep(500);
    captured.prerun_params = await shotClip("prerun-params.png", {
      anchors: [{ text: "Smiles List", padBottom: 70 }, { text: "Admet Model Type", padBottom: 70 }],
      padTop: 16, padB: 18,
    });
    captured.prerun_confirm = await shotClip("prerun-confirm.png", {
      anchors: [{ testid: "button-run-workflow-panel", padBottom: 0 }], padTop: 60, padB: 14,
    });
    // a fuller portrait fallback: params card + output-location (the editable strip)
    await shotClip("prerun-strip.png", {
      anchors: [{ text: "Smiles List" }, { testid: "output-location-section", padBottom: 10 }], padTop: 16, padB: 16,
    });

    // safety gate: only spend Batch if ADMET
    const bodyText = (await page.locator("body").innerText()).toLowerCase();
    if (!/admet/.test(bodyText)) { note("ABORT — generated workflow is NOT ADMET; no Batch spend"); throw new Error("not admet"); }

    const confirmBtn = page.getByRole("button", { name: /confirm.*run/i }).first();
    await confirmBtn.scrollIntoViewIfNeeded().catch(() => {});
    await confirmBtn.click({ timeout: 30000 }).catch(async () => { await confirmBtn.click({ force: true }); });
    note("confirmed & run");

    // ── RUNNING ──────────────────────────────────────────────────────────
    // Capture the phase-group (RUNNING phase card + QC GATES) across timepoints.
    try {
      await page.waitForFunction(() => !!document.querySelector('[data-status="running"]'), undefined, { timeout: 300000 });
      note("running observed");
      for (let i = 0; i < 7; i++) {
        // phase group holds the step cards + QC gates list
        const ok = await shotClip(`running-${i}.png`, {
          anchors: [{ testidPrefix: "phase-group-" }], padTop: 8, padB: 10, tightX: false,
        });
        if (!ok) { await shotEl(`running-${i}.png`, '[data-testid^="phase-group-"]'); }
        await sleep(2200);
      }
      // a crop that also includes the RUNNING overall badge at the top
      await shotClip("running-withbadge.png", {
        anchors: [{ testid: "workflow-overall-status-badge" }, { testidPrefix: "phase-group-", padBottom: 6 }],
        padTop: 8, padB: 10,
      });
      captured.running = true;
    } catch { note("SKIP running — not observed"); }

    // ── TERMINAL ─────────────────────────────────────────────────────────
    // Include Paused/Resume: a QC-gate / deliberate halt now surfaces as a
    // resumable 'Paused' state (not 'Restart'/'Failed'), so without these the
    // wait would hang 24 min on a paused run.
    await page.waitForFunction(
      () => /Run again|COMPLETED|Completed|FAILED|Failed|Restart|Paused|Resume/.test(document.body.innerText || ""),
      undefined, { timeout: 24 * 60 * 1000 },
    );
    note("terminal reached");
    await sleep(4000);

    // Dismiss the post-run "Quick feedback" survey if it popped up — it overlaps
    // the output cards and ruins the outputs capture.
    try {
      const survey = page.getByTestId("run-survey");
      if (await survey.count()) {
        const skip = page.getByRole("button", { name: /^skip$/i });
        if (await skip.count()) { await skip.first().click().catch(() => {}); }
        else { await survey.locator("button").first().click().catch(() => {}); }
        await sleep(800);
        note("dismissed post-run survey");
      }
    } catch { /* non-fatal */ }

    // open After run tab
    const afterRunTab = page.getByTestId("panel-tab-after-run");
    if (await afterRunTab.count()) { await afterRunTab.first().click().catch(() => {}); await sleep(1500); }

    // ── COMPLETED (Summary / Findings) ──────────────────────────────────
    // The landing "Results" tab holds the merged Findings + Outputs. (The old
    // separate "Summary"/"Outputs" tabs were merged into "results" — tab ids are
    // now "results" and "record"; findings live in after-summary-tab within it.)
    const resultsTab = page.getByTestId("after-tab-results");
    if (await resultsTab.count()) { await resultsTab.first().click().catch(() => {}); await sleep(1200); }
    captured.completed_findings = await shotEl("completed-findings.png", '[data-testid="after-summary-tab"]');
    captured.completed_badge = await shotClip("completed-badge.png", {
      anchors: [{ testid: "workflow-overall-status-badge", padBottom: 0 }], tightX: true, padX: 10, padTop: 8, padB: 8,
    });
    // badge + findings together (title row through findings metrics)
    await shotClip("completed-combo.png", {
      anchors: [{ testid: "workflow-overall-status-badge" }, { text: "Findings Summary", padBottom: 230 }],
      padTop: 8, padB: 14,
    });

    // ── OUTPUTS (now a SECTION inside the Results tab, not its own tab) ───
    // "after-tab-outputs" was removed when Outputs merged into Results. The
    // output-files-table lives below the findings in the results tab — scroll it
    // into view and shoot it there instead of clicking a tab that no longer exists.
    const outTable = page.getByTestId("output-files-table");
    await outTable.first().scrollIntoViewIfNeeded().catch(() => {});
    await sleep(1200);
    captured.outputs_table = await shotEl("outputs-table.png", '[data-testid="output-files-table"]');
    // outputs table + the "Download all … as ZIP" header row above it
    await shotClip("outputs-combo.png", {
      anchors: [{ testid: "output-files-table", padBottom: 10 }], padTop: 56, padB: 12,
    });

    // ── RECORD (Reproducibility) ────────────────────────────────────────
    const recTab = page.getByTestId("after-tab-record");
    if (await recTab.count()) { await recTab.first().click().catch(() => {}); await sleep(1500); }
    // compute checksums so SHA-256 column is populated (honest: real checksums)
    const cksum = page.getByTestId("repro-compute-checksums");
    if (await cksum.count()) { await cksum.first().click().catch(() => {}); await sleep(3500); }
    captured.record_intro = await shotEl("record-intro.png", '[data-testid="record-intro"]');
    captured.record_full = await shotEl("record-full.png", '[data-testid="repro-tab"]');
    // record fields (Workflow/Run id/Status/Created/Completed) — tight crop
    await shotClip("record-fields.png", {
      anchors: [{ text: "Run id" }, { text: "Completed", padBottom: 10 }], padTop: 48, padB: 12,
    });
    // outputs + checksums table within the record
    await shotClip("record-outputs.png", {
      anchors: [{ text: "Name" }, { text: "versions.yml", padBottom: 14 }], padTop: 48, padB: 12,
    });

    const runId = await page.evaluate(() => { const m = (window.location.href || "").match(/[0-9a-f-]{36}/); return m ? m[0] : ""; });
    note("runId: " + runId);
  } catch (e) {
    note("CAPTURE ERROR: " + (e && e.message ? e.message.split("\n")[0] : e));
    try { await page.screenshot({ path: path.join(OUT, "_fail-state.png") }); } catch {}
  }

  fs.writeFileSync(path.join(OUT, "capture-log.json"), JSON.stringify({ dsf: DSF, captured, log }, null, 2));
  await ctx.close();
  await browser.close();
  console.log("\n=== focal capture done ===\n" + log.join("\n"));
})();
