/**
 * Prerun-only verification for the CN1C phantom-param fix (docs/20261020).
 *
 * Sends the 3-SMILES ADMET query, waits for the prerun workflow panel, and
 * asserts:
 *   - NO phantom "CN1C" param row (the mis-parsed SMILES fragment key)
 *   - the SMILES value carries all three compounds (aspirin/caffeine/ibuprofen)
 *
 * STOPS before "Confirm & Run" — no AWS Batch spend. Screenshot saved for review.
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai E2E_FIXTURE_PASSWORD='WpmFixture!2026' \
 *     npx playwright test e2e/admet-prerun-verify.e2e.ts --project=chromium --workers=1
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });

const OUT = "/Users/kky/Desktop/business/bioconductor_screenshot/e2e_review_20261020";
fs.mkdirSync(OUT, { recursive: true });

const ASPIRIN = "CC(=O)Oc1ccccc1C(=O)O";
const CAFFEINE = "CN1C=NC2=C1C(=O)N(C(=O)N2C)C";
const IBUPROFEN = "CC(C)Cc1ccc(cc1)C(C)C(=O)O";
const QUERY =
  "Screen these SMILES for ADMET liabilities and rank them by developability: " +
  `${ASPIRIN}, ${CAFFEINE}, ${IBUPROFEN}`;

test("ADMET prerun panel: no phantom CN1C row, all 3 SMILES present", async ({ page }) => {
  test.setTimeout(6 * 60 * 1000);
  await loginAsFixture(page);

  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
  const input = page.getByTestId("chat-input");
  await input.waitFor({ state: "visible", timeout: 45_000 });
  await page.waitForTimeout(2500);
  await input.click();
  await input.fill(QUERY);

  const send = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await send.waitFor({ state: "visible", timeout: 30_000 });
  await send.click({ timeout: 15_000 });

  // Wait for the prerun panel (Confirm & Run) — do NOT click it.
  const confirm = page.getByRole("button", { name: /confirm.*run/i });
  await confirm.first().waitFor({ timeout: 220_000 });
  await page.waitForTimeout(3500);

  const panel = page.getByTestId("workflow-right-panel");
  await panel.first().screenshot({ path: path.join(OUT, "verify-prerun-panel.png") }).catch(() => {});
  await page.screenshot({ path: path.join(OUT, "verify-prerun-full.png") });

  const panelText = await panel.first().innerText().catch(() => "");
  console.log("\n[verify] panel text:\n" + panelText + "\n");

  // 1) It routed to ADMET
  expect(panelText.toLowerCase()).toMatch(/admet|predict admet/);

  // 2) No phantom "CN1C" param row. "CN1C" appears legitimately INSIDE the
  //    caffeine SMILES value; a phantom row would show it as a standalone param
  //    LABEL. Assert it is not rendered as its own param field label.
  const cn1cLabel = page.getByText(/^\s*CN1C\s*$/).or(page.locator('label', { hasText: /^CN1C$/ }));
  expect(await cn1cLabel.count().catch(() => 0)).toBe(0);

  // 3) All three compounds present in the SMILES value (caffeine is the one that
  //    was previously split/lost). Match on distinctive fragments.
  expect(panelText).toContain("CC(=O)Oc1ccccc1C(=O)O");      // aspirin
  expect(panelText).toContain("CC(C)Cc1ccc(cc1)C(C)C(=O)O"); // ibuprofen (the lost one)
  expect(panelText).toMatch(/CN1C=NC2=C1C\(=O\)N\(C\(=O\)N2C\)C/); // caffeine intact

  console.log("[verify] PASS — no phantom CN1C row; all 3 SMILES present");
});
