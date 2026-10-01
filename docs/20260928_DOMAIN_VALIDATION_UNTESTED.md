# Domain Validation — Untested Domains (ChIP-seq, Single-cell, Spatial)

**Date:** 2026-09-28
**Author:** Yaoyun Zhang
**Companion to:** `docs/20260923_DOMAIN_VALIDATION_PLAN.md`, `docs/20260923_DOMAIN_VALIDATION_RESULTS.md`
**Scope:** advance real end-to-end AWS Batch validation for the three domains flagged with
no run evidence in `project_workflow_validation_gaps` — **epigenomics/ChIP-seq, single-cell,
spatial** — measured, read-only survey + at most 2 cheap production-path runs.

## Headline

- ✅ **ChIP-seq is now VALIDATED end-to-end on production AWS Batch.** A real ChIPseeker peak-
  annotation run **SUCCEEDED** (both Batch tasks exit 0) on the `biomate-nextflow-queue`,
  producing correct hg19 genomic annotations (GAPDH/ACTB/MYC promoters, etc.) — the first real
  ChIP-seq output artifacts ever on S3. Run id `e48ec367-7c61-4689-9986-cc7a2702113e`.
- ⚠️→✅ **Single-cell dropletutils: the libz container blocker is FIXED and the science is
  VALIDATED on production AWS Batch.** (Update 2026-09-28, follow-up session.) Two root causes
  were found and fixed; the DropletUtils `emptyDrops` analysis ran correctly on the real RAW
  PBMC3k matrix.
  1. **Container blocker (FIXED + deployed):** swapped `dropletutils/main.nf`'s `container` from
     the raw `quay.io/biocontainers/bioconductor-dropletutils` (missing `libz.so.1`) to the
     Batch-ready `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim`
     — the exact image its siblings (scran/scater/scuttle) use. DropletUtils is in that image's
     deps manifest (`deps/transcriptomics.txt:62`) and the registry files dropletutils under the
     `transcriptomics` domain. **Proof it works:** the re-run (Batch job `49fc7307`) used the new
     image, S3 staging succeeded (no libz error), and DropletUtils loaded + ran.
  2. **Data-appropriateness (FIXED by staging RAW matrix):** the first re-run used the *filtered*
     PBMC3k matrix (32738 × **2700 cells**, already cell-called), so `emptyDrops` correctly errored
     "no counts available to estimate the ambient profile" — emptyDrops REQUIRES the unfiltered
     matrix. Staged the RAW 10X PBMC3k matrix (32738 × **737280 barcodes**) to
     `s3://biomate-test-data/team-curated/single_cell/pbmc3k_10x_raw/`. On the raw matrix,
     **emptyDrops detected 2876 cell-containing droplets (FDR ≤ 0.01)** — biologically correct for
     PBMC3k (~2700-2900 cells). The R body wrote all outputs ("Pipeline completed successfully.
     Outputs saved: barcode_ranks_plot.pdf, barcode_ranks_stats.csv, empty_drops_results.csv,
     empty_drops_plot.pdf, filtered_cells_sce.rds").
  3. **versions.yml typo (FIXED, commit pending consolidated sync):** the task still exited 1 on
     the FINAL line: `packageVersion("dropletutils")` — lowercase; the installed Bioc package is
     CamelCase `DropletUtils`. Because the task exited non-zero, Nextflow never unstaged the
     already-computed outputs to S3 (so the S3 outputs dir is empty despite the analysis
     succeeding). Fixed to `packageVersion("DropletUtils")` (commit `6fb4b084e`). The next
     dispatch (after the consolidated dev sync ships this .nf) exits 0 and persists the real
     outputs. **The single-cell capability is proven; only a one-token version-string fix remains
     to be deployed for clean output persistence.**
  - **2-input wrapper finding (FIXED):** the `// Input: dir.name, my.counts` header made
    `_build_bioc_entry_wrapper` return `None` (→ 422) when only `dir.name` was supplied, because
    the placeholder fallback only fired for a single declared name. Relaxed the wrapper: for a
    single collect-all `path(input_files, stageAs:'?/*')` slot (`n_path<=1`), a subsequent
    unsupplied declared name after one already resolved is harmless (all files pool into the same
    list; the R body derives the optional `my.counts` from `counts(sce)`). Genuine multi-SLOT
    workflows (`n_path>1`) still bail so real missing inputs surface. Commit `9641ed6e2`,
    `nextflow_executor.py`.
- ✅ **Single-cell Bioconductor chain is now VALIDATED on production AWS Batch (2026-10-01).** Four
  of the five composable single-cell Bioc subworkflows **SUCCEEDED** (exit 0, real non-empty outputs)
  on `biomate-nextflow-queue` using image `bioc-domain-transcriptomics:3.20-slim`, staged from
  `s3://biomate-nextflow-work/singlecell_bioc_20261001/`:
  **scran** (quick clustering: 400 cells → 3 clusters 130/170/100 + 11 subclusters, `scran 1.34.0`),
  **scater** (QC + dimred: 18 plot PDFs incl. tSNE/UMAP/PCA + variance-explained CSVs),
  **scuttle** (feature QC: 7 artifacts emitted, QC gate `passes=true`),
  **scdblfinder** (doublet detection: 400 cells, 7 doublets / 393 singlets, `doublet_rate=0.0175`,
  gate `passes=true`, `scDblFinder 1.20.2`). The **sc3** workflow FAILED and was root-caused to a
  1-line omission (`library(SingleCellExperiment)` never attached — fix applied, commit pending; needs
  sync + re-run to confirm). See Run 3.
- ❌ **Spatial is BLOCKED (as the plan predicted):** the executable spatial workflow
  (`visium_voyager_spatial_esda`) references ECR image `biomate/bioc-spatial:v1` which
  **does not exist** (confirmed — no `spatial` repo in ECR at all), and the MERFISH alternative
  is an honest-failing stub (`sys.exit(1)`). No run dispatched.
- **`scrnaseq_standard_endtoend` stub verdict: BUILD-OR-REMOVE — recommend REMOVE/REPLACE** (see
  §Single-cell stub). Its bespoke image `biomate/scrnaseq-standard:v1` does not exist and its
  `/opt/biomate/scrnaseq/*.py|.R` scripts are unimplemented.
- **Total Batch spend: ~$0.12 (original session) + ~$0.06 (2026-09-28 follow-up: 2 short Batch
  jobs, ~90s each)** = **~$0.18**, well under cap. No EC2 launched.
- **Follow-up session did commit + sync:** container swap + wrapper fix committed (`9641ed6e2`) and
  synced to dev healthy; versions.yml fix committed (`6fb4b084e`) awaiting the consolidated sync.

---

## Readiness table (domain → workflow → READY / BLOCKED + reason)

| Domain | Workflow (`.nf`) | Container | Small data? | Verdict |
|---|---|---|---|---|
| **ChIP-seq** | `chipseeker/peak_annotation_and_feature_distribution.nf` | `biomate/bioc-domain-epigenomics:3.20-slim` (ECR, Batch-ready) | tiny hg19 BED (self-supplied) | **READY — RAN & SUCCEEDED** ✅ |
| ChIP-seq | `chipseeker/peak_annotation_and_enrichment.nf` | same | needs BED **+ txdb.rds** (2 inputs) | READY-ish; needs an RDS TxDb staged (fixture-built) — feature_distribution is cheaper |
| ChIP-seq | `chipseeker/main.nf` (`peak_profiling`) | quay biocontainer | needs BED + txdb.rds | BLOCKED on Batch — raw quay image (libz issue, see SC) |
| ChIP-seq | `nfcore/chipseq/main.nf` (DB id 1492) | — | — | **BLOCKED — non-executable stub** (invented tool flags `bwa mem --dedup`, `fastqc --whitelist`; 0 real outputs). Do not run. |
| **Single-cell** | `dropletutils/main.nf` (10X import/emptyDrops) | ~~quay biocontainer~~ → `biomate/bioc-domain-transcriptomics:3.20-slim` (ECR, Batch-ready) | 10X PBMC3k **RAW** (S3, ~40 MB) | **VALIDATED — emptyDrops detected 2876 cells (FDR≤0.01) on Batch.** libz blocker fixed (container swap `9641ed6e2`); only a versions.yml typo fix (`6fb4b084e`) remains to deploy for output persistence ✅ |
| Single-cell | `scran` / `scater` / `scuttle` / `scdblfinder` `/main.nf` | `biomate/bioc-domain-transcriptomics:3.20-slim` (Batch-ready) | SCE `.rds` input (staged) | **ALL 4 VALIDATED — RAN & SUCCEEDED on Batch (exit 0, real outputs)** ✅ (see Run 3) |
| Single-cell | `sc3/main.nf` | `bioc-domain-transcriptomics:3.20-slim` (Batch-ready) | `expression_matrix.csv` + `cell_metadata.csv` (staged) | **RAN & FAILED — root-caused** (missing `library(SingleCellExperiment)`; 1-line fix applied, awaits sync+re-run) ⚠️→🔧 (see Run 3) |
| Single-cell | `scrnaseq_standard_endtoend/main.nf` | `biomate/scrnaseq-standard:v1` **(does not exist)** | — | **BLOCKED — unimplemented stub** (see stub verdict) |
| **Spatial** | `visium_voyager_spatial_esda/main.nf` | `biomate/bioc-spatial:v1` **(does not exist)** | — | **BLOCKED — bespoke ECR image never built; bespoke `/opt/biomate/voyager/*.R` scripts unimplemented** |
| Spatial | `merfish_spatial_analysis/main.nf` | `biomate/biomni-tools:x86` (exists) | — | **BLOCKED — honest-failing stub** (`sys.exit(1)` "no real implementation"; needs Cellpose+SpatialDE wiring) |

`_candidate_bases` / logical-path note: dispatch the executor with the `nextflow_nfcore/...`
logical path (NOT `backend/biomni_workflows/...`) — the latter 404s at `_resolve_nextflow_path`.

---

## Run 1 — ChIP-seq (chipseeker) — ✅ SUCCEEDED

- **Workflow:** `nextflow_nfcore/subworkflows/bioconductor/chipseeker/peak_annotation_and_feature_distribution.nf`
- **Container:** `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim`
- **Input (self-staged, real):** a 12-peak hg19 BED at
  `s3://biomate-test-data/team-curated/epigenomics/chipseq_hg19_demo/peaks.bed`
  (genuine hg19 loci near GAPDH/ACTB/MYC/MALAT1/TP53 etc.). Supplied as
  `parameters={"files[[4]]": ["s3://…/peaks.bed"]}` — the list form makes the Bioc entry
  wrapper stage by **basename** (`peaks.bed`), which the R body's `list.files(pattern=".bed")`
  glob then finds.
- **Run id (BioMate):** `90ff9b28-b044-4db9-88c1-5b452ce60222`
- **Nextflow run id:** `e48ec367-7c61-4689-9986-cc7a2702113e`
- **Batch tasks:** `BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_FEATURE_DISTRIBUTION (sample)` —
  COMPLETED, exit 0, 4m7s, peak_rss 1.3 GB; `BIOMATE_RDS_INTROSPECT (1)` — COMPLETED, exit 0.
- **Terminal status:** `succeeded` (returncode 0). Wall-clock ~6 min head + tasks.
- **Real outputs in S3** (work dir
  `s3://…/nextflow/work/fd5a73ac…/e48ec367…/5e/8cb689762c5b4690e9e5a02d6082b4/`):
  - `peak_annotation_results.csv` (2.4 KB) — all 12 peaks annotated with feature +
    nearest gene: peak4→**GAPDH** Promoter (≤1kb), peak5→**ACTB** Promoter, peak12→**MYC**
    Promoter, peak6→**MALAT1**, peak2→PRKCZ intron, etc. Biologically correct.
  - `peak_annotation_granges.rds` (1.8 KB) — GRanges object
  - `genomic_annotation_plots.pdf` (12 KB) — plotAnnoPie/Bar/vennpie
  - `distribution_to_tss_plot.pdf` (5 KB) — plotDistToTSS
  - `versions.yml` — `ChIPseeker: 1.42.1`; `.exitcode` = 0
- **Note:** `TxDb.Hsapiens.UCSC.hg19.knownGene` + `org.Hs.eg.db` are NOT baked into
  `epigenomics:3.20-slim` (absent from `backend/scripts/domain_images/deps/epigenomics.txt`),
  but the workflow's runtime `.bm_deps` BiocManager fallback installed them successfully inside
  the 4m7s task. **Recommendation (non-blocking):** add those two annotation packages to
  `deps/epigenomics.txt` so future ChIP-seq runs skip the runtime install.

**This closes the ChIP-seq gap:** the prior `nf-core/chipseq` attempts (pipeline_info-only,
no peaks) are superseded by a real, scored ChIPseeker annotation with correct output.

---

## Run 2b — Single-cell (dropletutils) — ✅ CONTAINER FIXED + SCIENCE VALIDATED (2026-09-28 follow-up)

- **Fixes shipped this session:**
  - Container swap `dropletutils/main.nf`: `quay.io/biocontainers/bioconductor-dropletutils:1.30.0`
    → `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim`.
    Commit `9641ed6e2`. **Synced to dev healthy** (`result=healthy`) via `sync_to_dev.sh` at that
    commit BEFORE the parallel-agent coordination freeze — so the container fix is LIVE on dev.
  - Bioc entry-wrapper relaxed for single collect-all slot + multiple declared names (the
    `// Input: dir.name, my.counts` 422). Same commit `9641ed6e2`, `nextflow_executor.py`.
  - versions.yml `packageVersion("dropletutils")` → `packageVersion("DropletUtils")`. Commit
    `6fb4b084e` (pending the consolidated dev sync the main session will run).
- **Dispatch 1 (filtered matrix)** — BioMate run `ef3e9fed-8dae-4c78-a6a7-1d7c50aebd29`, Nextflow
  `258cdb0f`, Batch job `92a029e7`. Image = `bioc-domain-transcriptomics:3.20-slim` ✅ (libz gone,
  staging OK, DropletUtils loaded). FAILED inside R with `emptyDrops(...)`: "no counts available to
  estimate the ambient profile" — **correct guard**: PBMC3k `matrix.mtx` was the FILTERED matrix
  (32738 × 2700, already cell-called); emptyDrops needs the RAW/unfiltered matrix.
- **RAW matrix staged:** downloaded 10x public `pbmc3k_raw_gene_bc_matrices.tar.gz`, extracted the
  hg19 matrix (32738 genes × **737280 barcodes**), staged to
  `s3://biomate-test-data/team-curated/single_cell/pbmc3k_10x_raw/{matrix.mtx,barcodes.tsv,genes.tsv}`.
- **Dispatch 2 (RAW matrix)** — BioMate run `671f6f43-3267-47fa-8fa9-9cee2784f923`, Nextflow
  `649abdaa-653a-45a2-8f9e-49ed1bb12f53`, Batch job `49fc7307-be84-49ab-bd13-7cb6e67174f6`.
  Image `bioc-domain-transcriptomics:3.20-slim`. Staging of all 4 files SUCCEEDED (work dir
  `.../649abdaa.../stage-6d256f62.../` holds matrix.mtx 42 MB + barcodes.tsv 12 MB + genes.tsv +
  my.counts). **R analysis SUCCEEDED** (CloudWatch `99702376...`):
  - `barcodeRanks` computed + `barcode_ranks_plot.pdf` written (log warns 578390 zero-count
    barcodes omitted from log plot — expected for a 737K-barcode raw matrix).
  - `emptyDrops` → **"Number of detected cell-containing droplets (FDR <= 0.01): 2876"**
    (Limited/Significant table: 2837 significant+limited, 39 significant+unlimited) — biologically
    correct for PBMC3k.
  - "Pipeline completed successfully. Outputs saved: barcode_ranks_plot.pdf,
    barcode_ranks_stats.csv, empty_drops_results.csv, empty_drops_plot.pdf,
    filtered_cells_sce.rds".
  - Task then exited 1 on the LAST line only: `packageVersion("dropletutils")` (lowercase) →
    "there is no package called 'dropletutils'". Because exit≠0, Nextflow did **not** unstage the
    (already-written) outputs to S3 — the S3 outputs dir is empty. **Fixed** in commit `6fb4b084e`;
    once that .nf ships to dev, the next dispatch exits 0 and persists all 5 artifacts + qc_metrics.json
    + versions.yml.
- **Verdict:** single-cell dropletutils is **capability-VALIDATED on real data on production Batch**
  (correct emptyDrops cell count on the raw PBMC3k matrix); the libz infra blocker and the 422
  wrapper bug are fixed + deployed; a one-token version-string fix is committed and awaiting the
  consolidated sync for clean output persistence.

### Run 2c — post-sync re-dispatch (2026-09-29) — ✅ FULLY VALIDATED, clean exit 0 + all outputs persisted

After the consolidated sync deployed the versions.yml fix (`6fb4b084e`,
`packageVersion("DropletUtils")` CamelCase — verified live in the dev container), the
run `671f6f43` params were re-dispatched via the production path
`POST /api/workflows/execute` (e2e fixture `lifeifei163361@163.com`, raw PBMC3k matrix,
container `bioc-domain-transcriptomics:3.20-slim`).

| Field | Value |
|---|---|
| BioMate run id | `2093bd88-6412-4a05-8c06-dafdb57f524b` |
| Nextflow run id | `83212a9a-e814-481d-9056-158de8f3dc69` |
| Batch job id | `adfdc14b-48fc-430c-ad5d-ca7bfc4ab879` |
| Terminal status | **SUCCEEDED** (returncode 0), ~94 s task compute, ~506 s wall |
| S3 outdir | `s3://biomate-nextflow-work/nextflow/outputs/fd5a73ac-87df-4850-b8ff-6d768c1b47fb/2d0a469c/` |

**All 7 expected outputs persisted to S3 (non-empty, count-checked):**
`barcode_ranks_plot.pdf` (993 KB), `barcode_ranks_stats.csv` (16.6 MB),
`empty_drops_plot.pdf` (175 KB), `empty_drops_results.csv` (17 MB),
`filtered_cells_sce.rds` (5.5 MB), `qc_metrics.json` (519 B), `versions.yml`
(`dropletutils: 1.26.0`). **Science confirmed:** parsing `empty_drops_results.csv`
(FDR column) yields exactly **2876 cell-containing droplets at FDR ≤ 0.01** — matching
the prior in-container proof and biologically correct for PBMC3k. The versions.yml
CamelCase fix closed the last gap: the task now exits 0 and Nextflow unstages every
artifact. **Single-cell dropletutils is fully VALIDATED end-to-end on production AWS
Batch.** Batch spend: ~$0.03.

---

## Run 3 — Single-cell Bioconductor chain (scran / scater / scuttle / scdblfinder / sc3) — ✅ 4/5 VALIDATED on Batch (2026-10-01)

- **Queue:** `biomate-nextflow-queue`. **Image (all 5):**
  `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim`.
- **Staged inputs:** `s3://biomate-nextflow-work/singlecell_bioc_20261001/`
  (`example_sce.rds`, `sce.rds` for the four SCE-based tools; `expression_matrix.csv` +
  `cell_metadata.csv` for sc3). Nextflow head dir `fd5a73ac-87df-4850-b8ff-6d768c1b47fb`.
- **Verification method:** `aws batch describe-jobs` (status + exit code) + `aws s3 ls`/`cp` on each
  task work dir to confirm real, non-empty output artifacts and read actual result values. No re-runs
  of the 4 that already succeeded.

| Tool | Batch job id | Status | Real evidence (read from S3 outputs) |
|---|---|---|---|
| **scran** (quick clustering & normalization) | `a4ef9c54-f795-4ede-b4c2-40764d89a00c` | ✅ SUCCEEDED (exit 0) | `quick_clusters.csv`: **400 cells → 3 clusters (cluster1=130, cluster2=170, cluster3=100)**; `subcluster_table.csv`: 11 subclusters (e.g. 1.1=52, 2.1=60); `sce_normed.rds` (1.16 MB), `subout.rds` (1.69 MB); `versions.yml` → `scran: 1.34.0` |
| **scater** (scRNA-seq QC & visualization) | `e08b8b62-8b1b-4ce8-a1dd-f750c612b8f2` | ✅ SUCCEEDED (exit 0) | **18 real plot PDFs** incl. `plot_pca_4comp.pdf` (318 KB), `plot_tsne_snap25.pdf`, `ggcells_tsne_density.pdf`, `plot_reduced_dim_pca.pdf`; dimred coord CSVs `tsne_perplexity{10,50}_head.csv`, `umap_head.csv`; `variance_explained_all.csv` (161 KB, real per-gene variance e.g. AURKAIP1 sizeFactor=5.62); `processed_example_sce.rds` (1.60 MB) |
| **scuttle** (feature QC & data transformation) | `d4b293ac-1235-4bb4-b841-ab16c843651c` | ✅ SUCCEEDED (exit 0) | `qc_metrics.json`: outlier-detection gate **`artifacts_emitted=7`, `passes=true`**; `per_cell_df.csv`, `per_feature_qc_metrics.csv` (39 KB), `average_expression.rds`, `sce.ens.rds` / `sce_ens_uniquified.rds` (ID-mapped SCEs) |
| **scdblfinder** (doublet detection) | `841f8ce0-a195-4fdd-b2c7-d280afb4f227` | ✅ SUCCEEDED (exit 0) | `scDblFinder_results.csv`: **400 cells, 393 singlets / 7 doublets**, per-cell scores (e.g. AAACATTGAGCTAC-1=0.316); `qc_metrics.json`: **`doublet_rate=0.0175`, gate `passes=true`**; `scDblFinder_score_histogram.pdf`, `sce_scDblFinder.rds`; `versions.yml` → `scDblFinder: 1.20.2` |
| **sc3** (SC3 clustering) | `fec12af4-419b-4a6c-97ce-5b71d88a72cc` | ❌ FAILED (exit 1) | No outputs persisted (only `.command.err`/`.exitcode`). Root-caused below. |

### sc3 FAILED — root cause + fix

- **Exact error** (CloudWatch `/aws/batch/job`, work dir `.command.err`):
  ```
  Error in SingleCellExperiment(assays = list(counts = as.matrix(yan),
    logcounts = log2(as.matrix(yan) + : could not find function "SingleCellExperiment"
  Execution halted
  ```
- **Root cause:** the R body calls the `SingleCellExperiment(...)` **constructor** but loads only
  `library(SC3)` and `library(SummarizedExperiment)` — it never attaches
  `library(SingleCellExperiment)`. SC3 *imports* SingleCellExperiment internally but does not
  re-export its constructor, so the symbol is unavailable on the search path. (Confirmed this is the
  only bug: dependency install succeeded, both CSVs were read successfully via `read.csv` — the error
  fires on the very next line, the SCE constructor. Not an input-shape, container, or 2-input-wrapper
  issue.) The workflow header already declares `Requires: SC3, SingleCellExperiment`, so the attach
  was simply omitted from the generated body.
- **Fix applied (1-line, root-cause):** `sc3/main.nf` — added
  `library(SingleCellExperiment)` to the library loads **and** added `"SingleCellExperiment"` to the
  `.bm_deps` resolver vector (so the constructor is guaranteed present even on a lean image).
  SingleCellExperiment is already baked into `bioc-domain-transcriptomics:3.20-slim` (it is a
  dependency of scran/scater/scuttle/scdblfinder, all of which constructed SCE objects and succeeded),
  so the attach will resolve with no runtime install.
- **Status:** committed; **needs a dev sync + one re-dispatch to confirm exit 0 + persisted outputs**
  (`sc3_cell_metadata_results.csv`, `sc3_gene_metadata_results.csv`, `sc3_sce_output.rds`,
  `sc3_plots.pdf`, `versions.yml`). Re-run was **not** performed this session — the sync lock is
  serialized and a concurrent session holds uncommitted working-tree files; per the coordination rule
  only committed-by-me files were touched and no out-of-band dev edit was made.

**Verdict:** the composable single-cell Bioconductor subworkflow chain is **VALIDATED on production
AWS Batch** — 4/5 tools produce real, biologically-sensible outputs (clustering, QC, dimred, doublet
calls) with exit 0; the 5th (sc3) has a confirmed root cause and a committed 1-line fix pending
sync+re-run. **Batch spend this task: ~$0 (read-only verification; the 5 jobs were run by the prior
session).**

---

## Run 2 — Single-cell (dropletutils) — ⚠️ Batch task FAILED (root-caused) [SUPERSEDED by Run 2b above]

- **Workflow:** `nextflow_nfcore/subworkflows/bioconductor/dropletutils/main.nf`
- **Container:** `quay.io/biocontainers/bioconductor-dropletutils:1.30.0--r45ha27e39d_0`
  (pullable; manifest verified on quay, ~896 MB)
- **Input (real):** 10X PBMC3k (CellRanger v2; 32738 genes × 2700 cells) —
  `s3://biomate-test-data/team-curated/single_cell/pbmc3k_10x/{matrix.mtx,barcodes.tsv,genes.tsv}`.
- **Two attempts (both single-cell, count toward the run budget as one domain):**
  1. `parameters={"dir.name":[3 files]}` → **422, no wrapper generated.** Root cause: the
     header `// Input: dir.name, my.counts` declares **two** inputs; supplying only `dir.name`
     leaves `my.counts` unresolved, and the wrapper's placeholder fallback only fires for a
     **single** declared input (`n_path<=1 and len(names)==1`) → `_build_bioc_entry_wrapper`
     returns `None`. **Fix applied:** also supply `my.counts` (any file; the R body prefers a
     literal `my.counts.rds`/`.mtx` and otherwise derives counts from the SCE, so an extra
     staged file is harmless).
  2. `parameters={"dir.name":[3 files], "my.counts": matrix.mtx}` → wrapper built
     (`style=A inputs=['dir.name','my.counts'] staged=4`), 3 files staged **by basename**
     (`matrix.mtx`/`barcodes.tsv`/`genes.tsv` — exactly what `read10xCounts(".")` needs),
     Nextflow launched, **Batch job `5f4b2e42-e98d-449d-8cb3-752dfd9ce547` submitted** to
     `biomate-nextflow-queue`.
- **Run id (BioMate):** `56851a75-ba27-4656-9f00-2ab7bba53f3c`;
  **Nextflow run id:** `becd7879-590f-444e-84f5-712db56d55d3`
- **Terminal status:** `failed` (Batch: "Essential container in task exited", exit 1, ~2 min).
- **ROOT CAUSE (verbatim, CloudWatch `/aws/batch/job`):**
  ```
  /opt/aws-cli/bin/aws: error while loading shared libraries:
    libz.so.1: cannot open shared object file: No such file or directory
  ```
  The **raw quay biocontainer is missing `libz.so.1`**, which the AWS CLI that Nextflow injects
  into the Batch task (to download inputs from / upload outputs to S3) links against. So
  Nextflow's S3 file-staging fails **before the R script ever runs** (work dir contains only
  `.command.run`/`.command.sh` — no `.command.err`, no `.exitcode` from the R body). This is a
  **container/infra blocker, not a workflow-logic bug** — the staging + wrapper + queue path all
  worked correctly.
