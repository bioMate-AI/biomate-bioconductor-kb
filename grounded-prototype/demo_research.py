#!/usr/bin/env python3
"""
Demo: the deep-research controller — iterative, parallel, trust-grounded.

Shows the harness/LLM/skills split end to end:
  * router picks the source SET per sub-question (use-case aware, keyless-only)
  * harness fans out in PARALLEL and dedups
  * injected LLM judgment decomposes + judges sufficiency (drills one gap round)
  * the deterministic verifier guards against spinning
  * final synthesis grounds the answer in the Grounded trust lattice (tiered
    citations + honest boundary)

Backed by the real CMC guideline corpus so the citations are genuine.

Run:  python3 grounded-prototype/demo_research.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from engine import to_markdown                      # noqa: E402
from engine.domains import get_corpus               # noqa: E402
from engine.retrieve import retrieve as _retrieve   # noqa: E402
from research import research, Budget, Verdict, router  # noqa: E402

_CMC = get_corpus("cmc")


def retrieve_fn(source_id, subq):
    """Stand-in for a live source: return the CMC corpus items matching the
    sub-question (in production this is federated_query / query_database /
    ich_corpus keyed by source_id)."""
    scored, _ = _retrieve(subq, _CMC, requesting_user="demo", limit=2, min_score=0.5)
    return [s.source for s in scored]


def decompose_fn(question):
    # (LLM would do this) break the ask into independent sub-questions
    return [
        "mutagenic impurity acceptable intake ICH M7 1.5 ug/day",
        "hERG cardiac safety threshold",
        "impurity qualification threshold ICH Q3A",
    ]


_round = {"n": 0}
def assess_fn(question, evidence):
    _round["n"] += 1
    if _round["n"] == 1:
        return Verdict(sufficient=False, gaps=["derivation of the 1.5 ug/day figure"],
                       follow_up=["why is the mutagenic impurity limit 1.5 ug/day and what is the derivation"])
    return Verdict(sufficient=True)


def main():
    q = "What are the ADMET and regulatory risks of this mutagenic impurity, and how are its limits justified?"
    print("QUESTION:", q)
    srcs, intent = router.route(q)
    print(f"\nROUTER → intent='{intent}', sources={[s.id for s in srcs]}  (keyless-only)\n")

    res = research(q, user="demo", retrieve_fn=retrieve_fn,
                   decompose_fn=decompose_fn, assess_fn=assess_fn,
                   budget=Budget(max_rounds=3, max_parallel=6))

    print("="*78); print("RESEARCH TRACE"); print("="*78)
    for t in res.trace:
        print(f"  round {t.round}: {t.retrievals} parallel retrievals across "
              f"{len(t.subquestions)} sub-questions {t.intents} → "
              f"+{t.new_evidence} evidence (+{t.new_authoritative} authoritative) "
              f"→ sufficient={t.sufficient}")
        if t.gaps:
            print(f"            gap → drilled: {t.gaps}")
    print(f"\n  stopped after {res.rounds} round(s): {res.stop_reason}")
    print(f"  evidence gathered: {res.sources_used}\n")

    print("="*78); print("GROUNDED SYNTHESIS"); print("="*78)
    print(to_markdown(res.answer))


if __name__ == "__main__":
    main()
