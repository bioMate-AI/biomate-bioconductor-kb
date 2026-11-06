"""Step 8: learning curve vs number of TRAINING DOCUMENTS (S2 LODO and S3 external), models M1 (ridge, T1/T2-diff) and M5 (pairwise ridge)."""
import json, numpy as np, pandas as pd
from joblib import Parallel, delayed
import engine, splits
from metrics import rmse, boot_metric
U, Pp, clus, xs, xp = splits.load(); g = engine.G(); T = g["T"]
SIZES = [5, 10, 20, 40, 80, 160, 10**6]
def sub(spec, k, seed):
    docs = np.array(sorted(set(spec["train"].doc) | set(spec["train_pairs"].doc))); rng = np.random.RandomState(seed)
    keep = set(rng.permutation(docs)[:k]); s = dict(spec); s["train"] = spec["train"][spec["train"].doc.isin(keep)]; s["train_pairs"] = spec["train_pairs"][spec["train_pairs"].doc.isin(keep)]
    return s, min(k, len(docs))
def job(split, fid, spec, k, seed):
    s, kk = sub(spec, k, seed); a, b = engine.run_fold(s, models=("M1", "M5")); return split, k, kk, seed, a.assign(fold=fid), b.assign(fold=fid)
jobs = []
for fid, spec in splits.make_folds("S2", U, Pp, clus, xs, xp, g["ci_of"], T): jobs += [("S2", fid, spec, k, 0) for k in SIZES]
(fid, spec), = splits.make_folds("S3", U, Pp, clus, xs, xp, g["ci_of"], T); jobs += [("S3", fid, spec, k, sd) for k in SIZES for sd in range(8)]
res = Parallel(n_jobs=7, verbose=2)(delayed(job)(*j) for j in jobs)
out = {}
for split in ["S2", "S3"]:
    for k in SIZES:
        R = [r for r in res if r[0] == split and r[1] == k]
        if not R: continue
        if split == "S2": a = pd.concat([r[4] for r in R]); b = pd.concat([r[5] for r in R]); vals = [(rmse(a.M1, a.y), rmse(a.N1, a.y), rmse(b.M1d, b.delta), rmse(b.M5, b.delta), rmse(b.N1p, b.delta))]
        else: vals = [(rmse(r[4].M1, r[4].y), rmse(r[4].N1, r[4].y), rmse(r[5].M1d, r[5].delta), rmse(r[5].M5, r[5].delta), rmse(r[5].N1p, r[5].delta)) for r in R]
        v = np.mean(vals, 0); out[f"{split}_k{min(k, 999)}"] = dict(n_train_docs_requested=k if k < 10**6 else "all", T1_rmse_M1=v[0], T1_rmse_N1=v[1], T2_rmse_M1diff=v[2], T2_rmse_M5=v[3], T2_rmse_N1pair=v[4], n_reps=len(vals))
json.dump(out, open("learning_curve.json", "w"), indent=1); print(json.dumps(out, indent=1))
