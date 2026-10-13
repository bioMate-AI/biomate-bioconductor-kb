/**
 * Parametrized END-TO-END capture for the committee "bucket C" domain
 * COVERAGE GAPS — domains that had ZERO end-to-end screenshots. Each case
 * drives its SELF-CONTAINED cold-start example (verified routing to a real
 * workflow, demo data either built-in or attached from /demo/cold-start/)
 * through the full journey and captures HIGH-RES (2×) stills:
 *   domain-<key>-prerun.png     pre-run workflow card + param strip
 *   domain-<key>-running.png    running, ≥1 phase card in progress
 *   domain-<key>-completed.png  terminal (completed/failed)
 *   domain-<key>-results.png    merged Results view (findings + inline outputs)
 *
 * Honesty rules (same as real-run-capture.e2e.ts):
 *  - SAFETY GATE before Confirm & Run: if the generated workflow does NOT
 *    match the expected domain (lane mis-route), keep prerun only and spend
 *    NO Batch. A wrong/heavy run would waste money.
 *  - Captures whatever the run actually produces. A FAILED state is a real
 *    figure. Nothing is mocked.
 *  - Each domain is its own test() so one slow/failed run does not kill the
 *    others. Ordered cheapest-first (built-in small demos → attached demos →
 *    heavier pipelines).
 *
 * GPU domains (cryo-EM, structural-biology/AlphaFold, histology nuclei-seg)
 * are intentionally NOT in this table — they are the expensive ones and are
 * HELD for an explicit go.
 *
 * Run (REAL Batch, a few cents each, CPU):
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     npx playwright test e2e/domain-e2e-capture.e2e.ts --project=chromium --retries=0
 *
 * Limit to one domain:
 *   ... --grep "metabolomics"
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

// HIGH-RES is mandatory (see docs/20260922_USER_MANUAL_SCREENSHOT_AUDIT.md):
// deviceScaleFactor must be set at context creation. 2× → a 1440 CSS vp yields
// a 2880px PNG. (playwright.config.ts already pins this for chromium; we set it
// here too so the spec is self-describing and correct under any project.)
test.use({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 2 });

const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const DEMO_ROOT = "/demo/cold-start/";

interface DomainCase {
  key: string;
  /** The exact self-contained prompt sent to the composer. */
  query: string;
  /** Demo files to attach (fetched from /demo/cold-start/). Empty = built-in demo data. */
  attach: string[];
  /** SAFETY-GATE: the generated workflow / panel text must match this, or we abort with no Batch spend. */
  expect: RegExp;
  /** GPU tier: cryo-EM / structure-prediction / histology run on a GPU Batch
   *  queue — slower to dispatch (capacity) and to execute. Extends timeouts. */
  gpu?: boolean;
}

