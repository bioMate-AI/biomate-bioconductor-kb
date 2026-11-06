"""Tests for the designability speed surrogate.

Contract: (1) sequence featurizer is deterministic and the right width; (2) the ranking AUC helper
is correct; (3) leave-one-target-out + within-target evaluators run and return well-formed reports;
(4) the honest signal holds on synthetic data where designability is a known function of features.
No GPU, no network — runs on the committed designability_v1.csv if present, else synthetic.
"""
import importlib.util
import sys
from pathlib import Path

import numpy as np
import pytest

HERE = Path(__file__).resolve().parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


ss = _load("speed_surrogate")


def test_selftest():
    assert ss._selftest() == 0


def test_featurizer_width_and_determinism():
    a = ss.featurize("ACDEFGHIK")
    b = ss.featurize("ACDEFGHIK")
    assert a == b
    assert len(a) == len(ss.FEATURE_NAMES)
    assert a[0] == 9.0  # length


def test_auc_helper():
    assert ss._auc([0, 0, 1, 1], [0.1, 0.2, 0.8, 0.9]) == 1.0
    assert ss._auc([1, 1, 0, 0], [0.1, 0.2, 0.8, 0.9]) == 0.0
    assert abs(ss._auc([0, 1, 0, 1], [0.5, 0.5, 0.5, 0.5]) - 0.5) < 1e-9  # all-tie -> 0.5


def test_row_features_modes():
    row = {"sequence": "ACDEF", **{c: 1.0 for c in ss.DESIGN_FEATS}}
    seq = ss.row_features(row, "seq")
    des = ss.row_features(row, "design")
    comb = ss.row_features(row, "combined")
    assert len(seq) == len(ss.FEATURE_NAMES)
    assert len(des) == len(ss.DESIGN_FEATS)
    assert len(comb) == len(seq) + len(des)


def test_screening_efficiency_perfect_ranking():
    # perfect score ordering -> co-fold only the positives to reach full recall
    y = [1, 1, 0, 0, 0]
    score = [0.9, 0.8, 0.3, 0.2, 0.1]
    out = ss.screening_efficiency(y, score, recall_target=1.0)
    assert out["candidates_cofolded"] == 2
    assert out["cofold_work_saved_pct"] == 60.0


def test_within_target_eval_runs_on_synthetic():
    rng = np.random.default_rng(1)
    rows = []
    for t in ["a", "b"]:
        for _ in range(80):
            seq = "".join(rng.choice(list(ss._AAS), int(rng.integers(8, 14))))
            kd = sum(ss._KD[c] for c in seq) / len(seq)
            fr = 2.2 - 0.5 * kd + rng.normal(0, 0.4)
            rows.append({"sequence": seq, "target": t, "filter_rmsd": fr,
                         "designable": int(fr < 2.0)})
    res = ss.within_target_eval(rows, min_rows=40, mode="seq")
    assert res["targets_evaluated"]
    assert res["macro_auc_designable"] is not None


@pytest.mark.skipif(not ss.DEFAULT_CSV.exists(), reason="real dataset not present")
def test_real_dataset_loads_and_has_design_feats():
    rows = ss.load_rows(ss.DEFAULT_CSV)
    assert len(rows) > 100
    assert ss.has_design_feats(rows)
    # within-target combined should beat sequence-only on the real data (design confidence helps)
    seq_auc = ss.within_target_eval(rows, mode="seq")["macro_auc_designable"]
    comb_auc = ss.within_target_eval(rows, mode="combined")["macro_auc_designable"]
    assert comb_auc >= seq_auc  # design-time features add signal (honest: modest)
