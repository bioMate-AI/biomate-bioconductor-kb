"""Parallel/checkpointed loop runner. Run: python3 test_loop_par.py"""
import os, sys, json, tempfile
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_loop as R, run_loop_par as P

def fake(n=400, seed=0):
    rng = np.random.RandomState(seed); X = rng.rand(n, 40).astype(np.float32); y = X[:, 0] * 3 + rng.randn(n) * 0.3
    srcs = rng.choice(["s1", "s2", "s3"], n, p=[.5, .3, .2]); scaf = [f"sc{i % 60}" for i in range(n)]
    return X, y, srcs, scaf

def test_seed_task_is_deterministic_and_bounded():
    X, y, srcs, scaf = fake(); R.N_INIT, R.ROUNDS, R.BATCH, R.ENS = 20, 3, 10, 2
    thr = float(np.quantile(y, .9)); a = P.run_task(("fp", "A", 3), X, y, srcs, scaf, thr); b = P.run_task(("fp", "A", 3), X, y, srcs, scaf, thr)
    assert a == b, (a, b)
    assert all(0 <= a[p] <= 30 for p in ("random", "greedy", "ucb", "oracle")), a
    assert a["oracle"] >= a["greedy"] and a["oracle"] >= a["random"] - 3, a      # oracle is the upper bound (allow tiny random excess)

def test_informative_features_beat_random_and_shift_pool_is_scaffold_disjoint():
    X, y, srcs, scaf = fake(600); R.N_INIT, R.ROUNDS, R.BATCH, R.ENS = 30, 4, 10, 2
    thr = float(np.quantile(y, .9)); g = [P.run_task(("fp", "A", s), X, y, srcs, scaf, thr) for s in range(6)]
    assert np.mean([r["greedy"] for r in g]) > np.mean([r["random"] for r in g]), g
    init, pool = P.setup("B", 1, srcs, scaf, 30)
    assert not ({scaf[i] for i in init} & {scaf[i] for i in pool}) and not (set(init) & set(pool))
    assert {srcs[i] for i in init} <= {"s1", "s2"}                                # the two largest sources

def test_results_are_checkpointed_per_task_and_resumable():
    X, y, srcs, scaf = fake(); R.N_INIT, R.ROUNDS, R.BATCH, R.ENS = 20, 2, 10, 2; d = tempfile.mkdtemp()
    thr = float(np.quantile(y, .9)); tasks = [("fp", "A", 0), ("fp", "A", 1)]
    P.run_all(tasks, X, y, srcs, scaf, thr, d, procs=2)
    assert sorted(os.listdir(d)) == ["fp_A_0.json", "fp_A_1.json"]
    m0 = os.path.getmtime(f"{d}/fp_A_0.json"); P.run_all(tasks, X, y, srcs, scaf, thr, d, procs=2)
    assert os.path.getmtime(f"{d}/fp_A_0.json") == m0                              # finished tasks are skipped on resume

if __name__ == "__main__":
    k = 0
    for n, f in sorted(globals().items()):
        if n.startswith("test_"): f(); k += 1; print("PASS", n)
    print(k, "tests passed")
