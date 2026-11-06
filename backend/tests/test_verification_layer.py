"""Unit tests for the VerificationLayer (pure logic, no network).

Loads the module file DIRECTLY (importlib) to avoid triggering galaxy.ai.__init__'s heavy chain
(sentence_transformers/sklearn/scipy), which is unrelated to this stdlib-only module.
"""
import importlib.util
import os

_PATH = os.path.join(os.path.dirname(__file__), "..", "lib", "galaxy", "ai", "verification_layer.py")
_spec = importlib.util.spec_from_file_location("verification_layer", _PATH)
vl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(vl)


def test_majority_vote_mode_and_confidence():
    ans, conf, counts = vl.majority_vote(["nf-core/rnaseq", "nf-core/rnaseq", "salmon"])
    assert ans == "nf-core/rnaseq" and abs(conf - 2 / 3) < 1e-9
    assert vl.majority_vote([]) == (None, 0.0, {})
    assert vl.majority_vote(["", "  "]) == (None, 0.0, {})


def test_majority_vote_normalizes():
    ans, conf, _ = vl.majority_vote(["GRCh38", "grch38 ", "GRCh37"])
    assert conf == 2 / 3 and vl.default_normalize(ans) == "grch38"


def test_self_consistent():
    seq = iter(["A", "B", "A", "A", "B"])
    ans, conf, _ = vl.self_consistent(lambda: next(seq), k=5)
    assert ans == "A" and conf == 3 / 5


def test_verified_sample_passk_oracle():
    s = iter(["w1", "w2", "right", "w3"])
    r, ok = vl.verified_sample(lambda: next(s), lambda x: x == "right", k=4)
    assert r == "right" and ok is True
    s2 = iter(["a", "b", "c"])
    r2, ok2 = vl.verified_sample(lambda: next(s2), lambda x: False, k=3)
    assert ok2 is False and r2 == "c"


def test_consensus_exact_for_terse():
    assert vl.consensus(["DESeq2", "DESeq2", "edgeR"], min_agree=2)[1] == 2
    v, n = vl.consensus(["A", "B", "C"], min_agree=2)
    assert v is None and n == 1


def test_consensus_fuzzy_for_prose():
    # two prose answers naming DESeq2 differently -> cluster under fuzzy salient-F1
    v, n = vl.consensus(["DESeq2 is the best tool here", "I would use DESeq2 for this", "use edgeR instead"],
                        min_agree=2, fuzzy_threshold=0.3)
    assert n == 2 and v is not None


def test_grounded_pick_rejects_off_catalog():
    cands = ["nf-core/rnaseq", "salmon_quant", "star_align"]
    assert vl.grounded_pick("You should run nf-core/rnaseq here.", cands) == "nf-core/rnaseq"
    assert vl.grounded_pick("salmon_quant", cands) == "salmon_quant"
    assert vl.grounded_pick("use FusionCatcher (not in catalog)", cands) is None
    assert vl.grounded_pick("", cands) is None


if __name__ == "__main__":
    import traceback
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for fn in fns:
        try:
            fn(); passed += 1; print("PASS", fn.__name__)
        except Exception:
            print("FAIL", fn.__name__); traceback.print_exc()
    print("\n%d/%d passed" % (passed, len(fns)))
    raise SystemExit(0 if passed == len(fns) else 1)
