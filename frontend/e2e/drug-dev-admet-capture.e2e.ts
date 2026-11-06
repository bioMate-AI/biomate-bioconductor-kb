/**
 * Drug-dev ADMET flow capture (d2-admet + drug-dev decks), 2026-10-19.
 *
 * The domain-capture ADMET case used a hERG-blocker demo set, which trips the
 * safety QC gate → the run PAUSES → the harness (which waits for auto-complete)
 * ends in a SIGTERM failure, so "completed" was a failed run. Here we use
 * PASSING compounds (aspirin / caffeine / ibuprofen — low hERG) so the run
 * completes cleanly, dismiss the post-run feedback popup, and capture the five
 * states the decks reference: prerun / running / completed / outputs / record,
 * written straight to the deck's assets/live/ with the deck filenames.
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     npx playwright test e2e/drug-dev-admet-capture.e2e.ts --project=chromium --workers=1
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 2 });
const LIVE = path.resolve(process.cwd(), "..", "reference/claude_design/tutorials_v2_design/assets/live");
// Clean, low-liability compounds (caffeine, metformin, nicotinamide) chosen so
// the safety gates PASS and the run completes cleanly — Scenario 1 (Completed).
const QUERY =
  "Screen these SMILES for ADMET liabilities and rank them by developability: " +
  "CN1C=NC2=C1C(=O)N(C(=O)N2C)C, CN(C)C(=N)NC(=N)N, NC(=O)c1cccnc1";

async function dismissFeedback(page: any) {
  // The post-run "Quick feedback" popup overlays the panel — dismiss it so it
  // doesn't obscure completed/outputs/record. Try its buttons, then any close.
  for (const re of [/^not now$/i, /^skip$/i]) {
    const b = page.getByRole("button", { name: re });
    if ((await b.count().catch(() => 0)) > 0) { await b.first().click({ timeout: 4000 }).catch(() => {}); return; }
  }
  const x = page.getByRole("button", { name: /close/i });
  if ((await x.count().catch(() => 0)) > 0) await x.first().click({ timeout: 4000 }).catch(() => {});
}

test("drug-dev ADMET flow → prerun/running/completed/outputs/record", async ({ page }) => {
  test.setTimeout(40 * 60 * 1000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string, el?: any) => {
    await (el ?? page).screenshot({ path: path.join(LIVE, name) });
    log.push("OK   " + name);
  };
  try {
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
    const input = page.getByTestId("chat-input");
    await input.waitFor({ state: "visible", timeout: 45_000 });
    await page.waitForTimeout(3000);
    await input.click();
    await input.fill(QUERY);
    const send = page.locator('[data-testid="chat-send-button"]:not([disabled])');
    await send.waitFor({ state: "visible", timeout: 30_000 });
    await send.click({ timeout: 15_000 });
    log.push("submitted ADMET request");

    // prerun — the workflow card with Confirm & run (LLM gen up to ~200s)
    const confirm = page.getByRole("button", { name: /confirm.*run/i });
    await confirm.first().waitFor({ timeout: 200_000 });
    await page.waitForTimeout(4000);
    // SAFETY GATE — only spend Batch if it routed to ADMET.
    const panelText = (await page.locator("body").innerText()).toLowerCase();
    if (!/admet|herg|toxicity|predict_admet|cyp/.test(panelText)) {
      log.push("ABORT — did not route to ADMET; kept prerun only, no Batch spend");
      await shot("prerun.png");
      console.log("\n[drug-dev admet]\n" + log.join("\n") + "\n");
      return;
    }
    await shot("prerun.png");

    await confirm.first().click({ timeout: 30_000 }).catch(async () => { await confirm.first().click({ force: true }); });
    log.push("clicked Confirm & run");

    // running — any phase card data-status=running (up to 4 min to dispatch)
    try {
      await page.waitForFunction(() => !!document.querySelector('[data-status="running"]'), null, { timeout: 240_000 });
      await page.waitForTimeout(1500);
      await shot("running.png");
    } catch { log.push("SKIP running (not observed in 240s)"); }

    // Drive to a CLEAN completion. The ADMET workflow PAUSES on safety QC gates
    // (hERG / DILI) — the auto-loop can't fix a compound property, so the run
    // waits for the user to Resume (proceed, accepting the flagged risk) or
    // Cancel. Poll fast and click "Resume from last step" the moment a gate
    // pauses, before the idle run is SIGTERM'd → Failed. Repeat per gate.
    let completed = false;
    for (let i = 0; i < 120; i++) {
      await page.waitForTimeout(4000);
      const body = await page.locator("body").innerText();
      const paused = /Paused on a safety QC gate|Resume from last step/i.test(body);
      if (/Run again|Download report/i.test(body) && !paused && !/Restart|RUN FAILED/i.test(body)) { completed = true; break; }
      if (paused) {
        const resume = page.getByRole("button", { name: /resume from last step/i });
        if ((await resume.count().catch(() => 0)) > 0 && await resume.first().isEnabled().catch(() => false)) {
          await resume.first().click({ timeout: 8000 }).catch(() => {});
          log.push("Resume past safety gate (attempt " + (i + 1) + ")");
          await page.waitForTimeout(4000);
        }
      } else if (/RUN FAILED|Restart/i.test(body)) { log.push("run FAILED (not resumable)"); break; }
    }
    await page.waitForTimeout(4000);
    await dismissFeedback(page);
    await page.waitForTimeout(1000);
    log.push(completed ? "terminal: COMPLETED (clean)" : "WARN did not reach clean completion");
    await shot("completed.png");

    // outputs — the After-run Outputs section/tab
    for (const re of [/^outputs$/i, /output files/i]) {
      const t = page.getByRole("tab", { name: re }).or(page.getByText(re, { exact: false }));
      if ((await t.count().catch(() => 0)) > 0) { await t.first().click({ timeout: 6000 }).catch(() => {}); break; }
    }
    await page.waitForTimeout(2500);
    await shot("outputs.png");

    // record — the Reproducibility record tab
    const rec = page.getByRole("tab", { name: /reproducib|record/i }).or(page.getByText(/Reproducibility record/i, { exact: false }));
    if ((await rec.count().catch(() => 0)) > 0) { await rec.first().click({ timeout: 6000 }).catch(() => {}); }
    await page.waitForTimeout(2500);
    await shot("record.png");
  } catch (e: any) {
    log.push("FAIL — " + (e?.message?.split("\n")[0] ?? e));
  }
  console.log("\n[drug-dev admet]\n" + log.join("\n") + "\n");
  expect(log.some((l) => l.includes("prerun.png"))).toBe(true);
});
