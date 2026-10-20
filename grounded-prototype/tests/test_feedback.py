"""
Tests for the instruction-panel feedback -> reward bridge (B2).

Proves a user correction becomes an answer-based reward signal the gated Harness2
improver can use, routes through the P0 verifier bridge, and maps to a DPO pair.

Run:  python3 grounded-prototype/tests/test_feedback.py
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from research.feedback import (  # noqa: E402
    Correction, CorrectionVerifier, corrections_to_dpo_pairs,
)
from research.verifiers import select_verifier  # noqa: E402

_R = []


def ck(name, cond):
    print(("PASS" if cond else "FAIL"), "-", name)
    _R.append(cond)


def _raises(fn):
    try:
        fn()
        return False
    except Exception:
        return True


# a realistic correction: user said human -> GRCh38, model had used GRCh37
_c = Correction(
    correction_type="parameters",
    context="Align my human RNA-seq reads to the reference genome.",
    original_value="GRCh37",
    corrected_value="GRCh38",
    reason="we standardise on GRCh38",
)

# validation
ck("unknown correction_type raises", _raises(lambda: Correction("bogus", "c", "a", "b")))

# to_task -> Harness2-shaped task with correction ground truth
t = _c.to_task()
ck("to_task carries expected + avoid ground truth",
   t["ground_truth"]["expected"] == "GRCh38" and t["ground_truth"]["avoid"] == "GRCh37")
ck("to_task id is correction-scoped", t["id"].startswith("corr:parameters:"))

# CorrectionVerifier: reward the fix, penalise repeating the mistake
cv = CorrectionVerifier()
gt = t["ground_truth"]
ck("producing the corrected value scores full",
   cv.score(gt, "I will align to GRCh38.") == 1.0)
ck("repeating the original mistake lowers the score",
   cv.score(gt, "aligning to GRCh38 (not GRCh37)") < 1.0)
ck("producing neither scores 0", cv.score(gt, "aligning to the reference") == 0.0)

# P0 verifier bridge routes a correction-shaped task to the correction verifier
ck("select_verifier routes a correction task to CorrectionVerifier",
   select_verifier(gt).name == "correction_match" and select_verifier(gt).answer_free is False)

# DPO pair mapping (generalises the regulatory-DPO template)
pair = _c.to_dpo_pair()
ck("to_dpo_pair is chosen=corrected / rejected=original",
   pair["chosen"] == "GRCh38" and pair["rejected"] == "GRCh37")
noop = Correction("domain", "q", "genomics", "genomics")  # fix == original
ck("corrections_to_dpo_pairs skips no-op corrections",
   len(corrections_to_dpo_pairs([_c, noop])) == 1)


if __name__ == "__main__":
    passed = sum(1 for c in _R if c)
    print(f"\n{passed}/{len(_R)} passed")
    sys.exit(0 if passed == len(_R) else 1)
