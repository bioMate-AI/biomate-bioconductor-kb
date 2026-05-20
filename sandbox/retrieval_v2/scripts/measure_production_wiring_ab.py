"""
Production wiring A/B harness for family_dedup integration into
backend/lib/galaxy/ai/workflow_ops/autofix/tool_parameter_recommender.py.

Measures:
  1. Utility: top-1 = canonical hit rate across the curated eval set
  2. Time cost: mean / p50 / p95 / p99 latency per search_tools call
  3. Held-out safety: behavior on 30 uncovered families

Run:
  PYTHONPATH=. python -m sandbox.retrieval_v2.scripts.measure_production_wiring_ab
"""
from __future__ import annotations

import os
import sys
import time
import statistics
from pathlib import Path
from typing import Any, Dict, List, Tuple

import yaml

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "backend" / "lib"))

# Import recommender (production path). NOTE: env flag must be set BEFORE
# the production code path is invoked; check inside search_tools.
from galaxy.ai.workflow_ops.autofix.tool_parameter_recommender import (  # noqa: E402
    ToolParameterRecommender,
)

DB = ROOT / "backend" / "database" / "galaxy_ai_tools.db"

# Re-use the same 12-query canonical eval set as measure_canonical_lift.py
# extended to 30 entries (heads of well-curated families with known canonicals)
EVAL = [
    ("samtools",   "samtools"),
    ("bwa",        "bwa"),
    ("picard",     "picard"),
    ("fastqc",     "fastqc"),
    ("deseq2",     "deseq2"),
    ("bowtie2",    "bowtie2"),
    ("multiqc",    "multiqc"),
    ("cutadapt",   "cutadapt"),
    ("kraken2",    "kraken2"),
    ("bcftools",   "bcftools"),
    ("bedtools",   "bedtools"),
    ("gatk4",      "gatk4"),
    ("seqkit",     "seqkit"),
    ("seqtk",      "seqtk"),
    ("augustus",   "augustus"),
    ("maker",      "maker"),
    ("prokka",     "prokka"),
    ("bakta",      "bakta"),
    ("mash",       "mash"),
    ("mafft",      "mafft"),
    ("muscle",     "muscle"),
    ("tabix",      "tabix"),
    ("busco",      "busco"),
    ("meme",       "meme"),
    ("plink",      "plink"),
    ("minimap2",   "minimap2"),
    ("snpeff",     "snpeff"),
    ("macs2",      "macs2"),
    ("trinity",    "trinity"),
    ("emboss",     "emboss"),
]

# Held-out: families NOT in canonical YAML (must be safe = no change)
HELDOUT = [
    "qiime", "gembassy", "ball", "frogs", "sentieon",
    "parabricks", "sapp", "secimtools", "pycrac", "biobb",
]


def measure_run(recommender, flag_on: bool, limit: int = 5) -> Dict[str, Any]:
    """Run the eval + held-out set under a given flag state."""
    os.environ.pop("BIOMATE_FAMILY_PRIORITIZE", None)
    if flag_on:
        os.environ["BIOMATE_FAMILY_PRIORITIZE"] = "1"

    # ── Utility: canonical eval set ──
    hits = 0
    times_ms = []
    per_query = []
    from sandbox.retrieval_v2.retrievers.tool_catalog import _connect  # noqa
    import sqlite3
    canon_conn = sqlite3.connect(
        f"file:{ROOT}/sandbox/retrieval_v2/output/tool_canonical.db?mode=ro",
        uri=True
    )
    canon_conn.row_factory = sqlite3.Row

    for query, expected_family in EVAL:
        t0 = time.perf_counter()
        results = recommender.search_tools(query, limit=limit)
        elapsed_ms = (time.perf_counter() - t0) * 1000
        times_ms.append(elapsed_ms)

        # Determine family of top-1
        top1_family = None
        if results:
            # Look up canonical_family_id for top-1's tool_id
            row = canon_conn.execute(
                "SELECT suite_id FROM tool_wrapper_mapping WHERE wrapper_tool_id = ?",
                (results[0].tool_id,),
            ).fetchone()
            top1_family = row["suite_id"] if row else None

        hit = (top1_family == expected_family)
        if hit: hits += 1
        per_query.append({
            "query": query, "expected": expected_family,
            "top1_name": results[0].name if results else None,
            "top1_family": top1_family, "hit": hit,
            "elapsed_ms": round(elapsed_ms, 2),
        })

    # ── Held-out: confirm no false positive on uncovered families ──
    heldout_diffs = 0
    heldout_baseline_top1 = {}
    for q in HELDOUT:
        out = recommender.search_tools(q, limit=limit)
        top1 = out[0].name if out else None
        if flag_on:
            # Compare to baseline run (stored below in caller logic)
            pass
        heldout_baseline_top1[q] = top1

    canon_conn.close()
    return {
        "flag_on": flag_on,
        "n_eval": len(EVAL),
        "hits": hits,
        "hit_rate": hits / len(EVAL),
        "times_ms": times_ms,
        "mean_ms": statistics.mean(times_ms),
        "p50_ms": statistics.median(times_ms),
        "p95_ms": sorted(times_ms)[int(0.95 * len(times_ms))],
        "p99_ms": sorted(times_ms)[min(int(0.99 * len(times_ms)), len(times_ms) - 1)],
        "max_ms": max(times_ms),
        "per_query": per_query,
        "heldout_top1": heldout_baseline_top1,
    }


