# Phase 3c Adoption Recipe — adding BIOC_QC_HARNESS gates to a Bioc workflow

**Worktree:** `/home/yzhang/biomate` · **Branch:** `qc/coverage-and-rebuilds`
**Status as of 2026-06-16:** 1 of 396 Bioc workflows adopted (`deseq2_transformation_and_qc`, commit `67b92c0a1`); 395 candidates remaining. Use `python3 backend/scripts/bioc_qc_harness_rollout.py` for the priority-ordered queue.

This recipe captures the canonical pattern from `67b92c0a1` so anyone can adopt the next workflow in ~15 minutes.

## When to use which pattern

| Pattern | When | Effort | Metric quality |
|---|---|---|---|
| **A. Inline (canonical)** — compute metrics directly in the workflow's existing R session | Workflow has the analytic objects (counts matrix, Seurat, dds, SCE, etc.) in R scope already | ~15 min per workflow | real values |
| **B. Wrapper** — call `BIOC_QC_HARNESS(out.artifact, qc_steps_json)` as a downstream Nextflow process | Workflow emits an artifact but doesn't compute metrics in its own session | ~5 min per workflow | `status: not_computed (harness MVP)` — audit ledger only |

**Default to Pattern A** when feasible. Pattern B is the fallback that gets coverage in audit at zero per-workflow analyst effort, useful for bulk rollout.

## Pattern A — inline adoption (canonical)

### Step 1 — read the declared qc_steps

```bash
sqlite3 backend/database/galaxy_ai_tools.db \
  "SELECT qc_steps FROM workflows WHERE name='<workflow_name>';"
```

Output is a JSON list of 1+ labels from the 25-label taxonomy.

### Step 2 — find the corresponding `bioconductor_qc.*` YAML rows

For each declared label, look up the canonical gate row + metric name in the `LABEL_TO_GATE` table at `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/_qc_harness/main.nf:64-87`. Example:

| Label | gate_row | metric_name |
|---|---|---|
| dispersion/size-factor estimation | `bioc_dispersion_size_factor` | `disp_outlier_fraction` |
| diagnostic MA/PCA QC | `bioc_diagnostic_ma_pca_qc` | `pc1_var_explained` |
| count normalization | `bioc_count_normalization` | `lib_size_cv_ratio` |
| variance-stabilizing normalization | `bioc_vsn_normalization` | `mean_sd_slope_after_vsn` |
| cell QC metrics | `bioc_cell_qc_metrics` | `pct_mito_max` |
| low-count filtering | `bioc_low_count_filtering` | `genes_kept_fraction` |
| ... | (see LABEL_TO_GATE) | ... |

### Step 3 — add the qc_metrics.json output declaration

In the workflow's `process` block:

```groovy
output:
tuple val(meta), path("*.csv"), emit: tables, optional: true
tuple val(meta), path("*.pdf"), emit: plots,  optional: true
tuple val(meta), path("qc_metrics.json"), emit: qc_metrics    // ← add this
path "versions.yml",            emit: versions
```

### Step 4 — compute each metric inline at the end of the R script

Insert before the existing `writeLines(c(..., "versions.yml"))` block. Use **`tryCatch + isTRUE` patterns** so a failed metric never breaks the whole emit:

```R
# ── BIOC_QC_HARNESS — Track 3 Phase 3c canonical adoption ─────────────────
.qc_metrics_path <- "qc_metrics.json"
.gates_by_label <- list()

# Per-label metric impls — one block per declared qc_steps label.
# Each block must produce a metric_value (numeric/NA) + passes (logical/NA)
# + status ("computed" or "not_computed (..)"). Wrap everything in tryCatch
# and use isTRUE() for the passes field so non-finite values don't trip.

# Example: "dispersion/size-factor estimation"
.disp_outlier_pct <- tryCatch({
  .dds_d <- tryCatch(estimateDispersions(dds), error = function(e) dds)
  .o <- mcols(.dds_d)\$dispOutlier        # ← escape \$ for Nextflow Groovy parser
  if (!is.null(.o)) round(mean(.o, na.rm = TRUE), 4) else NA_real_
}, error = function(e) NA_real_)
.gates_by_label[["dispersion/size-factor estimation"]] <- list(
  gate_row = "bioc_dispersion_size_factor",
  metric_name = "disp_outlier_fraction",
  metric_value = .disp_outlier_pct,
  passes = isTRUE(is.finite(.disp_outlier_pct) && .disp_outlier_pct <= 0.01),
  status = if (is.finite(.disp_outlier_pct)) "computed" else "not_computed (dispersion not estimable)"
)

# ...repeat one block per declared label...

.qc_payload <- list(
  success = TRUE,
  process = "<UPPERCASE_PROCESS_NAME>",
  domain  = "bioconductor",
  declared_qc_steps = c(<declared-label-list>),
  gates_by_label = .gates_by_label,
  evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
  harness_version = "0.1.0-canonical"
)
cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
    file = .qc_metrics_path)
```

### Step 5 — escape every R `$` to `\$`

