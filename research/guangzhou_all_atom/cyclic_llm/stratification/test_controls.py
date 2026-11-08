"""Positive/negative controls for family permutation importance and stratified metrics. Run: python3 test_controls.py"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from sklearn.model_selection import GroupKFold
import importance as I

def test_importance_finds_only_the_planted_family():
    rng = np.random.default_rng(0); n = 1200; X = rng.normal(size=(n, 9)); y = 1.5 * X[:, 0] + 1.0 * X[:, 1] + rng.normal(0, 0.5, n)      # families: A=cols0-2 (signal), B=3-5 (noise), C=6-8 (noise)
    g = np.repeat(np.arange(300), 4); folds = list(GroupKFold(5).split(X, y, g))
    d = I.family_perm_importance(X, y, folds, {"A": [0, 1, 2], "B": [3, 4, 5], "C": [6, 7, 8]}, reps=8)
    assert d["A"].mean() > 0.3 and d["B"].mean() < 0.03 and d["C"].mean() < 0.03

def test_importance_zero_when_no_signal():
    rng = np.random.default_rng(1); n = 800; X = rng.normal(size=(n, 6)); y = rng.normal(size=n); g = np.repeat(np.arange(200), 4); folds = list(GroupKFold(5).split(X, y, g))
    d = I.family_perm_importance(X, y, folds, {"A": [0, 1, 2], "B": [3, 4, 5]}, reps=6); assert abs(d["A"].mean()) < 0.12 and abs(d["B"].mean()) < 0.12          # null Spearman SD ~ 1/sqrt(n) = 0.035 (3.4 SD)

def test_stratum_metric_detects_skill_only_in_planted_stratum():
    rng = np.random.default_rng(2); n = 1500; stratum = rng.random(n) < 0.4; y = rng.normal(size=n); pred = np.where(stratum, y + rng.normal(0, 0.5, n), rng.normal(size=n)); g = np.arange(n)
    pt_in, lo_in, _ = I.stratum_spearman(pred, y, stratum, g); pt_out, lo_out, hi_out = I.stratum_spearman(pred, y, ~stratum, g)
    assert lo_in > 0.5 and lo_out < 0 < hi_out          # skill recovered inside, CI covers 0 outside

if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for f in fns: f(); print("PASS", f.__name__)
    print(len(fns), "tests passed")
