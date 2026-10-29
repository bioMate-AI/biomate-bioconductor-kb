"""Cheap tests for gpc_agg.py using hand-made records (no gate runs)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gpc_agg as A


def rec(biased=(), unver=(), lo90=0.47, hi90=0.53, status=None):
    prim = {k: dict(point=0.5, lo=0.4, hi=0.6, lo90=lo90, hi90=hi90, n_families=26) for k in ("C1_atomlm_typicality", "C2_multiproxy_leave_fold_out", "C3_morgan_leave_fold_out")}
    st = "NOT_VALID_BIASED" if biased else "NOT_VALID_UNVERIFIABLE" if unver else "VALID"
    return dict(status=status or st, biased=list(biased), unverifiable=list(unver), not_equivalent=[], primary=prim)


def test_status_at_margin_and_priority():
    r = rec(lo90=0.47, hi90=0.53)
    assert A.status_at(r, 0.05) == "VALID" and A.status_at(r, 0.03) == "VALID" and A.status_at(rec(lo90=0.44, hi90=0.56), 0.05) == "NOT_VALID_NOT_EQUIVALENT"
    assert A.status_at(rec(lo90=0.44, hi90=0.56), 0.10) == "VALID"
    assert A.status_at(rec(biased=["secondary:tpsa"]), 0.10) == "NOT_VALID_BIASED" and A.status_at(rec(unver=["secondary:x"]), 0.05) == "NOT_VALID_UNVERIFIABLE"


def test_detection_requires_intended_detector():
    assert A.detected(rec(biased=["secondary:tpsa"]), "S-tpsa") and not A.detected(rec(biased=["secondary:logp"]), "S-tpsa")
    assert A.detected(rec(biased=["secondary:logp"]), "S-diffuse") and not A.detected(rec(), "S-cens")
    assert A.detected(rec(biased=["secondary:C4_censored_label"]), "S-cens")


def test_clopper_pearson_known_values():
    lo, hi = A.cp(0, 200); assert lo == 0.0 and abs(hi - 0.0183) < 0.001
    lo, hi = A.cp(10, 100); assert abs(lo - 0.0490) < 0.002 and abs(hi - 0.1762) < 0.002
    assert A.cp(5, 5)[1] == 1.0
