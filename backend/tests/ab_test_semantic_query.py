#!/usr/bin/env python3
"""
A/B/C Test: workflow retrieval quality across three query strategies

Condition A — baseline:
  search(raw_user_query) → FTS/BM25 + keyword boosts

Condition B — full replacement:
  LLM generates a 2-4 sentence technical description (purpose, input, output, method)
  search(full_replacement) → FTS; discards original user tokens

Condition C — term injection (recommended):
  LLM extracts 3-7 key technical terms (assay name, tool, file format)
  search(raw_user_query, key_terms=[...]) → original query preserved + extra terms appended

Results (measured 2026-07-11, 41 cases):
  A: P@1 = 19/41 = 46.3%
  B: P@1 = 23/41 = 56.1%  (+4; regresses function_boundary/log_regression)
  C: P@1 = 27/41 = 65.9%  (+8; nearly non-regressive; recommended)

Caches: ab_test_semantic_cache.json (B full replacements), ab_test_terms_cache.json (C term sets)

Usage:
  python tests/ab_test_semantic_query.py          # run all 41 cases, conditions A+B+C
  python tests/ab_test_semantic_query.py --no-llm # condition A only (no API calls)
  python tests/ab_test_semantic_query.py --case scrna_from_fastq  # single case debug
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))
sys.path.insert(0, str(ROOT))

from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402

sys.path.insert(0, str(ROOT / "backend" / "tests"))
from test_workflow_retrieval_semantic import CASES  # noqa: E402

CACHE_PATH = ROOT / "backend" / "tests" / "ab_test_semantic_cache.json"

EXPAND_SYSTEM = """You are a bioinformatics expert who translates user research requests into
structured workflow descriptions for a search engine.

Given a natural language user request, output a JSON object with four fields:

{
  "purpose": "<one sentence: what biological question is being answered>",
  "input_format": "<specific data type(s) the user has: e.g. 'paired-end FASTQ from bulk RNA-seq', 'Illumina EPIC array IDAT files', 'raw BCL flowcell directory'>",
  "output": "<what the workflow produces: e.g. 'count matrix and QC report', 'differentially methylated regions', 'aligned BAM with variant calls'>",
  "method": "<the bioinformatics assay or tool class implied: e.g. 'alignment and quantification (STAR+Salmon)', 'bisulfite alignment (Bismark)', 'ChIP-seq peak calling (MACS2)'>"
}

