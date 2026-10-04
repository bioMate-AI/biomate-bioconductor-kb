/**
 * ONE real end-to-end run on the fixture account to capture the dynamic
 * workflow-panel states that /debug/viewer (hardcoded completed, no findings)
 * cannot show: pre-run param strip, running phase card, completed + POPULATED
 * findings, outputs. A cheap ADMET-from-SMILES run (~15 min, real Batch).
 *
 * Honesty: captures whatever the run actually produces — if it fails, the
 * FAILED state is captured (also a real figure). Nothing mocked.
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     npx playwright test e2e/real-run-capture.e2e.ts --project=chromium
 */
import { test } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 2 });
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");

const ADMET_PROMPT =
  "Run the Predict ADMET Properties workflow on these SMILES and rank them by " +
  "developability: CC(=O)Oc1ccccc1C(=O)O, CN1C=NC2=C1C(=O)N(C(=O)N2C)C, " +
  "CC(C)Cc1ccc(C(C)C(=O)O)cc1";

test("real ADMET run — capture dynamic panel states", async ({ page }) => {
  test.setTimeout(32 * 60 * 1000); // 32 min
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string) => { await page.screenshot({ path: path.join(ASSETS, name) }); log.push("OK   " + name); };

  try {
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 45_000 });

    // 1. Submit an explicit ADMET request via the composer. Gate every step on
    //    READINESS, not fixed timeouts — the production build on dev defers JS, so
    //    interacting before hydration (or while a prior stream is active) races:
    //    chat-send-button only renders when NOT streaming (else it's the stop button)
    //    and is disabled until message.trim() registers in React state.
    const input = page.getByTestId("chat-input");
    await input.waitFor({ state: "visible", timeout: 30_000 });
    await page.waitForTimeout(3000); // hydration settle for the deferred bundle
    await input.click();
    await input.fill(ADMET_PROMPT);
    // Wait for the send button to be present AND enabled before clicking.
    const sendReady = page.locator('[data-testid="chat-send-button"]:not([disabled])');
    await sendReady.waitFor({ state: "visible", timeout: 30_000 });
    await sendReady.click({ timeout: 15_000 });
    log.push("submitted ADMET request");

    // 2. Wait for the workflow card / pre-run panel (Confirm & run). LLM gen up to 180s.
    const confirm = page.getByRole("button", { name: /confirm.*run/i });
    await confirm.first().waitFor({ timeout: 180_000 });
    await page.waitForTimeout(3500);
    await shot("r1-prerun-param-strip.png"); // pre-run: workflow name + param strip (FREE)

    // 3. SAFETY GATE: only spend a Batch run if the generated workflow is the cheap
    //    ADMET one. Lane routing can misclassify (it read a prior ADMET prompt as
    //    variant_calling) — a wrong/heavy run would waste money. If not ADMET, keep
    //    r1 and stop with NO Batch spend.
    const panelText = (await page.locator("body").innerText()).toLowerCase();
    if (!/admet/.test(panelText)) {
      log.push("ABORT run — generated workflow is NOT ADMET (routing); kept r1 only, no Batch spend. panel='" + panelText.slice(0, 160).replace(/\n/g, " ") + "'");
    } else {
      const confirmBtn = page.getByRole("button", { name: /confirm.*run/i }).first();
      await confirmBtn.waitFor({ state: "visible", timeout: 30_000 });
      await confirmBtn.scrollIntoViewIfNeeded().catch(() => {});
      await confirmBtn.click({ timeout: 30_000 }).catch(async () => { await confirmBtn.click({ timeout: 15_000, force: true }); });
      log.push("clicked Confirm & run (ADMET confirmed)");

      // 4. RUNNING state — poll for any phase card data-status=running.
      try {
        await page.waitForFunction(() => !!document.querySelector('[data-status="running"]'), { timeout: 240_000 });
        await page.waitForTimeout(1500);
        await shot("r2-running.png");
      } catch { log.push("SKIP r2-running (running state not observed in 240s)"); }

      // 5. Terminal state — Completed or Failed — up to ~24 min.
      await page.waitForFunction(
        () => /Run again|COMPLETED|Completed|FAILED|Failed|Restart/.test(document.body.innerText || ""),
        { timeout: 24 * 60 * 1000 },
      );
      await page.waitForTimeout(5000);
      await shot("r3-terminal.png");

      // 6. Findings (populated or unavailable — whichever is real).
      const fc = page.getByTestId("findings-card");
      if ((await fc.count()) > 0) { await fc.first().scrollIntoViewIfNeeded().catch(() => {}); await page.waitForTimeout(1500); await shot("r4-findings.png"); }
      else { log.push("SKIP r4-findings (no findings-card)"); }

      // 7. Outputs tab, if present.
      const outTab = page.getByText(/^Outputs$/).first();
      if ((await outTab.count()) > 0) { await outTab.click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(2500); await shot("r5-outputs.png"); }
    }

    // 8. Record the run id / url for the follow-up (debug viewer + dataset lineage).
    const runId = await page.evaluate(() => {
      try { const m = window.location.href.match(/[0-9a-f-]{36}/); return m ? m[0] : window.location.href; }
      catch { return "unknown"; }
    });
    log.push("RUN_URL/ID: " + runId);
    log.push("HREF: " + page.url());
  } catch (e: any) {
    log.push("FAIL real-run — " + (e?.message?.split("\n")[0] ?? e));
    try { await shot("r-fail-state.png"); } catch { /* ignore */ }
  }
  // eslint-disable-next-line no-console
  console.log("\n[real-run-capture]\n" + log.join("\n") + "\n");
});
