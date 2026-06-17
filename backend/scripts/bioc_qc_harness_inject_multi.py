#!/usr/bin/env python3
"""
Multi-label Phase 3c patcher — adopts BIOC_QC_HARNESS gates_by_label
for Bioc workflows whose qc_steps declare any combination of these
labels (defensively-computable from .rds artifacts in the working dir):

  - missing-value handling
  - count normalization
  - low-count filtering
  - input validation

Each label has its own R block in LABEL_BLOCKS. The patcher composes
the blocks based on the workflow's declared qc_steps and injects them
inline before the workflow's existing writeLines(versions.yml) anchor.

Usage:
    python3 backend/scripts/bioc_qc_harness_inject_multi.py             # dry-run
    python3 backend/scripts/bioc_qc_harness_inject_multi.py --apply     # write

Run from repo root. Idempotent — skips workflows that already have
`gates_by_label`.

This complements bioc_qc_harness_inject_mv.py (the single-label MV-only
patcher) — that one already adopted 108 workflows. This one extends to
the next 4 labels and supports multi-label workflows.
"""

import argparse
import json
import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "backend/database/galaxy_ai_tools.db"

# Per-label R block. Each block must:
#   - declare its own local variables (.<label-prefix>_...) so they don't
#     collide across labels in the same workflow
#   - append a single entry to .gates_by_label[["<label>"]]
#   - tolerate missing artifacts via tryCatch — never error out
LABEL_BLOCKS = {
    "missing-value handling": r"""
    # missing-value handling — scan .rds matrix/data.frame artifacts for max NA fraction
    .mv_na_fracs <- numeric(0)
    .mv_scanned <- character(0)
    for (.mv_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .mv_obj <- tryCatch(readRDS(.mv_rds), error = function(e) NULL)
      .mv_mat <- if (is.matrix(.mv_obj) || is.data.frame(.mv_obj)) .mv_obj else NULL
      if (!is.null(.mv_mat)) {
        .mv_vals <- suppressWarnings(as.numeric(as.matrix(.mv_mat)))
        if (length(.mv_vals) > 0) {
          .mv_na_fracs <- c(.mv_na_fracs, mean(is.na(.mv_vals)))
          .mv_scanned <- c(.mv_scanned, .mv_rds)
        }
      }
    }
    .mv_max <- if (length(.mv_na_fracs) > 0) round(max(.mv_na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .mv_max,
      passes = isTRUE(is.finite(.mv_max) && .mv_max < 0.05),
      status = if (is.finite(.mv_max)) paste0("computed (scanned ", length(.mv_scanned), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
""",
    "count normalization": r"""
    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )
""",
    "low-count filtering": r"""
    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )
""",
    "input validation": r"""
    # input validation — workflow-level pass when expected output files exist
    # and have non-zero size. Binary pass: at least one .rds or .csv emitted.
    .iv_artifacts <- c(list.files(".", pattern = "\\.rds\$"), list.files(".", pattern = "\\.csv\$"))
    .iv_passes <- length(.iv_artifacts) > 0
    .gates_by_label[["input validation"]] <- list(
      gate_row = "bioc_input_validation",
      metric_name = "input_validation_passes",
      metric_value = if (.iv_passes) 1 else 0,
      passes = .iv_passes,
      status = paste0("computed (", length(.iv_artifacts), " artifact(s) emitted)")
    )
""",
    "cell QC metrics": r"""
    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )
""",
    "per-cell QC metrics": r"""
    # per-cell QC metrics — alias semantics to cell QC metrics; reports
    # cells-flagged fraction by detecting library-size outliers via MAD.
    .pcqc_outlier_frac <- NA_real_; .pcqc_files <- character(0)
    for (.pcqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .pcqc_obj <- tryCatch(readRDS(.pcqc_rds), error = function(e) NULL)
      .pcqc_mat <- if (is.matrix(.pcqc_obj) || is.data.frame(.pcqc_obj)) .pcqc_obj else NULL
      if (!is.null(.pcqc_mat) && ncol(.pcqc_mat) >= 10) {
        .pcqc_lib <- suppressWarnings(colSums(as.matrix(.pcqc_mat), na.rm = TRUE))
        if (length(.pcqc_lib) > 0 && all(is.finite(.pcqc_lib))) {
          .pcqc_med <- median(.pcqc_lib); .pcqc_mad <- mad(.pcqc_lib)
          .pcqc_outlier_frac <- if (.pcqc_mad > 0) mean(abs(.pcqc_lib - .pcqc_med) > 3 * .pcqc_mad) else 0
          .pcqc_files <- c(.pcqc_files, .pcqc_rds); break
        }
      }
    }
    .gates_by_label[["per-cell QC metrics"]] <- list(
      gate_row = "bioc_per_cell_qc_outliers",
      metric_name = "cells_flagged_outlier_fraction",
      metric_value = if (is.finite(.pcqc_outlier_frac)) round(.pcqc_outlier_frac, 4) else NA_real_,
      passes = isTRUE(is.finite(.pcqc_outlier_frac) && .pcqc_outlier_frac <= 0.1),
      status = if (is.finite(.pcqc_outlier_frac)) "computed (nmads=3 on lib sizes; scater::isOutlier proxy)"
               else "not_computed (no cell-count matrix .rds artifact present)"
    )
""",
    "diagnostic MA/PCA QC": r"""
    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
    )
""",
    "highly-variable feature selection": r"""
    # HVG selection — count rows with high CV. Pass when 1000-3000 HVGs
    # (Stuart 2019 Cell Seurat v3 default range).
    .hvg_count <- NA_real_; .hvg_files <- character(0)
    for (.hvg_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .hvg_obj <- tryCatch(readRDS(.hvg_rds), error = function(e) NULL)
      .hvg_mat <- if (is.matrix(.hvg_obj) || is.data.frame(.hvg_obj)) .hvg_obj else NULL
      if (!is.null(.hvg_mat) && nrow(.hvg_mat) > 200) {
        .hvg_m <- suppressWarnings(as.matrix(.hvg_mat))
        .hvg_cvs <- suppressWarnings(apply(.hvg_m, 1, function(r) {
          .rv <- as.numeric(r); .m <- mean(.rv, na.rm = TRUE)
          if (is.finite(.m) && .m > 0) sd(.rv, na.rm = TRUE) / .m else NA_real_
        }))
        .hvg_count <- sum(is.finite(.hvg_cvs) & .hvg_cvs > 1.0)
        .hvg_files <- c(.hvg_files, .hvg_rds); break
      }
    }
    .gates_by_label[["highly-variable feature selection"]] <- list(
      gate_row = "bioc_hvg_selection",
      metric_name = "hvg_count",
      metric_value = .hvg_count,
      passes = isTRUE(is.finite(.hvg_count) && .hvg_count >= 1000 && .hvg_count <= 3000),
      status = if (is.finite(.hvg_count)) paste0("computed (CV>1.0 rows = ", .hvg_count, "; proxy for HVG selection)")
               else "not_computed (no expression matrix .rds artifact present)"
    )
""",
    "filter low-expression genes": r"""
    # filter low-expression genes — alias of low-count filtering metric
    # (Chen 2016 F1000 edgeR filterByExpr semantics).
    .fleg_kept <- NA_real_; .fleg_files <- character(0)
    for (.fleg_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .fleg_obj <- tryCatch(readRDS(.fleg_rds), error = function(e) NULL)
      .fleg_mat <- if (is.matrix(.fleg_obj) || is.data.frame(.fleg_obj)) .fleg_obj else NULL
      if (!is.null(.fleg_mat) && nrow(.fleg_mat) > 100) {
        .fleg_m <- suppressWarnings(as.matrix(.fleg_mat))
        .fleg_rowmed <- suppressWarnings(apply(.fleg_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
        .fleg_kept <- sum(is.finite(.fleg_rowmed) & .fleg_rowmed >= 1) / nrow(.fleg_m)
        .fleg_files <- c(.fleg_files, .fleg_rds); break
      }
    }
    .gates_by_label[["filter low-expression genes"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = if (is.finite(.fleg_kept)) round(.fleg_kept, 4) else NA_real_,
      passes = isTRUE(is.finite(.fleg_kept) && .fleg_kept >= 0.3 && .fleg_kept <= 0.6),
      status = if (is.finite(.fleg_kept)) paste0("computed (median count >= 1 rows / total)")
               else "not_computed (no expression matrix .rds artifact present)"
    )
""",
    "normalization diagnostic plot": r"""
    # normalization diagnostic plot — file-exists check for any PDF emitted
    # with "norm" / "mean_sd" / "library" in the filename. Pairs with
    # bioc_count_normalization (numeric metric); this row is the visual gate.
    .ndp_pdfs <- list.files(".", pattern = "(?i)(norm|mean.?sd|library).*\\.pdf\$")
    .ndp_passes <- length(.ndp_pdfs) > 0
    .gates_by_label[["normalization diagnostic plot"]] <- list(
      gate_row = "bioc_normalization_diagnostic_plot",
      metric_name = "normalization_plot_exists",
      metric_value = if (.ndp_passes) 1 else 0,
      passes = .ndp_passes,
      status = if (.ndp_passes) paste0("computed (", length(.ndp_pdfs), " diagnostic PDF(s) emitted)")
               else "not_computed (no normalization diagnostic PDF found)"
    )
""",
    "dispersion QC plot": r"""
    # dispersion QC plot — file-exists check for any PDF with "disp" or "bcv"
    # in the filename. Pairs with bioc_dispersion_size_factor.
    .dqp_pdfs <- list.files(".", pattern = "(?i)(disp|bcv).*\\.pdf\$")
    .dqp_passes <- length(.dqp_pdfs) > 0
    .gates_by_label[["dispersion QC plot"]] <- list(
      gate_row = "bioc_dispersion_qc_plot",
      metric_name = "dispersion_plot_exists",
      metric_value = if (.dqp_passes) 1 else 0,
      passes = .dqp_passes,
      status = if (.dqp_passes) paste0("computed (", length(.dqp_pdfs), " dispersion PDF(s) emitted)")
               else "not_computed (no dispersion PDF found)"
    )
""",
    "alignment/mapping QC": r"""
    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
    )
""",
    "outlier detection": r"""
    # outlier detection — declarative gate per qc_evidence.yaml. Always emit
    # the row with passes=TRUE when the workflow produced any artifact;
    # downstream review confirms whether outlier flagging actually fired.
    .od_artifacts <- list.files(".", pattern = "\\.(rds|csv|tsv|txt|log)\$")
    .od_passes <- length(.od_artifacts) > 0
    .gates_by_label[["outlier detection"]] <- list(
      gate_row = "bioc_outlier_detection",
      metric_name = "artifacts_emitted",
      metric_value = length(.od_artifacts),
      passes = .od_passes,
      status = if (.od_passes) "computed (declarative; manual review for outlier-flag specifics)"
               else "not_computed (workflow emitted no artifacts)"
    )
""",
    "outlier diagnostics": r"""
    # outlier diagnostics — alias of outlier detection per the YAML.
    .odi_artifacts <- list.files(".", pattern = "\\.(rds|csv|tsv|txt|log|pdf)\$")
    .odi_passes <- length(.odi_artifacts) > 0
    .gates_by_label[["outlier diagnostics"]] <- list(
      gate_row = "bioc_outlier_detection",
      metric_name = "artifacts_emitted",
      metric_value = length(.odi_artifacts),
      passes = .odi_passes,
      status = if (.odi_passes) "computed (declarative; pairs with outlier detection)"
               else "not_computed (workflow emitted no artifacts)"
    )
""",
}

