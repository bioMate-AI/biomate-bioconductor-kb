#!/usr/bin/env python3
"""
Refresh workflows.input_types from CURRENT .nf files on disk.

Why: index_all_workflows.py skips workflows whose hash hasn't changed
(_wf_exists check), so if the .nf is edited (e.g. `params.mock_mode` removed),
the DB's input_types stays stale. The 'workflow_json' column also keeps the
old content. This script bypasses both — reads current .nf from disk, runs
the same param extractor, updates the DB.

Discovered 2026-05-29: ~1878 of 2182 workflows had stale phantom params in
input_types (most commonly `mock_mode`, `pdb`, `smi`, `mol2`, etc.).

Usage:
  python3 backend/scripts/refresh_workflow_input_types.py [--dry-run]
"""
import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DB_PATH = REPO_ROOT / "backend" / "database" / "galaxy_ai_tools.db"
NF_DIR = REPO_ROOT / "backend" / "biomni_workflows" / "nextflow_nfcore" / "subworkflows"


def extract_inputs_from_nf(content: str) -> list[str]:
    """Same logic as extract_biomni_input_output in index_all_workflows.py."""
    skip = {"outdir", "publish_dir_mode", "enable_conda"}
    names = re.findall(r"\bparams\.(\w+)\s*=", content)
    return list(dict.fromkeys(n for n in names if n not in skip))


def extract_outputs_from_nf(content: str) -> list[str]:
    """Extract file extensions from process output: blocks."""
    skip = {"yml", "yaml", "log"}
    exts = re.findall(r'path\s+["\'][^"\']*\.(\w+)["\']', content)
    return list(dict.fromkeys(e for e in exts if e.lower() not in skip))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dry-run", action="store_true", help="show diffs only, don't write DB")
    args = p.parse_args()

    if not DB_PATH.exists():
        print(f"ERROR: DB not found at {DB_PATH}", file=sys.stderr)
        sys.exit(1)

    conn = sqlite3.connect(str(DB_PATH))
    cur = conn.cursor()

    refreshed = changed = unchanged = missing = 0
    examples = []

    for nf in sorted(NF_DIR.glob("*/*/main.nf")):
        # Build filename per DB convention: nextflow_nfcore/subworkflows/<domain>/<name>/main.nf
        rel = nf.relative_to(REPO_ROOT / "backend" / "biomni_workflows")
        db_filename = str(rel)
        content = nf.read_text()

        new_inputs = extract_inputs_from_nf(content)
        new_outputs = extract_outputs_from_nf(content)
        new_inp_json = json.dumps(new_inputs)
        new_out_json = json.dumps(new_outputs)

        row = cur.execute(
            "SELECT id, input_types, output_types FROM workflows WHERE filename = ?",
            (db_filename,),
        ).fetchone()
        if not row:
            missing += 1
            continue
        wf_id, cur_inp, cur_out = row

        if cur_inp == new_inp_json and cur_out == new_out_json:
            unchanged += 1
            continue

        if not args.dry_run:
            cur.execute(
                "UPDATE workflows SET input_types = ?, output_types = ? WHERE id = ?",
                (new_inp_json, new_out_json, wf_id),
            )
        changed += 1
        if len(examples) < 8:
            examples.append((db_filename, cur_inp[:60], new_inp_json[:60]))
        refreshed += 1

    if not args.dry_run:
        conn.commit()

    print(f"Refreshed {refreshed} rows ({'DRY-RUN' if args.dry_run else 'WRITTEN'})")
    print(f"  changed:   {changed}")
    print(f"  unchanged: {unchanged}")
    print(f"  missing from DB (in subworkflows/ but not indexed): {missing}")
    print()
    print("Sample diffs (first 8):")
    for fn, was, now in examples:
        print(f"  {fn}")
        print(f"    was: {was}")
        print(f"    now: {now}")


if __name__ == "__main__":
    main()
