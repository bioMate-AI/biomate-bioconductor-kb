/**
 * E2E (dev, live, no mocks): the dataset object's own surface — header, tabular preview tools,
 * versions and provenance — asserted, not recorded.
 *
 * Replaces the 2026-10-28 record-only audit (hard-coded project / file / run ids, 18 swallowed
 * `.catch(() => {})`, PASS/FAIL written to a JSON file while the test itself always passed, and
 * checks for header badges the design has since removed).
 *
 * Coverage map — what this harness does NOT re-verify (it is asserted elsewhere):
 *   - per-format kinds / stats / toggles / previews (CSV, TSV, JSON, FASTA, VCF, PDB, MRC, images,
 *     h5ad, BAM …) and folder profiles → e2e/dataset-format-matrix.e2e.ts;
 *   - cell edits, stale-version / rowFrom refusals, header-less edits → e2e/dataset-edit-safety.e2e.ts;
 *   - rename keeps versions + diff → e2e/project-file-rename.e2e.ts;
 *   - sort / filter / record view logic, edit payload, error messages → client vitest
 *     (dataset-rows.test.tsx, nested-json.test.tsx, dataset-object.*.test.tsx).
 *
 * Flow A (one project, deleted loudly in finally): upload panel.csv twice (v1 → v2), open it from
 *   the tree, then assert header (name, v2 chip, quality pill, CSV format chip, tabs, actions),
 *   Preview table with real sort (asc then exact reverse) and filter, Columns and Plot views, the
 *   Versions list (v2 current, v1 comparable → diff shows the changed cell), the upload's
 *   Provenance (origin, no storage key, no "produced by"), and text hygiene.
 * Flow B: a RUN OUTPUT's provenance — the fixture's projects are searched (API, bounded) for a
 *   run-output file; its "produced by" row must name the workflow (· step), never the run id. No
 *   such file in the fixture → the flow FAILS (the outcome cannot be shown), it is not skipped.
 *
 * Rules honoured (CLAUDE.md): fixture account, ONE login (cookie session; every API call goes
 * through page.request), ONE project, never register, no page.route.
 *
 * Run: BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/dataset-panel-full.e2e.ts \
 *      --project=chromium --retries=0
 */
import { test, expect, type Locator, type Page } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { createProject, deleteProjectLoudly, uploadFile, openProjectFiles, openFile, revealFile } from "./_project-ui";

test.setTimeout(8 * 60_000);

const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
const RAW_KEY_RE = /\b(dataset_obj|file_tree|data_hub|perception|actions|nav)\.[a-z_]+/i;

const V1 = "gene,count\nTP53,5\nBRCA1,12\nEGFR,3\nMYC,8\n";
const V2 = "gene,count\nTP53,5\nBRCA1,12\nEGFR,4\nMYC,8\n";   // EGFR 3 → 4

/** The panel shows no raw id, no undefined / NaN and no untranslated i18n key. */
async function expectCleanText(panel: Locator, extra: string[] = []): Promise<void> {
  const text = await panel.innerText();
  expect(text, "no raw uuid in the panel").not.toMatch(UUID_RE);
  expect(text, "no 'undefined'").not.toMatch(/\bundefined\b/i);
  expect(text, "no NaN").not.toMatch(/\bNaN\b/);
  expect(text, "no raw i18n key").not.toMatch(RAW_KEY_RE);
  for (const s of extra) expect(text, `'${s}' is not shown`).not.toContain(s);
}

async function firstColumn(page: Page): Promise<string[]> {
  return page.locator('[data-testid="dataset-preview-table"] tbody tr[data-testid="dataset-preview-row"] td:first-child').allInnerTexts();
}

