/**
 * Live E2E (no mocks): folder Use/attach → every file under the folder.
 *
 * Proves on https://dev-public.biomate.ai:
 *   (1) GET /api/projects/:id/folders/files returns all inputs under the path
 *   (2) Analysis deep-link ?attachFolder= expands to N composer chips
 *   (3) Models dataset picker offers folder:path with "(N files)"
 *   (4) Nested folder expands only its descendants (count assert)
 *   (5) Empty folder → 404 folder_not_found
 *   (6) When POST …/folders/samplesheet is live: persist → one attachFile chip
 *
 * One login, one project. No Batch/GPU runs.
 *
 * Run:
 *   E2E_FIXTURE_PASSWORD=$(cat ~/.config/biomate/e2e_fixture_password) \
 *   BIOMATE_URL=https://dev-public.biomate.ai \
 *   npx playwright test e2e/folder-attach-all-files.e2e.ts --project=chromium --retries=0
 */
import { test, expect } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { loginAsFixture, BASE_URL, FIXTURE_PASSWORD } from "./_fixture-login";
import { createProject, deleteProjectLoudly, uploadFile } from "./_project-ui";

const FOLDER = "pairs";
const NESTED = "pairs/lane1";
const EMPTY = "empty_probe";
const FILES = [
  { name: "S1_R1.fastq.gz", rel: `${FOLDER}/S1_R1.fastq.gz`, body: "@S1.1\nACGT\n+\nIIII\n" },
  { name: "S1_R2.fastq.gz", rel: `${FOLDER}/S1_R2.fastq.gz`, body: "@S1.2\nTGCA\n+\nIIII\n" },
  { name: "S2_R1.fastq.gz", rel: `${FOLDER}/S2_R1.fastq.gz`, body: "@S2.1\nAAAA\n+\nIIII\n" },
];
const NESTED_FILES = [
  { name: "N1_R1.fastq.gz", rel: `${NESTED}/N1_R1.fastq.gz`, body: "@N1.1\nACGT\n+\nIIII\n" },
  { name: "N1_R2.fastq.gz", rel: `${NESTED}/N1_R2.fastq.gz`, body: "@N1.2\nTGCA\n+\nIIII\n" },
];
const SHOT_DIR = path.join(import.meta.dirname, "execshots", "folder-attach-20261113");

test.beforeAll(() => {
  expect(FIXTURE_PASSWORD, "E2E_FIXTURE_PASSWORD or ~/.config/biomate/e2e_fixture_password required").toBeTruthy();
  fs.mkdirSync(SHOT_DIR, { recursive: true });
});

