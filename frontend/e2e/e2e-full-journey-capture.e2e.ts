/**
 * End-to-end journey capture — the ENTIRE BioMate process, step by step, for
 * visual review. Numbered screenshots into a review folder the user can browse.
 *
 * Uses the genuinely-safe panel (aspirin / caffeine / ibuprofen) so the ADMET
 * run passes all gates and completes cleanly (no gate pause).
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai E2E_FIXTURE_PASSWORD='WpmFixture!2026' \
 *     npx playwright test e2e/e2e-full-journey-capture.e2e.ts --project=chromium --workers=1
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });

const OUT = "/Users/kky/Desktop/business/bioconductor_screenshot/e2e_review_20261020";
fs.mkdirSync(OUT, { recursive: true });

// Aspirin, caffeine, ibuprofen — the narration's safe panel (all gates pass).
const QUERY =
  "Screen these SMILES for ADMET liabilities and rank them by developability: " +
  "CC(=O)Oc1ccccc1C(=O)O, CN1C=NC2=C1C(=O)N(C(=O)N2C)C, CC(C)Cc1ccc(cc1)C(C)C(=O)O";

test("full BioMate journey → numbered end-to-end screenshots", async ({ page }) => {
  test.setTimeout(45 * 60 * 1000);
  await loginAsFixture(page);
  const log: string[] = [];
  let n = 0;
  const shot = async (label: string, el?: any) => {
    n += 1;
    const name = `${String(n).padStart(2, "0")}-${label}.png`;
    try {
      await (el ?? page).screenshot({ path: path.join(OUT, name) });
      log.push("OK   " + name);
    } catch (e: any) {
      log.push("MISS " + name + " — " + (e?.message?.split("\n")[0] ?? e));
    }
  };
  const dismissFeedback = async () => {
    for (const re of [/^not now$/i, /^skip$/i, /close/i]) {
      const b = page.getByRole("button", { name: re });
      if ((await b.count().catch(() => 0)) > 0) { await b.first().click({ timeout: 3000 }).catch(() => {}); return; }
    }
  };

  try {
    // 01 — Cold start (landing)
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
    const input = page.getByTestId("chat-input");
    await input.waitFor({ state: "visible", timeout: 45_000 });
    await page.waitForTimeout(3500);
    await shot("cold-start");

    // 02 — Goal typed in the composer
    await input.click();
    await input.fill(QUERY);
    await page.waitForTimeout(800);
    await shot("goal-typed");

    // Send
    const send = page.locator('[data-testid="chat-send-button"]:not([disabled])');
    await send.waitFor({ state: "visible", timeout: 30_000 });
    await send.click({ timeout: 15_000 });
    log.push("submitted ADMET request");

    // 03 — AI response begins (analysis plan / routing)
    await page.waitForTimeout(8000);
    await shot("ai-response-plan");

    // 04 — Workflow card + panel prerun (full page)
    const confirm = page.getByRole("button", { name: /confirm.*run/i });
    await confirm.first().waitFor({ timeout: 220_000 });
    await page.waitForTimeout(4000);
    await shot("prerun-full-page");

    // 05 — Workflow panel (right) prerun
    const panel = page.getByTestId("workflow-right-panel");
    if ((await panel.count().catch(() => 0)) > 0) await shot("prerun-panel", panel.first());

    // Safety: only spend Batch if routed to ADMET
    const panelText = (await page.locator("body").innerText()).toLowerCase();
    if (!/admet|herg|toxicity|predict_admet|cyp/.test(panelText)) {
      log.push("ABORT — did not route to ADMET; kept prerun only, no Batch spend");
      console.log("\n[e2e journey]\n" + log.join("\n") + "\n");
      return;
    }

    // 06 — Confirm & run → running
    await confirm.first().click({ timeout: 30_000 }).catch(async () => { await confirm.first().click({ force: true }); });
    log.push("clicked Confirm & run");
    try {
      await page.waitForFunction(() => !!document.querySelector('[data-status="running"]'), null, { timeout: 240_000 });
      await page.waitForTimeout(2000);
      await shot("running");
    } catch { log.push("SKIP running (not observed in 240s)"); }

    // 07 — a later running/progress state
    await page.waitForTimeout(20_000);
    await shot("running-progress");

    // Drive to clean completion (safe compounds → no gate; resume if one appears)
    let completed = false;
    for (let i = 0; i < 150; i++) {
      await page.waitForTimeout(4000);
      const body = await page.locator("body").innerText();
      const paused = /Paused on a safety QC gate|Resume from last step/i.test(body);
      if (/Run again|Download report/i.test(body) && !paused && !/Restart|RUN FAILED/i.test(body)) { completed = true; break; }
      if (paused) {
        const resume = page.getByRole("button", { name: /resume from last step/i });
        if ((await resume.count().catch(() => 0)) > 0 && await resume.first().isEnabled().catch(() => false)) {
          await resume.first().click({ timeout: 8000 }).catch(() => {});
          log.push("Resume past gate (attempt " + (i + 1) + ")");
          await page.waitForTimeout(4000);
        }
      }
    }
    log.push(completed ? "terminal: COMPLETED (clean)" : "WARN did not reach clean completion");
    await page.waitForTimeout(3000);
    await dismissFeedback();
    await page.waitForTimeout(1500);

    // 08 — Completed (full page)
    await shot("completed-full-page");
    // 09 — Completed panel
    if ((await panel.count().catch(() => 0)) > 0) await shot("completed-panel", panel.first());

    // 10 — Results / Findings
    for (const re of [/^results$/i, /^findings$/i, /^summary$/i]) {
      const t = page.getByRole("tab", { name: re }).or(page.getByText(re, { exact: false }));
      if ((await t.count().catch(() => 0)) > 0) { await t.first().click({ timeout: 5000 }).catch(() => {}); break; }
    }
    await page.waitForTimeout(2500);
    await shot("results-findings");

    // 11 — Outputs
    for (const re of [/^outputs$/i, /output files/i]) {
      const t = page.getByRole("tab", { name: re }).or(page.getByText(re, { exact: false }));
      if ((await t.count().catch(() => 0)) > 0) { await t.first().click({ timeout: 5000 }).catch(() => {}); break; }
    }
    await page.waitForTimeout(2500);
    await shot("outputs");

    // 12 — An output file preview (click first previewable output)
    const prev = page.getByText(/\.(json|txt|csv|tsv)$/i).first();
    if ((await prev.count().catch(() => 0)) > 0) { await prev.click({ timeout: 5000 }).catch(() => {}); await page.waitForTimeout(2000); }
    await shot("output-file-preview");

    // 13 — Reproducibility record
    const rec = page.getByRole("tab", { name: /reproducib|record/i }).or(page.getByText(/Reproducibility record/i, { exact: false }));
    if ((await rec.count().catch(() => 0)) > 0) { await rec.first().click({ timeout: 5000 }).catch(() => {}); }
    await page.waitForTimeout(2500);
    await shot("reproducibility-record");

    // 14 — Download menu on the after-run report
    const dl = page.getByTestId("afterrun-download-toggle");
    if ((await dl.count().catch(() => 0)) > 0) { await dl.first().click({ timeout: 4000 }).catch(() => {}); await page.waitForTimeout(800); await shot("download-menu"); }

    // 15 — Data hub (project picker)
    await page.goto(BASE_URL + "/files", { waitUntil: "domcontentloaded", timeout: 60_000 });
    await page.waitForTimeout(4000);
    await shot("data-hub-projects");

    // 16 — Data hub: open a project + a file → dataset object
    const proj = page.getByTestId(/^data-hub-project-/).first();
    if ((await proj.count().catch(() => 0)) > 0) {
      await proj.click({ timeout: 5000 }).catch(() => {});
      await page.waitForTimeout(3000);
      await shot("data-hub-filetree");
      const fileRow = page.locator('[data-testid^="file-open-"]').first();
      if ((await fileRow.count().catch(() => 0)) > 0) {
        await fileRow.click({ timeout: 5000 }).catch(() => {});
        await page.waitForTimeout(3500);
        await shot("dataset-object-preview");
        // Where it came from tab
        const wf = page.getByTestId("dataset-tab-wherefrom");
        if ((await wf.count().catch(() => 0)) > 0) { await wf.click({ timeout: 4000 }).catch(() => {}); await page.waitForTimeout(2500); await shot("dataset-where-from"); }
      }
    }

    // 17 — Workflows page
    await page.goto(BASE_URL + "/workflows", { waitUntil: "domcontentloaded", timeout: 60_000 }).catch(() => {});
    await page.waitForTimeout(3500);
    await shot("workflows-page");

    // 18 — Models page
    await page.goto(BASE_URL + "/models", { waitUntil: "domcontentloaded", timeout: 60_000 }).catch(() => {});
    await page.waitForTimeout(3500);
    await shot("models-page");
  } catch (e: any) {
    log.push("FAIL — " + (e?.message?.split("\n")[0] ?? e));
  }
  console.log("\n[e2e journey] OUT=" + OUT + "\n" + log.join("\n") + "\n");
  expect(log.some((l) => l.includes("cold-start"))).toBe(true);
});
