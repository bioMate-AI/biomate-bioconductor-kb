# Single-Cell Workflow Implementation Requirement — 3 New Workflows

**Date:** 2026-06-16
**For:** engineering / bioc-fix workstream
**Companion docs:**
- `docs/20260616_SINGLE_CELL_DESIGN_REFERENCE_PACKET.md` — DB schema, phase taxonomy, gates
- `docs/20260616_SC_TUTORIAL_DEMO_DESIGN_REQUIREMENT.md` — the design/recording contract that consumes these workflows

This document is the **engineering contract** for building three single-cell workflows that fill confirmed coverage gaps. These workflows are the substrate for the Merck-pilot tutorial demos (Doc B). Both docs must be satisfied — the demo cannot be faked from design alone; the workflows must actually execute end-to-end on AWS Batch.

## Decisions locked

| # | Question | Decision | Rationale |
|---|---|---|---|
| 1 | Spec 1 — call `nf-core/scrnaseq` (id 12777) as sub-workflow or fork? | **Sub-workflow call** via `include { SCRNASEQ } from '../../subworkflows/nf-core/scrnaseq/main'` | upstream sync; isolates novel logic in our composer |
| 2 | Spec 2 — T2 CPU or T3 GPU? | **T2 CPU 16 vCPU / 64 GB Balanced** | survey concluded `mgcv::gam` is CPU-only; no CUDA path exists for tradeSeq / condiments / monocle3 / Lamian; memory is the ceiling, not FLOPs (refs: [mgcv-parallel](https://stat.ethz.ch/R-manual/R-devel/library/mgcv/html/mgcv-parallel.html); [tradeSeq #245](https://github.com/statOmics/tradeSeq/issues/245); [Van den Berge 2020](https://www.nature.com/articles/s41467-020-14766-3)) |
| 3 | Spec 3 — bundle OmniPath cache or fetch live? | **Short-term: bundle `omnipath_resource.parquet` in docker image. Long-term: fix `OmnipathR` (id 11975, `exec_error`) + stand up versioned LR-resource S3 cache + fall back to live fetch if cache stale.** | OmnipathR is in bioc-fix queue. P0–P3 staged plan below. |
| 4 | Acceptance dataset | **Jerby-Arnon GSE115978 melanoma** across all 3 workflows | one coherent dataset arc validates the 3-workflow handoff chain in one engineering smoke run |

## OmnipathR / LR-resource roadmap (decision #3 expanded)

| Phase | Action | When | Owner |
|---|---|---|---|
| P0 | Triage OmnipathR (id 11975) error (likely missing R package per §earlier 33-broken categorization); target `ok` status | this sprint | bioc-fix |
| P1 | Stand up internal "LR-resource cache" S3 bucket refreshed weekly via cron (single source of truth for LIANA + future CellChat + NicheNet) | 2026 Q3 | infra |
| P2 | Version stamps on resource: `omnipath@2026.06`, `cellchatdb@2026.06`; embedded in Methods Report for reproducibility | 2026 Q3 | infra |
| P3 | Inference workflows default-read from cache; fall back to live OmnipathR if cache stale | 2026 Q4 | infra |

Pattern maps directly onto the **drug-entity resolution layer** from the data-moat plan — single canonical reference cache, all consumers point at it, versioned, audit-trail-ready.

---

## Spec 1 — `scrnaseq_standard_endtoend`

### Identity
- **Workflow ID to assign:** 14435
- **Domain:** `single_cell`
- **Format:** `nextflow_nf`
- **Source:** `custom_composer` (sub-workflow include of `nf-core/scrnaseq` id 12777)
- **Docker image:** `bioconductor/scrnaseq-standard:v1` — Bioc 3.20, Scanpy 1.10, scDblFinder 1.18, harmony-pytorch 0.1.7, celltypist 1.6, `procps`
- **Composer pattern:** sub-workflow include of 12777 for alignment; our `.nf` modules for QC / integration / annotation / iSEE chaining

### Inputs (`params_schema.data_inputs[]`)

| name | type | optional | description |
|---|---|---|---|
| `fastq_dir` | `directory` | false | 10X paired-end fastq (`*_R1_001.fastq.gz`, `*_R2_001.fastq.gz`) |
| `samplesheet.csv` | `csv` | false | nf-core format: `sample,fastq_1,fastq_2,expected_cells` (+ optional `patient`, `lesion_type`) |
| `reference_genome` | `fasta` | false | Default GRCh38 |
| `gtf_annotation` | `gtf` | false | Default GENCODE v44 |

### Params (`params_schema.param_inputs[]`)

| name | type | default | range | description |
|---|---|---|---|---|
| `species` | `enum` | `human` | `human` \| `mouse` | drives celltypist model default |
| `aligner` | `enum` | `starsolo` | `starsolo` \| `cellranger` \| `salmon_alevin` | quantifier |
| `min_genes_per_cell` | `int` | 200 | 100–1000 | drop low-quality cells |
| `max_pct_mito` | `float` | 20 | 5–50 | drop dying cells |
| `doublet_score_threshold` | `float` | 0.3 | 0.1–0.6 | scDblFinder cutoff |
| `n_hvgs` | `int` | 2000 | 500–5000 | for embedding |
| `n_pcs` | `int` | 50 | 10–100 | embedding dim |
| `harmony_batch_key` | `string` | `sample` | column-name | accepts `patient` for Merck dataset |
| `leiden_resolution` | `float` | 0.5 | 0.1–2.0 | cluster resolution |
| `celltypist_model` | `enum` | `Immune_All_Low` | celltypist registry | for TME: `Immune_All_High` |

### Steps (`step_metadata[]`)

```json
[
  {"step": "Validate samplesheet + locate fastq pairs", "phase": "Input & Preparation",
   "outputs": [], "visualizations": [], "qc": []},
  {"step": "Sub-workflow call: nf-core/scrnaseq (id 12777) — alignment + quantification",
   "phase": "Core Analysis",
   "subworkflow_call": {"workflow_id": 12777, "include_path": "subworkflows/nf-core/scrnaseq/main"},
   "outputs": [{"file":"counts_matrix.h5ad","kind":"object"},
               {"file":"multiqc_report.html","kind":"report"}],
   "visualizations": [{"title":"Alignment summary","src":"multiqc_report.html","kind":"html"}],
   "qc": [{"metric":"pct_reads_assigned","threshold":50,"direction":"gte","gate_action":"halt"},
          {"metric":"pct_reads_in_cells","threshold":30,"direction":"gte","gate_action":"halt"}]},
  {"step": "Per-cell QC + scDblFinder doublet filter", "phase": "QC & Filtering",
   "outputs": [{"file":"cells_passing_qc.h5ad","kind":"object"},
               {"file":"qc_metrics.csv","kind":"table"}],
   "visualizations": [{"title":"Violin: n_genes, n_counts, pct_mito","src":"qc_violin.png","kind":"image"},
                      {"title":"Doublet score distribution","src":"doublet_hist.png","kind":"image"}],
   "qc": [{"metric":"cells_post_qc","threshold":500,"direction":"gte","gate_action":"halt"},
          {"metric":"median_genes_per_cell_post_qc","threshold":1000,"direction":"gte","gate_action":"advisory"}]},
  {"step": "Normalize + log + HVGs + scale", "phase": "Core Analysis",
   "outputs": [{"file":"normalized.h5ad","kind":"object"}], "visualizations": [], "qc": []},
  {"step": "PCA + Harmony batch integration", "phase": "Core Analysis",
   "outputs": [{"file":"integrated.h5ad","kind":"object"}],
   "visualizations": [{"title":"PC variance explained","src":"pc_variance.png","kind":"image"},
                      {"title":"Harmony before/after","src":"harmony_compare.png","kind":"image"}],
   "qc": [{"metric":"silhouette_after_harmony","threshold":0.0,"direction":"gte","gate_action":"advisory"}]},
  {"step": "Leiden clustering + UMAP", "phase": "Annotation & Interpretation",
   "outputs": [{"file":"clustered.h5ad","kind":"object"},{"file":"umap_coords.csv","kind":"table"}],
   "visualizations": [{"title":"UMAP by cluster","src":"umap_clusters.png","kind":"image"},
                      {"title":"UMAP by sample","src":"umap_samples.png","kind":"image"}],
   "qc": [{"metric":"n_clusters","threshold":3,"direction":"gte","gate_action":"advisory"}]},
  {"step": "Cell-type annotation via celltypist", "phase": "Annotation & Interpretation",
   "outputs": [{"file":"annotated.h5ad","kind":"object"},{"file":"celltype_assignments.csv","kind":"table"},
               {"file":"marker_genes_per_cluster.csv","kind":"table"}],
   "visualizations": [{"title":"UMAP by cell type","src":"umap_celltypes.png","kind":"image"},
                      {"title":"Marker gene heatmap","src":"marker_heatmap.png","kind":"image"}],
   "qc": [{"metric":"mean_celltypist_confidence","threshold":0.6,"direction":"gte","gate_action":"advisory"}]},
  {"step": "Render iSEE app + Methods HTML", "phase": "Output & Reporting",
   "downstream_workflow_calls": [
     {"workflow_id": 11653, "name": "iSEE", "inputs": {"sce_rds": "annotated.h5ad"},
      "produces": ["isee_app.tar.gz"]}
   ],
   "outputs": [{"file":"methods_report.html","kind":"report"}],
   "visualizations": [], "qc": []}
]
```

### Output contract
- `annotated.h5ad` — required (counts + UMAP + cell types + sample/patient metadata)
- `methods_report.html` — required (param table, QC trace, Harmony / scDblFinder / celltypist citations)
- `celltype_assignments.csv`, `marker_genes_per_cluster.csv`, `qc_metrics.csv` — required
- `isee_app.tar.gz` (from chained id 11653) — recommended

### Auto-loop QC gates with remediation

| Gate | Direction | Threshold | Action | Remediation |
|---|---|---|---|---|
| `pct_reads_assigned` | `gte` | 50% | halt | switch `aligner=salmon_alevin` |
| `pct_reads_in_cells` | `gte` | 30% | halt | suggest CellBender background-removal pre-step |
| `cells_post_qc` | `gte` | 500 | halt | relax `min_genes_per_cell` 200→100; `max_pct_mito` 20→25 |
| `median_genes_per_cell_post_qc` | `gte` | 1000 | advisory | surface to user |
| `silhouette_after_harmony` | `gte` | 0.0 | advisory | bump `n_pcs` 50→100 |
| `n_clusters` | `gte` | 3 | advisory | bump `leiden_resolution` 0.5→0.8 |
| `mean_celltypist_confidence` | `gte` | 0.6 | advisory | swap `celltypist_model` to tissue-matched |

### Acceptance criteria

| Test | Dataset | Tier | Wall time | Cost | Pass condition |
|---|---|---|---|---|---|
| Smoke | `10x_pbmc1k` (1K cells, public) | T2 hybrid | ~25 min | ~$1.50 | 800–1000 cells survive QC; 6–10 clusters; PBMC types present (T, B, NK, mono, DC, platelet); `methods_report.html` ≥ 5KB |
| Real | Jerby-Arnon GSE115978 (~7K cells, 33 patients) | T3 hybrid | ~70 min | ~$5 | Tumour cells + Treg + exhausted-CD8 (LAG3+) + macrophage + endothelial + CAF identified; Harmony resolves batch by `patient` (silhouette > 0.1) |
| Auto-loop | low-quality patient (300 cells passing QC) | T2 | — | — | `cells_post_qc` halts; remediation card surfaces param diff; re-run completes |

### Known pitfalls
- API field is `parameters:` not `params:` (Pydantic silently drops wrong key)
- Docker layer must include `procps` (Nextflow `ps` call → exit 127)
- `celltypist` model download requires internet egress from Batch worker → VPC endpoint or NAT
- `harmony_batch_key` must match an `adata.obs` column → silent NaN otherwise; validate at submit
- Quay biocontainer tag flakes — pin SHA, not version tag

---

## Spec 2 — `scrnaseq_trajectory_pseudotime`

### Identity
- **Workflow ID:** 14436
- **Domain:** `single_cell`
- **Format:** `nextflow_nf`
- **Source:** `custom`
- **Docker image:** `bioconductor/sc-trajectory:v1` — Bioc 3.20, slingshot 2.10, tradeSeq 1.16, condiments 1.10, mgcv 1.9, BiocParallel, `procps`
- **Compute tier:** T2 CPU 16 vCPU / 64 GB Balanced (locked per decision #2)

### Inputs

| name | type | optional | description |
|---|---|---|---|
| `annotated.h5ad` | `h5ad` | false | Output of Spec 1 or any clustered + annotated SC object |
| `condition_labels.csv` | `csv` | true | 2-col `cell_id,condition` for condiments comparison |

### Params

| name | type | default | range | description |
|---|---|---|---|---|
| `start_cluster` | `string` | (required if no `start_celltype`) | column value | trajectory start cluster |
| `start_celltype` | `string` | (required if no `start_cluster`) | column value | OR specify by cell-type |
| `embedding` | `enum` | `X_umap` | `X_umap` \| `X_pca` \| `X_diffmap` | trajectory-fit space |
| `n_top_hvgs_for_trajectory` | `int` | 2000 | 500–5000 | HVG subset (RAM-bound) |
| `extend_curves` | `enum` | `y` | `y` \| `n` | Slingshot curve extension |
| `n_knots_gam` | `int` | 6 | 3–10 | tradeSeq GAM basis |
| `fdr_threshold` | `float` | 0.05 | 0.001–0.2 | DE table FDR cutoff |
| `condiments_test` | `enum` | `none` | `none` \| `topology` \| `progression` \| `differentialFateSelection` | comparison test |
| `bpparam_workers` | `int` | **4** (locked) | 2–8 | RAM-per-worker dominates (#245) |
| `lineage_split_threshold` | `int` | **20000** | — | if cells > this, fit each lineage separately |

### Steps (`step_metadata[]`)

```json
[
  {"step": "Load + validate h5ad (must have cluster + embedding)", "phase": "Input & Preparation",
   "outputs": [], "visualizations": [],
   "qc": [{"metric":"has_cluster_col","threshold":1,"direction":"eq","gate_action":"halt"}]},
  {"step": "HVG subset + build SingleCellExperiment", "phase": "Input & Preparation",
   "outputs": [{"file":"sce_for_traj.rds","kind":"object"}], "visualizations": [], "qc": []},
  {"step": "Slingshot lineage fit", "phase": "Core Analysis",
   "outputs": [{"file":"slingshot_curves.rds","kind":"object"},
               {"file":"pseudotime_per_cell.csv","kind":"table"}],
   "visualizations": [{"title":"UMAP with Slingshot curves","src":"umap_slingshot.png","kind":"image"},
                      {"title":"UMAP coloured by pseudotime","src":"umap_pseudotime.png","kind":"image"}],
   "qc": [{"metric":"n_lineages","threshold":1,"direction":"gte","gate_action":"halt"},
          {"metric":"max_pseudotime_range","threshold":0.5,"direction":"gte","gate_action":"advisory"}]},
  {"step": "tradeSeq GAM fit (lineage-split if cells > lineage_split_threshold)", "phase": "Core Analysis",
   "outputs": [{"file":"tradeseq_gam.rds","kind":"object"}],
   "visualizations": [{"title":"GAM fit diagnostics","src":"gam_diag.png","kind":"image"}],
   "qc": [{"metric":"gam_convergence_rate","threshold":0.8,"direction":"gte","gate_action":"advisory"},
          {"metric":"peak_mem_gb","threshold":56,"direction":"lte","gate_action":"halt"}]},
  {"step": "Association + startVsEnd + earlyDE", "phase": "Annotation & Interpretation",
   "outputs": [{"file":"association_genes.csv","kind":"table"},
               {"file":"startvsend_genes.csv","kind":"table"},
               {"file":"earlyDE_genes.csv","kind":"table"}],
   "visualizations": [{"title":"Top association gene heatmap","src":"association_heatmap.png","kind":"image"},
                      {"title":"Selected gene trend panels","src":"gene_trends.png","kind":"image"}],
   "qc": [{"metric":"n_assoc_genes_fdr05","threshold":50,"direction":"gte","gate_action":"advisory"}]},
  {"step": "Optional condiments comparison", "phase": "Annotation & Interpretation",
   "outputs": [{"file":"condiments_result.csv","kind":"table"}],
   "visualizations": [{"title":"Trajectory differential test","src":"condiments_plot.png","kind":"image"}],
   "qc": []},
  {"step": "Methods report + per-lineage gallery", "phase": "Output & Reporting",
   "outputs": [{"file":"methods_report.html","kind":"report"},
               {"file":"trajectory_results.tar.gz","kind":"archive"}],
   "visualizations": [], "qc": []}
]
```

### Output contract
- `pseudotime_per_cell.csv`, `association_genes.csv`, `startvsend_genes.csv`, `earlyDE_genes.csv` — required
- `umap_slingshot.png`, `umap_pseudotime.png` — required
- `methods_report.html` — required (Slingshot Street 2018 + tradeSeq Van den Berge 2020 + condiments Roux de Bézieux 2024 citations)

### Auto-loop QC gates

| Gate | Direction | Threshold | Action | Remediation |
|---|---|---|---|---|
| `has_cluster_col` | `eq` | 1 | halt | rerun Spec 1 first |
| `n_lineages` | `gte` | 1 | halt | suggest alternate `start_cluster` |
| `max_pseudotime_range` | `gte` | 0.5 | advisory | include more clusters |
| `gam_convergence_rate` | `gte` | 80% | advisory | reduce `n_knots_gam` 6→4 |
| `peak_mem_gb` | `lte` | 56 | halt | enable lineage-split (`lineage_split_threshold=10000`); reduce `n_top_hvgs_for_trajectory` 2000→1000 |
| `n_assoc_genes_fdr05` | `gte` | 50 | advisory | relax `fdr_threshold` 0.05→0.1 |

### Acceptance criteria

| Test | Dataset | Tier | Wall time | Cost | Pass condition |
|---|---|---|---|---|---|
| Smoke | `paul15` (2730 cells, public Slingshot ref) | T1 CPU | ~10 min | ~$0.30 | 2–3 lineages (GMP/MEP/LMPP); ~200 association genes at FDR 0.05 |
| Real | Jerby-Arnon CD8 T-cell subset (~3K cells, start `Naive-CD8`) | T2 CPU | ~25 min | ~$0.80 | Exhausted-CD8 lineage detected; PDCD1, TIGIT, TOX, LAG3 in top 50 early-DE genes |
| Auto-loop | 25K-cell input (forced) | T2 | — | — | `peak_mem_gb` halt; remediation enables lineage_split; re-run completes |

### Known pitfalls
- Slingshot needs SCE not AnnData — bundle conversion inside (don't depend on `zellkonverter` id 12641 which is `exec_error`)
- tradeSeq each `BiocParallel` worker copies count matrix (#245) → workers=4 locked
- `condiments::topologyTest` needs ≥3 cells per cluster × condition

---

## Spec 3 — `scrnaseq_cellcell_communication`

### Identity
- **Workflow ID:** 14437
- **Domain:** `single_cell`
- **Format:** `nextflow_nf`
- **Source:** `custom` — inference layer only; viz delegated to existing tested workflows
- **Docker image:** `python-singlecell/liana-plus:v1` — Python 3.11, `liana[full]` 1.5, `decoupler-py` 1.6, `omnipath` 1.0, `mudata` 0.2, bundled `omnipath_resource.parquet` + `cellchatdb_v2.parquet` cache, `procps`

### Inputs

| name | type | optional | description |
|---|---|---|---|
| `annotated.h5ad` | `h5ad` | false | Must contain `adata.obs.celltype` |
| `omnipath_resource` | `bool` | true | If true, fetches live via OmnipathR (id 11975); else uses bundled cache. Default false until OmnipathR fixed. |

### Params

| name | type | default | range | description |
|---|---|---|---|---|
| `celltype_key` | `string` | `celltype` | column | annotation column |
| `condition_key` | `string` | (none) | column | condition-stratified comparison (e.g. Jerby-Arnon `lesion_type`) |
| `methods` | `multi_enum` | `["consensus"]` | `consensus,natmi,cellphonedb,sca,connectome,logfc,cellchat` | LIANA+ methods |
| `min_cells_per_celltype` | `int` | 10 | 5–100 | celltype filter |
| `resource_name` | `enum` | `consensus` | `consensus,omnipath,cellchatdb,cellphonedb,baccin2019,mouseconsensus` | LR resource |
| `top_n_pairs` | `int` | 50 | 10–500 | pairs per source-target |
| `run_decoupler_followup` | `bool` | true | — | LR activity → TF activity |
| `assume_raw_counts` | `bool` | true | — | guard against log-normalized input |

### Steps (`step_metadata[]`)

```json
[
  {"step": "Validate input: celltype col + min cells per type + raw counts", "phase": "Input & Preparation",
   "outputs": [], "visualizations": [],
   "qc": [{"metric":"has_celltype_col","threshold":1,"direction":"eq","gate_action":"halt"},
          {"metric":"n_valid_celltypes","threshold":3,"direction":"gte","gate_action":"halt"},
          {"metric":"mean_X_modulus_check","threshold":50,"direction":"gte","gate_action":"halt"}]},
  {"step": "Load LR resource (bundled cache default; live OmniPathR if opt-in)",
   "phase": "Input & Preparation",
   "outputs": [{"file":"resource.csv","kind":"table"}], "visualizations": [],
   "qc": [{"metric":"n_lr_pairs_loaded","threshold":500,"direction":"gte","gate_action":"halt"},
          {"metric":"resource_version_stamp","threshold":1,"direction":"eq","gate_action":"advisory"}]},
  {"step": "Run LIANA+ scoring", "phase": "Core Analysis",
   "outputs": [{"file":"liana_results.csv","kind":"table"},
               {"file":"liana_consensus.parquet","kind":"object"}],
   "visualizations": [], "qc": []},
  {"step": "Aggregate + rank pairs across methods + emit CCPlotR-format TSV",
   "phase": "Annotation & Interpretation",
   "outputs": [{"file":"top_lr_pairs.csv","kind":"table"},
               {"file":"liana_for_ccplotr.tsv","kind":"table"}],
   "visualizations": [], "qc": []},
  {"step": "Condition-stratified comparison (optional)", "phase": "Annotation & Interpretation",
   "outputs": [{"file":"condition_diff_lr.csv","kind":"table"}],
   "visualizations": [{"title":"Condition diff volcano","src":"condition_diff_volcano.png","kind":"image"}],
   "qc": []},
  {"step": "decoupler TF-activity follow-up (optional)", "phase": "Annotation & Interpretation",
   "outputs": [{"file":"tf_activity_per_target.csv","kind":"table"}],
   "visualizations": [{"title":"TF activity heatmap","src":"tf_activity_heatmap.png","kind":"image"}],
   "qc": []},
  {"step": "Emit handoff TSV + chain to viz workflows", "phase": "Output & Reporting",
   "outputs": [{"file":"methods_report.html","kind":"report"},
               {"file":"liana_results.tar.gz","kind":"archive"}],
   "visualizations": [],
   "qc": [],
   "downstream_workflow_calls": [
     {"workflow_id": 11052, "name": "CCPlotR (status: ok_warnings)",
      "inputs": {"interactions_tsv": "liana_for_ccplotr.tsv"},
      "produces": ["cc_heatmap.png","cc_dotplot.png","cc_network.png"]},
     {"workflow_id": 11646, "name": "InterCellar (status: ok_warnings)",
      "inputs": {"interactions_tsv": "liana_for_ccplotr.tsv"},
      "produces": ["intercellar_shiny_app.tar.gz"]}
   ]}
]
```

### Output contract (this workflow produces)
- `liana_results.csv`, `top_lr_pairs.csv`, `liana_for_ccplotr.tsv` — required
- `methods_report.html` — required (Dimitrov 2022 LIANA + Türei 2021 OmniPath + Browaeys 2020 NicheNet citations)
- `tf_activity_per_target.csv` (optional)
- `condition_diff_lr.csv` (optional)

Downstream-chained (produced by ids 11052 + 11646, not by this workflow):
- `cc_heatmap.png`, `cc_dotplot.png`, `cc_network.png`
- `intercellar_shiny_app.tar.gz`

### Auto-loop QC gates

| Gate | Direction | Threshold | Action | Remediation |
|---|---|---|---|---|
| `has_celltype_col` | `eq` | 1 | halt | rerun Spec 1 with celltypist |
| `n_valid_celltypes` | `gte` | 3 | halt | drop `min_cells_per_celltype` 10→5 |
| `mean_X_modulus_check` | `gte` | 50 | halt | log-normalized passed; require `adata.layers['counts']` raw |
| `n_lr_pairs_loaded` | `gte` | 500 | halt | flip `omnipath_resource=true` (post-OmnipathR-fix) |
| `resource_version_stamp` | `eq` | 1 | advisory | carry version into Methods Report |
| `mean_score_consensus` | `gte` | 0.0 | advisory | tissue-matched `resource_name` |

### Acceptance criteria

| Test | Dataset | Tier | Wall time | Cost | Pass condition |
|---|---|---|---|---|---|
| Smoke | Spec-1 PBMC output (3K cells, 6 celltypes) | T1 CPU | ~5 min | ~$0.20 | ~30 source-target pairs; CXCL12-CXCR4 (T-cell↔DC) in top-10 (Browaeys 2020 baseline) |
| Real | Jerby-Arnon melanoma TME (~7K cells, 9 celltypes, `lesion_type` set) | T2 CPU | ~25 min | ~$1 | Top pathways include PD-1/PD-L1, TIGIT-PVR, HLA-class-II-LAG3; condition-stratified test shows differential inhibitory signaling resistant vs naive |
| Auto-loop | log-normalized h5ad (forced) | T1 | — | — | `mean_X_modulus_check` halts; remediation points to `adata.layers['counts']`; re-run completes |
| Chain | LIANA+ → CCPlotR (11052) → InterCellar (11646) | end-to-end | ~30 min | ~$1.20 | all 3 chained outputs produced; user can navigate from LIANA+ Methods Report to CCPlotR heatmap to InterCellar Shiny app via the workflow panel handoff |

### Known pitfalls
- LIANA+ expects raw counts — `mean_X_modulus_check` gate is non-negotiable
- OmniPath rate-limits cold first-run on fresh Batch worker → bundled cache is default
- Chord diagrams (5–20 MB HTML) are NOT in this spec — delegated to CCPlotR + InterCellar
- Condition imbalance: gate on minimum cells per (celltype × condition); LIANA+ silently underpowers

---

## Cross-spec engineering checklist

| # | Item | Spec | Owner | Priority |
|---|---|---|---|---|
| 1 | Assign workflow IDs 14435 / 14436 / 14437 in DB | all | engineering | P0 |
| 2 | Build 3 docker images, push to ECR | all | engineering | P0 |
| 3 | Wire `nextflow_nfcore/subworkflows/single_cell/<name>/main.nf` | all | engineering | P0 |
| 4 | Stage Jerby-Arnon GSE115978 to S3 acceptance bucket | all | engineering | P0 |
| 5 | Stage `10x_pbmc1k` + `paul15` to S3 (already public; copy in) | 1, 2 | engineering | P0 |
| 6 | Spec 1: sub-workflow `include` of id 12777 verified | 1 | engineering | P0 |
| 7 | Spec 2: lock `BPPARAM=MulticoreParam(4)`, implement `lineage_split` for >20K cells | 2 | engineering | P0 |
| 8 | Spec 3: bundle `omnipath_resource.parquet` + `cellchatdb_v2.parquet` in docker image | 3 | engineering | P0 |
| 9 | Index in `workflows` table (full `step_metadata`, `params_schema`, `input_types`, `output_types`) | all | engineering | P0 |
| 10 | Smoke-test each on CE `biomate-nextflow-ce-v2` until `real_exec_status='ok'` | all | engineering | P0 |
| 11 | Add per-spec auto-loop gates to `qc_trace_monitor.py` | all | engineering | P0 |
| 12 | Add 3 routing few-shots to `galaxy-assistant.ts` | all | engineering | P0 |
| 13 | Tag iSEE (11653), CCPlotR (11052), InterCellar (11646) as "chainable downstream" in DB | 1, 3 | engineering | P0 |
| 14 | Fix OmnipathR (id 11975) — unblocks long-term P3 of decision #3 | 3 (optional live mode) | bioc-fix | P1 |
| 15 | Stand up LR-resource S3 cache + versioning | 3 (long-term) | infra | P1 |
| 16 | Confirm chained-call rendering in BioMate UI (sub-phase of parent, not separate workflow row) | all | frontend | P0 (demo blocker) |

## Acceptance gate

All three workflows must reach `real_exec_status='ok'` (or `ok_warnings`) on the smoke + real Jerby-Arnon acceptance tests before the corresponding tutorial demo (Doc B) can be recorded. **The demo cannot be faked from design alone.**