test("folder Use/attach yields multiple files (Analysis + Models + nested/empty)", async ({ page }) => {
  test.setTimeout(8 * 60 * 1000);
  await loginAsFixture(page);
  const api = page.request;

  // Build-info gate
  const bi = await api.get(`${BASE_URL}/build-info.json`);
  expect(bi.ok(), `build-info ${bi.status()}`).toBeTruthy();
  const build = await bi.json();
  const liveCommit = String(build.commit || "");
  expect(liveCommit, "build-info.commit").toMatch(/^[0-9a-f]{7,40}$/i);
  console.log(`[build] live commit=${liveCommit}`);

  const projectName = `E2E-FolderAttach-${Date.now()}`;
  const projectId = await createProject(api, projectName);
  console.log(`[project] ${projectId}`);

  const evidence: Record<string, unknown> = {
    ok: false,
    baseUrl: BASE_URL,
    liveCommit,
    projectId,
    folder: FOLDER,
    nested: NESTED,
  };

  try {
    // ── Upload top-level folder files + nested lane ────────────────────────
    const uploadedIds: string[] = [];
    for (const f of [...FILES, ...NESTED_FILES]) {
      const up = await uploadFile(
        api, projectId, f.name, Buffer.from(f.body), "application/gzip", f.rel,
      );
      uploadedIds.push(up.id);
      expect(up.name).toBe(f.rel);
    }
    expect(uploadedIds).toHaveLength(FILES.length + NESTED_FILES.length);

    // ── API: folder → all files under prefix (includes nested) ─────────────
    const list = await api.get(
      `${BASE_URL}/api/projects/${encodeURIComponent(projectId)}/folders/files?path=${encodeURIComponent(FOLDER)}`,
    );
    expect(list.ok(), `folders/files ${list.status()} ${await list.text().catch(() => "")}`).toBeTruthy();
    const listBody = await list.json();
    const apiFiles: Array<{ id: string; name: string }> = Array.isArray(listBody.files) ? listBody.files : [];
    const expectedTop = FILES.length + NESTED_FILES.length;
    console.log(`[api] folders/files path=${FOLDER} count=${apiFiles.length} (expect ${expectedTop})`);
    expect(apiFiles.length, "API returns all files under folder incl nested").toBe(expectedTop);
    for (const f of [...FILES, ...NESTED_FILES]) {
      expect(apiFiles.some((x) => x.name === f.rel), `API includes ${f.rel}`).toBe(true);
    }

    // ── Nested folder: only lane1 descendants ──────────────────────────────
    const nestedList = await api.get(
      `${BASE_URL}/api/projects/${encodeURIComponent(projectId)}/folders/files?path=${encodeURIComponent(NESTED)}`,
    );
    expect(nestedList.ok(), `nested folders/files ${nestedList.status()}`).toBeTruthy();
    const nestedBody = await nestedList.json();
    const nestedFiles: Array<{ id: string; name: string }> = Array.isArray(nestedBody.files) ? nestedBody.files : [];
    console.log(`[api] nested count=${nestedFiles.length}`);
    expect(nestedFiles.length).toBe(NESTED_FILES.length);
    for (const f of NESTED_FILES) {
      expect(nestedFiles.some((x) => x.name === f.rel)).toBe(true);
    }
    // Sibling top-level FASTQs must not appear under nested path
    for (const f of FILES) {
      expect(nestedFiles.some((x) => x.name === f.rel)).toBe(false);
    }

    // ── Empty folder: no files under prefix → 404 ──────────────────────────
    const emptyList = await api.get(
      `${BASE_URL}/api/projects/${encodeURIComponent(projectId)}/folders/files?path=${encodeURIComponent(EMPTY)}`,
    );
    expect(emptyList.status(), "empty folder → folder_not_found").toBe(404);
    const emptyBody = await emptyList.json().catch(() => ({}));
    expect(String((emptyBody as any).error || "")).toMatch(/folder_not_found|not found/i);

    // ── Analysis: attachFolder deep-link expands to N chips ────────────────
    // Seed active project BEFORE navigation so chat-input's attachFolder effect
    // does not race an empty/wrong activeProjectId (live flake on 429c3dbc).
    await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded", timeout: 60_000 });
    await page.evaluate((id) => localStorage.setItem("biomate-active-project-id", id), projectId);
    await page.goto(
      `${BASE_URL}/?project=${encodeURIComponent(projectId)}&attachFolder=${encodeURIComponent(FOLDER)}`,
      { waitUntil: "domcontentloaded", timeout: 60_000 },
    );
    const chips = page.locator('[data-testid="composer-dataset-ref"]');
    await expect
      .poll(async () => chips.count(), {
        timeout: 60_000,
        message: `Analysis attachFolder → ${expectedTop} composer chips`,
      })
      .toBe(expectedTop);
    await expect.poll(() => new URL(page.url()).searchParams.has("attachFolder")).toBe(false);
    const chipTexts = await chips.allTextContents();
    console.log(`[analysis] chips=${chipTexts.length} :: ${chipTexts.map((t) => t.trim()).join(" | ")}`);
    for (const f of [...FILES, ...NESTED_FILES]) {
      expect(chipTexts.some((t) => t.includes(f.name)), `chip for ${f.name}`).toBe(true);
    }
    await page.screenshot({ path: path.join(SHOT_DIR, "01-analysis-folder-chips.png"), fullPage: true });

    // ── Nested Analysis attach ─────────────────────────────────────────────
    await page.evaluate((id) => localStorage.setItem("biomate-active-project-id", id), projectId);
    await page.goto(
      `${BASE_URL}/?project=${encodeURIComponent(projectId)}&attachFolder=${encodeURIComponent(NESTED)}`,
      { waitUntil: "domcontentloaded", timeout: 60_000 },
    );
    await expect
      .poll(async () => page.locator('[data-testid="composer-dataset-ref"]').count(), {
        timeout: 60_000,
        message: "Nested attachFolder → only nested chips",
      })
      .toBe(NESTED_FILES.length);
    await page.screenshot({ path: path.join(SHOT_DIR, "01b-analysis-nested-chips.png"), fullPage: true });

    // ── Models: folder option lists N files ────────────────────────────────
    await page.goto(`${BASE_URL}/models`, { waitUntil: "domcontentloaded", timeout: 60_000 });
    await page.evaluate((id) => localStorage.setItem("biomate-active-project-id", id), projectId);
    await page.reload({ waitUntil: "domcontentloaded", timeout: 60_000 });

    const select = page.getByTestId("launcher-dataset").first();
    await expect(select, "Models dataset select").toBeVisible({ timeout: 60_000 });
    await expect
      .poll(async () => {
        const opts = await select.locator("option").allTextContents();
        return opts.some((o) => o.includes(`${FOLDER}/`) && o.includes(`${expectedTop} files`));
      }, { timeout: 45_000, message: `Models picker has folder/(${expectedTop} files)` })
      .toBe(true);

    const folderValue = `folder:${FOLDER}`;
    await select.selectOption(folderValue);
    await expect(select).toHaveValue(folderValue);
    const optionLabel = await select.locator(`option[value="${folderValue}"]`).textContent();
    console.log(`[models] selected=${folderValue} label=${optionLabel?.trim()}`);
    expect(optionLabel || "").toMatch(new RegExp(`${FOLDER}/\\s*\\(${expectedTop} files\\)`));

    // Nested folder option count
    const nestedValue = `folder:${NESTED}`;
    await expect
      .poll(async () => {
        const opts = await select.locator("option").allTextContents();
        return opts.some((o) => o.includes(`${NESTED}/`) && o.includes(`${NESTED_FILES.length} files`));
      }, { timeout: 30_000, message: "Models picker has nested folder count" })
      .toBe(true);
    await page.screenshot({ path: path.join(SHOT_DIR, "02-models-folder-option.png"), fullPage: true });

    // ── Samplesheet-as-one (when route is deployed) ────────────────────────
    let samplesheet: { id?: string; name?: string; status: number } | null = null;
    const sheetRes = await api.post(
      `${BASE_URL}/api/projects/${encodeURIComponent(projectId)}/folders/samplesheet`,
      { data: { path: FOLDER } },
    );
    samplesheet = { status: sheetRes.status() };
    if (sheetRes.ok()) {
      const body = await sheetRes.json();
      samplesheet.id = body.file?.id;
      samplesheet.name = body.file?.name;
      expect(samplesheet.id, "persisted samplesheet file id").toBeTruthy();
      await page.goto(
        `${BASE_URL}/?project=${encodeURIComponent(projectId)}&attachFile=${encodeURIComponent(samplesheet.id!)}`,
        { waitUntil: "domcontentloaded", timeout: 60_000 },
      );
      await page.evaluate((id) => localStorage.setItem("biomate-active-project-id", id), projectId);
      if (!(await page.locator('[data-testid="composer-dataset-ref"]').count())) {
        await page.reload({ waitUntil: "domcontentloaded", timeout: 60_000 });
      }
      await expect(
        page.locator('[data-testid="composer-dataset-ref"]'),
        "samplesheet attachFile → exactly one chip",
      ).toHaveCount(1, { timeout: 45_000 });
      const sheetChip = (await page.locator('[data-testid="composer-dataset-ref"]').allTextContents())[0] || "";
      expect(sheetChip.toLowerCase()).toMatch(/samplesheet|\.csv/);
      await page.screenshot({ path: path.join(SHOT_DIR, "03-samplesheet-one-chip.png"), fullPage: true });
      console.log(`[samplesheet] persisted id=${samplesheet.id} chip=${sheetChip.trim()}`);
    } else {
      console.log(`[samplesheet] route not live yet status=${sheetRes.status()} — skip attach assert`);
    }

    evidence.ok = true;
    evidence.fileCount = expectedTop;
    evidence.nestedCount = NESTED_FILES.length;
    evidence.emptyStatus = emptyList.status();
    evidence.apiFileNames = apiFiles.map((f) => f.name);
    evidence.chipTexts = chipTexts.map((t) => t.trim());
    evidence.modelsFolderLabel = optionLabel?.trim() ?? null;
    evidence.samplesheet = samplesheet;
    evidence.at = new Date().toISOString();

    fs.writeFileSync(path.join(SHOT_DIR, "result.json"), JSON.stringify(evidence, null, 2));
  } finally {
    await deleteProjectLoudly(api, projectId);
  }
});
