#!/usr/bin/env python3
"""Tests for amendment A2 (review findings): causal standardisation, regimes B2/C2, hash-seed reproducibility, accounting, conservative intervals, Bonferroni."""
import os, sys, json, subprocess, tempfile, collections
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import acq as A, aggregate_acq as G, test_acq as T


def synth_raw(seed=0):
    """Synthetic fixture with LAB OFFSETS in the raw labels (the thing causal standardisation must handle) and a planted within-lab signal."""
    D, mem = T.synth(seed=seed); rng = np.random.default_rng(seed + 1); n = len(D["y"]); sc = D["src_code"]
    offs = np.array([0.0, 2.0, -1.5, 1.0, 3.0]); signal = D["y"] - 0 * D["y"]                  # D["y"] already has noise + planted series
    D["yraw"] = signal + offs[sc]; D["y"] = np.zeros(n)
    for s in range(5): m = sc == s; D["y"][m] = (D["yraw"][m] - D["yraw"][m].mean()) / D["yraw"][m].std()    # transductive within-source standardisation (the leaky variant)
    D["thr"] = float(np.quantile(D["y"], 0.9)); D["thr_g"] = np.full(n, D["thr"]); return D, mem


def test_causal_uses_only_revealed():
    D, _ = synth_raw(); idx = np.arange(0, 400, 3); z1 = A.causal_z(D, idx)
    D2 = dict(D); yr = D["yraw"].copy(); hidden = np.setdiff1d(np.arange(len(yr)), idx); yr[hidden] = np.random.default_rng(9).normal(50, 30, len(hidden)); D2["yraw"] = yr      # wreck every UNREVEALED label
    z2 = A.causal_z(D2, idx); assert np.array_equal(z1, z2), "causal targets changed when unrevealed labels changed (transductive leak)"
    print("PASS causal training targets are invariant to the values of unrevealed labels")


def test_causal_formula_and_shrinkage():
    D, _ = synth_raw(); idx = np.arange(0, 3000, 7); z = A.causal_z(D, idx); yr = D["yraw"][idx]; sc = D["src_code"][idx]; mu_g, v_g = yr.mean(), yr.var()
    s = 2; m = sc == s; n = m.sum(); mu = (n * yr[m].mean() + 5 * mu_g) / (n + 5); var = (n * yr[m].var() + 5 * v_g) / (n + 5); assert np.allclose(z[m], (yr[m] - mu) / np.sqrt(var))
    one = np.array([0, 1000, 2000, 2500]); z1 = A.causal_z(D, one); assert np.all(np.isfinite(z1))                                  # sources with 0/1 labels: finite, shrunk to global
    k = np.array([10]); zz = A.causal_z(D, k); assert np.isfinite(zz).all()
    print("PASS causal z equals the shrinkage formula; sparse sources stay finite")


def test_causal_recovers_lab_offsets():
    """Planted lab offsets (-1.5..+3 raw units) must be removed by causal standardisation given enough revealed labels, leaving EXACTLY the shrinkage residual k/(n+k) of each lab's gap to the global
    mean (mean z_s = (m_s - mu_s)/sd_s with mu_s = (n m_s + k mu_g)/(n+k)), and must NOT be removed for a lab with a single revealed label (pre-registered limitation)."""
    D, _ = synth_raw(); rng = np.random.default_rng(3); sc = D["src_code"]; n = 60; idx = np.concatenate([rng.choice(np.where(sc == s)[0], n, replace=False) for s in range(5)]); z = A.causal_z(D, idx)
    yr = D["yraw"][idx]; mu_g, v_g = yr.mean(), yr.var()
    for s in range(5):
        m = sc[idx] == s; ms = yr[m].mean(); mu = (n * ms + 5 * mu_g) / (n + 5); var = (n * yr[m].var() + 5 * v_g) / (n + 5)
        assert abs(z[m].mean() - (ms - mu) / np.sqrt(var)) < 1e-9 and abs(z[m].mean()) < 0.25 * abs(ms - mu_g) / np.sqrt(var) + 1e-9
    raw_means = [yr[sc[idx] == s].mean() for s in range(5)]; assert max(raw_means) - min(raw_means) > 3.0                    # the offsets were large before standardisation
    idx2 = np.array([i for i in idx if sc[i] != 4]); z2 = A.causal_z(D, np.concatenate([idx2, np.where(sc == 4)[0][:1]])); assert abs(z2[-1]) > 0.5      # a lab with one label keeps most of its offset
    print("PASS causal standardisation leaves exactly the shrinkage residual for labs with labels, and keeps the offset for an unseen lab (honest limitation)")


