"""Rebuild results/perm_nested_n0_summary.json from perm_nested_n0_cells.csv (the original was written by an inline snippet never committed as a script).
Validated: on the ORIGINAL (pre-source-correction) nested cells it reproduces the committed summary exactly. usage: python3 summarize_nested.py CELLS.csv OUT.json
Per k: per-lab means over seeds; best component = argmax over {K, A} of the lab-mean (chosen on the evaluation labs, as registered); diff_vs_best = mean over labs of (F_cv - best);
ci95 = percentile lab-cluster bootstrap (B = 2000, seed 3)."""
import sys, json, numpy as np, pandas as pd
c = pd.read_csv(sys.argv[1]); pl = c.groupby(["k", "lab"])[["F1_cv", "F2_cv", "K", "A"]].mean().reset_index()

def boot(v, B=2000, seed=3):
    v = np.asarray(v, float); rng = np.random.default_rng(seed); idx = rng.integers(0, len(v), (B, len(v))); m = v[idx].mean(1)
    return [float(np.percentile(m, 2.5)), float(np.percentile(m, 97.5))]

res = {}
for k in sorted(pl.k.unique()):
    W = pl[pl.k == k]; best = "K" if W.K.mean() >= W.A.mean() else "A"; r = {"n_labs": int(len(W)), "best": best}
    for f in ("F1_cv", "F2_cv"):
        d = (W[f] - W[best]).values; r[f] = {"mean_spearman": float(W[f].mean()), "diff_vs_best": float(d.mean()), "ci95": boot(d)}
    res[str(int(k))] = r
json.dump(res, open(sys.argv[2], "w"), indent=1); print("wrote", sys.argv[2])
