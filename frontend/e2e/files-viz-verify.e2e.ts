/**
 * Verify the files-module shares the run-output visualization (JSON → structured
 * key/value, CSV → table) after the file-content-view refactor. Captures the
 * dataset preview for a JSON and a CSV file in the fixture's demo project.
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai E2E_FIXTURE_PASSWORD='WpmFixture!2026' \
 *     npx playwright test e2e/files-viz-verify.e2e.ts --project=chromium --workers=1
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });

const OUT = "/Users/kky/Desktop/business/bioconductor_screenshot/e2e_review_20261020";
fs.mkdirSync(OUT, { recursive: true });

const PROJECT = "3cd5292d-fcc4-4d78-8d41-53d6d3a5e77a"; // MG PBMC — sample data demo
const JSON_FILE = "da07d4b4-42c6-4b03-a340-45d35b5de6ae"; // preview_checks.json
const CSV_FILE = "5288f63c-d6e5-4fcb-b192-f35dad49991b"; // counts_matrix.csv

test("files module renders JSON structurally and CSV as a table", async ({ page }) => {
  test.setTimeout(4 * 60 * 1000);
  await loginAsFixture(page);

  await page.goto(`${BASE_URL}/files?project=${PROJECT}&file=${JSON_FILE}`, { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.waitForTimeout(5000);

  // JSON → structured key/value viewer (data-testid json-preview from the shared viewer).
  const jsonView = page.getByTestId("json-preview");
  await jsonView.first().waitFor({ state: "visible", timeout: 30_000 }).catch(() => {});
  await page.screenshot({ path: path.join(OUT, "files-viz-json.png") });
  const jsonCount = await jsonView.count().catch(() => 0);
  console.log("[files-viz] json-preview count:", jsonCount);
  expect(jsonCount).toBeGreaterThan(0);

  // CSV → table (shared TableGrid: shows "N rows × M cols" header).
  await page.goto(`${BASE_URL}/files?project=${PROJECT}&file=${CSV_FILE}`, { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.waitForTimeout(5000);
  await page.screenshot({ path: path.join(OUT, "files-viz-csv.png") });
  const previewText = await page.getByTestId("dataset-text-preview").first().innerText().catch(() => "");
  console.log("[files-viz] CSV preview text (head):\n" + previewText.slice(0, 400));
  // TableGrid renders a shape header and a real <table> (not a raw <pre> dump).
  const tableCount = await page.getByTestId("dataset-text-preview").locator("table").count().catch(() => 0);
  console.log("[files-viz] <table> count in CSV preview:", tableCount);
  expect(tableCount).toBeGreaterThan(0);

  console.log("[files-viz] PASS — JSON structured + CSV table in the files module");
});