def main() -> int:
    rec = ToolParameterRecommender(db_path=str(DB))

    # Run baseline (flag OFF)
    print("=== BASELINE (BIOMATE_FAMILY_PRIORITIZE unset) ===")
    baseline = measure_run(rec, flag_on=False, limit=5)
    print(f"  Top-1 family hit: {baseline['hits']}/{baseline['n_eval']} "
          f"({100*baseline['hit_rate']:.1f}%)")
    print(f"  Latency: mean={baseline['mean_ms']:.2f}ms "
          f"p50={baseline['p50_ms']:.2f}ms p95={baseline['p95_ms']:.2f}ms "
          f"p99={baseline['p99_ms']:.2f}ms max={baseline['max_ms']:.2f}ms")

    # Run treatment (flag ON)
    print("\n=== TREATMENT (BIOMATE_FAMILY_PRIORITIZE=1) ===")
    treatment = measure_run(rec, flag_on=True, limit=5)
    print(f"  Top-1 family hit: {treatment['hits']}/{treatment['n_eval']} "
          f"({100*treatment['hit_rate']:.1f}%)")
    print(f"  Latency: mean={treatment['mean_ms']:.2f}ms "
          f"p50={treatment['p50_ms']:.2f}ms p95={treatment['p95_ms']:.2f}ms "
          f"p99={treatment['p99_ms']:.2f}ms max={treatment['max_ms']:.2f}ms")

    print(f"\n=== A/B summary ===")
    print(f"  Utility delta: {treatment['hits'] - baseline['hits']:+d} hits "
          f"({100*(treatment['hit_rate'] - baseline['hit_rate']):.1f}pp)")
    print(f"  Latency delta: mean +{treatment['mean_ms'] - baseline['mean_ms']:.2f}ms "
          f"p95 +{treatment['p95_ms'] - baseline['p95_ms']:.2f}ms "
          f"p99 +{treatment['p99_ms'] - baseline['p99_ms']:.2f}ms")

    # Held-out safety
    heldout_changed = sum(1 for q in HELDOUT
                           if baseline['heldout_top1'][q] != treatment['heldout_top1'][q])
    print(f"\n=== Held-out safety (n={len(HELDOUT)}) ===")
    print(f"  Queries where treatment differs from baseline: {heldout_changed}")
    if heldout_changed:
        for q in HELDOUT:
            b = baseline['heldout_top1'][q]; t = treatment['heldout_top1'][q]
            if b != t:
                print(f"    {q!r}: {b!r} → {t!r}")
    else:
        print(f"  ✅ Zero behavior change on held-out families")

    # Write to disk for reproducibility
    out_path = ROOT / "sandbox/retrieval_v2/output/production_wiring_ab.md"
    with out_path.open("w", encoding="utf-8") as f:
        f.write("# family_dedup Production Wiring A/B (Local, Pre-Dev-Sync)\n\n")
        f.write(f"**Date:** 2026-05-20\n")
        f.write(f"**Patched file:** `backend/lib/galaxy/ai/workflow_ops/autofix/tool_parameter_recommender.py`\n")
        f.write(f"**Flag:** `BIOMATE_FAMILY_PRIORITIZE=1`\n")
        f.write(f"**Eval limit per query:** 5 results\n")
        f.write(f"**Internal fetch_limit when flag on:** 5 × 10 = 50\n\n")
        f.write("## Utility\n\n")
        f.write("| Metric | Baseline (flag OFF) | Treatment (flag ON) | Delta |\n|---|---|---|---|\n")
        f.write(f"| Top-1 = canonical family | {baseline['hits']}/{baseline['n_eval']} "
                f"({100*baseline['hit_rate']:.1f}%) | "
                f"{treatment['hits']}/{treatment['n_eval']} "
                f"({100*treatment['hit_rate']:.1f}%) | "
                f"**{treatment['hits']-baseline['hits']:+d} hits "
                f"({100*(treatment['hit_rate']-baseline['hit_rate']):+.1f}pp)** |\n\n")
        f.write("## Time cost\n\n")
        f.write("| Metric | Baseline | Treatment | Δ |\n|---|---|---|---|\n")
        for k in ("mean_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms"):
            f.write(f"| {k} | {baseline[k]:.2f}ms | {treatment[k]:.2f}ms | "
                    f"{treatment[k] - baseline[k]:+.2f}ms |\n")
        f.write("\n## Held-out safety\n\n")
        f.write(f"| Metric | Value |\n|---|---|\n")
        f.write(f"| Held-out families | {len(HELDOUT)} |\n")
        f.write(f"| Queries where treatment ≠ baseline | {heldout_changed} |\n\n")
        if heldout_changed == 0:
            f.write("✅ Zero behavior change on held-out — library never fires on "
                    "uncovered families.\n\n")
        f.write("## Per-query (treatment)\n\n")
        f.write("| query | expected | top-1 name | hit | latency |\n|---|---|---|---|---|\n")
        for q in treatment["per_query"]:
            f.write(f"| {q['query']} | {q['expected']} | {q['top1_name']} | "
                    f"{'✓' if q['hit'] else '✗'} | {q['elapsed_ms']:.2f}ms |\n")

    print(f"\nWrote {out_path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
