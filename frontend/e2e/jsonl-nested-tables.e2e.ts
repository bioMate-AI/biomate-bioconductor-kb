/**
 * E2E (dev, live, no mocks): a JSONL file whose records hold tables (headers + rows) is shown and
 * profiled as structure — founder 2026-11-11 on data/glp_study_data/epar_study_tables.jsonl:
 * "should not it be analyzed as a json?" (the Preview showed truncated JSON text).
 *
 * One project per harness (deleted in finally): upload the real EPAR file → open it in the project's
 * Files view → nested cells show table shapes, not JSON text → a row opens as a record with a real
 * header table → the QC card reports the 7-row cap (69% of 2,281 tables; extractor kept t[1:8]).
 *
 * Run: E2E_FIXTURE_PASSWORD=$(cat ~/.config/biomate/e2e_fixture_password) \
 *      BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/jsonl-nested-tables.e2e.ts --project=chromium
 */
import { test, expect } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { loginAsFixture, BASE_URL, E2E_TOKEN } from "./_fixture-login";

const FILE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../data/glp_study_data/epar_study_tables.jsonl");

test("JSONL nested tables: shapes in the Preview, record view with a real table, row-cap QC", async ({ page, request }) => {
  test.setTimeout(8 * 60 * 1000);
  const pw = process.env.E2E_FIXTURE_PASSWORD;
  test.skip(!pw || !fs.existsSync(FILE), "needs E2E_FIXTURE_PASSWORD and the EPAR file");
  const H = { "x-e2e-test-token": E2E_TOKEN };
  const login = await request.post(`${BASE_URL}/api/auth/login`, { headers: H, data: { email: "lifeifei163361@163.com", password: pw } });
  expect(login.ok(), `login ${login.status()}`).toBeTruthy();
  const auth = { ...H, Authorization: `Bearer ${(await login.json()).token}` };
  const pr = await request.post(`${BASE_URL}/api/projects`, { headers: auth, data: { name: `e2e jsonl nested ${new Date().toISOString().slice(0, 16)}` } });
  expect(pr.ok(), `create project ${pr.status()}`).toBeTruthy();
  const pj = await pr.json(); const projectId = pj.id || pj.project?.id;
  try {
    const up = await request.post(`${BASE_URL}/api/projects/${projectId}/files/upload`, {
      headers: auth,
      multipart: { file: { name: "epar_study_tables.jsonl", mimeType: "application/x-ndjson", buffer: fs.readFileSync(FILE) } },
      timeout: 120_000,
    });
    expect(up.ok(), `upload ${up.status()} ${await up.text().catch(() => "")}`).toBeTruthy();
    const fileId = (await up.json()).file.id;

    await loginAsFixture(page);
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
    await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });   // app loaded
    const projBtn = page.getByTestId(`button-project-${projectId}`);
    // The PROJECTS header is a toggle and remembers its state: only click it if the project does not
    // render once the list has loaded (clicking an already-open section collapses it).
    if (!(await projBtn.waitFor({ state: "visible", timeout: 10_000 }).then(() => true).catch(() => false))) {
      await page.getByTestId("button-projects-section").click({ timeout: 15_000 });
    }
    await projBtn.click({ timeout: 30_000, noWaitAfter: true });
    await page.getByTestId(`project-link-files-${projectId}`).click({ timeout: 15_000, noWaitAfter: true });   // client-side route
    const open = page.getByTestId(`file-open-${fileId}`);
    if (!(await open.isVisible().catch(() => false))) await page.getByTestId("folder-inputs").click().catch(() => {});
    await open.click({ timeout: 30_000 });

    // Nested cells show their shape, not JSON text.
    await page.getByTestId("dataset-nested-cell").first().waitFor({ state: "visible", timeout: 90_000 });
    const chips = await page.getByTestId("dataset-nested-cell").allInnerTexts();
    expect(chips.some((c) => /(table|表格)\s*\d+\s*×\s*\d+/.test(c)), `chips: ${chips.slice(0, 4).join(" | ")}`).toBe(true);
    const tableText = await page.getByTestId("dataset-preview-table").innerText();
    expect(tableText.includes('[["'), "no raw nested JSON in the table").toBe(false);
    await page.screenshot({ path: "e2e/screenshots/jsonl-nested-1-preview.png", fullPage: true });

    // A row opens as a record with a real table (header row from the same-width headers list).
    await page.getByTestId("dataset-preview-row").first().click();
    const rec = page.getByTestId("dataset-record-view");
    await expect(rec).toBeVisible();
    const tbl = rec.getByTestId("dataset-record-table").first().locator("table");
    expect(await tbl.locator("tbody tr").count(), "embedded table rows").toBeGreaterThan(0);
    await rec.scrollIntoViewIfNeeded();
    await page.screenshot({ path: "e2e/screenshots/jsonl-nested-2-record.png", fullPage: true });

    // The QC card reports the extraction cap.
    const qc = page.getByTestId("dataset-quality");
    await expect(qc).toContainText(/69%/, { timeout: 120_000 });
    await expect(qc).toContainText(/\b7\b/);
    await qc.scrollIntoViewIfNeeded();
    await page.screenshot({ path: "e2e/screenshots/jsonl-nested-3-qc.png", fullPage: true });
  } finally {
    await request.delete(`${BASE_URL}/api/projects/${projectId}`, { headers: auth }).catch(() => {});
  }
});
