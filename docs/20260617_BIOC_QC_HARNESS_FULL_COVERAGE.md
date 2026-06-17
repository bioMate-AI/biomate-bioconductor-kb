# Bioc QC Harness — Full Phase 3c Coverage (396/396)

**Date:** 2026-06-17
**Branch:** `qc/coverage-and-rebuilds`
**Commits this session:**
- `27db1eefb3` MV-only patcher (+108 → 109)
- `1e95237bbf` multi-label patcher v0.1 (+82 → 191)
- `6b237b91f`  multi-label patcher v0.2 (+99 → 290)
- `78a7998ef`  recipe doc update
- `6c8bcdc38`  multi-label patcher v0.3 (+106 → **396, 100%**)

## Outcome

Every Bioconductor subworkflow that declares a non-empty `qc_steps` list (n=396) now emits `qc_metrics.json` keyed to the `BIOC_QC_HARNESS` `gates_by_label` shape. Each declared label produces exactly one entry referencing a canonical `qc_evidence.yaml` `bioconductor_qc.*` gate row, with either a computed numeric metric or `status='not_computed (...)'` explaining why the artifact wasn't computable in the current run.

| Date | Adopted | % | Method |
|---|---:|---:|---|
| 2026-06-16 (`67b92c0a1`) | 1 | 0.3% | inline canonical (DESeq2 transformation_and_qc, hand-written) |
| 2026-06-17 (`27db1eefb3`) | 109 | 27% | bulk MV-only patcher |
| 2026-06-17 (`1e95237bbf`) | 191 | 48% | multi-label patcher v0.1 (4 labels) |
| 2026-06-17 (`6b237b91f`)  | 290 | 73% | multi-label patcher v0.2 (15 labels) |
| 2026-06-17 (`6c8bcdc38`)  | **396** | **100%** | multi-label patcher v0.3 (26 labels) |

## Design

### Single patcher, registry of per-label R blocks

`backend/scripts/bioc_qc_harness_inject_multi.py` holds a `LABEL_BLOCKS` dict mapping each of the 26 declared qc_steps labels to an R block. For each workflow, the patcher reads its declared `qc_steps`, composes the relevant blocks back-to-back, and injects them immediately before the existing `writeLines(c(..., "versions.yml"))` anchor. The same patcher run also adds a `tuple val(meta), path("qc_metrics.json"), emit: qc_metrics` line to the process `output:` block.

The patcher is idempotent (skips files where `gates_by_label` already appears) and only patches workflows where **every** declared label is in `LABEL_BLOCKS` — partial adoption would mislead the audit ledger about coverage.

### Three computational tiers, each defensive

| Tier | Pattern | Examples |
|---|---|---|
| **Matrix scan** | scan `.rds` files for any matrix/data.frame, compute the metric across cells | `missing-value handling` (max NA fraction), `count normalization` (lib-size CV), `low-count filtering` (rows w/ median ≥ 1), `cell QC metrics` (n_cells), `diagnostic MA/PCA QC` (PC1 var explained via prcomp), `HVG selection` (high-CV row count), `prevalence filtering` |
| **Object-type-aware** | `inherits(.obj, "...")` discrimination, then extract the canonical metric | `dispersion/size-factor estimation` (DESeqDataSet `mcols$dispOutlier` OR DGEList `common.dispersion`), `TMM normalization` (DGEList `samples$norm.factors`), `VSN` (DESeqTransform/SE → `lm` slope of row-SD ~ row-mean), `doublet detection QC` (SCE colData / Seurat meta.data), `voom mean-variance` (EList `weights`), `clustering QC` (n_clusters in cluster column), `array detection QC` (ExpressionSet detection p-values) |
| **File-exists / declarative** | check artifact filename patterns; binary pass when present | `input validation`, `normalization diagnostic plot`, `dispersion QC plot`, `alignment/mapping QC`, `batch-effect correction`, `between-array normalization`, `outlier detection`, `outlier diagnostics`, `expression-level QC` |

Every block uses **`tryCatch` + `isTRUE`** patterns so a failed metric never breaks the whole emit. When the expected object class isn't present, the block writes `status='not_computed (no XXX .rds artifact present)'` — the gate row still lands in the audit ledger.

