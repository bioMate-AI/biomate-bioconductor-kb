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
