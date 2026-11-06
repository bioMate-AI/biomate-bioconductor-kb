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
  // loginAsFixture sets Authorization + X-E2E-Test-Token on EVERY context request;
  // S3 rejects a presigned URL that also carries an Authorization header (400).
  // Strip them for direct S3 fetches so the preview exercises the real viewer
  // (real users never send those headers to S3).
  await page.route(/amazonaws\.com/, async (route) => {
    const h = { ...route.request().headers() };
    delete h["authorization"]; delete h["Authorization"];
    delete h["x-e2e-test-token"]; delete h["X-E2E-Test-Token"];
    await route.continue({ headers: h });
  });

  // Data hub → choose the demo project (sets it active), then open a file.
  await page.goto(`${BASE_URL}/files`, { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.waitForTimeout(3000);
  await page.screenshot({ path: path.join(OUT, "files-viz-00-data-hub.png") });
  const proj = page.getByTestId(`data-hub-project-${PROJECT}`);
  await proj.first().waitFor({ state: "visible", timeout: 30_000 });
  await proj.first().click({ timeout: 10_000 });
  await page.waitForTimeout(3000);

  const openFile = async (fileId: string) => {
    const row = page.getByTestId(`file-open-${fileId}`);
    await row.first().waitFor({ state: "visible", timeout: 20_000 });
    await row.first().click({ timeout: 10_000 });
    await page.waitForTimeout(3500);
  };

  // JSON → structured key/value viewer (data-testid json-preview from the shared viewer).
  await openFile(JSON_FILE);
  const jsonView = page.getByTestId("json-preview");
  await jsonView.first().waitFor({ state: "visible", timeout: 20_000 }).catch(() => {});
  await page.screenshot({ path: path.join(OUT, "files-viz-json.png") });
  const jsonCount = await jsonView.count().catch(() => 0);
  console.log("[files-viz] json-preview count:", jsonCount);
  expect(jsonCount).toBeGreaterThan(0);

  // CSV → a real <table> (the dataset-object's rich table viewer; shared
  // TableGrid is the fallback for the text-preview path). Either way, a CSV must
  // render as a table, never a raw <pre> dump.
  await openFile(CSV_FILE);
  await page.waitForTimeout(2500);
  await page.screenshot({ path: path.join(OUT, "files-viz-csv.png") });
  const panelTables = await page.locator('[data-testid="dataset-object"] table, [data-testid="dataset-text-preview"] table').count().catch(() => 0);
  const panelText = await page.getByTestId("dataset-object").first().innerText().catch(() => "");
  console.log("[files-viz] <table> count:", panelTables, "| has gene header:", /\bgene\b/i.test(panelText));
  expect(panelTables).toBeGreaterThan(0);

  console.log("[files-viz] PASS — JSON structured + CSV table in the files module");
});