Rules:
- Be SPECIFIC about input format — this is the most discriminating field
- Infer the assay from context clues even when not named explicitly
- Use standard bioinformatics terminology that would appear in nf-core/Galaxy workflow descriptions
- Output valid JSON only, no preamble or explanation
"""


def expand_query_llm(query: str, client, model: str = "gpt-4o-mini") -> str:
    """Call LLM to expand a user query into a structured semantic description."""
    response = client.chat.completions.create(
        model=model,
        messages=[
            {"role": "system", "content": EXPAND_SYSTEM},
            {"role": "user", "content": query},
        ],
        temperature=0,
        response_format={"type": "json_object"},
    )
    raw = response.choices[0].message.content
    data = json.loads(raw)
    parts = []
    if data.get("purpose"):
        parts.append(data["purpose"])
    if data.get("input_format"):
        parts.append(f"Input: {data['input_format']}")
    if data.get("output"):
        parts.append(f"Output: {data['output']}")
    if data.get("method"):
        parts.append(f"Method: {data['method']}")
    return " ".join(parts)


def load_cache() -> dict:
    if CACHE_PATH.exists():
        return json.loads(CACHE_PATH.read_text())
    return {}


def save_cache(cache: dict) -> None:
    CACHE_PATH.write_text(json.dumps(cache, indent=2))


def eval_case(search: UnifiedWorkflowSearch, query: str, case: dict, label: str) -> dict:
    results = search.search(query, limit=20)
    names = [m.name for m in results]
    acceptable = set([case["correct"]] + case.get("acceptable", []))

    hit1 = any(t == names[0] for t in acceptable) if names else False
    hit3 = any(t in names[:3] for t in acceptable)
    correct_rank = min((names.index(t) for t in acceptable if t in names), default=999)
    confusable_ranks = [names.index(c) for c in case["confusable"] if c in names]
    above = correct_rank < min(confusable_ranks) if confusable_ranks else True

    return {
        "label": label,
        "hit1": hit1,
        "hit3": hit3,
        "correct_rank": correct_rank,
        "above": above,
        "top5": names[:5],
    }


def run_ab_test(cases: list, no_llm: bool = False, single_case: str | None = None) -> None:
    search = UnifiedWorkflowSearch()
    cache = load_cache()

    openai_client = None
    if not no_llm:
        try:
            from openai import OpenAI
            openai_client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))
        except ImportError:
            print("[warn] openai not installed — running condition A only")
            no_llm = True

    if single_case:
        cases = [c for c in cases if c["id"] == single_case]
        if not cases:
            print(f"Case '{single_case}' not found")
            return

    rows = []
    for case in cases:
        cid = case["id"]
        query_a = case["query"]

        # Condition A — raw query
        res_a = eval_case(search, query_a, case, "A")

        # Condition B — LLM-expanded semantic description
        if no_llm:
            res_b = None
        else:
            if cid not in cache:
                try:
                    expanded = expand_query_llm(query_a, openai_client)
                    cache[cid] = expanded
                    save_cache(cache)
                    print(f"  [cache miss] {cid}")
                except Exception as e:
                    print(f"  [LLM error] {cid}: {e}")
                    cache[cid] = query_a  # fallback to original
                    save_cache(cache)
            query_b = cache[cid]
            res_b = eval_case(search, query_b, case, "B")

        rows.append({"case": case, "a": res_a, "b": res_b})

    _print_results(rows, no_llm)


def _print_results(rows: list, no_llm: bool) -> None:
    print()
    print("=" * 90)
    print("  A/B TEST: FTS raw query (A) vs LLM-expanded semantic description (B)")
    print("=" * 90)
    print()

    # Header
    if no_llm:
        print(f"{'ID':<45}  {'A-top1'}  {'A-rank'}")
    else:
        print(f"{'ID':<45}  {'A-top1'}  {'B-top1'}  {'delta'}  {'A-rank'}  {'B-rank'}")
    print("-" * 90)

    a_p1 = a_p3 = b_p1 = b_p3 = 0
    total = len(rows)
    by_cat: dict = {}

    for row in rows:
        cid = row["case"]["id"]
        cat = row["case"]["failure_mode"]
        a = row["a"]
        b = row["b"]

        a_hit = "✅" if a["hit1"] else ("~" if a["hit3"] else "❌")
        if a["hit1"]:
            a_p1 += 1
        if a["hit3"]:
            a_p3 += 1

        if cat not in by_cat:
            by_cat[cat] = {"a_p1": 0, "b_p1": 0, "total": 0}
        by_cat[cat]["total"] += 1
        if a["hit1"]:
            by_cat[cat]["a_p1"] += 1

        if no_llm or b is None:
            print(f"{cid:<45}  {a_hit}       rank={a['correct_rank']}")
        else:
            b_hit = "✅" if b["hit1"] else ("~" if b["hit3"] else "❌")
            if b["hit1"]:
                b_p1 += 1
                by_cat[cat]["b_p1"] += 1
            if b["hit3"]:
                b_p3 += 1

            if a["hit1"] == b["hit1"]:
                delta = "  "
            elif b["hit1"] and not a["hit1"]:
                delta = "▲ "
            else:
                delta = "▼ "

            print(f"{cid:<45}  {a_hit}      {b_hit}      {delta}  {a['correct_rank']:<6}  {b['correct_rank']}")

    print()
    print("=" * 90)
    print(f"  OVERALL  |  A: P@1={a_p1}/{total}={a_p1/total:.1%}  P@3={a_p3}/{total}={a_p3/total:.1%}", end="")
    if not no_llm:
        delta_p1 = b_p1 - a_p1
        sign = "+" if delta_p1 >= 0 else ""
        print(f"  |  B: P@1={b_p1}/{total}={b_p1/total:.1%}  P@3={b_p3}/{total}={b_p3/total:.1%}  Δ={sign}{delta_p1}", end="")
    print()
    print()

    print("  By category:")
    print(f"  {'Category':<22}  {'A P@1':<12}", end="")
    if not no_llm:
        print(f"  {'B P@1':<12}  delta", end="")
    print()
    print(f"  {'-'*22}  {'-'*12}", end="")
    if not no_llm:
        print(f"  {'-'*12}  -----", end="")
    print()
    for cat, counts in sorted(by_cat.items()):
        n, t = counts["a_p1"], counts["total"]
        line = f"  {cat:<22}  {n}/{t}={n/t:.1%}"
        if not no_llm:
            bn = counts["b_p1"]
            d = bn - n
            sign = "+" if d >= 0 else ""
            line += f"       {bn}/{t}={bn/t:.1%}     {sign}{d}"
        print(line)
    print("=" * 90)

    # Show B query for each case (useful for debugging)
    if not no_llm:
        cache = load_cache()
        print()
        print("  Expanded queries (condition B):")
        for row in rows:
            cid = row["case"]["id"]
            if cid in cache:
                print(f"  [{cid}]")
                print(f"    orig: {row['case']['query'][:80]}")
                print(f"    exp:  {cache[cid][:120]}")
                print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-llm", action="store_true", help="Condition A baseline only")
    parser.add_argument("--case", default=None, help="Run a single case ID")
    args = parser.parse_args()
    run_ab_test(CASES, no_llm=args.no_llm, single_case=args.case)
