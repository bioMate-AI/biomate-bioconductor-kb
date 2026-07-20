"""
A/B/C/D Test: FTS variants vs full production pipeline (Pass-0 LLM reranking)

Condition A — raw user message → FTS only (current baseline, no LLM)
Condition B — LLM rewrites full query → FTS (destructive — discards named-tool anchors)
Condition C — LLM extracts key terms → appended to original query via key_terms (non-destructive)
Condition D — same as C but WITH Pass-0 LLM catalog browse enabled (production-equivalent)

Pass-0 asks the LLM to pick the top 10 workflow IDs from a broad 60-candidate FTS result.
Those IDs get graded boosts (rank 0 → +3.0, ..., rank 9 → +0.3) layered on top of FTS scores.
In production this is always active; in A/B/C it was silently disabled (_llm_client=None).
D measures the true production pipeline ceiling.

Run:
  python backend/tests/ab_test_semantic_retrieval.py           # all conditions A/B/C/D
  python backend/tests/ab_test_semantic_retrieval.py --no-pass0  # A/B/C only
  python backend/tests/ab_test_semantic_retrieval.py --category multi_hop
  python backend/tests/ab_test_semantic_retrieval.py --dry-run   # show rewrites, no scoring
"""
from __future__ import annotations

import argparse
import os
import sys
import json
import time
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))
sys.path.insert(0, str(ROOT))

from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402

# Import CASES from sibling test file
_test_file = ROOT / "backend" / "tests" / "test_workflow_retrieval_semantic.py"
_spec = __import__("importlib.util", fromlist=["spec_from_file_location", "module_from_spec"])
import importlib.util as _ilu
_spec2 = _ilu.spec_from_file_location("_sem_cases", _test_file)
_mod = _ilu.module_from_spec(_spec2)
_spec2.loader.exec_module(_mod)
CASES = _mod.CASES


# ──────────────────────────────────────────────────────────────────────────────
# LLM semantic query expander
# ──────────────────────────────────────────────────────────────────────────────

_EXPAND_SYSTEM = """\
You are a bioinformatics expert. Given a user's natural-language description of
an analysis they want to run, rewrite it as a compact technical description
(2-4 sentences) that explicitly names:
1. The biological purpose (what question is being answered)
2. The input data format and file type (FASTQ, BAM, count matrix CSV, .idat, .raw mass-spec, VCF, BCL, etc.)
3. The expected output (aligned reads, peak calls, count matrix, variant calls, etc.)
4. The bioinformatics method and key tools (e.g. STAR alignment, DESeq2, MACS2, DIA-NN, Bismark, QIIME2, etc.)

Rules:
- Use technical bioinformatics vocabulary precisely
- If the input format is ambiguous or not stated, infer the most likely format from context
- Do NOT repeat the original phrasing verbatim — use synonyms and technical terms
- Output ONLY the rewritten description, nothing else
"""

_TERMS_SYSTEM = """\
You are a bioinformatics expert. Given a user's analysis request, extract the 3-7 most
specific technical keywords that would help find the right bioinformatics pipeline.

Focus on:
- The assay/sequencing technology (e.g. ATAC-seq, ChIP-seq, Hi-C, 16S amplicon, DIA proteomics)
- The bioinformatics pipeline or tool (e.g. nf-core/rnaseq, DIA-NN, STAR, BWA, GATK, sarek, QIIME2)
- The input file format (e.g. FASTQ, BAM, .idat, .raw, BCL, count matrix, VCF)
- The analysis goal (e.g. differential expression, peak calling, variant calling, metagenome assembly)

Rules:
- Return ONLY a JSON array of strings (no explanation, no extra text)
- 3-7 terms maximum
- Each term should be a single word or short phrase
- Prefer exact bioinformatics terms over generic biology terms
- Example output: ["ATAC-seq", "open chromatin", "peak calling", "MACS2", "FASTQ"]
"""

_EXPAND_USER_TEMPLATE = "Original request: {query}"


class OpenAILLMClient:
    """Adapter wrapping OpenAI client to match UnifiedWorkflowSearch._llm_client interface.

    UnifiedWorkflowSearch calls: client.generate(prompt, max_tokens, temperature, use_fast_model)
    """
    def __init__(self, openai_client, model: str = "gpt-4o-mini"):
        self._client = openai_client
        self._model = model

    def generate(self, prompt: str, max_tokens: int = 512, temperature: float = 0.0,
                 use_fast_model: bool = False) -> str:
        resp = self._client.chat.completions.create(
            model=self._model,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=max_tokens,
            temperature=temperature,
        )
        return resp.choices[0].message.content or ""


