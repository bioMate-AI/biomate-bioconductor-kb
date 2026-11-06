"""Planted-signal controls for T1b (PREREG sec. 6.1). Run: python3 test_fusion_b.py"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fusion_b as B


def world(seed, prior_strength, cluster_strength, n_clusters=20, per=20, nbits=256, noise=0.5):
    rng = np.random.default_rng(seed); n = n_clusters * per; cid = np.repeat(np.arange(n_clusters), per)
    cent = rng.random((n_clusters, nbits)) < 0.25; X = np.logical_xor(cent[cid], rng.random((n, nbits)) < 0.05).astype(np.float32)
    u = rng.normal(size=n); off = rng.normal(size=n_clusters)[cid]; y = prior_strength * u + cluster_strength * off + noise * rng.normal(size=n)
    P = u + 0.7 * rng.normal(size=n) if prior_strength > 0 else rng.normal(size=n)        # learned prior = noisy copy of the latent signal (or pure noise)
    return X, y, P


def run(ps, cs, ks=(5, 10, 25), seeds=20, n0=5.0):
    out = {k: {m: [] for m in ("PT", "A", "PTk", "F1b", "F2b")} for k in ks}
    for s in range(seeds):
        X, y, P = world(s, ps, cs); rng = np.random.default_rng(1000 + s)
        for k in ks:
            rev = rng.choice(len(y), k, replace=False); rest = np.setdiff1d(np.arange(len(y)), rev); sim = B.tanimoto(X[rest], X[rev])
            A = B.analog_perm(sim, y[rev]); r = B.reliability_perm(B.tanimoto(X[rev], X[rev]), y[rev]); sp = B.spearman
            out[k]["PT"].append(sp(P[rest], y[rest])); out[k]["A"].append(sp(A, y[rest])); out[k]["PTk"].append(sp(B.ptk(P[rest], sim, y[rev], P[rev]), y[rest]))
            out[k]["F1b"].append(sp(B.fuse(P[rest], A, k, n0), y[rest])); out[k]["F2b"].append(sp(B.fuse2(P[rest], A, k, r, n0), y[rest]))
    return {k: {m: float(np.nanmean(v)) for m, v in d.items()} for k, d in out.items()}


def show(tag, r): print(tag, {k: {m: round(v, 3) for m, v in d.items()} for k, d in r.items()})


def test_prior_informative_world():
    r = run(1.0, 0.0); show("prior-informative", r)
    for k in r: assert r[k]["F2b"] >= 0.85 * r[k]["PT"], (k, r[k])


def test_analog_informative_world():
    r = run(0.0, 1.5); show("analog-informative", r); assert r[25]["F2b"] >= r[25]["A"] - 0.03, r[25]


def test_both_informative_world():
    r = run(1.0, 1.5); show("both-informative", r)
    for k in r: assert r[k]["F2b"] >= max(r[k]["PT"], r[k]["A"]) - 0.03, (k, r[k])


def test_k0_and_ptk_recovers_residual_cluster():
    P = np.array([3., 1., 2., 5.]); A = np.array([1., 9., 3., 2.]); assert np.array_equal(np.argsort(B.fuse2(P, A, 0, 0.7)), np.argsort(P))
    r = run(1.0, 1.5); assert all(r[k]["PTk"] > r[k]["PT"] for k in r), r      # residual is cluster-structured: analog correction must help


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            try: fn(); print("PASS", name)
            except AssertionError as e: print("FAIL", name, e)
