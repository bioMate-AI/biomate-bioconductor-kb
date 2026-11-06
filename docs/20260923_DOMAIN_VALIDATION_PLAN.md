# Domain Validation Plan — 5 Untested Domains (READY-TO-RUN, NOT LAUNCHED)

**Date:** 2026-09-23
**Author:** Yaoyun Zhang
**Status:** PREP-ONLY. No AWS Batch run has been launched. This doc is a ready-to-run plan for user sign-off on the spend.

## Scope

Five domains have **no real end-to-end AWS Batch run evidence** on S3
(confirms the `project_workflow_validation_gaps` memory):
**proteomics, metabolomics, epigenomics/ChIP-seq, single-cell, spatial.**

For each: (1) existing-evidence check, (2) one representative indexed
workflow + `nextflow_path`, (3) a small real public dataset, (4) Batch
cost + wall-clock estimate, (5) dispatch + verify method. **Do NOT launch
any Batch run without explicit user approval — each costs real money.**

---

## 1. Existing-evidence check (S3 + docs) — what actually exists

Buckets scanned (read-only `aws s3 ls`): `s3://biomate-nextflow-work`
(main output store, ~40k objects / 17 GB under `nextflow/outputs/`),
`s3://biomate-nextflow-outputs` (near-empty: deploy tarballs + one test
h5ad), `s3://biomate-workflow-inputs` (gold inputs). `s3://biomate-prod-uploads`
**does not exist** (NoSuchBucket).

| Domain | Real run output on S3? | What was found instead |
|---|---|---|
| **Proteomics** | **NONE** | One 34 KB `proteomics.csv` inside an ADMET/drug-discovery project — a one-off stub, not a diaproteomics/msqrob2 run. No mzML, no protein-quant matrix, no MSstats. |
| **Metabolomics** | **NONE** | `test-drug-dev-batch/*/metabolite_run/metabolites.csv` (517 B) — drug-*metabolism* stubs, not LC-MS metabolomics. No xcms, no feature table, no MetaboIgniter/MTBLS run. |
| **Epigenomics / ChIP-seq** | **NONE (attempted, never completed)** | ~10 `nf-core/chipseq` launches under `nextflow/outputs/unknown/*/` — each has ONLY `pipeline_info/` (execution_report HTML, timeline, DAG) + a versions yml. **No BAM, no MACS2 narrowPeak/broadPeak, no annotated peaks, no MultiQC.** Every launch died before the peak-calling step. |
| **Single-cell** | **NONE (only inputs + stubs)** | Inputs: `sc_citeseq/` (rna.csv 16.7 MB + adt.csv), `sc_multiome*/`, `alignment_qc/pancreas.h5ad` (316 MB reference). Outputs: sub-10 KB synthetic virtual-workflow stubs (`doublet_run/cell_qc_table.csv`, `multiome_run/cell_annotations.csv`). No real Seurat/Scanpy run, no output h5ad/UMAP/CellTypist. |
| **Spatial** | **NONE** | `merfish_run/` stubs only: `spatial_domains.csv` (242 B), `spatially_variable_genes.csv` (346 B). All sub-KB synthetic. No Visium/spatialvi/Voyager run. |

**Cross-cutting gap — inputs are not staged.** `evaluation/tutorial_demos/gold_standards.yaml`
names an `s3_inputs:` path for each domain, but only **transcriptomics**
(23 objects, ~161 GB) and `neuroimmune/` are actually present under
`s3://biomate-workflow-inputs/tutorial-gold/`. The five target paths
(`proteomics/PXD002952/`, `metabolomics/MTBLS136/`,
`epigenomics/encode_k562_h3k27ac/`, `single_cell/pbmc_10k_v3/`, and any
spatial path) are **0 objects — empty**. So a genuine prerequisite for
every run below is **stage the input dataset first** (download from the
public repo → upload to the input path). That is data-transfer + time,
not Batch compute, but it must happen before dispatch.

---

## 2–5. Per-domain ready-to-run plan

Cost basis: the active Batch compute environment `biomate-nextflow-ce-v2`
(us-west-2, **EC2 on-demand** — not spot) offers `m5.large…m5.4xlarge`,
`c5.xlarge…c5.4xlarge`, `r5.xlarge/2xlarge`. Nextflow labels map to
`process_low` (2 vCPU / 4 GB), `process_medium` (4 / 8), `process_high`
(8 / 16) — from `backend/biomni_workflows/nextflow_nfcore/nextflow.config`.
On-demand $/hr (us-west-2): m5.large $0.096, m5.xlarge $0.192,
m5.2xlarge $0.384, m5.4xlarge $0.768, c5.2xlarge $0.34, c5.4xlarge $0.68,
r5.2xlarge $0.504. Estimates assume one instance active for the run's
wall-clock (Batch packs the DAG onto ~1–2 nodes for these small inputs)
and add ~20% for scheduler/scale-up idle + S3 I/O.

