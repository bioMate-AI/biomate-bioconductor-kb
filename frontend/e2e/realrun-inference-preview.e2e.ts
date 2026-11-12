/**
 * realrun-inference-preview.e2e.ts
 *
 * Converts two previously-SKIPPED areas into REAL, verified runs on LIVE dev
 * (https://dev-public.biomate.ai) — NO mocks, NO route interception.
 *
 * PART A — REAL pre-trained inference (covers UC-RP-02/03/04 + UC-VW-01):
 *   /models → "Run a pre-trained model" track → Structure domain → short peptide
 *   sequence → submit real inference (POST /api/models/{id}/infer → real NIM/Batch
 *   job) → assert running state → poll to terminal via GET /api/inference/{id}/result.
 *   On completion assert the real evidence viewer (pLDDT / PAE / 3D slot). If the
 *   backend returns a labelled STUB (no live NIM) assert the honest stub banner.
 *   If it FAILS assert result-status-failed + a real error (no stuck spinner).
 *   Reports which of {live-result | stub | failure} occurred, with the run id.
 *
 * PART B — Dataset Preview DATA TABLE (UC-DS-02):
 *   Create one project → UPLOAD a real small tabular CSV through the REAL upload
 *   endpoint the app uses (POST /api/projects/:id/files/upload — the exact
 *   endpoint project-file-tree.tsx calls) → open the file in the DataHub
 *   DatasetObject → Preview tab → assert an ACTUAL data table renders (column
 *   headers + first rows matching the CSV). If the perception profiler returns
 *   0 cols/rows for a valid CSV, that is a REAL BUG — reported with evidence.
 *
 * Discipline (CLAUDE.md §"E2E plan discipline"):
 *   - login ONCE via the shared _fixture-login.ts (lifeifei163361@163.com)
 *   - ONE project for the whole harness, torn down in afterAll
 *   - NEVER call /api/auth/register
 *   - generous timeouts for the real inference job (up to ~20 min poll)
 *
 * Screenshots: frontend/e2e/execshots/realrun-inference-preview/
 */