def expand_query_with_llm(query: str, client, model: str = "gpt-4o-mini", cache: dict = {}) -> str:
    """Call OpenAI to generate a semantic description of the query (Condition B)."""
    cache_key = f"expand:{query}"
    if cache_key in cache:
        return cache[cache_key]
    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": _EXPAND_SYSTEM},
                {"role": "user", "content": _EXPAND_USER_TEMPLATE.format(query=query)},
            ],
            max_tokens=200,
            temperature=0.1,
        )
        result = resp.choices[0].message.content.strip()
        cache[cache_key] = result
        return result
    except Exception as exc:
        print(f"  [LLM error] {exc}")
        return query  # fallback: use original


def extract_key_terms_with_llm(query: str, client, model: str = "gpt-4o-mini", cache: dict = {}) -> list:
    """Call OpenAI to extract 3-7 key technical terms to append to the FTS query (Condition C)."""
    cache_key = f"terms:{query}"
    if cache_key in cache:
        return cache[cache_key]
    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": _TERMS_SYSTEM},
                {"role": "user", "content": _EXPAND_USER_TEMPLATE.format(query=query)},
            ],
            max_tokens=100,
            temperature=0.0,
        )
        raw = resp.choices[0].message.content.strip()
        terms = json.loads(raw)
        if not isinstance(terms, list):
            terms = []
        cache[cache_key] = terms
        return terms
    except Exception as exc:
        print(f"  [LLM terms error] {exc}")
        return []


# ──────────────────────────────────────────────────────────────────────────────
# Eval helpers
# ──────────────────────────────────────────────────────────────────────────────

def eval_query(search: UnifiedWorkflowSearch, query: str, case: dict, limit: int = 20) -> dict:
    results = search.search(query, limit=limit)
    names = [m.name for m in results]
    acceptable = set([case["correct"]] + case.get("acceptable", []))
    hit1 = any(t == names[0] for t in acceptable) if names else False
    hit3 = any(t in names[:3] for t in acceptable)
    correct_rank = min(
        (names.index(t) for t in acceptable if t in names),
        default=999
    )
    confusable_ranks = [names.index(c) for c in case["confusable"] if c in names]
    above = correct_rank < min(confusable_ranks) if confusable_ranks else True
    return {
        "hit1": hit1,
        "hit3": hit3,
        "correct_rank": correct_rank,
        "top5": names[:5],
        "above_confusable": above,
    }


def eval_query_with_terms(search: UnifiedWorkflowSearch, query: str, terms: list, case: dict, limit: int = 20) -> dict:
    """Condition C: run search with original query + LLM-extracted key_terms appended."""
    results = search.search(query, limit=limit, key_terms=terms)
    names = [m.name for m in results]
    acceptable = set([case["correct"]] + case.get("acceptable", []))
    hit1 = any(t == names[0] for t in acceptable) if names else False
    hit3 = any(t in names[:3] for t in acceptable)
    correct_rank = min(
        (names.index(t) for t in acceptable if t in names),
        default=999
    )
    confusable_ranks = [names.index(c) for c in case["confusable"] if c in names]
    above = correct_rank < min(confusable_ranks) if confusable_ranks else True
    return {
        "hit1": hit1,
        "hit3": hit3,
        "correct_rank": correct_rank,
        "top5": names[:5],
        "above_confusable": above,
    }


def eval_query_with_pass0(search: UnifiedWorkflowSearch, query: str, terms: list,
                          llm_client: OpenAILLMClient, case: dict, limit: int = 20) -> dict:
    """Condition D: C terms + Pass-0 LLM catalog reranking (production-equivalent)."""
    search.set_llm_client(llm_client)
    results = search.search(query, limit=limit, key_terms=terms)
    search.set_llm_client(None)  # reset so other conditions don't get LLM
    names = [m.name for m in results]
    acceptable = set([case["correct"]] + case.get("acceptable", []))
    hit1 = any(t == names[0] for t in acceptable) if names else False
    hit3 = any(t in names[:3] for t in acceptable)
    correct_rank = min(
        (names.index(t) for t in acceptable if t in names),
        default=999
    )
    confusable_ranks = [names.index(c) for c in case["confusable"] if c in names]
    above = correct_rank < min(confusable_ranks) if confusable_ranks else True
    return {
        "hit1": hit1,
        "hit3": hit3,
        "correct_rank": correct_rank,
        "top5": names[:5],
        "above_confusable": above,
    }


