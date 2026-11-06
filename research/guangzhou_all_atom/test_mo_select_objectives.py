"""Selector objective plumbing: exact hypervolume in any dimension, opt-in gating of unvalidated objectives, renal objective sanity. Run: python3 test_mo_select_objectives.py"""
import os, sys, itertools
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "renal"))
import mo_select_qnehvi as M

def test_hv_matches_existing_2d_3d_and_is_exact_in_4d():
    rng = np.random.default_rng(0)
    for m in (2, 3):
        P = rng.random((12, m)); assert abs(M.hv(P, np.zeros(m)) - (M._hv2d(P) if m == 2 else M._hv3d(P))) < 1e-12
    assert abs(M.hv(np.array([[0.5, 0.4, 0.3, 0.2]]), np.zeros(4)) - 0.5 * 0.4 * 0.3 * 0.2) < 1e-12                  # one point = box volume
    A, B = np.array([1, .5, .5, .5]), np.array([.5, 1, .5, .5])                                                     # two boxes: inclusion-exclusion
    inc = np.prod(A) + np.prod(B) - np.prod(np.minimum(A, B)); assert abs(M.hv(np.vstack([A, B]), np.zeros(4)) - inc) < 1e-12
    P4 = rng.random((8, 4)); S = list(range(8))                                                                     # brute-force inclusion-exclusion on 8 random 4-D points
    ie = sum(((-1) ** (len(c) + 1)) * np.prod(np.min(P4[list(c)], axis=0)) for r in range(1, 9) for c in itertools.combinations(S, r))
    assert abs(M.hv(P4, np.zeros(4)) - ie) < 1e-9, (M.hv(P4, np.zeros(4)), ie)

def test_greedy_hv_select_works_with_four_objectives():
    Y = np.random.default_rng(1).random((30, 4)); sel = M.greedy_hv_select(Y, 5, np.zeros(4)); assert len(set(sel)) == 5

def test_unvalidated_objective_requires_explicit_opt_in():
    assert M.parse_objectives("binding,permeability,synthesizability", False) == ["binding", "permeability", "synthesizability"]
    try: M.parse_objectives("binding,renal", False); assert False
    except ValueError as e: assert "unvalidated" in str(e).lower()
    assert M.parse_objectives("binding,renal", True) == ["binding", "renal"]
    try: M.parse_objectives("binding,notathing", True); assert False
    except ValueError: pass

def test_renal_objective_is_deterministic_finite_labelled_and_nan_safe():
    import renal_objective as R
    seqs = ["KKKKKKKK", "GGAGGAGG", "RGDLAYPK", "EEEEEEEE"]; a = R.predict_kidney(seqs); b = R.predict_kidney(seqs)
    assert np.array_equal(a, b) and np.all(np.isfinite(a)) and a.shape == (4,)
    assert R.STATUS["validated"] is False and "Gate A" in R.STATUS["reason"]
    assert np.isnan(R.predict_kidney(["not a peptide!"])[0])              # unparsable -> NaN, never a fabricated number
    assert np.isnan(R.predict_kidney(["GGAG"], chelator="DOTA", radiometal="99mTc")[0])   # unknown (chelator, metal) charge -> NaN

def test_flatness_check_flags_an_objective_that_cannot_discriminate():
    import renal_objective as R
    flat = np.array([2.115, 2.116, 2.116, 2.080]); wide = np.array([0.5, 1.5, 2.5, 3.5])
    sd, ok = R.informative(flat); assert sd < 0.05 and ok is False
    sd, ok = R.informative(wide); assert sd > 0.5 and ok is True
    sd, ok = R.informative(np.array([np.nan, np.nan])); assert ok is False                    # nothing to rank -> not informative

def test_assemble_objectives_selects_named_columns_and_fills_nan_with_column_min():
    cols = {"binding": np.array([7.0, np.nan, 5.0]), "permeability": np.array([-5.0, -6.0, -4.0]), "synthesizability": np.array([-3.0, -2.0, -4.0]), "renal": np.array([-2.1, -2.0, -2.2])}
    Y = M.assemble_objectives(["binding", "renal"], cols); assert Y.shape == (3, 2) and Y[1, 0] == 5.0 and not np.isnan(Y).any()
    assert np.array_equal(M.assemble_objectives(["permeability"], cols)[:, 0], cols["permeability"])

if __name__ == "__main__":
    k = 0
    for n, f in sorted(globals().items()):
        if n.startswith("test_"): f(); k += 1; print("PASS", n)
    print(k, "tests passed")