test("dataset object: header, preview tools, versions and provenance (upload + run output)", async ({ page }) => {
  await loginAsFixture(page);
  const api = page.request;
  const name = `e2e dataset panel ${Date.now()}`;
  const projectId = await createProject(api, name);
  try {
    // ── Flow A ──────────────────────────────────────────────────────────────
    const v1 = await uploadFile(api, projectId, "panel.csv", Buffer.from(V1), "text/csv");
    const v2 = await uploadFile(api, projectId, "panel.csv", Buffer.from(V2), "text/csv");
    expect(v2.id, "same name → a new version of the same file").toBe(v1.id);

    await openProjectFiles(page, projectId, name);
    await openFile(page, v1.id, "panel.csv");
    const obj = page.getByTestId("dataset-object");

    await test.step("header", async () => {
      await expect(page.getByTestId("dataset-object-name")).toHaveText("panel.csv");
      await expect(page.getByTestId("dataset-header-version")).toHaveText("v2", { timeout: 30_000 });
      const pill = page.getByTestId("dataset-header-quality");
      await expect(pill).toBeVisible({ timeout: 60_000 });
      expect(["good", "watch", "blocked", "unassessed"]).toContain(await pill.getAttribute("data-quality"));
      await expect(page.getByTestId("dataset-header-format")).toHaveText(/^CSV/, { timeout: 60_000 });
      for (const tab of ["preview", "versions", "wherefrom"]) await expect(page.getByTestId(`dataset-tab-${tab}`)).toBeVisible();
      await expect(page.getByTestId("dataset-tab-preview")).toHaveAttribute("aria-selected", "true");
      await expect(page.getByTestId("dataset-object-analyze")).toBeVisible();
      await expect(page.getByTestId("dataset-object-download")).toBeVisible();
    });

    await test.step("preview: table, sort, filter", async () => {
      await expect(page.getByTestId("dataset-preview")).toHaveAttribute("data-preview-kind", "table", { timeout: 60_000 });
      await expect.poll(() => firstColumn(page), { timeout: 30_000 }).toEqual(["TP53", "BRCA1", "EGFR", "MYC"]);
      await page.getByTestId("dataset-col-sort-0").click();
      await expect.poll(() => firstColumn(page)).toEqual(["BRCA1", "EGFR", "MYC", "TP53"]);
      await page.getByTestId("dataset-col-sort-0").click();
      await expect.poll(() => firstColumn(page)).toEqual(["TP53", "MYC", "EGFR", "BRCA1"]);
      await page.getByTestId("dataset-preview-filter").fill("EGF");
      await expect.poll(() => firstColumn(page)).toEqual(["EGFR"]);
      await page.getByTestId("dataset-preview-filter").fill("");
      await expect.poll(async () => (await firstColumn(page)).length).toBe(4);
    });

    await test.step("columns and plot views", async () => {
      await page.getByTestId("dataset-preview-toggle-columns").click();
      await expect(page.getByTestId("dataset-preview-columns")).toBeVisible();
      await expect(page.getByTestId("dataset-column-row")).toHaveCount(2);
      await page.getByTestId("dataset-preview-toggle-plot").click();
      await expect(page.getByTestId("dataset-sample-plot"), "a numeric column (count) is plotted").toBeVisible();
      await expect(page.getByTestId("dataset-preview-plot-future")).toHaveCount(0);
    });

    await test.step("versions: v2 current, v1 compares to the changed cell", async () => {
      await page.getByTestId("dataset-tab-versions").click();
      await expect(page.getByTestId("dataset-versions")).toBeVisible({ timeout: 30_000 });
      await expect(page.getByTestId("dataset-version-2")).toBeVisible();
      await expect(page.getByTestId("dataset-version-1")).toBeVisible();
      await expect(page.getByTestId("dataset-version-compare-2"), "the current version has no Compare").toHaveCount(0);
      await page.getByTestId("dataset-version-compare-1").click();
      const cell = page.getByTestId("dataset-version-diff-1").getByTestId("dataset-diff-cell");
      await expect(cell).toHaveCount(1, { timeout: 30_000 });
      await expect(cell).toContainText("count");
      await expect(cell).toContainText("3");
      await expect(cell).toContainText("4");
    });

    await test.step("provenance of an upload", async () => {
      await page.getByTestId("dataset-tab-wherefrom").click();
      const origin = page.getByTestId("dataset-origin");
      await expect(origin).toBeVisible({ timeout: 30_000 });
      expect(await origin.innerText(), "the storage key is plumbing, never shown").not.toMatch(/s3:\/\/|projects\/\S+\/inputs\//i);
      await expect(page.getByTestId("lineage-open-run"), "an upload has no producing run").toHaveCount(0);
      await expect(page.getByTestId("dataset-consumers").or(page.getByTestId("dataset-no-consumers")).first()).toBeVisible({ timeout: 30_000 });
      await expectCleanText(obj);
    });

    // ── Flow B: a run output's provenance ───────────────────────────────────
    await test.step("provenance of a run output (fixture data)", async () => {
      const pres = await api.get(`${BASE_URL}/api/projects`);
      expect(pres.ok(), `list projects ${pres.status()}`).toBeTruthy();
      const projects = ((await pres.json()).projects ?? []) as Array<{ id: string; name: string }>;
      let found: { project: { id: string; name: string }; file: any } | null = null;
      // Bounded search (one GET per project, at most 40) for a run output with a run id.
      for (const p of projects.filter((x) => x.id !== projectId).slice(0, 40)) {
        const fres = await api.get(`${BASE_URL}/api/projects/${p.id}/files`);
        if (!fres.ok()) continue;
        const f = ((await fres.json()).files ?? []).find((x: any) => x.source === "run_output" && x.run_id);
        if (f) { found = { project: p, file: f }; break; }
      }
      expect(found, "the fixture account has a run-output file to show provenance for").not.toBeNull();
      const { project, file } = found!;
      await openProjectFiles(page, project.id, project.name);
      await revealFile(page, file.id, undefined, `outputs/${file.run_id}`);
      await page.getByTestId(`file-open-${file.id}`).click();
      await expect(page.getByTestId("dataset-object-name")).toContainText(String(file.name).split("/").pop()!, { timeout: 30_000 });
      await page.getByTestId("dataset-tab-wherefrom").click();
      const produced = page.getByTestId("lineage-open-run");
      await expect(produced).toBeVisible({ timeout: 30_000 });
      const label = (await produced.innerText()).trim();
      expect(label, "produced-by names the workflow, not the run id").not.toContain(file.run_id);
      expect(label).not.toMatch(UUID_RE);
      if (file.step_name) expect(label, "pinned to the producing step").toContain(String(file.step_name).trim());
      expect(await page.getByTestId("dataset-origin").innerText()).not.toMatch(/s3:\/\//i);
      await expectCleanText(page.getByTestId("dataset-object"), [file.run_id]);
    });
  } finally {
    await deleteProjectLoudly(api, projectId);
  }
});
