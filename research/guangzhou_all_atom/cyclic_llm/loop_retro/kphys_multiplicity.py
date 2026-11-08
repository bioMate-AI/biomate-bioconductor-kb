#!/usr/bin/env python3
"""L7q K_phys contrasts with multiplicity control (exploratory; owner asked 2026-10-29).
usage: kphys_multiplicity.py OUT.json DIR[,DIR...]   (the res7q_* directories, as passed to aggregate_l7.py --small)
For every (learner, regime) group of the deterministic-K_shuf re-runs (learner key *_detK*), the per-seed paired yield difference (total hits over the rounds, as in the aggregate's `yield_total`)
for two contrasts: PRIMARY K_phys - K_shuf, SECONDARY K_phys - loop. Test: paired sign-flip permutation (exact when n <= 12, else 20000 Monte-Carlo flips, fixed seed) of the mean difference, two-sided.
Holm and Benjamini-Hochberg are applied separately within each contrast family (all groups). Intervals: percentile bootstrap of the mean over seeds (95%). SEEDS ARE NOT INDEPENDENT ACROSS GROUPS (same pool,
same held-out labs in regime L) so the corrections are approximate; this is an exploratory analysis and is labelled as such."""
import sys, json, itertools, zlib
import numpy as np
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import aggregate_l7 as A


def seed_for(v): return zlib.crc32(repr(tuple(round(float(x), 6) for x in v)).encode())


def signflip_p(d, B=20000):
    d = np.asarray(d, float); n = len(d); obs = abs(d.mean())
    if n <= 12:
        signs = np.array(list(itertools.product([1, -1], repeat=n)), float); stat = np.abs((signs * d).mean(1))
    else:
        rng = np.random.default_rng(seed_for(d)); signs = rng.choice([1.0, -1.0], size=(B, n)); stat = np.abs((signs * d).mean(1))
    return float((np.sum(stat >= obs - 1e-12) + (0 if n <= 12 else 1)) / (len(stat) + (0 if n <= 12 else 1)))


def boot_ci(d, B=5000):
    d = np.asarray(d, float); rng = np.random.default_rng(seed_for(d) + 1); bs = [rng.choice(d, len(d)).mean() for _ in range(B)]
    return [round(float(np.percentile(bs, 2.5)), 3), round(float(np.percentile(bs, 97.5)), 3)]


def holm(p):
    m = len(p); o = np.argsort(p); adj = np.empty(m); run = 0.0
    for r, i in enumerate(o): run = max(run, (m - r) * p[i]); adj[i] = min(1.0, run)
    return adj


def bh(p):
    m = len(p); o = np.argsort(p)[::-1]; adj = np.empty(m); run = 1.0
    for r, i in enumerate(o): k = m - r; run = min(run, p[i] * m / k); adj[i] = min(1.0, run)
    return adj


def main(out, dirs):
    R = A.load_small([d for d in dirs.split(",") if d])
    rows = []
    for (lk, reg), seeds in sorted(R.items()):
        if "detK" not in lk: continue
        S = sorted(seeds); y = lambda arm: np.array([A.hits(seeds[s].get(arm)) for s in S], float)
        kp, ks, lp = y("loop_kphys_sub"), y("loop_kshuf_sub"), y("loop_sub")
        for nm, a, b in (("K_phys - K_shuf", kp, ks), ("K_phys - loop", kp, lp)):
            ok = np.isfinite(a) & np.isfinite(b); d = (a - b)[ok]
            if len(d) < 3: continue
            rows.append(dict(learner=lk, regime=reg, contrast=nm, n_seeds=int(len(d)), mean=round(float(d.mean()), 3), ci95_seed_bootstrap=boot_ci(d), p_signflip=signflip_p(d)))
    for nm in ("K_phys - K_shuf", "K_phys - loop"):
        idx = [i for i, r in enumerate(rows) if r["contrast"] == nm]; p = np.array([rows[i]["p_signflip"] for i in idx])
        for i, h, b in zip(idx, holm(p), bh(p)): rows[i]["p_holm"] = round(float(h), 4); rows[i]["p_bh"] = round(float(b), 4)
    json.dump(dict(note=__doc__.split("\n")[0], rows=rows), open(out, "w"), indent=1)
    for r in rows: print(f"{r['contrast']:16s} {r['learner']:24s} {r['regime']} n={r['n_seeds']:2d} mean={r['mean']:+6.2f} ci={r['ci95_seed_bootstrap']} p={r['p_signflip']:.4f} holm={r['p_holm']:.4f} bh={r['p_bh']:.4f}")


if __name__ == "__main__": main(sys.argv[1], sys.argv[2])