def delta_marker(a_hit: bool, b_hit: bool) -> str:
    if a_hit and b_hit:
        return "  "   # both pass — no change
    if not a_hit and b_hit:
        return "⬆️ "  # B fixed it
    if a_hit and not b_hit:
        return "⬇️ "  # B broke it
    return "  "       # both fail


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--category", default=None, help="Filter by failure_mode category")
    parser.add_argument("--dry-run", action="store_true", help="Show LLM rewrites only, no scoring")
    parser.add_argument("--model", default="gpt-4o-mini", help="OpenAI model for query expansion and Pass-0")
    parser.add_argument("--save-rewrites", default=None, help="JSON file to save/load rewritten queries")
    parser.add_argument("--no-pass0", action="store_true", help="Skip Condition D (Pass-0 LLM reranking)")
    args = parser.parse_args()

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("ERROR: OPENAI_API_KEY not set")
        sys.exit(1)

    try:
        from openai import OpenAI
    except ImportError:
        print("ERROR: openai package not installed (pip install openai)")
        sys.exit(1)

    openai_client = OpenAI(api_key=api_key)
    llm_client = OpenAILLMClient(openai_client, model=args.model)
    search = UnifiedWorkflowSearch()

    cases = CASES
    if args.category:
        cases = [c for c in CASES if c["failure_mode"] == args.category]
        if not cases:
            print(f"No cases for category '{args.category}'. Available: {sorted({c['failure_mode'] for c in CASES})}")
            sys.exit(1)

    # Load cached rewrites if available
    rewrite_cache: dict = {}
    if args.save_rewrites and Path(args.save_rewrites).exists():
        with open(args.save_rewrites) as f:
            rewrite_cache = json.load(f)
        print(f"Loaded {len(rewrite_cache)} cached rewrites from {args.save_rewrites}")

    run_pass0 = not args.no_pass0
    print("=" * 80)
    print(f"A/B/C{'D' if run_pass0 else ''} Test: FTS vs LLM-augmented retrieval")
    print(f"Model: {args.model}  |  Cases: {len(cases)}")
    print("  A = raw user query → FTS only  [baseline, no LLM]")
    print("  B = LLM rewrites full query → FTS  [destructive replacement]")
    print("  C = LLM extracts key terms → appended via key_terms  [non-destructive injection]")
    if run_pass0:
        print("  D = C + Pass-0 LLM catalog browse (graded reranking)  [production-equivalent]")
    print("=" * 80)
    print()

    results = []
    for case in cases:
        query_a = case["query"]
        print(f"[{case['id']}]  ({case['failure_mode']})")
        print(f"  Query A: {query_a}")

        # Generate B query (full replacement)
        query_b = expand_query_with_llm(query_a, openai_client, model=args.model, cache=rewrite_cache)
        print(f"  Query B: {query_b}")

        # Generate C terms (injection)
        terms_c = extract_key_terms_with_llm(query_a, openai_client, model=args.model, cache=rewrite_cache)
        print(f"  Terms C: {terms_c}")
        print(f"  Correct: {case['correct']}  |  Confusable: {case['confusable']}")

        if args.dry_run:
            print()
            continue

        # Score all conditions
        result_a = eval_query(search, query_a, case)
        result_b = eval_query(search, query_b, case)
        result_c = eval_query_with_terms(search, query_a, terms_c, case)
        result_d = eval_query_with_pass0(search, query_a, terms_c, llm_client, case) if run_pass0 else None

        def status(r): return "✅" if r["hit1"] else ("~" if r["hit3"] else "❌")
        def arrow(base, r): return "⬆️" if not base["hit1"] and r["hit1"] else ("⬇️" if base["hit1"] and not r["hit1"] else "")

        print(f"  A: {status(result_a)} rank={result_a['correct_rank']}  top3={result_a['top5'][:3]}")
        print(f"  B: {status(result_b)} rank={result_b['correct_rank']}  top3={result_b['top5'][:3]}  {arrow(result_a, result_b)}")
        print(f"  C: {status(result_c)} rank={result_c['correct_rank']}  top3={result_c['top5'][:3]}  {arrow(result_a, result_c)}")
        if result_d:
            print(f"  D: {status(result_d)} rank={result_d['correct_rank']}  top3={result_d['top5'][:3]}  {arrow(result_a, result_d)}")
        print()

        row = {
            "case": case,
            "query_a": query_a,
            "query_b": query_b,
            "terms_c": terms_c,
            "a": result_a,
            "b": result_b,
            "c": result_c,
        }
        if result_d:
            row["d"] = result_d
        results.append(row)

        time.sleep(0.1)  # gentle rate limit

    # Save rewrites
    if args.save_rewrites and rewrite_cache:
        with open(args.save_rewrites, "w") as f:
            json.dump(rewrite_cache, f, indent=2)
        print(f"Saved rewrites to {args.save_rewrites}")

    if args.dry_run or not results:
        return

    # ── Summary ────────────────────────────────────────────────────────────────
    total = len(results)
    has_d = run_pass0 and any("d" in r for r in results)
    a_p1 = sum(1 for r in results if r["a"]["hit1"])
    b_p1 = sum(1 for r in results if r["b"]["hit1"])
    c_p1 = sum(1 for r in results if r["c"]["hit1"])
    d_p1 = sum(1 for r in results if r.get("d", {}).get("hit1")) if has_d else None
    a_p3 = sum(1 for r in results if r["a"]["hit3"])
    b_p3 = sum(1 for r in results if r["b"]["hit3"])
    c_p3 = sum(1 for r in results if r["c"]["hit3"])
    d_p3 = sum(1 for r in results if r.get("d", {}).get("hit3")) if has_d else None

    print("=" * 80)
    print("SUMMARY")
    print("=" * 80)
    header = f"{'Metric':<8}  {'A (raw FTS)':<16}  {'B (replace)':<16}  {'C (inject)':<16}"
    if has_d:
        header += f"  {'D (C+Pass-0)':<16}"
    print(header)
    print("-" * (80 + (20 if has_d else 0)))
    p1_line = f"{'P@1':<8}  {a_p1}/{total}={a_p1/total:.1%}  {' ':4}  {b_p1}/{total}={b_p1/total:.1%} ({b_p1-a_p1:+d})  {c_p1}/{total}={c_p1/total:.1%} ({c_p1-a_p1:+d})"
    if has_d:
        p1_line += f"  {d_p1}/{total}={d_p1/total:.1%} ({d_p1-a_p1:+d})"
    print(p1_line)
    p3_line = f"{'P@3':<8}  {a_p3}/{total}={a_p3/total:.1%}  {' ':4}  {b_p3}/{total}={b_p3/total:.1%} ({b_p3-a_p3:+d})  {c_p3}/{total}={c_p3/total:.1%} ({c_p3-a_p3:+d})"
    if has_d:
        p3_line += f"  {d_p3}/{total}={d_p3/total:.1%} ({d_p3-a_p3:+d})"
    print(p3_line)
    print()

    # Per-category breakdown
    categories = sorted({r["case"]["failure_mode"] for r in results})
    col_hdr = f"{'Category':<22}  {'A P@1':<8}  {'B P@1':<8}  {'C P@1':<8}"
    if has_d:
        col_hdr += f"  {'D P@1':<8}"
    print(col_hdr)
    print("-" * (65 + (12 if has_d else 0)))
    for cat in categories:
        cat_results = [r for r in results if r["case"]["failure_mode"] == cat]
        n = len(cat_results)
        a_n = sum(1 for r in cat_results if r["a"]["hit1"])
        b_n = sum(1 for r in cat_results if r["b"]["hit1"])
        c_n = sum(1 for r in cat_results if r["c"]["hit1"])
        b_marker = "⬆️" if b_n > a_n else ("⬇️" if b_n < a_n else "  ")
        c_marker = "⬆️" if c_n > a_n else ("⬇️" if c_n < a_n else "  ")
        row = f"  {cat:<20}  {a_n}/{n}={a_n/n:.0%}  {' ':3}  {b_n}/{n}={b_n/n:.0%} {b_marker}  {c_n}/{n}={c_n/n:.0%} {c_marker}"
        if has_d:
            d_n = sum(1 for r in cat_results if r.get("d", {}).get("hit1"))
            d_marker = "⬆️" if d_n > a_n else ("⬇️" if d_n < a_n else "  ")
            row += f"  {d_n}/{n}={d_n/n:.0%} {d_marker}"
        print(row)

    print()
    condition_keys = [("B", "b"), ("C", "c")]
    if has_d:
        condition_keys.append(("D", "d"))
    for label, condition_key in condition_keys:
        improved = [r for r in results if not r["a"]["hit1"] and r.get(condition_key, {}).get("hit1")]
        regressed = [r for r in results if r["a"]["hit1"] and not r.get(condition_key, {}).get("hit1")]
        if improved:
            print(f"Fixed by {label} ({len(improved)}): {[r['case']['id'] for r in improved]}")
        if regressed:
            print(f"Broken by {label} ({len(regressed)}): {[r['case']['id'] for r in regressed]}")


if __name__ == "__main__":
    main()
