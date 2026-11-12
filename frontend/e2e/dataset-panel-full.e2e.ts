/**
 * DatasetObject (data-hub dataset panel) — COMPREHENSIVE live audit.
 * ==================================================================
 * TEST ARTIFACT — do NOT commit (per task). Drives the real DatasetObject on
 * https://dev-public.biomate.ai against real project files, screenshots every
 * state, and records a pass/fail matrix grounded in rendered DOM/pixels.
 *
 * Discipline (CLAUDE.md §E2E):
 *   - Single canonical fixture; login ONCE (loginAsFixture caches the JWT→cookie
 *     module-wide, reused across all tests here).
 *   - NO backend-response mocking and no page.route at all: the browser is
 *     authenticated by the session cookie (_fixture-login.ts), which never
 *     reaches presigned S3 URLs, so the type-aware preview fetches S3 as a real
 *     browser does.
 *
 * Data (probed live 2026-10-28):
 *   - UPLOAD project "MG PBMC — sample data demo" (3cd5292d…): counts_matrix.csv
 *     (text/csv, 23382 B → "22.8 KB", numeric columns) + preview_checks.json
 *     (application/json) → exercises header, Preview table/sort/filter/columns/
 *     plot, type-aware JSON, Versions.
 *   - RUN-OUTPUT project (060f8039…): toxicity_report.json etc., all produced by
 *     run c40459b2 / workflow "Predict ADMET Properties (AI)" / step "run" →
 *     exercises the Provenance "Output from workflow" row (workflow·step label,
 *     never a raw run id) + Data QC + consumers.
 */
import { test, expect, type Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });
test.setTimeout(6 * 60_000);

const OUT =
  process.env.SHOT_DIR ||
  "/private/tmp/claude-501/-Users-kky-biomate-review/68177db6-d7aa-4237-b387-f3aab691085b/scratchpad/dataset-panel-shots";
fs.mkdirSync(OUT, { recursive: true });

// Upload project (CSV + JSON uploads)
const UP_PROJECT = "3cd5292d-fcc4-4d78-8d41-53d6d3a5e77a";
const CSV_FILE = "5288f63c-d6e5-4fcb-b192-f35dad49991b"; // counts_matrix.csv (numeric, 22.8KB)
const JSON_FILE = "da07d4b4-42c6-4b03-a340-45d35b5de6ae"; // preview_checks.json

// Run-output project (Provenance)
const RO_PROJECT = "060f8039-f0b0-46fb-bd87-3047b4c8e5f8";
const RO_FILE = "7557a9d2-bbf6-44a3-89e9-234d75879400"; // toxicity_report.json (run_output)
const RO_RUN_ID = "c40459b2-4dd0-407e-bbbd-e985df4ce0fc";
const RO_WF = "Predict ADMET Properties (AI)";

const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
const LONGHEX_RE = /\b[0-9a-f]{16,}\b/i;

type Verdict = "PASS" | "FAIL" | "NOT-TESTABLE";
const results: { id: string; check: string; verdict: Verdict; shot: string; note: string }[] = [];
function rec(id: string, check: string, verdict: Verdict, shot: string, note: string) {
  results.push({ id, check, verdict, shot, note });
  console.log(`RESULT | ${id} | ${check} | ${verdict} | ${shot} | ${note}`);
}

let page: Page;

async function shot(name: string): Promise<string> {
  const f = `${name}.png`;
  await page.screenshot({ path: path.join(OUT, f), fullPage: true }).catch(() => {});
  return f;
}
async function vis(testid: string, ms = 15_000): Promise<boolean> {
  const loc = page.locator(`[data-testid="${testid}"]`).first();
  await loc.waitFor({ state: "visible", timeout: ms }).catch(() => {});
  return loc.isVisible().catch(() => false);
}
async function txt(testid: string): Promise<string> {
  return (await page.locator(`[data-testid="${testid}"]`).first().innerText().catch(() => "")) ?? "";
}

