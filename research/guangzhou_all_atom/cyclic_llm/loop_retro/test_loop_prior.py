"""Knowledge-as-prior arms (PREREG_LOOP L2). Run: OMP_NUM_THREADS=1 python3 test_loop_prior.py"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_loop as R, run_loop_prior as K

def world(n=500, seed=0, informative=True):
    rng = np.random.RandomState(seed); X = rng.rand(n, 30).astype(np.float32); k = rng.randn(n)
    y = (2.0 * k if informative else 0.0 * k) + 0.5 * X[:, 0] + rng.randn(n) * 0.3
    return X, y, k

def setup_small():
    R.N_INIT, R.ROUNDS, R.BATCH, R.ENS = 30, 4, 20, 2

def test_returns_per_round_hits_and_total():
    setup_small(); X, y, k = world(); thr = float(np.quantile(y, .9)); init = list(range(30)); pool = list(range(30, 500))
    for mode in ("resid", "fuse", "fp"):
        tot, per = K.run_prior_policy(mode, X, y, k, init, pool, thr, seed=1)
        assert len(per) == 4 and tot == sum(per) and all(0 <= h <= 20 for h in per), (mode, tot, per)

def test_good_prior_helps_cold_start_and_is_deterministic():
    setup_small(); res = {m: [] for m in ("fp", "resid", "fuse")}
    for s in range(6):
        X, y, k = world(seed=s); thr = float(np.quantile(y, .9)); init = list(range(30)); pool = list(range(30, 500))
        for m in res: res[m].append(K.run_prior_policy(m, X, y, k, init, pool, thr, seed=s)[1][0])   # FIRST round yield
    assert np.mean(res["resid"]) > np.mean(res["fp"]) and np.mean(res["fuse"]) > np.mean(res["fp"]), {m: np.mean(v) for m, v in res.items()}
    X, y, k = world(); thr = float(np.quantile(y, .9)); init = list(range(30)); pool = list(range(30, 500))
    assert K.run_prior_policy("resid", X, y, k, init, pool, thr, 3) == K.run_prior_policy("resid", X, y, k, init, pool, thr, 3)

def test_useless_prior_does_not_collapse_to_chance():
    setup_small(); X, y, k = world(informative=True); thr = float(np.quantile(y, .9)); init = list(range(30)); pool = list(range(30, 500))
    bad = np.random.RandomState(9).randn(len(y))                               # prior unrelated to y
    tot = np.mean([K.run_prior_policy("resid", X, y, bad, init, pool, thr, s)[0] for s in range(4)]); rnd = 4 * 20 * 0.1
    assert tot >= rnd * 0.8, (tot, rnd)                                           # data correction still works

def test_knowledge_scores_are_label_free_and_z_scored():
    import numpy as np
    nme = np.array([0, 1, 2, 3], float); hbd = np.array([4, 3, 2, 1], float); tpsa = np.array([300, 250, 200, 150], float)
    z = K.k_z(nme, hbd, tpsa); assert abs(z.mean()) < 1e-9 and z[3] > z[0]

if __name__ == "__main__":
    k = 0
    for n, f in sorted(globals().items()):
        if n.startswith("test_"): f(); k += 1; print("PASS", n)
    print(k, "tests passed")
