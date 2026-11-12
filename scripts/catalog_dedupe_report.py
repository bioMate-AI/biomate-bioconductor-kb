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


def norm(name: str) -> str:
    import re
    return re.sub(r"[^a-z0-9]+", "", (name or "").lower())


def main():
    db, backend_root = sys.argv[1], sys.argv[2]
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    rows = con.execute("SELECT id, name, filename, indexed_at, source, domain, format FROM workflows").fetchall()
    # Chains reference workflows by NAME — a row a chain names must never be dropped.
    chain_refs = set()
    for (steps,) in con.execute("SELECT steps FROM workflow_chains"):
        try:
            import json
            for st in json.loads(steps or "[]"):
                chain_refs.add(norm(st.get("workflow_name", "")))
        except Exception:
            pass
    groups = defaultdict(list)
    for wid, name, fn, at, src, dom, fmt in rows:
        real = resolve(backend_root, fn or "") if (fmt or "").lower() in ("nextflow", "nf", "") else None
        key = ("file", real) if real else ("name", norm(name), (dom or "").lower())
        groups[key].append((wid, name, fn, at, src, real))
    # rows of one module indexed under a path that no longer exists → group with the existing file by name
    by_name = defaultdict(list)
    for (k, g) in groups.items():
        for r in g:
            by_name[(norm(r[1]))].append((k, r))
    dup = {k: g for k, g in groups.items() if len(g) > 1}
    for nm, items in by_name.items():
        keys = {k for k, _ in items}
        if len(keys) > 1 and any(k[0] == "file" for k in keys) and any(k[0] == "name" for k in keys):
            dup.setdefault(("merged-name", nm), [r for _, r in items])
    drop = 0
    for k, g in sorted(dup.items(), key=lambda x: str(x[0])):
        keep_ids = {r[0] for r in g if r[5]} or {min(r[0] for r in g)}
        print(f"\n== {k[0]}: {k[1]}  ({len(g)} rows)")
        for wid, name, fn, at, src, real in sorted(g):
            is_keep = wid in keep_ids if len(keep_ids) < len(g) else wid == min(keep_ids)
            tag = "KEEP" if is_keep else "DROP"
            note = " — referenced by a chain" if (tag == "DROP" and norm(name) in chain_refs and not any(norm(x[1]) == norm(name) and x[0] in keep_ids for x in g)) else ""
            if tag == "DROP":
                drop += 1
            print(f"  [{tag}] id={wid} src={src} name={name!r} file={fn} {'(on disk)' if real else '(file missing)' if (fn or '').endswith('.nf') else ''}{note}")
    print(f"\n{len(dup)} duplicate groups across all sources; {drop} drop candidates. Nothing was changed.")


if __name__ == "__main__":
    main()