// Open a dataset by deep-link (?file=) with the active project preset, then wait
// for the DatasetObject to mount (fall back to clicking the file row).
async function openDataset(projectId: string, fileId: string) {
  await page.addInitScript((pid) => {
    try { localStorage.setItem("biomate-active-project-id", pid as string); } catch { /* */ }
  }, projectId);
  await page.goto(`${BASE_URL}/files?file=${fileId}`, { waitUntil: "domcontentloaded", timeout: 60_000 });
  // Condition wait: the deep link opens the object, or at least the file row renders.
  const obj = page.locator('[data-testid="dataset-object"]').first();
  const row = page.locator(`[data-testid="file-open-${fileId}"]`).first();
  await obj.or(row).first().waitFor({ state: "visible", timeout: 30_000 }).catch(() => {});
  if (!(await obj.isVisible()) && (await row.isVisible())) await row.click();
  await obj.waitFor({ state: "visible", timeout: 20_000 }).catch(() => {});
}

test.beforeAll(async ({ browser }) => {
  page = await browser.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });
  await loginAsFixture(page);
});

test.afterAll(async () => {
  fs.writeFileSync(path.join(OUT, "_results.json"), JSON.stringify(results, null, 2));
  const counts = results.reduce((a, r) => ((a[r.verdict] = (a[r.verdict] ?? 0) + 1), a), {} as Record<string, number>);
  console.log("COUNTS |", JSON.stringify(counts));
  await page?.close();
});