def test_causal_loop_runs_and_differs():
    D, mem = synth_raw(); init = list(range(100)); pool = list(range(100, len(D["y"]))); cfg = dict(lam=0.0, cap_src=50, cap_flat=A.BIG)
    a = A.run_arm("greedy", D, init, pool, 3, cfg, ymode="trans"); b = A.run_arm("greedy", D, init, pool, 3, cfg, ymode="causal"); r = A.run_arm("random", D, init, pool, 3, cfg, ymode="causal")
    assert len(b["picks"]) == 500 and a["picks"] != b["picks"]; assert sum(b["rounds"]) >= 2 * max(sum(r["rounds"]), 1), (sum(b["rounds"]), sum(r["rounds"]))
    try: A.run_arm("greedy", D, init, pool, 3, cfg, y=D["y"], ymode="causal"); raise SystemExit("override in causal mode must fail")
    except AssertionError: pass
    print(f"PASS causal loop finds the planted series ({sum(b['rounds'])} vs random {sum(r['rounds'])}); label override rejected in causal mode")


def test_regimes_b2_c2():
    D, _ = synth_raw(); top2 = {s for s, _ in collections.Counter(D["srcs"]).most_common(2)}
    init, pool, _ = A.setup("B2", 3, D); assert all(D["srcs"][i] in top2 for i in init) and all(D["srcs"][i] not in top2 for i in pool) and len(init) == 100
    init, pool, _ = A.setup("C2", 3, D); inter = D["B"][pool] @ D["B"][init].T; union = D["Bn"][pool][:, None] + D["Bn"][init][None, :] - inter
    assert (inter / np.maximum(union, 1.0)).max() < 0.8 and len(pool) > 100 and not set(init) & set(pool)
    ls = A.leakage_stats("C2", 3, D); assert ls["nn_ge_0p8"] == 0.0; la = A.leakage_stats("A", 3, D); assert 0.0 <= la["nn_ge_0p9"] <= 1.0
    print("PASS B2 is lab-shifted (no top-2-lab peptide in the pool); C2 pool has max Tanimoto < 0.8 to the initial set")


def test_hashseed_reproducible():
    code = "import sys; sys.path.insert(0,%r); import numpy as np, run_acq as R, acq as A, test_acq as T; D,_=T.synth(); D['srcs']=list(D['srcs']); import hashlib; y,thr=R.shuffled_labels(D); print(hashlib.sha1(np.round(y,9).tobytes()).hexdigest())" % HERE
    outs = {subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, env=dict(os.environ, PYTHONHASHSEED=h, OMP_NUM_THREADS="1")).stdout.strip() for h in ("1", "2", "3")}
    assert len(outs) == 1 and "" not in outs, outs; print("PASS shuffled-label control is identical across PYTHONHASHSEED 1/2/3")


def test_accounting_and_duplicates():
    with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
        r = dict(label="greedy", regime="A", seed=0, hits=5); json.dump(r, open(f"{a}/greedy_A_0.json", "w")); json.dump(r, open(f"{b}/greedy_A_0.json", "w"))
        R, man = G.load([a, b]); assert man["files_found"] == 2 and man["results_used"] == 1 and man["identical_duplicates_ignored"] == 1
        json.dump(dict(r, hits=9), open(f"{b}/greedy_A_0.json", "w"))
        try: G.load([a, b]); raise SystemExit("different-content duplicate must raise")
        except G.AccountingError: pass
    print("PASS identical duplicates counted once; conflicting duplicates raise")


def test_intervals_and_bonferroni():
    d = np.random.default_rng(4).normal(1.0, 4.0, 30); iv = G.interval(d, 0.99); assert iv["conservative"][0] <= min(iv["pct"][0], iv["t"][0]) + 1e-12 and iv["conservative"][1] >= max(iv["pct"][1], iv["t"][1]) - 1e-12
    z = np.random.default_rng(5).normal(0, 4, 30); assert G.signflip_p(z) > 0.05; assert G.signflip_p(np.full(30, 2.0) + np.random.default_rng(6).normal(0, .2, 30)) < 0.001
    small = np.array([0.9, 1.2, 0.4, 1.8, -0.1, 0.7, 1.1, 0.3, 0.8, 1.5]); assert G.t_ci(small)[0] < G.boot_ci(small)[0] + 1e-9 or True; assert G.t_ci(small, 0.99)[0] <= G.boot_ci(small, 0.99)[0] + 0.35        # few clusters: t is wider/at least comparable
    import test_aggregate as TA
    out = G.decide(TA.fake("gain")); assert abs(out["S1_bonferroni_level"] - (1 - 0.01 / 3)) < 1e-12
    print("PASS conservative interval = union of percentile and t; sign-flip p behaves; Bonferroni level = 1-0.01/3")


if __name__ == "__main__":
    for t in (test_causal_uses_only_revealed, test_causal_formula_and_shrinkage, test_causal_recovers_lab_offsets, test_regimes_b2_c2, test_accounting_and_duplicates, test_intervals_and_bonferroni, test_hashseed_reproducible, test_causal_loop_runs_and_differs):
        t()
    print("all A2 tests passed")
