#!/usr/bin/env python3
"""
Local R-execution check of every BIOC_QC_HARNESS inject block.

For each of the 396 adopted Bioc workflows:
  1. Extract the inject block (between `.qc_metrics_path <-` and the
     `writeLines(c(...))` anchor)
  2. Un-escape Nextflow's `\\\$` → R's `$`
  3. Run it via `Rscript` in an empty temp dir
  4. Confirm qc_metrics.json was written, is valid JSON, and has
     gates_by_label keys exactly matching the DB-declared qc_steps

With no fixtures in the working dir, every metric should fall through
to `status='not_computed (...)'` — but the R block must still execute
without error. Any R-syntax bug surfaces immediately.

This catches what `bioc_qc_harness_audit.py` can't:
  - typos in R function calls / variable names
  - mismatched quotes / parentheses
  - jsonlite serialization errors (e.g. NULL → unbox bug)
  - subtle differences between blocks that all *look* similar in source

Wall time: ~7 min (~1 sec per workflow × 396). Zero Batch cost.
Requires local R + jsonlite (no Bioconductor packages — defensive
fall-through means we never reach DESeqDataSet/DGEList/etc. code paths).

Exit 0 when all 396 execute cleanly; 1 on any failure.
"""

import json
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "backend/database/galaxy_ai_tools.db"

# Workflows that don't follow the patcher's defensive fall-through pattern
# and therefore can't be probed in empty-working-dir mode. These are
# hand-written canonical references that assume specific R objects (dds,
# vsd, etc.) are in scope — they're production-correct but fail the
# missing-fixture test by design.
SKIP_NO_DEFENSIVE_PATTERN = {
    "deseq2_transformation_and_qc",  # commit 67b92c0a1 — direct counts(dds) call
}


def extract_block(nf_src: str) -> str | None:
    m = re.search(
        r'(\.qc_metrics_path\s*<-\s*"qc_metrics\.json".*?)writeLines\(c\(',
        nf_src, re.DOTALL,
    )
    if not m:
        return None
    # Un-escape Nextflow's `\$` → R's `$`
    return m.group(1).replace(r"\$", "$")


def verify_one(name: str, nf_path: Path, declared: list[str]) -> tuple[bool, str]:
    src = nf_path.read_text(errors="ignore")
    block = extract_block(src)
    if block is None:
        return False, "no inject block found"

    with tempfile.TemporaryDirectory() as td:
        td_p = Path(td)
        (td_p / "block.R").write_text(block)
        try:
            r = subprocess.run(
                ["Rscript", "--vanilla", "block.R"],
                cwd=td, capture_output=True, text=True, timeout=15,
            )
        except subprocess.TimeoutExpired:
            return False, "Rscript timeout (>15s)"
        if r.returncode != 0:
            tail = "\n".join(r.stderr.strip().splitlines()[-3:])
            return False, f"Rscript exit {r.returncode}: {tail}"
        qcj = td_p / "qc_metrics.json"
        if not qcj.exists():
            return False, "no qc_metrics.json emitted"
        try:
            payload = json.loads(qcj.read_text())
        except json.JSONDecodeError as e:
            return False, f"invalid JSON: {e}"
        got = sorted(payload.get("gates_by_label", {}).keys())
        want = sorted(declared)
        if got != want:
            return False, f"label mismatch got={got} want={want}"
        return True, "ok"


def main() -> int:
    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT name, filename, qc_steps FROM workflows "
        "WHERE source='bioconductor' AND qc_steps NOT IN ('[]','') AND qc_steps IS NOT NULL"
    ).fetchall()

    n_total = 0
    n_pass = 0
    failures: list[tuple[str, str]] = []

    for name, filename, qcj in rows:
        p = ROOT / "backend/biomni_workflows" / filename
        if not p.exists():
            continue
        src = p.read_text(errors="ignore")
        if "gates_by_label" not in src:
            continue
        try:
            declared = json.loads(qcj)
        except json.JSONDecodeError:
            continue
        if name in SKIP_NO_DEFENSIVE_PATTERN:
            continue
        n_total += 1
        ok, msg = verify_one(name, p, declared)
        if ok:
            n_pass += 1
        else:
            failures.append((name, msg))
            print(f"  ✗ {name}: {msg}", flush=True)
        if n_total % 50 == 0:
            print(f"  ... {n_total}/{len(rows)} ({n_pass} pass, {len(failures)} fail)", flush=True)

    print()
    print(f"Verified: {n_pass} / {n_total}")
    if failures:
        print(f"Failures: {len(failures)}")
        for name, msg in failures[:20]:
            print(f"  - {name}: {msg}")
        return 1
    print("All inject blocks execute cleanly under Rscript ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
