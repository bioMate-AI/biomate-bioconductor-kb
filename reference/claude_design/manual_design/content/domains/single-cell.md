# Single-cell RNA-seq

> One-line promise: go from raw 10x FASTQ (or a Cell Ranger / `.h5ad` object)
> to a **clustered, cell-type-annotated single-cell atlas** — a UMAP you can
> read at a glance, the marker genes that name each cluster, and a per-cell QC
> report that tells you which cells to trust — then take cell types forward to
> pseudobulk differential expression across donors. No coding required.
> For: **wet-lab immunologists / cancer biologists** with a 10x run and no
> desire to write Scanpy or Seurat, and **bioinformaticians** who want the
> nf-core + Harmony + celltypist production chain run and reported for them.

<!--
P1 chapter. Every "supported" claim below is green in coverage-ledger.md § "Single-cell RNA-seq".
Honesty rules honored here:
- The scRNA .nf workflow (stages, outputs, QC params) is code-verified (tier C, file:line).
- The in-app single-cell panel (UMAP + clusters + markers) is FRONTEND-verified (tier C) but
  DATA-GATED: it only draws when a real run has emitted the annotated.h5ad.summary.json sidecar.
  Until a live scRNA run emits that sidecar end-to-end, the panel self-hides → tier L / ⏳.
- No AWS Batch runs were fired for this chapter (plan forbids speculative execution). The
  worked-example numbers come from the gold-standard demo spec; a live re-run is L / ⏳.
- The bulk-vs-single-cell routing guard is code-verified (tier C) and cross-referenced to the
  Transcriptomics chapter, which documents the same guard from the bulk side.
Cross-ref I.8 (Outputs, viewers & interactive panels) for the viewer taxonomy + the sidecar honesty gate.
-->

## What this is for

This is the **"what cell types are in my sample, and how do they differ between
conditions"** path. You ran a droplet experiment (10x Chromium, Drop-seq,
Smart-seq) and you have thousands to hundreds of thousands of individual cells.
You want to know: how many populations are there, what are they (T cells, B
cells, monocytes, a tumour subclone…), which genes mark each one, and — if you
have more than one donor or condition — which populations shift.

BioMate meets you at whichever point you already have:

1. **You have raw 10x FASTQ.** BioMate runs the full production chain:
   alignment + quantification (nf-core/scrnaseq) → per-cell QC + doublet removal
   (scDblFinder) → normalise + batch integration (Harmony) → clustering + UMAP
   (Leiden) → reference-based cell-type annotation (celltypist) → a Methods
   report — and, on a real run, the compact summary that powers the in-app UMAP
   panel.
2. **You have Cell Ranger output or an `.h5ad`.** BioMate runs the downstream
   chain directly — QC, integration, clustering, annotation, and multi-sample
   differential abundance / pseudobulk DE.

The through-line of this chapter is the same as the rest of the book:
**interpretation, not a statistics dump.** Every QC number below is explained as
"what it means and what to do next," and the worked example ends on a *decision*
(these cell types, these markers, this shift), not a process tree.

> **Pitfall — this is single-cell, not bulk.** The single most important
> disambiguation in transcriptomics is bulk vs single-cell, and it is a real
> statistical error, not a preference. Do **not** route single-cell data to the
> bulk `differentialabundance` / DESeq2 chain: running a count model cell-by-cell
> treats every cell as an independent replicate, which they are not (cells from
> one donor are correlated), and it inflates false positives massively. BioMate's
> router enforces the split in code (see *How to ask*). When you want DE across
> conditions on single-cell data, the correct statistics are **pseudobulk**
> (aggregate counts per donor × cell type, then DESeq2 on those) — which is
> exactly what the single-cell pseudobulk chain does. See the Transcriptomics
> chapter for the same pitfall from the bulk side.

## Use cases

