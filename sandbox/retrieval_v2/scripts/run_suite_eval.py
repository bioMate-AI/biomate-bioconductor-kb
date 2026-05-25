"""
A/B evaluation: flat wrapper-level search vs canonical suite-level search.

Runs the 30-query suite_eval_set.yaml through two retrieval paths:

  FLAT     — query the existing galaxy_ai_tools.db `tools_fts` index, then
             collapse the wrapper-level results to suite_ids using the
             tool_wrapper_mapping table for fair comparison.
  CANONICAL — query the new sandbox/retrieval_v2/output/tool_canonical.db
             `suites_fts` index directly.

Metrics: top1_hit, top3_hit, top10_hit, mean_candidate_count.

Run:
    PYTHONPATH=. python -m sandbox.retrieval_v2.scripts.run_suite_eval

Read-only.
"""
from __future__ import annotations

import re
import sqlite3
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple

import yaml

from sandbox.retrieval_v2.retrievers.tool_catalog import search_tool_suites

ROOT = Path(__file__).resolve().parents[3]
EVAL_YAML = Path(__file__).resolve().parents[1] / "tests" / "suite_eval_set.yaml"
PROD_DB = ROOT / "backend" / "database" / "galaxy_ai_tools.db"
CANONICAL_DB = Path(__file__).resolve().parents[1] / "output" / "tool_canonical.db"

_FTS_SAFE_PAT = re.compile(r"[^a-zA-Z0-9_ ]+")


def _fts_sanitize(q: str) -> str:
    cleaned = _FTS_SAFE_PAT.sub(" ", q).strip()
    tokens = [t for t in cleaned.split() if len(t) >= 2]
    if not tokens:
        return '""'
    return " OR ".join(tokens) if len(tokens) > 1 else tokens[0]


def flat_search(query: str, top_k: int = 10) -> List[str]:
    """Flat wrapper-level search collapsed to ordered, deduped suite_ids.

    Mirrors what the existing /api/ai_assistant/search_ranked endpoint does
    at the FTS layer (without the BGE bonus, which we don't have at the
    suite-id level for fair comparison).
    """
    fts_q = _fts_sanitize(query)
    prod = sqlite3.connect(f"file:{PROD_DB}?mode=ro", uri=True)
    canon = sqlite3.connect(f"file:{CANONICAL_DB}?mode=ro", uri=True)
    prod.row_factory = sqlite3.Row
    canon.row_factory = sqlite3.Row
    try:
        rows = prod.execute(
            """
            SELECT t.tool_id
            FROM tools_fts f
            JOIN tools t USING(tool_id)
            WHERE tools_fts MATCH ?
            ORDER BY bm25(tools_fts)
            LIMIT 100
            """,
            (fts_q,),
        ).fetchall()
    except sqlite3.OperationalError:
        prod.close(); canon.close()
        return []

    # Map wrappers → suite_ids, preserve rank order, dedup.
    suite_order: List[str] = []
    seen: Set[str] = set()
    for r in rows:
        m = canon.execute(
            "SELECT suite_id FROM tool_wrapper_mapping WHERE wrapper_tool_id = ?",
            (r["tool_id"],),
        ).fetchone()
        if not m:
            continue
        sid = m["suite_id"]
        if sid in seen:
            continue
        seen.add(sid)
        suite_order.append(sid)
        if len(suite_order) >= top_k:
            break
    prod.close(); canon.close()
    return suite_order


def canonical_search(query: str, top_k: int = 10) -> List[str]:
    results = search_tool_suites(query, top_k=top_k)
    return [r["suite_id"] for r in results]


def _hit_at(expected: List[str], ranked: List[str], k: int) -> bool:
    expected_norm = {e.lower() for e in expected}
    for sid in ranked[:k]:
        if sid.lower() in expected_norm:
            return True
        # Also accept prefix-match for variants like bwa_mem when bwa expected
        sid_l = sid.lower()
        if any(sid_l.startswith(e + "_") or sid_l.startswith(e + "-") for e in expected_norm):
            return True
    return False


def main() -> int:
    if not EVAL_YAML.exists():
        print(f"ERROR: eval set not found at {EVAL_YAML}", file=sys.stderr); return 1
    cases = yaml.safe_load(EVAL_YAML.read_text())
    print(f"Loaded {len(cases)} eval cases")

    metrics: Dict[str, Dict[str, float]] = {
        "FLAT":       {"top1": 0, "top3": 0, "top10": 0, "candidates": 0},
        "CANONICAL":  {"top1": 0, "top3": 0, "top10": 0, "candidates": 0},
    }
    rows = []

    for c in cases:
        q = c["query"]; exp = c["expected"]
        flat_ranked = flat_search(q, top_k=10)
        canon_ranked = canonical_search(q, top_k=10)

        rows.append({
            "id": c["id"], "query": q, "expected": exp,
            "flat_top3": flat_ranked[:3], "canon_top3": canon_ranked[:3],
            "flat_hit1": _hit_at(exp, flat_ranked, 1),
            "canon_hit1": _hit_at(exp, canon_ranked, 1),
            "flat_hit3": _hit_at(exp, flat_ranked, 3),
            "canon_hit3": _hit_at(exp, canon_ranked, 3),
        })
        for name, ranked in (("FLAT", flat_ranked), ("CANONICAL", canon_ranked)):
            if _hit_at(exp, ranked, 1):  metrics[name]["top1"] += 1
            if _hit_at(exp, ranked, 3):  metrics[name]["top3"] += 1
            if _hit_at(exp, ranked, 10): metrics[name]["top10"] += 1
            metrics[name]["candidates"] += len(ranked)

    n = len(cases)
    print(f"\n{'='*70}")
    print(f"{'Path':<12} {'top1':>8} {'top3':>8} {'top10':>8} {'mean_cands':>12}")
    print(f"{'-'*70}")
    for path, m in metrics.items():
        print(f"{path:<12} "
              f"{m['top1']/n:>7.1%} "
              f"{m['top3']/n:>7.1%} "
              f"{m['top10']/n:>7.1%} "
              f"{m['candidates']/n:>11.1f}")
    print(f"{'='*70}")

    # Show mismatches: queries where FLAT and CANONICAL disagree at top-1
    print("\nPer-query (top-3 surfaced):")
    print(f"{'id':<5} {'F1':>3} {'C1':>3}  {'query':<60}")
    print("-" * 110)
    for r in rows:
        marker_f = "✓" if r["flat_hit1"] else "✗"
        marker_c = "✓" if r["canon_hit1"] else "✗"
        print(f"{r['id']:<5} {marker_f:>3} {marker_c:>3}  {r['query'][:60]:<60}")
        if not (r["flat_hit1"] and r["canon_hit1"]):
            print(f"      expected={r['expected']}")
            print(f"      flat   ={r['flat_top3']}")
            print(f"      canon  ={r['canon_top3']}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
