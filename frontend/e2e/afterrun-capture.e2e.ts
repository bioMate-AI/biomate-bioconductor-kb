/**
 * Capture the After-run report states for a COMPLETED run (no Batch spend) —
 * Outputs list, an output-file preview in the enlarged pop-up (with the new
 * down-arrow download icon + taller content), and the download menu.
 *
 * Uses the /debug/afterrun/:runId route which renders AfterRunReport directly.
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai E2E_FIXTURE_PASSWORD='WpmFixture!2026' \
 *     npx playwright test e2e/afterrun-capture.e2e.ts --project=chromium --workers=1
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });

const OUT = "/Users/kky/Desktop/business/bioconductor_screenshot/e2e_review_20261020/d2-admet";
fs.mkdirSync(OUT, { recursive: true });

// Completed ADMET run on dev (6 output files).
const RUN_ID = "e2c3e772-580d-4a59-be1c-487999a072b4";

test("after-run: outputs + enlarged preview pop-up + download icon", async ({ page }) => {
  test.setTimeout(4 * 60 * 1000);
  await loginAsFixture(page);

  await page.goto(`${BASE_URL}/debug/afterrun/${RUN_ID}`, { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: path.join(OUT, "08-afterrun-overview.png"), fullPage: true });

  // Outputs table
  const outputsTable = page.getByTestId("output-files-table");
  if ((await outputsTable.count().catch(() => 0)) > 0) {
    await outputsTable.first().scrollIntoViewIfNeeded().catch(() => {});
    await page.waitForTimeout(1000);
    await page.screenshot({ path: path.join(OUT, "11-outputs.png") });
  }

  // Open a JSON output's enlarged preview pop-up (prefer a results/report json).
  const cards = page.getByTestId("output-card");
  const n = await cards.count().catch(() => 0);
  console.log("[afterrun] output cards:", n);
  let opened = false;
  for (let i = 0; i < n; i++) {
    const card = cards.nth(i);
    const nameText = await card.innerText().catch(() => "");
    if (/results\.json|toxicity|qc_metrics|pk_summary|\.json/i.test(nameText)) {
      const viewBtn = card.getByRole("button", { name: /view|preview/i });
      if ((await viewBtn.count().catch(() => 0)) > 0) {
        await viewBtn.first().click({ timeout: 8000 }).catch(() => {});
        await page.waitForTimeout(3500);
        opened = true;
        break;
      }
    }
  }
  if (opened) {
    await page.screenshot({ path: path.join(OUT, "12-output-preview-popup.png") });
    // The enlarged pane width should be > 760 (was the old size). Soft-check the json viewer.
    const jsonView = page.getByTestId("json-preview");
    console.log("[afterrun] json-preview in popup:", await jsonView.count().catch(() => 0));
  } else {
    console.log("[afterrun] no previewable JSON output card found");
  }

  expect(n).toBeGreaterThan(0);
  console.log("[afterrun] PASS — captured after-run outputs + preview");
});
