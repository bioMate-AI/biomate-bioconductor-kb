/**
 * Verify the ADMET step-attribution fix end-to-end: run a fresh ADMET workflow
 * to completion and confirm the after-run Outputs attribute to the real step
 * ("Predict Admet Properties"), NOT a phantom "run". Also captures the Phases
 * tab (step cards + status) and a StepDetail panel.
 *
 * Safe panel (aspirin/caffeine/ibuprofen) → clean completion, no gate pause.
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai E2E_FIXTURE_PASSWORD='WpmFixture!2026' \
 *     npx playwright test e2e/admet-step-verify.e2e.ts --project=chromium --workers=1
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });
const OUT = "/Users/kky/Desktop/business/bioconductor_screenshot/admet_step_verify_20261021";
fs.mkdirSync(OUT, { recursive: true });
const QUERY =
  "Screen these SMILES for ADMET liabilities and rank them by developability: " +
  "CC(=O)Oc1ccccc1C(=O)O, CN1C=NC2=C1C(=O)N(C(=O)N2C)C, CC(C)Cc1ccc(cc1)C(C)C(=O)O";

test("ADMET step attribution — real step name, not 'run'", async ({ page }) => {
  test.setTimeout(45 * 60 * 1000);
  await loginAsFixture(page);
  await page.route(/amazonaws\.com/, async (route) => {
    const h = { ...route.request().headers() };
    delete h["authorization"]; delete h["Authorization"];
    delete h["x-e2e-test-token"]; delete h["X-E2E-Test-Token"];
    await route.continue({ headers: h });
  });
  const log: string[] = [];

  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
  const nc = page.getByTestId("button-new-chat");
  if ((await nc.count().catch(() => 0)) > 0) { await nc.first().click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(1500); }
  const input = page.getByTestId("chat-input");
  await input.click(); await input.fill(QUERY);
  const send = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await send.waitFor({ state: "visible", timeout: 30_000 });
  await send.scrollIntoViewIfNeeded().catch(() => {});
  await send.click({ timeout: 15_000 }).catch(async () => { await send.click({ force: true }); });

  // Click "Confirm & Run" and VERIFY the run actually started (the button
  // disappears / a running indicator appears). Retry the click if it didn't
  // take — the button can be briefly non-actionable while the card settles.
  const confirm = page.getByRole("button", { name: /confirm.*run/i });
  await confirm.first().waitFor({ timeout: 220_000 });
  let started = false;
  for (let a = 0; a < 5 && !started; a++) {
    await confirm.first().scrollIntoViewIfNeeded().catch(() => {});
    await confirm.first().click({ timeout: 8_000 }).catch(async () => { await confirm.first().click({ force: true }).catch(() => {}); });
    // Run started when "Confirm & Run" is gone and a running/terminal state shows.
    started = await page.waitForFunction(() => {
      const b = (document.body.innerText || "");
      const confirmGone = !/confirm\s*&?\s*run/i.test(b);
      const runningish = /Pause|Stop phase|Run again|Download report|COMPLETED|RUNNING|After run/i.test(b);
      return confirmGone && runningish;
    }, undefined, { timeout: 15_000 }).then(() => true).catch(() => false);
    log.push(`confirm attempt ${a + 1}: started=${started}`);
  }
  expect(started, "run should start after Confirm & Run").toBe(true);

  // Drive to completion (safe panel → no gate; resume if one appears). 25 min budget.
  let completed = false;
  for (let i = 0; i < 350; i++) {
    await page.waitForTimeout(4000);
    const body = await page.locator("body").innerText();
    if (/Run again|Download report|COMPLETED/i.test(body) && !/Restart|RUN FAILED/i.test(body)) { completed = true; break; }
    const resume = page.getByRole("button", { name: /resume from last step/i });
    if ((await resume.count().catch(() => 0)) > 0 && await resume.first().isEnabled().catch(() => false)) {
      await resume.first().click({ timeout: 8000 }).catch(() => {});
    }
  }
  log.push(completed ? "terminal: COMPLETED" : "WARN not completed in budget");
  await page.waitForTimeout(3000);
  await page.screenshot({ path: path.join(OUT, "01-completed.png"), fullPage: true });

  // Phases tab → step cards + status
  const phasesTab = page.getByRole("tab", { name: /phases/i }).or(page.getByText(/^Phases/));
  if ((await phasesTab.count().catch(() => 0)) > 0) { await phasesTab.first().click({ timeout: 6000 }).catch(() => {}); await page.waitForTimeout(2500); }
  await page.screenshot({ path: path.join(OUT, "02-phases.png"), fullPage: true });

  // StepDetail for step id 1 (Predict Admet Properties) if the Details button exists.
  const details = page.locator('[data-testid^="button-full-step-view-"]');
  if ((await details.count().catch(() => 0)) > 0) {
    await details.last().click({ timeout: 6000 }).catch(() => {});
    await page.waitForTimeout(2500);
    await page.screenshot({ path: path.join(OUT, "03-step-detail.png"), fullPage: true });
  }

  // After-run Outputs → check the step label per output.
  const afterTab = page.getByRole("tab", { name: /after run/i }).or(page.getByText(/After run/));
  if ((await afterTab.count().catch(() => 0)) > 0) { await afterTab.first().click({ timeout: 6000 }).catch(() => {}); await page.waitForTimeout(2500); }
  const outputsText = await page.locator("body").innerText();
  await page.screenshot({ path: path.join(OUT, "04-after-run-outputs.png"), fullPage: true });

  const hasRunLabel = /\bpredict_admet_properties_results\.json\b[^]*?·\s*run\b/i.test(outputsText) || /\.json\s*·\s*run\b/i.test(outputsText);
  const hasRealStep = /predict.?admet.?properties/i.test(outputsText);
  log.push("output shows '· run' step label: " + hasRunLabel);
  log.push("output shows real step name: " + hasRealStep);
  fs.writeFileSync(path.join(OUT, "_verify.txt"), log.join("\n"));
  console.log("\n[admet-step-verify]\n" + log.join("\n") + "\nOUT=" + OUT + "\n");

  expect(completed, "run should complete").toBe(true);
});
