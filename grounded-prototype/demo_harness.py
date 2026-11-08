#!/usr/bin/env python3
"""
Demo: Harness2-style Propose-Probe-Compose on the deep-research harness, GOVERNED.

Shows: propose two harness edits (general + task-specific) -> probe each by
running the research controller and scoring via the Grounded TRUST LATTICE
(verifier-free) -> compose the winner -> HUMAN GATE before adoption.

Run:  python3 grounded-prototype/demo_harness.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from engine.domains import get_corpus                # noqa: E402
from engine.retrieve import retrieve as _retrieve    # noqa: E402
from research import Budget, Verdict                  # noqa: E402
from research.harness_improver import (               # noqa: E402
    HarnessConfig, ImprovementHarness, propose_probe_compose,
)

_CMC = get_corpus("cmc")


def retrieve_fn(source_id, subq):
    scored, _ = _retrieve(subq, _CMC, requesting_user="demo", limit=2, min_score=0.5)
    return [s.source for s in scored]


def decompose_fn(q):
    return ["mutagenic impurity acceptable intake ICH M7 1.5 ug/day",
            "hERG cardiac safety threshold", "impurity qualification ICH Q3A"]


def assess_fn(q, ev):
    return Verdict(sufficient=True)


def main():
    task = "ADMET and regulatory risks of this mutagenic impurity"
    base = HarnessConfig(budget=Budget(max_sources_per_subq=3, max_rounds=1))

    prop = propose_probe_compose(task, base, retrieve_fn=retrieve_fn,
                                 decompose_fn=decompose_fn, assess_fn=assess_fn)

    print("TASK:", task)
    print(f"\nbase harness trust-lattice score: {prop.base_score:.2f}\n")
    print("PROBED CANDIDATES (verifier-free; scored by the trust lattice):")
    for p in prop.probes:
        m = p.metrics
        print(f"  [{p.edit.kind:13}] {p.edit.description}")
        print(f"       score={p.score:.2f}  (authoritative={m['authoritative_claims']:.0f}, "
              f"tier_breadth={m['tier_breadth']:.0f}, boundaries={m['unresolved_boundaries']:.0f}, "
              f"cost={m['retrieval_cost']:.0f})")

    print(f"\nCOMPOSE → winner: '{prop.winner.edit.description}'")
    print(f"improved? {prop.improved}  |  lesson: {prop.lesson}")

    # ── governance gate ──────────────────────────────────────────────────
    harness = ImprovementHarness()
    print(f"\nGATE: adopt before approval -> {harness.adopt(prop)}  (refused: not reviewed)")
    prop.approve()                       # a human reviews + approves the edit
    print(f"GATE: adopt after approval  -> {harness.adopt(prop)}  (accepted)")
    print(f"improvement harness now carries {len(harness.lessons)} approved lesson(s).")


if __name__ == "__main__":
    main()
