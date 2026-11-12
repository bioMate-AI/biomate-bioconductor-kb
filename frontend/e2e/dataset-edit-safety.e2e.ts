/**
 * E2E (dev, live, no mocks): in-place cell edits change ONLY the edited cell.
 *
 * 2026-11-11: the edit route split lines on bare delimiters — editing a row with a quoted field
 * (`1,"x, y"`) corrupted it, CRLF files came back LF, and the grid edited the profile's truncated
 * 100-row sample. Now edits go through the full-rows table and a quote-aware rewrite.
 *
 * One project (deleted in finally): upload a CSV with quotes, CRLF, a multi-line field and a blank
 * line → Edit → change one cell in a row AFTER the multi-line record → Save → the new version's
 * bytes equal the original with exactly that field replaced → a stale edit (wrong `from`) is
 * refused with 409 and writes nothing.
 *
 * Run: E2E_FIXTURE_PASSWORD=$(cat ~/.config/biomate/e2e_fixture_password) \
 *      BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/dataset-edit-safety.e2e.ts --project=chromium
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL, E2E_TOKEN } from "./_fixture-login";

const ORIGINAL =
  'sample,condition,note\r\n' +
  'S1,"treated, 10 uM","said ""ok"""\r\n' +
  'S2,control,"two\nlines"\r\n' +
  '\r\n' +
  'S3,control,plain\r\n';
// Data row 2 (S3), column 1 — after the multi-line record and the blank line.
const EXPECTED = ORIGINAL.replace("S3,control,plain", 'S3,"vehicle, DMSO",plain');

test("cell edit rewrites only that cell (quotes, CRLF, multi-line kept); stale edit refused", async ({ page, request }) => {
  test.setTimeout(6 * 60 * 1000);
  const pw = process.env.E2E_FIXTURE_PASSWORD;
  test.skip(!pw, "E2E_FIXTURE_PASSWORD not set");
  const H = { "x-e2e-test-token": E2E_TOKEN };
  const login = await request.post(`${BASE_URL}/api/auth/login`, { headers: H, data: { email: "lifeifei163361@163.com", password: pw } });
  expect(login.ok(), `login ${login.status()}`).toBeTruthy();
  const auth = { ...H, Authorization: `Bearer ${(await login.json()).token}` };
  const pr = await request.post(`${BASE_URL}/api/projects`, { headers: auth, data: { name: `e2e edit safety ${new Date().toISOString().slice(0, 16)}` } });
  expect(pr.ok(), `create project ${pr.status()}`).toBeTruthy();
  const pj = await pr.json(); const projectId = pj.id || pj.project?.id;
  const fileBytes = async (fileId: string) => {
    const u = await (await request.get(`${BASE_URL}/api/projects/${projectId}/files/${fileId}/url`, { headers: auth })).json();
    const abs = u.url.startsWith("http");
    return (await request.get(abs ? u.url : `${BASE_URL}${u.url}`, { headers: abs ? {} : auth })).text();
  };
  try {
    const up = await request.post(`${BASE_URL}/api/projects/${projectId}/files/upload`, {
      headers: auth, multipart: { file: { name: "samples.csv", mimeType: "text/csv", buffer: Buffer.from(ORIGINAL, "utf-8") } },
    });
    expect(up.ok(), `upload ${up.status()}`).toBeTruthy();
    const fileId = (await up.json()).file.id;
    expect(await fileBytes(fileId)).toBe(ORIGINAL);

    await loginAsFixture(page);
    await page.route(/amazonaws\.com/, async (route) => {   // harness auth headers must not reach S3
      const h = { ...route.request().headers() }; delete h["authorization"]; delete h["x-e2e-test-token"];
      await route.continue({ headers: h });
    });
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
    await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
    const projBtn = page.getByTestId(`button-project-${projectId}`);
    if (!(await projBtn.waitFor({ state: "visible", timeout: 10_000 }).then(() => true).catch(() => false))) {
      await page.getByTestId("button-projects-section").click({ timeout: 15_000 });
    }
    await projBtn.click({ timeout: 30_000, noWaitAfter: true });
    await page.getByTestId(`project-link-files-${projectId}`).click({ timeout: 15_000, noWaitAfter: true });
    const open = page.getByTestId(`file-open-${fileId}`);
    if (!(await open.isVisible().catch(() => false))) await page.getByTestId("folder-inputs").click().catch(() => {});
    await open.click({ timeout: 30_000 });

    await page.getByTestId("dataset-preview-toggle-edit").click({ timeout: 60_000 });
    const cell = page.getByTestId("dataset-edit-cell-2-1");
    await expect(cell).toHaveValue("control", { timeout: 60_000 });
    await expect(page.getByTestId("dataset-edit-cell-0-1")).toHaveValue("treated, 10 uM");   // full, unquoted value
    await cell.fill("vehicle, DMSO");
    await page.screenshot({ path: "e2e/screenshots/dataset-edit-1-editing.png", fullPage: true });
    await page.getByTestId("dataset-edit-save").click();
    await expect(page.getByTestId("dataset-edit-saved")).toBeVisible({ timeout: 60_000 });
    await page.screenshot({ path: "e2e/screenshots/dataset-edit-2-saved.png", fullPage: true });

    expect(await fileBytes(fileId), "new version = original with exactly that field changed").toBe(EXPECTED);

    // A stale edit (the cell no longer holds "control") is refused and writes nothing.
    const stale = await request.post(`${BASE_URL}/api/projects/${projectId}/files/${fileId}/edit`, {
      headers: auth, data: { edits: [{ row: 2, col: 1, from: "control", value: "x" }] },
    });
    expect(stale.status()).toBe(409);
    expect(await fileBytes(fileId)).toBe(EXPECTED);
  } finally {
    await request.delete(`${BASE_URL}/api/projects/${projectId}`, { headers: auth }).catch(() => {});
  }
});
