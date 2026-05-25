"""
Investigation: run 155-case cross_domain_routing benchmark through
UnifiedWorkflowSearch and categorize failures by type.

Goal: determine which of the 3 levers (intent-anchor / domain-gate /
tighter-disambig) the failures actually call for. The absolute top-1 number
will be artificially low because BGE dense retrieval doesn't load locally
(model file not present); that's fine — we're after the distribution of
failure modes, not the absolute accuracy.

Failure taxonomy (per the proposal doc):
  A. ADJACENT — wrong workflow chosen, but it's adjacent to the correct one
                (rnaseq when user meant scrnaseq; sarek when user meant raredisease).
                Lever: intent-anchor canonical map.
  B. UNRELATED_TOP1 — top-1 is unrelated to the user's actual intent
                (e.g. cutandrun when query is bulk RNA-seq).
                Could be: retrieval-engine issue (FTS noise) or missing intent context.
  C. CORRECT_IN_TOP3 — correct workflow IS in top-3 but not top-1.
                Lever: tighter ranking via intent boost OR LLM verification.
  D. CORRECT_NOT_IN_TOP10 — correct workflow not even in top-10.
                Indicates retrieval-engine issue (BGE needed, query terms missing).
  E. DISAMBIG_FIRES_CORRECTLY — top-2 gap < 3.0 and correct workflow IS in
                the candidate set — disambiguation card would handle this fine.

Output: sandbox/workflow_search_v2/docs/20260519_failure_categorization.md
"""
from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path
from typing import Dict, List

import yaml

sys.path.insert(0, str(Path("backend/lib").resolve()))
from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
EVAL_YAML = ROOT / "evaluation" / "datasets" / "cross_domain_routing" / "queries.yaml"
OUT_DOC = Path(__file__).resolve().parents[1] / "docs" / "20260519_failure_categorization.md"

# Workflow adjacency map — used to detect ADJACENT-type failures
ADJACENT_SETS = [
    {"nf-core/rnaseq", "nf-core/scrnaseq", "nf-core/smrnaseq", "nf-core/lncpipe",
     "nf-core/differentialabundance", "nf-core/rnafusion", "nf-core/spatialvi"},
    {"nf-core/sarek", "nf-core/raredisease"},
    {"nf-core/mag", "nf-core/taxprofiler", "nf-core/ampliseq"},
    {"nf-core/chipseq", "nf-core/atacseq", "nf-core/cutandrun"},
    {"nf-core/proteomicslfq", "nf-core/diaproteomics", "nf-core/mhcquant"},
]


def is_adjacent(predicted: str, correct: str) -> bool:
    for cluster in ADJACENT_SETS:
        if predicted in cluster and correct in cluster:
            return True
    return False


def categorize(query: str, correct: str, results) -> str:
    """Return one of: HIT, ADJACENT, UNRELATED_TOP1, CORRECT_IN_TOP3,
    CORRECT_NOT_IN_TOP10, DISAMBIG_OK."""
    if not results:
        return "EMPTY_RESULTS"
    names = [r.name for r in results]
    top1 = names[0]
    top3 = names[:3]
    top10 = names[:10]
    if top1 == correct:
        return "HIT"
    if correct in top3:
        return "CORRECT_IN_TOP3"
    if correct in top10:
        # check disambig gate (gap top-2 < 3.0)
        if len(results) >= 2 and results[0].score - results[1].score < 3.0:
            return "DISAMBIG_OK"
        return "CORRECT_IN_TOP10_NOT_TOP3"
    # Top-1 wrong, correct not in top-10
    if is_adjacent(top1, correct):
        return "ADJACENT"
    return "UNRELATED_TOP1"


