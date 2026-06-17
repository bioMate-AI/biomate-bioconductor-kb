#!/usr/bin/env python3
"""
Track 3 Phase 3c rollout helper — surveys the 395 remaining Bioc
subworkflows that declare a non-empty qc_steps list but don't yet
emit qc_metrics.json keyed by the BIOC_QC_HARNESS shape.

Reports a sorted priority queue:
    label                          # workflows declaring it
    ─────────────────────────────  ─────────────────────────
    missing-value handling         126
    count normalization            79
    cell QC metrics                72
    ...

For each workflow, also flags:
    has_qc_metrics_emit  — already emits qc_metrics.json (skip)
    has_canonical_adopt  — uses the .gates_by_label shape (skip)
    candidate_for_adoption — needs Phase 3c work

The 2026-06-16 canonical example is:
    bioconductor/deseq2/transformation_and_qc.nf  (commit 67b92c0a1)

Usage (read-only audit):
    python3 backend/scripts/bioc_qc_harness_rollout.py
"""

import json
import re
import sqlite3
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "backend/database/galaxy_ai_tools.db"
BIOC_DIR = ROOT / "backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor"


def main() -> None:
    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT name, filename, qc_steps FROM workflows "
        "WHERE source='bioconductor' AND qc_steps NOT IN ('[]','') AND qc_steps IS NOT NULL"
    ).fetchall()

    label_counts: Counter[str] = Counter()
    candidates: list[tuple[str, str, list[str]]] = []
    already_canonical: list[str] = []
    emits_qc: list[str] = []

    for name, filename, qc_steps_json in rows:
        try:
            labels = json.loads(qc_steps_json)
        except json.JSONDecodeError:
            continue
        if not isinstance(labels, list) or not labels:
            continue
        for label in labels:
            label_counts[label] += 1

        # Inspect the .nf file
        nf_path = ROOT / "backend/biomni_workflows" / filename
        if not nf_path.exists():
            continue
        nf_src = nf_path.read_text(errors="ignore")

        has_canonical = "gates_by_label" in nf_src
        has_emit = re.search(r'qc_metrics\.json["\']?\s*,\s*emit', nf_src) is not None

        if has_canonical:
            already_canonical.append(name)
        elif has_emit:
            emits_qc.append(name)
        else:
            candidates.append((name, filename, labels))

    print(f"Bioc workflows declaring qc_steps: {len(rows)}")
    print(f"  Already adopted canonical (gates_by_label): {len(already_canonical)}")
    print(f"  Emit qc_metrics.json but not canonical shape: {len(emits_qc)}")
    print(f"  Candidates for Phase 3c adoption: {len(candidates)}")
    print()

    print("Top 15 labels by workflow count (priority order for Phase 3c):")
    for label, n in label_counts.most_common(15):
        print(f"  {n:5d}  {label}")
    print()

    print("First 10 candidates for Phase 3c adoption (sample):")
    for name, filename, labels in candidates[:10]:
        print(f"  {name}")
        print(f"    file: {filename}")
        print(f"    declared labels: {labels}")


if __name__ == "__main__":
    main()
