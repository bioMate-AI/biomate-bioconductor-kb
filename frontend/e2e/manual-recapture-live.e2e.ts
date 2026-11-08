/**
 * Core-journey LIVE-state re-capture: one real ADMET run → pre-run (idle),
 * running, completed-chat-and-panel, and the sidebar with a status dot.
 * Selectors mirror real-run-capture.e2e.ts. Safety-gated to ADMET (cheap).
 * Honest: only commit a state that actually renders. deviceScaleFactor=2.
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1680, height: 1000 }, deviceScaleFactor: 2 });
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const ADMET_PROMPT =
  "Predict ADMET properties (hERG, DILI, oral bioavailability, CYP) for aspirin CC(=O)OC1=CC=CC=C1C(=O)O and acetaminophen CC(=O)Nc1ccc(O)cc1.";

test("live ADMET run — pre-run / running / completed / sidebar", async ({ page }) => {
  test.setTimeout(30 * 60 * 1000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string, el?: import("@playwright/test").Locator) => {
    await (el ?? page).screenshot({ path: path.join(ASSETS, name) });
    log.push("OK   " + name);
  };

  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 45_000 });
  const input = page.getByTestId("chat-input");
  await input.waitFor({ state: "visible", timeout: 30_000 });
  await page.waitForTimeout(3000);
  await input.click();
  await input.fill(ADMET_PROMPT);
  const sendReady = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await sendReady.waitFor({ state: "visible", timeout: 30_000 });
  await sendReady.click({ timeout: 15_000 });
  log.push("submitted ADMET");

  const confirm = page.getByRole("button", { name: /confirm.*run/i });
  await confirm.first().waitFor({ timeout: 180_000 });
  await page.waitForTimeout(3500);

  // SAFETY GATE — ADMET only (no heavy mis-routed Batch spend).
  const panelText = (await page.locator("body").innerText()).toLowerCase();
  if (!/admet/.test(panelText)) {
    log.push("ABORT — not ADMET; no Confirm, no spend. panel=" + panelText.slice(0, 140).replace(/\n/g, " "));
    // eslint-disable-next-line no-console
    console.log("\n[live]\n" + log.join("\n") + "\n");
    return;
  }

  // --- PRE-RUN (idle) — the Workflow-settings pre-run panel + param strip.
  await shot("t3-1-workflow-panel.png");
  await shot("r1-prerun-param-strip.png");
  const wsTab = page.getByRole("tab", { name: /workflow settings/i }).first();
  if ((await wsTab.count()) > 0) {
    await wsTab.click({ timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(1500);
    await shot("w1-2-workflow-settings.png");
  } else { log.push("SKIP w1-2 (no Workflow settings tab)"); }

  // --- CONFIRM & RUN.
  const confirmBtn = page.getByRole("button", { name: /confirm.*run/i }).first();
  await confirmBtn.scrollIntoViewIfNeeded().catch(() => {});
  await confirmBtn.click({ timeout: 30_000 }).catch(async () => { await confirmBtn.click({ timeout: 15_000, force: true }); });
  log.push("confirmed");

  // --- RUNNING.
  try {
    await page.waitForFunction(() => !!document.querySelector('[data-status="running"]'), { timeout: 240_000 });
    await page.waitForTimeout(1500);
    await shot("r2-running.png");
    const phasesTab = page.getByRole("tab", { name: /^phases$/i }).first();
    if ((await phasesTab.count()) > 0) { await phasesTab.click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(1200); }
    await shot("w1-1-phases.png");
  } catch { log.push("SKIP r2/w1-1 (running not observed)"); }

  // --- COMPLETED — chat + panel together.
  try {
    await page.waitForFunction(
      () => /Run again|COMPLETED|Completed/.test(document.body.innerText || ""),
      { timeout: 24 * 60 * 1000 },
    );
    await page.waitForTimeout(5000);
    await shot("r8-completed-chat-and-panel.png");
  } catch { log.push("SKIP r8 (no completion)"); }

  // --- SIDEBAR — chat history with a status dot.
  const sidebar = page.locator('[data-testid="platform-sidebar"]').first();
  if ((await sidebar.count()) > 0) { await shot("s1-1-sidebar.png", sidebar); }
  else { log.push("SKIP s1-1 (no sidebar testid)"); }

  // eslint-disable-next-line no-console
  console.log("\n[live]\n" + log.join("\n") + "\n");
  expect(log.some((r) => r.startsWith("OK"))).toBe(true);
});