### R-`$` escaping for Nextflow Groovy parser

Every R member-access (`mcols(x)$dispOutlier`, `.pca$sdev`, `.obj$samples$norm.factors`) is written as `\$` in the Python source so the Nextflow heredoc doesn't try to interpolate it as a Groovy variable. Hit `572637e48` (nlmixr2) and `a56262912` (DESeq2 canonical) before; the patcher avoids the trap by default.

## The 26 labels in LABEL_BLOCKS

```
missing-value handling                  count normalization
low-count filtering                     input validation
cell QC metrics                         per-cell QC metrics
diagnostic MA/PCA QC                    highly-variable feature selection
filter low-expression genes             normalization diagnostic plot
dispersion QC plot                      alignment/mapping QC
outlier detection                       outlier diagnostics
dispersion/size-factor estimation       TMM normalization
variance-stabilizing normalization      doublet detection QC
voom mean-variance modelling            clustering QC
batch-effect correction                 prevalence/abundance filtering
array detection QC                      between-array normalization
expression-level QC
```

## Caveats — what's "computed" vs "declarative"

| Honesty bucket | Count | Meaning |
|---|---:|---|
| Genuine numeric computation when artifact present | 14 labels | matrix scans + object-type-aware metrics produce real values |
| Declarative / file-exists | 9 labels | emit row landed in audit ledger; concrete acceptance metric is per-workflow follow-on (e.g. real kBET acceptance rate, real silhouette score) |
| Alias of an existing computation | 3 labels | `filter low-expression genes` aliases low-count, `per-cell QC metrics` aliases cell QC, `outlier diagnostics` aliases outlier detection |

For declarative gates, the YAML row's `evidence_tier` already documents the gap (`SILVER` or `BRONZE`). This is the right honesty level: we'd rather emit `status='computed (declarative; kBET acceptance pending)'` than fabricate a fake pass rate.

## Verification on dev

Sync `6c8bcdc38` is in flight. After sync, the canonical verification is per the recipe doc (`docs/20260616_BIOC_PHASE_3C_ADOPTION_RECIPE.md` step 7):

1. Pick 5-10 workflows across the three tiers
2. Submit a run with a fixture for each
3. `aws s3 cp s3://biomate-nextflow-work/nextflow/outputs/<user>/<short>/<step>/qc_metrics.json -`
4. Confirm `gates_by_label` keys exactly match declared `qc_steps`
5. For matrix-scan and object-type-aware labels, confirm at least one `status='computed'`
6. For declarative labels, confirm `status='computed (declarative; ...)'` (not silently passing without the qualifier)

## What's NOT covered

`workflows.qc_steps='[]'` or NULL (n ≈ 1860 Bioc workflows): no qc_steps declared, nothing to wire. These are the candidates for the next Track 3 phase: classify each by package family and either backfill a `qc_steps` declaration or document the omission.

## Files touched

- `backend/scripts/bioc_qc_harness_inject_multi.py` — patcher (LABEL_BLOCKS dict, 26 entries; ~600 lines)
- `backend/scripts/bioc_qc_harness_inject_mv.py` — original single-label MV patcher (kept for archeology)
- `backend/scripts/bioc_qc_harness_rollout.py` — audit helper (no change)
- `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/**/main.nf` — 395 workflows patched across the four commits (DESeq2 transformation_and_qc was already adopted hand-written)
- `docs/20260616_BIOC_PHASE_3C_ADOPTION_RECIPE.md` — updated with adoption history table

## Related docs

- Master inventory + plan: `docs/20260615_QC_GATE_INVENTORY_AND_PLAN.md`
- Earlier session writeup: `docs/20260615_QC_TRACK1_TRACK2_TRACK3_SESSION.md`
- Bioc orphan audit: `docs/20260615_BIOC_ORPHAN_AUDIT.md`
- Adoption recipe (Pattern A canonical): `docs/20260616_BIOC_PHASE_3C_ADOPTION_RECIPE.md`
- LABEL_TO_GATE source: `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/_qc_harness/main.nf`
- `qc_evidence.yaml` (`bioconductor_qc.*` rows): `backend/config/qc_evidence.yaml`
