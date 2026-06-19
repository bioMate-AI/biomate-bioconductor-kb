#!/usr/bin/env python3
"""
Bulk Phase 3c adoption for the 'missing-value handling' label.

Identifies Bioc workflows whose qc_steps is exactly ["missing-value handling"]
and injects a defensive na_fraction_remaining metric block before their
existing `writeLines(c(..., "versions.yml"))` anchor.

The injected R block scans the workflow's working directory for any *.rds
artifacts and, for each one that loads as a matrix/data.frame, computes
the NA fraction. The worst (max) NA fraction across all artifacts is
reported as the metric. Threshold from qc_evidence.yaml.bioconductor_qc.
bioc_missing_value_handling: < 5% pass.

Usage:
    # Dry-run (show what would change, no writes):
    python3 backend/scripts/bioc_qc_harness_inject_mv.py

    # Apply to N workflows (writes + prints diff summary):
    python3 backend/scripts/bioc_qc_harness_inject_mv.py --apply --limit 5

Run from repo root. Safe to re-run — skips workflows that already have
a `gates_by_label` block (idempotent).
"""

import argparse
import json
import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "backend/database/galaxy_ai_tools.db"

# The R block to inject. Uses tryCatch + isTRUE patterns per the Phase 3c
# recipe (docs/20260616_BIOC_PHASE_3C_ADOPTION_RECIPE.md). R member-access
# uses \$ to survive Nextflow's Groovy parser.
INJECT_BLOCK = """
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\\\.rds\\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "%(process_name)s",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)

"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="actually write the files")
    ap.add_argument("--limit", type=int, default=5, help="max workflows to patch")
    args = ap.parse_args()

    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT name, filename FROM workflows "
        "WHERE source='bioconductor' AND qc_steps='[\"missing-value handling\"]' "
        "ORDER BY name"
    ).fetchall()

    patched: list[str] = []
    skipped_already_adopted: list[str] = []
    skipped_no_anchor: list[str] = []
    skipped_no_process_name: list[str] = []

    for name, filename in rows:
        if len(patched) >= args.limit:
            break
        nf_path = ROOT / "backend/biomni_workflows" / filename
        if not nf_path.exists():
            continue
        src = nf_path.read_text()

        # Idempotence: skip if already adopted
        if "gates_by_label" in src:
            skipped_already_adopted.append(name)
            continue

        # Need the process name for the emit's `process:` field
        m_proc = re.search(r"^process\s+(\w+)\s*\{", src, re.MULTILINE)
        if not m_proc:
            skipped_no_process_name.append(name)
            continue
        process_name = m_proc.group(1)

        # Inject the qc_metrics.json output declaration immediately after
        # the existing tuple/path output lines (look for `path "versions.yml"`).
        new_src, n_out = re.subn(
            r"(\n\s*)(path\s+\"versions\.yml\"\s*,\s*emit:\s*versions)",
            lambda m: f'{m.group(1)}tuple val(meta), path("qc_metrics.json"), emit: qc_metrics{m.group(1)}{m.group(2)}',
            src, count=1,
        )
        if n_out == 0:
            skipped_no_anchor.append(name)
            continue

        # Inject the R block immediately before the writeLines(versions.yml) anchor
        anchor_re = re.compile(r"(\n\s*)writeLines\(c\(", re.MULTILINE)
        m_anchor = anchor_re.search(new_src)
        if not m_anchor:
            skipped_no_anchor.append(name)
            continue

        block = INJECT_BLOCK.replace("%(process_name)s", process_name)
        new_src = new_src[:m_anchor.start()] + block + new_src[m_anchor.start():]

        if args.apply:
            nf_path.write_text(new_src)
        patched.append(name)

    print(f"Patched ({'applied' if args.apply else 'DRY RUN'}): {len(patched)}")
    for n in patched:
        print(f"  ✓ {n}")
    print(f"Skipped already-adopted: {len(skipped_already_adopted)}")
    for n in skipped_already_adopted[:5]:
        print(f"  - {n}")
    print(f"Skipped (no writeLines anchor): {len(skipped_no_anchor)}")
    for n in skipped_no_anchor[:5]:
        print(f"  - {n}")
    print(f"Skipped (no process line): {len(skipped_no_process_name)}")


if __name__ == "__main__":
    main()