### A. Proteomics
- **Workflow (indexed):** `bioc_proteomics_de_v2` chain — front-end
  `nf-core/proteomicslfq` (DB id **1496**) → **msqrob2 DIA precursor DE**.
- **`nextflow_path`:**
  `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/msqrob2/dia_precursor_workflow.nf`
  (front-end stub: `backend/biomni_workflows/nfcore/proteomicslfq/main.nf`).
- **Dataset:** ProteomeXchange **PXD002952** (UPS1 48-protein spike-in in
  yeast lysate). For a *cheap* first pass, use a **2–4 raw-file subset**
  (one low + one high spike ratio, ~1–3 GB) rather than the full
  ~20–40 GB deposit — enough to score `ups1_recall_at_fdr5` on a handful
  of runs. Full deposit only if the subset passes.
- **Instance / resources:** DIA search is CPU-bound → **c5.2xlarge**
  (8 vCPU / 16 GB), `process_high`.
- **Est. wall-clock:** ~1.5–3 h on a 2–4 file subset (raw→mzML convert +
  library search dominate).
- **Est. cost:** c5.2xlarge $0.34/hr × ~3 h × 1.2 ≈ **$1.2**. Full deposit
  (~12–20 raw files) would be ~$4–6.

### B. Metabolomics
- **Workflow (indexed):** `lcms_metabolomics_consensus` chain —
  `bioconductor_metabolomics` (XCMS → CAMERA → metaboAnnotation →
  clusterProfiler); also surfaces via `nf-core/metaboigniter` (DB id **12731**).
- **`nextflow_path`:**
  `backend/biomni_workflows/nextflow_nfcore/workflows/bioconductor_metabolomics/main.nf`.
- **Dataset:** MetaboLights **MTBLS136** (Thévenot 2015 human urine LC-MS,
  age×gender×BMI). Score `published_biomarker_recall` (gender-discriminating
  steroids). Small study — a ~20–40 sample mzML subset is ~2–4 GB;
  centroided mzML is small.
- **Instance / resources:** XCMS peak-picking is memory-ish, moderate CPU →
  **m5.2xlarge** (8 vCPU / 32 GB), `process_high`.
- **Est. wall-clock:** ~1–2 h.
- **Est. cost:** m5.2xlarge $0.384/hr × ~2 h × 1.2 ≈ **$0.9**.

### C. Epigenomics / ChIP-seq
- **Workflow (indexed):** `nf-core/chipseq` (DB id **1492**, bwa + MACS2 +
  IDR) → chain `bioc_chipseq_annotation_v2` (ChIPseeker → clusterProfiler).
- **`nextflow_path`:** `backend/biomni_workflows/nfcore/chipseq/main.nf`
  (annotation chain resolves via
  `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/chipseeker/`).
- **Dataset:** ENCODE **K562 H3K27ac** + matched input control. Ground
  truth = ENCODE consensus narrowPeak **ENCFF044JNJ**; score
  `encode_peak_overlap` ≥ 0.80. Use **one replicate FASTQ + one input
  control** (~2–5 GB each, subsampled if needed). Histone mark → set
  `macs2_broad=false` for H3K27ac (sharp enhancer/promoter peaks).
- **NOTE:** this is the only domain with prior Batch *attempts* — all died
  before peak-calling (pipeline_info-only outputs). Root-cause the earlier
  failure (likely missing genome/samplesheet columns) **before** re-running,
  per the "resolve root causes" rule. Do not just re-launch blindly.
- **Instance / resources:** bwa alignment CPU-bound → **c5.2xlarge**
  (8 vCPU / 16 GB), `process_high`.
- **Est. wall-clock:** ~2–4 h (align + MACS2 + annotate).
- **Est. cost:** c5.2xlarge $0.34/hr × ~4 h × 1.2 ≈ **$1.6**. Add ~10–20 min
  reference/index build if not cached.

### D. Single-cell
- **Workflow (indexed):** `scrnaseq_standard_endtoend` — validate →
  `nf-core/scrnaseq` (DB id **12777**, STARsolo) → scDblFinder QC → Harmony
  → Leiden+UMAP → CellTypist → Methods report; surfaced via chain
  `scrnaseq_standard_to_isee` (gold chain `single_cell_multimodal_analysis`).