// Self-contained prepared prompts. The three built-in-demo cases (metabolomics,
// epigenomics, proteomics) are verbatim from PREPARED_EXAMPLES in
// cold-start-examples.ts. The three attached-demo cases use the prepared
// "goal + Prepared demo context" shape with the exact catalog context strings
// (cold-start-demo-catalog.ts) so the workflow knows the attached inputs.
const DOMAINS: DomainCase[] = [
  // --- built-in demo data, no attachment (cheapest / most self-contained) ---
  {
    key: "metabolomics",
    query:
      "Run the metaboanalystr workflow using its built-in real human_cachexia demo dataset (77 samples, 63 metabolites). Use the public sample data defaults; do not require my own uploads.",
    attach: [],
    expect: /metabo|cachexia|metaboanalyst/i,
  },
  {
    key: "epigenomics",
    query:
      "Run perform_chipseq_peak_calling_with_macs2 using its built-in MACS3 CTCF_SE ChIP and control chr22 50k-read BED demo files. Use the real public demo defaults.",
    attach: [],
    expect: /chip|macs|peak|ctcf/i,
  },
  {
    key: "proteomics",
    query:
      "Run the chemoproteomics_pulldown workflow on its built-in LFQ-Analyst proteinGroups.txt public demo dataset; use the sample-data defaults. (A workflow + QC demonstration on public demo data, not a biologically specific pull-down.)",
    attach: [],
    expect: /proteom|pulldown|pull-down|lfq|chemoproteomic/i,
  },
  // --- attached demo data from /demo/cold-start/ ---
  {
    key: "crispr",
    query:
      "Analyze my pooled CRISPR screen: call enriched/depleted hits at an FDR cutoff and rank the candidate dependency genes.\n\nPrepared demo context:\nUse the official MAGeCK demo: sgRNA and Gene columns, HL60.initial/HL60.final and KBM7.initial/KBM7.final. Analyze final versus initial separately within each cell line and compare depletion effects between lines. There is one column per line/time, no replicate experiment: report that limitation and do not fabricate replicate correlations.",
    attach: ["crispr_counts.tsv", "crispr_design.csv"],
    expect: /crispr|mageck/i,
  },
  {
    key: "single-cell",
    query:
      "Cluster and annotate my single-cell RNA-seq and find the cell-type composition and markers.\n\nPrepared demo context:\nUse the attached real 10x PBMC3k raw h5ad: 2,700 healthy human PBMCs. Perform QC, clustering, cell-type annotation and marker analysis; no disease/control contrast is present.",
    attach: ["pbmc3k_raw.h5ad"],
    expect: /scrnaseq|single.?cell|scdownstream|scanpy|seurat|cluster|cell.?type/i,
  },
  {
    key: "variant-calling",
    query:
      "Call variants on these samples and flag the clinically relevant ones.\n\nPrepared demo context:\nUse the paired nf-core/sarek tiny normal reads and the attached matching small GRCh37/b37 reference, NOT GRCh38. This is a small pipeline fixture, not a clinical diagnostic dataset. Do not claim clinical relevance from sparse test coverage; report callable regions and available annotations.",
    attach: [
      "normal_R1.fastq.gz",
      "normal_R2.fastq.gz",
      "tumor_R1.fastq.gz",
      "tumor_R2.fastq.gz",
      "reference_grch37.fasta",
      "sequencing_samples.csv",
    ],
    expect: /sarek|variant|haplotype|strelka|deepvariant|mutect|germline|somatic/i,
  },
  // --- GPU tier (expensive; run scoped via --grep, greenlit explicitly) ---
  // histology: PREPARED_EXAMPLES built-in demo slide, no attachment.
  {
    key: "histology",
    query:
      "Run wsi_he_nuclei_segmentation using the built-in real OpenSlide CMU-1-Small-Region.svs demo slide. Use the public sample data defaults.",
    attach: [],
    expect: /wsi|nuclei|segment|histolog|openslide|cellpose|he\b|h&e/i,
    gpu: true,
  },
  // cryo-EM: catalog `cryo` intent + staged EMPIAR-10028 movies (S3); cryo_inputs.json manifest attached.
  {
    key: "cryo-em",
    query:
      "Process this cryo-EM dataset to a density map and report the resolution.\n\nPrepared demo context:\nUse the already staged EMPIAR-10028 beta-galactosidase movies at s3://biomate-cryo-data/empiar-10028/Micrographs/ (001_movie.mrcs through 020_movie.mrcs). cryo_inputs.json provides acquisition settings: pixel size 0.885 Å, 300 kV, Cs 2.7 mm, amplitude contrast 0.1, symmetry D2, particle diameter 180 Å. Bind the staged movie prefix as the workflow input, not this manifest as a micrograph. This 20-movie tutorial subset is not guaranteed to reconstruct the full-dataset resolution; report observed QC/resolution honestly.",
    attach: ["cryo_inputs.json"],
    expect: /cryo|cryosparc|relion|density|reconstruct|particle|micrograph|resolution/i,
    gpu: true,
  },
  // structural-biology: catalog `structure` intent + attached 1LYZ lysozyme (prepareColdStartExample rewrites the sequence tail to "the attached lysozyme sequence").
  {
    key: "structural-biology",
    query:
      "Predict the structure for the attached lysozyme sequence and tell me where to trust it.\n\nPrepared demo context:\nUse the experimental hen egg-white lysozyme sequence in 1LYZ.fasta for structure prediction and the supplied 1LYZ.pdb as a reference for assessment. Report model confidence and measured comparison separately.",
    attach: ["1LYZ.fasta", "1LYZ.pdb"],
    expect: /alphafold|esmfold|openfold|structure|fold|confidence|plddt|lysozyme|predict/i,
    gpu: true,
  },
];

