"""Step 6: run a split. usage: python3 06_run.py S2 [n_jobs]"""
import sys, os, time, numpy as np, pandas as pd
from joblib import Parallel, delayed
import engine, splits
split = sys.argv[1]; nj = int(sys.argv[2]) if len(sys.argv) > 2 else 6
OUT = os.environ.get("INTEGRIN_OUT", "data/preds"); os.makedirs(OUT, exist_ok=True)
U, Pp, clus, xs, xp = splits.load(); g = engine.G(); T = g["T"]
folds = splits.make_folds(split, U, Pp, clus, xs, xp, g["ci_of"], T)
if len(sys.argv) > 3: folds = folds[:int(sys.argv[3])]
print(split, "folds", len(folds), "train rows (first)", len(folds[0][1]["train"]), "test rows", sum(len(f[1]["test"]) for f in folds), flush=True)
t0 = time.time()
res = Parallel(n_jobs=nj, verbose=5)(delayed(engine.run_fold)(spec) for _, spec in folds)
o1 = []; o2 = []
for (fid, spec), (a, b) in zip(folds, res):
    a = a.copy(); b = b.copy(); a["fold"] = fid; b["fold"] = fid; o1.append(a); o2.append(b)
o1 = pd.concat(o1); o2 = pd.concat(o2)
for df in (o1, o2): df["cluster"] = df.ck.map(clus)
o1.to_csv(f"{OUT}/{split}_t1.csv.gz", index=False); o2.to_csv(f"{OUT}/{split}_t2.csv.gz", index=False)
print("done", split, round(time.time() - t0), "s", o1.shape, o2.shape)