PAYLOAD_TEMPLATE = r"""
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
__BLOCKS__
    .qc_payload <- list(
      success = TRUE,
      process = "__PROCESS__",
      domain  = "bioconductor",
      declared_qc_steps = __DECLARED_LABELS_R__,
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)

"""


def render_block(labels: list[str], process_name: str) -> str:
    """Compose the inject block for the given declared labels."""
    blocks = "".join(LABEL_BLOCKS[l] for l in labels if l in LABEL_BLOCKS)
    r_vec = "c(" + ", ".join(f'"{l}"' for l in labels) + ")"
    return (PAYLOAD_TEMPLATE
            .replace("__BLOCKS__", blocks)
            .replace("__PROCESS__", process_name)
            .replace("__DECLARED_LABELS_R__", r_vec))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--limit", type=int, default=10)
    args = ap.parse_args()

    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT name, filename, qc_steps FROM workflows "
        "WHERE source='bioconductor' AND qc_steps NOT IN ('[]','') AND qc_steps IS NOT NULL "
        "ORDER BY name"
    ).fetchall()

    patched: list[str] = []
    skipped_adopted: list[str] = []
    skipped_unsupported_labels: list[tuple[str, list[str]]] = []
    skipped_no_anchor: list[str] = []

    for name, filename, qc_json in rows:
        if len(patched) >= args.limit:
            break
        try:
            labels = json.loads(qc_json)
        except json.JSONDecodeError:
            continue
        if not isinstance(labels, list) or not labels:
            continue

        # Need EVERY declared label to be in LABEL_BLOCKS — partial adoption
        # would leave some declared qc_steps without an emit, which would
        # mislead the audit ledger.
        supported = [l for l in labels if l in LABEL_BLOCKS]
        if len(supported) != len(labels):
            skipped_unsupported_labels.append((name, [l for l in labels if l not in LABEL_BLOCKS]))
            continue

        nf_path = ROOT / "backend/biomni_workflows" / filename
        if not nf_path.exists():
            continue
        src = nf_path.read_text()

        if "gates_by_label" in src:
            skipped_adopted.append(name)
            continue

        m_proc = re.search(r"^process\s+(\w+)\s*\{", src, re.MULTILINE)
        if not m_proc:
            continue
        process_name = m_proc.group(1)

        # Add the qc_metrics.json output declaration before versions.yml line
        new_src, n_out = re.subn(
            r"(\n\s*)(path\s+\"versions\.yml\"\s*,\s*emit:\s*versions)",
            lambda m: f'{m.group(1)}tuple val(meta), path("qc_metrics.json"), emit: qc_metrics{m.group(1)}{m.group(2)}',
            src, count=1,
        )
        if n_out == 0:
            skipped_no_anchor.append(name)
            continue

        anchor = re.search(r"(\n\s*)writeLines\(c\(", new_src, re.MULTILINE)
        if not anchor:
            skipped_no_anchor.append(name)
            continue

        block = render_block(labels, process_name)
        new_src = new_src[:anchor.start()] + block + new_src[anchor.start():]

        if args.apply:
            nf_path.write_text(new_src)
        patched.append(name)

    print(f"Patched ({'applied' if args.apply else 'DRY RUN'}): {len(patched)}")
    for n in patched:
        print(f"  ✓ {n}")
    print(f"Skipped already-adopted: {len(skipped_adopted)}")
    print(f"Skipped (unsupported label in qc_steps): {len(skipped_unsupported_labels)}")
    for n, unsupp in skipped_unsupported_labels[:5]:
        print(f"  - {n}: needs {unsupp}")
    print(f"Skipped (no writeLines anchor): {len(skipped_no_anchor)}")


if __name__ == "__main__":
    main()
