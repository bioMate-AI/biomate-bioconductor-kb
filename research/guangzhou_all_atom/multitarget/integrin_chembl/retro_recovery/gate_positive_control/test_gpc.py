"""Tests for the positive-control library (cheap; no full gate runs except one tiny determinism check)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
import gpc_lib as L


def _items():
    S = L.state(); return S["I"]


def test_permutation_preserves_target_counts_and_changes_labels():
    I = _items(); P = L.permute_labels(I, np.random.default_rng(3))
    assert (I.groupby("target_key").label.sum() == P.groupby("target_key").label.sum()).all() and (I.label.values != P.label.values).mean() > 0.05
    assert (P.compound_id.values == I.compound_id.values).all()


def test_planted_labels_preserve_counts_and_hit_calibrated_auc():
    I = _items(); z = L.planted_score(I, "S-tpsa"); rng = np.random.default_rng(1)
    for d in (0.0, 1.5):
        Q = L.planted_labels(I, z, d, rng); assert (I.groupby("target_key").label.sum() == Q.groupby("target_key").label.sum()).all()
    a0 = L.mean_target_auc(L.planted_labels(I, z, 0.0, np.random.default_rng(2)), z); a1 = L.mean_target_auc(L.planted_labels(I, z, 3.0, np.random.default_rng(2)), z)
    assert 0.45 < a0 < 0.55 and a1 > 0.7, (a0, a1)
    c = L.calibrate(I, "S-tpsa", 0.65, seeds=range(5), tol=0.01); assert c["feasible"] and abs(c["achieved"] - 0.65) < 0.02, c


def test_censoring_shortcut_uses_the_real_flag_and_is_calibratable():
    I = _items(); c = L.calibrate(I, "S-cens", 0.60, seeds=range(5), tol=0.01); assert c["feasible"], c


def test_synth_benchmark_shapes_and_determinism():
    a, tf, fo = L.synth_benchmark(8, 11); b, _, _ = L.synth_benchmark(8, 11)
    assert a.equals(b) and tf.family.nunique() == 8 and a.groupby("target_key").label.agg(["min", "max"]).values.tolist() and (a.groupby("target_key").label.nunique() == 2).all()
    assert max(fo.values()) == 4 and a.groupby("target_key").size().max() <= 600


def test_tiny_job_is_deterministic():
    j = dict(id="t", kind="CURVE", F=8, seed=424242); r1 = L.run_job(j); r2 = L.run_job(j)
    assert r1["status"] == r2["status"] and r1["primary"] == r2["primary"]
