"""
Tests for the Grounded Standards Assistant prototype.

These encode the two product invariants as executable checks:
  * BOUNDARY HONESTY — a "why this exact number" question must produce a boundary
    that routes to humans, and must NOT claim the exact derivation as grounded.
  * TENANT ISOLATION — one user's unverified note is never visible to another,
    and no unverified note ever supports a confirmed claim.

Run:  python3 -m pytest grounded-prototype/tests -q
  or: python3 grounded-prototype/tests/test_engine.py   (no pytest needed)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from engine import ask, load_corpus  # noqa: E402
from engine.classify import classify  # noqa: E402
from engine.models import QuestionType, SourceTier  # noqa: E402
from engine.retrieve import retrieve  # noqa: E402


# ── classification ──────────────────────────────────────────────────────────

def test_classify_rationale():
    t, _ = classify("Why is the dryness threshold 0.95 and what experiments justify it?")
    assert t == QuestionType.RATIONALE


def test_classify_normative():
    t, _ = classify("What dryness value does the standard require?")
    assert t == QuestionType.NORMATIVE


def test_classify_investigation():
    t, _ = classify("Our steam quality test failed — what should we check?")
    assert t == QuestionType.INVESTIGATION


# ── boundary honesty ──────────────────────────────────────────────────────────

def test_rationale_produces_boundary():
    ans = ask("Why is the dryness value set to 0.95? What work produced that number?",
              user="alice")
    assert ans.boundaries, "a 'why this exact number' question must raise a boundary"
    b = ans.boundaries[0]
    assert b.escalate_to, "boundary must route to real experts, not dead-end"
    assert any("committee" in e.lower() or "pda" in e.lower() or "ispe" in e.lower()
               for e in b.escalate_to)


def test_rationale_does_not_claim_exact_derivation_as_grounded():
    ans = ask("Why exactly 0.95 for the dryness value?", user="alice")
    # The grade must be capped — we never hand back HIGH confidence on a question
    # whose core ask (the exact derivation) we could not ground.
    assert ans.grade.value in ("moderate", "low", "not_established")


def test_rationale_still_grounds_the_mechanism():
    # Boundary-honesty must not mean "refuse everything": the mechanism and the
    # normative limit ARE grounded and must be returned.
    ans = ask("Why is there a dryness value limit of 0.95 in EN 285?", user="alice")
    assert any(c.is_grounded for c in ans.claims)


# ── tenant isolation ──────────────────────────────────────────────────────────

def test_other_tenant_note_never_retrieved():
    corpus = load_corpus()
    q = "dryness value 0.95 study"
    scored_alice, audit_alice = retrieve(q, corpus, requesting_user="alice")
    ids = {s.source.id for s in scored_alice}
    assert "note-bob-opinion" not in ids, "bob's private note leaked to alice"
    assert "note-alice-draft" in ids, "alice should see her own note"
    assert audit_alice.other_tenant_personal_blocked >= 1


def test_isolation_is_symmetric():
    corpus = load_corpus()
    q = "dryness value 0.95 study"
    scored_bob, _ = retrieve(q, corpus, requesting_user="bob")
    ids = {s.source.id for s in scored_bob}
    assert "note-alice-draft" not in ids, "alice's private note leaked to bob"
    assert "note-bob-opinion" in ids


def test_unverified_note_never_supports_a_grounded_claim():
    ans = ask("Why is the dryness value 0.95?", user="alice")
    for c in ans.claims:
        if any(s.tier == SourceTier.UNVERIFIED_PERSONAL for s in c.supporting):
            assert not c.is_grounded, "an unverified note must never ground a claim"


def test_personal_note_shown_only_to_owner():
    ans_alice = ask("dryness value 0.95 wet load deviation", user="alice")
    texts = " ".join(c.text for c in ans_alice.claims)
    assert "working note" in texts.lower()  # alice sees her own note surfaced
    ans_carol = ask("dryness value 0.95 wet load deviation", user="carol")
    texts_c = " ".join(c.text for c in ans_carol.claims)
    assert "working note" not in texts_c.lower()  # carol sees no personal notes


# ── no-authoritative-source → refuse to answer from memory ────────────────────

def test_unknown_topic_refuses_rather_than_confabulates():
    ans = ask("What colour should the sterilizer chamber be painted?", user="alice")
    # Nothing authoritative in corpus → no grounded claims, and a boundary.
    assert not any(c.is_grounded for c in ans.claims)


def _run_all():
    import traceback
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for fn in fns:
        try:
            fn()
            print(f"PASS  {fn.__name__}")
            passed += 1
        except Exception:
            print(f"FAIL  {fn.__name__}")
            traceback.print_exc()
    print(f"\n{passed}/{len(fns)} passed")
    return passed == len(fns)


if __name__ == "__main__":
    sys.exit(0 if _run_all() else 1)
