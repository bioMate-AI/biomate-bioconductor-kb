"""Rebuild results/perm_baselines_summary.json from perm_cells.csv (the original file was written by an inline snippet that was never committed as a script).
Validated: run on the ORIGINAL (pre-source-correction) cells it reproduces the committed file exactly (see docs/20261031_T1_T1B_RECOMPUTED_CORRECTED.md).
usage: python3 summarize_baselines.py CELLS.csv OUT.json   (lab-cluster bootstrap of per-lab mean differences, B = 2000, seed 3, 95% percentile)"""
import sys, json, numpy as np, pandas as pd
cells, out = sys.argv[1], sys.argv[2]
df = pd.read_csv(cells); pl = df.groupby(["k", "lab", "arm"]).spearman.mean().reset_index()
ARMS = ["K", "A", "F1_5", "F2_5", "RF_rev", "PT", "PTk"]

def boot(v, B=2000, seed=3):
    v = np.asarray(v, float); rng = np.random.default_rng(seed); idx = rng.integers(0, len(v), (B, len(v))); m = v[idx].mean(1)
    return [round(float(v.mean()), 3), round(float(np.percentile(m, 2.5)), 3), round(float(np.percentile(m, 97.5)), 3)]

res = {}
for k in sorted(pl.k.unique()):
    W = pl[pl.k == k].pivot(index="lab", columns="arm", values="spearman").dropna(subset=ARMS)
    r = {"n_labs": int(len(W)), "strongest_single_arm_on_eval": max(["PT", "PTk", "RF_rev", "A", "K"], key=lambda a: W[a].mean())}
    for f in ("F1_5", "F2_5"):
        for b in ("PTk", "PT", "RF_rev"): r[f"{f}_minus_{b}"] = boot((W[f] - W[b]).values)
    r["means"] = {a: round(float(W[a].mean()), 3) for a in ARMS}
    res[str(int(k))] = r
json.dump(res, open(out, "w"), indent=1); print("wrote", out)
