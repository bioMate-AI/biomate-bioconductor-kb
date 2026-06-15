# Bioconductor orphan QC-row audit — Track 2 Batch 5

Date: 2026-06-15
Branch: `qc/coverage-and-rebuilds`
Source: `backend/config/qc_evidence.yaml`
Related: Phase 3a commit `1ab27c2f9` (23 new `bioconductor_qc:` rows),
       inventory plan `docs/20260615_QC_GATE_INVENTORY_AND_PLAN.md`.

## Background

Prior to Phase 3a, 14 Bioconductor metric entries existed in
`qc_evidence.yaml` under the transcriptomics / single_cell / epigenomics
domain sections. They have citations, `paper_supports`, and `rule_text`,
but **no workflow emits `qc_metrics.json` against them** — they are
orphan rows from earlier curation passes.

Phase 3a added 23 cross-domain `bioconductor_qc:` rows keyed by labels
in the `qc_steps` taxonomy already enriched into
`backend/database/galaxy_ai_tools.db` (396 workflows non-empty). These
new rows are the canonical home for *metric-level* gates that any Bioc
subworkflow can populate.

This audit reconciles the 14 orphans against the 23 new canonical rows.

## Classification scheme

- **(a) SUPERSEDED** — the orphan duplicates a more general
  `bioconductor_qc:` row. Mark `superseded_by: bioconductor_qc.<row>`,
  demote provenance to BRONZE, add a `note:` field. Citation kept for
  audit-trail continuity.
- **(b) PACKAGE-SPECIFIC** — the orphan is a per-package gate that no
  cross-domain row covers. Add `harness_owner: BIOC_QC_HARNESS` and
  `package: <name>`; route through the Phase 3b harness at package
  granularity.
- **(c) DEPRECATED** — citation invalid or metric folded into a
  different gate. (None found in this audit.)

## Audit table

| # | Entry | Section | Classification | Rationale | Canonical row / package |
|---|---|---|---|---|---|
| 1 | `apeglm_lfc_shrinkage` | transcriptomics | (b) PACKAGE | apeglm LFC shrinkage prior is specific to DESeq2 post-processing; no cross-domain row covers it | package=`apeglm` |
| 2 | `clusterprofiler_enrichment` | transcriptomics | (b) PACKAGE | GSEA/ORA enrichment; no `bioconductor_qc:` row covers pathway-enrichment QC | package=`clusterProfiler` |
| 3 | `edger_qlf_alternative` | transcriptomics | (b) PACKAGE | Alternative DE method (QLF); orthogonal to any cross-domain metric row | package=`edgeR` |
| 4 | `limma_voom_alternative` | transcriptomics | (b) PACKAGE | voom-as-DE-tool; distinct from the voom *fit-quality* metric in `bioc_voom_fit` | package=`limma` |
| 5 | `scater_qc_normalization` | single_cell | (a) SUPERSEDED | Same McCarthy 2017 scater citation; metric overlap with `bioc_per_cell_qc_outliers` (isOutlier, nmads=3) | `bioconductor_qc.bioc_per_cell_qc_outliers` |
| 6 | `mast_hurdle_de` | single_cell | (b) PACKAGE | MAST scRNA hurdle DE; no cross-domain row covers per-cluster DE methods | package=`MAST` |
| 7 | `monocle_pseudotime_de` | single_cell | (b) PACKAGE | Monocle3 pseudotime DE; no cross-domain analog | package=`monocle` |
| 8 | `scran_normalization_hvg` | single_cell | (a) SUPERSEDED | HVG-count metric subsumed by `bioc_hvg_selection`; normalization portion by `bioc_count_normalization` | `bioconductor_qc.bioc_hvg_selection` |
| 9 | `score_markers_per_cluster` | single_cell | (b) PACKAGE | scran::scoreMarkers per-cluster effect-size scoring; `bioc_clustering_qc` covers silhouette/ARI, not marker scoring | package=`scran` |
| 10 | `singler_celltype_annotation` | single_cell | (b) PACKAGE | Reference-based cell-type labelling; no cross-domain row covers annotation QC | package=`SingleR` |
| 11 | `minfi_array_processing` | epigenomics | (a) SUPERSEDED | Detection-p QC subsumed by `bioc_array_detection_qc` (detection-call-rate, same diagnostic) | `bioconductor_qc.bioc_array_detection_qc` |
| 12 | `limma_dmp_test` | epigenomics | (b) PACKAGE | limma eBayes on M-values for methylation DMPs; `bioc_voom_fit` is RNA-seq-specific so does not subsume | package=`limma` |
| 13 | `dmrcate_region_call` | epigenomics | (b) PACKAGE | DMR region-caller; no cross-domain analog | package=`DMRcate` |
| 14 | `missmethyl_cpg_corrected_go` | epigenomics | (b) PACKAGE | CpG-bias-corrected GO; pedagogically distinct from generic enrichment | package=`missMethyl` |

## Summary

| Classification | Count | Action taken |
|---|---:|---|
| (a) SUPERSEDED | **3** | Demoted to BRONZE, added `superseded_by:` + `note:` |
| (b) PACKAGE-SPECIFIC | **11** | Added `harness_owner: BIOC_QC_HARNESS`, `package:`, `superseded_by: null` |
| (c) DEPRECATED | 0 | — |
| **Total** | **14** | |

## Phase 3b implications

The 11 package-specific entries become first-class targets for the
`BIOC_QC_HARNESS` Nextflow process template. The harness will:

1. Inspect the workflow's `qc_steps` declaration.
2. If a step's package matches a registered package gate (e.g.
   `apeglm`, `MAST`, `DMRcate`), route the gate's `rule_text` /
   threshold logic to a package-specific evaluator.
3. Otherwise fall back to the cross-domain `bioconductor_qc:` row
   keyed by label (where the 3 SUPERSEDED rows now point).

This keeps per-package gates accountable without duplicating the
cross-domain metric rows.

## No workflow code touched

Per scope, no `main.nf` files in `backend/biomni_workflows/` were
modified. This is pure YAML + doc work. Harness wiring is deferred
to Phase 3b.