| Goal (researcher's words) | Workflow(s) / chain | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "Cluster my 10x run and tell me what cell types are there" | `scrnaseq_standard_endtoend` (the end-to-end `.nf`: nf-core/scrnaseq **12777** → scDblFinder QC → Harmony → Leiden+UMAP → celltypist), surfaced via chain **`scrnaseq_standard_to_isee`** | 10x FASTQ + samplesheet (or Cell Ranger `.h5ad`) | `annotated.h5ad` + `celltype_assignments.csv` + `marker_genes_per_cluster.csv` + `qc_metrics.csv` + `umap_celltypes.png` + Methods report; **+ the in-app UMAP panel** when the `.summary.json` sidecar is emitted | Cloud (AWS Batch) |
| "Full multi-sample scRNA analysis with donor batch correction, then which populations shift" | chain **`single_cell_multimodal_analysis`**: QC/normalise → Harmony integration → clustering+annotation → trajectory → differential abundance (donor as random effect) | Cell Ranger output (or `.h5ad`) + sample metadata (donor + condition) | `h5ad_final` + `cell_type_umap` (pdf) + `da_results` (tsv) + `trajectory_plot` (pdf) | Cloud |
| "I already have cell types — run pseudobulk DE across conditions the right way" | chain **`scrna_pseudobulk_de_bioc`** ("scRNA-seq → Pseudobulk DESeq2 (OSCA)") | Annotated `.h5ad` / SCE + condition metadata | Pseudobulk DE table per cell type | Cloud |
| "Open my clustered `.h5ad` in an interactive browser" | chained **iSEE** (id **11653**) after `scrnaseq_standard_endtoend`; or CellxGene/Jupyter from the Outputs section | `annotated.h5ad` | iSEE Shiny app / interactive session | Cloud (interactive, environment-gated — see *What's not covered*) |

> **Tip — you don't need FASTQ to get value.** If a collaborator or core gave you
> a Cell Ranger `.h5ad`, skip alignment and enter the downstream chain directly.
> Alignment (STARsolo / alevin on Batch) is the expensive step; run it only when
> you actually have raw reads.

## How to ask

BioMate routes on intent. The two disambiguations that matter here are **single-cell
vs bulk** (a hard statistical fork) and **what you already have** (FASTQ vs a
clustered object).

Full pipeline from 10x FASTQ:

> "Run single-cell analysis from Cell Ranger output — QC, clustering, and annotate
> the cell types. Human PBMC, 10x Chromium."

Downstream on an existing object, with donor correction and abundance testing:

> "scRNA-seq clustering, annotation, and differential abundance across donors —
> correct for donor batch."

**How the routing actually decides** (verified in
`backend/lib/galaxy/ai/unified_workflow_search.py:2620-2657`). The single-cell
chain `single_cell_multimodal_analysis` is **only** allowed to match when your
prompt carries an explicit single-cell signal — one of: `single cell`,
`single-cell`, `scrnaseq`, `scrna-seq`, `10x genomics`, `10x chromium`,
`cell ranger`, `cellranger`, `droplet-based`, `dropseq`, `smart-seq`, `umi counts`,
`scanpy`, `seurat`, `anndata`, and related terms
(`_CHAIN_REQUIRED_CONTEXT`, `unified_workflow_search.py:2620-2634`). The gate is
enforced by `_chain_multimodal_context_compatible()`
(`unified_workflow_search.py:2637-2657`): a query lacking any of those terms is
filtered out of this chain.

**The bulk-vs-single-cell guard — the documented pitfall, from both sides.** The
in-code comment is explicit: *"Bulk RNA-seq queries ('process 30 bulk RNA-seq
samples', 'produce a gene counts matrix') share vocabulary with this chain but
describe completely different assays"* (`unified_workflow_search.py:2622-2626`).
Generic biology words — "cell types", "clustering" — are **deliberately excluded**
from the single-cell trigger set, because they also appear when someone clusters
*bulk* samples. That is why one word matters: say **"single-cell"** (or name your
10x / Cell Ranger / Scanpy / `.h5ad` input) and the route flips to the correct
chain and the correct — pseudobulk — statistics. The Transcriptomics chapter
documents the mirror image of this guard on the `bulk_rnaseq_de_analysis` side.

> **Pitfall — "cell types" alone does not mean single-cell.** A prompt like "find
> the cell-type differences between my samples" with no single-cell technology
> named will **not** route here — the router treats "cell types" as ambiguous
> (bulk deconvolution says "cell types" too). Name the assay: "single-cell",
> "10x", "Cell Ranger", ".h5ad". That is the difference between pseudobulk (right)
> and cell-by-cell DESeq2 (wrong).

## Tools & workflows behind this

| Tool / workflow | Role | Where (verified) |
|---|---|---|
| `scrnaseq_standard_endtoend` (the end-to-end `.nf`) | 7-stage pipeline: validate → nf-core/scrnaseq → scDblFinder QC → normalise+Harmony → Leiden+UMAP → celltypist → Methods report (+ sidecar) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/single_cell/scrnaseq_standard_endtoend/main.nf:1-193` |
| `nf-core/scrnaseq` (id **12777**) | Alignment + quantification (STARsolo default); called as a **sub-workflow** for the counts matrix | `.../scrnaseq_standard_endtoend/main.nf:6-8,81-86`; DB id 12777 |
| scDblFinder | Per-cell QC + doublet detection/removal | `.../main.nf:88-98` (`scdblfinder_qc.R`); Germain et al. 2021 F1000Research |
| Harmony | Batch-aware integration across samples/donors | `.../main.nf:100-109` (`normalize_harmony.py`); Korsunsky et al. 2019 Nat Methods |
| Leiden + UMAP | Clustering + 2-D embedding | `.../main.nf:111-119` (`leiden_umap.py`) |
| celltypist | Reference-based cell-type annotation (default model `Immune_All_Low`) | `.../main.nf:44-45,121-130` (`celltypist_annotate.py`); Domínguez Conde et al. 2022 Science |
| **Summary sidecar (STAGE 6.5)** | Emits `annotated.h5ad.summary.json` (UMAP points, cluster counts, top markers) that powers the in-app panel — **optional + fail-soft** | `.../main.nf:66-69,132-172` |
| Chain `scrnaseq_standard_to_isee` | "Standard scRNA-seq → interactive iSEE app" — surfaces the end-to-end `.nf` + chains iSEE | DB `workflow_chains` (domain `single_cell`) |
| Chain `single_cell_multimodal_analysis` | Multi-sample: QC → Harmony → annotate → trajectory → differential abundance (donor random effect) | `backend/scripts/index_all_workflows.py:509-548` |
| Chain `scrna_pseudobulk_de_bioc` | scRNA → **pseudobulk** DESeq2 (OSCA) — the correct cross-condition DE | DB `workflow_chains` (domain `single_cell`) |
| iSEE (id **11653**) | Interactive Shiny app, chained after annotation | `.../main.nf:17,174-178`; DB id 11653 |
| Chain routing / single-cell context guard | Keyword gate; bulk-vs-single-cell hard split | `unified_workflow_search.py:2620-2657` |
| Single-cell QC evidence | Per-cell QC + doublet thresholds with citations | `backend/config/qc_evidence.yaml:1450-1464` (`bioc_cell_qc_metrics`), `:1565-1578` (`bioc_doublet_detection`) |
| In-app single-cell panel | Renders UMAP + clusters + markers from the sidecar | `frontend/client/src/components/viewers/single-cell-summary.tsx`; wired in `step-output-preview.tsx:589` (see I.8) |

The end-to-end `.nf` is a **composer**: it `include`s `nf-core/scrnaseq` (12777)
for alignment, then adds BioMate's own QC / Harmony / Leiden / celltypist layer
and the sidecar (`.../main.nf:6-9`). STAGE 5's `X_umap` embedding and STAGE 6's
`marker_genes_per_cluster.csv` are what STAGE 6.5 reads to build the sidecar
(`.../main.nf:144-168`) — no extra compute beyond a subsample.

> **License** — nf-core/scrnaseq, Scanpy, Harmony, scDblFinder, Leiden, celltypist
> and iSEE are open-source academic tools; results are yours. celltypist models
> (`Immune_All_Low` / `Immune_All_High`) are the standard public releases; the
> GRCh38 / GENCODE reference is the standard public annotation.

## QC gates & how to read them

A single-cell QC gate answers one question for a biologist: **"which of my
'cells' are real, healthy cells I can cluster and trust?"** In droplet data three
things go wrong before any biology: empty/dying cells (too few genes), stressed or
lysed cells (too much mitochondrial RNA), and two cells captured in one droplet
(doublets). The pipeline filters all three, with these real thresholds:

| Gate | Threshold (real default) | What a fail means | Enforced where |
|---|---|---|---|
| **Min genes per cell** | **≥ 200** genes detected | Below ~200 genes a barcode is usually an empty droplet or ambient RNA, not a cell — it adds noise, not signal. | `.nf` param `min_genes_per_cell='200'` (`.../main.nf:38`); applied in STAGE 3 (`--min_genes`, `:93`). Matches the `n_features > 200` floor in evidence (`qc_evidence.yaml:1461`) |
| **% mitochondrial reads** | **≤ 20%** (`.nf` default) | High mito fraction = a stressed / dying / lysed cell leaking cytoplasmic RNA. Filter it before clustering or it forms a fake "low-quality" cluster. | `.nf` param `max_pct_mito='20'` (`.../main.nf:39`); applied STAGE 3 (`--max_pct_mito`, `:94`). **See the pitfall below** — evidence default is 10% for most tissues |
| **Doublet score** | **≤ 0.3** (scDblFinder) | Cells above the doublet score are two cells in one droplet; they produce chimeric expression and spurious "intermediate" clusters. | `.nf` param `doublet_score_threshold='0.3'` (`.../main.nf:40`); applied STAGE 3 (`--doublet_threshold`, `:95`). Expected 10x doublet rate ~1% per 1000 cells (`qc_evidence.yaml:1570-1575`) |

**How to read each:**

- **Min genes ≥ 200** — this is the standard floor (Luecken & Theis 2019,
  `qc_evidence.yaml:1450-1461`). For most tissues 200 is a safe empty-droplet
  cutoff; very sparse assays (some nuclei preps) may sit lower — if you filter out
  most of your barcodes, your capture may have been poor, not your threshold wrong.
- **% mito ≤ 20%** — read the **distribution**, not just the cutoff. The QC violin
  (`qc_violin.png`) shows a healthy population near the low end with a tail of
  dying cells; the gate trims the tail. A whole sample sitting high means a stressed
  prep (long dissociation, warm handling), not a threshold problem.
- **Doublet score ≤ 0.3** — scDblFinder estimates a doublet rate calibrated to
  droplet loading. Look at `doublet_hist.png`: a clean bimodal split (singlets low,
  doublets high) means the filter is doing its job. If ~half your cells are called
  doublets you over-loaded the chip — that's a wet-lab signal, not a software one.

> **Pitfall — the `.nf` %-mito default is 20%, higher than the 10% "standard."**
> The single-cell QC evidence (`qc_evidence.yaml:1460`) states `pct_mito_max < 10%`
> for **most** tissues, with `< 20%` reserved for **brain / liver** (which
> naturally carry more mitochondria). The production `.nf` ships a **permissive
> 20% default** (`main.nf:39`) so it does not silently discard cells on
> mito-rich tissues. The manual states the code truth: 20% is what runs unless you
> lower it. For a standard PBMC / immune sample, set `max_pct_mito` to **10%**
> yourself for a stricter, tissue-appropriate cut — the 20% default will let more
> stressed cells through than the textbook standard.

> **QC gate — read the QC plots before the UMAP.** `qc_violin.png` (genes / counts
> / %mito distributions) and `doublet_hist.png` are produced *before* clustering
> (`main.nf:98`). They are the "are these real cells" check. A UMAP always looks
> like *something* — even from junk — so confirm the QC first, then interpret the
> embedding.

### What "fixing" a QC issue looks like here

There is **no automatic parameter-tuning loop** for scRNA-seq QC (unlike the ADMET
auto-loop). QC issues here are threshold or wet-lab problems you correct and re-run:

- Too many cells filtered → your `min_genes` or `max_pct_mito` may be too strict
  for the tissue; loosen and re-run.
- A whole sample high on %mito → a dissociation/handling problem — flag the sample,
  don't just raise the threshold to keep it.
- Half the cells called doublets → chip over-loading; a wet-lab fix for the next run.

## Worked example (gold standard)

**Goal.** Cluster and annotate a benchmark scRNA-seq dataset where the *right
answer is known*, and read the artifact as a biologist would.

**Dataset.** **10x PBMC 10k v3** — the canonical human peripheral-blood mononuclear
cell reference (~10,000 cells, 10x Chromium v3 chemistry). The annotation ground
truth is the Azimuth PBMC reference (Hao et al., *Cell* 184:3573, 2021), so we can
score whether the pipeline's cell-type calls match the published atlas, not just
eyeball the UMAP.
(`evaluation/tutorial_demos/gold_standards.yaml:17-26`;
`s3://biomate-workflow-inputs/tutorial-gold/single_cell/pbmc_10k_v3/`.)

**Prompt** (the recorded tutorial):

> "Run single-cell analysis from Cell Ranger output."

**What comes back and how to read it:**

- **Per-cell QC (`qc_metrics.csv` + `qc_violin.png`).** The violin shows the
  healthy population; cells with < 200 genes or > 20% mito and scDblFinder
  doublets are removed. Interpretation: the cells that survive are real, single,
  healthy — your sanity anchor before any biology.
- **Integrated UMAP (`umap_celltypes.png`).** Distinct islands, coloured by
  celltypist call: T cells (CD4, CD8), NK, B, monocytes (CD14 / CD16), dendritic
  cells — the classic PBMC composition. Interpretation: the embedding recovers the
  known immune populations, well-separated.
- **Cell-type assignments (`celltype_assignments.csv`).** Per-cell labels from
  celltypist (`Immune_All_Low`). This is the artifact you carry forward — a
  per-cell table, not a picture.
- **Markers (`marker_genes_per_cluster.csv`).** Each cluster's top genes name it:
  *MS4A1/CD79A* → B cells, *CD3D/CD8A* → CD8 T, *NKG7/GNLY* → NK,
  *LYZ/CD14* → monocytes. Interpretation: the markers *confirm* the automated
  labels — you don't take celltypist on faith, you check the genes.
- **The ground-truth check.** Scoring the celltypist calls against the Azimuth PBMC
  reference gives a **macro-F1** the gold-standard target sets at **≥ 0.85**
  (`gold_standards.yaml:24-26`). Interpretation: the pipeline names the major
  populations at the published standard, so you can trust it on your own samples.

**The artifact.** An `annotated.h5ad` + `celltype_assignments.csv` +
`marker_genes_per_cluster.csv` + the UMAP. You end on a decision — *these are the
populations, here are the markers that name them, at reference-grade agreement* —
which is the "gold-standard-comparable artifact" the manual mandates.

> **Note (verification tier).** The pipeline stages, workflow IDs (12777 / 11653),
> QC-param defaults, sidecar emission, chains, and routing/guard are
> **code-verified (C)** by reading source (citations above). The numeric outcome
> (macro-F1 ≥ 0.85, the PBMC composition) is the **gold-standard demo target**
> (`gold_standards.yaml`); a **fresh live AWS Batch re-run** to reproduce it — and
> to emit the sidecar that lights up the in-app panel — is **pending (L / ⏳)** and
> was not fired (Batch runs cost real money; the plan forbids speculative
> execution).

## Outputs & visualization

Every output renders in the after-run panel's Outputs section via the in-app viewer
taxonomy (see **I.8 — Outputs, viewers & interactive panels**). The mapping below
is by file type.

| Output | File | In-app viewer | When to go interactive |
|---|---|---|---|
| **In-app single-cell panel** (UMAP + clusters + markers) | `annotated.h5ad` **+ `annotated.h5ad.summary.json` sidecar** | `SingleCellSummaryPanel` — dependency-free SVG UMAP coloured by cluster, cluster-composition bars, top markers (`single-cell-summary.tsx`) | Read populations + markers inline; **needs the sidecar** (see the honesty gate below) |
| Annotated object | `annotated.h5ad` | Single-cell preview (`step-output-preview.tsx:557`); falls back to CellxGene/Jupyter/download when no sidecar | Open in CellxGene for full interactive gating (where provisioned) |
| Cell-type assignments | `celltype_assignments.csv` | **Table** viewer (sortable, 200-row preview + full download) | Download to cross-tab cell type × condition |
| Marker genes per cluster | `marker_genes_per_cluster.csv` | **Table** viewer | Download for the marker figure; sort by cluster |
| Per-cell QC metrics | `qc_metrics.csv` | **Table** viewer | Read distributions; confirm before the UMAP |
| UMAP / QC / marker plots | `umap_celltypes.png`, `qc_violin.png`, `doublet_hist.png`, `marker_heatmap.png` | **Image** viewer (click-to-zoom) | Export PNG for the figure panel |
| Methods report | `methods_report.html` | **HTML iframe** viewer (sandboxed) | Read the parameters + citations inline |
| iSEE app | `isee_app.tar.gz` (chained id 11653) | Download / interactive launch | Full interactive Shiny exploration (environment-gated) |

> **QC gate / honesty (⏳) — the in-app UMAP panel needs the pipeline sidecar.**
> The single-cell panel is **wired and verified in the frontend** (tier C:
> `single-cell-summary.tsx`, `step-output-preview.tsx:589`), but it only draws when
> the pipeline has written `annotated.h5ad.summary.json` with useful content
> (clusters, UMAP points, or markers). The sidecar comes from **STAGE 6.5** of the
> `.nf`, which is **optional + fail-soft**: if it can't be produced, the run is
> unaffected and the panel simply doesn't appear (`main.nf:66-69,139`). On the
> frontend side, an absent/empty sidecar makes the panel **self-hide** and call
> `onAbsent` (`single-cell-summary.tsx:66-71`), and the parent falls back to the
> CellxGene / Jupyter / download path (`step-output-preview.tsx:589,592-623`).
> **Until a real scRNA run emits that sidecar end-to-end, expect the fallback (the
> `umap_celltypes.png` image + download) rather than the interactive in-app UMAP.**
> This is tracked as **L / ⏳** in the ledger — the FE is done, the data path is
> pending a live run. See I.8 for the full sidecar honesty gate.

> **Tip — read the tables in-app, don't re-plot.** `celltype_assignments.csv` and
> `marker_genes_per_cluster.csv` render sortable in the panel (200-row preview +
> full download). You rarely need to open a notebook just to see which genes name a
> cluster. Go interactive (CellxGene / Jupyter) only to re-gate or re-cluster — and
> only where those tools are provisioned (see *What's not covered*).

## Pitfalls & tips

> **Pitfall — bulk vs single-cell is a statistical fork, not a preference.**
> Running DESeq2 on individual cells inflates false positives (cells from one donor
> aren't independent). If your input is 10x / Cell Ranger / `.h5ad`, say
> "single-cell" so the router's context guard sends you to the single-cell chain,
> which does **pseudobulk** DE (aggregate per donor × cell type). See
> `unified_workflow_search.py:2620-2657` and the Transcriptomics chapter.

> **Pitfall — "cell types" / "clustering" alone won't route you here.** Those words
> are deliberately excluded from the single-cell trigger (bulk deconvolution uses
> them too). Name the assay — "single-cell", "10x", "Cell Ranger", ".h5ad".

> **Pitfall — the in-app UMAP needs the sidecar.** On a real run the interactive
> in-app UMAP appears only once STAGE 6.5 has written `annotated.h5ad.summary.json`.
> If you don't see it, you're on the fail-soft fallback — open `umap_celltypes.png`
> (the static plot always ships) or the object in CellxGene. This is expected until
> the sidecar is live end-to-end (L / ⏳).

> **Tip — set %mito to 10% for immune / PBMC samples.** The `.nf` default is a
> permissive 20% (`main.nf:39`) chosen so mito-rich tissues (brain/liver) aren't
> over-filtered. For a standard immune sample the textbook cut is 10%
> (`qc_evidence.yaml:1460`) — lower it yourself for a stricter QC.

> **Tip — start from the object if you have it.** Alignment (STARsolo/alevin on
> Batch) is the expensive step. If you already have a Cell Ranger `.h5ad`, enter the
> downstream chain and skip straight to QC + clustering.

> **Tip — confirm automated labels with the markers.** celltypist gives you a fast
> first-pass annotation; `marker_genes_per_cluster.csv` is how you *verify* it.
> A cluster labelled "B cell" should show *MS4A1 / CD79A* — if the markers don't
> match the label, trust the markers and flag the call.

## What's not covered

Honest scope — these are **not** claimed as present in this chapter; they live in
**Appendix E (Coverage & roadmap)**:

- **The in-app UMAP panel on real runs.** The frontend panel is verified (tier C),
  but it depends on the pipeline emitting a populated `annotated.h5ad.summary.json`
  sidecar on a live run. Until a real scRNA Batch run emits it end-to-end, the
  fallback (static `umap_celltypes.png` + CellxGene/Jupyter/download) is what you'll
  see. Tracked **L / ⏳**.
- **Live gold-standard numbers.** The PBMC 10k macro-F1 ≥ 0.85 is the demo target,
  not a fresh live measurement — no AWS Batch run was fired for this chapter
  (**L / ⏳**).
- **An scRNA auto-loop / auto-remediation.** Unlike the ADMET chapter, there is no
  automatic parameter-tuning loop for single-cell QC fails. Over-/under-filtering is
  surfaced for you to correct (threshold or wet-lab) and re-run — the fix is manual.
- **spatial transcriptomics, scATAC-seq, CITE-seq / multimodal ADT, and trajectory
  as a documented worked example.** Related workflows exist in the catalog
  (`scrna_adt_multimodal_via_scrapper`, the trajectory step in
  `single_cell_multimodal_analysis`, `screpertoire_integrated_single_cell_analysis`,
  etc.) and route, but this chapter documents only the standard cluster→annotate and
  pseudobulk-DE paths end-to-end. The others are available-but-undocumented
  (roadmap) — treat them as such until a dedicated section lands.
- **Interactive tools (iSEE / CellxGene / Jupyter) launch on dev.** These are **not
  provisioned** on the dev environment (the availability probe returns
  `available:false`); the launch buttons correctly hide and the launcher blocks. In-app
  viewers cover reading outputs; interactive re-analysis is environment-dependent.
  See I.8.
- **Batch (multi-run fan-out).** No Batch multi-sample fan-out views are documented here.

---
_Verification: this page depends on the coverage-ledger rows under
**"## Single-cell RNA-seq"** — the `scrnaseq_standard_endtoend` `.nf` stages 1–7 +
outputs (`annotated.h5ad`, `celltype_assignments.csv`, `marker_genes_per_cluster.csv`,
`qc_metrics.csv`, `umap_celltypes.png`, Methods report) (C, file:line), the STAGE 6.5
`annotated.h5ad.summary.json` fail-soft sidecar (C), QC param defaults
min_genes=200 / max_pct_mito=20 / doublet=0.3 with the evidence-vs-`.nf` mito mismatch
(C 🔧), the sub-workflow call to nf-core/scrnaseq 12777 + iSEE 11653 (C), the chains
`scrnaseq_standard_to_isee` / `single_cell_multimodal_analysis` / `scrna_pseudobulk_de_bioc`
(C, DB + index script), the single-cell context guard + bulk-vs-single-cell split
(C, `unified_workflow_search.py:2620-2657`), the in-app single-cell panel FE wiring
(C, `single-cell-summary.tsx` / `step-output-preview.tsx:589`) with its **data-gated
L / ⏳** sidecar dependency, the PBMC 10k gold-standard artifact + macro-F1 ≥ 0.85
target (C from `gold_standards.yaml`; live-Batch re-run L / ⏳), and the roadmap/gap
rows (🗺️). No Batch runs fired._