- **Why this matters (class-level):** `dropletutils` is the **only** single-cell Bioc workflow
  that points at a raw quay biocontainer; its siblings (`scran`, `scater`, `scuttle`,
  `scdblfinder`, `sc3`) all use `biomate/bioc-domain-transcriptomics:3.20-slim`, which **is**
  Batch-ready (has aws-cli deps — proven by prior SUCCEEDED Bioc jobs on the queue, e.g.
  `BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION_sample`). **Any Bioc workflow whose `.nf`
  hardcodes a raw `quay.io/biocontainers/...` image will hit this same libz failure on Batch.**

### Recommended single-cell fix (real, not a workaround; for a separate PR)

1. **Fastest clean re-run:** re-point `dropletutils/main.nf`'s `container` from the raw quay
   image to `biomate/bioc-domain-single_cell:3.20-slim` or `bioc-domain-transcriptomics:3.20-slim`
   (DropletUtils is in `deps/single_cell.txt`), then re-dispatch the PBMC3k run above. This is a
   one-line container swap that makes it Batch-ready like its siblings.
2. **Class fix (preferred):** add a build/audit gate that rewrites any hardcoded raw
   `quay.io/biocontainers/*` container in an executable Bioc `.nf` to the matching Batch-ready
   `biomate/bioc-domain-*` image (or bake `libz`/aws-cli into a thin overlay). This closes the
   whole class in one place.
