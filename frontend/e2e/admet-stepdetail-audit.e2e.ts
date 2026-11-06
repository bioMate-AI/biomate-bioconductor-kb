/**
 * Audit the ADMET step display + StepDetail panel for a COMPLETED run.
 * Uses /debug/viewer/:runId which mounts the real NextflowWorkflowViewer in
 * completed state for the run — so we see the Phases tab, step cards, and the
 * full StepDetail exactly as a user would.
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai E2E_FIXTURE_PASSWORD='WpmFixture!2026' \
 *     npx playwright test e2e/admet-stepdetail-audit.e2e.ts --project=chromium --workers=1
 */
import { test } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });
const OUT = "/Users/kky/Desktop/business/bioconductor_screenshot/admet_stepdetail_20261021";
fs.mkdirSync(OUT, { recursive: true });
const RUN_ID = "e2c3e772-580d-4a59-be1c-487999a072b4"; // completed ADMET run

test("ADMET step display + StepDetail audit", async ({ page }) => {
  test.setTimeout(4 * 60 * 1000);
  await loginAsFixture(page);
  await page.route(/amazonaws\.com/, async (route) => {
    const h = { ...route.request().headers() };
    delete h["authorization"]; delete h["Authorization"];
    delete h["x-e2e-test-token"]; delete h["X-E2E-Test-Token"];
    await route.continue({ headers: h });
  });

  await page.goto(`${BASE_URL}/debug/viewer/${RUN_ID}`, { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.waitForTimeout(7000);
  await page.screenshot({ path: path.join(OUT, "01-viewer-overview.png"), fullPage: true });

  // Phases tab → step cards
  const phasesTab = page.getByRole("tab", { name: /phases/i }).or(page.getByText(/^Phases/i));
  if ((await phasesTab.count().catch(() => 0)) > 0) {
    await phasesTab.first().click({ timeout: 6000 }).catch(() => {});
    await page.waitForTimeout(2500);
    await page.screenshot({ path: path.join(OUT, "02-phases-tab.png"), fullPage: true });
  }

  // Dump the step-card text so we can see names/status in the log.
  const cards = page.locator('[data-testid^="phase-card"], [class*="phase"], [class*="step-card"]');
  const n = await cards.count().catch(() => 0);
  console.log("[stepdetail] phase/step card elements:", n);
  for (let i = 0; i < Math.min(n, 6); i++) {
    const t = (await cards.nth(i).innerText().catch(() => "")).replace(/\n+/g, " | ").slice(0, 120);
    console.log(`  card[${i}]: ${t}`);
  }

  // Open the full StepDetail for the first step/phase if a trigger exists.
  const openFull = page.getByRole("button", { name: /full step view|view full|step detail|open step/i })
    .or(page.getByText(/full step view/i));
  if ((await openFull.count().catch(() => 0)) > 0) {
    await openFull.first().click({ timeout: 6000 }).catch(() => {});
    await page.waitForTimeout(2500);
    await page.screenshot({ path: path.join(OUT, "03-step-detail.png"), fullPage: true });
  } else {
    // Try clicking the first step card directly.
    if (n > 0) { await cards.first().click({ timeout: 5000 }).catch(() => {}); await page.waitForTimeout(2000); await page.screenshot({ path: path.join(OUT, "03-step-card-clicked.png"), fullPage: true }); }
  }

  console.log("[stepdetail] OUT=" + OUT);
});
