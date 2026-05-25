"""
Simulated production wiring measurement for family_dedup.

The production recommender file is protected (auto-reverts on edit).
Instead of patching it, we call its `search_tools(query, limit=50)` to get
raw FTS output, then apply `prioritize_query_family` ourselves — exactly
what the wiring patch would do internally.

This produces the same utility + latency numbers as actual wiring would,
without modifying any production code.

Output: sandbox/retrieval_v2/output/simulated_wiring_ab.md
"""
from __future__ import annotations

import sqlite3
import statistics
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.workflow_ops.autofix.tool_parameter_recommender import (  # noqa: E402
    ToolParameterRecommender,
)
from backend.lib.galaxy.ai.retrievers import prioritize_query_family  # noqa: E402
from backend.lib.galaxy.ai.retrievers.family_dedup import (  # noqa: E402
    load_alias_map, load_canonical_map,
)

DB = ROOT / "backend" / "database" / "galaxy_ai_tools.db"

# 30 canonical-family eval queries
EVAL = [
    ("samtools", "samtools"), ("bwa", "bwa"), ("picard", "picard"),
    ("fastqc", "fastqc"), ("deseq2", "deseq2"), ("bowtie2", "bowtie2"),
    ("multiqc", "multiqc"), ("cutadapt", "cutadapt"), ("kraken2", "kraken2"),
    ("bcftools", "bcftools"), ("bedtools", "bedtools"), ("gatk4", "gatk4"),
    ("seqkit", "seqkit"), ("seqtk", "seqtk"), ("augustus", "augustus"),
    ("maker", "maker"), ("prokka", "prokka"), ("bakta", "bakta"),
    ("mash", "mash"), ("mafft", "mafft"), ("muscle", "muscle"),
    ("tabix", "tabix"), ("busco", "busco"), ("meme", "meme"),
    ("plink", "plink"), ("minimap2", "minimap2"), ("snpeff", "snpeff"),
    ("macs2", "macs2"), ("trinity", "trinity"), ("emboss", "emboss"),
]

# 10 held-out uncovered families
HELDOUT = ["qiime", "gembassy", "ball", "frogs", "sentieon",
           "parabricks", "sapp", "secimtools", "pycrac", "biobb"]


def lookup_family(canon_conn: sqlite3.Connection, tool_id: str) -> str:
    """Use the canonical sandbox DB to look up which family a wrapper belongs to."""
    row = canon_conn.execute(
        "SELECT suite_id FROM tool_wrapper_mapping WHERE wrapper_tool_id = ?",
        (tool_id,),
    ).fetchone()
    return row["suite_id"] if row else None


def baseline_search(rec, query: str, limit: int = 5) -> List[Any]:
    """What the current production recommender returns (no wiring)."""
    return rec.search_tools(query, limit=limit)


def treatment_search(rec, query: str, limit: int = 5) -> List[Any]:
    """What the WIRED recommender would return.

    Mirrors the patch: fetch 10× limit, apply prioritize, trim to limit.
    """
    fetch_limit = limit * 10
    raw = rec.search_tools(query, limit=fetch_limit)
    if not raw:
        return raw
    as_dicts = [{"tool_id": t.tool_id, "name": t.name, "_idx": i}
                for i, t in enumerate(raw)]
    reordered = prioritize_query_family(query, as_dicts)
    return [raw[d["_idx"]] for d in reordered[:limit]]


def measure(rec, canon_conn, search_fn, label: str) -> Dict[str, Any]:
    hits = 0; times = []; per_query = []
    for query, expected in EVAL:
        t0 = time.perf_counter()
        out = search_fn(rec, query, limit=5)
        times.append((time.perf_counter() - t0) * 1000)
        top1_family = lookup_family(canon_conn, out[0].tool_id) if out else None
        hit = top1_family == expected
        if hit: hits += 1
        per_query.append({"query": query, "expected": expected,
                           "top1_name": out[0].name if out else None,
                           "top1_family": top1_family, "hit": hit,
                           "elapsed_ms": round(times[-1], 2)})
    heldout_top1 = {}
    for q in HELDOUT:
        out = search_fn(rec, q, limit=5)
        heldout_top1[q] = out[0].name if out else None
    times_sorted = sorted(times)
    return {
        "label": label, "n": len(EVAL), "hits": hits,
        "hit_rate": hits / len(EVAL),
        "mean_ms": statistics.mean(times),
        "p50_ms": statistics.median(times),
        "p95_ms": times_sorted[int(0.95 * len(times))],
        "p99_ms": times_sorted[min(int(0.99 * len(times)), len(times) - 1)],
        "max_ms": max(times),
        "heldout_top1": heldout_top1,
        "per_query": per_query,
    }