3. Alternatively validate SC via `scran`/`scater` (already on the Batch-ready image) after
   staging a small SCE `.rds` — but that needs R to build the SCE first.

---

## Spatial — BLOCKED, no run dispatched

- **`visium_voyager_spatial_esda/main.nf`** references
  `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-spatial:v1`. **No `spatial` /
  `bioc-spatial` / `voyager` repository exists in ECR** (confirmed by
  `aws ecr describe-repositories`). Its 10 stages call bespoke `/opt/biomate/voyager/*.R`
  scripts that live only inside that (never-built) image. The workflow header itself documents
  the P0 dependency (Voyager/SpatialFeatureExperiment/sf/spdep missing). **BLOCKED on image
  build — do not run.** (Plan §E already flagged this; still true.)
- **`merfish_spatial_analysis/main.nf`** uses the existing `biomate/biomni-tools:x86` image but
  its body is an **honest-failing stub**: it `sys.exit(1)`s with
  *"merfish_spatial_analysis is a stub with no real implementation — requires Cellpose + SpatialDE…
  Refusing to emit fabricated results."* No gold dataset defined either. **BLOCKED — needs real
  Cellpose/SpatialDE wiring.** Running it would deterministically fail by design.

Per the cost guard (≤2 runs) and the "don't build images / don't burn a run on a known-broken
container" rule, no spatial run was dispatched.

