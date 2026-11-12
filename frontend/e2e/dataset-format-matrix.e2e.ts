/**
 * E2E (dev, live, no mocks): dataset-panel FORMAT MATRIX — a pass/fail gate per format.
 *
 * For every common bioinformatics format (real fixtures from Galaxy's own datatype tests, plus a
 * few small files written inline and two folder uploads) this harness uploads the file into ONE
 * project, opens it in the Files view (data hub), waits for the panel to settle (a condition: no
 * loading markers and an unchanged DOM for 3 polls, bounded) and checks the outcome against the
 * committed table e2e/format-matrix-expectations.json:
 *   core      — settled; dataset-object[data-view-kind] and dataset-preview[data-preview-kind] are
 *               the expected kinds; no dataset-preview-none where a preview is expected; no visible
 *               error (role=alert / *-error testid) and no page errors;
 *   secondary — rows-table columns for rowKinds (required / min / max / must-not-be-header), QC
 *               verdict class (data-perception[data-quality] ∈ expected set; watch/blocked list a
 *               reason), per-kind stat cards (dataset-stat[data-stat], the profiler's stat codes),
 *               and no Table/Columns/Plot/Edit toggles outside toggleKinds.
 * The kinds are the backend profiler's vocabulary (data_perception.py decide(): viewKind), so the
 * panel, the profile and this table speak one language.
 * Verdict per item: PASS (all checks) / PARTIAL (core ok, some secondary failed) / FAIL (a core
 * check failed). The harness computes the verdicts and the counts and writes them to
 * e2e/format-matrix-results.json (after every item, so a partial run keeps what it measured);
 * the test then FAILS unless every item is PASS. Only testids and data-* attributes are read —
 * never English UI text. The expectations describe the TARGET contract of
 * docs/20261112_DATASET_PANEL_AUDIT.md, so the matrix is expected to fail until those fixes deploy.
 *
 * Folders: the tree's folder rows + each folder opened as an object (folder view) with asserted
 * facts: pairs/ → S1 paired, S2_R1 orphan, a paired samplesheet (S1) + a single-end sheet (S2) downloaded from the UI; tenx/ →
 * a recognised 10x matrix with its cells × genes; per-file consequences (S1_R1's QC names its mate,
 * S2_R1's has fastq_mate_missing, features.tsv is header-less).
 *
 * Rules honoured (CLAUDE.md): fixture account, ONE login (cookie session; all API calls through
 * page.request), ONE project deleted loudly in finally, never register, no page.route at all.
 *
 * Content-hash dedup: uploads with identical bytes link to one entry (project-routes.ts), so the
 * folder copies are made byte-distinct (read headers renamed; an extra MatrixMarket comment line).
 *
 * Run: cd frontend && BIOMATE_URL=https://dev-public.biomate.ai npx playwright test \
 *      e2e/dataset-format-matrix.e2e.ts --project=chromium --reporter=line --retries=0
 *      (fixtures: GALAXY_DATATYPE_TEST_DIR, else ../backend/lib/galaxy/datatypes/test of this or the
 *      main checkout — a missing fixture dir FAILS the run, it is not skipped.)
 */
