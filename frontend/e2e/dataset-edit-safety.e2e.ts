/**
 * E2E (dev, live, no mocks): in-place cell edits change ONLY the edited cell, and an edit made
 * against a version that is no longer current is refused.
 *
 * 2026-11-11: the edit route split lines on bare delimiters — editing a row with a quoted field
 * (`1,"x, y"`) corrupted it, CRLF files came back LF, and the grid edited the profile's truncated
 * 100-row sample. Now edits go through the full-rows table and a quote-aware rewrite.
 * 2026-11-12 (audit S3): with REPEATED values the `from` check cannot detect a stale edit — a
 * client that saw v1 and edits "row 2" after a new version inserted a row lands on the wrong row
 * with 200. The edit contract must carry the version the client saw (`baseVersion`) and refuse a
 * stale one (409). This harness expects that fixed contract: step C FAILS until the server fix
 * (stream A, project-routes.ts edit precondition) deploys.
 *
 * ONE login (loginAsFixture → cookie session; every API call below uses page.request), ONE project
 * (deleted loudly in finally):
 *   A. quoted / CRLF / multi-line CSV → UI edit of one cell after the multi-line record → the new
 *      version's bytes equal the original with exactly that field replaced → a stale edit whose
 *      `from` no longer matches is refused (409) and writes nothing.
 *   B. header-less TSV (first line is data) → UI edit of a first-line cell → bytes equal the
 *      original with exactly that field replaced (row 0 = line 1; no header swallowed).
 *   C. repeated values: v1 (all "control") → a new upload inserts a row (v2) → an edit numbered
 *      against v1 (baseVersion 1, `from` still matches on v2) is refused 409 and v2 is unchanged;
 *      the same edit with baseVersion 2 is accepted (positive control).
 *   D. repeated values on the current version: an edit mis-numbered onto another row holding the
 *      same value is refused by its `rowFrom` (the whole row the user saw) — 409, nothing written;
 *      the correctly numbered edit lands (positive control).
 *
 * Run: BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/dataset-edit-safety.e2e.ts \
 *      --project=chromium --retries=0     (password: E2E_FIXTURE_PASSWORD or ~/.config/biomate/e2e_fixture_password)
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { createProject, deleteProjectLoudly, uploadFile, fileText, openProjectFiles, openFile } from "./_project-ui";

const ORIGINAL =
  'sample,condition,note\r\n' +
  'S1,"treated, 10 uM","said ""ok"""\r\n' +
  'S2,control,"two\nlines"\r\n' +
  '\r\n' +
  'S3,control,plain\r\n';
// Data row 2 (S3), column 1 — after the multi-line record and the blank line.
const EXPECTED = ORIGINAL.replace("S3,control,plain", 'S3,"vehicle, DMSO",plain');

// Header-less: every line is data (numeric third column, Ensembl ids — no header-like first line).
const HEADERLESS =
  "ENSG00000141510\tTP53\t7.25\n" +
  "ENSG00000012048\tBRCA1\t3.10\n" +
  "ENSG00000146648\tEGFR\t5.80\n";
const HEADERLESS_EXPECTED = HEADERLESS.replace("\tTP53\t", "\tTP53_edited\t");

const REP_V1 = "sample,condition\nS1,control\nS2,control\nS3,control\n";
const REP_V2 = "sample,condition\nS0,control\nS1,control\nS2,control\nS3,control\n";   // a row inserted on top

test("cell edit rewrites only that cell; stale edits refused (incl. repeated values); header-less edit", async ({ page }) => {
  test.setTimeout(6 * 60 * 1000);
  await loginAsFixture(page);
  const api = page.request;
  const projectName = `e2e edit safety ${new Date().toISOString().slice(0, 16)}`;
  const projectId = await createProject(api, projectName);
  try {
    const csv = await uploadFile(api, projectId, "samples.csv", Buffer.from(ORIGINAL, "utf-8"), "text/csv");
    const tsv = await uploadFile(api, projectId, "genes_noheader.tsv", Buffer.from(HEADERLESS, "utf-8"), "text/tab-separated-values");
    const rep = await uploadFile(api, projectId, "repeated.csv", Buffer.from(REP_V1, "utf-8"), "text/csv");
    expect(await fileText(api, projectId, csv.id), "presigned download returns the uploaded bytes").toBe(ORIGINAL);

    await openProjectFiles(page, projectId, projectName);

    await test.step("A. quoted / CRLF / multi-line CSV: UI edit of one cell", async () => {
      await openFile(page, csv.id, "samples.csv");
      await page.getByTestId("dataset-preview-toggle-edit").click({ timeout: 60_000 });
      const cell = page.getByTestId("dataset-edit-cell-2-1");
      await expect(cell).toHaveValue("control", { timeout: 60_000 });
      await expect(page.getByTestId("dataset-edit-cell-0-1")).toHaveValue("treated, 10 uM");   // full, unquoted value
      await cell.fill("vehicle, DMSO");
      await page.screenshot({ path: "e2e/screenshots/dataset-edit-1-editing.png", fullPage: true });
      await page.getByTestId("dataset-edit-save").click();
      await expect(page.getByTestId("dataset-edit-saved")).toBeVisible({ timeout: 60_000 });
      await page.screenshot({ path: "e2e/screenshots/dataset-edit-2-saved.png", fullPage: true });
      expect(await fileText(api, projectId, csv.id), "new version = original with exactly that field changed").toBe(EXPECTED);

      // A stale edit (the cell no longer holds "control") is refused and writes nothing — even
      // against the current version (v2 after the UI save), the `from` check catches it.
      const stale = await api.post(`${BASE_URL}/api/projects/${projectId}/files/${csv.id}/edit`, {
        data: { baseVersion: 2, edits: [{ row: 2, col: 1, from: "control", value: "x" }] },
      });
      expect(stale.status(), "stale edit (from mismatch) → 409").toBe(409);
      expect(await fileText(api, projectId, csv.id)).toBe(EXPECTED);
    });

    await test.step("B. header-less TSV: UI edit of a first-line cell", async () => {
      await openFile(page, tsv.id, "genes_noheader.tsv");
      await page.getByTestId("dataset-preview-toggle-edit").click({ timeout: 60_000 });
      // Row 0 is the FIRST LINE of the file: nothing was taken as a header.
      const cell = page.getByTestId("dataset-edit-cell-0-1");
      await expect(cell, "header-less: data row 0 = line 1 (TP53)").toHaveValue("TP53", { timeout: 60_000 });
      await expect(page.getByTestId("dataset-edit-cell-2-1")).toHaveValue("EGFR");
      await cell.fill("TP53_edited");
      await page.getByTestId("dataset-edit-save").click();
      await expect(page.getByTestId("dataset-edit-saved")).toBeVisible({ timeout: 60_000 });
      await page.screenshot({ path: "e2e/screenshots/dataset-edit-3-headerless-saved.png", fullPage: true });
      expect(await fileText(api, projectId, tsv.id), "header-less: exactly line 1's field changed").toBe(HEADERLESS_EXPECTED);
    });

    await test.step("C. repeated values: an edit numbered against an old version is refused", async () => {
      // v2: same name, new bytes → a new version of the same file with a row inserted on top.
      const v2 = await uploadFile(api, projectId, "repeated.csv", Buffer.from(REP_V2, "utf-8"), "text/csv");
      expect(v2.id, "same name → new version of the same file").toBe(rep.id);
      const vres = await api.get(`${BASE_URL}/api/projects/${projectId}/files/${rep.id}/versions`);
      expect(vres.ok(), `versions ${vres.status()}`).toBeTruthy();
      const versions = ((await vres.json()).versions ?? []) as Array<{ version: string; current: boolean }>;
      expect(versions.find((v) => v.current)?.version, "repeated.csv is at v2").toBe("2");

      // The client saw v1 and edits its row 2 (S3). On v2, row 2 is S2 — and it ALSO holds "control",
      // so the `from` check cannot catch it. Only the version precondition can.
      const stale = await api.post(`${BASE_URL}/api/projects/${projectId}/files/${rep.id}/edit`, {
        data: { baseVersion: 1, edits: [{ row: 2, col: 1, from: "control", value: "treated" }] },
      });
      const staleBody = (await stale.text()).slice(0, 200);
      const after = await fileText(api, projectId, rep.id);
      expect(stale.status(), `edit against v1 when v2 is current → 409 (got ${stale.status()}: ${staleBody})`).toBe(409);
      expect(after, "the refused edit wrote nothing").toBe(REP_V2);

      // Positive control: the same edit against the current version lands on S2 (v2 row 2).
      const ok = await api.post(`${BASE_URL}/api/projects/${projectId}/files/${rep.id}/edit`, {
        data: { baseVersion: 2, edits: [{ row: 2, col: 1, from: "control", value: "treated" }] },
      });
      expect(ok.status(), `edit against the current version is accepted (${(await ok.text()).slice(0, 200)})`).toBe(200);
      const V3 = REP_V2.replace("S2,control", "S2,treated");
      expect(await fileText(api, projectId, rep.id)).toBe(V3);
    });

    await test.step("D. repeated values on the CURRENT version: rowFrom pins the edit to the row the user saw", async () => {
      // v3 rows: S0, S1, S2(treated), S3 — rows 0, 1 and 3 all hold "control". The user saw S3
      // (row 3) but the edit is mis-numbered as row 1: `from` matches, the version is current,
      // only the whole-row check (rowFrom) can refuse it.
      const V3 = REP_V2.replace("S2,control", "S2,treated");
      const wrong = await api.post(`${BASE_URL}/api/projects/${projectId}/files/${rep.id}/edit`, {
        data: { baseVersion: 3, edits: [{ row: 1, col: 1, from: "control", value: "x", rowFrom: ["S3", "control"] }] },
      });
      expect(wrong.status(), `mis-numbered edit with rowFrom of another row → 409 (got ${wrong.status()}: ${(await wrong.text()).slice(0, 200)})`).toBe(409);
      expect(await fileText(api, projectId, rep.id), "the refused edit wrote nothing").toBe(V3);
      const right = await api.post(`${BASE_URL}/api/projects/${projectId}/files/${rep.id}/edit`, {
        data: { baseVersion: 3, edits: [{ row: 3, col: 1, from: "control", value: "x", rowFrom: ["S3", "control"] }] },
      });
      expect(right.status(), `the correctly numbered edit lands (${(await right.text()).slice(0, 200)})`).toBe(200);
      expect(await fileText(api, projectId, rep.id)).toBe(V3.replace("S3,control", "S3,x"));
    });
  } finally {
    await deleteProjectLoudly(api, projectId);
  }
});
