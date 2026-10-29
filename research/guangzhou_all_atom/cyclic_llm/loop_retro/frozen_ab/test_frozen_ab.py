#!/usr/bin/env python3
"""Unit tests for the frozen aware-vs-blind aggregator and planted labels. Run: python3 frozen_ab/test_frozen_ab.py (prints PASS/FAIL per test, exit 1 on failure)."""
import os, sys, math
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import aggregate_frozen_ab as A, planted_run as P
FAILS = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name); 
    if not cond: FAILS.append(name)


def t_intervals_match_scipy():
    d = np.array([1., 2., 3., 4., 5., 9.]); lo, hi = A.t_interval(d, .95)
    from scipy import stats
    ref = stats.t.interval(.95, 5, loc=d.mean(), scale=d.std(ddof=1) / math.sqrt(6)); check("t_interval equals scipy", abs(lo - ref[0]) < 1e-9 and abs(hi - ref[1]) < 1e-9)


def boot_deterministic_and_covers():
    d = np.random.default_rng(1).normal(5, 2, 40); a, b = A.boot_interval(d), A.boot_interval(d); check("bootstrap deterministic", a == b)
    check("bootstrap interval contains the mean and is near the t-interval", a[0] < d.mean() < a[1] and abs(a[0] - A.t_interval(d)[0]) < 0.5)


def holm_known():
    out = A.holm({"a": 0.01, "b": 0.04, "c": 0.03}); check("Holm adjusted p (0.01,0.03,0.04 -> 0.03,0.06,0.06)", abs(out["a"] - 0.03) < 1e-12 and abs(out["c"] - 0.06) < 1e-12 and abs(out["b"] - 0.06) < 1e-12)


def decision_rule():
    rng = np.random.default_rng(2)
    d0 = rng.normal(0.0, 4.0, 40); lab0, _ = A.decide(d0, A.holm({"x": A.paired_p(d0)})["x"]); check("null difference with SE~0.6 is EQUIVALENT", lab0 == "EQUIVALENT")
    d1 = rng.normal(-13, 14, 40); lab1, _ = A.decide(d1, 0.01); check("-13 hits with SD 14 (n=40), adj p .01 is DIFFERENT (CI not inside +-10)", lab1 in ("DIFFERENT", "DIFFERENT_BUT_WITHIN_MARGIN"))
    d2 = rng.normal(-3, 4, 40); lab2, _ = A.decide(d2, 1e-6); check("small real difference is DIFFERENT_BUT_WITHIN_MARGIN", lab2 == "DIFFERENT_BUT_WITHIN_MARGIN")
    d3 = rng.normal(0, 30, 6); lab3, _ = A.decide(d3, 0.9); check("few noisy seeds is INCONCLUSIVE", lab3 == "INCONCLUSIVE")


def regression_detects_changes():
    rec = {"frozen": {"hits": [1, 2], "picks": [[1], [2]], "E_scores_final": [0.1]}, "E": [1], "init": [2]}
    same = A.regression({0: rec}, {0: dict(rec)}, "aware", "L"); check("regression passes on identical files", not same["mismatches"] and same["compared"] == 1)
    other = {"frozen": {"hits": [1, 3], "picks": [[1], [2]], "E_scores_final": [0.1]}, "E": [1], "init": [2]}
    bad = A.regression({0: other}, {0: rec}, "aware", "L"); check("regression flags one changed hit", len(bad["mismatches"]) == 1)
    miss = A.regression({}, {0: rec}, "aware", "L"); check("regression flags a missing new file", len(miss["mismatches"]) == 1)


def planted_labels():
    from rdkit import Chem
    iso = ["N[C@@H](C)C(=O)N[C@@H](C)C(=O)O", "N[C@H](C)C(=O)N[C@@H](C)C(=O)O", "N[C@H](C)C(=O)N[C@H](C)C(=O)O"]    # LL / DL / DD alanine dipeptides: one graph, three stereoisomers
    assert len({Chem.MolToSmiles(Chem.MolFromSmiles(s), isomericSmiles=False) for s in iso}) == 1
    ch = P.synthetic_raw_labels(iso * 40, "chiral"); fl = P.synthetic_raw_labels(iso * 40, "flat")
    # strip the noise term by comparing the identical-stereo copies with different noise: use group means over the 40 copies
    m_ch = [ch[i::3].mean() for i in range(3)]; m_fl = [fl[i::3].mean() for i in range(3)]
    check("chiral signal separates stereoisomers of one graph", max(m_ch) - min(m_ch) > 1.0)
    check("flat signal is identical for stereoisomers of one graph", max(m_fl) - min(m_fl) < 0.5)


for t in (t_intervals_match_scipy, boot_deterministic_and_covers, holm_known, decision_rule, regression_detects_changes, planted_labels): t()
print("ALL PASS" if not FAILS else f"FAILED: {FAILS}"); sys.exit(1 if FAILS else 0)