- **`nextflow_path`:**
  `backend/biomni_workflows/nextflow_nfcore/subworkflows/single_cell/scrnaseq_standard_endtoend/main.nf`.
- **Dataset:** **10x PBMC 10k v3** (~10k cells, Chromium v3). Ground truth =
  Azimuth PBMC reference; score `azimuth_macro_f1` ≥ 0.85. **Cheapest
  variant:** feed the **Cell Ranger `.h5ad` / filtered_feature matrix**
  (skips STARsolo alignment entirely — the expensive step) so the run is
  just QC→cluster→annotate. Full FASTQ→counts path is the pricier option.
- **Instance / resources:** if `.h5ad` input → **m5.2xlarge** (8/32),
  `process_high`. If full FASTQ+STARsolo → needs **m5.4xlarge** (16/64,
  ~30+ GB for the human index).
- **Est. wall-clock:** `.h5ad` path ~1–1.5 h; full FASTQ path ~3–5 h.
- **Est. cost:** `.h5ad` path m5.2xlarge $0.384/hr × ~1.5 h × 1.2 ≈ **$0.7**.
  Full FASTQ path m5.4xlarge $0.768/hr × ~5 h × 1.2 ≈ **$4.6**.

### E. Spatial
- **Workflow (indexed):** `visium_voyager_spatial_esda` — composes
  `nf-core/spatialvi` (id 12783) → SpatialFeatureExperiment → Voyager
  spatial stats (Moran's I / Geary's C / Getis-Ord) → iSEE.
- **`nextflow_path`:**
  `backend/biomni_workflows/nextflow_nfcore/subworkflows/single_cell/visium_voyager_spatial_esda/main.nf`.
- **Dataset:** a small **10x Visium** demo — e.g. 10x Genomics public
  *Human Brain (Cerebellum) / Mouse Brain Sagittal* Space Ranger output
  (one capture area, filtered_feature_bc_matrix + spatial/, ~1–3 GB).
- **⚠️ BLOCKER — NOT READY TO RUN.** The workflow header documents a **P0
  dependency**: Voyager, SpatialFeatureExperiment, VisiumIO, SpatialExperiment
  are all `exec_error` because the `bioc-domain-transcriptomics:3.20` ECR
  image is **missing the Voyager R package + sf + spdep**. The bioc-fix
  workstream must rebuild the image (tag `:3.20-voyager`) before this can
  acceptance-test. Alternative: `merfish_spatial_analysis` (Cellpose/Baysor
  → spatialDE) — but no gold dataset is defined for spatial in
  `gold_standards.yaml`, so scoring is qualitative only.
- **Instance / resources (once unblocked):** **r5.2xlarge** (8/64, sf/spdep
  graphs are memory-heavy), `process_high`.
- **Est. wall-clock:** ~1.5–3 h (once image is fixed).
- **Est. cost (once unblocked):** r5.2xlarge $0.504/hr × ~3 h × 1.2 ≈ **$1.8**.
  **Prerequisite cost:** rebuilding the ECR image is a separate
  build-instance spend (~$0.5–2 of build time), not counted below.

---

## Cost + time summary

| Domain | Workflow | `nextflow_path` | Dataset (accession) | Cheap-subset size | Instance | Est. time | Est. $ |
|---|---|---|---|---|---|---|---|
| Proteomics | `bioc_proteomics_de_v2` (msqrob2 DIA; nf-core/proteomicslfq 1496) | `…/subworkflows/bioconductor/msqrob2/dia_precursor_workflow.nf` | PXD002952 (UPS1) | 2–4 raw files, ~1–3 GB | c5.2xlarge | ~3 h | **$1.2** |
| Metabolomics | `lcms_metabolomics_consensus` (bioconductor_metabolomics; metaboigniter 12731) | `…/workflows/bioconductor_metabolomics/main.nf` | MTBLS136 (urine LC-MS) | ~20–40 mzML, ~2–4 GB | m5.2xlarge | ~2 h | **$0.9** |
| Epigenomics/ChIP-seq | `nf-core/chipseq` 1492 → `bioc_chipseq_annotation_v2` | `…/nfcore/chipseq/main.nf` | ENCODE K562 H3K27ac (gold ENCFF044JNJ) | 1 rep + 1 control, ~4–10 GB | c5.2xlarge | ~4 h | **$1.6** |
| Single-cell | `scrnaseq_standard_endtoend` (nf-core/scrnaseq 12777) | `…/subworkflows/single_cell/scrnaseq_standard_endtoend/main.nf` | 10x PBMC 10k v3 | `.h5ad` (cheap) / FASTQ (full) | m5.2xlarge / m5.4xlarge | ~1.5 h / ~5 h | **$0.7 / $4.6** |
| Spatial ⚠️ | `visium_voyager_spatial_esda` (spatialvi 12783 + Voyager) | `…/subworkflows/single_cell/visium_voyager_spatial_esda/main.nf` | 10x Visium demo (brain) | 1 capture, ~1–3 GB | r5.2xlarge | ~3 h | **$1.8** *(blocked)* |