// ─────────────────────────────────────────────────────────────────────────────
// FLOW 1 — Upload CSV: HEADER + PREVIEW (table/sort/filter/columns/plot) + VERSIONS
// ─────────────────────────────────────────────────────────────────────────────
test("Flow 1 — CSV upload: header + preview + versions", async () => {
  await openDataset(UP_PROJECT, CSV_FILE);
  const mounted = await vis("dataset-object", 20_000);
  let s = await shot("01_csv_mounted");
  if (!mounted) {
    rec("MOUNT", "DatasetObject mounts for CSV", "FAIL", s, "dataset-object never visible on upload project");
    return;
  }

  // ── HEADER ──
  const name = (await txt("dataset-object-name")).trim();
  rec("H-name", "header name (not undefined/empty)", name.length > 0 && !/undefined/i.test(name) ? "PASS" : "FAIL", s, `name='${name}'`);

  const hasType = await vis("dataset-header-type", 4000);
  const typeTxt = (await txt("dataset-header-type")).trim();
  rec("H-type", "content-type badge (dataset-header-type)", hasType && typeTxt.length > 0 ? "PASS" : "FAIL", s, `type badge='${typeTxt}'`);

  const hasSize = await vis("dataset-header-size", 4000);
  const sizeTxt = (await txt("dataset-header-size")).trim();
  const sizeOk = hasSize && /\d/.test(sizeTxt) && /(B|KB|MB|GB)\b/.test(sizeTxt);
  rec("H-size", "SIZE badge present w/ real value (dataset-header-size)", sizeOk ? "PASS" : "FAIL", s, `size badge='${sizeTxt}'`);

  const hasVer = await vis("dataset-header-version", 4000);
  const verTxt = (await txt("dataset-header-version")).trim();
  rec("H-version", "version chip (dataset-header-version)", hasVer && /^v/i.test(verTxt) ? "PASS" : "FAIL", s, `version chip='${verTxt}'`);

  // Quality pill is profile-dependent (perception may resolve or not).
  const hasQual = await vis("dataset-header-quality", 6000);
  const qualTxt = (await txt("dataset-header-quality")).trim();
  rec("H-quality", "quality pill (dataset-header-quality)", hasQual ? "PASS" : "NOT-TESTABLE", s,
    hasQual ? `quality pill='${qualTxt}'` : "perception profile returned no quality verdict → pill absent (honest)");

  // Segmented pill tab group: gray track (bg-muted) with raised white selected box
  // (bg-background + shadow), NOT an underline.
  const tablist = page.locator('[role="tablist"]').first();
  const trackCls = (await tablist.getAttribute("class").catch(() => "")) ?? "";
  const selTab = page.locator('[data-testid="dataset-tab-preview"]');
  const selCls = (await selTab.getAttribute("class").catch(() => "")) ?? "";
  const selAria = await selTab.getAttribute("aria-selected").catch(() => "");
  const segmented = /bg-muted/.test(trackCls) && /bg-background/.test(selCls) && /shadow/.test(selCls) && selAria === "true";
  rec("H-tabs", "tabs render as SEGMENTED PILL group (not underline)", segmented ? "PASS" : "FAIL", s,
    `track has bg-muted=${/bg-muted/.test(trackCls)}; selected has bg-background=${/bg-background/.test(selCls)} shadow=${/shadow/.test(selCls)} aria-selected=${selAria}`);

  const analyze = await vis("dataset-object-analyze", 4000);
  const download = await vis("dataset-object-download", 4000);
  rec("H-actions", "actions: Use in chat + Download", analyze && download ? "PASS" : "FAIL", s,
    `analyze(Use in chat)=${analyze} download=${download}`);

  // ── PREVIEW — Table ──
  await page.locator('[data-testid="dataset-tab-preview"]').click().catch(() => {});
  const previewWrap = await vis("dataset-preview", 8000);
  const tableVisible = await vis("dataset-preview-table", 8000);
  s = await shot("02_csv_preview_table");
  rec("P-table", "Preview table renders rows/cols for CSV", previewWrap && tableVisible ? "PASS" : "FAIL", s,
    `dataset-preview=${previewWrap} dataset-preview-table=${tableVisible}`);

  // ── PREVIEW — sort header reorders ──
  if (tableVisible) {
    const firstColCells = async () =>
      page.locator('[data-testid="dataset-preview-table"] tbody tr td:first-child').allInnerTexts().catch(() => [] as string[]);
    const before = await firstColCells();
    // Click once → ascending. Click again on the SAME header → descending. The
    // descending order MUST be the exact reverse of the ascending order — this
    // proves the sort actually reorders, independent of the data's initial order
    // (the sample may already be ascending, so a single click can be a no-op).
    const ascending = (xs: string[]) => xs.every((v, i) => i === 0 || xs[i - 1].localeCompare(v) <= 0 ||
      (Number.isFinite(Number(xs[i - 1])) && Number.isFinite(Number(v)) && Number(xs[i - 1]) <= Number(v)));
    await page.locator('[data-testid="dataset-col-sort-0"]').first().click().catch(() => {});
    await expect.poll(async () => ascending(await firstColCells()), { timeout: 5_000 }).toBe(true).catch(() => {});
    const asc = await firstColCells();
    await page.locator('[data-testid="dataset-col-sort-0"]').first().click().catch(() => {});
    await expect.poll(firstColCells, { timeout: 5_000 }).not.toEqual(asc).catch(() => {});
    const desc = await firstColCells();
    s = await shot("03_csv_sorted");
    const isAsc = ascending(asc);
    const reversed = JSON.stringify(desc) === JSON.stringify([...asc].reverse());
    const reorders = reversed && JSON.stringify(asc) !== JSON.stringify(desc);
    rec("P-sort", "sort header (dataset-col-sort-0) reorders (asc↔desc toggle)",
      isAsc && reorders && asc.length > 1 ? "PASS" : "FAIL", s,
      `rows=${asc.length} ascending=${isAsc} desc-is-reverse-of-asc=${reversed} | asc[0..2]=${JSON.stringify(asc.slice(0,3))} desc[0..2]=${JSON.stringify(desc.slice(0,3))}`);

    // ── PREVIEW — filter input filters rows ──
    const rowsBefore = await page.locator('[data-testid="dataset-preview-table"] tbody tr').count();
    const sampleCell = (asc[0] ?? before[0] ?? "").trim();
    const token = sampleCell.slice(0, Math.min(3, sampleCell.length)) || "a";
    await page.locator('[data-testid="dataset-preview-filter"]').fill(token).catch(() => {});
    const rowTexts = () => page.locator('[data-testid="dataset-preview-table"] tbody tr').allInnerTexts();
    await expect.poll(async () => (await rowTexts()).every((t) => t.toLowerCase().includes(token.toLowerCase())), { timeout: 5_000 })
      .toBe(true).catch(() => {});
    const rowsAfter = await page.locator('[data-testid="dataset-preview-table"] tbody tr').count();
    s = await shot("04_csv_filtered");
    rec("P-filter", "filter input (dataset-preview-filter) filters rows", rowsAfter > 0 && rowsAfter <= rowsBefore ? "PASS" : "FAIL", s,
      `token='${token}' rowsBefore=${rowsBefore} rowsAfter=${rowsAfter}`);
    await page.locator('[data-testid="dataset-preview-filter"]').fill("").catch(() => {});
    await expect.poll(() => page.locator('[data-testid="dataset-preview-table"] tbody tr').count(), { timeout: 5_000 })
      .toBe(rowsBefore).catch(() => {});
  } else {
    rec("P-sort", "sort header reorders", "NOT-TESTABLE", s, "no preview table (profiler returned no columns/rows)");
    rec("P-filter", "filter filters rows", "NOT-TESTABLE", s, "no preview table");
  }

  // ── PREVIEW — Columns toggle ──
  await page.locator('[data-testid="dataset-preview-toggle-columns"]').click().catch(() => {});
  const colsFuture = await vis("dataset-preview-columns-future", 4000);
  s = await shot("05_csv_columns");
  rec("P-columns", "Columns view toggle renders", colsFuture ? "PASS" : "FAIL", s,
    `columns-future fallback=${colsFuture} (profiler has no per-column stats → honest fallback)`);

  // ── PREVIEW — Plot toggle ──
  await page.locator('[data-testid="dataset-preview-toggle-plot"]').click().catch(() => {});
  const plot = await vis("dataset-sample-plot", 5000);
  const plotFuture = await vis("dataset-preview-plot-future", 2000);
  s = await shot("06_csv_plot");
  rec("P-plot", "Plot view toggle renders distribution or honest fallback", plot || plotFuture ? "PASS" : "FAIL", s,
    plot ? "dataset-sample-plot rendered (numeric distribution)" : plotFuture ? "honest plot-future fallback (no numeric sample)" : "neither plot nor fallback");

  // ── VERSIONS ──
  await page.locator('[data-testid="dataset-tab-versions"]').click().catch(() => {});
  const versWrap = await vis("dataset-versions", 6000);
  const noVers = await vis("dataset-no-versions", 2000);
  const verRows = await page.locator('[data-testid^="dataset-version-"]').count();
  s = await shot("07_csv_versions");
  rec("V-log", "Versions tab shows version log", versWrap ? "PASS" : "FAIL", s,
    `dataset-versions=${versWrap} version-rows=${verRows} no-versions-empty=${noVers} (likely v1-only)`);

  // GLOBAL text-hygiene on the whole open panel (upload file).
  const panelText = await txt("dataset-object");
  const uuidHit = panelText.match(UUID_RE);
  const hexHit = panelText.match(LONGHEX_RE);
  const undef = /\bundefined\b/i.test(panelText);
  const nan = /\bNaN\b/.test(panelText);
  const rawKey = /\b(dataset_obj|file_tree|actions|nav)\.[a-z_]+/i.test(panelText);
  rec("G-upload", "no raw uuid/hex/undefined/NaN/i18n-key visible (upload panel)",
    !uuidHit && !undef && !nan && !rawKey ? "PASS" : "FAIL", s,
    `uuid=${uuidHit?.[0] ?? "none"} longhex=${hexHit?.[0] ?? "none"} undefined=${undef} NaN=${nan} rawKey=${rawKey}`);
});

