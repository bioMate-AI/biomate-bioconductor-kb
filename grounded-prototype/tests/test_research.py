"""
Tests for the deep-research controller — proves the harness loop with no network
and no LLM, by injecting fake judgment + retrieval.

Asserts the architecture claims:
  * PARALLEL fan-out across (sub-question x routed source)
  * DEPTH iteration: insufficient -> drill gaps -> next round
  * deterministic anti-spin verifier: a round with no new authoritative evidence stops
  * keyless-only routing by default (honours "no credential application")
  * use-case routing picks the right source KINDS (admet -> KB+regulatory+...)
  * final synthesis is grounded + cited via the Grounded engine

Run:  python3 grounded-prototype/tests/test_research.py
"""

import os
import sys
import threading
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from engine.models import Source, SourceTier  # noqa: E402
from research import research, Budget, Verdict, router, registry  # noqa: E402


def _src(sid, tier=SourceTier.PEER_REVIEWED, verified=True):
    return Source(id=sid, tier=tier, title=sid, citation=sid, text=sid + " evidence text",
                  owner=None, verified=verified, locator="x://" + sid, keywords=[sid])


# ── routing ───────────────────────────────────────────────────────────────

def test_router_is_keyless_by_default():
    srcs, _ = router.route("What is the ADMET hERG risk of this compound?")
    assert srcs and all(s.keyless for s in srcs), "default routing must be keyless-only"


def test_router_admet_picks_kb_and_regulatory():
    srcs, intent = router.route("ADMET hERG CYP toxicity of the compound")
    assert intent == "admet"
    kinds = {s.kind for s in srcs}
    assert registry.KNOWLEDGE_BASE in kinds and registry.REGULATORY in kinds


def test_router_patent_lane_is_europepmc_not_google():
    # patents come via the keyless EuropePMC lane; no Google Patents in the registry
    assert "patents_epmc" in registry.BY_ID
    assert not any("google" in s.id.lower() for s in registry.all_sources())
    assert not any("uspto" in s.id.lower() or "odp" in s.id.lower() for s in registry.all_sources())


# ── the loop ────────────────────────────────────────────────────────────────

def test_parallel_fanout_and_grounded_synthesis():
    seen_concurrency = {"max": 0}
    active = {"n": 0}
    lock = threading.Lock()

    def retrieve_fn(source_id, subq):
        with lock:
            active["n"] += 1; seen_concurrency["max"] = max(seen_concurrency["max"], active["n"])
        time.sleep(0.02)
        with lock:
            active["n"] -= 1
        # one authoritative source per KB/regulatory source id
        return [_src(f"{source_id}:hit", SourceTier.ORG_VALIDATED)]

    res = research("ADMET hERG risk of the compound", user="u",
                   retrieve_fn=retrieve_fn,
                   assess_fn=lambda q, ev: Verdict(sufficient=True),
                   budget=Budget(max_parallel=6))
    assert seen_concurrency["max"] >= 2, "retrievals must run in parallel"
    assert res.answer.claims, "final synthesis must produce a grounded answer"
    assert res.sources_used, "evidence must be gathered"


def test_depth_iteration_drills_gaps():
    calls = {"assess": 0}

    def retrieve_fn(source_id, subq):
        return [_src(f"{source_id}:{subq[:6]}", SourceTier.PEER_REVIEWED)]

    def assess_fn(q, ev):
        calls["assess"] += 1
        if calls["assess"] == 1:
            return Verdict(sufficient=False, gaps=["dose-response"],
                           follow_up=["what is the dose-response?"])
        return Verdict(sufficient=True)

    res = research("mechanism of the compound", user="u",
                   retrieve_fn=retrieve_fn, assess_fn=assess_fn,
                   decompose_fn=lambda q: [q],
                   budget=Budget(max_rounds=3))
    assert res.rounds == 2, "should drill one follow-up round then stop"
    assert res.stop_reason == "sufficient"
    assert len(res.trace) == 2


def test_anti_spin_verifier_stops_on_no_new_authoritative():
    # retrieve returns only UNVERIFIED (non-authoritative) -> verifier must stop,
    # not keep drilling to the budget ceiling.
    def retrieve_fn(source_id, subq):
        return [_src(source_id + ":weak", SourceTier.UNVERIFIED_PERSONAL)]

    res = research("obscure question", user="u", retrieve_fn=retrieve_fn,
                   assess_fn=lambda q, ev: Verdict(sufficient=False, follow_up=["more?"]),
                   budget=Budget(max_rounds=5))
    assert res.stop_reason == "no_new_evidence"
    assert res.rounds == 1, "must not spin past a non-productive round"


def test_dead_source_does_not_kill_round():
    def retrieve_fn(source_id, subq):
        if "crossref" in source_id:
            raise RuntimeError("source down")
        return [_src(source_id + ":ok", SourceTier.PEER_REVIEWED)]

    res = research("general background on the topic", user="u",
                   retrieve_fn=retrieve_fn,
                   assess_fn=lambda q, ev: Verdict(sufficient=True))
    assert res.answer is not None and res.sources_used


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