**Total to validate all five (cheapest subset per domain):**
$1.2 + $0.9 + $1.6 + $0.7 + $1.8 ≈ **$6.2 in Batch compute.**
Realistic all-in with retries, index/reference builds, and the spatial
ECR rebuild: **~$10–15.** (Full-FASTQ single-cell instead of `.h5ad`
adds ~$4; full PXD002952 deposit adds ~$4.)

These are small — the constraint is **not** money but (a) staging the five
input datasets (none present in S3 today), (b) the spatial ECR-image
blocker, and (c) root-causing the prior failed ChIP-seq launches.

---

## Dispatch + verification (canonical pattern)

Dispatch via the live chat/stream API against dev, exactly as
`scripts/e2e_use_cases.sh` does — **do not** hand-roll `nextflow run`.

1. **Auth:** login the fixture `lifeifei163361@163.com` (password =
   `E2E_FIXTURE_PASSWORD`) → cache JWT once. Header
   `x-e2e-test-token: biomate-e2e-bypass-token-dev-only`. `BIOMATE_URL=https://dev-public.biomate.ai`.
2. **One project** per harness (create at top, delete in EXIT trap).
3. **Trigger:** `POST /api/chat/stream` with the domain prompt from
   `gold_standards.yaml` (e.g. proteomics: *"Bioconductor proteomics
   pipeline — label-free protein DE analysis"*) + the staged S3 input path
   as the dataset. Use a **90 s** timeout for the workflow-card
   generation call.
4. **Run:** confirm the workflow card, then trigger the run
   (`/api/nextflow/...` run endpoint the panel calls); poll run status via
   SSE / `GET` run endpoint until terminal.
5. **Verify (per domain gate in `gold_standards.yaml`):**
   - Proteomics: `ups1_recall_at_fdr5` ≥ 0.80, `yeast_background_fpr` ≤ 0.05
   - Metabolomics: `published_biomarker_recall` ≥ 0.70
   - Epigenomics: `encode_peak_overlap` ≥ 0.80
   - Single-cell: `azimuth_macro_f1` ≥ 0.85
   - Spatial: qualitative (no gold metric defined)
6. **Evidence:** confirm real output artifacts land in
   `s3://biomate-nextflow-work/nextflow/outputs/<project>/…` (protein-quant
   table / feature table / narrowPeak / annotated h5ad / spatial-stats CSV)
   — the very artifacts the S3 sweep found MISSING today.

---

## Cheapest-subset-first recommendation

Run these **two first** for the most validation-per-dollar:

1. **Single-cell (`.h5ad` input path) — ~$0.7, ~1.5 h.** Cheapest, fastest,
   highest-value: it exercises the full QC→Harmony→Leiden→CellTypist chain
   and the in-app UMAP panel, has a hard gold metric (`azimuth_macro_f1`),
   and the input is a single small object. Feeding `.h5ad` skips the
   expensive STARsolo alignment. Best first proof that a real multi-stage
   biological pipeline completes and scores.
2. **Metabolomics (MTBLS136 subset) — ~$0.9, ~2 h.** Second-cheapest;
   validates a distinct Bioconductor path (XCMS→CAMERA→annotation→pathway)
   that shares nothing with single-cell, so it broadens coverage per dollar.

**Defer:** **Spatial** (blocked on the Voyager ECR rebuild — fix the image
first, don't burn a run on a known-broken container) and **full-FASTQ
single-cell / full-PXD002952** (only after the cheap subsets prove the
path). **Epigenomics** is cheap but should wait until the prior failed
ChIP-seq launches are root-caused (they died pre-peak-calling — re-running
without diagnosis violates the "resolve root causes" rule).

**Prerequisite for ALL of the above (no Batch cost, but blocking):** stage
the five input datasets into their `s3://biomate-workflow-inputs/tutorial-gold/<domain>/`
paths — none are present today.

---

## Do-not / guardrails
- **No Batch run launched by this plan.** User must approve the spend.
- **No `sync_to_dev.sh`, no direct dev edits** from this work — read-only.
- Fix the spatial ECR image and root-cause the ChIP-seq failures **before**
  spending on those two.
