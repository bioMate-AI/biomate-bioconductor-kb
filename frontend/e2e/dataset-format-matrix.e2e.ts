/**
 * E2E (dev, live, no mocks): dataset-panel FORMAT MATRIX — a measurement, not a pass/fail gate.
 *
 * For every common bioinformatics format (real fixtures from Galaxy's own datatype tests, plus a
 * few small files written inline and two folder uploads) this harness uploads the file into ONE
 * project, opens it in the Files view (data hub), waits (bounded) for the panel to settle and
 * records what is actually on screen:
 *   - the preview kind shown (rows table + column names / rich viewer / text / image / density /
 *     "no preview" / error), the testids + elements present in the Preview area, a text snippet;
 *   - the QC card: quality chip + finding texts (or the QC card's own empty/error state);
 *   - visible errors (role=alert / destructive text) and page errors;
 *   - a screenshot e2e/screenshots/format-matrix/<name>.png.
 * For folders it also records what the file tree shows (folder row, file rows, counts).
 *
 * Results → e2e/format-matrix-results.json (written after every item, so a partial run keeps
 * what it measured). Per-format verdicts (PASS / PARTIAL / FAIL) are assigned in the report
 * docs/<date>_DATASET_FORMAT_MATRIX.md after reviewing the screenshots — the harness only asserts
 * that the harness itself worked (login, project, uploads, every file opened in the UI).
 *
 * Rules honoured (CLAUDE.md): fixture account, ONE login, ONE project deleted in finally, never
 * register, no response stubbing. The only page.route strips the harness's own Authorization /
 * x-e2e-test-token headers from requests to amazonaws.com (a presigned S3 URL rejects a second
 * auth mechanism) — same as run-code-outputs.e2e.ts.
 *
 * Content-hash dedup: uploads with identical bytes link to one entry (project-routes.ts), so the
 * folder copies are made byte-distinct (read headers renamed; an extra MatrixMarket comment line).
 *
 * Run: cd frontend && E2E_FIXTURE_PASSWORD="$(cat ~/.config/biomate/e2e_fixture_password)" \
 *      BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/dataset-format-matrix.e2e.ts \
 *      --project=chromium --reporter=line --retries=0
 */
