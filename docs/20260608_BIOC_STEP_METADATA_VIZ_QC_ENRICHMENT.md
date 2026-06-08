# Bioconductor — per-step Visualizations + QC enrichment & step-parser gap fix (2026-06-08)

## Problem
The all-validated E2E (`bioconductor-all-validated.e2e.ts`) exposed two gaps for the 347
real-execution-validated Bioconductor workflows:

1. **No-steps gap** — 141/347 `.nf` files were **missing from the main tree** (corpus lives in
   the `bioc-fix` worktree; main had 206). `/api/nextflow/steps` re-parses the `.nf` from disk,
   so those 141 returned **0 steps → empty panel**.
2. **Viz/QC barely populated** — of the 347, only **20 had any per-step visualization** and
   **31 any per-step QC**. The user's directive: *"per-step visualizations (PCA plot) + QC —
   this is not done for all, double check to enrich."*

## Root causes
- **Steps endpoint re-parsed the `.nf`** instead of using the curated DB `step_metadata` that
  prior rounds already filled. For non-`main`/missing files the parser yields 0.
- **`extract_r()` end-marker was stale**: the corpus-wide versions fix replaced
  `cat <<-END_VERSIONS` with R `writeLines`, so `extract_r` matched nothing → `step_meta`
  returned empty for the *current* corpus (the existing DB metadata predated that conversion).
- **Vocab too narrow**: `VIZ_FUNCS` only caught *named* functions (`plotPCA`, `dotplot`) and
  missed generic plotting (`ggplot`/`ggsave`/`pdf(`/`pheatmap`/volcano) and all single-cell
  plots; `QC_PATTERNS` missed doublet/scater/normalization/clustering QC.
- **Two step formats**: v3 workflows use `# N.` R section comments; ~88 use only a `// Steps:`
  header; ~49 old-style have neither.

## Fixes
### Endpoint — serve the collected DB `step_metadata` (`nextflow_executor.py`)
- New `_steps_from_db_metadata(nextflow_path)`: for `/bioconductor/<pkg>/<wf>.nf`, reads the DB
  `step_metadata` (carries per-step **phase + visualizations + QC + outputs**) and builds viewer
  steps. `/api/nextflow/steps` now **prefers the DB metadata whenever present** (the parser does
  not emit viz/QC); parser stays the fallback for nf-core/drug_discovery/non-indexed paths.
- Robust to the missing-file case (no disk read needed).

### Enrichment — `extract_r` + vocab + multi-format step extraction
(`backend/scripts/enrich_bioc_viz_qc.py`, `enrich_bioc_step_metadata.py`)
- **`extract_r`** now grabs R from the `script: """ … """` block (Rscript shebang → closing
  `"""`), with the legacy `END_VERSIONS` path as fallback.
- **`VIZ_FUNCS`** +single-cell (plotUMAP/plotTSNE/DimPlot/FeaturePlot/VlnPlot/plot_cells/…).
- **`FIG_HINTS` + `viz_from_figure_files`**: when a step writes a figure but no *named* viz
  matched, derive a specific label from the **output filename** (`pca_plot.pdf` → "PCA plot",
  `umap.png` → "UMAP plot", volcano/heatmap/…); generic `plot` only as last resort.
- **`QC_PATTERNS`** +doublet detection (scDblFinder/findDoubletClusters), cell QC metrics
  (calculateQCMetrics/scater/emptyDrops), normalization, HVG selection, clustering QC,
  alignment/array-detection QC.
- **Three-tier step extraction** in `step_meta`: (1) `# N.` R sections → per-section viz/QC;
  (2) no sections → build from `// Steps:` header, attach whole-R viz/QC/outputs to the
  semantically-matching step; (3) neither → synthesize a single analysis step carrying the
  whole-R viz/QC so plots/QC still surface. All derived from **real R** — never faked.

### Corpus sync
Copied the 141 missing validated `.nf` from the `bioc-fix` worktree into the main tree so the
product can both **render and run** all 347 (was 206 present → now 347/347).

## Results (validated set, n=347)
| metric | before | after |
|---|---|---|
| `.nf` present in main tree | 206 | **347** |
| per-step `step_metadata` non-empty | 233 | **346** |
| per-step ≥1 visualization | 20 | **271** |
| per-step ≥1 QC | 31 | **60** |
| workflow-level `visualization_tools` | — | 275 |
| workflow-level `qc_steps` | — | 71 |

**Honesty check:** 0 workflows with QC *code* still show empty `qc_steps` (no vocab misses); the
~76 without viz are genuinely data-conversion/annotation packages.

**E2E:** `bioconductor-all-validated.e2e.ts` — **served=347/347, with-steps=347/347**, soft floor
raised to a hard `≥95%`. Live-verified: `absseq/main` (3 header steps), `enhancedvolcano/main`
(synth step, "volcano plot" + "low-count filtering"), `scdblfinder/find_doublet_clusters`
(7 steps, per-step t-SNE/cluster/doublet-QC).

## Known follow-ups
- **49 old-style validated workflows** (no `// Steps:` header, not v3 `Document-derived`) get a
  single synthesized step. Proper fix = regenerate them via `generate_bioc_workflows_v3.py`
  (gives real input-consuming multi-stage R + header + sections). Listed in the residual audit.
- DB (`galaxy_ai_tools.db`) is untracked; enrichment is re-runnable via the two scripts.

## Files
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` (main repo) — endpoint + helper
- `backend/scripts/enrich_bioc_viz_qc.py`, `enrich_bioc_step_metadata.py` (bioc-fix worktree)
- `frontend/e2e/bioconductor-all-validated.e2e.ts` — `__dirname`→`import.meta.url`, hard ≥95% floor
- 141 new `.nf` under `backend/biomni_workflows/.../bioconductor/`
