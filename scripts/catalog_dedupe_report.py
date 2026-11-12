#!/usr/bin/env python3
"""DRY RUN — report duplicate catalog rows (same workflow module indexed twice). Writes nothing.

Usage: python3 scripts/catalog_dedupe_report.py <galaxy_ai_tools.db> <backend_root>

A module counts as duplicated when several `biomni_nextflow` rows share the module folder name
(the indexer re-inserted a row under a remapped domain path and on every content-hash change).
For each group the row whose workflow file exists on disk is the KEEP candidate; rows whose file is
missing (renamed, archived to _archived/, or a remapped path that never existed) are DROP candidates.
Applying any deletion is a separate, explicit step that needs the founder's approval.
"""
import os
import sqlite3
import sys
from collections import defaultdict


def resolve(backend_root: str, filename: str):
    for base in ("biomni_workflows/nextflow_nfcore/subworkflows", "biomni_workflows/nextflow_nfcore",
                 "biomni_workflows/subworkflows", "biomni_workflows"):
        p = os.path.join(backend_root, base, filename)
        if os.path.isfile(p):
            return os.path.realpath(p)
    return None


def main():
    db, backend_root = sys.argv[1], sys.argv[2]
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    rows = con.execute("SELECT id, name, filename, indexed_at FROM workflows WHERE source='biomni_nextflow'").fetchall()
    groups = defaultdict(list)
    for wid, name, fn, at in rows:
        module = os.path.basename(os.path.dirname(fn or "")) or fn
        groups[module].append((wid, name, fn, at, resolve(backend_root, fn or "")))
    dup = {m: g for m, g in groups.items() if len(g) > 1}
    drop = 0
    for m, g in sorted(dup.items()):
        reals = {r[4] for r in g if r[4]}
        print(f"\n== {m}  ({len(g)} rows, {len(reals)} distinct file(s) on disk)")
        for wid, name, fn, at, real in sorted(g):
            tag = "KEEP" if real else "DROP (file missing)"
            if not real:
                drop += 1
            print(f"  [{tag}] id={wid} name={name!r} file={fn} indexed={at}")
    print(f"\n{len(dup)} duplicated modules; {drop} rows whose file is missing (drop candidates). Nothing was changed.")


if __name__ == "__main__":
    main()