def main() -> int:
    cases = yaml.safe_load(EVAL_YAML.read_text())
    print(f"Loaded {len(cases)} routing cases")

    search = UnifiedWorkflowSearch()
    bge_active = bool(getattr(search, "_bge_model", None))
    print(f"BGE dense retrieval: {'ACTIVE' if bge_active else 'DISABLED (local)'}\n")

    counts: Counter = Counter()
    by_domain: Dict[str, Counter] = {}
    failure_examples: Dict[str, List[dict]] = {}

    for c in cases:
        query = c["query"]
        correct = c["correct_workflow"]
        domain = c.get("domain", "unknown")
        try:
            results = search.search(query, limit=10)
        except Exception as exc:
            counts["ERROR"] += 1
            continue
        cat = categorize(query, correct, results)
        counts[cat] += 1
        by_domain.setdefault(domain, Counter())[cat] += 1
        if cat != "HIT" and len(failure_examples.get(cat, [])) < 5:
            failure_examples.setdefault(cat, []).append({
                "id": c["id"], "query": query[:80],
                "correct": correct,
                "top3": [r.name for r in results[:3]],
                "scores": [round(r.score, 1) for r in results[:3]],
            })

    n = sum(counts.values())
    print(f"=== Failure categorization (n={n}) ===")
    print(f"{'category':<28} {'count':>6}  {'pct':>5}")
    print("-" * 50)
    for cat, count in counts.most_common():
        print(f"{cat:<28} {count:>6}  {100*count/n:>4.1f}%")

    print(f"\n=== By domain ===")
    for domain in sorted(by_domain):
        cs = by_domain[domain]
        total = sum(cs.values())
        print(f"  {domain:<25} n={total:>3}  HIT={cs['HIT']:>3} "
              f"ADJ={cs.get('ADJACENT', 0):>2} UNREL={cs.get('UNRELATED_TOP1', 0):>2} "
              f"T3={cs.get('CORRECT_IN_TOP3', 0):>2} OOR={cs.get('CORRECT_NOT_IN_TOP10', 0):>2}")

    # Write markdown report
    OUT_DOC.parent.mkdir(parents=True, exist_ok=True)
    with OUT_DOC.open("w", encoding="utf-8") as f:
        f.write("# 155-Case Workflow-Routing Failure Categorization\n\n")
        f.write(f"**Date:** 2026-05-19\n**Source:** `evaluation/datasets/cross_domain_routing/queries.yaml`\n")
        f.write(f"**Runner:** `sandbox/workflow_search_v2/scripts/categorize_failures.py`\n")
        f.write(f"**BGE dense retrieval:** {'ACTIVE' if bge_active else '**DISABLED locally** — absolute numbers are artificially low; failure-mode distribution is still valid'}\n\n")
        f.write("## Failure-mode distribution\n\n")
        f.write("| Category | Count | % | Recommended lever |\n|---|---|---|---|\n")
        lever_map = {
            "HIT": "—",
            "ADJACENT": "**Lever 1: Intent-anchor map** — codify rnaseq-vs-scrnaseq etc.",
            "UNRELATED_TOP1": "Lever 1 + retrieval-engine review (likely missing context)",
            "CORRECT_IN_TOP3": "Lever 1 (intent boost re-orders top-3) OR Lever 2 (LLM verify)",
            "CORRECT_IN_TOP10_NOT_TOP3": "Lever 2 (domain-gated re-rank)",
            "CORRECT_NOT_IN_TOP10": "Retrieval-engine issue (BGE / FTS), out of scope",
            "DISAMBIG_OK": "Existing disambiguation UX handles it",
            "EMPTY_RESULTS": "Pre-search query parsing / classification issue",
        }
        for cat, count in counts.most_common():
            f.write(f"| {cat} | {count} | {100*count/n:.1f}% | {lever_map.get(cat, '?')} |\n")
        f.write(f"\nTotal n = {n}\n\n")
        f.write("## Failure examples (top 5 per category)\n\n")
        for cat, exs in failure_examples.items():
            f.write(f"### {cat}\n\n")
            for ex in exs:
                f.write(f"- **{ex['id']}** `{ex['query']}`\n")
                f.write(f"  - expected: `{ex['correct']}`\n")
                f.write(f"  - got top-3: `{ex['top3']}` (scores {ex['scores']})\n")
            f.write("\n")

        f.write("## Lever recommendation\n\n")
        adj = counts.get("ADJACENT", 0)
        unrel = counts.get("UNRELATED_TOP1", 0)
        in_top3 = counts.get("CORRECT_IN_TOP3", 0)
        not_in_top10 = counts.get("CORRECT_NOT_IN_TOP10", 0)
        if adj + in_top3 >= 0.3 * n:
            rec = "**Lever 1 (intent-anchor canonical map)** — fits the dominant failure modes (ADJACENT + CORRECT_IN_TOP3). Build a YAML codifying intent→workflow mappings; expected lift on these two categories combined."
        elif not_in_top10 >= 0.3 * n:
            rec = "**Retrieval-engine issue** — too many correct answers fall out of top-10. Re-rank levers can't help; fix BGE indexing / query expansion first."
        elif unrel >= 0.3 * n:
            rec = "**Mixed: Lever 1 + retrieval review**. Many top-1 picks are unrelated, suggesting both missing context (Lever 1 helps) and possibly missing dense-retrieval signal."
        else:
            rec = "**Lever 3 (tighter disambig gate)** — failures are scattered, no dominant pattern; gate tightening + Lever 1 on selected high-traffic queries."
        f.write(rec + "\n")

    print(f"\nWrote {OUT_DOC.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
