#!/usr/bin/env python3
"""Idempotent data-quality fix: front-load the DISCRIMINATOR into workflow descriptions so it survives the
routing catalog's description[:120] truncation (production UnifiedWorkflowSearch._browse_catalog_with_llm and
the RealBio routing eval both truncate at 120 chars).

ROOT CAUSE (docs/20261025_BENCHMARK_ERROR_ANALYSIS_ROOTCAUSE.md): `nf-core/scnanoseq` is the Oxford Nanopore
LONG-READ single-cell pipeline, but its description opened with "...for 10X Genomics single-cell/nuclei
RNA-seq data derived from Oxford Nanopore..." — "Oxford Nanopore" fell at ~char 130, past the [:120] cut, so
a "10x Genomics / Cell Ranger" SHORT-READ query lexically matched scnanoseq over the correct nf-core/scrnaseq.
`nf-core/scrnaseq` did not front-load "10X / Cell Ranger / short-read" either. `nf-core/mhcquant` buried
"Comet database search" past char 120. This mis-routes in PRODUCTION too (same descriptions, same truncation).

Fix: prepend a short discriminator lead (kept < ~115 chars so it survives [:120]) to each affected
description, preserving the existing curated text. Idempotent: re-running is a no-op (guarded by a marker).

Apply to the canonical workflow DB via the normal DB-maintenance path (the local backend/database copy is a
draft for measurement; the canonical DB lives on dev + S3 per reference_workflow_db_canonical).

Usage:  python3 scripts/fix_routing_descriptions_20261025.py [--db PATH] [--dry-run]
"""
import argparse, os, sqlite3

# name -> discriminator lead (prepended once). Keep each lead < ~115 chars so the key terms survive desc[:120].
LEADS = {
    "nf-core/scnanoseq":
        "OXFORD NANOPORE LONG-READ single-cell/nuclei RNA-seq (ONT Q20+); for SHORT-READ 10X use nf-core/scrnaseq.",
    "nf-core/scrnaseq":
        "10X SHORT-READ single-cell RNA-seq (Cell Ranger/STARsolo/alevin-fry); Nanopore long-read uses nf-core/scnanoseq.",
    "nf-core/mhcquant":
        "IMMUNOPEPTIDOMICS MS database search (Comet) of peptides eluted from MHC class I/II (MHC-IP).",
}
MARKER_PREFIXES = tuple(v[:24] for v in LEADS.values())  # idempotency guard


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=os.path.join(os.path.dirname(__file__), "..", "backend", "database", "galaxy_ai_tools.db"))
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    con = sqlite3.connect(os.path.abspath(a.db))
    changed = skipped = missing = 0
    for name, lead in LEADS.items():
        row = con.execute("SELECT description FROM workflows WHERE name=?", (name,)).fetchone()
        if row is None:
            print(f"  MISSING  {name} (not in DB)"); missing += 1; continue
        cur = (row[0] or "").strip()
        if cur.startswith(lead[:24]):
            print(f"  skip     {name} (already front-loaded)"); skipped += 1; continue
        new = lead + " " + cur
        print(f"  UPDATE   {name}: now leads -> {new[:120]!r}")
        if not a.dry_run:
            con.execute("UPDATE workflows SET description=? WHERE name=?", (new, name))
        changed += 1
    if not a.dry_run:
        con.commit()
    con.close()
    print(f"\n{'[dry-run] ' if a.dry_run else ''}changed={changed} skipped={skipped} missing={missing}")


if __name__ == "__main__":
    main()
