"""Targeted differentiation of the 3 genuinely ambiguous bulk RNA-seq chains.

Audit context: 10 transcriptomics 3-step chains. Of those, 7 are differentiated
by assay (CAGE-seq, GeoMx spatial, small-RNA), method family (Piano, EGSEA,
ExpHunterSuite), or data source (recount2). Three target the SAME intent
("bulk RNA-seq → DE → enrichment") but in different execution shapes:

  bulk_rnaseq_de_analysis           — nf-core production pipeline path
  bulk_rnaseq_consensus_de_bioc     — Bioconductor handoff (full + bare R)
  bioc_bulk_rnaseq_de_v2            — downstream-only (count matrix start)

Their pre-update descriptions don't make the differentiation explicit, so a
plain "DESeq2 + clusterProfiler" query is ambiguous between all three. This
script writes explicit "Use this when..." language into chain.description.

Usage:
    python scripts/differentiate_ambiguous_chains.py --dry-run
    python scripts/differentiate_ambiguous_chains.py --apply
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
from pathlib import Path

DB = Path(__file__).resolve().parents[1] / "database" / "galaxy_ai_tools.db"

UPDATES = {
    "bulk_rnaseq_de_analysis": {
        "description": (
            "Production nf-core bulk RNA-seq DE pipeline. Use this when you want a "
            "one-click multi-method DE analysis (DESeq2 + limma-voom run in parallel) "
            "with bundled GSEA over MSigDB/KEGG/Reactome, HTML report, volcano plots, "
            "and PCA — production-grade FAIR outputs from raw FASTQ. "
            "Pick this for routine production analyses. "
            "Pick `bulk_rnaseq_consensus_de_bioc` instead when you want the "
            "Bioconductor-canonical bare-R path with swappable DE methods and "
            "R Markdown narrative output. "
            "Pick `bioc_bulk_rnaseq_de_v2` instead when you already have a "
            "pre-computed count matrix and want pure downstream Bioc analysis."
        ),
    },
    "bulk_rnaseq_consensus_de_bioc": {
        "description": (
            "Bioconductor-canonical bulk RNA-seq DE chain: nf-core/rnaseq for FASTQ "
            "processing + bare-R DESeq2 (single-method) + clusterProfiler ORA "
            "(over-representation on the DE gene list). Step 2 is the swap point — "
            "substitute edgeR / limma / DSS / EBSeq / baySeq / IHW when the "
            "experimental design calls for it (multi-method consensus DE). "
            "Use this for teaching, R Markdown narrative output with full sessionInfo, "
            "or when you want explicit programmatic R control and Bioconductor-style "
            "consensus comparisons. "
            "Pick `bulk_rnaseq_de_analysis` instead for the one-click nf-core pipeline "
            "with bundled multi-method + GSEA + HTML report. "
            "Pick `bioc_bulk_rnaseq_de_v2` instead when you already have a count "
            "matrix and don't need upstream FASTQ processing."
        ),
    },
    "bioc_bulk_rnaseq_de_v2": {
        "description": (
            "Pure-downstream Bioconductor RNA-seq analysis: DESeq2 differential "
            "expression on a pre-computed count matrix, then clusterProfiler ORA, "
            "then enrichplot visualization (dotplot, GSEA plots, emapPlot). "
            "Use this when you ALREADY have a counts table (from Salmon, STAR, "
            "featureCounts, recount2, or any external pipeline) and want bare-R "
            "Bioconductor downstream analysis without rerunning FASTQ processing. "
            "Pick `bulk_rnaseq_consensus_de_bioc` instead when you have raw FASTQ "
            "and need the full upstream nf-core/rnaseq processing. "
            "Pick `bulk_rnaseq_de_analysis` instead for the one-click nf-core "
            "production pipeline with bundled HTML report and GSEA."
        ),
    },
}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--apply", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()
    if not (args.apply or args.dry_run):
        p.error("pass --dry-run or --apply")

    if not DB.exists():
        print(f"DB not found: {DB}", file=sys.stderr)
        return 2

    names = list(UPDATES.keys())
    backup_path = DB.parent / f"differentiate_ambiguous_chains_backup_{time.strftime('%Y%m%dT%H%M%S')}.json"

    con = sqlite3.connect(DB)
    try:
        for name in names:
            row = con.execute(
                "SELECT length(description) FROM workflow_chains WHERE name=?", (name,)
            ).fetchone()
            if row is None:
                print(f"  MISSING in DB: {name}")
                return 2
            print(f"  before  {name:40}  desc_len={row[0]}")

        if args.dry_run:
            print("\n(dry-run — no changes written)")
            return 0

        cur = con.execute(
            f"SELECT name, description FROM workflow_chains WHERE name IN ({','.join('?'*len(names))})",
            names,
        )
        backup = [dict(zip([c[0] for c in cur.description], r)) for r in cur.fetchall()]
        backup_path.write_text(json.dumps(backup, indent=2, default=str))
        print(f"  backed up {len(backup)} chain row(s) to {backup_path}")

        with con:
            for name, fields in UPDATES.items():
                sets = ", ".join(f"{k}=?" for k in fields)
                values = list(fields.values()) + [name]
                con.execute(f"UPDATE workflow_chains SET {sets} WHERE name=?", values)
                print(f"  updated {name}")

        for name in names:
            row = con.execute(
                "SELECT length(description) FROM workflow_chains WHERE name=?", (name,)
            ).fetchone()
            print(f"  after   {name:40}  desc_len={row[0]}")

        print("\ndone.")
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    sys.exit(main())