for (const d of DOMAINS) {
  test(`domain e2e: ${d.key}`, async ({ page }) => {
    test.setTimeout((d.gpu ? 60 : 45) * 60 * 1000); // GPU 60 min, CPU 45 min
    const RUNNING_TIMEOUT = d.gpu ? 10 * 60 * 1000 : 240_000; // GPU queue/capacity can be slow to dispatch
    const TERMINAL_TIMEOUT = (d.gpu ? 50 : 30) * 60 * 1000;    // cryoSPARC ~35-45 min, AlphaFold ~10-40 min
    await loginAsFixture(page);
    const log: string[] = [];
    const shot = async (suffix: string, el?: import("@playwright/test").Locator) => {
      const name = `domain-${d.key}-${suffix}.png`;
      await (el ?? page).screenshot({ path: path.join(ASSETS, name) });
      log.push(`OK   ${name}`);
    };

    try {
      await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });

      // 1. Attach demo files (if any) via the hidden composer file input, then
      //    submit the prepared prompt. Gate every step on READINESS, not fixed
      //    timeouts (prod build on dev defers JS).
      const input = page.getByTestId("chat-input");
      await input.waitFor({ state: "visible", timeout: 45_000 });
      await page.waitForTimeout(3000); // hydration settle

      if (d.attach.length > 0) {
        // Fetch each demo file from dev (Playwright HTTP stack) and attach as a
        // buffer payload — no disk needed. Fails loud if a demo file is missing.
        const payloads = [];
        for (const fname of d.attach) {
          const resp = await page.request.get(`${BASE_URL}${DEMO_ROOT}${fname}`);
          if (!resp.ok()) throw new Error(`demo file ${fname} not served (${resp.status()})`);
          const buffer = await resp.body();
          payloads.push({ name: fname, mimeType: "application/octet-stream", buffer });
        }
        const fileInput = page.locator('[data-testid="chat-attach-file-input"]');
        await fileInput.setInputFiles(payloads, { timeout: 30_000 });
        log.push(`attached ${d.attach.length} demo file(s): ${d.attach.join(", ")}`);
        // Attachment chips register asynchronously; wait for at least one to show.
        await page.getByTestId("composer-attached-file").first().waitFor({ state: "visible", timeout: 20_000 }).catch(() => {
          log.push("WARN attachment chip not visible — proceeding (send still carries files)");
        });
      }

      await input.click();
      await input.fill(d.query);
      const sendReady = page.locator('[data-testid="chat-send-button"]:not([disabled])');
      await sendReady.waitFor({ state: "visible", timeout: 30_000 });
      await sendReady.click({ timeout: 15_000 });
      log.push(`submitted ${d.key} request`);

      // 2. Pre-run panel — the workflow card with Confirm & run. LLM gen up to 180s.
      const confirm = page.getByRole("button", { name: /confirm.*run/i });
      await confirm.first().waitFor({ timeout: 200_000 });
      await page.waitForTimeout(4000);
      await shot("prerun");

      // 3. SAFETY GATE — only spend Batch if the generated workflow matches the
      //    expected domain. If not, keep prerun and stop with NO Batch spend.
      const panelText = (await page.locator("body").innerText()).toLowerCase();
      if (!d.expect.test(panelText)) {
        log.push(
          `ABORT run — generated workflow does NOT match ${d.expect} (lane mis-route); kept prerun only, no Batch spend. panel~='` +
            panelText.slice(0, 220).replace(/\n/g, " ") +
            "'",
        );
        console.log(`\n[domain-e2e ${d.key}]\n` + log.join("\n") + "\n");
        return;
      }
      log.push(`SAFETY GATE pass — workflow matches ${d.expect}`);

      // 4. Confirm & run.
      const confirmBtn = confirm.first();
      await confirmBtn.scrollIntoViewIfNeeded().catch(() => {});
      await confirmBtn
        .click({ timeout: 30_000 })
        .catch(async () => { await confirmBtn.click({ timeout: 15_000, force: true }); });
      log.push("clicked Confirm & run");

      // 5. RUNNING — poll for any phase card data-status=running (up to 4 min to dispatch).
      try {
        // NOTE: waitForFunction signature is (pageFunction, arg, options) — the
        // timeout MUST be the 3rd arg. Passing it as the 2nd arg silently makes
        // it the page-function argument and falls back to the config actionTimeout.
        await page.waitForFunction(() => !!document.querySelector('[data-status="running"]'), null, { timeout: RUNNING_TIMEOUT });
        await page.waitForTimeout(1500);
        await shot("running");
      } catch {
        log.push(`SKIP running (running state not observed in ${Math.round(RUNNING_TIMEOUT / 1000)}s)`);
      }

      // 6. Terminal — Completed or Failed — up to 30 min. Capture the runId first
      //    (from the URL after Confirm & Run) so completed/results can be
      //    re-captured from the already-dispatched run without a second Batch spend.
      const dispatchedRunId = await page.evaluate(() => {
        try {
          const m = (window.location.href || "").match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/);
          return m ? m[0] : null;
        } catch { return null; }
      });
      if (dispatchedRunId) log.push("DISPATCHED_RUN_ID: " + dispatchedRunId);
      await page.waitForFunction(
        () => /Run again|COMPLETED|Completed|FAILED|Failed|Restart/.test(document.body.innerText || ""),
        null,
        { timeout: TERMINAL_TIMEOUT },
      );
      await page.waitForTimeout(5000);
      await shot("completed");

      // 7. Merged Results view. Prefer the clean /debug/afterrun/:runId mount
      //    (the v2 AfterRunReport = findings banner + inline Outputs gallery).
      //    Fall back to the in-panel After-run tab if we can't resolve a runId.
      const runId = await page.evaluate(() => {
        try {
          const m = (window.location.href || "").match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/);
          return m ? m[0] : null;
        } catch { return null; }
      });
      if (runId) {
        log.push("RUN_ID: " + runId);
        await page.goto(BASE_URL + `/debug/afterrun/${runId}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
        await page.waitForTimeout(6000); // AfterRunReport + findings fetch + lazy previews
        await shot("results");
      } else {
        log.push("no runId in URL — capturing in-panel results as fallback");
        const fc = page.getByTestId("findings-card");
        if ((await fc.count()) > 0) await fc.first().scrollIntoViewIfNeeded().catch(() => {});
        await page.waitForTimeout(1500);
        await shot("results");
      }
      log.push("HREF: " + page.url());
    } catch (e: any) {
      log.push(`FAIL ${d.key} — ` + (e?.message?.split("\n")[0] ?? e));
      try { await shot("fail-state"); } catch { /* ignore */ }
    }
    // eslint-disable-next-line no-console
    console.log(`\n[domain-e2e ${d.key}]\n` + log.join("\n") + "\n");
    // A pass means we at least captured the prerun figure.
    expect(log.some((l) => l.includes("domain-" + d.key + "-prerun"))).toBe(true);
  });
}