// ─────────────────────────────────────────────────────────────────────────────
// FLOW 2 — Type-awareness: a JSON upload previews structurally, not empty table
// ─────────────────────────────────────────────────────────────────────────────
test("Flow 2 — type-aware preview (JSON upload)", async () => {
  await openDataset(UP_PROJECT, JSON_FILE);
  const mounted = await vis("dataset-object", 15_000);
  if (!mounted) { rec("T-json", "JSON type-aware preview", "FAIL", await shot("08_json_mounted"), "dataset-object did not mount"); return; }
  await page.locator('[data-testid="dataset-tab-preview"]').click().catch(() => {});
  const textPreview = await vis("dataset-text-preview", 8000);
  const richTable = await vis("dataset-preview-table", 2000);
  const none = await vis("dataset-preview-none", 2000);
  const s = await shot("09_json_preview");
  // A JSON file must preview structurally (FileContentView → table/json view via
  // dataset-text-preview) OR as the profiler table — NOT a bare "no preview".
  const pretxt = await txt("dataset-text-preview");
  const structural = textPreview && (pretxt.includes("{") || pretxt.includes(":") || (await page.locator('[data-testid="dataset-text-preview"] table, [data-testid="dataset-text-preview"] pre').count()) > 0);
  rec("T-json", "JSON upload previews structurally (not empty table)",
    structural || richTable ? "PASS" : none ? "FAIL" : "FAIL", s,
    `dataset-text-preview=${textPreview} rich-table=${richTable} preview-none=${none} structural=${structural}`);
  rec("T-image", "image → <img>", "NOT-TESTABLE", s, "no png/jpg/gif/webp file in any accessible fixture project (reliably scanned 139/139 projects; only .txt/.csv/.fastq/.json/.yml present)");
  rec("T-pdf", "PDF → iframe", "NOT-TESTABLE", s, "no .pdf file in any accessible fixture project (reliably scanned 139/139 projects; only .txt/.csv/.fastq/.json/.yml present)");
  rec("T-fasta-vcf", "FASTA/VCF → structural text", "NOT-TESTABLE", s, "no .fa/.fasta/.vcf file in any accessible fixture project (reliably scanned 139/139 projects; only .txt/.csv/.fastq/.json/.yml present)");
  rec("T-mrc", "MRC/.map → 3-axis density viewer", "NOT-TESTABLE", s, "no .mrc/.map/.rec density file in any accessible fixture project (reliably scanned 139/139 projects; only .txt/.csv/.fastq/.json/.yml present)");
});

