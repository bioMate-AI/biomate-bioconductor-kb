"""
Tests for the pluggable retrieval seam — proving the engine grounds in LIVE
sources (literature, firm records) without any network, by injecting fakes that
mimic BioMate's real callables.

This is what makes "point it at BioMate's live data" verifiable on a laptop: the
mechanism is tested with fakes; the backend wiring (galaxy.ai.grounded.live) just
passes the real functions into the same classes.

Run:  python3 grounded-prototype/tests/test_retrievers.py
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from engine import (  # noqa: E402
    ask, CompositeRetriever, CorpusRetriever, LiteratureRetriever,
    RegulatoryRetriever, FirmRecordRetriever, literature_item_to_source,
)
from engine.domains import get_corpus  # noqa: E402
from engine.models import SourceTier  # noqa: E402


# --- fakes mimicking BioMate's real functions --------------------------------

def _fake_literature_search(query, limit):
    # shape of galaxy.ai.federated_query.iterative_literature_search
    return {"results": [
        {
            "pmid": "12345678",
            "title": "Steam dryness fraction and moist-heat sterilization lethality",
            "authors": "Smith J, Doe A",
            "year": 2019,
            "journal": "J Hospital Sterilization",
            "abstract": "We show that steam dryness below 0.9 impairs penetration and "
                        "latent-heat transfer, reducing microbial lethality on porous loads.",
            "full_text_url": "https://example.org/paper/12345678",
        },
        {"title": "", "abstract": "no title -> dropped"},  # must be skipped
    ]}


def _fake_firm_db(query, user):
    # tenant-scoped: returns alice's validated batch evidence only for alice
    if user != "alice":
        return []
    return [{
        "id": "firm:alice:cpv-001",
        "title": "CPV trend: steam dryness, line 3",
        "text": "Dryness value held 0.96-0.98 across 312 batches; no OOS deviations.",
        "citation": "CPV-REPORT-2026-Q2 (QA-approved)",
        "locator": "dms://CPV-REPORT-2026-Q2",
        "verified": True,
    }]


# --- tests -------------------------------------------------------------------

def test_literature_item_mapping():
    s = literature_item_to_source(_fake_literature_search("x", 6)["results"][0])
    assert s is not None
    assert s.tier == SourceTier.PEER_REVIEWED
    assert s.verified is True
    assert "12345678" in (s.locator or "")
    assert "Smith" in s.citation and "2019" in s.citation


def test_untitled_literature_item_dropped():
    assert literature_item_to_source({"title": "", "abstract": "x"}) is None


def test_live_literature_grounds_a_claim():
    retr = CompositeRetriever([
        CorpusRetriever(get_corpus("gmp_steam")),      # Tier A normative (curated)
        LiteratureRetriever(_fake_literature_search),  # Tier B live literature
    ])
    a = ask("Why is the steam dryness value threshold set where it is?",
            user="alice", retriever=retr)
    cited = [s for c in a.claims for s in c.supporting]
    assert any(s.id.startswith("lit:") and s.verified for s in cited), \
        "a live literature source must be grounded + cited in the answer"


def test_firm_record_is_tenant_scoped():
    retr = CompositeRetriever([
        CorpusRetriever(get_corpus("gmp_steam")),
        FirmRecordRetriever(_fake_firm_db),
    ])
    # alice sees her firm record
    a_alice = ask("steam dryness CPV trend batches line 3", user="alice", retriever=retr)
    ids_alice = {s.id for c in a_alice.claims for s in c.supporting}
    assert any(i.startswith("firm:alice") for i in ids_alice)
    # bob gets none of alice's firm records (query_fn returns [] AND the gate re-checks)
    a_bob = ask("steam dryness CPV trend batches line 3", user="bob", retriever=retr)
    ids_bob = {s.id for c in a_bob.claims for s in c.supporting}
    assert not any(i.startswith("firm:alice") for i in ids_bob)


def _fake_ich_search(query, limit):
    # shape of the backend ICH-corpus adapter (galaxy.ai.grounded.live)
    if "mutagenic" in query.lower() or "m7" in query.lower():
        return [{
            "citation": "ICH M7",
            "text": "A TTC-based acceptable intake of 1.5 micrograms per day is "
                    "applied as a default for a mutagenic impurity, corresponding "
                    "to a negligible theoretical excess lifetime cancer risk.",
            "score": 0.8,
            "locator": "ICH_M7_R2.pdf",
        }]
    return []


def test_regulatory_source_is_tier_A_and_grounds():
    from engine.models import SourceTier
    retr = CompositeRetriever([
        RegulatoryRetriever(_fake_ich_search),          # Tier A (live guideline)
        LiteratureRetriever(_fake_literature_search),   # Tier B
    ])
    a = ask("Why is the mutagenic impurity limit 1.5 ug/day in ICH M7?",
            user="alice", retriever=retr)
    cited = [s for c in a.claims for s in c.supporting]
    reg = [s for s in cited if s.id.startswith("reg:")]
    assert reg, "the ICH guideline passage must be retrieved and cited"
    assert reg[0].tier == SourceTier.NORMATIVE_PRIMARY and reg[0].verified


def test_dead_literature_backend_degrades_not_crashes():
    def _boom(q, l):
        raise RuntimeError("literature service down")
    retr = CompositeRetriever([
        CorpusRetriever(get_corpus("gmp_steam")),
        LiteratureRetriever(_boom),
    ])
    a = ask("Why is the steam dryness value threshold set where it is?",
            user="alice", retriever=retr)
    assert a.claims  # still answers from the curated corpus, no exception


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
