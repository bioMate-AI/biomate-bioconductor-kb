/**
 * E2E (dev, live, no mocks): a JSONL file whose records hold tables (headers + rows) is shown and
 * profiled as structure — founder 2026-11-11 on epar_study_tables.jsonl: "should not it be analyzed
 * as a json?" (the Preview showed truncated JSON text).
 *
 * 2026-11-12 (audit "Test quality"): this harness used to upload the real EPAR file and assert the
 * QC card said "69%" / "7" — i.e. it PINNED a defect of that file's extraction (the extractor kept
 * t[1:8]), so fixing the data would have failed the test. It now builds a synthetic JSONL whose
 * row-cap property is constructed here and known exactly:
 *   50 records {drug, headers:[Study, Dose, Route], rows:[[…]×n]}; records 0–29 have n = 9 (the
 *   cap), records 30–49 have n = 4…8. → 60% of the 50 tables sit at the 9-row maximum → the
 *   profiler's nested_row_cap signal (pct 60, max_rows 9) and quality "watch"; no blank cells.
 * Assertions use testids / data-* and language-neutral numbers only (no English UI text).
 *
 * One login (cookie session), one project (deleted loudly in finally): upload → open in the
 * project's Files view → nested cells show table shapes (9×3), not JSON text → a row opens as a
 * record with a real header table (Study/Dose/Route, 9 body rows) → the QC card lists
 * nested_row_cap with 60% / 9.
 *
 * Run: BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/jsonl-nested-tables.e2e.ts \
 *      --project=chromium --retries=0
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture } from "./_fixture-login";
import { createProject, deleteProjectLoudly, uploadFile, openProjectFiles, openFile } from "./_project-ui";

const N_RECORDS = 50;
const CAP = 9;
const N_AT_CAP = 30;                       // 30 / 50 = 60% at the cap (profiler threshold: ≥ 50%)
const PCT = Math.round((100 * N_AT_CAP) / N_RECORDS);
const HEADERS = ["Study", "Dose", "Route"];

function syntheticJsonl(): string {
  const lines: string[] = [];
  for (let i = 0; i < N_RECORDS; i++) {
    const n = i < N_AT_CAP ? CAP : 4 + (i % 5);           // 4..8 rows below the cap
    const rows = Array.from({ length: n }, (_, r) => [`S${i}-${r}`, `${(r + 1) * 5} mg`, r % 2 ? "iv" : "oral"]);
    lines.push(JSON.stringify({ drug: `drug_${i}`, headers: HEADERS, rows }));
  }
  return lines.join("\n") + "\n";
}

test("JSONL nested tables: shapes in the Preview, record view with a real table, row-cap QC", async ({ page }) => {
  test.setTimeout(6 * 60 * 1000);
  await loginAsFixture(page);
  const api = page.request;
  const projectName = `e2e jsonl nested ${new Date().toISOString().slice(0, 16)}`;
  const projectId = await createProject(api, projectName);
  try {
    const f = await uploadFile(api, projectId, "study_tables.jsonl", Buffer.from(syntheticJsonl(), "utf-8"), "application/x-ndjson");
    await openProjectFiles(page, projectId, projectName);
    await openFile(page, f.id, "study_tables.jsonl");

    // Nested cells show their shape (record 0: 9 rows × 3 columns), not JSON text.
    const chips = page.getByTestId("dataset-nested-cell");
    await expect(chips.first()).toBeVisible({ timeout: 90_000 });
    const chipTexts = await chips.allInnerTexts();
    expect(chipTexts.some((c) => new RegExp(`\\b${CAP}\\s*×\\s*${HEADERS.length}\\b`).test(c)),
      `a chip shows ${CAP}×${HEADERS.length}; chips: ${chipTexts.slice(0, 4).join(" | ")}`).toBe(true);
    expect((await page.getByTestId("dataset-preview-table").innerText()).includes('[["'), "no raw nested JSON in the table").toBe(false);
    await page.screenshot({ path: "e2e/screenshots/jsonl-nested-1-preview.png", fullPage: true });

    // Row 0 opens as a record whose embedded table has the real header row and all 9 body rows.
    await page.getByTestId("dataset-preview-row").first().click();
    const rec = page.getByTestId("dataset-record-view");
    await expect(rec).toBeVisible();
    const tbl = rec.getByTestId("dataset-record-table").first().locator("table");
    await expect(tbl.locator("tbody tr"), "embedded table body rows").toHaveCount(CAP);
    const head = (await tbl.locator("thead th").allInnerTexts()).map((s) => s.trim()).filter(Boolean);
    expect(head, "header row comes from the record's headers list").toEqual(HEADERS);
    await rec.scrollIntoViewIfNeeded();
    await page.screenshot({ path: "e2e/screenshots/jsonl-nested-2-record.png", fullPage: true });

    // The QC card reports the constructed cap: nested_row_cap, 60% of tables at 9 rows, verdict watch.
    const qc = page.getByTestId("dataset-quality");
    const capItem = qc.locator('[data-testid="perception-why-item"][data-code="nested_row_cap"]');
    await expect(capItem).toBeVisible({ timeout: 120_000 });
    await expect(capItem).toContainText(`${PCT}%`);
    await expect(capItem).toContainText(new RegExp(`\\b${CAP}\\b`));
    await expect(qc.getByTestId("data-perception")).toHaveAttribute("data-quality", "watch");
    await qc.scrollIntoViewIfNeeded();
    await page.screenshot({ path: "e2e/screenshots/jsonl-nested-3-qc.png", fullPage: true });
  } finally {
    await deleteProjectLoudly(api, projectId);
  }
});