Nextflow's Groovy parser tries to interpolate bare `$` references in `"""..."""` heredocs. R member-access (`obj$field`, `mcols(x)$col`, `pca$sdev`) must be written `\$` in the workflow main.nf. Common offenders: `mcols(x)\$dispOutlier`, `.pca\$sdev`, `fit\$shrink`. Same trap as `572637e48` (nlmixr2) and `a56262912` (this commit's pre-push fix).

### Step 6 — verify YAML threshold matches your `passes` logic

`backend/config/qc_evidence.yaml` has the canonical threshold per gate row. Your inline `passes = isTRUE(...)` should match its `rule_text`. Example: `bioc_dispersion_size_factor.rule_text` says "≤ 1% pass" → R does `<= 0.01`.

### Step 7 — commit one workflow at a time

```
git add backend/biomni_workflows/.../path/to/workflow.nf
git commit -m "feat(bioc-qc): Phase 3c adoption — <workflow_name>"
git push
```

Don't batch adoptions across workflows — small commits make it easy to revert a single bad adoption.

## Pattern B — wrapper adoption (bulk / fallback)

For workflows where compute-in-R-session isn't feasible (e.g. external CLI tools that produce only file artifacts), include the harness as a downstream process:

```groovy
include { BIOC_QC_HARNESS } from '../_qc_harness/main.nf'

workflow MY_BIOC_WORKFLOW {
    take: ch_input
    main:
      CORE_ANALYSIS(ch_input)
      BIOC_QC_HARNESS(
        CORE_ANALYSIS.out.artifact,
        '["<label_1>","<label_2>",...]'    // string-literal JSON of declared qc_steps
      )
    emit:
      qc_metrics = BIOC_QC_HARNESS.out.qc_metrics
}
```

This produces a `qc_metrics.json` with `status='not_computed (harness MVP; metric impl pending)'` for every declared label. The gate row lands in the audit ledger; real metric impls are a Phase 3c follow-on per label.

## Rolling-adoption priority queue

From `python3 backend/scripts/bioc_qc_harness_rollout.py` (2026-06-16):

| # workflows | Label | Status |
|---:|---|---|
| 126 | missing-value handling | 0 / 126 adopted |
| 79 | count normalization | 1 / 79 adopted (DESeq2 transformation_and_qc) |
| 72 | cell QC metrics | 0 / 72 adopted |
| 54 | low-count filtering | 0 / 54 adopted |
| 32 | diagnostic MA/PCA QC | 1 / 32 adopted (DESeq2 transformation_and_qc) |
| 28 | dispersion/size-factor estimation | 1 / 28 adopted (DESeq2 transformation_and_qc) |
| 21 | batch-effect correction | 0 / 21 adopted |
| 21 | highly-variable feature selection | 0 / 21 adopted |
| 16 | TMM normalization | 0 / 16 adopted |
| 13 | variance-stabilizing normalization | 1 / 13 adopted (DESeq2 transformation_and_qc) |
| 11 | doublet detection QC | 0 / 11 adopted |
| 10 | normalization diagnostic plot | 1 / 10 adopted (DESeq2 transformation_and_qc) |
| 10 | clustering QC | 0 / 10 adopted |
| ... | (full table in the rollout-helper output) | ... |

The DESeq2 canonical covers 5 high-frequency labels; adopting workflows that overlap on those labels lets you copy the existing R blocks verbatim.

## Common pitfalls

| Trap | How it surfaces | Fix |
|---|---|---|
| Unescaped R `$` | Nextflow head crashes `No such variable: ...` | `\$` per Step 5 |
| `numpy.bool_` (Python workflows) | `TypeError: Object of type bool_ is not JSON serializable` | wrap with `bool(...)` |
| `NULL` in jsonlite auto_unbox | Field serializes as `{}` (empty dict) | use `NA_real_` / `NA` |
| Missing process keyword | `[QC-S3] No report found ...` despite file existing | confirm process name contains a substring registered in `_S3_REPORT_PATHS` |
| Wrong gate_row name | YAML lookup fails; gate skipped | copy verbatim from `LABEL_TO_GATE` |

## Verification template

After adopting a workflow:

1. Sync to dev: `bash scripts/sync_to_dev.sh`
2. Submit a run with a fixture for that workflow's expected input
3. Check log for `[QC-S3] Reading report for <PROCESS_NAME>` + `[QC Gate] PASSED/TRIGGERED/FAILED`
4. Read the artifact directly: `aws s3 cp s3://biomate-nextflow-work/nextflow/outputs/<user>/<short>/<step>/qc_metrics.json -`
5. Confirm `gates_by_label` shape matches expected schema
6. If failure: read `.command.err` from the work dir before re-deploying

## Related docs

- Master inventory + plan: `docs/20260615_QC_GATE_INVENTORY_AND_PLAN.md`
- Session writeup: `docs/20260615_QC_TRACK1_TRACK2_TRACK3_SESSION.md`
- Bioc orphan audit: `docs/20260615_BIOC_ORPHAN_AUDIT.md`
- Canonical example (DESeq2 transformation_and_qc): commit `67b92c0a1` + escape fix `a56262912`
- Rollout audit script: `backend/scripts/bioc_qc_harness_rollout.py`
- LABEL_TO_GATE source: `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/_qc_harness/main.nf:64-87`
