#!/usr/bin/env python3
"""L7m (label-range hypothesis): refit the physchem GBM on the LOOP's revealed rows with importance weights that match the RANDOM arm's label histogram (10 quantile bins of the global label distribution),
and measure how much of the loop-vs-random gap on E source-rho is recovered. All three models use the identical refit recipe (5-member bootstrap ensemble, same rng seed) so they are comparable.
usage: diag_label_range_refit.py CycPeptMPDB.csv OUT.json RESULT_DIR[,...]"""
import os, sys, json, collections
import numpy as np
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import run_loop as R, run_l7a as L, aggregate_l7 as G
from sklearn.ensemble import HistGradientBoostingRegressor

def fit_ens_w(X, y, rng, w=None, n_models=5):
    ms = []; p = None if w is None else (w / w.sum())
    for _ in range(n_models):
        idx = rng.choice(len(y), len(y), p=p) if p is not None else rng.integers(0, len(y), len(y))
        ms.append(HistGradientBoostingRegressor(max_iter=150, learning_rate=0.1, random_state=int(rng.integers(1 << 30))).fit(X[idx], y[idx]))
    return ms

def src_rho(scores, E, y, srcs, min_n=15):
    es = np.asarray([srcs[i] for i in E]); out = []
    for s in sorted(set(es.tolist())):
        m = es == s
        if m.sum() >= min_n: out.append(G._rho(scores[m], y[E][m]) if np.std(scores[m]) > 0 else 0.0)
    return float(np.mean(out)) if out else float("nan")

def main(csv, out, dirs):
    recs, d = L.build(csv, "gbm_physchem", "cpu"); y, srcs, desc = d["y"], d["srcs"], d["desc"]; S = G.load_small(dirs); qs = np.quantile(y, np.linspace(0, 1, 11)[1:-1]); res = {}
    for (be, reg), seeds in sorted(S.items()):
        if be != "gbm_physchem": continue
        rows = collections.defaultdict(list)
        for seed, r in sorted(seeds.items()):
            if "loop" not in r or "random_fb" not in r: continue
            E = np.asarray(r["E"], int); init = list(r["init"]); rev = {a: np.asarray(init + [i for rd in r[a]["picks"] for i in rd], int) for a in ("loop", "random_fb")}
            b_l, b_r = np.digitize(y[rev["loop"]], qs), np.digitize(y[rev["random_fb"]], qs); pl = np.bincount(b_l, minlength=10) / len(b_l); pr = np.bincount(b_r, minlength=10) / len(b_r)
            w = np.clip(pr[b_l] / np.maximum(pl[b_l], 1e-6), 0, 20); sc = {}
            for name, idx, ww in (("loop", rev["loop"], None), ("random_fb", rev["random_fb"], None), ("loop_weighted", rev["loop"], w)):
                ms = fit_ens_w(desc[idx], y[idx], np.random.default_rng(seed * 1000 + 17), ww); sc[name] = src_rho(np.mean([m.predict(desc[E]) for m in ms], 0), E, y, srcs)
            gap = sc["random_fb"] - sc["loop"]; rows["loop"].append(sc["loop"]); rows["random_fb"].append(sc["random_fb"]); rows["loop_weighted"].append(sc["loop_weighted"])
            rows["recovered_fraction"].append((sc["loop_weighted"] - sc["loop"]) / gap if abs(gap) > 0.02 else float("nan")); rows["ess_fraction"].append(float(w.sum() ** 2 / (w ** 2).sum() / len(w)))
        ci = lambda v: G.summ([x for x in v if x == x], 2.5, 97.5)
        res[f"{be}|{reg}"] = {k: ci(v) for k, v in rows.items()}; res[f"{be}|{reg}"]["gap_random_minus_loop_refit"] = ci(np.asarray(rows["random_fb"]) - np.asarray(rows["loop"])); res[f"{be}|{reg}"]["weighted_minus_loop"] = ci(np.asarray(rows["loop_weighted"]) - np.asarray(rows["loop"]))
    json.dump(res, open(out, "w"), indent=1); print("wrote", out); return res

if __name__ == "__main__": main(sys.argv[1], sys.argv[2], [x for x in sys.argv[3].split(",") if x])
