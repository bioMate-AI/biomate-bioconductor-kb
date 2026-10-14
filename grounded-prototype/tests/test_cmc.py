"""
Tests for the CMC / ADMET domain pack — the R&D/CMC edge BioMate already owns.

These assert the engine distinguishes the GROUNDEDNESS SPECTRUM of thresholds:
  * ICH M7 TTC (1.5 ug/day)  -> documented derivation BUT contested  -> MODERATE + "contested" boundary
  * ICH Q3A qualification (0.15%) -> convention -> MODERATE + "exact value" boundary
  * Lipinski Ro5 (MW 500)   -> empirical heuristic -> boundary (not a derived spec)
  * hERG                    -> NO fixed regulatory cutoff -> grounded refusal, no endorsement of a personal heuristic

Run:  python3 grounded-prototype/tests/test_cmc.py
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from engine import ask  # noqa: E402
from engine.domains import get_corpus, list_domains  # noqa: E402
from engine.models import SourceTier  # noqa: E402


def test_domain_registry():
    assert "cmc" in list_domains()
    assert "gmp_steam" in list_domains()
    assert len(get_corpus("cmc")) > 0


def test_m7_ttc_is_grounded_but_contested():
    a = ask("Why is the mutagenic impurity limit 1.5 ug/day in ICH M7? "
            "What is the derivation?", user="alice", domain="cmc")
    assert any(c.is_grounded for c in a.claims), "M7 derivation must be grounded"
    assert a.boundaries, "a contested derivation must still raise a boundary"
    frag = a.boundaries[0].question_fragment.lower()
    assert "contested" in frag or "settled" in frag
    # documented + contested -> not a false HIGH
    assert a.grade.value in ("moderate", "low")


def test_q3a_threshold_is_convention_with_boundary():
    a = ask("Why is the impurity qualification threshold 0.15% in ICH Q3A?",
            user="carol", domain="cmc")
    assert a.boundaries, "a convention figure must flag that the exact value is not derived"
    assert "exact" in a.boundaries[0].question_fragment.lower()


def test_lipinski_is_heuristic_not_derived_spec():
    a = ask("Why is the Lipinski rule-of-five molecular weight limit 500?",
            user="alice", domain="cmc")
    assert a.boundaries, "a heuristic has no first-principles derivation -> boundary"


def test_herg_has_no_fixed_threshold_and_is_grounded():
    a = ask("What is the hERG threshold a compound must pass?",
            user="bob", domain="cmc")
    grounded_text = " ".join(c.text for c in a.claims if c.is_grounded).lower()
    assert "no single regulatory" in grounded_text or "no fixed" in grounded_text \
        or "not a regulatory" in grounded_text, "must state there is no fixed hERG cutoff"


def test_personal_heuristic_never_endorsed_as_fact():
    # bob's wrong belief ("under 10 uM is automatically fine") must appear ONLY as
    # his unverified note, never as a grounded claim.
    a = ask("What is the hERG threshold a compound must pass?",
            user="bob", domain="cmc")
    for c in a.claims:
        if any(s.tier == SourceTier.UNVERIFIED_PERSONAL for s in c.supporting):
            assert not c.is_grounded


def test_cmc_cross_tenant_isolation():
    # alice's CMC note must never surface for bob, and vice-versa.
    a_bob = ask("genotoxic impurity 1.5 ug/day compound-specific higher limit",
                user="bob", domain="cmc")
    texts = " ".join(c.text for c in a_bob.claims)
    assert "compound-specific risk assessment" not in texts  # that is alice's note
    assert a_bob.isolation.other_tenant_personal_blocked >= 1


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