import { test, expect, type Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import * as zlib from "zlib";
import { fileURLToPath } from "url";
import { BASE_URL, E2E_TOKEN } from "./_fixture-login";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const GALAXY_TEST = process.env.GALAXY_DATATYPE_TEST_DIR || "/Users/kky/biomate-review/backend/lib/galaxy/datatypes/test";
const SHOTS = path.join(HERE, "screenshots", "format-matrix");
const RESULTS = path.join(HERE, "format-matrix-results.json");
const SETTLE_MS = 75_000;

test.use({ deviceScaleFactor: 1 });

type Item = {
  key: string;            // screenshot / result key
  name: string;           // uploaded file name (basename)
  relativePath?: string;  // folder upload: "pairs/S1_R1.fastq.gz"
  folder?: string;        // folder group
  src?: string;           // Galaxy fixture basename
  bytes?: () => Buffer;   // inline / derived content
  expect: string;         // what an ideal dataset panel shows for this format
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

/** Snapshot of the open dataset object: preview kind, QC card, errors. Pure DOM read. */
async function snapshot(page: Page) {
  return page.evaluate(() => {
    const obj = document.querySelector('[data-testid="dataset-object"]') as HTMLElement | null;
    const q = (sel: string, root: ParentNode = document) => root.querySelector(sel) as HTMLElement | null;
    const txt = (el: Element | null, n = 600) => ((el as HTMLElement | null)?.innerText || "").replace(/\s+\n/g, "\n").trim().slice(0, n);
    const prev = obj ? q('[data-testid="dataset-preview"]', obj) : null;
    const qc = obj ? q('[data-testid="dataset-quality"]', obj) : null;
    // The Preview area minus the QC card + stat grid (they live inside dataset-preview).
    const testids = prev ? Array.from(prev.querySelectorAll("[data-testid]"))
      .filter((e) => !qc?.contains(e) && !e.closest('[data-testid="dataset-stat-grid"]'))
      .map((e) => e.getAttribute("data-testid")!).filter((v, i, a) => a.indexOf(v) === i) : [];
    const inPrev = (sel: string) => prev ? Array.from(prev.querySelectorAll(sel)).filter((e) => !qc?.contains(e) && !e.closest('[data-testid="dataset-stat-grid"]')) : [];
    const rowsTable = prev ? q('[data-testid="dataset-preview-table"]', prev) : null;
    const columns = rowsTable ? Array.from(rowsTable.querySelectorAll("thead th")).map((th) => (th as HTMLElement).innerText.trim()).filter(Boolean) : [];
    const rowCount = rowsTable ? rowsTable.querySelectorAll("tbody tr").length : 0;
    const textPrev = prev ? q('[data-testid="dataset-text-preview"]', prev) : null;
    const otherTables = inPrev("table").filter((t) => !rowsTable?.contains(t));
    const otherCols = otherTables[0] ? Array.from(otherTables[0].querySelectorAll("thead th, tr:first-child th")).map((th) => (th as HTMLElement).innerText.trim()).filter(Boolean).slice(0, 20) : [];
    let kind = "unknown";
    if (!obj) kind = "no-dataset-object";
    else if (rowsTable) kind = "rows-table";
    else if (q('[data-testid="density-map-viewer"]', prev!)) kind = "density";
    else if (q('[data-testid="inline-structure-viewer"]', prev!)) kind = "structure-3d";
    else if (inPrev("img").length) kind = "image";
    else if (inPrev("iframe").length) kind = "iframe";
    else if (q('[data-testid="dataset-json-tree"], [data-testid="json-preview"]', prev!)) kind = "json-tree";
    else if (textPrev && otherTables.length) kind = "rich-table-viewer";
    else if (textPrev && inPrev("pre, code").length) kind = "text";
    else if (textPrev) kind = "text-other";
    else if (q('[data-testid="dataset-preview-none"]', prev!)) kind = "no-preview";
    else if (q('[data-testid="dataset-rows-error"]', prev!)) kind = "rows-error";
    else if (q('[data-testid="dataset-preview-loading"]', prev!)) kind = "still-loading";
    else if (inPrev("canvas").length) kind = "canvas";
    else if (inPrev('[role="alert"]').length) kind = "preview-error";
    else kind = "message";
    // Preview text without QC / stat grid.
    let previewText = "";
    if (prev) {
      const clone = prev.cloneNode(true) as HTMLElement;
      clone.querySelectorAll('[data-testid="dataset-quality"], [data-testid="dataset-stat-grid"]').forEach((e) => e.remove());
      document.body.appendChild(clone); clone.style.position = "absolute"; clone.style.left = "-99999px";
      previewText = txt(clone, 700); clone.remove();
    }
    const perception = qc ? q('[data-testid="data-perception"]', qc) : null;
    const stat = obj ? q('[data-testid="dataset-stat-grid"]', obj) : null;
    const errors = obj ? Array.from(obj.querySelectorAll('[role="alert"], .text-destructive')).map((e) => (e as HTMLElement).innerText.trim()).filter(Boolean) : [];
    return {
      kind,
      previewTestids: testids,
      elements: { tables: otherTables.length, pre: inPrev("pre").length, canvas: inPrev("canvas").length, img: inPrev("img").length, iframe: inPrev("iframe").length },
      columns, rowCount, otherTableColumns: otherCols,
      previewText,
      header: { name: txt(obj ? q('[data-testid="dataset-object-name"]', obj) : null, 200), quality: txt(obj ? q('[data-testid="dataset-header-quality"]', obj) : null, 60) },
      qc: {
        state: !qc ? "absent" : perception ? "perception" : q('[data-testid="dataset-quality-loading"]', qc) ? "loading"
          : q('[data-testid="dataset-quality-error"]', qc) ? "error" : q('[data-testid="dataset-quality-noref"]', qc) ? "noref" : "other",
        quality: perception?.getAttribute("data-quality") || null,
        chip: txt(qc ? q('[data-testid="perception-quality-badge"]', qc) : null, 60),
        findings: qc ? Array.from(qc.querySelectorAll('[data-testid="perception-why-item"]')).map((e) => ({ code: e.getAttribute("data-code"), text: (e as HTMLElement).innerText.trim() })) : [],
        text: txt(qc, 900),
      },
      stats: txt(stat, 300),
      errors,
    };
  });
}

async function settled(page: Page) {
  return page.evaluate(() => {
    const obj = document.querySelector('[data-testid="dataset-object"]');
    if (!obj) return false;
    if (obj.querySelector('[data-testid="dataset-preview-loading"], [data-testid="dataset-quality-loading"], [data-testid="dataset-preview-columns-loading"]')) return false;
    const prev = obj.querySelector('[data-testid="dataset-preview"]');
    // DatasetFilePreview's own loading line ("Loading preview…" / density loading) is role=status.
    const busy = prev ? Array.from(prev.querySelectorAll('[role="status"]')).some((e) => /load|加载|…/i.test((e as HTMLElement).innerText)) : false;
    return !busy;
  });
}

test("dataset format matrix (measurement): upload → open → preview kind + QC per format", async ({ page, request }) => {
  test.setTimeout(60 * 60 * 1000);
  const pw = process.env.E2E_FIXTURE_PASSWORD;
  test.skip(!pw || !fs.existsSync(GALAXY_TEST), "needs E2E_FIXTURE_PASSWORD and the Galaxy datatype test fixtures");
  fs.mkdirSync(SHOTS, { recursive: true });

  const buildInfo = await request.get(`${BASE_URL}/build-info.json`).then((r) => r.json()).catch(() => ({}));
  const H = { "x-e2e-test-token": E2E_TOKEN };
  // ONE login for the whole harness: the token drives both the API calls and the browser session.
  const login = await request.post(`${BASE_URL}/api/auth/login`, { headers: H, data: { email: "lifeifei163361@163.com", password: pw } });
  expect(login.ok(), `login ${login.status()}`).toBeTruthy();
  const token = (await login.json()).token as string;
  expect(token, "login token").toBeTruthy();
  const auth = { ...H, Authorization: `Bearer ${token}` };
  const pr = await request.post(`${BASE_URL}/api/projects`, { headers: auth, data: { name: `e2e format matrix ${new Date().toISOString().slice(0, 16)}` } });
  expect(pr.ok(), `create project ${pr.status()}`).toBeTruthy();
  const pj = await pr.json(); const projectId = pj.id || pj.project?.id;
  expect(projectId, "project id").toBeTruthy();

  const out: any = { baseUrl: BASE_URL, buildInfo, startedAt: new Date().toISOString(), projectId, items: [] as any[], folders: {} as any };
  const save = () => fs.writeFileSync(RESULTS, JSON.stringify(out, null, 2) + "\n");
  const pageErrors: string[] = [];
  page.on("pageerror", (e) => pageErrors.push(String(e?.message || e).slice(0, 300)));

  try {
    // ── Uploads (multipart; relativePath BEFORE the file part keeps folders) ──
    const uploaded: Record<string, { id: string; storedName: string; status: number; dedup?: boolean }> = {};
    const uploadAttempts: Record<string, number[]> = {};
    out.uploadAttempts = uploadAttempts;
    for (const it of ITEMS) {
      const buf = it.src ? fx(it.src) : it.bytes!();
      const multipart: any = {};
      if (it.relativePath) multipart.relativePath = it.relativePath;
      multipart.file = { name: it.name, mimeType: mimeOf(it.name), buffer: buf };
      // A bare gateway 5xx (502/503/504, empty body) is a client↔EC2 blip (dev has no retry layer;
      // reproduced in isolation the same upload returns 201) — retry it, and record the attempts.
      let up = await request.post(`${BASE_URL}/api/projects/${projectId}/files/upload`, { headers: auth, multipart, timeout: 120_000 });
      const attempts: number[] = [up.status()];
      while ([502, 503, 504].includes(up.status()) && attempts.length < 3) {
        await page.waitForTimeout(3000);
        up = await request.post(`${BASE_URL}/api/projects/${projectId}/files/upload`, { headers: auth, multipart, timeout: 120_000 });
        attempts.push(up.status());
      }
      uploadAttempts[it.key] = attempts;
      const body = await up.json().catch(() => ({}));
      expect(up.ok(), `upload ${it.name} ${up.status()} ${JSON.stringify(body).slice(0, 200)}`).toBeTruthy();
      uploaded[it.key] = { id: body.file.id, storedName: body.file.name, status: up.status(), dedup: !!body.deduplicated };
      expect(body.deduplicated, `${it.name} must be byte-distinct (dedup would hide it)`).toBeFalsy();
    }

    // ── Browser session from the same token (no second login) ──
    const u = new URL(BASE_URL);
    await page.context().addCookies([{ name: "biomate_token", value: token, domain: u.hostname, path: "/", httpOnly: false, secure: false, sameSite: "Lax" }]);
    await page.context().setExtraHTTPHeaders({ Authorization: `Bearer ${token}`, "X-E2E-Test-Token": E2E_TOKEN, "X-Forwarded-Proto": "https" });
    // Presigned S3 URLs reject a second auth mechanism: strip OUR headers only (no response stubbing).
    await page.route(/amazonaws\.com/, async (route) => {
      const h = { ...route.request().headers() };
      delete h["authorization"]; delete h["Authorization"]; delete h["x-e2e-test-token"]; delete h["X-E2E-Test-Token"];
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
    await page.getByTestId("project-file-tree").first().waitFor({ state: "visible", timeout: 60_000 });

    const ensureVisible = async (fileId: string, folder?: string) => {
      const open = page.getByTestId(`file-open-${fileId}`);
      const vis = (l: any) => l.isVisible().catch(() => false);
      for (let attempt = 0; attempt < 3 && !(await vis(open)); attempt++) {
        // Folder rows are toggles: click one only when what it hides is not visible.
        const anyChildShown = await page.locator('[data-testid^="file-open-"], [data-testid^="folder-inputs/"]').first().isVisible().catch(() => false);
        if (!anyChildShown && (await vis(page.getByTestId("folder-inputs")))) await page.getByTestId("folder-inputs").click();
        else if (folder && (await vis(page.getByTestId(`folder-inputs/${folder}`)))) await page.getByTestId(`folder-inputs/${folder}`).click();
        else await page.getByTestId("project-files-refresh-btn").click().catch(() => {});
        await open.waitFor({ state: "visible", timeout: 8_000 }).catch(() => {});
      }
      return open;
    };

    for (const it of ITEMS) {
      const up = uploaded[it.key];
      const t0 = Date.now();
      pageErrors.length = 0;
      const open = await ensureVisible(up.id, it.folder);
      await open.click({ timeout: 30_000 });
      // The right file is shown (name contains the basename).
      await expect(page.getByTestId("dataset-object-name")).toContainText(it.name, { timeout: 30_000 });
      const tab = page.getByTestId("dataset-tab-preview");
      if (await tab.isVisible().catch(() => false)) await tab.click().catch(() => {});
      let isSettled = false;
      while (Date.now() - t0 < SETTLE_MS) {
        if (await settled(page)) { isSettled = true; break; }
        await page.waitForTimeout(1000);
      }
      await page.waitForTimeout(isSettled ? 2500 : 0);   // let a rich viewer paint (3D / density / table)
      const snap = await snapshot(page);
      await page.screenshot({ path: path.join(SHOTS, `${it.key}.png`) });
      // Also capture the QC card in view (it sits under the preview and may be below the fold).
      const qcLoc = page.getByTestId("dataset-quality");
      if (await qcLoc.isVisible().catch(() => false)) {
        await qcLoc.scrollIntoViewIfNeeded().catch(() => {});
        await qcLoc.screenshot({ path: path.join(SHOTS, `${it.key}.qc.png`) }).catch(() => {});
      }
      out.items.push({
        key: it.key, uploadedAs: it.name, storedName: up.storedName, galaxyFixture: it.src ?? null,
        source: it.src ? `galaxy/datatypes/test/${it.src}` : "inline/derived", folder: it.folder ?? null,
        expect: it.expect, fileId: up.id, settled: isSettled, settleMs: Date.now() - t0,
        ...snap, pageErrors: [...pageErrors],
      });
      save();
    }

    // ── Folders: what the tree shows ──
    for (const folder of ["pairs", "tenx"]) {
      const row = page.getByTestId(`folder-inputs/${folder}`);
      const rec: any = { folderRowVisible: await row.isVisible().catch(() => false) };
      rec.folderRowText = rec.folderRowVisible ? (await row.innerText()).trim() : null;
      // Subtree: the folder row's parent block (row + its children).
      rec.treeText = await page.evaluate((f) => {
        const r = document.querySelector(`[data-testid="folder-inputs/${f}"]`) as HTMLElement | null;
        const block = r?.parentElement;
        return block ? block.innerText.trim().slice(0, 1500) : null;
      }, folder);
      rec.files = ITEMS.filter((i) => i.folder === folder).map((i) => ({ name: i.relativePath, storedName: uploaded[i.key].storedName,
        rowVisible: false as boolean }));
      for (const f of rec.files) {
        const it = ITEMS.find((i) => i.relativePath === f.name)!;
        f.rowVisible = await page.getByTestId(`file-open-${uploaded[it.key].id}`).isVisible().catch(() => false);
      }
      if (rec.folderRowVisible) {
        await row.scrollIntoViewIfNeeded().catch(() => {});
        const box = await page.getByTestId("project-file-tree").first().boundingBox();
        await page.screenshot({ path: path.join(SHOTS, `folder-${folder}.png`), ...(box ? { clip: { x: box.x, y: Math.max(0, box.y), width: Math.max(1, box.width), height: Math.min(1080 - Math.max(0, box.y), Math.max(1, box.height)) } } : {}) }).catch(() => page.screenshot({ path: path.join(SHOTS, `folder-${folder}.png`) }));
      }
      out.folders[folder] = rec;
      save();
    }
    out.finishedAt = new Date().toISOString();
    save();

    // Harness-level assertions only (the per-format outcome is a measurement).
    expect(out.items.length, "every item opened").toBe(ITEMS.length);
    expect(out.items.filter((r: any) => r.kind === "no-dataset-object").map((r: any) => r.key), "dataset object rendered for every item").toEqual([]);
  } finally {
    // Cleanup must not be silent: a failed delete leaks the project on the shared fixture account.
    let del = await request.delete(`${BASE_URL}/api/projects/${projectId}`, { headers: auth }).catch(() => null);
    if (!del?.ok()) {
      await new Promise((r) => setTimeout(r, 5000));
      del = await request.delete(`${BASE_URL}/api/projects/${projectId}`, { headers: auth }).catch(() => null);
    }
    if (!del?.ok()) console.warn(`[format-matrix] project ${projectId} NOT deleted (status ${del?.status() ?? "network error"}) — delete it manually`);
  }
});
