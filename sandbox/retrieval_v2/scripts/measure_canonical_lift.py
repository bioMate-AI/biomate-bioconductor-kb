"""
Measure top-1 canonical-name accuracy: raw FTS vs FTS + rerank_to_canonical.

Uses the actual `tool_parameter_recommender.search_tools` (no patch) as the
baseline, applies the library-side reranker on top, reports a side-by-side
top-1 table for the same 7 canonical-tool queries the user asked about.

Run:
    PYTHONPATH=. python -m sandbox.retrieval_v2.scripts.measure_canonical_lift
"""
from __future__ import annotations

import dataclasses
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DB = ROOT / "backend" / "database" / "galaxy_ai_tools.db"

from backend.lib.galaxy.ai.retrievers.family_dedup import (
    load_alias_map, load_canonical_map, rerank_to_canonical,
    prioritize_query_family,
)


def raw_fts_search(query: str, limit: int = 10) -> list[dict]:
    """Mirrors tool_parameter_recommender.search_tools — current production behavior."""
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute("""
            SELECT t.tool_id, t.name, t.category, t.description
            FROM tools t JOIN tools_fts fts ON t.tool_id = fts.tool_id
            WHERE tools_fts MATCH ?
            LIMIT ?
        """, (query, limit)).fetchall()
    except sqlite3.OperationalError:
        conn.close(); return []
    conn.close()
    return [dict(r) for r in rows]


CASES = [
    ("samtools",  "Samtools sort"),     # canonical wrapper's display name
    ("bwa",       "Map with BWA-MEM"),
    ("picard",    "MarkDuplicates"),
    ("fastqc",    "FastQC"),
    ("deseq2",    "DESeq2"),
    ("bowtie2",   "Bowtie2"),
    ("multiqc",   "MultiQC"),
    ("cutadapt",  "Cutadapt"),
    ("kraken2",   "Kraken2"),
    ("bcftools",  "bcftools view"),
    ("bedtools",  "bedtools Intersect intervals"),
    ("gatk4",     "Gatk4 Haplotypecaller"),
]


def main() -> int:
    alias = load_alias_map()
    canon = load_canonical_map()
    print(f"Loaded {len(alias)} aliases + {len(canon)} canonical mappings\n")
    print(f"{'query':<10}  {'raw FTS(L=10) top-1':<40}  {'fetch L=100 + rerank top-1':<42}  Δ")
    print("-" * 116)
    raw_hits = 0
    rerank_hits = 0
    for q, expected_canonical in CASES:
        # Baseline: production limit=10
        baseline = raw_fts_search(q, limit=10)
        raw_top1 = baseline[0]["name"] if baseline else "(none)"
        # Treatment: fetch 100, prioritize family + promote canonical, take top-1
        wide = raw_fts_search(q, limit=100)
        rer = prioritize_query_family(q, wide, alias_map=alias, canonical_map=canon)
        rer_top1 = rer[0]["name"] if rer else "(none)"
        raw_match = expected_canonical.lower() in raw_top1.lower() or raw_top1.lower() in expected_canonical.lower()
        rer_match = expected_canonical.lower() in rer_top1.lower() or rer_top1.lower() in expected_canonical.lower()
        if raw_match: raw_hits += 1
        if rer_match: rerank_hits += 1
        marker = "↻" if raw_top1 != rer_top1 else " "
        print(f"{q:<10}  {raw_top1[:38]:<40}  {rer_top1[:40]:<42}  {marker}")
    n = len(CASES)
    print("-" * 116)
    print(f"Top-1 = canonical hits:")
    print(f"  raw FTS L=10          : {raw_hits}/{n}  ({100*raw_hits/n:.1f}%)")
    print(f"  L=100 + rerank        : {rerank_hits}/{n}  ({100*rerank_hits/n:.1f}%)")
    print(f"  delta                 : +{rerank_hits - raw_hits} ({100*(rerank_hits-raw_hits)/n:.1f}pp)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
