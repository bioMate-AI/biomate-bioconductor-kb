"""Classical models M1-M5. Usage: run_classical.py MODEL [splits comma list] [--sub path_to_pid_subset]
HP selection on the inner validation set only; final refit on train+val. Writes results/preds/<MODEL>.csv"""
import sys, time, json, numpy as np, pandas as pd, itertools
from sklearn.ensemble import RandomForestRegressor, HistGradientBoostingRegressor
from common import *
import cv, features

def design(model, c, Z, extra=None):
    A = Z["assay"]
    if model in ("M1", "M2"): return np.hstack([Z["ecfp"], A])
    if model == "M3": return np.hstack([Z["desc"], A])
    if model == "M4":
        sh = (c["shape"] == "Lariat").values[:, None].astype(np.float32)
        misc = c[["ring_res", "ring_atoms", "n_nme_smiles", "n_nme_helm", "n_dres", "n_heavy"]].values.astype(np.float32)
        return np.hstack([Z["bag"], misc, sh, Z["desc"], A])
    if model == "M5":
        a, b = c.CHCl3_3DPSA.values[:, None].astype(np.float32), c.H2O_3DPSA.values[:, None].astype(np.float32)
        return np.hstack([Z["ecfp"], a, b, b - a, A])
    if model == "C1":
        return np.hstack([Z["ecfp"], Z["desc"], extra, A])
    raise KeyError(model)

def make(model, cfg):
    if model == "M1":
        return RandomForestRegressor(n_estimators=300, max_features=cfg["mf"], min_samples_leaf=cfg["msl"], n_jobs=4, random_state=0)
    return HistGradientBoostingRegressor(learning_rate=0.05, max_iter=600, max_leaf_nodes=cfg["leaf"], early_stopping=True,
                                         n_iter_no_change=25, validation_fraction=0.1, l2_regularization=1.0, random_state=0)

GRID = {"M1": [dict(mf=0.3, msl=1), dict(mf="sqrt", msl=3)],
        "M2": [dict(leaf=15), dict(leaf=31)], "M3": [dict(leaf=15), dict(leaf=31)], "M4": [dict(leaf=15), dict(leaf=31)],
        "M5": [dict(leaf=15), dict(leaf=31)], "C1": [dict(leaf=15), dict(leaf=31)]}

def fit_predict(model, X, y, tr, va, te):
    # drop all-constant columns using the training rows only
    keep = X[tr].std(0) > 0; Xk = X[:, keep]
    best, bsc = None, 1e9
    for cfg in GRID[model]:
        m = make(model, cfg); m.fit(Xk[tr], y[tr]); sc = rmse(y[va], m.predict(Xk[va]))
        if sc < bsc: best, bsc = cfg, sc
    m = make(model, best); trva = np.concatenate([tr, va]); m.fit(Xk[trva], y[trva])
    return m.predict(Xk[te]), best, bsc

def run(model, which, subset=None, tag=None):
    c, _ = cv.load(); Z = features.get(); y = c.y.values.astype(float)
    extra = None
    if model == "C1":
        cf = pd.read_csv(os.path.join(HERE, "data/conf_features.csv")).set_index("pid")
        cols = [k for k in cf.columns if k not in ("nconf", "sec")]
        extra = cf.reindex(c.pid)[cols].values.astype(np.float32)
        subset = set(cf.index)
    X = design(model, c, Z, extra); out = []
    pth = os.path.join(HERE, f"results/preds/{tag or model}.csv"); done = set()
    if os.path.exists(pth):
        prev = pd.read_csv(pth); out.append(prev); done = set(zip(prev.split, prev.fold))
    for s in cv.splits(which):
        if (s["split"], s["fold"]) in done: continue
        if subset is not None:
            m = c.pid.isin(subset).values
            s = {k: (v[m[v]] if k in ("tr", "va", "te") else v) for k, v in s.items()}
        t0 = time.time(); p, cfg, vsc = fit_predict(model, X, y, s["tr"], s["va"], s["te"])
        out.append(pd.DataFrame({"split": s["split"], "fold": s["fold"], "row": s["te"], "pred": p}))
        print(model, s["split"], s["fold"], "test_r2=%.3f" % r2(y[s["te"]], p), cfg, "%.0fs" % (time.time() - t0), flush=True)
        pd.concat(out).to_csv(pth, index=False)

if __name__ == "__main__":
    which = sys.argv[2].split(",") if len(sys.argv) > 2 else ["S0", "S1", "S2", "S3"]
    run(sys.argv[1], which)