import { test, expect, type Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import * as zlib from "zlib";
import { fileURLToPath } from "url";
import { BASE_URL, loginAsFixture } from "./_fixture-login";
import { createProject, deleteProjectLoudly, uploadFile, openProjectFiles, openFile, revealFile } from "./_project-ui";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const GALAXY_TEST = [
  process.env.GALAXY_DATATYPE_TEST_DIR,
  path.resolve(HERE, "../../backend/lib/galaxy/datatypes/test"),
  "/Users/kky/biomate-review/backend/lib/galaxy/datatypes/test",
].find((d): d is string => !!d && fs.existsSync(path.join(d, "2.csv"))) ?? "";
const SHOTS = path.join(HERE, "screenshots", "format-matrix");
const RESULTS = path.join(HERE, "format-matrix-results.json");
const EXPECTATIONS = JSON.parse(fs.readFileSync(path.join(HERE, "format-matrix-expectations.json"), "utf8"));
const SETTLE_MS = 75_000;

test.use({ deviceScaleFactor: 1 });

type Item = {
  key: string;            // screenshot / result / expectation key
  name: string;           // uploaded file name (basename)
  relativePath?: string;  // folder upload: "pairs/S1_R1.fastq.gz"
  folder?: string;        // folder group
  src?: string;           // Galaxy fixture basename
  bytes?: () => Buffer;   // inline / derived content
  expect: string;         // what an ideal dataset panel shows for this format (prose; the checks are in the JSON)
};

const fx = (f: string) => fs.readFileSync(path.join(GALAXY_TEST, f));
const fastq = () => zlib.gunzipSync(fx("1.fastqsanger.gz")).toString("utf8");
const reheader = (txt: string, fn: (h: string) => string) =>
  txt.split("\n").map((l, i) => (i % 4 === 0 && l.startsWith("@") ? fn(l) : l)).join("\n");

const GENES = "TP53\nBRCA1\nEGFR\nMYC\nKRAS\nPTEN\nAKT1\nPIK3CA\nCDKN2A\nRB1\nERBB2\nNRAS\n";
const NARROWPEAK = [
  "chr1\t9980\t10480\tpeak_1\t850\t.\t12.51\t45.20\t42.10\t250",
  "chr1\t15420\t15890\tpeak_2\t640\t.\t8.33\t30.11\t27.95\t198",
  "chr2\t120400\t121010\tpeak_3\t1000\t.\t20.02\t88.70\t85.12\t305",
  "chr3\t500012\t500398\tpeak_4\t412\t.\t5.10\t15.42\t13.00\t160",
  "chrX\t77001\t77560\tpeak_5\t733\t.\t10.92\t39.03\t36.41\t271",
].join("\n") + "\n";
const BARCODES = ["AAACATACAACCAC-1", "AAACATTGAGCTAC-1", "AAACATTGATCAGC-1", "AAACCGTGCTTCCG-1", "AAACCGTGTATGCG-1"].join("\n") + "\n";
const FEATURES = [
  "ENSG00000243485\tMIR1302-2HG\tGene Expression",
  "ENSG00000237613\tFAM138A\tGene Expression",
  "ENSG00000186092\tOR4F5\tGene Expression",
  "ENSG00000238009\tAL627309.1\tGene Expression",
  "ENSG00000239945\tAL627309.3\tGene Expression",
].join("\n") + "\n";

const ITEMS: Item[] = [
  { key: "csv", name: "2.csv", src: "2.csv", expect: "rows table with header x,y,z" },
  { key: "tsv", name: "2.tsv", src: "2.tabular", expect: "rows table (3 numeric columns, header-less)" },
  { key: "bed", name: "1.bed", src: "1.bed", expect: "interval table chrom/start/end/name/score/strand…" },
  { key: "bed-complete", name: "complete.bed", src: "complete.bed", expect: "BED12 interval table" },
  { key: "gtf", name: "grch37.75.gtf", src: "grch37.75.gtf", expect: "annotation table seqname/source/feature/start/end/…/attributes" },
  { key: "gff3", name: "gff.gff3", src: "gff.gff3", expect: "annotation table (GFF3 columns)" },
  { key: "fasta", name: "1.fasta", src: "1.fasta", expect: "sequence viewer (records, lengths)" },
  { key: "fasta-gz", name: "1.fasta.gz", src: "1.fasta.gz", expect: "decompressed sequence viewer" },
  { key: "fastq", name: "1.fastq", src: "1.fastqsanger", expect: "reads viewer (id/seq/qual) + read QC" },
  { key: "fastq-gz", name: "1.fastq.gz", src: "1.fastqsanger.gz", expect: "decompressed reads viewer + read QC" },
  { key: "vcf", name: "1.vcf", src: "1.vcf", expect: "variant table CHROM/POS/ID/REF/ALT/QUAL/FILTER/INFO + samples" },
  { key: "vcf-gz", name: "1.vcf.gz", src: "1.vcf_bgzip", expect: "decompressed (bgzip) variant table" },
  { key: "bam", name: "1.bam", src: "1.bam", expect: "alignment summary / header (binary; needs server-side decode)" },
  { key: "cram", name: "2.cram", src: "2.cram", expect: "alignment summary (binary; needs reference)" },
  { key: "h5ad", name: "pbmc3k_tiny.h5ad", src: "pbmc3k_tiny.h5ad", expect: "AnnData summary (n_obs × n_vars, obs/var columns)" },
  { key: "loom", name: "test.loom", src: "test.loom", expect: "Loom summary (matrix shape, row/col attrs)" },
  { key: "xlsx", name: "1.xlsx", src: "1.excel.xlsx", expect: "sheet rows table" },
  { key: "mtx", name: "1.mtx", src: "1.mtx", expect: "sparse matrix summary (5×5, 8 nnz) or triplet table" },
  { key: "sdf", name: "drugbank_drugs.sdf", src: "drugbank_drugs.sdf", expect: "molecule table / 2D structures" },
  { key: "smi", name: "drugbank_drugs.smi", src: "drugbank_drugs.smi", expect: "SMILES table / 2D structures" },
  { key: "pdb", name: "5e5z.pdb", src: "5e5z.pdb", expect: "3D structure viewer" },
  { key: "cif", name: "Si.cif", src: "Si.cif", expect: "3D structure / crystal viewer" },
  { key: "mrc", name: "1.mrc", src: "1.mrc", expect: "density map slices" },
  { key: "tiff", name: "1.tiff", src: "1.tiff", expect: "image" },
  { key: "json", name: "1.json", src: "1.json", expect: "JSON tree / value" },
  { key: "pod5", name: "test.pod5", src: "test.pod5", expect: "nanopore read summary (binary)" },
  { key: "gene-list", name: "gene_list.txt", bytes: () => Buffer.from(GENES), expect: "single-column list (header-less) — 12 genes, no fake header" },
  { key: "narrowpeak", name: "peaks.narrowPeak", bytes: () => Buffer.from(NARROWPEAK), expect: "peak table (10 narrowPeak columns)" },
  // Folder 1: paired FASTQ with an orphan R1 (byte-distinct copies of 1.fastqsanger.gz).
  { key: "pairs-S1_R1", folder: "pairs", name: "S1_R1.fastq.gz", relativePath: "pairs/S1_R1.fastq.gz",
    bytes: () => zlib.gzipSync(reheader(fastq(), (h) => "@S1_" + h.slice(1))), expect: "reads; folder shows S1 pair" },
  { key: "pairs-S1_R2", folder: "pairs", name: "S1_R2.fastq.gz", relativePath: "pairs/S1_R2.fastq.gz",
    bytes: () => zlib.gzipSync(reheader(fastq(), (h) => "@S1_" + h.slice(1).replace(/\/1$/, "/2"))), expect: "reads; pairs with S1_R1" },
  { key: "pairs-S2_R1", folder: "pairs", name: "S2_R1.fastq.gz", relativePath: "pairs/S2_R1.fastq.gz",
    bytes: () => zlib.gzipSync(reheader(fastq(), (h) => "@S2_" + h.slice(1))), expect: "reads; flagged as orphan (no R2)" },
  // Folder 2: a 10x-style matrix folder.
  { key: "tenx-matrix", folder: "tenx", name: "matrix.mtx", relativePath: "tenx/matrix.mtx",
    bytes: () => Buffer.from(fx("1.mtx").toString("utf8").replace(/\n/, "\n% tenx/matrix.mtx (1.mtx)\n")), expect: "5×5 matrix; folder recognised as 10x" },
  { key: "tenx-barcodes", folder: "tenx", name: "barcodes.tsv", relativePath: "tenx/barcodes.tsv", bytes: () => Buffer.from(BARCODES), expect: "barcode list (header-less)" },
  { key: "tenx-features", folder: "tenx", name: "features.tsv", relativePath: "tenx/features.tsv", bytes: () => Buffer.from(FEATURES), expect: "features table id/symbol/type (header-less)" },
];

function mimeOf(name: string): string {
  const n = name.toLowerCase();
  if (n.endsWith(".gz")) return "application/gzip";
  if (n.endsWith(".csv")) return "text/csv";
  if (n.endsWith(".tsv")) return "text/tab-separated-values";
  if (n.endsWith(".json")) return "application/json";
  if (n.endsWith(".tiff")) return "image/tiff";
  if (n.endsWith(".xlsx")) return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
  if (/\.(bed|gtf|gff3|fasta|fastq|vcf|pdb|cif|sdf|smi|mtx|txt|narrowpeak)$/.test(n)) return "text/plain";
  return "application/octet-stream";
}

/** Snapshot of the open dataset object — testids and data-* attributes only (no UI text). */
async function snapshot(page: Page) {
  return page.evaluate(() => {
    const obj = document.querySelector('[data-testid="dataset-object"]') as HTMLElement | null;
    const q = (sel: string, root: ParentNode = document) => root.querySelector(sel) as HTMLElement | null;
    const prev = obj ? q('[data-testid="dataset-preview"]', obj) : null;
    const qc = obj ? q('[data-testid="dataset-quality"]', obj) : null;
    const outsideQc = (e: Element) => !qc?.contains(e) && !e.closest('[data-testid="dataset-stat-grid"]');
    const inPrev = (sel: string) => (prev ? Array.from(prev.querySelectorAll(sel)).filter(outsideQc) : []);
    const testids = inPrev("[data-testid]").map((e) => e.getAttribute("data-testid")!).filter((v, i, a) => a.indexOf(v) === i);
    const rowsTable = prev ? q('[data-testid="dataset-preview-table"]', prev) : null;
    const columns = rowsTable
      ? Array.from(rowsTable.querySelectorAll("thead th")).map((th) => (th.getAttribute("data-column-name") ?? (th as HTMLElement).innerText).trim()).filter(Boolean)
      : [];
    // Legacy heuristic (recorded for diagnosis only; the checks use data-preview-kind).
    let legacyKind = "unknown";
    if (!obj) legacyKind = "no-dataset-object";
    else if (rowsTable) legacyKind = "rows-table";
    else if (prev && q('[data-testid="density-map-viewer"]', prev)) legacyKind = "density";
    else if (prev && q('[data-testid="inline-structure-viewer"]', prev)) legacyKind = "structure-3d";
    else if (inPrev("img").length) legacyKind = "image";
    else if (prev && q('[data-testid="dataset-json-tree"], [data-testid="json-preview"]', prev)) legacyKind = "json-tree";
    else if (prev && q('[data-testid="dataset-text-preview"]', prev)) legacyKind = "text";
    else if (prev && q('[data-testid="dataset-preview-none"]', prev)) legacyKind = "no-preview";
    else legacyKind = "message";
    const perception = qc ? q('[data-testid="data-perception"]', qc) : null;
    const codes = qc
      ? Array.from(qc.querySelectorAll('[data-testid="perception-why-item"], [data-testid="perception-finding"]')).map((e) => e.getAttribute("data-code") || "")
      : [];
    const errors = obj
      ? Array.from(obj.querySelectorAll('[role="alert"], [data-testid$="-error"]')).map((e) => e.getAttribute("data-testid") || "role=alert")
      : [];
    return {
      viewKind: obj?.getAttribute("data-view-kind") ?? null,
      previewKind: prev?.getAttribute("data-preview-kind") ?? null,
      legacyKind,
      previewTestids: testids,
      previewNone: !!(prev && q('[data-testid="dataset-preview-none"]', prev)),
      columns,
      rowCount: rowsTable ? rowsTable.querySelectorAll("tbody tr").length : 0,
      toggles: obj ? Array.from(obj.querySelectorAll('[data-testid^="dataset-preview-toggle-"]')).map((e) => e.getAttribute("data-testid")!.slice("dataset-preview-toggle-".length)) : [],
      stats: obj ? Array.from(obj.querySelectorAll('[data-testid="dataset-stat"]')).map((e) => e.getAttribute("data-stat") || "") : [],
      statGridPresent: !!(obj && q('[data-testid="dataset-stat-grid"]', obj)),
      qc: {
        state: !qc ? "absent" : perception ? "perception" : q('[data-testid="dataset-quality-loading"]', qc) ? "loading"
          : q('[data-testid="dataset-quality-error"]', qc) ? "error" : q('[data-testid="dataset-quality-noref"]', qc) ? "noref" : "other",
        quality: perception?.getAttribute("data-quality") ?? null,
        whyCount: qc ? qc.querySelectorAll('[data-testid="perception-why-item"]').length : 0,
        codes,
        // The QC card's text is kept for the folder checks that look for a DATA value (a mate's file name).
        text: ((qc?.innerText) || "").slice(0, 2000),
      },
      errors,
    };
  });
}

/**
 * Condition wait: the object is loaded (no *-loading testid, no aria-busy, no untagged role=status
 * line in the Preview) AND its DOM signature is unchanged for 3 consecutive polls (500 ms apart).
 */
async function waitSettled(page: Page, timeout: number): Promise<boolean> {
  await page.evaluate(() => { (window as any).__mxSig = ""; (window as any).__mxN = 0; });
  return page.waitForFunction(() => {
    const w = window as any;
    const obj = document.querySelector('[data-testid="dataset-object"]');
    const prev = obj?.querySelector('[data-testid="dataset-preview"]');
    const busy = !obj || !prev
      || !!obj.querySelector('[data-testid$="-loading"], [aria-busy="true"]')
      || Array.from(prev.querySelectorAll('[role="status"]')).some((e) => !e.getAttribute("data-testid") && !e.closest('[data-testid="dataset-quality"]'));
    if (busy) { w.__mxSig = ""; w.__mxN = 0; return false; }
    const sig = `${obj!.innerHTML.length}|${obj!.querySelectorAll("*").length}`;
    if (sig === w.__mxSig) w.__mxN++; else { w.__mxSig = sig; w.__mxN = 0; }
    return w.__mxN >= 3;
  }, undefined, { polling: 500, timeout }).then(() => true).catch(() => false);
}

type Check = { name: string; core: boolean; pass: boolean; detail?: string };

/** Evaluate one item's snapshot against its committed expectation → checks + verdict. */
function judge(key: string, snap: Awaited<ReturnType<typeof snapshot>>, settled: boolean, pageErrors: string[]) {
  const ex = EXPECTATIONS.items[key];
  const checks: Check[] = [];
  const add = (name: string, core: boolean, pass: boolean, detail?: string) => checks.push({ name, core, pass, ...(pass ? {} : { detail }) });
  if (!ex) {
    add("expectation-defined", true, false, `no entry for "${key}" in format-matrix-expectations.json`);
    return { checks, verdict: "FAIL" as const };
  }
  const rowKind = (EXPECTATIONS.rowKinds as string[]).includes(ex.viewKind);
  const toggleKind = (EXPECTATIONS.toggleKinds as string[]).includes(ex.viewKind);
  add("expectation-vocabulary", true, (EXPECTATIONS.viewKinds as string[]).includes(ex.viewKind),
    `viewKind "${ex.viewKind}" is not in the profiler's vocabulary`);
  add("settled", true, settled, `not settled within ${SETTLE_MS} ms`);
  add("view-kind", true, snap.viewKind === ex.viewKind, `data-view-kind=${snap.viewKind ?? "(missing)"} want ${ex.viewKind}`);
  add("preview-kind", true, snap.previewKind === ex.previewKind,
    `data-preview-kind=${snap.previewKind ?? "(missing)"} want ${ex.previewKind} (legacy: ${snap.legacyKind})`);
  add("has-preview", true, !snap.previewNone, "dataset-preview-none shown where a preview is expected");
  add("no-errors", true, snap.errors.length === 0, `errors: ${snap.errors.join(", ")}`);
  add("no-page-errors", true, pageErrors.length === 0, `pageErrors: ${pageErrors.slice(0, 3).join(" | ")}`);

  if (rowKind) {
    const cols = snap.columns.map((c) => c.toLowerCase());
    const missing = (ex.columns ?? []).filter((c: string) => !cols.includes(c.toLowerCase()));
    add("columns-required", false, missing.length === 0, `missing columns ${missing.join(", ")}; got [${snap.columns.slice(0, 12).join(", ")}]`);
    if (ex.minColumns != null) add("columns-min", false, snap.columns.length >= ex.minColumns, `${snap.columns.length} columns < ${ex.minColumns}`);
    if (ex.maxColumns != null) add("columns-max", false, snap.columns.length <= ex.maxColumns, `${snap.columns.length} columns > ${ex.maxColumns}`);
    const asHeader = (ex.notColumns ?? []).filter((c: string) => cols.includes(c.toLowerCase()));
    add("no-data-as-header", false, asHeader.length === 0, `data value(s) taken as header: ${asHeader.join(", ")}`);
    add("rows-shown", false, snap.rowCount > 0, "table has no body rows");
  }
  if (!toggleKind) {
    const bad = snap.toggles.filter((t: string) => (EXPECTATIONS.nonTableForbiddenToggles as string[]).includes(t));
    add("no-table-controls", false, bad.length === 0, `non-table kind shows toggles: ${bad.join(", ")}`);
  }

  const needIds: string[] = (ex.requirePreviewTestids ?? []).filter((id: string) => !snap.previewTestids.includes(id));
  if ((ex.requirePreviewTestids ?? []).length) {
    add("preview-testids", false, needIds.length === 0, `Preview lacks ${needIds.join(", ")}; has [${snap.previewTestids.slice(0, 20).join(", ")}]`);
  }

  const allowed: string[] = EXPECTATIONS.qualitySets[ex.quality] ?? [];
  add("quality-class", false, snap.qc.quality !== null && allowed.includes(snap.qc.quality),
    `data-quality=${snap.qc.quality ?? `(none; qc ${snap.qc.state})`} want ${ex.quality} [${allowed.join("|")}]`);
  if (snap.qc.quality === "watch" || snap.qc.quality === "blocked") {
    add("verdict-has-reason", false, snap.qc.whyCount > 0, `${snap.qc.quality} without a perception-why-item`);
  }

  const ks = EXPECTATIONS.kindStats[ex.viewKind] ?? EXPECTATIONS.kindStats["*"];
  const required: string[] = [...(ks.require ?? []), ...(ex.requireStats ?? []), ...(EXPECTATIONS.alwaysStats ?? [])];
  const needStats = required.filter((k: string) => !snap.stats.includes(k));
  const badStats = (ks.forbid ?? []).filter((k: string) => snap.stats.includes(k));
  add("stats-per-kind", false, needStats.length === 0 && badStats.length === 0 && snap.statGridPresent,
    `stat cards [${snap.stats.join(", ") || "(no dataset-stat testids)"}]: missing ${needStats.join(", ") || "-"}; forbidden ${badStats.join(", ") || "-"}`);

  const verdict = checks.some((c) => c.core && !c.pass) ? "FAIL" : checks.some((c) => !c.pass) ? "PARTIAL" : "PASS";
  return { checks, verdict: verdict as "PASS" | "PARTIAL" | "FAIL" };
}

test("dataset format matrix: upload → open → per-format outcome vs committed expectations", async ({ page, request }) => {
  test.setTimeout(60 * 60 * 1000);
  expect(GALAXY_TEST, "Galaxy datatype test fixtures not found (set GALAXY_DATATYPE_TEST_DIR)").not.toBe("");
  expect(Object.keys(EXPECTATIONS.items).sort(), "every item has exactly one expectation").toEqual(ITEMS.map((i) => i.key).sort());
  fs.mkdirSync(SHOTS, { recursive: true });

  const buildInfo = await request.get(`${BASE_URL}/build-info.json`).then((r) => r.json()).catch(() => ({}));
  await loginAsFixture(page);   // ONE login: cookie session for the browser AND page.request
  const api = page.request;
  const projectName = `e2e format matrix ${new Date().toISOString().slice(0, 16)}`;
  const projectId = await createProject(api, projectName);

  const out: any = { baseUrl: BASE_URL, buildInfo, startedAt: new Date().toISOString(), projectId,
    expectations: "e2e/format-matrix-expectations.json", summary: null, items: [] as any[], folders: {} as any };
  const summarize = () => {
    const s: Record<string, number> = { PASS: 0, PARTIAL: 0, FAIL: 0 };
    for (const r of out.items) s[r.verdict]++;
    out.summary = { ...s, total: out.items.length, expected: ITEMS.length };
  };
  const save = () => { summarize(); fs.writeFileSync(RESULTS, JSON.stringify(out, null, 2) + "\n"); };
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(String(e?.message || e).slice(0, 300)));

  try {
    // ── Uploads (multipart; relativePath BEFORE the file part keeps folders) ──
    const uploaded: Record<string, { id: string; storedName: string }> = {};
    out.uploadAttempts = {} as Record<string, number[]>;
    for (const it of ITEMS) {
      const up = await uploadFile(api, projectId, it.name, it.src ? fx(it.src) : it.bytes!(), mimeOf(it.name), it.relativePath);
      out.uploadAttempts[it.key] = up.attempts;
      expect(up.deduplicated, `${it.name} must be byte-distinct (dedup would hide it)`).toBeFalsy();
      uploaded[it.key] = { id: up.id, storedName: up.name };
    }

    await openProjectFiles(page, projectId, projectName);

    for (const it of ITEMS) {
      const up = uploaded[it.key];
      const t0 = Date.now();
      pageErrors.length = 0;
      await openFile(page, up.id, it.name, it.folder);
      const tab = page.getByTestId("dataset-tab-preview");
      if (await tab.isVisible()) await tab.click();
      const isSettled = await waitSettled(page, SETTLE_MS);
      const snap = await snapshot(page);
      await page.screenshot({ path: path.join(SHOTS, `${it.key}.png`) });
      const qcLoc = page.getByTestId("dataset-quality");
      if (await qcLoc.isVisible()) {
        await qcLoc.scrollIntoViewIfNeeded();
        await qcLoc.screenshot({ path: path.join(SHOTS, `${it.key}.qc.png`) });
      }
      const { checks, verdict } = judge(it.key, snap, isSettled, pageErrors);
      out.items.push({
        key: it.key, verdict, failed: checks.filter((c) => !c.pass).map((c) => `${c.core ? "core" : "secondary"}:${c.name} — ${c.detail}`),
        uploadedAs: it.name, storedName: up.storedName, galaxyFixture: it.src ?? null,
        source: it.src ? `galaxy/datatypes/test/${it.src}` : "inline/derived", folder: it.folder ?? null,
        expect: it.expect, expected: EXPECTATIONS.items[it.key] ?? null, fileId: up.id, settled: isSettled, settleMs: Date.now() - t0,
        checks, ...snap, pageErrors: [...pageErrors],
      });
      save();
    }

    // ── Folders: what the tree shows, then each folder opened as one object ──
    for (const folder of ["pairs", "tenx"]) {
      const members = ITEMS.filter((i) => i.folder === folder);
      await revealFile(page, uploaded[members[0].key].id, folder);   // tree state is explicit, not assumed
      const row = page.getByTestId(`folder-inputs/${folder}`);
      const rec: any = { folderRowVisible: await row.isVisible() };
      rec.files = [] as any[];
      for (const i of members) {
        rec.files.push({ name: i.relativePath, storedName: uploaded[i.key].storedName,
          rowVisible: await page.getByTestId(`file-open-${uploaded[i.key].id}`).isVisible() });
      }
      await row.scrollIntoViewIfNeeded();
      await page.getByTestId("project-file-tree").first().screenshot({ path: path.join(SHOTS, `folder-${folder}.png`) });
      // The row click opens the folder object (it also toggles the folder; nothing after depends on that).
      await row.click({ timeout: 15_000 });
      const view = page.getByTestId("folder-profile");
      // A folder view that never opens is recorded (and asserted softly below), not a harness abort:
      // the matrix gate must still report every format.
      rec.viewShown = await expect(view).toHaveAttribute("data-path", folder, { timeout: 30_000 }).then(() => true, () => false);
      expect.soft(rec.viewShown, `clicking folder-inputs/${folder} opens the folder object (folder-profile[data-path=${folder}])`).toBe(true);
      if (rec.viewShown) {
        await expect(view).not.toHaveAttribute("data-kind", "", { timeout: 60_000 });
        rec.view = await page.evaluate(() => {
          const v = document.querySelector('[data-testid="folder-profile"]') as HTMLElement | null;
          const all = (sel: string) => Array.from(v?.querySelectorAll(sel) ?? []) as HTMLElement[];
          return v ? {
            kind: v.getAttribute("data-kind"),
            samples: all('[data-testid^="folder-sample-row-"]').map((r) => ({ testid: r.getAttribute("data-testid"), status: r.getAttribute("data-status") })),
            orphans: all('[data-testid^="folder-orphan-"]').map((e) => e.getAttribute("data-testid")),
            tenxDims: all('[data-testid="folder-tenx-dims"]').map((e) => e.innerText.trim()),
            findings: all('[data-testid="folder-finding"]').map((e) => ({ code: e.getAttribute("data-code"), level: e.getAttribute("data-level") })),
            hasDownload: !!v.querySelector('[data-testid="folder-samplesheet-download"]'),
          } : null;
        });
        await view.screenshot({ path: path.join(SHOTS, `folder-${folder}-view.png`) });
        if (folder === "pairs" && rec.view?.hasDownload) {
          const [dl] = await Promise.all([
            page.waitForEvent("download", { timeout: 30_000 }),
            page.getByTestId("folder-samplesheet-download").click(),
          ]);
          const p = await dl.path();
          rec.samplesheet = { filename: dl.suggestedFilename(), csv: p ? fs.readFileSync(p, "utf8") : null };
          // Orphans/singles go to their own single-end sheet (a paired sheet holds pairs only).
          const single = page.getByTestId("folder-samplesheet-single-download");
          if (await single.count()) {
            const [dl2] = await Promise.all([page.waitForEvent("download", { timeout: 30_000 }), single.click()]);
            const p2 = await dl2.path();
            rec.samplesheetSingle = { filename: dl2.suggestedFilename(), csv: p2 ? fs.readFileSync(p2, "utf8") : null };
          }
        }
      }
      out.folders[folder] = rec;
      save();
    }
    out.finishedAt = new Date().toISOString();
    save();

    // ── Harness integrity (hard) ──
    expect(out.items.length, "every item opened").toBe(ITEMS.length);

    // ── Folder-level facts (soft: every fact is reported) ──
    const pv = out.folders.pairs?.view;
    expect.soft(pv?.kind, "pairs/ is a FASTQ set").toBe("fastq_set");
    expect.soft(pv?.samples?.find((r: any) => r.testid === "folder-sample-row-S1")?.status, "S1 is paired").toBe("paired");
    expect.soft(pv?.samples?.find((r: any) => r.testid === "folder-sample-row-S2")?.status, "S2 is an orphan").toBe("orphan");
    expect.soft(pv?.orphans ?? [], "S2_R1 flagged as orphan").toContain("folder-orphan-S2_R1.fastq.gz");
    const sheet = String(out.folders.pairs?.samplesheet?.csv ?? "").trim().split("\n");
    expect.soft(sheet[0], "samplesheet header").toBe("sample,fastq_1,fastq_2");
    expect.soft(sheet.length - 1, "paired samplesheet holds pairs only (S1)").toBe(1);
    const single = String(out.folders.pairs?.samplesheetSingle?.csv ?? "").trim().split("\n");
    expect.soft(single.slice(1).some((l) => l.startsWith("S2,pairs/S2_R1.fastq.gz")), "orphan S2 is in the single-end samplesheet").toBe(true);
    expect.soft(sheet[1]).toBe("S1,pairs/S1_R1.fastq.gz,pairs/S1_R2.fastq.gz");
    const tv = out.folders.tenx?.view;
    expect.soft(tv?.kind, "tenx/ is a 10x matrix").toBe("tenx_matrix");
    expect.soft(tv?.tenxDims?.[0] ?? "", "cells × genes shown").toMatch(/5\D+5/);
    expect.soft((tv?.findings ?? []).map((f: any) => f.code)).toContain("folder_tenx_headerless");

    // ── Per-file consequences of the folder context (soft; codes + data values only) ──
    const item = (k: string) => out.items.find((r: any) => r.key === k);
    expect.soft(String(item("pairs-S1_R1")?.qc?.text ?? ""), "S1_R1's QC names its mate file").toContain("S1_R2.fastq.gz");
    expect.soft(item("pairs-S1_R1")?.qc?.codes ?? [], "S1_R1 is not treated as a lone single file").not.toContain("fastq_single_file");
    expect.soft(item("pairs-S2_R1")?.qc?.codes ?? [], "S2_R1: mate missing (perception-why-item / perception-finding data-code)").toContain("fastq_mate_missing");

    // ── The gate: every format meets its expectation ──
    const notPass = out.items.filter((r: any) => r.verdict !== "PASS").map((r: any) => `${r.key}=${r.verdict} [${r.failed.join("; ")}]`);
    console.log(`FORMAT MATRIX | ${JSON.stringify(out.summary)}`);
    expect(notPass, `format matrix ${JSON.stringify(out.summary)}`).toEqual([]);
  } finally {
    await deleteProjectLoudly(api, projectId);
  }
});
