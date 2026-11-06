"""Positive/negative controls for stats helpers and the within-source enrichment pipeline. Run: python3 test_stats.py"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, stats as S

def test_cluster_boot_covers_known_mean():
    rng = np.random.default_rng(0); g = np.repeat(np.arange(200), 5); v = rng.normal(0.4, 1, 1000) + np.repeat(rng.normal(0, 0.5, 200), 5)
    p, lo, hi = S.cluster_boot(lambda i: v[i].mean(), g, B=500); assert lo < 0.4 < hi and lo < p < hi

def test_dl_meta_recovers_planted_effect_with_source_offsets():
    rng = np.random.default_rng(1); E = []; V = []
    for s in range(30):
        off = rng.normal(0, 2); n = 60; f = rng.random(n) < 0.4; z = rng.normal(0, 1, n) + 0.5 * f + off          # source offset must cancel
        e, v = S.smd_within_source(z, f); E.append(e); V.append(v)
    m = S.dl_meta(E, V); assert m["lo"] < 0.5 < m["hi"] and m["lo"] > 0

def test_null_feature_gives_no_discoveries_beyond_fdr():
    rng = np.random.default_rng(2); ps = []
    for t in range(200):
        E = []; V = []
        for s in range(20):
            n = 50; f = rng.random(n) < 0.4; z = rng.normal(0, 1, n); e, v = S.smd_within_source(z, f); E.append(e); V.append(v)
        m = S.dl_meta(E, V); ps.append(S.p_from_ci(m["pooled"], m["se"]))
    adj, sig = S.bh_fdr(ps, 0.10); assert sig.sum() <= 5        # nothing planted: at most a handful of false positives (expected ~0)

def test_fdr_finds_planted_among_nulls():
    rng = np.random.default_rng(3); p = list(rng.random(100)) + [1e-6, 1e-7, 1e-5]; adj, sig = S.bh_fdr(p, 0.10); assert sig[-3:].all() and sig[:100].sum() <= 2

def test_meta_heterogeneity_detected():
    m = S.dl_meta([0.0, 1.0, 2.0, -1.0, 3.0], [0.01] * 5); assert m["I2"] > 0.9 and m["tau2"] > 0.5

if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for f in fns: f(); print("PASS", f.__name__)
    print(len(fns), "tests passed")