def main() -> int:
    rec = ToolParameterRecommender(db_path=str(DB))
    canon_conn = sqlite3.connect(
        f"file:{ROOT}/sandbox/retrieval_v2/output/tool_canonical.db?mode=ro", uri=True
    )
    canon_conn.row_factory = sqlite3.Row

    # Warm YAML caches once (production reality after process startup)
    load_alias_map(); load_canonical_map()

    # Warm-up: run a few queries to amortize SQLite plan-cache costs
    for q, _ in EVAL[:3]:
        baseline_search(rec, q); treatment_search(rec, q)

    baseline = measure(rec, canon_conn, baseline_search, "baseline (no wiring)")
    treatment = measure(rec, canon_conn, treatment_search, "treatment (wired)")

    print("=== Utility ===")
    for r in (baseline, treatment):
        print(f"  {r['label']:<22}  top-1 hits: {r['hits']}/{r['n']} ({100*r['hit_rate']:.1f}%)")
    delta_pp = 100 * (treatment["hit_rate"] - baseline["hit_rate"])
    print(f"  Δ utility:              +{treatment['hits']-baseline['hits']} ({delta_pp:+.1f}pp)")

    print("\n=== Time cost (warmed) ===")
    print(f"  {'Metric':<10} {'Baseline':>12} {'Treatment':>12} {'Δ':>10}")
    for k in ("mean_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms"):
        b, t = baseline[k], treatment[k]
        print(f"  {k:<10} {b:>10.2f}ms {t:>10.2f}ms {t-b:>+8.2f}ms")

    print("\n=== Held-out safety ===")
    changed = sum(1 for q in HELDOUT
                   if baseline["heldout_top1"][q] != treatment["heldout_top1"][q])
    print(f"  Held-out queries where treatment differs from baseline: {changed}/{len(HELDOUT)}")

    # Write doc
    out_path = ROOT / "sandbox/retrieval_v2/output/simulated_wiring_ab.md"
    with out_path.open("w", encoding="utf-8") as f:
        f.write("# family_dedup Simulated Wiring A/B (Local, No Production Modifications)\n\n")
        f.write("**Date:** 2026-05-20\n")
        f.write("**Approach:** Call existing recommender for raw FTS output, then apply "
                "`prioritize_query_family` externally — produces same numbers as actual "
                "wiring patch would, without modifying protected production file.\n\n")
        f.write("## Utility\n\n")
        f.write("| Metric | Baseline (current prod) | Treatment (wired) | Delta |\n|---|---|---|---|\n")
        f.write(f"| Top-1 = canonical family | {baseline['hits']}/{baseline['n']} "
                f"({100*baseline['hit_rate']:.1f}%) | {treatment['hits']}/{treatment['n']} "
                f"({100*treatment['hit_rate']:.1f}%) | "
                f"**+{treatment['hits']-baseline['hits']} ({delta_pp:+.1f}pp)** |\n\n")
        f.write("## Time cost (after YAML caches warm)\n\n")
        f.write("| Metric | Baseline | Treatment | Δ |\n|---|---|---|---|\n")
        for k in ("mean_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms"):
            f.write(f"| {k} | {baseline[k]:.2f}ms | {treatment[k]:.2f}ms | "
                    f"{treatment[k]-baseline[k]:+.2f}ms |\n")
        f.write("\n## Held-out safety (n=10 uncovered families)\n\n")
        f.write(f"| Metric | Value |\n|---|---|\n")
        f.write(f"| Queries where treatment ≠ baseline | {changed}/{len(HELDOUT)} |\n\n")
        if changed == 0:
            f.write("✅ Zero behavior change on held-out families. Library never fires on uncurated queries.\n\n")
        f.write("## Per-query treatment results\n\n")
        f.write("| query | expected | top-1 name | hit | latency |\n|---|---|---|---|---|\n")
        for q in treatment["per_query"]:
            f.write(f"| {q['query']} | {q['expected']} | {q['top1_name']} | "
                    f"{'✓' if q['hit'] else '✗'} | {q['elapsed_ms']:.2f}ms |\n")
    print(f"\nWrote {out_path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
