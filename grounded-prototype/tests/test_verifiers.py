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
ck("ground truth with expected_params -> answer-based params verifier (real preferred, mirror fallback)",
   select_verifier({"expected_params": {"genome": "GRCh38"}}).name in ("expected_params_real", "expected_params_f1"))
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

# RealDecompVerifier — BioMate's PRODUCTION scorer wired in (not the mirror)
from research.verifiers import real_decomp_verifier, StructureVerifier, select_verifier  # noqa: E402
import json as _json  # noqa: E402

_real = real_decomp_verifier()
_gold = {"gold_subtasks": [
    {"sub_task": "Align reads", "order": 1, "depends_on": [], "domain": "genomics"},
    {"sub_task": "Call variants", "order": 2, "depends_on": [1], "domain": "variant_calling"},
    {"sub_task": "Annotate variants", "order": 3, "depends_on": [2], "domain": "variant_calling"},
]}
_exact = _json.dumps([{"sub_task": s["sub_task"], "order": s["order"], "depends_on": s["depends_on"]}
                      for s in _gold["gold_subtasks"]])
_collapsed = _json.dumps([{"sub_task": s["sub_task"], "order": s["order"], "depends_on": []}
                          for s in _gold["gold_subtasks"]])

ck("real decomposition scorer loads from evaluation/", _real is not None)
if _real is not None:
    ck("select_verifier routes a gold_subtasks task to the REAL scorer",
       select_verifier(_gold).name == "decomp_structure_real")
    _mirror = StructureVerifier()
    # the mirror was faithful AND the real scorer is wired correctly iff they agree
    ck("real scorer agrees with the mirror on the exact plan",
       abs(_real.score(_gold, _exact) - _mirror.score(_gold, _exact)) < 1e-9)
    ck("real scorer agrees with the mirror on a collapsed plan",
       abs(_real.score(_gold, _collapsed) - _mirror.score(_gold, _collapsed)) < 1e-9)
    ck("real scorer ranks the exact plan above the collapsed one",
       _real.score(_gold, _exact) > _real.score(_gold, _collapsed))

# RealParamsVerifier — BioMate's production param matcher (alias/unit normalisation)
from research.verifiers import real_params_verifier  # noqa: E402
_rp = real_params_verifier()
ck("real param matcher loads from evaluation/", _rp is not None)
if _rp is not None:
    ck("select_verifier routes expected_params to the REAL matcher",
       select_verifier({"expected_params": {"genome": "human"}}).name == "expected_params_real")
    _gt = {"expected_params": {"genome": "human"}, "must_not_fill": ["adapter"]}
    # REAL alias normalisation: a structured 'GRCh38' matches expected 'human' (mirror cannot)
    ck("real matcher normalises human==GRCh38 on a structured response",
       _rp.score(_gt, _json.dumps({"genome": "GRCh38"})) == 1.0)
    ck("the text mirror CANNOT match human vs GRCh38 (shows the real gain)",
       ExpectedParamsVerifier().score(_gt, "genome GRCh38") < 1.0)
    ck("real matcher penalises a must_not_fill violation on a structured response",
       _rp.score(_gt, _json.dumps({"genome": "GRCh38", "adapter": "trimgalore"})) < 1.0)
    ck("real matcher degrades to the text mirror for a free-text response",
       _rp.score(_gt, "genome human") == ExpectedParamsVerifier().score(_gt, "genome human"))

passed = sum(1 for c in _R if c)
print(f"\n{passed}/{len(_R)} passed")
sys.exit(0 if passed == len(_R) else 1)