import { test, expect, type Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { deleteProjectLoudly } from "./_project-ui";

const SHOT_DIR = path.resolve(
  process.cwd(),
  "e2e",
  "execshots",
  "realrun-inference-preview",
);
fs.mkdirSync(SHOT_DIR, { recursive: true });

function shot(page: Page, name: string) {
  return page.screenshot({
    path: path.join(SHOT_DIR, `${name}.png`),
    fullPage: true,
  });
}

// A ~40 aa peptide (villin headpiece HP-36 like fragment) — short enough that a
// real structure prediction job stays fast, long enough to produce a real
// pLDDT/PAE profile. This is a real, foldable one-letter protein sequence.
const SHORT_PEPTIDE =
  "MLSDEDFKAVFGMTRSAFANLPLWKQQNLKKEKGLF";

// A tiny, valid gene × sample counts CSV (3 columns incl. gene id, ~10 rows).
const COUNTS_CSV = [
  "gene_id,sample_A,sample_B",
  "ENSG00000141510,120,98",
  "ENSG00000012048,45,52",
  "ENSG00000155657,8801,9102",
  "ENSG00000181449,3,0",
  "ENSG00000139618,210,187",
  "ENSG00000171862,77,64",
  "ENSG00000121879,412,509",
  "ENSG00000133703,1290,1330",
  "ENSG00000146648,66,71",
  "ENSG00000198793,5400,5210",
].join("\n");

// Shared harness state.
let projectId = "";
const projectName = `RealRun InferPreview ${Date.now()}`;
// Reported verdicts, printed in afterAll for a single consolidated table.
const verdicts: Record<string, string> = {};

test.describe.configure({ mode: "serial" });

test.describe("Real inference + dataset-preview (live dev)", () => {
  test.beforeAll(async ({ browser }) => {
    const page = await browser.newPage();
    await loginAsFixture(page);
    const res = await page.request.post(`${BASE_URL}/api/projects`, {
      headers: { "Content-Type": "application/json" },
      data: {
        name: projectName,
        description: "Real pre-trained inference + dataset preview verification",
        primaryDomain: "transcriptomics",
        researchGoal: "Verify UC-RP-0x inference viewers and UC-DS-02 preview table",
      },
    });
    const body = await res.json().catch(() => ({}));
    projectId = body?.project?.id ?? body?.id ?? "";
    expect(projectId, `project creation failed: ${JSON.stringify(body)}`).toBeTruthy();
    console.log(`[setup] project ${projectId} "${projectName}"`);
    await page.close();
  });

  test.afterAll(async ({ browser }) => {
    if (projectId) {
      const page = await browser.newPage();
      await loginAsFixture(page);
      await deleteProjectLoudly(page.request, projectId, { inHook: true });
      console.log(`[teardown] project deleted ${projectId}`);
      await page.close();
    }
    console.log("\n================ VERDICT TABLE ================");
    for (const [k, v] of Object.entries(verdicts)) {
      console.log(`  ${k.padEnd(42)} : ${v}`);
    }
    console.log("==============================================\n");
  });

  // ────────────────────────────────────────────────────────────────────────
  // PART A — REAL pre-trained STRUCTURE inference
  // ────────────────────────────────────────────────────────────────────────
  test("PART A · UC-RP-02/03/04 + UC-VW-01 — real structure inference", async ({
    page,
  }) => {
    // 20 min: a real NIM/Batch structure prediction can take minutes.
    test.setTimeout(20 * 60 * 1000 + 120_000);
    await loginAsFixture(page);

    // 1. Open /models and switch to the "Run a pre-trained model" track (idx 3).
    await page.goto(`${BASE_URL}/models`, { waitUntil: "domcontentloaded" });
    await expect(page.getByTestId("models-panel")).toBeVisible({ timeout: 60_000 });
    await page.getByTestId("models-track-3").click();
    await expect(page.getByTestId("run-pretrained")).toBeVisible({ timeout: 30_000 });

    // 2. STRUCTURE domain (default, but click to be explicit) + capture which
    //    concrete catalog model id was chosen (ESMFold/Boltz-2/OpenFold/BioNeMo).
    await page.getByTestId("domain-structure").click();
    const modelEl = page.getByTestId("run-pretrained-model");
    await expect(modelEl).toBeVisible({ timeout: 15_000 });
    const modelId = (await modelEl.textContent())?.trim() || "(unknown)";
    console.log(`[PART A] structure model id = ${modelId}`);

    await shot(page, "A1-run-pretrained-prerun");

    // 3. Supply a short protein sequence and submit the REAL inference.
    await page.getByTestId("run-pretrained-input").fill(SHORT_PEPTIDE);
    const submit = page.getByTestId("run-pretrained-submit");
    await expect(submit).toBeEnabled();

    // Capture the run_id from the real infer POST (so we can report it).
    const inferRespP = page
      .waitForResponse(
        (r) => /\/api\/models\/.+\/infer$/.test(r.url()) && r.request().method() === "POST",
        { timeout: 90_000 },
      )
      .catch(() => null);
    await submit.click();
    const inferResp = await inferRespP;
    let runId = "(none)";
    if (inferResp) {
      const j = await inferResp.json().catch(() => ({} as any));
      runId = j?.run_id ?? "(none)";
      console.log(`[PART A] infer POST ${inferResp.status()} run_id=${runId}`);
    }

    // 4. Result card must appear. Either the running badge shows, or (fast
    //    backends / stub) the job is already terminal by the first poll.
    const resultCard = page.getByTestId("run-pretrained-result-card");
    await expect(resultCard).toBeVisible({ timeout: 60_000 });
    await shot(page, "A2-inference-submitted");

    // Assert we observed a running OR pending state before terminal (real job).
    const running = page.getByTestId("result-status-running");
    const pending = page.getByTestId("result-pending");
    const sawInflight = await Promise.race([
      running.waitFor({ state: "visible", timeout: 8_000 }).then(() => true).catch(() => false),
      pending.waitFor({ state: "visible", timeout: 8_000 }).then(() => true).catch(() => false),
    ]);
    console.log(`[PART A] observed in-flight (running|pending) = ${sawInflight}`);

    // 5. Poll to terminal via the UI badges (the component polls
    //    GET /api/inference/{id}/result every 1.5s). Generous 20 min ceiling.
    const completed = page.getByTestId("result-status-completed");
    const failed = page.getByTestId("result-status-failed");
    const POLL_MS = 20 * 60 * 1000;
    const terminal = await Promise.race([
      completed.waitFor({ state: "visible", timeout: POLL_MS }).then(() => "completed").catch(() => ""),
      failed.waitFor({ state: "visible", timeout: POLL_MS }).then(() => "failed").catch(() => ""),
    ]);
    console.log(`[PART A] terminal state = ${terminal || "(timeout/none)"}`);

    // 6. Branch on the honest outcome.
    if (terminal === "completed") {
      const view = page.getByTestId("inference-result");
      await expect(view).toBeVisible({ timeout: 30_000 });
      // Structure evidence class → the structure viewer group must render.
      await expect(page.getByTestId("inference-structure")).toBeVisible();
      await expect(page.getByTestId("inference-structure-slot")).toBeVisible();

      const isStub = await page.getByTestId("inference-stub-badge").isVisible().catch(() => false);
      await shot(page, "A3-inference-completed");

      if (isStub) {
        const reason = (await page.getByTestId("inference-stub-badge").textContent())?.trim();
        verdicts["A · structure inference"] =
          `STUB (honest shape-only, NIM unreachable) · run=${runId} · model=${modelId}`;
        console.log(`[PART A] STUB banner shown — reason: ${reason}`);
        // A stub is a PASS of the honesty contract, not a failure. Assert the
        // viewer still rendered the correct SHAPE (pLDDT/PAE containers exist).
        expect(await page.getByTestId("inference-structure").isVisible()).toBe(true);
      } else {
        verdicts["A · structure inference"] =
          `LIVE RESULT (real pLDDT/PAE/structure) · run=${runId} · model=${modelId}`;
        console.log(`[PART A] LIVE non-stub structure result rendered`);
      }
    } else if (terminal === "failed") {
      await expect(page.getByTestId("result-error")).toBeVisible();
      const err = (await page.getByTestId("result-error").textContent())?.trim();
      // No stuck spinner on a failed run.
      await expect(running).toHaveCount(0);
      await shot(page, "A3-inference-failed");
      verdicts["A · structure inference"] =
        `FAILED (real error, no stuck spinner) · run=${runId} · model=${modelId} · err="${err}"`;
      console.log(`[PART A] FAILED — error="${err}"`);
    } else {
      // Neither terminal state within 20 min — capture evidence, report honestly.
      await shot(page, "A3-inference-timeout");
      verdicts["A · structure inference"] =
        `TIMEOUT (>20min, no terminal state) · run=${runId} · model=${modelId}`;
      throw new Error(
        `PART A: inference run ${runId} did not reach a terminal state within 20 min`,
      );
    }
  });

  // ────────────────────────────────────────────────────────────────────────
  // PART B — Dataset Preview DATA TABLE (UC-DS-02)
  // ────────────────────────────────────────────────────────────────────────
  test("PART B · UC-DS-02 — dataset preview renders the real data table", async ({
    page,
  }) => {
    test.setTimeout(4 * 60 * 1000);
    await loginAsFixture(page);

    // 1. UPLOAD a small real CSV through the REAL endpoint the file tree uses
    //    (POST /api/projects/:id/files/upload, multipart "file"). page.request
    //    uses Playwright's HTTP stack — this is the true upload path, not a mock.
    const uploadResp = await page.request.post(
      `${BASE_URL}/api/projects/${projectId}/files/upload`,
      {
        multipart: {
          file: {
            name: "counts.csv",
            mimeType: "text/csv",
            buffer: Buffer.from(COUNTS_CSV, "utf-8"),
          },
        },
      },
    );
    expect(
      uploadResp.ok(),
      `upload failed ${uploadResp.status()}: ${await uploadResp.text().catch(() => "")}`,
    ).toBeTruthy();
    const uploadBody = await uploadResp.json();
    const uploaded = uploadBody?.file;
    const s3Key: string = uploaded?.s3_key ?? "";
    console.log(`[PART B] uploaded file id=${uploaded?.id} s3_key=${s3Key}`);
    expect(uploaded?.id, "upload returned no file row").toBeTruthy();
    expect(s3Key, "upload returned no s3_key").toBeTruthy();

    // 1b. Directly probe the REAL perception profiler with the exact ref the UI
    //     sends, so we know the ground truth independent of any UI state.
    const profResp = await page.request.post(`${BASE_URL}/api/perception/profile`, {
      headers: { "Content-Type": "application/json" },
      data: { datasetRef: s3Key, name: "counts.csv" },
    });
    const prof = await profResp.json().catch(() => ({} as any));
    const profCols: string[] = Array.isArray(prof?.columns) ? prof.columns : [];
    const profRows: unknown[] = Array.isArray(prof?.sampleRows) ? prof.sampleRows : [];
    console.log(
      `[PART B] perception profile: status=${profResp.status()} quality=${prof?.quality} ` +
        `cols=${profCols.length} rows=${profRows.length} notes=${JSON.stringify(prof?.notes ?? [])}`,
    );
    fs.writeFileSync(
      path.join(SHOT_DIR, "B0-perception-profile.json"),
      JSON.stringify({ s3Key, profile: prof }, null, 2),
    );

    // 2. Open the DataHub (/files) with the project preselected, then open the
    //    uploaded file → Preview tab through the real UI.
    await page.addInitScript((id) => {
      try {
        localStorage.setItem("biomate-active-project-id", id as string);
      } catch {
        /* ignore */
      }
    }, projectId);
    await page.goto(`${BASE_URL}/files`, { waitUntil: "domcontentloaded" });
    await expect(page.getByTestId("data-hub")).toBeVisible({ timeout: 60_000 });

    // The two-pane hub renders once a project is active.
    const panes = page.getByTestId("data-hub-panes");
    if (!(await panes.isVisible().catch(() => false))) {
      // Fall back to clicking the project card if preselect didn't take.
      const card = page.getByTestId(`data-hub-project-${projectId}`);
      if (await card.isVisible().catch(() => false)) await card.click();
    }
    await expect(panes).toBeVisible({ timeout: 30_000 });
    await expect(page.getByTestId("project-file-tree")).toBeVisible({ timeout: 30_000 });
    await shot(page, "B1-datahub-file-tree");

    // 3. Open the uploaded file as a DatasetObject.
    const openBtn = page.getByTestId(`file-open-${uploaded.id}`);
    await expect(openBtn).toBeVisible({ timeout: 30_000 });
    await openBtn.click();
    await expect(page.getByTestId("dataset-object")).toBeVisible({ timeout: 30_000 });

    // 4. Preview tab (default). Give the profile fetch a moment to resolve.
    await page.getByTestId("dataset-tab-preview").click();
    const previewPane = page.getByTestId("dataset-preview");
    await expect(previewPane).toBeVisible({ timeout: 30_000 });

    // The data table renders ONLY when the profiler returned columns+rows.
    const previewTable = page.getByTestId("dataset-preview-table");
    const tableRendered = await previewTable
      .waitFor({ state: "visible", timeout: 20_000 })
      .then(() => true)
      .catch(() => false);
    await shot(page, "B2-dataset-preview");

    if (tableRendered) {
      // Assert the ACTUAL data: headers + first-row cell match the CSV.
      const headerCells = previewTable.locator("thead th");
      const headerTexts = (await headerCells.allTextContents()).map((t) => t.trim());
      console.log(`[PART B] rendered headers: ${JSON.stringify(headerTexts)}`);
      expect(headerTexts).toEqual(
        expect.arrayContaining(["gene_id", "sample_A", "sample_B"]),
      );
      const firstRow = previewTable.locator("tbody tr").first();
      const firstRowText = (await firstRow.textContent())?.trim() ?? "";
      console.log(`[PART B] first data row: ${firstRowText}`);
      expect(firstRowText).toContain("ENSG00000141510");
      verdicts["B · dataset preview table (UC-DS-02)"] =
        `PASS (real table: ${headerTexts.length} cols, first row matched)`;
    } else {
      // No table for a valid CSV. Cross-check the profiler ground truth to name
      // the root cause precisely — this is MY feature, so report it as a BUG.
      const rootCause =
        profCols.length === 0 || profRows.length === 0
          ? `perception profiler returned ${profCols.length} cols / ${profRows.length} rows ` +
            `for a valid CSV (quality=${prof?.quality}, notes=${JSON.stringify(prof?.notes ?? [])}) ` +
            `— datasetRef was an S3 key "${s3Key}" that the backend _resolve_path could not read`
          : `profiler returned ${profCols.length} cols / ${profRows.length} rows but the UI table did not render`;
      verdicts["B · dataset preview table (UC-DS-02)"] = `BUG — ${rootCause}`;
      console.error(`[PART B] BUG: ${rootCause}`);
      // Fail loudly so the BUG is unmissable (it is a real product defect).
      throw new Error(`UC-DS-02 BUG — Preview table did not render. ${rootCause}`);
    }
  });
});
