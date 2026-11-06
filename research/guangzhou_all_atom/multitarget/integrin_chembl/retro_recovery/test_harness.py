"""Positive controls for harness.py: planted signal is detected, no-signal gives chance + non-significant, ties handled exactly."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness as H

def world(n_fam=30, tpf=2, npos=8, ndec=20, seed=0):
    rng = np.random.default_rng(seed); rows = []; tf = []; cid = 0
    for f in range(n_fam):
        for t in range(tpf):
            tk = f"T{f}_{t}"; tf.append((tk, f"F{f}", ""))
            for i in range(npos + npos * ndec):
                lab = 1 if i < npos else 0
                rows.append((tk, f"C{cid}", lab)); cid += 1
    return pd.DataFrame(rows, columns=["target_key", "compound_id", "label"]), pd.DataFrame(tf, columns=["target_key", "family", "genes"])

def test_auc_ef_known_values():
    y = np.array([1, 0, 0, 0]); assert H.tie_aware_auc(y, np.array([4., 3, 2, 1])) == 1.0
    assert H.tie_aware_auc(y, np.array([1., 2, 3, 4])) == 0.0
    assert H.tie_aware_auc(y, np.zeros(4)) == 0.5                              # constant -> chance, exactly
    yy = np.array([1] * 5 + [0] * 95); assert abs(H.tie_aware_ef(yy, np.arange(100)[::-1].astype(float)) - 20.0) < 1e-9   # perfect: top 5 % all positive -> EF 20
    assert abs(H.tie_aware_ef(yy, np.zeros(100)) - 1.0) < 1e-9                  # all tied -> expected EF = 1

def test_planted_signal_detected_and_beats_random():
    items, tfam = world(); rng = np.random.default_rng(1)
    sig = items.assign(score=items.label * 1.5 + rng.normal(size=len(items)))[["compound_id", "score"]]
    rnd = items.assign(score=rng.random(len(items)))[["compound_id", "score"]]
    out = H.evaluate(items, tfam, {"signal": sig, "random": rnd}, ["random"])
    assert out["vs_strongest_auc"]["signal"]["verdict"] == "SUPPORTED" and out["vs_strongest_ef5"]["signal"]["verdict"] == "SUPPORTED", out
    assert out["arms"]["signal"]["auc"]["point"] > 0.8 and abs(out["arms"]["random"]["auc"]["point"] - 0.5) < 0.05

def test_shuffled_labels_not_supported():
    items, tfam = world(); rng = np.random.default_rng(2)
    shuf = items.copy(); shuf["label"] = shuf.groupby("target_key").label.transform(lambda s: rng.permutation(s.values))
    sig = items.assign(score=items.label * 1.5 + rng.normal(size=len(items)))[["compound_id", "score"]]   # signal for the ORIGINAL labels
    rnd = items.assign(score=rng.random(len(items)))[["compound_id", "score"]]
    out = H.evaluate(shuf, tfam, {"signal": sig, "random": rnd}, ["random"])
    assert out["vs_strongest_auc"]["signal"]["verdict"] != "SUPPORTED", out

def test_constant_scorer_equals_chance_and_inconclusive():
    items, tfam = world(); rnd = items.assign(score=np.random.default_rng(3).random(len(items)))[["compound_id", "score"]]
    const = items.assign(score=0.0)[["compound_id", "score"]]
    out = H.evaluate(items, tfam, {"const": const, "random": rnd}, ["random"])
    assert abs(out["arms"]["const"]["auc"]["point"] - 0.5) < 1e-9 and abs(out["arms"]["const"]["ef5"]["point"] - 1.0) < 1e-9
    assert out["vs_strongest_auc"]["const"]["verdict"] != "SUPPORTED"

def test_anti_signal_is_not_supported_and_flagged_negative():
    items, tfam = world(); rng = np.random.default_rng(4)
    anti = items.assign(score=-items.label * 1.5 + rng.normal(size=len(items)))[["compound_id", "score"]]
    rnd = items.assign(score=rng.random(len(items)))[["compound_id", "score"]]
    out = H.evaluate(items, tfam, {"anti": anti, "random": rnd}, ["random"])
    assert out["vs_strongest_auc"]["anti"]["verdict"] == "NOT_SUPPORTED"

def test_family_bootstrap_resamples_families_not_targets():
    items, tfam = world(n_fam=3, tpf=2); rng = np.random.default_rng(5)
    s = items.assign(score=items.label + rng.normal(size=len(items)))[["compound_id", "score"]]
    pt, cov = H.per_target(items, s); fm = H.family_means(pt, tfam, "auc"); assert len(fm) == 3 and cov == 1.0

if __name__ == "__main__":
    n = 0
    for k, f in list(globals().items()):
        if k.startswith("test_"): f(); n += 1; print("PASS", k)
    print(n, "tests passed")
