"""Positive controls for validity_gate.py: a benchmark whose positives differ in a no-target proxy must FAIL; a balanced benchmark must PASS."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import validity_gate as G

def _fp(prox, seed=1):
    return pd.DataFrame(np.random.default_rng(seed).poisson(1.0, (len(prox), 12)).astype(np.float32), index=prox.index)

def world(shift, n_fam=24, tpf=2, npos=10, ndec=20, seed=0):
    rng = np.random.default_rng(seed); rows = []; tf = []; prox = {}; cid = 0; folds = {}
    for f in range(n_fam):
        folds[f"F{f}"] = f % 5
        for t in range(tpf):
            tk = f"T{f}_{t}"; tf.append((tk, f"F{f}", ""))
            for i in range(npos * (1 + ndec)):
                lab = 1 if i < npos else 0; c = f"C{cid}"; cid += 1; rows.append((tk, c, lab))
                p = {k: rng.normal() for k in G.SECONDARY + ["typicality", "n_alpha"]}
                p["heavy"] += shift * lab                      # planted no-target difference
                prox[c] = p
    return pd.DataFrame(rows, columns=["target_key", "compound_id", "label"]), pd.DataFrame(tf, columns=["target_key", "family", "genes"]), pd.DataFrame.from_dict(prox, orient="index"), folds

def test_planted_proxy_difference_fails_gate():
    items, tfam, prox, folds = world(shift=0.8); r = G.run_gate(items, tfam, prox, folds, FP=_fp(prox))
    assert not r["VALID"] and any("heavy" in f for f in r["failed_controls"]) and "C2_multiproxy_leave_fold_out" in r["failed_controls"], r["failed_controls"]

def test_balanced_benchmark_passes_gate():
    items, tfam, prox, folds = world(shift=0.0, seed=3); r = G.run_gate(items, tfam, prox, folds, FP=_fp(prox))
    assert r["VALID"], r["failed_controls"]

def test_fingerprint_only_difference_fails_C3():
    items, tfam, prox, folds = world(shift=0.0, seed=6); rng = np.random.default_rng(6)
    FP = pd.DataFrame(rng.poisson(1.0, (len(prox), 12)).astype(np.float32), index=prox.index); lab = items.set_index("compound_id").label.reindex(prox.index).values
    FP.iloc[:, 0] += lab * 3
    r = G.run_gate(items, tfam, prox, folds, FP=FP); assert "C3_morgan_fp_leave_fold_out" in r["failed_controls"], r["failed_controls"]

def test_typicality_only_difference_fails_primary():
    items, tfam, prox, folds = world(shift=0.0, seed=4); prox["typicality"] += items.set_index("compound_id").label.reindex(prox.index).values * 0.8
    r = G.run_gate(items, tfam, prox, folds, FP=_fp(prox)); assert "C1_atomlm_typicality" in r["failed_controls"]

def test_too_few_families_is_unverifiable_not_valid():
    items, tfam, prox, folds = world(shift=0.0, n_fam=3, seed=8); r = G.run_gate(items, tfam, prox, folds, FP=_fp(prox))
    assert not r["VALID"] and any(f.startswith("unverifiable") for f in r["failed_controls"]), r["failed_controls"]

if __name__ == "__main__":
    n = 0
    for k, f in list(globals().items()):
        if k.startswith("test_"): f(); n += 1; print("PASS", k)
    print(n, "tests passed")