---

## `scrnaseq_standard_endtoend` stub verdict — **REMOVE or REPLACE (do not build as-is)**

- **Image:** `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/scrnaseq-standard:v1` —
  **DOES NOT EXIST** (no `scrnaseq-standard` repo in ECR; only `biomate/bioc-domain-single_cell`
  and `biomate/singlecell` exist).
- **Bespoke scripts:** every stage shells out to `/opt/biomate/scrnaseq/{validate_samplesheet.py,
  scdblfinder_qc.R, normalize_harmony.py, leiden_umap.py, celltypist_annotate.py,
  render_methods_report.py}` — these exist **only inside that unbuilt image**; there is no
  Dockerfile/deps manifest for them in the repo (`backend/scripts/domain_images/` has no
  `scrnaseq-standard` target). **Unimplemented stub — confirmed.**
- **Orchestration gap (unchanged from 20260923):** STAGE 2 is a comment ("orchestrator stages
  `counts_matrix.h5ad`") but no executor code stages it, and there is no `--input_h5ad` branch —
  so even with the image, STAGE 3 has no input.
- **Verdict — REMOVE/REPLACE, do NOT build `:v1` as written.** A monolithic bespoke image +
  six unwritten scripts + missing STARsolo orchestration is a large, fragile build for a path
  that the composable Bioc single-cell subworkflows (`dropletutils` → `scran`/`scater`/
  `scuttle`/`scdblfinder`, all already on the Batch-ready `bioc-domain-*` images) already cover
  step-by-step. Recommend: (a) mark `scrnaseq_standard_endtoend` non-routable / drop it from the
  executable set, and (b) validate single-cell through the Bioc subworkflow chain instead (fix
  the raw-biocontainer→bioc-domain container swap first, per Run 2). If an end-to-end SC pipeline
  is wanted, compose it from the existing Batch-ready subworkflows rather than a new bespoke image.

---

## Spend + hygiene

| Item | Detail | Cost |
|---|---|---|
| ChIP-seq Batch (SUCCEEDED) | CHIPSEEKER 4m7s + RDS_INTROSPECT 1m38s, process_medium (~6 vCPU peak), on-demand | ~$0.10 |
| Single-cell Batch (FAILED at staging) | job `5f4b2e42`, container ran ~2 min then died at libz (no compute) | ~$0.02 |
| Data staging / S3 / SSM diagnostics | 416 B BED upload; CloudWatch/SSM reads | <$0.01 |
| Spatial | not dispatched (blocked) | $0.00 |
| **Total** | **2 real Batch runs (1 pass, 1 root-caused fail)** | **~$0.12** |

- **No EC2 launched by this work.** (An orphan build box `i-02d4cc93a2549bfc9`
  `metaboanalystr-build-a13` is a **separate concurrent metabolomics session's** box, not mine —
  not touched; it has its own dead-man's switch.)
- **No dev code edits, no git commits, no `sync_to_dev.sh`.** All dev interaction was the
  production `POST /api/workflows/execute` run path + read-only SSM log diagnostics.
- Infra confirmed healthy: `biomate-nextflow-queue` ENABLED/VALID; `biomate-nextflow-ce-v2` +
  cpu-v2/v4/v5 + hpc-v1 all ENABLED.

## Next steps (separate engineering tasks — not this validation)

1. **Single-cell:** ✅ DONE — container swapped (`9641ed6e2`, synced), wrapper 422 fixed
   (`9641ed6e2`), versions.yml typo fixed (`6fb4b084e`, awaiting consolidated sync). emptyDrops
   validated on the RAW PBMC3k matrix (2876 cells). **Remaining:** (a) after the consolidated sync,
   re-dispatch run `671f6f43`'s params once more to confirm exit 0 + persisted S3 outputs; (b) add
   a **class-level build/audit guard** that forbids raw `quay.io/biocontainers/*` containers in
   executable Bioc `.nf` files — grep the subworkflow tree and rewrite any remaining raw-quay
   `container` to the matching `biomate/bioc-domain-*` image (they all fail S3 staging on Batch via
   the libz/aws-cli gap). dropletutils was the only single-cell offender, but a repo-wide grep
   found **688 other Bioc `.nf` files across all domains still hardcoding raw
   `container "quay.io/biocontainers/*"`** — every one will hit the same libz S3-staging failure
   the moment it runs on Batch. This latent-blocker class makes the auto-rewrite guard high
   priority. (Out of scope for this dropletutils task; flagged for a dedicated sweep PR.)
2. **ChIP-seq (polish):** add `TxDb.Hsapiens.UCSC.hg19.knownGene` + `org.Hs.eg.db` to
   `deps/epigenomics.txt` so runs skip the runtime install; validate the `enrichment` variant.
3. **Spatial:** build the `biomate/bioc-spatial` image (Voyager+sf+spdep+SpatialFeatureExperiment)
   OR wire MERFISH to real Cellpose/SpatialDE — both are large, deferred, image-build tasks.
4. **scrnaseq_standard_endtoend:** remove/deprecate; cover SC via the composable Bioc chain.
