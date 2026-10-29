"""Cheap tests for gpc_agg.py using hand-made records (no gate runs)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gpc_agg as A


def rec(biased=(), unver=(), lo90=0.47, hi90=0.53, status=None):
    prim = {k: dict(point=0.5, lo=0.4, hi=0.6, lo90=lo90, hi90=hi90, n_families=26) for k in ("C1_atomlm_typicality", "C2_multiproxy_leave_fold_out", "C3_morgan_leave_fold_out")}
    st = "NOT_VALID_BIASED" if biased else "NOT_VALID_UNVERIFIABLE" if unver else "VALID"
    return dict(status=status or st, biased=list(biased), unverifiable=list(unver), not_equivalent=[], primary=prim, secondary={"tpsa": dict(point=0.5, lo=0.45, hi=0.55, n_families=26)})


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


def test_knife_edge_flags_only_near_threshold_records():
    far = rec(lo90=0.47, hi90=0.53); near = rec(lo90=0.4503, hi90=0.53)           # lo90 within 3e-4 of the 0.45 equivalence edge
    assert not A.knife_edge(far) and A.knife_edge(near)


def test_per_control_and_certifier_logic():
    R = [rec(lo90=0.47, hi90=0.53) for _ in range(6)] + [rec(lo90=0.40, hi90=0.60) for _ in range(4)]
    pc = A.per_control(R)["C1_atomlm_typicality"]
    assert pc["P_equivalent"]["k"] == 6 and pc["P_width90_gt_0p10"]["k"] == 4 and pc["P_biased"]["k"] == 0
    assert A.CERT_F == [14, 20, 26, 47, 85, 150] and 150 in A.F_GRID and 47 in A.F_GRID


def test_main_merges_two_files_and_reports_certifier(tmp_path):
    import json
    def line(i, kind, **kw): r = rec(); r.update(id=i, kind=kind, family=kw.get("family"), a=kw.get("a"), F=kw.get("F"), seed=i); return json.dumps(r)
    f1 = tmp_path / "a.jsonl"; f2 = tmp_path / "b.jsonl"
    f1.write_text("\n".join(line(f"VI-{i}", "VI") for i in range(10)) + "\n"); f2.write_text("\n".join(line(f"CURVE-F26-{i}", "CURVE", F=26) for i in range(10)) + "\n")
    A.OUT = str(tmp_path); A.main([str(f1), str(f2)])
    S = json.load(open(tmp_path / "gpc_summary.json"))
    assert S["n_records"] == 20 and S["PASS_C_certifier"]["26"]["certifier"] and S["PASS_C_at_real_F"]["VI (real F=26)"]


def test_c3_range_shifts_only_c3():
    near = rec(); near["primary"]["C3_morgan_fp_leave_fold_out"] = dict(point=0.5, lo=0.4995, hi=0.6, lo90=0.47, hi90=0.53, n_families=26)   # lo within 5e-4 of 0.5
    out = A.c3_range([near])
    assert out["none"]["P_biased"]["k"] == 0 and out["c3_up"]["P_biased"]["k"] == 1 and out["c3_down"]["P_biased"]["k"] == 0
    other = rec(); other["primary"]["C1_atomlm_typicality"] = dict(point=0.5, lo=0.4995, hi=0.6, lo90=0.47, hi90=0.53, n_families=26)         # same geometry on C1: must NOT be shifted
    assert A.c3_range([other])["c3_up"]["P_biased"]["k"] == 0
