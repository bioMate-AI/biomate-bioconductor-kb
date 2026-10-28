"""Planted-signal controls for T1 (PREREG section 6.1). Run: python3 test_fusion.py"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fusion as F


def world(seed, prior_strength, cluster_strength, n_clusters=20, per=20, nbits=256, noise=0.5):
    rng = np.random.default_rng(seed); n = n_clusters * per; cid = np.repeat(np.arange(n_clusters), per)
    cent = (rng.random((n_clusters, nbits)) < 0.25); flip = rng.random((n, nbits)) < 0.05; X = np.logical_xor(cent[cid], flip).astype(np.float32)
    u = rng.normal(size=n); off = rng.normal(size=n_clusters)[cid]
    y = prior_strength * u + cluster_strength * off + noise * rng.normal(size=n)
    P = u + 0.7 * rng.normal(size=n) if prior_strength > 0 else rng.normal(size=n)
    return X, y, P


def run(prior_strength, cluster_strength, ks=(5, 10, 25), seeds=20, n0=5.0):
    out = {k: dict(K=[], A=[], F=[], F2=[]) for k in ks}
    for s in range(seeds):
        X, y, P = world(s, prior_strength, cluster_strength); rng = np.random.default_rng(1000 + s)
        for k in ks:
            rev = rng.choice(len(y), k, replace=False); rest = np.setdiff1d(np.arange(len(y)), rev)
            A = F.analog_perm(F.tanimoto(X[rest], X[rev]), y[rev])
            out[k]["K"].append(F.spearman(P[rest], y[rest])); out[k]["A"].append(F.spearman(A, y[rest])); out[k]["F"].append(F.spearman(F.fuse(P[rest], A, k, n0), y[rest]))
            r = F.reliability_perm(F.tanimoto(X[rev], X[rev]), y[rev]); out[k]["F2"].append(F.spearman(F.fuse2(P[rest], A, k, r, n0), y[rest]))
    return {k: {m: float(np.nanmean(v)) for m, v in d.items()} for k, d in out.items()}


def test_z_constant_and_k0():
    assert np.all(F.z(np.ones(5)) == 0)
    P = np.array([3., 1., 2., 5.]); A = np.array([1., 9., 3., 2.])
    assert np.array_equal(np.argsort(F.fuse(P, A, 0)), np.argsort(P))                    # k = 0 -> prior ordering
    assert np.all(np.isfinite(F.fuse(P, np.ones(4), 5)))                                 # constant analog component: no NaN


def test_prior_only_world():
    r = run(prior_strength=1.0, cluster_strength=0.0)
    print("prior-only world", {k: {m: round(v, 3) for m, v in d.items()} for k, d in r.items()})
    assert r[5]["F"] >= 0.8 * r[5]["K"], r[5]
    assert r[5]["F"] >= r[5]["A"] - 0.03


def test_analog_only_world():
    r = run(prior_strength=0.0, cluster_strength=1.5)
    print("analog-only world", {k: {m: round(v, 3) for m, v in d.items()} for k, d in r.items()})
    assert abs(r[25]["F"] - r[25]["A"]) <= 0.03 or r[25]["F"] >= r[25]["A"] - 0.03


def test_both_signals_world():
    r = run(prior_strength=1.0, cluster_strength=1.5)
    print("both-signals world", {k: {m: round(v, 3) for m, v in d.items()} for k, d in r.items()})
    assert any(r[k]["F"] >= max(r[k]["K"], r[k]["A"]) + 0.02 for k in r)


# ---- Amendment A1 controls for F2 (all three worlds, all k) ----
def test_F2_prior_only_world():
    r = run(1.0, 0.0); print("F2 prior-only", {k: {m: round(v, 3) for m, v in d.items()} for k, d in r.items()})
    for k in r: assert r[k]["F2"] >= max(r[k]["K"], r[k]["A"]) - 0.03 or r[k]["F2"] >= 0.8 * r[k]["K"], (k, r[k])


def test_F2_analog_only_world():
    r = run(0.0, 1.5); print("F2 analog-only", {k: {m: round(v, 3) for m, v in d.items()} for k, d in r.items()})
    assert r[25]["F2"] >= r[25]["A"] - 0.03, r[25]


def test_F2_both_signals_world():
    r = run(1.0, 1.5); print("F2 both", {k: {m: round(v, 3) for m, v in d.items()} for k, d in r.items()})
    assert any(r[k]["F2"] >= max(r[k]["K"], r[k]["A"]) + 0.02 for k in r), r


def _tie_auc(y, s):                                          # minimal tie-aware AUROC (stand-in for the harness function)
    y = np.asarray(y); s = np.asarray(s, float); pos = s[y == 1]; neg = s[y == 0]
    return float(((pos[:, None] > neg[None, :]).sum() + 0.5 * (pos[:, None] == neg[None, :]).sum()) / (len(pos) * len(neg)))


def test_reliability_nn_planted():
    rng = np.random.default_rng(0); nb = 256; hi, lo = [], []
    for s in range(40):
        cent = {c: (rng.random(nb) < 0.25) for c in (0, 1)}; lab = np.array([0, 1] * 6)                    # 12 revealed items, 2 chemotype clusters = the 2 classes
        X = np.stack([np.logical_xor(cent[l], rng.random(nb) < 0.05) for l in lab]).astype(np.float32)
        hi.append(F.reliability_nn(F.tanimoto(X, X), lab, _tie_auc))                                      # informative analogs
        X2 = (rng.random((12, nb)) < 0.25).astype(np.float32); lo.append(F.reliability_nn(F.tanimoto(X2, X2), lab, _tie_auc))   # unrelated random items
    print("reliability_nn informative %.3f vs random %.3f" % (np.mean(hi), np.mean(lo)))
    assert np.mean(hi) > 0.8 and np.mean(lo) < 0.65 and np.mean(hi) > np.mean(lo) + 0.2


def test_reliability_perm_planted():
    rng = np.random.default_rng(1); nb = 256; hi, lo = [], []
    for s in range(40):
        cid = np.repeat(np.arange(4), 3); cent = rng.random((4, nb)) < 0.25; X = np.stack([np.logical_xor(cent[c], rng.random(nb) < 0.05) for c in cid]).astype(np.float32)
        off = rng.normal(size=4)[cid]; hi.append(F.reliability_perm(F.tanimoto(X, X), off * 2 + 0.1 * rng.normal(size=12)))   # labels follow clusters
        lo.append(F.reliability_perm(F.tanimoto(X, X), rng.normal(size=12)))                                                  # labels unrelated to clusters
    print("reliability_perm informative %.3f vs random %.3f" % (np.mean(hi), np.mean(lo)))
    assert np.mean(hi) > np.mean(lo) + 0.15


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            try: fn(); print("PASS", name)
            except AssertionError as e: print("FAIL", name, e)
