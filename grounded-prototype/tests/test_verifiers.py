"""
Tests for the P0 verifier bridge — answer-based scoring where a task has ground
truth (mirroring BioMate's real scorers), answer-free trust-lattice otherwise.

Run:  python3 grounded-prototype/tests/test_verifiers.py
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from research.verifiers import (  # noqa: E402
    ExpectedParamsVerifier, ExactClassVerifier, TrustLatticeVerifier, select_verifier,
)

_R = []


def ck(name, cond):
    print(("PASS" if cond else "FAIL"), "-", name)
    _R.append(cond)


# selection
ck("ground truth with expected_params -> answer-based params verifier",
   select_verifier({"expected_params": {"genome": "GRCh38"}}).name == "expected_params_f1")
ck("ground truth with classes -> answer-based class verifier",
   select_verifier({"classes": {"herg": "blocker"}}).name == "exact_class_accuracy")
ck("no ground truth -> answer-free trust lattice",
   select_verifier(None).answer_free is True)
ck("empty dict ground truth -> answer-free",
   select_verifier({}).name == "trust_lattice")

# ExpectedParamsVerifier (param_prefill F1 shape)
pv = ExpectedParamsVerifier()
ck("exact param match scores high",
   pv.score({"expected_params": {"genome": "GRCh38"}}, "use genome GRCh38") > 0.9)
ck("missing param scores 0",
   pv.score({"expected_params": {"genome": "GRCh38"}}, "no relevant content") == 0.0)
ck("must_not_fill violation penalises",
   pv.score({"expected_params": {"genome": "GRCh38"}, "must_not_fill": ["adapter"]},
            "genome GRCh38 and adapter trimming")
   < pv.score({"expected_params": {"genome": "GRCh38"}, "must_not_fill": ["adapter"]},
              "genome GRCh38"))

# ExactClassVerifier (admet shape)
cv = ExactClassVerifier()
ck("class-match accuracy counts correct labels",
   cv.score({"classes": {"herg": "blocker", "ames": "negative"}},
            "herg: blocker; ames: negative") == 1.0)
ck("partial class match is partial",
   cv.score({"classes": {"herg": "blocker", "ames": "negative"}},
            "herg: blocker only") == 0.5)

# TrustLatticeVerifier (answer-free)
tv = TrustLatticeVerifier()
ck("more tier-A/B citations -> higher answer-free reward",
   tv.score(None, "[A·x][A·y][B·z]") > tv.score(None, "no citations"))
ck("boundary honesty earns a bonus",
   tv.score(None, "where the record stops") > tv.score(None, "plain text"))

passed = sum(1 for c in _R if c)
print(f"\n{passed}/{len(_R)} passed")
sys.exit(0 if passed == len(_R) else 1)