// ─────────────────────────────────────────────────────────────────────────────
// FLOW 3 — Provenance (run-output file): the key terminology/behavior checks
// ─────────────────────────────────────────────────────────────────────────────
test("Flow 3 — Provenance tab (run-output file)", async () => {
  await openDataset(RO_PROJECT, RO_FILE);
  const mounted = await vis("dataset-object", 20_000);
  let s = await shot("10_ro_mounted");
  if (!mounted) { rec("PROV-mount", "run-output DatasetObject mounts", "FAIL", s, "dataset-object did not mount on run-output project"); return; }

  // run-output header: size badge must still be present (bug was it missing).
  const roSize = (await txt("dataset-header-size")).trim();
  rec("PROV-size", "run-output header SIZE badge present", /\d/.test(roSize) && /(B|KB|MB|GB)\b/.test(roSize) ? "PASS" : "FAIL", s, `size badge='${roSize}'`);

  // Tab label reads "Provenance" (not "Where it came from").
  const wfTabLabel = (await txt("dataset-tab-wherefrom")).trim();
  rec("PROV-label", 'tab label reads "Provenance"', /^provenance$/i.test(wfTabLabel) ? "PASS" :
    /where it came from/i.test(wfTabLabel) ? "FAIL" : "FAIL", s, `tab label='${wfTabLabel}'`);

  await page.locator('[data-testid="dataset-tab-wherefrom"]').click().catch(() => {});
  const wfWrap = await vis("dataset-wherefrom", 8000);
  const originWrap = await vis("dataset-origin", 6000);
  s = await shot("11_ro_provenance");

  const originText = await txt("dataset-origin");
  // Storage ref / S3 key must be ABSENT.
  const hasStorageRef = /storage\s*ref/i.test(originText) || /s3:\/\//i.test(originText) || /projects\/.+\/.+\.(json|txt|yml)/i.test(originText);
  rec("PROV-origin", "Origin block present; internal S3 'Storage ref' ABSENT", originWrap && !hasStorageRef ? "PASS" : "FAIL", s,
    `origin=${originWrap} storage-ref-present=${hasStorageRef}`);

  // "Output from workflow" row: workflow·step label, NEVER a raw run id.
  const openRunBtn = page.locator('[data-testid="lineage-open-run"]').first();
  const openRunVisible = await openRunBtn.isVisible().catch(() => false);
  const openRunLabel = (await openRunBtn.innerText().catch(() => "")) ?? "";
  const labelIsUuid = UUID_RE.test(openRunLabel);
  const labelHasWf = openRunLabel.includes(RO_WF);
  rec("PROV-produced", '"Output from workflow" shows workflow·step, not a raw run id',
    openRunVisible && labelHasWf && !labelIsUuid ? "PASS" : "FAIL", s,
    `row-visible=${openRunVisible} label='${openRunLabel.trim()}' isUuid=${labelIsUuid} (expected '${RO_WF} · run')`);

  // Added row present (origin should carry an Added date).
  const addedOk = /added/i.test(originText);
  rec("PROV-added", "Origin shows Added date", addedOk ? "PASS" : "FAIL", s, `origin text contains 'Added'=${addedOk}`);

  // Consumers: each shows a workflow name or the Open-run action, NEVER a raw id.
  const consWrap = await vis("dataset-consumers", 6000);
  const noCons = await vis("dataset-no-consumers", 3000);
  const consEls = page.locator('[data-testid^="dataset-consumer-"]');
  const consN = await consEls.count();
  let consBad = "";
  for (let i = 0; i < consN; i++) {
    const ct = (await consEls.nth(i).innerText().catch(() => "")) ?? "";
    if (UUID_RE.test(ct) || LONGHEX_RE.test(ct)) consBad += `[${ct.trim()}]`;
  }
  rec("PROV-consumers", '"Input to workflow": name or Open-run action, never a raw run id',
    consWrap && !consBad ? "PASS" : "FAIL", s,
    noCons ? "honest-empty 'No runs recorded as reading this dataset yet.'" : `${consN} consumer rows; raw-id rows=${consBad || "none"}`);

  // Data-quality card labelled "Data QC".
  const qcWrap = await vis("dataset-quality", 6000);
  const qcHeading = (await txt("dataset-quality")).split("\n")[0]?.trim() ?? "";
  rec("PROV-dataqc", 'Data-quality card labelled "Data QC"', qcWrap && /data qc/i.test(qcHeading) ? "PASS" : "FAIL", s,
    `card-visible=${qcWrap} heading='${qcHeading}'`);

  // GLOBAL text-hygiene on the whole open provenance panel.
  const panelText = await txt("dataset-object");
  const uuidHit = panelText.match(UUID_RE);
  const hexHit = panelText.match(LONGHEX_RE);
  const runIdVisible = panelText.includes(RO_RUN_ID);
  const undef = /\bundefined\b/i.test(panelText);
  const nan = /\bNaN\b/.test(panelText);
  const rawKey = /\b(dataset_obj|file_tree|actions|nav)\.[a-z_]+/i.test(panelText);
  rec("G-prov", "no raw run-id/uuid/hex/undefined/NaN/i18n-key visible (provenance panel)",
    !uuidHit && !runIdVisible && !undef && !nan && !rawKey ? "PASS" : "FAIL", s,
    `uuid=${uuidHit?.[0] ?? "none"} runId-visible=${runIdVisible} longhex=${hexHit?.[0] ?? "none"} undefined=${undef} NaN=${nan} rawKey=${rawKey}`);
});
