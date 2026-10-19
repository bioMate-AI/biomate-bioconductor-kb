"""
Tests for the Harness2-style governed self-improver.

Proves: Propose-Probe-Compose runs; the trust-lattice score ranks candidates;
an improvement is only PROPOSED (never auto-applied); the governance gate blocks
adoption until a human approves.

Run:  python3 grounded-prototype/tests/test_harness.py
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from engine.models import Source, SourceTier  # noqa: E402
from research import Budget, Verdict  # noqa: E402
from research.harness_improver import (  # noqa: E402
    HarnessConfig, ImprovementHarness, harness_score, propose_probe_compose,
)
from research.controller import research, ResearchResult  # noqa: E402


def _src(sid, tier=SourceTier.ORG_VALIDATED):
    return Source(id=sid, tier=tier, title=sid, citation=sid, text=sid + " evidence",
                  owner=None, verified=True, locator="x://" + sid, keywords=[sid])


def _retrieve(source_id, subq):
    return [_src(source_id + ":" + subq[:4])]


def _sufficient(q, ev):
    return Verdict(sufficient=True)


# ── the PPC step ──────────────────────────────────────────────────────────

def test_ppc_proposes_two_candidates_and_a_winner():
    base = HarnessConfig(budget=Budget(max_sources_per_subq=3, max_rounds=1))
    prop = propose_probe_compose("ADMET hERG CYP toxicity risk", base,
                                 retrieve_fn=_retrieve, assess_fn=_sufficient,
                                 decompose_fn=lambda q: [q])
    assert len(prop.probes) == 2, "one general + one task-specific candidate"
    assert prop.winner is not None
    # broadening breadth yields more authoritative evidence -> beats base
    assert prop.improved and prop.winner.score > prop.base_score


def test_winner_actually_edits_the_harness():
    base = HarnessConfig(budget=Budget(max_sources_per_subq=3, max_rounds=1))
    prop = propose_probe_compose("ADMET risk of the compound", base,
                                 retrieve_fn=_retrieve, assess_fn=_sufficient,
                                 decompose_fn=lambda q: [q])
    w = prop.winner.edit.config
    changed = (w.budget != base.budget) or (w.kinds_override != base.kinds_override)
    assert changed, "the winning edit must differ from the base harness"


# ── trust-lattice probe is the verifier ─────────────────────────────────────

def test_score_rewards_authoritative_and_penalises_boundaries():
    from engine.models import GroundedAnswer, Claim, Boundary, EvidenceGrade, QuestionType

    def mk(result_claims, boundaries, cost):
        ans = GroundedAnswer("q", QuestionType.UNKNOWN, EvidenceGrade.HIGH,
                             result_claims, boundaries, None)
        class _T:  # minimal trace stub
            def __init__(s, r): s.retrievals = r
        return ResearchResult("q", ans, 1, [_T(cost)], [], "sufficient")

    strong = mk([Claim("a", [_src("s1", SourceTier.NORMATIVE_PRIMARY)])], [], 4)
    weak = mk([Claim("a", [_src("s1", SourceTier.NORMATIVE_PRIMARY)])],
              [Boundary("gap", "unresolved")], 4)
    assert harness_score(strong)[0] > harness_score(weak)[0], "boundaries must lower the score"


# ── governance gate (the safety-critical part) ──────────────────────────────

def test_improvement_is_only_proposed_not_auto_applied():
    base = HarnessConfig(budget=Budget(max_sources_per_subq=3, max_rounds=1))
    prop = propose_probe_compose("regulatory ICH guideline question", base,
                                 retrieve_fn=_retrieve, assess_fn=_sufficient,
                                 decompose_fn=lambda q: [q])
    assert prop.approved is False, "a proposal must never be pre-approved"


def test_gate_blocks_adoption_until_approved():
    base = HarnessConfig(budget=Budget(max_sources_per_subq=3, max_rounds=1))
    prop = propose_probe_compose("ADMET risk", base, retrieve_fn=_retrieve,
                                 assess_fn=_sufficient, decompose_fn=lambda q: [q])
    harness = ImprovementHarness()
    assert harness.adopt(prop) is False, "un-approved edits must be refused"
    assert harness.lessons == []
    prop.approve()                       # explicit human gate
    assert harness.adopt(prop) is True
    assert harness.lessons, "an approved lesson is recorded (harnessing-level recursion)"


def _run_all():
    import traceback
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for fn in fns:
        try:
            fn(); print(f"PASS  {fn.__name__}"); passed += 1
        except Exception:
            print(f"FAIL  {fn.__name__}"); traceback.print_exc()
    print(f"\n{passed}/{len(fns)} passed")
    return passed == len(fns)


if __name__ == "__main__":
    sys.exit(0 if _run_all() else 1)
